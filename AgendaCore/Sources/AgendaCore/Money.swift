import Foundation

/// The two currencies the user pays in. Raw values are ISO 4217 codes.
public enum Currency: String, Codable, CaseIterable, Sendable {
    case cop = "COP"
    case usd = "USD"

    /// Pesos are shown and rounded without cents.
    public var fractionDigits: Int { self == .cop ? 0 : 2 }

    /// Under $ 1.000 pesos is almost always a dollar price typed with the wrong currency ("Railway 5").
    public static func looksLikeDollars(_ amount: Decimal, in currency: Currency) -> Bool {
        currency == .cop && amount > 0 && amount < 1_000
    }
}

public enum MoneyKind: String, Codable, CaseIterable, Sendable {
    case expense
    case income
}

/// One income or expense, reduced to what the math needs.
/// `copPerUSD` is the rate when it was entered, so old months never change when the rate does.
public struct MoneyValue: Equatable, Sendable {
    public var kind: MoneyKind
    public var amount: Decimal
    public var currency: Currency
    public var copPerUSD: Decimal

    public init(kind: MoneyKind, amount: Decimal, currency: Currency, copPerUSD: Decimal) {
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.copPerUSD = copPerUSD
    }

    public func amount(in target: Currency) -> Decimal {
        Money.convert(amount, from: currency, to: target, copPerUSD: copPerUSD)
    }
}

public enum Money {
    public static func convert(_ amount: Decimal, from: Currency, to: Currency, copPerUSD: Decimal) -> Decimal {
        guard from != to, copPerUSD > 0 else { return amount }
        return from == .usd ? amount * copPerUSD : amount / copPerUSD
    }

    public static func rounded(_ amount: Decimal, for currency: Currency) -> Decimal {
        var value = amount
        var result = Decimal()
        NSDecimalRound(&result, &value, currency.fractionDigits, .plain)
        return result
    }
}

/// Income against expenses for any set of entries, in one display currency.
public struct MoneyTotals: Equatable, Sendable {
    public var income: Decimal
    public var expense: Decimal
    public var net: Decimal { income - expense }

    /// Share of income left after expenses (0.25 = saved a quarter). Nil without income.
    public var savingsRate: Decimal? { income > 0 ? net / income : nil }

    public init(income: Decimal = 0, expense: Decimal = 0) {
        self.income = income
        self.expense = expense
    }

    public init(_ values: [MoneyValue], in currency: Currency) {
        self.init()
        for value in values {
            switch value.kind {
            case .income: income += value.amount(in: currency)
            case .expense: expense += value.amount(in: currency)
            }
        }
    }
}

/// Result of a money quick-add line such as `Peluquería 25k #belleza ayer`.
public struct MoneyQuickAddResult: Equatable, Sendable {
    public var title: String
    public var amount: Decimal?
    /// Nil when the line names no currency; the caller uses its default.
    public var currency: Currency?
    /// True for a leading `+` (`+3.5M sueldo`). The category's kind can also make it income.
    public var isIncome: Bool
    public var tag: String?
    /// Start of the day; nil means today.
    public var date: Date?

    public init(title: String, amount: Decimal? = nil, currency: Currency? = nil, isIncome: Bool = false, tag: String? = nil, date: Date? = nil) {
        self.title = title
        self.amount = amount
        self.currency = currency
        self.isIncome = isIncome
        self.tag = tag
        self.date = date
    }
}

/// Reads amounts (`25k`, `80.000`, `1,5m`, `$20 usd`, `+3.5M`), `#category` and past days
/// (`ayer`, `anteayer`, `lunes`, `5/11`). Anything else stays in the title.
public struct MoneyQuickAddParser: Sendable {
    public let math: CalendarMath
    public let now: Date

    public init(math: CalendarMath = CalendarMath(), now: Date = .now) {
        self.math = math
        self.now = now
    }

    private static let currencyWords: [String: Currency] = [
        "usd": .usd, "dolar": .usd, "dolares": .usd, "dollar": .usd, "dollars": .usd,
        "cop": .cop, "peso": .cop, "pesos": .cop,
    ]
    private static let multiplierWords: [String: Decimal] = ["k": 1_000, "mil": 1_000, "m": 1_000_000, "millon": 1_000_000, "millones": 1_000_000]
    private static let weekdays: [String: Int] = [
        "domingo": 1, "lunes": 2, "martes": 3, "miercoles": 4, "jueves": 5, "viernes": 6, "sabado": 7,
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
    ]

