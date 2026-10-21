import AgendaCore
import AppKit
import SwiftData
import SwiftUI

@main
struct PlanificadorApp: App {
    @State private var store = StoreLoader.load()
    @State private var appState = AppState()

    var body: some Scene {
        Window("Agenda", id: "main") {
            switch store {
            case .success(let container):
                RootView()
                    .environment(appState)
                    .modelContainer(container)
            case .failure(let error):
                StoreErrorView(error: error, backup: BackupService.latestBackup(classesRoot: appState.classesRootURL)) { backup in
                    store = StoreLoader.recover(from: backup)
                }
            }
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands { AgendaCommands(appState: appState) }

        Settings {
            if case .success(let container) = store {
                AgendaSettingsView()
                    .environment(appState)
                    .modelContainer(container)
            }
        }
    }
}

/// Menu bar: navigation (⌘1–3), new task/event, backups.
struct AgendaCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { appState.pendingCommand = .newTask }
                .keyboardShortcut("n")
            Button("New Event") { appState.pendingCommand = .newEvent }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandGroup(after: .importExport) {
            Button("Back Up Now") { appState.pendingCommand = .backUpNow }
            Button("Export Backup…") { appState.pendingCommand = .exportBackup }
            Button("Import Backup…") { appState.pendingCommand = .importBackup }
        }
        CommandMenu("Go") {
            Button("Today") { appState.selection = .today }.keyboardShortcut("1")
            Button("Calendar") { appState.selection = .calendar }.keyboardShortcut("2")
            Button("Tasks") { appState.selection = .tasks }.keyboardShortcut("3")
            Divider()
            Button("Month") {
                appState.selection = .calendar
                appState.calendarMode = .month
            }
            .keyboardShortcut("m", modifiers: [.command, .control])
            Button("Week") {
                appState.selection = .calendar
                appState.calendarMode = .week
            }
            .keyboardShortcut("w", modifiers: [.command, .control])
        }
    }
}

/// Opens the SwiftData store in Application Support (never in iCloud or in the classes folder).
enum StoreLoader {
    static var storeURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "com.nicolas.agenda", directoryHint: .isDirectory)
            .appending(path: "Agenda.store")
    }

    static func load() -> Result<ModelContainer, Error> {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let schema = Schema(AgendaSchema.models)
            let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            return .success(try ModelContainer(for: schema, configurations: configuration))
        } catch {
            return .failure(error)
        }
    }

    /// Moves the unreadable store aside (kept, never deleted) and rebuilds it from a backup.
    static func recover(from backupURL: URL) -> Result<ModelContainer, Error> {
        do {
            let backup = try AgendaBackup.decode(Data(contentsOf: backupURL))
            let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
            let folder = storeURL.deletingLastPathComponent()
            for suffix in ["", "-shm", "-wal"] {
                let file = folder.appending(path: "Agenda.store\(suffix)")
                if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                    try FileManager.default.moveItem(at: file, to: folder.appending(path: "Agenda.store\(suffix).broken-\(stamp)"))
                }
            }
            let result = load()
            if case .success(let container) = result {
                try BackupService.restore(backup, into: container.mainContext)
            }
            return result
        } catch {
            return .failure(error)
        }
    }
}

/// Shown instead of an empty app when the database can't be opened, so data loss is never silent.
struct StoreErrorView: View {
    let error: Error
    let backup: URL?
    var onRestore: (URL) -> Void

    var body: some View {
        ContentUnavailableView {
            Label("The database couldn’t be opened", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Your data hasn’t been deleted. File: \(StoreLoader.storeURL.path(percentEncoded: false))\n\n\(error.localizedDescription)")
                .textSelection(.enabled)
        } actions: {
            if let backup {
                Button("Restore \(backup.lastPathComponent)") { onRestore(backup) }
                    .primaryAction()
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([StoreLoader.storeURL])
            }
            .secondaryAction()
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
