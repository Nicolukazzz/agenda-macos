import SwiftUI

/// Single source for spacing, corner radii and type so every screen looks like the same app.
/// Liquid Glass is reserved for controls that float over content (toolbars, bars, popovers);
/// content itself (calendar grid, lists) stays on plain backgrounds, per Apple's guidance.
enum Theme {
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let chip: CGFloat = 6
        static let control: CGFloat = 8
        static let card: CGFloat = 12
        static let panel: CGFloat = 18
    }

    enum Font {
        static let pageTitle = SwiftUI.Font.system(.title2, design: .rounded).weight(.semibold)
        static let sectionTitle = SwiftUI.Font.system(.headline, design: .rounded)
        static let body = SwiftUI.Font.body
        static let chip = SwiftUI.Font.system(size: 11, weight: .medium)
        static let chipTime = SwiftUI.Font.system(size: 11, weight: .regular).monospacedDigit()
        static let dayNumber = SwiftUI.Font.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
        static let caption = SwiftUI.Font.caption
        static let tag = SwiftUI.Font.system(.caption, design: .monospaced)
    }

    enum Palette {
        static let gridLine = Color.primary.opacity(0.08)
        static let weekendFill = Color.primary.opacity(0.025)
        static let outsideMonthText = Color.secondary.opacity(0.55)
        static let nowLine = Color.red
        static let overdue = Color.red

        /// Fill behind an event in the area's color.
        static func eventFill(_ hex: String) -> Color { Color(hex: hex).opacity(0.18) }
        static func eventStroke(_ hex: String) -> Color { Color(hex: hex).opacity(0.55) }
    }

    enum Motion {
        static let standard = Animation.smooth(duration: 0.28)
        static let snappy = Animation.snappy(duration: 0.2)
    }
}

// MARK: - Shared components

/// Large title row used at the top of content pages.
struct PageHeader<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            leading
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).font(Theme.Font.pageTitle)
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Space.m)
            trailing
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
    }
}

extension PageHeader where Leading == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, leading: { EmptyView() }, trailing: trailing)
    }
}

/// `#tag` in the area's color.
struct TagPill: View {
    let tag: String
    let colorHex: String

    var body: some View {
        Text("#\(tag)")
            .font(Theme.Font.tag)
            .padding(.horizontal, Theme.Space.s - 2)
            .padding(.vertical, Theme.Space.xxs)
            .background(Theme.Palette.eventFill(colorHex), in: Capsule())
            .foregroundStyle(Color(hex: colorHex))
    }
}

/// Rounded square with the area's initial; used in headers and pickers.
struct AreaBadge: View {
    let name: String
    let colorHex: String
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Color(hex: colorHex).gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }
}

extension Locale {
    /// The app follows the system language and region (including its 12/24-hour setting).
    static var agenda: Locale { .autoupdatingCurrent }
}

extension Date {
    /// Formats with the app's locale (the system's).
    func agenda(_ style: Date.FormatStyle) -> String { formatted(style.locale(.agenda)) }

    func agenda(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time).locale(.agenda))
    }
}

/// Weekday labels from the system calendar, Monday first. Numbers follow `Calendar`: 1 = Sunday … 7 = Saturday.
enum Weekdays {
    static let order = [2, 3, 4, 5, 6, 7, 1]

    static func name(_ weekday: Int) -> String {
        Calendar.autoupdatingCurrent.standaloneWeekdaySymbols[weekday - 1]
    }

    /// One- or two-letter label (`M`, `Tu`…) that stays unambiguous within the week.
    static func initial(_ weekday: Int) -> String {
        let shorts = order.map { short($0) }
        let mine = short(weekday)
        let first = String(mine.prefix(1))
        let clashes = shorts.filter { $0.prefix(1) == first }.count > 1
        return clashes ? String(mine.prefix(2)) : first
    }

    static func short(_ weekday: Int) -> String {
        Calendar.autoupdatingCurrent.shortStandaloneWeekdaySymbols[weekday - 1]
    }
}
