import AppKit
import SwiftUI

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

/// Small color dot used next to course names.
struct AreaDot: View {
    let hex: String
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(Color(hex: hex).gradient)
            .frame(width: size, height: size)
    }
}

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
