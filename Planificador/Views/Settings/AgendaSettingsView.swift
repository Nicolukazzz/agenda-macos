import AgendaCore
import AppKit
import SwiftData
import SwiftUI

/// App settings (⌘,): classes folder, week view hours, backups.
struct AgendaSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("weekFirstHour") private var firstHour = 6
    @AppStorage("weekLastHour") private var lastHour = 23

    var body: some View {
        PageContent(maxWidth: 560) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader("Classes Folder")
                Card {
                    CardRow(icon: "folder.fill", iconColor: .accentColor) {
                        Text(appState.classesRootPath).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Change…") {
                            if let url = chooseFolder(startingAt: appState.classesRootURL, prompt: "Use This Folder") {
                                appState.classesRootPath = url.path(percentEncoded: false)
                            }
                        }
                        .buttonStyle(.glass)
                    }
                    CardNote(text: "Holds one folder per semester (2026-1, 2026-2…), each with a folder per course.")
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader("Week View")
                Card {
                    CardRow(icon: "sunrise") {
                        Text("Day starts")
                        Spacer()
                        Stepper("\(firstHour):00", value: $firstHour, in: 0...(lastHour - 4))
                            .monospacedDigit()
                    }
                    CardDivider()
                    CardRow(icon: "moon") {
                        Text("Day ends")
                        Spacer()
                        Stepper("\(lastHour):00", value: $lastHour, in: (firstHour + 4)...24)
                            .monospacedDigit()
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader("Backups")
                Card {
                    CardRow(icon: "clock.arrow.circlepath") {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text("Daily, last 14 kept")
                            Text(latestText).font(Theme.Font.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Back Up Now") { appState.pendingCommand = .backUpNow }
                            .buttonStyle(.glass)
                        IconButton(title: "Show Backups in Finder", systemImage: "folder") {
                            let folder = BackupService.folder(classesRoot: appState.classesRootURL)
                            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(folder)
                        }
                    }
                    CardNote(text: "Saved in \(BackupService.folder(classesRoot: appState.classesRootURL).path(percentEncoded: false)). Notes are Markdown files in your course folders and aren’t part of backups.")
                }
            }
        }
        .frame(width: 600, height: 520)
    }

    private var latestText: String {
        guard let url = BackupService.latestBackup(classesRoot: appState.classesRootURL) else { return "No backups yet" }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        return "Last: \(date.agenda(date: .abbreviated, time: .shortened))"
    }
}
