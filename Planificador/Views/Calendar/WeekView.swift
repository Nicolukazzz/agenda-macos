import AppKit
import AgendaCore
import SwiftData
import SwiftUI

/// Outlook-style week: deadlines on top, hourly grid below. Drag on empty space to create,
/// drag a block to move it (also across days), drag its bottom edge to change its length.
struct WeekView: View {
    let anchor: Date
    let items: [CalendarItem]
    let tasks: [TaskItem]
    let math: CalendarMath
    var onOpen: (CalendarItem) -> Void
    var onOpenTask: (TaskItem) -> Void
    var onCreate: (Date, Date) -> Void
    var onReschedule: (CalendarItem, Date, Date) -> Void
    var onDrop: (String, Date) -> Bool
    /// A task dropped on the hour grid: payload and the start time under the pointer.
    var onDropAtTime: (String, Date) -> Bool

    @AppStorage("weekFirstHour") private var firstHour = 6
    @AppStorage("weekLastHour") private var lastHour = 23

    static let hourHeight: CGFloat = 52
    static let timeColumnWidth: CGFloat = 52
    static let snapMinutes = 15

    private var days: [Date] { math.weekDays(containing: anchor) }
    private var hours: [Int] { Array(firstHour..<max(lastHour, firstHour + 1)) }
    private var gridHeight: CGFloat { CGFloat(hours.count) * Self.hourHeight }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { scroller in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        timeColumn
                        GeometryReader { proxy in
                            let columnWidth = proxy.size.width / 7
                            HStack(spacing: 0) {
                                ForEach(days, id: \.self) { day in
                                    WeekDayColumn(
                                        day: day,
                                        items: items.filter { math.isSameDay($0.start, day) },
                                        isToday: math.isSameDay(day, .now),
                                        firstHour: hours.first ?? 0,
                                        lastHour: (hours.last ?? 23) + 1,
                                        columnWidth: columnWidth,
                                        math: math,
                                        onOpen: onOpen,
                                        onCreate: onCreate,
                                        onReschedule: onReschedule,
                                        onDropAtTime: onDropAtTime
                                    )
                                    .frame(width: columnWidth)
                                }
                            }
                        }
                        .frame(height: gridHeight)
                    }
                    .frame(height: gridHeight)
                    .padding(.bottom, Theme.Space.s)
                }
                .onAppear {
                    let hour = max(firstHour, math.calendar.component(.hour, from: .now) - 1)
                    scroller.scrollTo(hour, anchor: .top)
                }
            }
        }
    }

    // MARK: Header with day names and deadlines

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: Self.timeColumnWidth, height: 1)
            ForEach(days, id: \.self) { day in
                WeekDayHeader(
                    day: day,
                    isToday: math.isSameDay(day, .now),
                    tasks: tasks.filter { $0.dueDate.map { math.isSameDay($0, day) } ?? false },
                    onOpenTask: onOpenTask,
                    onDrop: { onDrop($0, day) }
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Theme.Space.s)
    }

    private var timeColumn: some View {
        VStack(spacing: 0) {
            ForEach(hours, id: \.self) { hour in
                Text(String(format: "%d:00", hour))
                    .font(Theme.Font.chipTime)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.timeColumnWidth - Theme.Space.s, height: Self.hourHeight, alignment: .topTrailing)
                    .offset(y: -7)
                    .id(hour)
            }
        }
        .frame(width: Self.timeColumnWidth, alignment: .leading)
    }
}

private struct WeekDayHeader: View {
    let day: Date
    let isToday: Bool
    let tasks: [TaskItem]
    var onOpenTask: (TaskItem) -> Void
    var onDrop: (String) -> Bool

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.xs) {
                Text(day.agenda(.dateTime.weekday(.abbreviated)).capitalized)
                    .foregroundStyle(.secondary)
                Text(day.agenda(.dateTime.day()))
                    .foregroundStyle(isToday ? .white : .primary)
                    .padding(.horizontal, isToday ? 7 : 0)
                    .frame(minHeight: 22)
                    .background { if isToday { Capsule().fill(.tint) } }
            }
            .font(Theme.Font.dayNumber)
            VStack(spacing: 2) {
                ForEach(tasks, id: \.liveID) { TaskChip(task: $0, onOpen: onOpenTask) }
            }
            .padding(.horizontal, Theme.Space.xs)
            .frame(minHeight: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xxs)
        .background {
            if isTargeted { RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(.tint, lineWidth: 2) }
        }
        .dropDestination(for: String.self) { payloads, _ in
            payloads.first.map(onDrop) ?? false
        } isTargeted: { isTargeted = $0 }
    }
}

