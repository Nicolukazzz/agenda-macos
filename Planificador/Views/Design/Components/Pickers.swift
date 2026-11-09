import AgendaCore
import MijickCalendarView
import SwiftUI

// iPhone-style pickers for macOS: glass pills that open an iOS-like month calendar (MijickCalendarView)
// or a scrolling time list, instead of the small stepper fields of `DatePicker`'s default style.

/// "Wed, Oct 21" pill → popover with the app's month calendar and quick choices.
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
                AgendaCalendar(date: $date) { isOpen = false }
            }
            .padding(Theme.Space.l)
        }
    }

    private func quick(_ title: String, _ day: Date) -> some View {
        Chip(title: title, isSelected: math.isSameDay(day, date)) {
            date = math.date(day, keepingTimeOf: date)
            isOpen = false
        }
    }
}

/// Month calendar from MijickCalendarView, styled like iOS: months scroll vertically, Monday first,
/// round day cells, selection in the accent color, today tinted. Picking a day keeps the time of `date`.
struct AgendaCalendar: View {
    @Binding var date: Date
    var onPick: () -> Void = {}

    private let math = CalendarMath()

    var body: some View {
        MCalendarView(selectedDate: Binding(get: { date }, set: { picked in
            guard let picked else { return }
            date = math.date(picked, keepingTimeOf: date)
            onPick()
        }), selectedRange: nil) {
            $0.startMonth(math.add(months: -24, to: .now))
                .endMonth(math.add(months: 36, to: .now))
                .firstWeekday(.monday)
                .locale(.agenda)
                .scrollTo(date: date)
                .monthLabelToDaysDistance(Theme.Space.s)
                .monthsSpacing(Theme.Space.xl)
                .daysVerticalSpacing(Theme.Space.xxs)
                .monthLabel(AgendaMonthLabel.init)
                .weekdaysView(AgendaWeekdays.init)
                .dayView(AgendaDayView.init)
        }
        .frame(width: 300, height: 330)
    }
}

private struct AgendaMonthLabel: MonthLabel {
    let month: Date

    func createContent() -> AnyView {
        Text(month.agenda(.dateTime.month(.wide).year()))
            .font(Theme.Font.sectionTitle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.s)
            .erased()
    }
}

private struct AgendaWeekdays: WeekdaysView {
    func createWeekdayLabel(_ weekday: MWeekday) -> AnyWeekdayLabel { AgendaWeekdayLabel(weekday: weekday).erased() }
}

private struct AgendaWeekdayLabel: WeekdayLabel {
    let weekday: MWeekday

    func createContent() -> AnyView {
        Text(getString(with: .veryShort))
            .font(Theme.Font.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .erased()
    }
}

private struct AgendaDayView: DayView {
    let date: Date
    let isCurrentMonth: Bool
    let selectedDate: Binding<Date?>?
    let selectedRange: Binding<MDateRange?>?

    func createContent() -> AnyView {
        let selected = isSelected()
        let today = isToday()
        return Text(getStringFromDay(format: "d"))
            .font(.system(size: 14, weight: selected || today ? .semibold : .regular, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(selected ? AnyShapeStyle(.white) : today ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .frame(width: 34, height: 34)
            .background {
                if selected { Circle().fill(Color.accentColor.gradient) }
                else if today { Circle().fill(.tint.opacity(0.15)) }
            }
            .animation(Theme.Motion.snappy, value: selected)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .hoverLift(scale: 1.1)
            .accessibilityLabel(date.agenda(date: .complete, time: .omitted))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .erased()
    }
}

private extension View {
    func erased() -> AnyView { AnyView(self) }
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
        .hoverHighlight(inset: 0)
        .id(minutes)
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
                        .frame(width: Theme.Size.dayCircle, height: Theme.Size.dayCircle)
                        .background(isOn ? AnyShapeStyle(tint.gradient) : Theme.Palette.neutralFill, in: Circle())
                        .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                }
                .buttonStyle(.plain)
                .hoverLift(scale: 1.08)
                .help(Weekdays.name(weekday))
                .accessibilityLabel(Weekdays.name(weekday))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
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

#Preview("Calendar") {
    @Previewable @State var date = Date.now
    AgendaCalendar(date: $date).padding()
}
