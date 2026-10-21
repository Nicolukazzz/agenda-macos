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
                StoreErrorView(error: error)
            }
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
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
}

/// Shown instead of an empty app when the database can't be opened, so data loss is never silent.
struct StoreErrorView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("The database couldn’t be opened", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Your data hasn’t been deleted. File: \(StoreLoader.storeURL.path(percentEncoded: false))\n\n\(error.localizedDescription)")
                .textSelection(.enabled)
        } actions: {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([StoreLoader.storeURL])
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
