import AgendaCore
import SwiftUI

// iPhone-style pickers for macOS: glass pills that open native graphical pickers or
// touch-friendly lists, instead of the small stepper fields of `DatePicker`'s default style.

/// "Wed, Oct 21" pill → popover with the native graphical calendar and quick choices.
struct DatePill: View {
    @Binding var date: Date
    var label: String?
    var showsIcon = true

    @State private var isOpen = false
    private let math = CalendarMath()

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            Label(label ?? date.agenda(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), systemImage: "calendar")
                .labelStyle(PillLabelStyle(showsIcon: showsIcon))
                .monospacedDigit()
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Date, \(date.agenda(date: .complete, time: .omitted))")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.s) {
                    quick("Today", math.startOfDay(.now))
                    quick("Tomorrow", math.add(days: 1, to: math.startOfDay(.now)))
                    quick("Next Week", math.add(days: 7, to: math.startOfWeek(containing: .now)))
                }
                MonthPicker(date: $date) { isOpen = false }
            }
            .padding(Theme.Space.l)
        }
    }

    private func quick(_ title: String, _ day: Date) -> some View {
        let isSelected = math.isSameDay(day, date)
        return Button(title) {
            date = math.date(day, keepingTimeOf: date)
            isOpen = false
        }
        .buttonStyle(.glass)
        .tint(isSelected ? .accentColor : nil)
        .controlSize(.small)
    }
}

/// iOS-style month calendar: Monday first, round day cells, selection in the accent color.
struct MonthPicker: View {
    @Binding var date: Date
    var onPick: () -> Void = {}

    @State private var month = Date.now
    private let math = CalendarMath()
    private static let cell: CGFloat = 34

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            HStack {
                Text(month.agenda(.dateTime.month(.wide).year()))
                    .font(Theme.Font.sectionTitle)
                    .contentTransition(.numericText())
                Spacer()
                ControlGroup {
                    Button("Previous Month", systemImage: "chevron.left") { shift(-1) }
                    Button("Next Month", systemImage: "chevron.right") { shift(1) }
                }
                .labelStyle(.iconOnly)
                .fixedSize()
            }
            .padding(.horizontal, Theme.Space.xs)

            HStack(spacing: 0) {
                ForEach(Weekdays.order, id: \.self) { weekday in
                    Text(Weekdays.initial(weekday))
                        .font(Theme.Font.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: Self.cell)
                }
            }

            VStack(spacing: 2) {
                ForEach(math.monthGrid(containing: month), id: \.first) { week in
                    HStack(spacing: 0) {
                        ForEach(week, id: \.self) { day in dayCell(day) }
                    }
                }
            }
        }
        .frame(width: Self.cell * 7)
        .onAppear { month = date }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = math.isSameDay(day, date)
        let isToday = math.isSameDay(day, .now)
        let inMonth = math.isSameMonth(day, month)
        return Button {
            date = math.date(day, keepingTimeOf: date)
            onPick()
        } label: {
            Text(day.agenda(.dateTime.day()))
                .font(.system(size: 14, weight: isSelected || isToday ? .semibold : .regular, design: .rounded))
                .monospacedDigit()
                .frame(width: Self.cell - 4, height: Self.cell - 4)
                .background {
                    if isSelected { Circle().fill(.tint) }
                    else if isToday { Circle().fill(.tint.opacity(0.15)) }
                }
                .foregroundStyle(
                    isSelected ? AnyShapeStyle(.white)
                        : isToday ? AnyShapeStyle(.tint)
                        : inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: Self.cell, height: Self.cell)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.agenda(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func shift(_ months: Int) {
        withAnimation(Theme.Motion.snappy) { month = math.add(months: months, to: month) }
    }
}

/// "09:00" pill → popover with a scrolling list of times every `step` minutes, centered on the selection.
struct TimePill: View {
    @Binding var time: Date
    var step = 15
    var icon = "clock"
    var showsIcon = true

    @State private var isOpen = false
    private let math = CalendarMath()

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            Label(time.agenda(date: .omitted, time: .shortened), systemImage: icon)
                .labelStyle(PillLabelStyle(showsIcon: showsIcon))
                .monospacedDigit()
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Time, \(time.agenda(date: .omitted, time: .shortened))")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            TimeList(time: $time, step: step) { isOpen = false }
        }
    }
}

struct TimeList: View {
    @Binding var time: Date
    let step: Int
    var onPick: () -> Void

    private let math = CalendarMath()

    private var selectedMinutes: Int { math.minutesIntoDay(time) }
    private var slots: [Int] { Array(stride(from: 0, to: 24 * 60, by: step)) }