    private struct Amount {
        var value: Decimal
        var currency: Currency?
        var isIncome: Bool
        var marked: Bool // had a currency sign, suffix or multiplier: surely the amount
        var length: Int
    }

    public func parse(_ text: String, knownTags: Set<String>) -> MoneyQuickAddResult {
        var original = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var leadingPlus = false
        if original.first == "+" {
            leadingPlus = true
            original.removeFirst()
        }
        let words = original.map { TagSuggester.normalize($0) }
        var used = Set<Int>()
        var result = MoneyQuickAddResult(title: "")

        for (index, word) in original.enumerated() where word.hasPrefix("#") && word.count > 1 {
            let tag = TagSuggester.normalize(String(word.dropFirst()))
            if knownTags.contains(tag), result.tag == nil {
                result.tag = tag
                used.insert(index)
            }
        }

        // The marked number wins; otherwise the biggest one ("2 cervezas 12000" costs 12000).
        var best: (index: Int, amount: Amount)?
        for index in original.indices where !used.contains(index) {
            guard let found = amount(at: index, original, words) else { continue }
            if let current = best?.amount, current.marked && !found.marked { continue }
            if let current = best?.amount, current.marked == found.marked, current.value >= found.value { continue }
            best = (index, found)
        }
        if let best {
            result.amount = best.amount.value
            result.isIncome = best.amount.isIncome
            result.currency = best.amount.currency
            used.formUnion(best.index..<(best.index + best.amount.length))
        }
        result.isIncome = result.isIncome || leadingPlus

        // A lone currency word anywhere ("Claude 20 dolares").
        if result.currency == nil {
            for index in words.indices where !used.contains(index) {
                if let currency = Self.currencyWords[words[index]], result.amount != nil {
                    result.currency = currency
                    used.insert(index)
                    break
                }
            }
        }

        for index in words.indices where !used.contains(index) && result.date == nil {
            if let found = pastDay(words[index], raw: original[index]) {
                result.date = found.day
                used.formUnion(index..<(index + found.length))
            }
        }

        result.title = original.enumerated().filter { !used.contains($0.offset) }.map(\.element).joined(separator: " ")
        return result
    }

    // MARK: - Amount

    private func amount(at index: Int, _ original: [String], _ words: [String]) -> Amount? {
        let raw = original[index].lowercased()
        guard !raw.contains("/"), !raw.contains(":"),
              let match = raw.wholeMatch(of: /([+-]?)(us\$|\$)?(\d[\d.,]*)(k|mil|m|usd|cop)?(usd|cop)?/)
        else { return nil }
        guard var value = Self.number(String(match.3)), value > 0 else { return nil }

        var currency: Currency? = match.2 == "us$" ? .usd : nil
        var marked = match.2 != nil
        var length = 1
        for suffix in [match.4, match.5].compactMap({ $0.map(String.init) }) {
            if let multiplier = Self.multiplierWords[suffix] { value *= multiplier }
            if let named = Self.currencyWords[suffix] { currency = named }
            marked = true
        }
        // Separate words: "25 mil", "1,5 millones", "20 usd".
        if match.4 == nil, index + length < words.count, let multiplier = Self.multiplierWords[words[index + length]] {
            value *= multiplier
            marked = true
            length += 1
        }
        if currency == nil, index + length < words.count, let named = Self.currencyWords[words[index + length]] {
            currency = named
            marked = true
            length += 1
        }
        if match.2 == "$", currency == nil { marked = true }
        return Amount(value: value, currency: currency, isIncome: match.1 == "+", marked: marked, length: length)
    }

