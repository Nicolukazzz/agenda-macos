import AgendaCore
import SwiftUI

// Hover details: rest the pointer on a calendar item to see everything about it without opening it.
//
// The peek is drawn inside the window by `peekHost()`, not in a popover: a popover is a second window
// that takes the pointer away from the item (the hand cursor drops back to the arrow) and costs a
// window, a material and an animation every time it opens.

extension View {
    /// Shows `peek` beside this view after the pointer rests on it. Clicks and drags still go through.
    /// Needs a `peekHost()` on a view around it.
    func hoverPeek<Peek: View>(isEnabled: Bool = true, @ViewBuilder _ peek: @escaping () -> Peek) -> some View {
        modifier(HoverPeek(isEnabled: isEnabled, peek: peek))
    }

    /// Draws the peeks asked for by the views inside, on top of them. One per page.
    func peekHost() -> some View {
        modifier(PeekHost())
    }
}

/// The item being peeked: where it is and what to show.
private struct PeekRequest {
    let anchor: Anchor<CGRect>
    let content: AnyView
}

private struct PeekKey: PreferenceKey {
    static var defaultValue: PeekRequest? { nil }
    static func reduce(value: inout PeekRequest?, nextValue: () -> PeekRequest?) { value = value ?? nextValue() }
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
            // A click opens the item, so the peek gets out of the way until the pointer comes back.
            .simultaneousGesture(TapGesture().onEnded { isShown = false })
            .anchorPreference(key: PeekKey.self, value: .bounds) { anchor in
                isShown ? PeekRequest(anchor: anchor, content: AnyView(peek())) : nil
            }
    }
}

private struct PeekHost: ViewModifier {
    func body(content: Content) -> some View {
        content.overlayPreferenceValue(PeekKey.self) { request in
            GeometryReader { proxy in
                if let request {
                    PeekPlacement(target: proxy[request.anchor], margin: Theme.Space.s) {
                        request.content
                            .padding(Theme.Space.l)
                            .frame(width: Theme.Size.peekWidth, alignment: .leading)
                            .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.card))
                            .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
                    }
                    .transition(.opacity)
                }
            }
            .animation(Theme.Motion.snappy, value: request == nil)
            // Never under the pointer as far as events go: the item keeps its hover and its cursor.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Puts the peek beside its item: trailing when it fits, else leading, always inside the page.
private struct PeekPlacement: Layout {
    let target: CGRect
    /// Gap to the item and to the page edges.
    let margin: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let peek = subviews.first else { return }
        let size = peek.sizeThatFits(.unspecified)
        var x = target.maxX + margin
        if x + size.width > bounds.width - margin {
            let leading = target.minX - margin - size.width
            x = leading >= margin ? leading : max(margin, bounds.width - margin - size.width)
        }
        let y = min(max(target.minY, margin), max(margin, bounds.height - margin - size.height))
        peek.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: .unspecified)
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
            PeekRow(systemImage: "clock", text: item.isAllDay
                ? "\(item.start.agenda(.dateTime.weekday(.wide).day().month(.wide))), all day"
                : "\(item.start.agenda(.dateTime.weekday(.wide).day().month(.wide))), \(item.start.agenda(date: .omitted, time: .shortened)) – \(item.end.agenda(date: .omitted, time: .shortened))")
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
