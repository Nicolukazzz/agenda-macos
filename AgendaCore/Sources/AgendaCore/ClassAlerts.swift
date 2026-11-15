import Foundation

/// A notification to deliver shortly before a class starts.
public struct ClassAlert: Equatable, Sendable {
    /// Stable for the same class, time and lead, so an unchanged plan is not scheduled twice.
    public var id: String
    public var fireDate: Date
    public var title: String
    public var location: String
    public var start: Date
}

/// Decides which class alerts to schedule. Pure, so it can be tested without the notification center.
public enum ClassAlertPlanner {
    /// Every alert id starts with this, to tell them apart from any other notification of the app.
    public static let idPrefix = "class|"
    /// macOS keeps at most 64 pending notifications per app; the soonest ones win.
    public static let limit = 60

    public struct Class: Equatable, Sendable {
        public var title: String
        public var location: String
        public var start: Date
        public init(title: String, location: String, start: Date) {
            self.title = title; self.location = location; self.start = start
        }
    }

    /// One alert per class, `leadMinutes` before it starts. Alerts whose moment already passed are left out.
    public static func alerts(for classes: [Class], leadMinutes: Int, now: Date) -> [ClassAlert] {
        let lead = TimeInterval(max(0, leadMinutes) * 60)
        return classes
            .map { item in
                ClassAlert(
                    id: "\(idPrefix)\(Int(item.start.timeIntervalSince1970))|\(leadMinutes)|\(item.title)|\(item.location)",
                    fireDate: item.start.addingTimeInterval(-lead), title: item.title, location: item.location, start: item.start)
            }
            .filter { $0.fireDate > now }
            .sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
            .prefix(limit)
            .map { $0 }
    }
}
