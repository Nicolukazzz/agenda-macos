import AgendaCore
import SwiftData
import SwiftUI

/// Month grid (main calendar view). Deadlines first, then appointments; classes are
/// compact color dots unless "Show Classes" is on, so the month stays readable.
struct MonthView: View {
    let anchor: Date
    let items: [CalendarItem]
    let tasks: [TaskItem]
    let showClasses: Bool
    let math: CalendarMath
    var onOpen: (CalendarItem) -> Void
    var onCreate: (Date) -> Void
    var onOpenDay: (Date) -> Void
    var onDrop: (String, Date) -> Bool

    private var grid: [[Date]] { math.monthGrid(containing: anchor) }

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
            Divider()
            GeometryReader { proxy in
                let rows = grid
                let rowHeight = proxy.size.height / CGFloat(max(rows.count, 1))
                VStack(spacing: 0) {
                    ForEach(rows, id: \.first) { week in
                        HStack(spacing: 0) {
                            ForEach(week, id: \.self) { day in
                                MonthDayCell(
                                    day: day,
                                    isInMonth: math.isSameMonth(day, anchor),
                                    isToday: math.isSameDay(day, .now),
                                    isWeekend: isWeekend(day),
                                    items: items.filter { math.isSameDay($0.start, day) },
                                    tasks: tasks.filter { $0.dueDate.map { math.isSameDay($0, day) } ?? false },
                                    showClasses: showClasses,
                                    height: rowHeight,
                                    onOpen: onOpen,
                                    onCreate: { onCreate(day) },
                                    onOpenDay: { onOpenDay(day) },
                                    onDrop: { onDrop($0, day) }
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: rowHeight)
                            }
                        }
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Palette.gridLine).frame(height: 1) }
                    }
                }
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(math.weekDays(containing: anchor), id: \.self) { day in
                Text(day.agenda(.dateTime.weekday(.abbreviated)).capitalized)
                    .font(Theme.Font.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Theme.Space.s)
    }

    private func isWeekend(_ day: Date) -> Bool {
        let weekday = math.calendar.component(.weekday, from: day)
        return weekday == 1 || weekday == 7
    }
}

private struct MonthDayCell: View {
    let day: Date
    let isInMonth: Bool
    let isToday: Bool
    let isWeekend: Bool
    let items: [CalendarItem]
    let tasks: [TaskItem]
    let showClasses: Bool
    let height: CGFloat
    var onOpen: (CalendarItem) -> Void
    var onCreate: () -> Void
    var onOpenDay: () -> Void
    var onDrop: (String) -> Bool

    @State private var isTargeted = false

    private static let lineHeight: CGFloat = 18
    private static let headerHeight: CGFloat = 26

    private var classes: [CalendarItem] { items.filter(\.isRecurring) }
    private var events: [CalendarItem] { showClasses ? items : items.filter { !$0.isRecurring } }

