import AgendaCore
import SwiftUI
import WidgetKit

// Today widget: what's on now or next, and what's due. It reads the JSON snapshot Agenda writes next to
// its database (`today-widget.json`) and never writes anything. The snapshot holds a week, and the
// timeline has an entry for every moment something changes, so it stays right with Agenda closed.

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot
}

struct TodayProvider: TimelineProvider {
    static var snapshotURL: URL {
        MoneyProvider.snapshotURL.deletingLastPathComponent().appending(path: "today-widget.json")
    }

    static func load() -> TodaySnapshot {
        (try? TodaySnapshot.decode(Data(contentsOf: snapshotURL))) ?? .empty
    }

    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let snapshot = Self.load()
        completion(TodayEntry(date: .now, snapshot: context.isPreview && snapshot.updatedAt == .distantPast ? .sample : snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        // The app reloads this timeline whenever the calendar or the tasks change.
        let snapshot = Self.load()
        let now = Date.now
        let moments = [now] + snapshot.refreshDates(after: now)
        completion(Timeline(entries: moments.map { TodayEntry(date: $0, snapshot: snapshot) }, policy: .atEnd))
    }
}

extension TodaySnapshot {
    static var sample: TodaySnapshot {
        let now = Date.now
        return TodaySnapshot(
            updatedAt: now,
            events: [
                .init(title: "Bases de Datos", location: "Ed. 67 – 204", colorHex: "#4F7BF7", start: now.addingTimeInterval(40 * 60), end: now.addingTimeInterval(160 * 60), isClass: true),
                .init(title: "Sistemas Operativos", location: "Ed. 54 – 301", colorHex: "#E5534B", start: now.addingTimeInterval(240 * 60), end: now.addingTimeInterval(360 * 60), isClass: true),
            ],
            tasks: [
                .init(title: "Taller 3", colorHex: "#4F7BF7", due: now.addingTimeInterval(-3600), hasTime: true),
                .init(title: "Lab report", colorHex: "#E5534B", due: now.addingTimeInterval(5 * 3600), hasTime: true),
                .init(title: "Leer capítulo 4", colorHex: "#6B7A90", due: now.addingTimeInterval(8 * 3600), hasTime: false),
            ])
    }

    /// Older than the days it holds: nothing in it is true any more.
    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(updatedAt) > TimeInterval(Self.horizonDays * 86_400)
    }
}

private let todayURL = URL(string: "agenda://today")!

struct TodayAgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayAgenda", provider: TodayProvider()) { entry in
            TodayAgendaView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(todayURL)
        }
        .configurationDisplayName("Today")
        .description("The class or event on now or next, and what's due today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayAgendaView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var snapshot: TodaySnapshot { entry.snapshot }
    private var now: Date { entry.date }
    private var due: [TodaySnapshot.Due] { snapshot.dueToday(at: now) }

    var body: some View {
        if snapshot.isStale(at: now) {
            VStack(alignment: .leading, spacing: 6) {
                header
                Spacer(minLength: 0)
                Text("Open Agenda to bring this up to date.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if family == .systemSmall {
            small
        } else {
            HStack(alignment: .top, spacing: 16) {
                small
                taskList
            }
        }
    }

    private var header: some View {
        Text(now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).capitalized)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let current = snapshot.current(at: now) {
                eventBlock("Now · until \(time(current.end))", current)
            } else if let next = snapshot.upcomingToday(at: now).first {
                eventBlock("Next · \(time(next.start))", next)
            } else if let next = snapshot.next(after: now) {
                eventBlock("\(next.start.formatted(.dateTime.weekday(.wide)).capitalized) · \(time(next.start))", next)
            } else {
                Text("Nothing scheduled").font(.headline)
                Text("No classes or events this week.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            dueLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func eventBlock(_ label: String, _ event: TodaySnapshot.Event) -> some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color(widgetHex: event.colorHex)).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                Text(event.title).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "3 due today", red when something is already late.
    private var dueLine: some View {
        let late = due.filter { snapshot.isOverdue($0, at: now) }.count
        let text = due.isEmpty ? "Nothing due today" : late > 0 ? "\(due.count) due · \(late) overdue" : "\(due.count) due today"
        return Label(text, systemImage: due.isEmpty ? "checkmark.circle" : "checklist")
            .font(.caption.weight(.medium))
            .foregroundStyle(late > 0 ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Due").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if due.isEmpty {
                Text("Nothing due today.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(due.prefix(4).enumerated()), id: \.offset) { _, task in
                let late = snapshot.isOverdue(task, at: now)
                HStack(spacing: 6) {
                    Circle().strokeBorder(Color(widgetHex: task.colorHex), lineWidth: 1.5).frame(width: 10, height: 10)
                    Text(task.title).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(late ? "Overdue" : task.hasTime ? time(task.due) : "Today")
                        .foregroundStyle(late ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .monospacedDigit()
                }
                .font(.caption)
            }
            if due.count > 4 {
                Text("+\(due.count - 4) more").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}

#Preview("Today", as: .systemMedium) {
    TodayAgendaWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .sample)
}

#Preview("Today small", as: .systemSmall) {
    TodayAgendaWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .sample)
}