    /// `80.000` and `1,500` are thousands; `3.5` and `20,99` are decimals; `1.234,56` mixes both.
    static func number(_ text: String) -> Decimal? {
        let separators = text.filter { $0 == "." || $0 == "," }
        var plain = text
        if let last = text.lastIndex(where: { $0 == "." || $0 == "," }) {
            let decimals = text[text.index(after: last)...]
            let isThousands = Set(separators).count == 1 && (separators.count > 1 || decimals.count == 3)
            let integer = text[..<last].filter(\.isNumber)
            plain = isThousands ? text.filter(\.isNumber) : "\(integer).\(decimals)"
        }
        guard plain.wholeMatch(of: /\d+(\.\d+)?/) != nil else { return nil }
        return Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: - Date (money is logged after the fact, so days point back)

    private func pastDay(_ word: String, raw: String) -> (day: Date, length: Int)? {
        let today = math.startOfDay(now)
        switch word {
        case "hoy", "today": return (today, 1)
        case "ayer", "yesterday": return (math.add(days: -1, to: today), 1)
        case "anteayer", "antier": return (math.add(days: -2, to: today), 1)
        default: break
        }
        if let weekday = Self.weekdays[word] {
            let current = math.calendar.component(.weekday, from: today)
            return (math.add(days: -((current - weekday + 7) % 7), to: today), 1)
        }
        // 5/11 or 5/11/2026, day first. Without a year, a future date means last year.
        let parts = raw.split(separator: "/").map { Int($0) }
        if (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) {
            let day = parts[0]!, month = parts[1]!
            let year = parts.count == 3 ? (parts[2]! < 100 ? 2000 + parts[2]! : parts[2]!) : math.calendar.component(.year, from: now)
            guard var date = math.calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  math.calendar.component(.day, from: date) == day else { return nil }
            if parts.count == 2, date > today, let previous = math.calendar.date(byAdding: .year, value: -1, to: date) { date = previous }
            return (date, 1)
        }
        return nil
    }
}

extension Currency {
    /// `$ 80.000` or `US$ 20,00`, Colombian style for both.
    public func format(_ amount: Decimal, signed: Bool = false) -> String {
        var style = Decimal.FormatStyle.Currency(code: rawValue, locale: Locale(identifier: "es_CO"))
            .precision(.fractionLength(fractionDigits))
        let value = Money.rounded(amount, for: self)
        // "+$ 0" reads like a gain; zero never gets a sign.
        if signed, value != 0 { style = style.sign(strategy: .always()) }
        return value.formatted(style)
    }
}

// MARK: - Recurring money

public enum Cadence: String, Codable, CaseIterable, Sendable {
    case weekly, monthly, yearly

    /// How many times it happens in an average month, to show a fixed monthly cost.
    public var perMonth: Decimal {
        switch self {
        case .weekly: Decimal(52) / 12
        case .monthly: 1
        case .yearly: Decimal(1) / 12
        }
    }
}

/// When a subscription (or a salary) is charged. Each date is counted from `start`, not from the
/// previous charge, so a plan started on the 31st is charged on the 28th in February and the 31st again in March.
public struct RecurringSchedule: Equatable, Sendable {
    public var start: Date
    public var cadence: Cadence
    /// Every `every` weeks / months / years (2 = every other month).
    public var every: Int

    public init(start: Date, cadence: Cadence, every: Int = 1) {
        self.start = start
        self.cadence = cadence
        self.every = max(1, every)
    }

    /// Average charges per month, for a fixed monthly cost.
    public var perMonth: Decimal { cadence.perMonth / Decimal(every) }

    public func occurrence(_ index: Int, calendar: Calendar) -> Date? {
        let step = index * every
        switch cadence {
        case .weekly: return calendar.date(byAdding: .day, value: 7 * step, to: start)
        case .monthly: return calendar.date(byAdding: .month, value: step, to: start)
        case .yearly: return calendar.date(byAdding: .year, value: step, to: start)
        }
    }

    /// Last moment of `date`'s day. Charges count by day: one due at 9:00 is logged from midnight on.
    public static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return (calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)).addingTimeInterval(-1)
    }

    /// Charges after `last` (exclusive; nil = from `start`) up to `now` (inclusive), oldest first.
    /// `limit` stops runaway catch-up if a start date is typed decades in the past.
    public func due(after last: Date?, through now: Date, calendar: Calendar, limit: Int = 400) -> [Date] {
        var dates: [Date] = []
        var index = 0
        while dates.count < limit, let date = occurrence(index, calendar: calendar), date <= now {
            if last.map({ date > $0 }) ?? true { dates.append(date) }
            index += 1
        }
        return dates
    }

    /// First charge strictly after `date`.
    public func next(after date: Date, calendar: Calendar) -> Date? {
        var index = 0
        while let candidate = occurrence(index, calendar: calendar) {
            if candidate > date { return candidate }
            index += 1
            if index > 5000 { return nil }
        }
        return nil
    }
}

