import AgendaCore
import Darwin
import SwiftUI
import WidgetKit

// Money widgets. They read the JSON snapshot Agenda writes next to its database
// (`~/Library/Application Support/com.nicolas.agenda/money-widget.json`) and never write anything:
// buttons open `agenda://money/...` links that the app handles.

struct MoneyEntry: TimelineEntry {
    let date: Date
    let snapshot: MoneySnapshot
}

struct MoneyProvider: TimelineProvider {
    /// The sandbox redirects `~`, so build the real home path for the read-only file exception.
    static var snapshotURL: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(filePath: home).appending(path: "Library/Application Support/com.nicolas.agenda/money-widget.json")
    }

    static func load() -> MoneySnapshot {
        (try? MoneySnapshot.decode(Data(contentsOf: snapshotURL))) ?? .empty
    }

    func placeholder(in context: Context) -> MoneyEntry { MoneyEntry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (MoneyEntry) -> Void) {
        let snapshot = Self.load()
        completion(MoneyEntry(date: .now, snapshot: context.isPreview && snapshot.updatedAt == .distantPast ? .sample : snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoneyEntry>) -> Void) {
        // The app reloads timelines whenever money changes; the midnight refresh rolls "today" over.
        let snapshot = Self.load()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now.addingTimeInterval(86_400)
        // A second entry at midnight zeroes "today" (and the month on the 1st) even if Agenda is closed.
        let entries = [MoneyEntry(date: .now, snapshot: snapshot), MoneyEntry(date: midnight, snapshot: snapshot)]
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
    }
}

extension MoneySnapshot {
    static let sample = MoneySnapshot(
        updatedAt: .now, monthTitle: "noviembre", currency: .cop, spent: 439_500, earned: 3_000_000, spentToday: 21_500,
        slices: [
            .init(name: "Pareja", emoji: "❤️", colorHex: "#E85D9A", amount: 120_000),
            .init(name: "Hogar", emoji: "🏠", colorHex: "#4F7BF7", amount: 95_000),
            .init(name: "Gasolina", emoji: "⛽", colorHex: "#E5534B", amount: 80_000),
            .init(name: "Suscripciones", emoji: "🔁", colorHex: "#8E6CF0", amount: 80_000),
        ],
        shortcuts: [
            .init(title: "Gasolina", emoji: "⛽", amount: 80_000, currency: .cop, kind: .expense, categoryTag: "gasolina"),
            .init(title: "Café", emoji: "🍔", amount: 7_500, currency: .cop, kind: .expense, categoryTag: "comida"),
        ],
        nextCharge: .init(title: "Claude", date: .now.addingTimeInterval(3 * 86_400)))

    /// Months change at midnight even if the app didn't run; an old snapshot shouldn't pose as this month.
    func isCurrent(at date: Date) -> Bool { Calendar.current.isDate(updatedAt, equalTo: date, toGranularity: .month) }
}

extension Color {
    init(widgetHex hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x6B7A90
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

private let newEntryURL = URL(string: "agenda://money/new")!

// MARK: - Summary

struct MoneySummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoneySummary", provider: MoneyProvider()) { entry in
            MoneySummaryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(newEntryURL)
        }
        .configurationDisplayName("Money")
        .description("What you've spent this month, today and where it went.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MoneySummaryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MoneyEntry

    private var snapshot: MoneySnapshot { entry.snapshot }
    private var current: Bool { snapshot.isCurrent(at: entry.date) }
    private var spent: Decimal { current ? snapshot.spent : 0 }
    private var today: Decimal {
        current && Calendar.current.isDate(snapshot.updatedAt, inSameDayAs: entry.date) ? snapshot.spentToday : 0
    }

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemLarge: large
        default: medium
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Spent · \(current ? snapshot.monthTitle : entry.date.formatted(.dateTime.month(.wide)))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(snapshot.currency.format(spent))
                .font(.system(.title, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
    }

    private var todayLine: some View {
        Label("Today \(snapshot.currency.format(today))", systemImage: "cup.and.saucer")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            headline
            Spacer(minLength: 0)
            todayLine
            if current, snapshot.earned > 0 {
                Text("Balance \(snapshot.currency.format(snapshot.balance, signed: true))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(snapshot.balance < 0 ? .red : .green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            small
            categories(limit: 4)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                headline
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    todayLine
                    if current, snapshot.earned > 0 {
                        Text("Balance \(snapshot.currency.format(snapshot.balance, signed: true))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(snapshot.balance < 0 ? .red : .green)
                    }
                }
            }
            categories(limit: 6)
            Spacer(minLength: 0)
            if let next = snapshot.nextCharge, next.date > entry.date {
                // `.relative` text keeps counting down on its own between timeline reloads.
                Label { Text("\(next.title) · \(next.date, style: .relative)") } icon: { Image(systemName: "repeat") }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            ShortcutButtons(shortcuts: Array(snapshot.shortcuts.prefix(3)), compact: true)
        }
    }

    /// Bars scaled to the biggest category.
    @ViewBuilder
    private func categories(limit: Int) -> some View {
        let slices = current ? Array(snapshot.slices.prefix(limit)) : []
        let top = slices.first?.amount ?? 1
        VStack(alignment: .leading, spacing: 6) {
            if slices.isEmpty {
                Text("Nothing logged yet this month.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(slices, id: \.name) { slice in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("\(slice.emoji) \(slice.name)").lineLimit(1)
                        Spacer(minLength: 4)
                        Text(snapshot.currency.format(slice.amount)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    GeometryReader { proxy in
                        Capsule().fill(Color(widgetHex: slice.colorHex).gradient)
                            .frame(width: max(4, proxy.size.width * CGFloat(truncating: (slice.amount / top) as NSNumber)))
                    }
                    .frame(height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Quick log

struct MoneyQuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoneyQuickLog", provider: MoneyProvider()) { entry in
            QuickLogView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Log")
        .description("One click to log what you buy most, or open Agenda to type a new one.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickLogView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MoneyEntry

    var body: some View {
        let limit = family == .systemSmall ? 2 : 4
        VStack(alignment: .leading, spacing: 8) {
            Link(destination: newEntryURL) {
                Label("New expense", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if entry.snapshot.shortcuts.isEmpty {
                Text("Things you log twice or more show up here as one-click buttons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ShortcutButtons(shortcuts: Array(entry.snapshot.shortcuts.prefix(limit)), compact: family == .systemSmall)
            Spacer(minLength: 0)
        }
    }
}

/// Links that log a frequent entry again.
struct ShortcutButtons: View {
    let shortcuts: [MoneySnapshot.Shortcut]
    var compact = false

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: compact ? 1 : 2)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(shortcuts, id: \.url) { shortcut in
                Link(destination: shortcut.url) {
                    HStack(spacing: 4) {
                        Text(shortcut.emoji)
                        Text(shortcut.title).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(shortcut.currency.format(shortcut.amount)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.fill.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

#Preview("Summary", as: .systemMedium) {
    MoneySummaryWidget()
} timeline: {
    MoneyEntry(date: .now, snapshot: .sample)
}

#Preview("Large", as: .systemLarge) {
    MoneySummaryWidget()
} timeline: {
    MoneyEntry(date: .now, snapshot: .sample)
}

#Preview("Quick Log", as: .systemMedium) {
    MoneyQuickLogWidget()
} timeline: {
    MoneyEntry(date: .now, snapshot: .sample)
}