    var body: some View {
        VStack(spacing: 0) {
            DatePicker("Exact time", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)
                .labelsHidden()
                .padding(Theme.Space.m)
            Divider()
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(slots, id: \.self) { minutes in
                            row(minutes)
                        }
                    }
                    .padding(Theme.Space.s)
                }
                .onAppear {
                    let nearest = slots.min { abs($0 - selectedMinutes) < abs($1 - selectedMinutes) } ?? 0
                    scroller.scrollTo(nearest, anchor: .center)
                }
            }
        }
        .frame(width: 180, height: 300)
    }

    private func row(_ minutes: Int) -> some View {
        let date = math.date(time, atMinutes: minutes)
        let isSelected = minutes == selectedMinutes
        return Button {
            time = date
            onPick()
        } label: {
            HStack {
                Text(date.agenda(date: .omitted, time: .shortened)).monospacedDigit()
                Spacer()
                if isSelected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s - 2)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
            .background {
                if isSelected { RoundedRectangle(cornerRadius: Theme.Radius.control).fill(.tint.opacity(0.2)) }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .id(minutes)
    }
}

/// Quick durations that move the end time: 30m · 45m · 1h · 1h 30m · 2h · 3h.
struct DurationChips: View {
    let start: Date
    @Binding var end: Date

    private static let options = [30, 45, 60, 90, 120, 180]

    private var currentMinutes: Int { Int(end.timeIntervalSince(start) / 60) }

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(Self.options, id: \.self) { minutes in
                let isSelected = minutes == currentMinutes
                Button(Self.label(minutes)) {
                    withAnimation(Theme.Motion.snappy) { end = start.addingTimeInterval(TimeInterval(minutes * 60)) }
                }
                .buttonStyle(.plain)
                .font(Theme.Font.chip)
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, Theme.Space.xs)
                .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary.opacity(0.6)), in: Capsule())
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            }
        }
    }

    static func label(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(rest)m"
        }
    }
}

/// Tappable course chips in their colors, plus "None".
struct CourseChips: View {
    @Binding var selection: Area?
    let areas: [Area]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.xs + 2) {
                chip(title: "None", colorHex: nil, isSelected: selection == nil) { selection = nil }
                ForEach(areas) { area in
                    chip(title: area.name, colorHex: area.colorHex, isSelected: selection === area) { selection = area }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
    }

    private func chip(title: String, colorHex: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let color = colorHex.map { Color(hex: $0) } ?? .secondary
        return Button {
            withAnimation(Theme.Motion.snappy, action)
        } label: {
            HStack(spacing: Theme.Space.xs + 1) {
                if colorHex != nil {
                    Circle().fill(isSelected ? .white : color).frame(width: 7, height: 7)
                }
                Text(title).lineLimit(1)
            }
            .font(.callout.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, Theme.Space.m - 2)
            .padding(.vertical, Theme.Space.xs + 1)
            .background(isSelected ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.14)), in: Capsule())
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// iPhone-alarm style weekday circles, Monday first.
struct WeekdayCircles: View {
    @Binding var selection: Set<Int>
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: Theme.Space.xs + 2) {
            ForEach(Weekdays.order, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    withAnimation(Theme.Motion.snappy) {
                        if isOn { selection.remove(weekday) } else { selection.insert(weekday) }
                    }
                } label: {
                    Text(Weekdays.initial(weekday))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(width: 30, height: 30)
                        .background(isOn ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.quaternary.opacity(0.6)), in: Circle())
                        .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                }
                .buttonStyle(.plain)
                .help(Weekdays.name(weekday))
                .accessibilityLabel(Weekdays.name(weekday))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// Rounded card that groups rows with leading icons (iOS Settings look, app spacing).
struct EditorCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

/// Row inside an `EditorCard`: icon, then content; separators between rows come from `EditorDivider`.
struct EditorRow<Content: View>: View {
    let icon: String
    var iconColor: Color = .secondary
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 20)
            HStack(spacing: Theme.Space.s) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Space.m + 2)
        .padding(.vertical, Theme.Space.s + 2)
    }
}

struct EditorDivider: View {
    var body: some View { Divider().padding(.leading, 48) }
}

/// Pills inside editor rows already have a row icon; this hides the duplicate.
struct PillLabelStyle: LabelStyle {
    var showsIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsIcon {
            Label(configuration)
        } else {
            configuration.title
        }
    }
}

#Preview("Pickers") {
    @Previewable @State var days: Set<Int> = [2, 4]
    @Previewable @State var date = Date.now
    HStack(alignment: .top, spacing: Theme.Space.xl) {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            WeekdayCircles(selection: $days)
            MonthPicker(date: $date)
        }
        TimeList(time: $date, step: 15) {}
    }
    .padding(Theme.Space.xl)
}
