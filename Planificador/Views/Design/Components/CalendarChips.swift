import AgendaCore
import SwiftData
import SwiftUI

// Items as they appear inside calendar cells and lists.

/// The one completion control for tasks, everywhere in the app.
/// Checking plays a burst first and calls `action` a moment later, so the reward is seen before the task moves or hides.
struct CheckCircle: View {
    let isOn: Bool
    let colorHex: String
    var size: CGFloat = 11
    let action: () -> Void

    @State private var celebrating = false

    var body: some View {
        let shown = isOn || celebrating
        Button(action: toggle) {
            Image(systemName: shown ? "checkmark.circle.fill" : "circle")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color(hex: colorHex))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: shown)
                .celebration(celebrating, color: Color(hex: colorHex), size: size)
                // Clickable area grows to `minHitTarget` without changing the layout.
                .padding(hitInset)
                .contentShape(Rectangle())
                .padding(-hitInset)
        }
        .buttonStyle(.plain)
        .hoverLift(scale: 1.12)
        .accessibilityLabel(shown ? "Mark as not done" : "Mark as done")
    }

    private var hitInset: CGFloat { max(0, (Theme.Size.minHitTarget - size) / 2) }

    private func toggle() {
        guard !celebrating else { return }
        guard !isOn else { return action() }
        celebrating = true
        Reward.play()
        Task {
            try? await Task.sleep(for: Theme.Motion.celebrationDelay)
            action()
            celebrating = false
        }
    }
}

@MainActor
extension TaskItem {
    var displayColorHex: String { area?.colorHex ?? Theme.Palette.noAreaHex }

    func toggleDone() {
        withAnimation(Theme.Motion.celebrate) {
            isDone.toggle()
            completedAt = isDone ? .now : nil
        }
    }
}

/// One-line event: color bar, time, title. Draggable to another day.
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
        .hoverLift(scale: 1.03)
        .onTapGesture { onOpen(item) }
        .draggable(CalendarDragPayload.block(item)) {
            Text(item.block.title).font(Theme.Font.chip).padding(Theme.Space.xs)
                .background(Theme.Palette.eventFill(item.colorHex), in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
        }
        .hoverPeek { EventPeek(item: item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Deadline chip: completion circle + title in the course color. Draggable to change the due date.
struct TaskChip: View {
    @Bindable var task: TaskItem
    var onOpen: (TaskItem) -> Void = { _ in }

    var body: some View {
        // The check sits outside the draggable, hover-peek part: a click on it never starts a drag or hits a popover.
        HStack(spacing: Theme.Space.xs) {
            CheckCircle(isOn: task.isDone, colorHex: task.displayColorHex, size: 12) { task.toggleDone() }
                .zIndex(1)
            Text(task.title)
                .font(Theme.Font.chip.weight(.semibold))
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .hoverLift(scale: 1.03)
                .onTapGesture { onOpen(task) }
                .draggable(CalendarDragPayload.task(task)) {
                    Text(task.title).font(Theme.Font.chip).padding(Theme.Space.xs)
                }
                .hoverPeek { TaskPeek(task: task) }
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip - 2)
                .strokeBorder(Theme.Palette.eventStroke(task.displayColorHex), lineWidth: 1)
        )
    }
}

/// An event as a full card row (Today view, lists): color bar, time range, title, room.
/// Live: past events fade, the current one shows how much is left, the next ones count down.
struct EventRow: View {
    let item: CalendarItem
    var onOpen: (CalendarItem) -> Void

    @Environment(\.now) private var now

    private var isPast: Bool { item.end <= now }
    private var isCurrent: Bool { item.start <= now && item.end > now }
    /// Counts down only for what starts within the next few hours.
    private var startsSoon: Bool { item.start > now && item.start.timeIntervalSince(now) < 3 * 3600 }

    var body: some View {
        CardRow {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(hex: item.colorHex))
                .frame(width: 3, height: 32)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(item.block.title).font(Theme.Font.rowTitle.weight(.medium))
                HStack(spacing: Theme.Space.s) {
                    Text("\(item.start.agenda(date: .omitted, time: .shortened)) – \(item.end.agenda(date: .omitted, time: .shortened))")
                        .monospacedDigit()
                    if !item.block.location.isEmpty {
                        Label(item.block.location, systemImage: "mappin")
                    }
                }
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    Text("Now").font(Theme.Font.caption.weight(.bold)).foregroundStyle(.tint)
                    Text("Ends \(Self.relative(item.end, from: now))").font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                ProgressRing(progress: now.timeIntervalSince(item.start) / item.end.timeIntervalSince(item.start), lineWidth: 3)
                    .frame(width: 18, height: 18)
            } else if startsSoon {
                Text(Self.relative(item.start, from: now).capitalized(with: .agenda))
                    .font(Theme.Font.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(isPast ? 0.5 : 1)
        .animation(Theme.Motion.standard, value: now)
        .contentShape(Rectangle())
        .hoverHighlight()
        .onTapGesture { onOpen(item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// "in 25 min"
    static func relative(_ date: Date, from now: Date) -> String {
        date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated).locale(.agenda))
    }
}

/// The current time inside a list of today's events, in the week view's now-line style.
struct NowDivider: View {
    let time: Date

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(time.agenda(date: .omitted, time: .shortened))
                .font(Theme.Font.chipTime.weight(.semibold))
                .foregroundStyle(Theme.Palette.nowLine)
                .contentTransition(.numericText(value: time.timeIntervalSince1970))
            Circle().fill(Theme.Palette.nowLine).frame(width: 6, height: 6)
            Rectangle().fill(Theme.Palette.nowLine).frame(height: 1.5)
        }
        .padding(.horizontal, Theme.Space.m + 2)
        .padding(.vertical, Theme.Space.xxs)
        .accessibilityElement()
        .accessibilityLabel("Now, \(time.agenda(date: .omitted, time: .shortened))")
    }
}
