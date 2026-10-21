import Foundation

/// Result of parsing a quick-add line such as `Lab report #so friday 6pm !`.
public struct QuickAddResult: Equatable, Sendable {
    public var title: String
    public var tag: String?
    /// Start of the due day, or the exact due moment when `hasTime` is true.
    public var dueDate: Date?
    public var hasTime: Bool
    /// 0 normal, 1 high (`!`), 2 urgent (`!!`).
    public var priority: Int

    public init(title: String, tag: String? = nil, dueDate: Date? = nil, hasTime: Bool = false, priority: Int = 0) {
        self.title = title
        self.tag = tag
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.priority = priority
    }
}

/// Understands dates, times, `#tags` and `!` priority in English and Spanish.
/// Anything it doesn't recognize stays in the title, so no text is ever lost.
public struct QuickAddParser: Sendable {
    public let math: CalendarMath
    public let now: Date

    public init(math: CalendarMath = CalendarMath(), now: Date = .now) {
        self.math = math
        self.now = now
    }

    private static let weekdays: [String: Int] = [
        "sunday": 1, "sun": 1, "domingo": 1, "dom": 1,
        "monday": 2, "mon": 2, "lunes": 2, "lun": 2,
        "tuesday": 3, "tue": 3, "tues": 3, "martes": 3, "mar": 3,
        "wednesday": 4, "wed": 4, "miercoles": 4, "mie": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5, "jueves": 5, "jue": 5,
        "friday": 6, "fri": 6, "viernes": 6, "vie": 6,
        "saturday": 7, "sat": 7, "sabado": 7, "sab": 7,
    ]

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "ene": 1, "enero": 1,
        "feb": 2, "february": 2, "febrero": 2,
        "mar": 3, "march": 3, "marzo": 3,
        "apr": 4, "april": 4, "abr": 4, "abril": 4,
        "may": 5, "mayo": 5,
        "jun": 6, "june": 6, "junio": 6,
        "jul": 7, "july": 7, "julio": 7,
        "aug": 8, "august": 8, "ago": 8, "agosto": 8,
        "sep": 9, "sept": 9, "september": 9, "septiembre": 9, "setiembre": 9,
        "oct": 10, "october": 10, "octubre": 10,
        "nov": 11, "november": 11, "noviembre": 11,
        "dec": 12, "december": 12, "dic": 12, "diciembre": 12,
    ]

    /// Filler words that only make sense next to a date/time ("due friday", "a las 3pm").
    private static let connectors: Set<String> = ["due", "on", "at", "by", "el", "a", "las", "la", "para", "hasta"]

    public func parse(_ text: String, knownTags: Set<String>) -> QuickAddResult {
        let original = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let words = original.map { TagSuggester.normalize($0) }
        var used = Set<Int>()
        var result = QuickAddResult(title: "")

        // #tag
        for (index, word) in original.enumerated() where word.hasPrefix("#") && word.count > 1 {
            let tag = TagSuggester.normalize(String(word.dropFirst()))
            if knownTags.contains(tag), result.tag == nil {
                result.tag = tag
                used.insert(index)
            }
        }

        // ! priority (standalone `!`/`!!`, or trailing on a word)
        for (index, word) in original.enumerated() where !used.contains(index) && word.allSatisfy({ $0 == "!" }) {
            result.priority = max(result.priority, min(word.count, 2))
            used.insert(index)
        }

        var day: Date?
        var minutes: Int?

        var index = 0
        while index < words.count {
            defer { index += 1 }
            guard !used.contains(index) else { continue }
            let word = words[index]
            let next = index + 1 < words.count ? words[index + 1] : nil

            let third = index + 2 < words.count ? words[index + 2] : nil
            if day == nil, let found = relativeDay(word, next: next, third: third) {
                day = found.day
                used.formUnion(index..<(index + found.length))
                continue
            }
            if day == nil, let found = explicitDate(word, next: next, raw: original[index]) {
                day = found.day
                used.formUnion(index..<(index + found.length))
                continue
            }
            if minutes == nil, let found = time(word, raw: original[index], next: next) {
                minutes = found.minutes
                used.formUnion(index..<(index + found.length))
                continue
            }
        }

        // Drop connectors right before a recognized date/time word ("due friday", "a las 3pm").
        for i in original.indices where !used.contains(i) && Self.connectors.contains(words[i]) {
            var j = i + 1
            while j < original.count, !used.contains(j), Self.connectors.contains(words[j]) { j += 1 }
            if j < original.count, used.contains(j), (day != nil || minutes != nil) {
                used.formUnion(i..<j)
            }
        }

        if let minutes {
            let base = day ?? (minutes > math.minutesIntoDay(now) ? math.startOfDay(now) : math.add(days: 1, to: math.startOfDay(now)))
            result.dueDate = math.date(base, atMinutes: minutes)
            result.hasTime = true
        } else if let day {
            result.dueDate = math.startOfDay(day)
        }

        result.title = original.enumerated().filter { !used.contains($0.offset) }.map(\.element).joined(separator: " ")
        return result
    }

    // MARK: - Pieces

    private func relativeDay(_ word: String, next: String?, third: String?) -> (day: Date, length: Int)? {
        let today = math.startOfDay(now)
        switch word {
        case "today", "hoy": return (today, 1)
        case "tomorrow", "tmr", "manana": return (math.add(days: 1, to: today), 1)
        case "pasado" where next == "manana": return (math.add(days: 2, to: today), 2)
        default: break
        }
        // "in 3 days" / "en 3 dias" / "in 2 weeks"
        if word == "in" || word == "en", let next, let count = Int(next), let third {
            if ["day", "days", "dia", "dias"].contains(third) { return (math.add(days: count, to: today), 3) }
            if ["week", "weeks", "semana", "semanas"].contains(third) { return (math.add(days: 7 * count, to: today), 3) }
        }
        // weekday, "next friday", "proximo viernes", "otro viernes"
        if let weekday = Self.weekdays[word] {
            return (upcoming(weekday, skipWeek: false), 1)
        }
        if ["next", "proximo", "proxima", "otro"].contains(word), let next, let weekday = Self.weekdays[next] {
            return (upcoming(weekday, skipWeek: true), 2)
        }
        return nil
    }

    /// This week's occurrence (today counts); `skipWeek` jumps to the following week.
    private func upcoming(_ weekday: Int, skipWeek: Bool) -> Date {
        let today = math.startOfDay(now)
        let current = math.calendar.component(.weekday, from: today)
        var offset = (weekday - current + 7) % 7
        if skipWeek { offset += 7 }
        return math.add(days: offset, to: today)
    }

    private func explicitDate(_ word: String, next: String?, raw: String) -> (day: Date, length: Int)? {
        // 21/11 or 21/11/2026 (day first, as in Colombia)
        let slashParts = raw.split(separator: "/").map { Int($0) }
        if slashParts.count >= 2, slashParts.count <= 3, slashParts.allSatisfy({ $0 != nil }) {
            let d = slashParts[0]!, m = slashParts[1]!
            let y = slashParts.count == 3 ? normalizeYear(slashParts[2]!) : nil
            if let date = makeDate(day: d, month: m, year: y) { return (date, 1) }
            return nil
        }
        // 21 nov / nov 21
        if let d = Int(word), let next, let m = Self.months[next], let date = makeDate(day: d, month: m, year: nil) {
            return (date, 2)
        }
        if let m = Self.months[word], word.count >= 3, let next, let d = Int(next), let date = makeDate(day: d, month: m, year: nil) {
            return (date, 2)
        }
        return nil
    }

    private func normalizeYear(_ year: Int) -> Int { year < 100 ? 2000 + year : year }

    /// Without a year, a date already past this year means next year.
    private func makeDate(day: Int, month: Int, year: Int?) -> Date? {
        let currentYear = math.calendar.component(.year, from: now)
        var components = DateComponents(year: year ?? currentYear, month: month, day: day)
        guard let date = math.calendar.date(from: components),
              math.calendar.component(.day, from: date) == day,
              math.calendar.component(.month, from: date) == month
        else { return nil }
        if year == nil, date < math.startOfDay(now) {
            components.year = currentYear + 1
            return math.calendar.date(from: components)
        }
        return date
    }

    private func time(_ word: String, raw: String, next: String?) -> (minutes: Int, length: Int)? {
        let lower = raw.lowercased()
        // 6pm, 6:30pm, 18:00, 6 pm
        if let match = lower.wholeMatch(of: /(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?/) {
            let hour = Int(match.1)!
            let minute = match.2.flatMap { Int($0) } ?? 0
            var meridiem = match.3.map { String($0).replacingOccurrences(of: ".", with: "") }
            var length = 1
            if meridiem == nil, let next, ["am", "pm"].contains(next) {
                meridiem = next
                length = 2
            }
            // A bare number without ":" or am/pm is not a time ("Lab 3").
            guard match.2 != nil || meridiem != nil, minute < 60 else { return nil }
            var h = hour
            if let meridiem {
                guard (1...12).contains(hour) else { return nil }
                if meridiem == "pm", hour != 12 { h += 12 }
                if meridiem == "am", hour == 12 { h = 0 }
            }
            guard (0..<24).contains(h) else { return nil }
            return (h * 60 + minute, length)
        }
        if word == "noon" || word == "mediodia" { return (12 * 60, 1) }
        return nil
    }
}
