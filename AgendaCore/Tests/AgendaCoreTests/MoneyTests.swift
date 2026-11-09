import Foundation
import Testing
@testable import AgendaCore

private let bogota: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Bogota")!
    return calendar
}()

private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
    bogota.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

/// "Now" is Sunday 2026-11-08 at 10:00.
private let parser = MoneyQuickAddParser(math: CalendarMath(calendar: bogota), now: day(2026, 11, 8, 10))
private let tags: Set<String> = ["belleza", "gasolina", "sueldo", "suscripciones"]

struct MoneyParserTests {
    @Test func thousandsSuffixAndTag() {
        #expect(parser.parse("Peluquería 25k #belleza", knownTags: tags)
            == MoneyQuickAddResult(title: "Peluquería", amount: 25_000, tag: "belleza"))
    }

    @Test func dottedThousandsAndYesterday() {
        #expect(parser.parse("gasolina 80.000 ayer", knownTags: tags)
            == MoneyQuickAddResult(title: "gasolina", amount: 80_000, date: day(2026, 11, 7)))
    }

    @Test func dollarsInManyForms() {
        let expected = MoneyQuickAddResult(title: "Claude", amount: 20, currency: .usd)
        #expect(parser.parse("Claude 20 usd", knownTags: tags) == expected)
        #expect(parser.parse("Claude 20usd", knownTags: tags) == expected)
        #expect(parser.parse("Claude us$20", knownTags: tags) == expected)
        #expect(parser.parse("Claude 20 dólares", knownTags: tags) == expected)
        #expect(parser.parse("Claude $20 USD", knownTags: tags) == expected)
    }

    @Test func decimals() {
        #expect(parser.parse("Netflix 3.99 usd", knownTags: tags).amount == Decimal(string: "3.99"))
        #expect(parser.parse("Café 4,50 usd", knownTags: tags).amount == Decimal(string: "4.5"))
        #expect(parser.parse("Arriendo 1.234,56", knownTags: tags).amount == Decimal(string: "1234.56"))
    }

    @Test func millionsAndIncome() {
        let r = parser.parse("+1,5m sueldo #sueldo", knownTags: tags)
        #expect(r == MoneyQuickAddResult(title: "sueldo", amount: 1_500_000, isIncome: true, tag: "sueldo"))
        #expect(parser.parse("+ Freelance 2.000.000", knownTags: tags).isIncome)
        #expect(parser.parse("Regalo 25 mil", knownTags: tags).amount == 25_000)
    }

    @Test func picksMarkedOrBiggestNumber() {
        #expect(parser.parse("2 cervezas 12000", knownTags: tags) == MoneyQuickAddResult(title: "2 cervezas", amount: 12_000))
        #expect(parser.parse("3 cafés 9k", knownTags: tags).amount == 9_000)
    }

    @Test func pastDays() {
        #expect(parser.parse("Cine 30k viernes", knownTags: tags).date == day(2026, 11, 6))
        #expect(parser.parse("Cine 30k domingo", knownTags: tags).date == day(2026, 11, 8))
        #expect(parser.parse("Cine 30k antier", knownTags: tags).date == day(2026, 11, 6))
        #expect(parser.parse("Cine 30k 5/11", knownTags: tags).date == day(2026, 11, 5))
        // A day still ahead this year means last year's.
        #expect(parser.parse("Cine 30k 20/12", knownTags: tags).date == day(2025, 12, 20))
    }

    @Test func unknownTagAndNoAmountStayInTitle() {
        #expect(parser.parse("Almuerzo #comida", knownTags: tags) == MoneyQuickAddResult(title: "Almuerzo #comida"))
    }
}

struct MoneyMathTests {
    @Test func convertsBothWays() {
        #expect(Money.convert(20, from: .usd, to: .cop, copPerUSD: 4_000) == 80_000)
        #expect(Money.convert(80_000, from: .cop, to: .usd, copPerUSD: 4_000) == 20)
        #expect(Money.convert(5, from: .usd, to: .usd, copPerUSD: 4_000) == 5)
    }

