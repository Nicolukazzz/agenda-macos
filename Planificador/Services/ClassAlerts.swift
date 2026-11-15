import AgendaCore
import Foundation
import OSLog
import SwiftData
@preconcurrency import UserNotifications

/// "BD in 10 min · Room 204": a local notification before each class of the timetable.
/// Off until turned on in Settings. Nothing leaves the Mac: macOS delivers them itself, also with Agenda closed.
@MainActor
enum ClassAlerts {
    static let enabledKey = "classAlertsEnabled"
    static let leadKey = "classAlertsLeadMinutes"
    static let defaultLead = 10
    /// How far ahead alerts are scheduled. Opening Agenda once in that time keeps them coming.
    private static let horizonDays = 14

    private static let log = Logger(subsystem: "com.nicolas.agenda", category: "ClassAlerts")
    private static let presenter = Presenter()
    /// What was last handed to macOS, so saves that don't touch the timetable cost nothing.
    private static var scheduled: [String]?

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var leadMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: leadKey)
        return stored > 0 ? stored : defaultLead
    }

    /// Asks macOS to let Agenda notify. False when the user said no.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Brings the pending alerts in line with the timetable and the settings. Safe to call often.
    static func refresh(_ context: ModelContext, semester: Semester) {
        guard !AppEnvironment.isPreview else { return }
        let alerts = isEnabled ? plan(context, semester: semester) : []
        let ids = alerts.map(\.id)
        guard ids != scheduled else { return }
        scheduled = ids

        let center = UNUserNotificationCenter.current()
        center.delegate = presenter
        Task {
            let stale = await center.pendingNotificationRequests().map(\.identifier)
                .filter { $0.hasPrefix(ClassAlertPlanner.idPrefix) && !ids.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for alert in alerts {
                do { try await center.add(request(for: alert)) } catch {
                    log.error("Class alert failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private static func plan(_ context: ModelContext, semester: Semester) -> [ClassAlert] {
        let math = CalendarMath()
        let now = Date.now
        let blocks = ((try? context.fetch(FetchDescriptor<Block>())) ?? [])
            .filter { $0.isClassSchedule && !$0.isAllDay && $0.area?.semester === semester }
        let interval = DateInterval(start: now, end: math.add(days: horizonDays, to: now))
        let classes = CalendarFeed.items(for: blocks, in: interval, breaks: semester.breaks, math: math)
            .map { ClassAlertPlanner.Class(title: $0.block.title, location: $0.block.location, start: $0.start) }
        return ClassAlertPlanner.alerts(for: classes, leadMinutes: leadMinutes, now: now)
    }

    private static func request(for alert: ClassAlert) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        let minutes = Int(alert.start.timeIntervalSince(alert.fireDate) / 60)
        let time = alert.start.agenda(date: .omitted, time: .shortened)
        let when = minutes > 0 ? "In \(minutes) min, at \(time)" : "Starts now, at \(time)"
        content.body = alert.location.isEmpty ? when : "\(when) · \(alert.location)"
        content.sound = .default
        let parts = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alert.fireDate)
        return UNNotificationRequest(
            identifier: alert.id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    /// macOS hides notifications of the app in front; a class alert should show anyway.
    private final class Presenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }
    }
}
