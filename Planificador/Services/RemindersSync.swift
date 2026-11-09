import AgendaCore
import AppKit
import Combine
import EventKit
import Foundation
import Observation
import OSLog
import SwiftData

/// Keeps tasks marked "Create reminder" in step with Apple Reminders, which iCloud syncs to the iPhone.
///
/// - Tasks with the option on get a reminder in the "Reminders" list; edits flow both ways
///   (three-way merge against the last synced state, the app wins a tie).
/// - Turning the option off, or deleting the task, removes the reminder.
/// - Deleting the reminder on the iPhone deletes the task.
/// - Open reminders created anywhere else (iPhone, Mac Reminders) are pulled in as new tasks.
///
/// Runs only while the app is open: on launch, on every save, when Reminders changes and when the app
/// comes to the front.
@Observable
final class RemindersSync {
    enum Access { case notDetermined, granted, denied }

    private(set) var access: Access = RemindersSync.currentAccess()
    private(set) var lastSync: Date?
    private(set) var lastError: String?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var needsAnotherPass = false

    private static let log = Logger(subsystem: "com.nicolas.agenda", category: "Reminders")
    private static let linkedKey = "reminders.linkedIDs"
    private static let removedKey = "reminders.removedIDs"
    private static let listNames = ["reminders", "recordatorios"]

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Notifications that may mean something changed on either side.
    static var triggers: some Publisher<Notification, Never> {
        Publishers.Merge3(
            NotificationCenter.default.publisher(for: .EKEventStoreChanged),
            NotificationCenter.default.publisher(for: ModelContext.didSave),
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        )
        .receive(on: DispatchQueue.main)
    }

    func attach(_ context: ModelContext) {
        guard !AppEnvironment.isPreview else { return }
        self.context = context
        access = Self.currentAccess()
        schedule(delay: .zero)
    }

    /// Asks macOS for access the first time "Create reminder" is turned on.
    func requestAccess() async {
        guard access == .notDetermined else { return }
        do {
            _ = try await store.requestFullAccessToReminders()
        } catch {
            Self.log.error("Reminders access request failed: \(error.localizedDescription, privacy: .public)")
        }
        access = Self.currentAccess()
        if access == .granted {
            store.reset()
            schedule(delay: .zero)
        }
    }