    @Test func totalsUseEachEntrysOwnRate() {
        let values = [
            MoneyValue(kind: .income, amount: 2_000_000, currency: .cop, copPerUSD: 4_000),
            MoneyValue(kind: .expense, amount: 20, currency: .usd, copPerUSD: 4_000), // 80.000
            MoneyValue(kind: .expense, amount: 20, currency: .usd, copPerUSD: 4_200), // 84.000
            MoneyValue(kind: .expense, amount: 336_000, currency: .cop, copPerUSD: 4_200),
        ]
        let totals = MoneyTotals(values, in: .cop)
        #expect(totals.income == 2_000_000)
        #expect(totals.expense == 500_000)
        #expect(totals.net == 1_500_000)
        #expect(totals.savingsRate == Decimal(string: "0.75"))
        #expect(MoneyTotals([], in: .cop).savingsRate == nil)
    }

    @Test func roundsPerCurrency() {
        #expect(Money.rounded(Decimal(string: "19047.619")!, for: .cop) == 19_048)
        #expect(Money.rounded(Decimal(string: "4.761")!, for: .usd) == Decimal(string: "4.76"))
    }
}

struct RecurringTests {
    @Test func monthlyKeepsTheDayAcrossShortMonths() {
        let schedule = RecurringSchedule(start: day(2026, 1, 31), cadence: .monthly)
        let dates = schedule.due(after: nil, through: day(2026, 4, 30), calendar: bogota)
        #expect(dates == [day(2026, 1, 31), day(2026, 2, 28), day(2026, 3, 31), day(2026, 4, 30)])
    }

    @Test func onlyChargesAfterTheLastOne() {
        let schedule = RecurringSchedule(start: day(2026, 9, 5), cadence: .monthly)
        #expect(schedule.due(after: day(2026, 10, 5), through: day(2026, 11, 8, 10), calendar: bogota) == [day(2026, 11, 5)])
        #expect(schedule.due(after: day(2026, 11, 5), through: day(2026, 11, 8, 10), calendar: bogota).isEmpty)
    }

    @Test func futureStartChargesNothingYet() {
        let schedule = RecurringSchedule(start: day(2026, 11, 20), cadence: .monthly)
        #expect(schedule.due(after: nil, through: day(2026, 11, 8), calendar: bogota).isEmpty)
        #expect(schedule.next(after: day(2026, 11, 8), calendar: bogota) == day(2026, 11, 20))
    }

    @Test func weeklyAndYearly() {
        let weekly = RecurringSchedule(start: day(2026, 11, 1), cadence: .weekly)
        #expect(weekly.due(after: nil, through: day(2026, 11, 15), calendar: bogota).count == 3)
        let yearly = RecurringSchedule(start: day(2024, 2, 29), cadence: .yearly)
        #expect(yearly.next(after: day(2026, 11, 8), calendar: bogota) == day(2027, 2, 28))
    }

    @Test func endOfDayCountsTheWholeDay() {
        let schedule = RecurringSchedule(start: day(2026, 11, 8, 9), cadence: .monthly)
        let cutoff = RecurringSchedule.endOfDay(day(2026, 11, 8, 0), calendar: bogota)
        #expect(schedule.due(after: nil, through: cutoff, calendar: bogota) == [day(2026, 11, 8, 9)])
        #expect(bogota.isDate(cutoff, inSameDayAs: day(2026, 11, 8)))
    }

    @Test func catchUpIsCapped() {
        let schedule = RecurringSchedule(start: day(1990, 1, 1), cadence: .weekly)
        #expect(schedule.due(after: nil, through: day(2026, 11, 8), calendar: bogota, limit: 50).count == 50)
    }
}

struct MoneySnapshotTests {
    @Test func shortcutURLRoundTrips() {
        let shortcut = MoneySnapshot.Shortcut(title: "Gasolina & café", emoji: "⛽", amount: Decimal(string: "80000.5")!, currency: .cop, kind: .expense, categoryTag: "gasolina")
        let back = MoneySnapshot.Shortcut(url: shortcut.url)
        #expect(back?.title == shortcut.title)
        #expect(back?.amount == shortcut.amount)
        #expect(back?.categoryTag == "gasolina")
        #expect(MoneySnapshot.Shortcut(url: URL(string: "agenda://money/add?title=x&amount=-5&currency=COP&kind=expense")!) == nil)
        #expect(MoneySnapshot.Shortcut(url: URL(string: "https://example.com/add")!) == nil)
    }