// MARK: - Widget snapshot

/// What the widgets and the menu bar show, written by the app as JSON whenever money changes.
public struct MoneySnapshot: Codable, Equatable, Sendable {
    public struct Slice: Codable, Equatable, Sendable {
        public var name: String
        public var emoji: String
        public var colorHex: String
        public var amount: Decimal
        public init(name: String, emoji: String, colorHex: String, amount: Decimal) {
            self.name = name; self.emoji = emoji; self.colorHex = colorHex; self.amount = amount
        }
    }

    /// A one-tap repeat of something logged often ("⛽ Gasolina $ 80.000").
    public struct Shortcut: Codable, Equatable, Sendable {
        public var title: String
        public var emoji: String
        public var amount: Decimal
        public var currency: Currency
        public var kind: MoneyKind
        public var categoryTag: String?
        public init(title: String, emoji: String, amount: Decimal, currency: Currency, kind: MoneyKind, categoryTag: String?) {
            self.title = title; self.emoji = emoji; self.amount = amount; self.currency = currency; self.kind = kind; self.categoryTag = categoryTag
        }

        /// `agenda://money/add?...`, opened by a widget button.
        public var url: URL {
            var components = URLComponents()
            components.scheme = "agenda"
            components.host = "money"
            components.path = "/add"
            components.queryItems = [
                .init(name: "title", value: title), .init(name: "amount", value: "\(amount)"),
                .init(name: "currency", value: currency.rawValue), .init(name: "kind", value: kind.rawValue),
            ] + (categoryTag.map { [.init(name: "tag", value: $0)] } ?? [])
            return components.url!
        }

        public init?(url: URL) {
            guard url.scheme == "agenda", url.host() == "money", url.path() == "/add",
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            guard let title = value("title"),
                  let amount = value("amount").flatMap({ Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }), amount > 0,
                  let currency = value("currency").flatMap(Currency.init(rawValue:)),
                  let kind = value("kind").flatMap(MoneyKind.init(rawValue:))
            else { return nil }
            self.init(title: title, emoji: "", amount: amount, currency: currency, kind: kind, categoryTag: value("tag"))
        }
    }

    public var updatedAt: Date
    public var monthTitle: String
    public var currency: Currency
    public var spent: Decimal
    public var earned: Decimal
    public var spentToday: Decimal
    /// Expenses by category, biggest first.
    public var slices: [Slice]
    public var shortcuts: [Shortcut]
    /// Next recurring charge, e.g. "Claude · mañana".
    public var nextCharge: NextCharge?

    /// Stored as a date so the widget can count down live ("in 2 hours", "tomorrow").
    public struct NextCharge: Codable, Equatable, Sendable {
        public var title: String
        public var date: Date
        public init(title: String, date: Date) { self.title = title; self.date = date }
    }

    public var balance: Decimal { earned - spent }

    public init(updatedAt: Date, monthTitle: String, currency: Currency, spent: Decimal, earned: Decimal, spentToday: Decimal,
                slices: [Slice], shortcuts: [Shortcut], nextCharge: NextCharge?) {
        self.updatedAt = updatedAt; self.monthTitle = monthTitle; self.currency = currency; self.spent = spent; self.earned = earned
        self.spentToday = spentToday; self.slices = slices; self.shortcuts = shortcuts; self.nextCharge = nextCharge
    }

    public static let empty = MoneySnapshot(updatedAt: .distantPast, monthTitle: "", currency: .cop, spent: 0, earned: 0, spentToday: 0, slices: [], shortcuts: [], nextCharge: nil)

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> MoneySnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MoneySnapshot.self, from: data)
    }
}

/// Picks the entries worth a one-tap button: same title, amount and currency logged at least twice, most frequent first.
public enum MoneyShortcuts {
    public static func frequent(_ candidates: [MoneySnapshot.Shortcut], limit: Int = 4) -> [MoneySnapshot.Shortcut] {
        struct Key: Hashable { let title: String; let amount: Decimal; let currency: Currency; let kind: MoneyKind }
        var counts: [Key: (count: Int, order: Int, item: MoneySnapshot.Shortcut)] = [:]
        for (order, item) in candidates.enumerated() {
            let key = Key(title: TagSuggester.normalize(item.title), amount: item.amount, currency: item.currency, kind: item.kind)
            if let existing = counts[key] { counts[key] = (existing.count + 1, existing.order, existing.item) }
            else { counts[key] = (1, order, item) }
        }
        return counts.values.filter { $0.count >= 2 }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.order < $1.order }
            .prefix(limit).map(\.item)
    }
}

