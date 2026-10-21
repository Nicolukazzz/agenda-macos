import SwiftData
import SwiftUI

// One chip primitive; course chips, duration chips and quick choices are built on it.

struct Chip: View {
    let title: String
    var colorHex: String?
    var isSelected: Bool
    var showsDot = true
    let action: () -> Void

    private var color: Color { colorHex.map { Color(hex: $0) } ?? .accentColor }

    var body: some View {
        Button {
            withAnimation(Theme.Motion.snappy, action)
        } label: {
            HStack(spacing: Theme.Space.xs + 1) {
                if showsDot, colorHex != nil {
                    Circle().fill(isSelected ? .white : color).frame(width: 7, height: 7)
                }
                Text(title).lineLimit(1)
            }
            .font(.callout.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, Theme.Space.m - 2)
            .padding(.vertical, Theme.Space.xs + 1)
            .background(background, in: Capsule())
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(color.gradient) }
        return colorHex == nil ? Theme.Palette.neutralFill : AnyShapeStyle(color.opacity(0.14))
    }
}

/// Horizontally scrolling chips. The trailing edge fades out only when the row overflows,
/// hinting that there is more to scroll.
struct ChipRow<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var overflows = false

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.xs + 2) { content }
                .padding(.vertical, 2)
                .padding(.trailing, overflows ? Theme.Space.xl : 0)
        }
        .scrollIndicators(.never)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.width > geometry.containerSize.width + 1
        } action: { _, newValue in
            overflows = newValue
        }
        .mask {
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: overflows ? Theme.Space.xxl : 0)
            }
        }
    }
}

/// Course chips in their colors, plus "None".
struct CourseChips: View {
    @Binding var selection: Area?
    let areas: [Area]
    /// Label for the nil choice: "None" when assigning, "All" when filtering.
    var noneTitle = "None"

    var body: some View {
        ChipRow {
            Chip(title: noneTitle, isSelected: selection == nil) { selection = nil }
            ForEach(areas, id: \.liveID) { area in
                Chip(title: area.name, colorHex: area.colorHex, isSelected: selection === area) { selection = area }
            }
        }
    }
}

/// Quick durations that move the end time.
struct DurationChips: View {
    let start: Date
    @Binding var end: Date

    private static let options = [30, 45, 60, 90, 120, 180]
    private var current: Int { Int(end.timeIntervalSince(start) / 60) }

    var body: some View {
        ChipRow {
            ForEach(Self.options, id: \.self) { minutes in
                Chip(title: Self.label(minutes), isSelected: minutes == current) {
                    end = start.addingTimeInterval(TimeInterval(minutes * 60))
                }
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