private struct WeekDayColumn: View {
    let day: Date
    let items: [CalendarItem]
    let isToday: Bool
    let firstHour: Int
    let lastHour: Int
    let columnWidth: CGFloat
    let math: CalendarMath
    var onOpen: (CalendarItem) -> Void
    var onCreate: (Date, Date) -> Void
    var onReschedule: (CalendarItem, Date, Date) -> Void
    var onDropAtTime: (String, Date) -> Bool

    @State private var ghost: (start: CGFloat, end: CGFloat)?

    private var pointsPerMinute: CGFloat { WeekView.hourHeight / 60 }

    var body: some View {
        let slots = OverlapLayout.slots(for: items.map { ($0.start, $0.end) })
        ZStack(alignment: .topLeading) {
            gridLines
            Color.clear
                .contentShape(Rectangle())
                .gesture(createGesture)
                .gesture(SpatialTapGesture(count: 2).onEnded { value in
                    let start = snappedMinutes(at: value.location.y)
                    onCreate(math.date(day, atMinutes: start), math.date(day, atMinutes: min(start + 60, 24 * 60 - 1)))
                })

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let slot = slots[index]
                let width = columnWidth / CGFloat(slot.columnCount)
                WeekBlockView(
                    item: item,
                    columnWidth: columnWidth,
                    pointsPerMinute: pointsPerMinute,
                    onOpen: onOpen,
                    onCommit: { minuteShift, dayShift, extraMinutes in commit(item, minuteShift, dayShift, extraMinutes) }
                )
                .frame(width: max(width - 3, 10), height: max(height(of: item), 18))
                .offset(x: width * CGFloat(slot.column) + 1, y: y(of: item.start))
            }

            if let ghost {
                RoundedRectangle(cornerRadius: Theme.Radius.chip)
                    .fill(.tint.opacity(0.25))
                    .strokeBorder(.tint, lineWidth: 1)
                    .frame(width: columnWidth - 4, height: max(abs(ghost.end - ghost.start), 6))
                    .offset(x: 2, y: min(ghost.start, ghost.end))
            }

            if isToday { nowLine }
        }
        .background(isWeekend ? Theme.Palette.weekendFill : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.Palette.gridLine).frame(width: 1) }
        .clipped()
        .dropDestination(for: String.self) { payloads, location in
            guard let payload = payloads.first else { return false }
            return onDropAtTime(payload, math.date(day, atMinutes: snappedMinutes(at: location.y)))
        }
    }

    private var isWeekend: Bool {
        let weekday = math.calendar.component(.weekday, from: day)
        return weekday == 1 || weekday == 7
    }

    private var gridLines: some View {
        Canvas { context, size in
            let hourCount = lastHour - firstHour
            for hour in 0...hourCount {
                let y = CGFloat(hour) * WeekView.hourHeight
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Theme.Palette.gridLine))
                let half = y + WeekView.hourHeight / 2
                if hour < hourCount {
                    context.fill(Path(CGRect(x: 0, y: half, width: size.width, height: 0.5)), with: .color(Theme.Palette.gridLine.opacity(0.5)))
                }
            }
        }
    }

    private var nowLine: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let y = y(of: context.date)
            HStack(spacing: 0) {
                Circle().fill(Theme.Palette.nowLine).frame(width: 8, height: 8)
                Rectangle().fill(Theme.Palette.nowLine).frame(height: 1.5)
            }
            .offset(x: -4, y: y - 4)
        }
        .allowsHitTesting(false)
    }

    // MARK: Geometry

    private func y(of date: Date) -> CGFloat {
        CGFloat(math.minutesIntoDay(date) - firstHour * 60) * pointsPerMinute
    }

    private func height(of item: CalendarItem) -> CGFloat {
        CGFloat(item.end.timeIntervalSince(item.start) / 60) * pointsPerMinute
    }

    private func snappedMinutes(at y: CGFloat) -> Int {
        let raw = Int(y / pointsPerMinute) + firstHour * 60
        let snapped = Int((Double(raw) / Double(WeekView.snapMinutes)).rounded(.down)) * WeekView.snapMinutes
        return min(max(snapped, 0), 24 * 60 - WeekView.snapMinutes)
    }

    // MARK: Gestures

    private var createGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in ghost = (value.startLocation.y, value.location.y) }
            .onEnded { value in
                ghost = nil
                var start = snappedMinutes(at: min(value.startLocation.y, value.location.y))
                var end = snappedMinutes(at: max(value.startLocation.y, value.location.y)) + WeekView.snapMinutes
                if end - start < 30 { end = start + 30 }
                end = min(end, 24 * 60 - 1)
                start = min(start, end - WeekView.snapMinutes)
                onCreate(math.date(day, atMinutes: start), math.date(day, atMinutes: end))
            }
    }

    private func commit(_ item: CalendarItem, _ minuteShift: Int, _ dayShift: Int, _ extraMinutes: Int) {
        let duration = Int(item.end.timeIntervalSince(item.start) / 60)
        let newDuration = max(WeekView.snapMinutes, duration + extraMinutes)
        let targetDay = math.add(days: dayShift, to: math.startOfDay(item.start))
        // Keep the whole block inside its day: no blocks across midnight.
        var startMinutes = math.minutesIntoDay(item.start) + minuteShift
        startMinutes = min(max(startMinutes, 0), 24 * 60 - newDuration)
        let newStart = math.date(targetDay, atMinutes: startMinutes)
        let newEnd = math.date(targetDay, atMinutes: min(startMinutes + newDuration, 24 * 60 - 1))
        guard newStart != item.start || newEnd != item.end else { return }
        onReschedule(item, newStart, newEnd)
    }
}

