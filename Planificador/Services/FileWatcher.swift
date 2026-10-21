import Foundation

/// Calls `onChange` when a file or directory changes on disk (written, renamed, deleted).
/// Re-arms itself after atomic saves, which replace the file and invalidate the old descriptor.
@MainActor
final class FileWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var debounce: Task<Void, Never>?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        arm()
    }

    isolated deinit {
        source?.cancel()
        debounce?.cancel()
    }

    private func arm() {
        source?.cancel()
        let descriptor = open(url.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func changed() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            self.arm()
            self.onChange()
        }
    }
}
