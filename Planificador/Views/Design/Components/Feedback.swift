import SwiftUI

// Messages to the user: empty states, banners and validation.

struct EmptyState: View {
    let title: String
    let systemImage: String
    var message: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        }
    }
}

/// Full-width notice under a header (e.g. a course folder that moved).
struct Banner<Action: View>: View {
    enum Style { case warning, info }

    var style: Style = .warning
    let title: String
    var message: String?
    @ViewBuilder var action: Action

    private var tint: Color { style == .warning ? Theme.Palette.warning : .accentColor }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: style == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).font(Theme.Font.rowDetail.weight(.semibold))
                if let message {
                    Text(message).font(Theme.Font.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            action
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.s + 2)
        .background(tint.opacity(0.12))
    }
}

/// Inline error shown after a failed save attempt.
struct ValidationMessage: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(Theme.Font.rowDetail)
            .foregroundStyle(Theme.Palette.danger)
            .transition(.opacity)
    }
}
