import AgendaCore
import SwiftData
import SwiftUI

// Items as they appear inside calendar cells and lists.

/// The one completion control for tasks, everywhere in the app.
struct CheckCircle: View {
    let isOn: Bool
    let colorHex: String
    var size: CGFloat = 11
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color(hex: colorHex))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Mark as not done" : "Mark as done")
    }
}

@MainActor
extension TaskItem {
    var displayColorHex: String { area?.colorHex ?? Theme.Palette.noAreaHex }

    func toggleDone() {
        withAnimation(Theme.Motion.snappy) {
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
        .onTapGesture { onOpen(item) }
        .draggable(CalendarDragPayload.block(item)) {
            Text(item.block.title).font(Theme.Font.chip).padding(Theme.Space.xs)
                .background(Theme.Palette.eventFill(item.colorHex), in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
        }
        .help(item.block.title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Deadline chip: completion circle + title in the course color. Draggable to change the due date.
struct TaskChip: View {
    @Bindable var task: TaskItem
    var onOpen: (TaskItem) -> Void = { _ in }

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            CheckCircle(isOn: task.isDone, colorHex: task.displayColorHex) { task.toggleDone() }
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
                .strokeBorder(Theme.Palette.eventStroke(task.displayColorHex), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpen(task) }
        .draggable(CalendarDragPayload.task(task)) {
            Text(task.title).font(Theme.Font.chip).padding(Theme.Space.xs)
        }
        .help("Due: \(task.title)")
    }
}

/// Compact class marker in month cells: the course tag in its color.
struct ClassTag: View {
    let item: CalendarItem
    var onOpen: (CalendarItem) -> Void

    var body: some View {
        TagPill(tag: item.block.area?.tag ?? "•", colorHex: item.colorHex, compact: true)
            .help("\(item.start.agenda(date: .omitted, time: .shortened)) · \(item.block.title)")
            .onTapGesture { onOpen(item) }
            .accessibilityAddTraits(.isButton)
    }
}