    /// Rows available below the day number (one reserved for class dots or "+N more").
    private var capacity: Int { max(0, Int((height - Self.headerHeight - 4) / Self.lineHeight)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.xs)
        .padding(.top, Theme.Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isWeekend ? Theme.Palette.weekendFill : .clear)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(.tint, lineWidth: 2)
                    .padding(2)
            }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.Palette.gridLine).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onCreate)
        .dropDestination(for: String.self) { payloads, _ in
            payloads.first.map(onDrop) ?? false
        } isTargeted: { isTargeted = $0 }
        .contextMenu {
            Button("New Event", systemImage: "plus", action: onCreate)
            Button("Show Week", systemImage: "calendar.day.timeline.left", action: onOpenDay)
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Text(dayLabel)
                .font(Theme.Font.dayNumber)
                .foregroundStyle(isToday ? .white : (isInMonth ? .primary : Theme.Palette.outsideMonthText))
                .padding(.horizontal, isToday ? 7 : 2)
                .frame(minWidth: 22, minHeight: 22)
                .background {
                    if isToday { Capsule().fill(.tint) }
                }
        }
        .frame(height: Self.headerHeight - 4)
    }

    private var dayLabel: String {
        let dayNumber = Calendar.current.component(.day, from: day)
        return dayNumber == 1 ? day.agenda(.dateTime.day().month(.abbreviated)) : "\(dayNumber)"
    }

    @ViewBuilder
    private var content: some View {
        let showDots = !showClasses && !classes.isEmpty
        let rows = capacity - (showDots ? 1 : 0)
        let entries: [Entry] = tasks.map(Entry.task) + events.map(Entry.event)
        let visible = entries.prefix(max(0, entries.count > rows ? rows - 1 : rows))
        let hidden = entries.count - visible.count

        ForEach(visible) { entry in
            switch entry {
            case .task(let task): TaskChip(task: task)
            case .event(let item): EventChip(item: item, onOpen: onOpen)
            }
        }
        .opacity(isInMonth ? 1 : 0.6)

        if hidden > 0 {
            Button("+\(hidden) more", action: onOpenDay)
                .buttonStyle(.plain)
                .font(Theme.Font.chip)
                .foregroundStyle(.secondary)
                .padding(.leading, Theme.Space.xs)
        }

        if showDots {
            // Compact class markers: the course tag in its color, in time order.
            HStack(spacing: 3) {
                ForEach(classes) { item in
                    Text(item.block.area?.tag ?? "•")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(height: 13)
                        .foregroundStyle(Color(hex: item.colorHex))
                        .background(Theme.Palette.eventFill(item.colorHex), in: Capsule())
                        .help("\(item.start.agenda(date: .omitted, time: .shortened)) · \(item.block.title)")
                        .onTapGesture { onOpen(item) }
                }
            }
            .padding(.leading, Theme.Space.xxs)
            .frame(height: 14, alignment: .leading)
            .clipped()
            .opacity(isInMonth ? 1 : 0.6)
        }
    }

    private enum Entry: Identifiable {
        case task(TaskItem)
        case event(CalendarItem)

        var id: String {
            switch self {
            case .task(let task): "t-\(CalendarFeed.key(for: task))"
            case .event(let item): item.id
            }
        }
    }
}

/// One-line event in the month grid: color bar, time, title. Draggable to another day.
struct EventChip: View {
    let item: CalendarItem
    var onOpen: (CalendarItem) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(hex: item.colorHex))
                .frame(width: 3)
            Text(item.start.agenda(.dateTime.hour().minute()))
                .font(Theme.Font.chipTime)
                .foregroundStyle(.secondary)
            Text(item.block.title)
                .font(Theme.Font.chip)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .leading)
        .background(Theme.Palette.eventFill(item.colorHex).opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.chip - 2))
        .contentShape(Rectangle())
        .onTapGesture { onOpen(item) }
        .draggable(CalendarDragPayload.block(item)) {
            Text(item.block.title).font(Theme.Font.chip).padding(Theme.Space.xs)
                .background(Theme.Palette.eventFill(item.colorHex), in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
        }
        .help(item.block.title)
    }
}

/// Deadline in the calendar: checkbox + title in the area's color. Draggable to change the due date.
struct TaskChip: View {
    @Bindable var task: TaskItem

    private var colorHex: String { task.area?.colorHex ?? CoursePalette.hexColors.last! }

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Button {
                withAnimation(Theme.Motion.snappy) {
                    task.isDone.toggle()
                    task.completedAt = task.isDone ? .now : nil
                }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: colorHex))
            }
            .buttonStyle(.plain)
            Text(task.title)
                .font(Theme.Font.chip.weight(.semibold))
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .secondary : .primary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip - 2)
                .strokeBorder(Theme.Palette.eventStroke(colorHex), lineWidth: 1)
        )
        .draggable(CalendarDragPayload.task(task)) {
            Text(task.title).font(Theme.Font.chip).padding(Theme.Space.xs)
        }
        .help("Due: \(task.title)")
    }
}
