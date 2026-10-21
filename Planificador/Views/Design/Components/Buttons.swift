import SwiftUI

// Button roles. Primary = glass prominent (one per screen/sheet), secondary = glass,
// quiet = plain text inside dense content. Use these instead of picking styles per screen.

extension View {
    func primaryAction() -> some View { buttonStyle(.glassProminent).controlSize(.large) }
    func secondaryAction() -> some View { buttonStyle(.glass).controlSize(.large) }
    func toolbarAction() -> some View { buttonStyle(.glass) }
}

/// Footer for sheets and flows: optional destructive action on the left, cancel + primary on the right.
struct ActionBar: View {
    var destructiveTitle: String?
    var onDestructive: () -> Void = {}
    var cancelTitle: String? = "Cancel"
    var onCancel: () -> Void = {}
    let primaryTitle: String
    var primaryDisabled = false
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let destructiveTitle {
                Button(destructiveTitle, systemImage: "trash", role: .destructive, action: onDestructive)
                    .secondaryAction()
            }
            Spacer()
            if let cancelTitle {
                Button(cancelTitle, action: onCancel)
                    .secondaryAction()
                    .keyboardShortcut(.cancelAction)
            }
            Button(primaryTitle, action: onPrimary)
                .primaryAction()
                .keyboardShortcut(.defaultAction)
                .disabled(primaryDisabled)
        }
    }
}

/// Icon-only glass button with a tooltip (used in card rows and headers).
struct IconButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, role: role, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .help(title)
    }
}