private struct WeekBlockView: View {
    let item: CalendarItem
    let columnWidth: CGFloat
    let pointsPerMinute: CGFloat
    var onOpen: (CalendarItem) -> Void
    /// minute shift, day shift, extra minutes of length
    var onCommit: (Int, Int, Int) -> Void

    @State private var drag: CGSize = .zero
    @State private var resize: CGFloat = 0
    @State private var hovering = false

    private func snap(_ points: CGFloat) -> Int {
        let minutes = Double(points / pointsPerMinute)
        return Int((minutes / Double(WeekView.snapMinutes)).rounded()) * WeekView.snapMinutes
    }

    var body: some View {
        let color = Color(hex: item.colorHex)
        let shiftedMinutes = snap(drag.height)
        let dayShift = Int((drag.width / columnWidth).rounded())
        VStack(alignment: .leading, spacing: 1) {
            Text(item.block.title)
                .font(Theme.Font.chip.weight(.semibold))
                .lineLimit(2)
            Text(timeRange(shiftedMinutes: shiftedMinutes))
                .font(Theme.Font.chipTime)
                .foregroundStyle(.secondary)
            if !item.block.location.isEmpty {
                Label(item.block.location, systemImage: "mappin")
                    .font(Theme.Font.chipTime)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.xs + 1)
        .padding(.vertical, Theme.Space.xs - 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: nil)
        .background(Theme.Palette.eventFill(item.colorHex), in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.chip, bottomLeadingRadius: Theme.Radius.chip)
                .fill(color)
                .frame(width: 3)
        }
        .overlay(alignment: .bottom) { resizeHandle }
        .padding(.bottom, -resize)
        .shadow(color: .black.opacity(drag == .zero ? 0 : 0.2), radius: 8, y: 4)
        .offset(x: CGFloat(dayShift) * columnWidth, y: CGFloat(shiftedMinutes) * pointsPerMinute)
        .zIndex(drag == .zero ? 0 : 1)
        .onHover { hovering = $0 }
        .onTapGesture { onOpen(item) }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    let minutes = snap(value.translation.height)
                    let days = Int((value.translation.width / columnWidth).rounded())
                    drag = .zero
                    onCommit(minutes, days, 0)
                }
        )
        .help(item.block.title)
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 7)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { resize = $0.translation.height }
                    .onEnded { value in
                        resize = 0
                        onCommit(0, 0, snap(value.translation.height))
                    }
            )
    }

    private func timeRange(shiftedMinutes: Int) -> String {
        let start = item.start.addingTimeInterval(TimeInterval(shiftedMinutes * 60))
        let end = item.end.addingTimeInterval(TimeInterval((shiftedMinutes + snap(resize)) * 60))
        let style = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(start.agenda(style)) – \(end.agenda(style))"
    }
}
