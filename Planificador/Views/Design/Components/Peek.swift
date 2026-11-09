import AgendaCore
import SwiftUI

// Hover details: rest the pointer on a calendar item to see everything about it without opening it.

extension View {
    /// Opens `peek` in a popover after the pointer rests on this view. Clicks and drags still go through.
    func hoverPeek<Peek: View>(isEnabled: Bool = true, @ViewBuilder _ peek: @escaping () -> Peek) -> some View {
        modifier(HoverPeek(isEnabled: isEnabled, peek: peek))
    }
}

private struct HoverPeek<Peek: View>: ViewModifier {
    let isEnabled: Bool
    let peek: () -> Peek

    @State private var isHovering = false
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .task(id: isHovering && isEnabled) {
                guard isHovering && isEnabled else { isShown = false; return }
                try? await Task.sleep(for: Theme.Motion.peekDelay)
                if !Task.isCancelled { isShown = true }
            }
            .popover(isPresented: $isShown, arrowEdge: .trailing) {
                peek()
                    .padding(Theme.Space.l)
                    .frame(width: Theme.Size.peekWidth, alignment: .leading)
            }
    }
}

/// Layout of a hover peek: color bar + title, then detail rows (`PeekRow`).
struct PeekCard<Content: View>: View {
    let title: String
    let colorHex: String
    var isDone = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(hex: colorHex))
                    .frame(width: 3)
                Text(title)
                    .font(Theme.Font.sectionTitle)
                    .strikethrough(isDone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Theme.Space.xs) { content }
                .font(Theme.Font.rowDetail)
        }
    }
}

/// Icon + text line inside a `PeekCard`.
struct PeekRow: View {
    let systemImage: String
    let text: String
    var lineLimit = 1

    var body: some View {
        Label {
            Text(text).lineLimit(lineLimit)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.secondary)
        }
    }
}

/// Everything about one event occurrence.
struct EventPeek: View {
    let item: CalendarItem

    var body: some View {
        let block = item.block
        PeekCard(title: block.title, colorHex: item.colorHex) {
            PeekRow(systemImage: "clock", text: "\(item.start.agenda(.dateTime.weekday(.wide).day().month(.wide))), \(item.start.agenda(date: .omitted, time: .shortened)) – \(item.end.agenda(date: .omitted, time: .shortened))")
            if item.isRecurring { PeekRow(systemImage: "repeat", text: "Every week") }
            if !block.location.isEmpty { PeekRow(systemImage: "mappin.and.ellipse", text: block.location) }
            if let area = block.area {
                HStack(spacing: Theme.Space.s) {
                    Text(area.name)
                    TagPill(tag: area.tag, colorHex: area.colorHex)
                }
            }
            if let task = block.linkedTask { PeekRow(systemImage: "checklist", text: "Work on: \(task.title)") }
            if !block.notes.isEmpty { PeekRow(systemImage: "text.alignleft", text: block.notes, lineLimit: 4).foregroundStyle(.secondary) }
        }
    }
}

/// Everything about one task.
struct TaskPeek: View {
    let task: TaskItem

    var body: some View {
        PeekCard(title: task.title, colorHex: task.displayColorHex, isDone: task.isDone) {
            HStack(spacing: Theme.Space.s) {
                DueLabel(task: task)
                PriorityMark(priority: task.priority)
            }
            if let area = task.area {
                HStack(spacing: Theme.Space.s) {
                    Text(area.name)
                    TagPill(tag: area.tag, colorHex: area.colorHex)
                }
            }
            if !task.subtasks.isEmpty {
                PeekRow(systemImage: "checklist", text: "\(task.subtasks.filter(\.isDone).count) of \(task.subtasks.count) subtasks done")
            }
            if task.isDone { PeekRow(systemImage: "checkmark.circle.fill", text: "Done") }
            if !task.notes.isEmpty { PeekRow(systemImage: "text.alignleft", text: task.notes, lineLimit: 4).foregroundStyle(.secondary) }
        }
    }
}
