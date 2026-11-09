import SwiftUI

// Pointer feedback, Apple style: everything clickable answers the pointer before it's clicked.
// Rows get a soft inset highlight; buttons and tiles lift a little. Both show the hand cursor.

extension View {
    /// Rows and list items: a rounded, inset wash behind the content while hovered.
    func hoverHighlight(cornerRadius: CGFloat = Theme.Radius.control + 2, inset: CGFloat = Theme.Space.xs) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, inset: inset))
    }

    /// Buttons, chips and tiles: a slight lift (scale, brightness, shadow) while hovered.
    func hoverLift(scale: CGFloat = 1.02) -> some View {
        modifier(HoverLift(scale: scale))
    }
}

private struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    let inset: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.07 : 0))
                    .padding(.horizontal, inset)
                    .padding(.vertical, inset / 2)
            }
            .onHover { inside in withAnimation(Theme.Motion.snappy) { hovering = inside } }
            .pointerStyle(.link)
    }
}

private struct HoverLift: ViewModifier {
    let scale: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .brightness(hovering ? 0.04 : 0)
            .shadow(color: .black.opacity(hovering ? 0.18 : 0), radius: hovering ? 10 : 0, y: hovering ? 4 : 0)
            .onHover { inside in withAnimation(Theme.Motion.snappy) { hovering = inside } }
            .pointerStyle(.link)
    }
}
