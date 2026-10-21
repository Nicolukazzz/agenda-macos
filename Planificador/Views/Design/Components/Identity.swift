import AgendaCore
import SwiftUI

// How a course (Area) is represented visually: dot, badge, tag pill and color choice.

/// Small color dot next to course names.
struct AreaDot: View {
    let hex: String
    var size: CGFloat = Theme.Size.dot

    var body: some View {
        Circle()
            .fill(Color(hex: hex).gradient)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Rounded square with the course initial; used in page headers.
struct AreaBadge: View {
    let name: String
    let colorHex: String
    var size: CGFloat = Theme.Size.badge

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Color(hex: colorHex).gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// `#tag` in the course color.
struct TagPill: View {
    let tag: String
    let colorHex: String
    var compact = false

    var body: some View {
        Text(compact ? tag : "#\(tag)")
            .font(compact ? .system(size: 9, weight: .semibold, design: .rounded) : Theme.Font.tag)
            .lineLimit(1)
            .padding(.horizontal, compact ? Theme.Space.xs : Theme.Space.s - 2)
            .padding(.vertical, compact ? 0 : Theme.Space.xxs)
            .frame(minHeight: compact ? 13 : nil)
            .background(Theme.Palette.eventFill(colorHex), in: Capsule())
            .foregroundStyle(Color(hex: colorHex))
    }
}

/// Inline row of palette swatches; the selected one gets a ring.
struct ColorSwatchPicker: View {
    @Binding var hex: String

    var body: some View {
        HStack(spacing: Theme.Space.s - 2) {
            ForEach(CoursePalette.hexColors, id: \.self) { color in
                Button {
                    withAnimation(Theme.Motion.snappy) { hex = color }
                } label: {
                    AreaDot(hex: color, size: 18)
                        .padding(3)
                        .overlay {
                            if color == hex { Circle().strokeBorder(.primary, lineWidth: 2) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(color)")
                .accessibilityAddTraits(color == hex ? .isSelected : [])
            }
        }
    }
}

/// Compact color choice (dot that opens the palette) for dense rows.
struct ColorSwatchMenu: View {
    @Binding var hex: String

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            AreaDot(hex: hex, size: 14).padding(4).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ColorSwatchPicker(hex: $hex)
                .padding(Theme.Space.m)
                .onChange(of: hex) { isOpen = false }
        }
        .accessibilityLabel("Course color")
    }

    @State private var isOpen = false
}