// MARK: - Spotting habits

/// "You've logged Peluquería about every 2 months — make it recurring?"
public struct RecurringSuggestion: Equatable, Sendable {
    /// Normalized title, the key used to dismiss a suggestion.
    public var key: String
    public var title: String
    public var cadence: Cadence
    public var every: Int
    /// Most recent amount and currency.
    public var amount: Decimal
    public var currency: Currency
    public var kind: MoneyKind
    public var categoryTag: String?
    public var occurrences: Int
    /// Next expected date, used as the schedule start.
    public var next: Date

    public init(key: String, title: String, cadence: Cadence, every: Int, amount: Decimal, currency: Currency, kind: MoneyKind,
                categoryTag: String?, occurrences: Int, next: Date) {
        self.key = key; self.title = title; self.cadence = cadence; self.every = every; self.amount = amount; self.currency = currency
        self.kind = kind; self.categoryTag = categoryTag; self.occurrences = occurrences; self.next = next
    }
}

public enum RecurringDetector {
    public struct Item: Sendable {
        public var title: String
        public var date: Date
        public var amount: Decimal
        public var currency: Currency
        public var kind: MoneyKind
        public var categoryTag: String?
        public init(title: String, date: Date, amount: Decimal, currency: Currency, kind: MoneyKind, categoryTag: String?) {
            self.title = title; self.date = date; self.amount = amount; self.currency = currency; self.kind = kind; self.categoryTag = categoryTag
        }
    }

    /// Entries with the same title, logged at least 3 times on different days, at steady gaps
    /// (each gap within 25% of the typical one) that match weeks, months or a year. Stale habits
    /// (last one more than two gaps ago) and `excluded` titles are skipped. Most frequent first.
    public static func suggestions(from items: [Item], excluding excluded: Set<String>, now: Date, calendar: Calendar) -> [RecurringSuggestion] {
        let groups = Dictionary(grouping: items) { TagSuggester.normalize($0.title) }
        var found: [RecurringSuggestion] = []
        for (key, group) in groups where !key.isEmpty && !excluded.contains(key) {
            // One per day: two coffees on Monday are not a pattern.
            var seen = Set<Date>()
            let sorted = group.sorted { $0.date < $1.date }.filter { seen.insert(calendar.startOfDay(for: $0.date)).inserted }
            guard sorted.count >= 3, let last = sorted.last else { continue }
            let gaps = zip(sorted, sorted.dropFirst()).map {
                Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.date), to: calendar.startOfDay(for: $1.date)).day ?? 0)
            }
            let typical = gaps.sorted()[gaps.count / 2]
            guard typical >= 5, gaps.allSatisfy({ abs($0 - typical) <= max(2, typical * 0.25) }),
                  let (cadence, every) = cadence(forDays: typical) else { continue }
            let sinceLast = Double(calendar.dateComponents([.day], from: last.date, to: now).day ?? 0)
            guard sinceLast <= typical * 2 else { continue }
            let schedule = RecurringSchedule(start: last.date, cadence: cadence, every: every)
            guard let next = schedule.next(after: last.date, calendar: calendar) else { continue }
            found.append(RecurringSuggestion(key: key, title: last.title, cadence: cadence, every: every, amount: last.amount, currency: last.currency,
                                             kind: last.kind, categoryTag: last.categoryTag, occurrences: sorted.count, next: next))
        }
        return found.sorted { $0.occurrences != $1.occurrences ? $0.occurrences > $1.occurrences : $0.title < $1.title }
    }

    /// 7 → weekly, 14 → every 2 weeks, 30 → monthly, 61 → every 2 months, 365 → yearly.
    static func cadence(forDays days: Double) -> (Cadence, Int)? {
        for weeks in 1...3 where abs(days - Double(7 * weeks)) <= Double(weeks) + 1 { return (.weekly, weeks) }
        for months in 1...6 where abs(days - 30.44 * Double(months)) <= 4 * Double(months) { return (.monthly, months) }
        if abs(days - 365) <= 20 { return (.yearly, 1) }
        return nil
    }
}
