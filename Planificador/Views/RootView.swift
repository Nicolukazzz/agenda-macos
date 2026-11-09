import AgendaCore
import AppKit
import Combine
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Semester> { $0.isActive }) private var activeSemesters: [Semester]

    var body: some View {
        if let semester = activeSemesters.first {
            MainSplitView(semester: semester)
                .task(id: semester.persistentModelID) {
                    semester.normalizeDates()
                    ScheduleImporter.importPending(into: semester, context: context)
                    BackupService.runDailyBackup(context, classesRoot: appState.classesRootURL)
                }
                .modifier(CommandHandler(semester: semester))
        } else {
            SetupWizardView()
        }
    }
}

extension EnvironmentValues {
    /// The current time, ticking every minute. Views that show "now" read it to stay live.
    @Entry var now: Date = .now
}

struct MainSplitView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    let semester: Semester

    @State private var now = Date.now

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView(semester: semester)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            detail
        }
        .id(appState.today)
        .environment(\.now, now)
        .task { await tick() }
        .onReceive(Self.dayChanges) { _ in
            now = .now
            appState.refreshDay()
        }
        // ⌘Z / ⌘⇧Z undo calendar and task changes.
        .onAppear { context.undoManager = undoManager }
        .onChange(of: undoManager) { context.undoManager = undoManager }
    }

    /// Wakes on each minute boundary; the day check also catches midnight.
    private func tick() async {
        while !Task.isCancelled {
            let next = Calendar.autoupdatingCurrent.nextDate(after: .now, matching: DateComponents(second: 0), matchingPolicy: .nextTime)
            try? await Task.sleep(for: .seconds(max(1, next?.timeIntervalSinceNow ?? 60)))
            now = .now
            appState.refreshDay()
        }
    }

    /// Midnight, waking from sleep, or coming back to the app may all mean a new day.
    private static var dayChanges: some Publisher<Notification, Never> {
        Publishers.Merge3(
            NotificationCenter.default.publisher(for: .NSCalendarDayChanged),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        )
        .receive(on: DispatchQueue.main)
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.selection {
        case .today:
            TodayView(semester: semester)
        case .calendar, .none:
            CalendarView(semester: semester)
        case .tasks:
            TasksPage(semester: semester)
        case .area(let id):
            if let area = context.model(for: id) as? Area, area.semester != nil {
                CourseView(area: area)
                    .id(id)
            } else {
                EmptyState(title: "Course", systemImage: "questionmark.folder", message: "This course no longer exists.")
            }
        }
    }
}

/// Performs menu commands that need the model context: new task, backups.
private struct CommandHandler: ViewModifier {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    let semester: Semester

    @State private var showingNewTask = false
    @State private var pendingImport: URL?
    @State private var message: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: appState.pendingCommand) { handle() }
            .sheet(isPresented: $showingNewTask) {
                SheetScaffold(eyebrow: "New Task") {
                    QuickAddBar(areas: semester.sortedAreas, focusOnAppear: true) { showingNewTask = false }
                    Text("Type a title, then `#course`, a day and a time — e.g. “Lab report #so friday 6pm !”.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                } footer: {
                    ActionBar(primaryTitle: "Done") { showingNewTask = false }
                }
                .frame(width: 600)
            }
            .confirmationDialog(
                "Replace everything with this backup?",
                isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })
            ) {
                Button("Replace with Backup", role: .destructive) { importBackup() }
            } message: {
                Text("Your current semesters, events and tasks will be replaced by “\(pendingImport?.lastPathComponent ?? "")”. A backup of the current data is saved first. Notes are files and aren’t affected.")
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            }
    }

    private func handle() {
        guard let command = appState.pendingCommand else { return }
        switch command {
        case .newTask:
            appState.pendingCommand = nil
            showingNewTask = true
        case .newEvent, .calendarPrevious, .calendarNext, .calendarToday:
            // CalendarView picks these up.
            appState.selection = .calendar
        case .backUpNow:
            appState.pendingCommand = nil
            let folder = BackupService.folder(classesRoot: appState.classesRootURL)
            let url = folder.appending(path: BackupRotation.fileName(for: .now))
            do {
                try BackupService.export(context, to: url)
                message = "Backup saved to \(url.path(percentEncoded: false))"
            } catch {
                message = "Backup failed: \(error.localizedDescription)"
            }
        case .exportBackup:
            appState.pendingCommand = nil
            let panel = NSSavePanel()
            panel.nameFieldStringValue = BackupRotation.fileName(for: .now)
            panel.allowedContentTypes = [.json]
            panel.directoryURL = BackupService.folder(classesRoot: appState.classesRootURL)
            if panel.runModal() == .OK, let url = panel.url {
                do { try BackupService.export(context, to: url) } catch { message = "Export failed: \(error.localizedDescription)" }
            }
        case .importBackup:
            appState.pendingCommand = nil
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.directoryURL = BackupService.folder(classesRoot: appState.classesRootURL)
            if panel.runModal() == .OK { pendingImport = panel.url }
        }
    }

    private func importBackup() {
        guard let url = pendingImport else { return }
        pendingImport = nil
        do {
            let backup = try AgendaBackup.decode(Data(contentsOf: url))
            // Safety copy of the current data before replacing it.
            let folder = BackupService.folder(classesRoot: appState.classesRootURL)
            let stamp = Int(Date.now.timeIntervalSince1970)
            try BackupService.export(context, to: folder.appending(path: "before-import-\(stamp).json"))
            try BackupService.restore(backup, into: context)
            appState.selection = .calendar
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }
}
