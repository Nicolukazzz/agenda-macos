import AppKit
import SwiftUI

// Design tokens. Every size, radius, font, color and animation used by the app comes from here.
// Components in `Design/Components` read these; screens never hard-code them.
//
// Liquid Glass rule (Apple HIG): glass is for the control layer that floats over content
// (toolbars, pills, popovers, primary actions). Content (calendar grid, lists, cards) stays opaque.

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

    enum Size {
        static let rowIcon: CGFloat = 20
        /// Smallest clickable area for small controls, even when they draw smaller.
        static let minHitTarget: CGFloat = 24
        /// Leading inset of row separators: row padding + icon + spacing.
        static let rowInset: CGFloat = 48
        static let dot: CGFloat = 8
        static let badge: CGFloat = 40
        static let dayCircle: CGFloat = 30
        static let sheetWidth: CGFloat = 540
        static let contentMaxWidth: CGFloat = 720
        static let peekWidth: CGFloat = 280
    }

    enum Font {
        static let pageTitle = SwiftUI.Font.system(.title2, design: .rounded).weight(.semibold)
        static let editorTitle = SwiftUI.Font.system(.title2, design: .rounded).weight(.semibold)
        static let sectionTitle = SwiftUI.Font.system(.headline, design: .rounded)
        static let eyebrow = SwiftUI.Font.caption.weight(.semibold)
        static let body = SwiftUI.Font.body
        static let rowTitle = SwiftUI.Font.body
        static let rowDetail = SwiftUI.Font.callout
        static let caption = SwiftUI.Font.caption
        static let chip = SwiftUI.Font.system(size: 11, weight: .medium)
        static let chipTime = SwiftUI.Font.system(size: 11, weight: .regular).monospacedDigit()
        static let dayNumber = SwiftUI.Font.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
        static let tag = SwiftUI.Font.system(.caption, design: .monospaced)
    }

    enum Palette {
        static let cardFill = AnyShapeStyle(.background.secondary)
        static let neutralFill = AnyShapeStyle(.quaternary.opacity(0.6))
        static let gridLine = Color.primary.opacity(0.08)
        static let weekendFill = Color.primary.opacity(0.025)
        static let outsideMonthText = Color.secondary.opacity(0.55)
        static let nowLine = Color.red
        static let danger = Color.red
        static let warning = Color.orange
        static let success = Color.green
        /// Area color used when an item has no course.
        static let noAreaHex = "#6B7A90"

        static func eventFill(_ hex: String) -> Color { Color(hex: hex).opacity(0.18) }
        static func eventStroke(_ hex: String) -> Color { Color(hex: hex).opacity(0.55) }
    }

    enum Motion {
        static let standard = Animation.smooth(duration: 0.28)
        static let snappy = Animation.snappy(duration: 0.2)
        /// Springy, for rewards: a task checked off, a day cleared.
        static let celebrate = Animation.spring(duration: 0.5, bounce: 0.35)
        /// How long a checked task stays put (and its burst plays) before it moves or hides.
        static let celebrationDelay = Duration.milliseconds(450)
        /// Pointer rest time before a hover peek opens.
        static let peekDelay = Duration.milliseconds(700)
    }
}

// MARK: - Color

extension Color {
    /// `#RRGGBB` → Color. Falls back to gray for malformed input.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// MARK: - Dates

extension Locale {
    /// The app follows the system language and region (including its 12/24-hour setting).
    static var agenda: Locale { .autoupdatingCurrent }
}

extension Date {
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

    static func short(_ weekday: Int) -> String {
        Calendar.autoupdatingCurrent.shortStandaloneWeekdaySymbols[weekday - 1]
    }

    /// One- or two-letter label (`M`, `Tu`…) that stays unambiguous within the week.
    static func initial(_ weekday: Int) -> String {
        let mine = short(weekday)
        let first = String(mine.prefix(1))
        let clashes = order.map(short).filter { $0.prefix(1) == first }.count > 1
        return clashes ? String(mine.prefix(2)) : first
    }
}

// MARK: - System panels

/// Opens a folder picker starting at `start`; returns the chosen folder or nil.
@MainActor
func chooseFolder(startingAt start: URL?, prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = prompt
    panel.directoryURL = start
    return panel.runModal() == .OK ? panel.url : nil
}
