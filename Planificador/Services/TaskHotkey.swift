import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global "new task" hotkey. No default: the user picks one in Settings.
    static let newTask = Self("newTask")
}

/// From any app: bring Agenda forward with the one-line New Task sheet open (the same one as ⌘N).
@MainActor
enum TaskHotkey {
    static let url = URL(string: "agenda://task/new")!

    static func listen() {
        KeyboardShortcuts.onKeyUp(for: .newTask) { NSWorkspace.shared.open(url) }
    }
}