    /// Coalesces bursts (typing, autosave, our own writes) into one pass.
    func schedule(delay: Duration = .milliseconds(700)) {
        guard context != nil else { return }
        access = Self.currentAccess()
        guard access == .granted else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await run()
        }
    }

    private func run() async {
        if isRunning {
            needsAnotherPass = true
            return
        }
        isRunning = true
        defer { isRunning = false }
        repeat {
            needsAnotherPass = false
            await syncOnce()
        } while needsAnotherPass
    }

    // MARK: Pass

    private func syncOnce() async {
        guard let context, access == .granted else { return }
        guard let openIDs = await openReminderIDs() else { return }
        guard let tasks = try? context.fetch(FetchDescriptor<TaskItem>()) else { return }

        let defaults = UserDefaults.standard
        let previouslyLinked = Set(defaults.stringArray(forKey: Self.linkedKey) ?? [])
        var removed = RemovedReminders(defaults.stringArray(forKey: Self.removedKey) ?? [])
        var deletedOnPhone: [TaskItem] = []
        var storeChanged = false

        // Our own pulls must not land on the ⌘Z stack.
        let undo = context.undoManager
        undo?.disableUndoRegistration()
        defer { undo?.enableUndoRegistration() }

        do {
            for task in tasks {
                if !task.createsReminder {
                    // Option turned off: the reminder goes away.
                    if let id = task.reminderID {
                        if let reminder = reminder(for: task) {
                            try store.remove(reminder, commit: false)
                            storeChanged = true
                        }
                        removed.insert(id)
                        task.clearReminderLink()
                    }
                    continue
                }

                guard let id = task.reminderID else {
                    try create(for: task)
                    continue
                }

                if let reminder = reminder(for: task) {
                    if try merge(task, with: reminder) { storeChanged = true }
                } else if removed.contains(id) {
                    // The app removed it (e.g. the task came back with ⌘Z): make a fresh one.
                    task.clearReminderLink()
                    needsAnotherPass = true
                } else if let listID = task.reminderListID, store.calendar(withIdentifier: listID) != nil {
                    deletedOnPhone.append(task)
                }
                // Otherwise its list isn't available right now (iCloud signed out?): leave it alone.
            }

            let linkedCount = tasks.count { $0.reminderID != nil }
            if !ReminderDeletionGuard.allows(deleting: deletedOnPhone.count, ofLinked: linkedCount) {
                Self.log.error("Skipped deleting \(deletedOnPhone.count) tasks: too many reminders missing at once")
                deletedOnPhone = []
            }
            let phoneDeletedIDs = Set(deletedOnPhone.compactMap(\.reminderID))
            let deleted = Set(deletedOnPhone.map(ObjectIdentifier.init))
            for task in deletedOnPhone { context.delete(task) }
            let live = tasks.filter { !deleted.contains(ObjectIdentifier($0)) }

            // Tasks deleted in the app: remove their reminders.
            let liveIDs = Set(live.compactMap(\.reminderID))
            for id in previouslyLinked.subtracting(liveIDs).subtracting(phoneDeletedIDs) {
                if let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
                    try store.remove(reminder, commit: false)
                    storeChanged = true
                }
                removed.insert(id)
            }

            // Open reminders made elsewhere become tasks.
            for id in openIDs where !liveIDs.contains(id) && !previouslyLinked.contains(id) && !removed.contains(id) {
                guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { continue }
                let fields = fields(of: reminder)
                let task = TaskItem(title: fields.title.isEmpty ? "Reminder" : fields.title)
                apply(fields, to: task)
                task.createsReminder = true
                link(task, to: reminder, fields: fields)
                context.insert(task)
            }

            if storeChanged { try store.commit() }
            if context.hasChanges { try context.save() }

            let linkedNow = (try? context.fetch(FetchDescriptor<TaskItem>()))?.compactMap(\.reminderID) ?? Array(liveIDs)
            defaults.set(linkedNow, forKey: Self.linkedKey)
            defaults.set(removed.ids, forKey: Self.removedKey)
            lastSync = .now
            lastError = nil
        } catch {
            store.reset()
            lastError = error.localizedDescription
            Self.log.error("Reminders sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: EventKit

    /// Identifiers of every open reminder, in every list. Nil when the fetch fails.
    private func openReminderIDs() async -> [String]? {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders?.map(\.calendarItemIdentifier))
            }
        }
    }

    private func reminder(for task: TaskItem) -> EKReminder? {
        if let id = task.reminderID, let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
            return reminder
        }
        // iCloud can re-identify items after a full sync; the external id survives it.
        guard let external = task.reminderExternalID else { return nil }
        let reminder = store.calendarItems(withExternalIdentifier: external).compactMap { $0 as? EKReminder }.first
        if let reminder { task.reminderID = reminder.calendarItemIdentifier }
        return reminder
    }

    /// The "Reminders" list (Spanish systems name it "Recordatorios"), else the default list.
    private func targetList() -> EKCalendar? {
        let lists = store.calendars(for: .reminder).filter(\.allowsContentModifications)
        return lists.first { Self.listNames.contains($0.title.lowercased()) } ?? store.defaultCalendarForNewReminders()
    }

    private func create(for task: TaskItem) throws {
        guard let list = targetList() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        let fields = fields(of: task)
        apply(fields, to: reminder, dueChanged: true)
        // Committed right away so the identifiers are final before they're stored.
        try store.save(reminder, commit: true)
        link(task, to: reminder, fields: fields)
    }

    /// Returns true when the reminder was changed (needs a commit).
    private func merge(_ task: TaskItem, with reminder: EKReminder) throws -> Bool {
        let remote = fields(of: reminder)
        let result = ReminderMerge.merge(app: fields(of: task), remote: remote, base: task.reminderFieldsSnapshot)
        if result.updatesApp { apply(result.fields, to: task) }
        var changed = false
        if result.updatesRemote {
            apply(result.fields, to: reminder, dueChanged: result.fields.due != remote.due)
            try store.save(reminder, commit: false)
            changed = true
        }
        if task.reminderFieldsSnapshot != result.fields { task.reminderFieldsSnapshot = result.fields }
        if task.reminderListID != reminder.calendar?.calendarIdentifier { task.reminderListID = reminder.calendar?.calendarIdentifier }
        if task.reminderExternalID != reminder.calendarItemExternalIdentifier { task.reminderExternalID = reminder.calendarItemExternalIdentifier }
        return changed
    }

    private func link(_ task: TaskItem, to reminder: EKReminder, fields: ReminderFields) {
        task.reminderID = reminder.calendarItemIdentifier
        task.reminderExternalID = reminder.calendarItemExternalIdentifier
        task.reminderListID = reminder.calendar?.calendarIdentifier
        task.reminderFieldsSnapshot = fields
    }

    // MARK: Field mapping

    private func fields(of task: TaskItem) -> ReminderFields {
        ReminderFields(
            title: task.title, notes: task.notes,
            due: task.dueDate.map { ReminderDue(date: $0, hasTime: task.dueHasTime) },
            isDone: task.isDone, priority: task.priority)
    }

    private func fields(of reminder: EKReminder) -> ReminderFields {
        ReminderFields(
            title: reminder.title ?? "", notes: reminder.notes ?? "",
            due: reminder.dueDateComponents.flatMap(ReminderDue.init(components:)),
            isDone: reminder.isCompleted,
            priority: ReminderPriority.app(fromEventKit: reminder.priority))
    }

    private func apply(_ fields: ReminderFields, to task: TaskItem) {
        if task.title != fields.title, !fields.title.isEmpty { task.title = fields.title }
        if task.notes != fields.notes { task.notes = fields.notes }
        let date = fields.due?.appDate()
        if task.dueDate != date { task.dueDate = date }
        let hasTime = fields.due?.hasTime ?? false
        if task.dueHasTime != hasTime { task.dueHasTime = hasTime }
        if task.priority != fields.priority { task.priority = fields.priority }
        if task.isDone != fields.isDone {
            task.isDone = fields.isDone
            task.completedAt = fields.isDone ? .now : nil
        }
    }

    private func apply(_ fields: ReminderFields, to reminder: EKReminder, dueChanged: Bool) {
        reminder.title = fields.title
        reminder.notes = fields.notes.isEmpty ? nil : fields.notes
        reminder.priority = ReminderPriority.eventKit(fromApp: fields.priority)
        reminder.isCompleted = fields.isDone
        guard dueChanged else { return }
        // Alarms are only touched with the date, so ones set on the iPhone survive other edits.
        if let due = fields.due {
            var components = due.components
            components.calendar = .current
            if due.hasTime { components.timeZone = .current }
            reminder.dueDateComponents = components
            if due.hasTime, let date = due.appDate() {
                reminder.alarms = [EKAlarm(absoluteDate: date)]
            } else {
                reminder.alarms = nil
            }
        } else {
            reminder.dueDateComponents = nil
            reminder.alarms = nil
        }
    }
}