    @Test func frequentNeedsTwoAndSortsByCount() {
        func s(_ title: String, _ amount: Decimal) -> MoneySnapshot.Shortcut {
            .init(title: title, emoji: "", amount: amount, currency: .cop, kind: .expense, categoryTag: nil)
        }
        let picked = MoneyShortcuts.frequent([s("Café", 7500), s("Gasolina", 80000), s("cafe", 7500), s("Gasolina", 80000), s("Gasolina", 80000), s("Cine", 30000)])
        #expect(picked.map(\.title) == ["Gasolina", "Café"])
    }

    @Test func snapshotRoundTrips() throws {
        let snapshot = MoneySnapshot(updatedAt: day(2026, 11, 8), monthTitle: "noviembre", currency: .cop, spent: 439_500, earned: 3_000_000, spentToday: 21_500,
                                     slices: [.init(name: "Pareja", emoji: "❤️", colorHex: "#E85D9A", amount: 120_000)], shortcuts: [], nextCharge: .init(title: "Claude", date: day(2026, 12, 5)))
        #expect(try MoneySnapshot.decode(snapshot.encoded()) == snapshot)
    }
}

struct RecurringDetectorTests {
    private func item(_ title: String, _ date: Date, _ amount: Decimal = 25_000) -> RecurringDetector.Item {
        .init(title: title, date: date, amount: amount, currency: .cop, kind: .expense, categoryTag: "belleza")
    }
    private let now = day(2026, 11, 8, 10)

    @Test func everyTwoMonths() {
        let items = [item("Peluquería", day(2026, 5, 3)), item("peluqueria", day(2026, 7, 4)), item("Peluquería", day(2026, 9, 2), 28_000)]
        let found = RecurringDetector.suggestions(from: items, excluding: [], now: now, calendar: bogota)
        #expect(found.count == 1)
        #expect(found.first?.cadence == .monthly)
        #expect(found.first?.every == 2)
        #expect(found.first?.amount == 28_000)
        #expect(found.first?.next == day(2026, 11, 2))
    }

    @Test func weeklyAndBiweekly() {
        let weekly = (0..<4).map { item("Fútbol", day(2026, 10, 11 + 7 * $0)) }
        #expect(RecurringDetector.suggestions(from: weekly, excluding: [], now: now, calendar: bogota).first?.cadence == .weekly)
        let biweekly = (0..<3).map { item("Lavandería", day(2026, 9, 27 + 14 * $0)) }
        let found = RecurringDetector.suggestions(from: biweekly, excluding: [], now: now, calendar: bogota).first
        #expect(found?.cadence == .weekly)
        #expect(found?.every == 2)
    }

    @Test func irregularStaleDismissedOrTooFewAreSkipped() {
        let irregular = [item("Cine", day(2026, 8, 1)), item("Cine", day(2026, 8, 9)), item("Cine", day(2026, 10, 20))]
        #expect(RecurringDetector.suggestions(from: irregular, excluding: [], now: now, calendar: bogota).isEmpty)
        let stale = [item("Gym", day(2026, 1, 5)), item("Gym", day(2026, 2, 5)), item("Gym", day(2026, 3, 5))]
        #expect(RecurringDetector.suggestions(from: stale, excluding: [], now: now, calendar: bogota).isEmpty)
        let monthly = [item("Gym", day(2026, 8, 5)), item("Gym", day(2026, 9, 5)), item("Gym", day(2026, 10, 5))]
        #expect(RecurringDetector.suggestions(from: monthly, excluding: ["gym"], now: now, calendar: bogota).isEmpty)
        #expect(RecurringDetector.suggestions(from: Array(monthly.prefix(2)), excluding: [], now: now, calendar: bogota).isEmpty)
    }

    @Test func sameDayRepeatsCountOnce() {
        let items = [item("Café", day(2026, 11, 2, 8)), item("Café", day(2026, 11, 2, 15)), item("Café", day(2026, 11, 3)), item("Café", day(2026, 11, 4))]
        #expect(RecurringDetector.suggestions(from: items, excluding: [], now: now, calendar: bogota).isEmpty)
    }

    @Test func everyTwoMonthsSchedule() {
        let schedule = RecurringSchedule(start: day(2026, 1, 15), cadence: .monthly, every: 2)
        #expect(schedule.due(after: nil, through: day(2026, 6, 1), calendar: bogota) == [day(2026, 1, 15), day(2026, 3, 15), day(2026, 5, 15)])
        #expect(schedule.perMonth == Decimal(1) / 2)
    }
}
