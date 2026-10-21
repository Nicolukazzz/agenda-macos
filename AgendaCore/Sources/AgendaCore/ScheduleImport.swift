import Foundation

/// A semester timetable to import: one entry per course and room.
/// Weekdays follow `Calendar`: 1 = Sunday, 2 = Monday … 7 = Saturday.
public struct ScheduleImportFile: Codable, Sendable, Equatable {
    public struct Slot: Codable, Sendable, Equatable {
        public var tag: String
        public var weekdays: [Int]
        public var start: String
        public var end: String
        public var room: String?

        public init(tag: String, weekdays: [Int], start: String, end: String, room: String? = nil) {
            self.tag = tag
            self.weekdays = weekdays
            self.start = start
            self.end = end
            self.room = room
        }
    }

    public var semester: String
    public var slots: [Slot]

    public init(semester: String, slots: [Slot]) {
        self.semester = semester
        self.slots = slots
    }

    /// `"07:00"` → 420. Nil for malformed or out-of-range times.
    public static func minutes(from text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }

    /// Problems that would make the import wrong; empty when the file is usable.
    public func problems(knownTags: Set<String>) -> [String] {
        var problems: [String] = []
        for slot in slots {
            if !knownTags.contains(slot.tag) { problems.append("Unknown course #\(slot.tag)") }
            if slot.weekdays.isEmpty || !slot.weekdays.allSatisfy((1...7).contains) { problems.append("Bad weekdays for #\(slot.tag)") }
            guard let start = Self.minutes(from: slot.start), let end = Self.minutes(from: slot.end), end > start else {
                problems.append("Bad time range for #\(slot.tag)")
                continue
            }
        }
        return problems
    }
}
