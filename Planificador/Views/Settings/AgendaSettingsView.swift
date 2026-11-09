import AgendaCore
import AppKit
import KeyboardShortcuts
import SwiftData
import SwiftUI

/// App settings (⌘,): classes folder, week view hours, backups.
struct AgendaSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("weekFirstHour") private var firstHour = 6
    @AppStorage("weekLastHour") private var lastHour = 23
    @AppStorage(MoneySettings.rateKey) private var copPerUSD = MoneySettings.defaultRate

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
                SectionHeader("Money")
                Card {
                    CardRow(icon: "dollarsign.arrow.circlepath") {
                        Text("Pesos per dollar")
                        Spacer()
                        TextField("4000", value: $copPerUSD, format: .number.precision(.fractionLength(0...2)))
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 120)
                    }
                    CardNote(text: "Agenda is offline, so update this when the dollar moves. New entries save the rate of their day; past months keep theirs.")
                    CardDivider()
                    CardRow(icon: "keyboard") {
                        Text("Log expense from anywhere")
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .logMoney)
                    }
                    CardNote(text: "Press it in any app to open Agenda's Add Expense form. Pick a combination nothing else uses, like ⌃⌥M.")
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader("Reminders")
                Card {
                    CardRow(icon: "checklist", iconColor: appState.reminders.access == .granted ? .accentColor : .secondary) {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(remindersTitle)
                            Text(remindersDetail).font(Theme.Font.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        switch appState.reminders.access {
                        case .notDetermined:
                            Button("Allow Access") { Task { await appState.reminders.requestAccess() } }
                                .buttonStyle(.glass)
                        case .granted:
                            Button("Sync Now") { appState.reminders.schedule(delay: .zero) }
                                .buttonStyle(.glass)
                        case .denied:
                            Button("Open Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    CardNote(text: "Tasks with “Create reminder” on go to your Reminders list and sync both ways. Open reminders made on the iPhone come in as tasks; deleting one there deletes the task here.")
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
        .frame(width: 600, height: 660)
    }

    private var remindersTitle: String {
        switch appState.reminders.access {
        case .granted: "Connected"
        case .notDetermined: "Not connected"
        case .denied: "No access"
        }
    }

    private var remindersDetail: String {
        if let error = appState.reminders.lastError { return "Last sync failed: \(error)" }
        if let last = appState.reminders.lastSync { return "Last sync: \(last.agenda(date: .omitted, time: .shortened))" }
        return appState.reminders.access == .denied ? "Allow Agenda in Privacy & Security" : "Syncs while Agenda is open"
    }

    private var latestText: String {
        guard let url = BackupService.latestBackup(classesRoot: appState.classesRootURL) else { return "No backups yet" }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        return "Last: \(date.agenda(date: .abbreviated, time: .shortened))"
    }
}
