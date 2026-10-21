import AppKit
import QuickLook
import SwiftUI

/// Read-only browser of a course folder: Finder icons, Quick Look (Space), open with the default app
/// (double-click or Return). It never moves, renames or deletes anything.
struct FilesView: View {
    let files: CourseFiles

    @State private var selection: Set<URL> = []
    @State private var search = ""
    @State private var quickLook: URL?

    private var allFiles: [FileNode] { CourseFiles.flatten(files.tree).filter { !$0.isFolder } }

    private var results: [FileNode] {
        allFiles.filter { $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                SearchField(text: $search, prompt: "Search files")
                    .frame(maxWidth: 320)
                Spacer()
                Text("\(allFiles.count) files").font(Theme.Font.caption).foregroundStyle(.secondary)
                IconButton(title: "Open Folder in Finder", systemImage: "folder") { NSWorkspace.shared.open(files.folder) }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            Divider()

            List(selection: $selection) {
                if search.isEmpty {
                    OutlineGroup(files.tree, children: \.children) { node in
                        FileRow(node: node).tag(node.url)
                    }
                } else {
                    ForEach(results) { node in
                        FileRow(node: node, showsParent: true).tag(node.url)
                    }
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()
            .contextMenu(forSelectionType: URL.self) { urls in
                Button("Open") { open(urls) }
                Button("Quick Look") { quickLook = urls.first }
                Divider()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(urls)) }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(urls.map { $0.path(percentEncoded: false) }.joined(separator: "\n"), forType: .string)
                }
            } primaryAction: { urls in
                open(urls)
            }
            .onKeyPress(.space) {
                guard let first = selection.first else { return .ignored }
                quickLook = quickLook == nil ? first : nil
                return .handled
            }
            .quickLookPreview($quickLook, in: allFiles.map(\.url))
        }
    }

    private func open(_ urls: Set<URL>) {
        for url in urls {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if !isFolder { NSWorkspace.shared.open(url) }
        }
    }
}

private struct FileRow: View {
    let node: FileNode
    var showsParent = false

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(node.name).lineLimit(1).truncationMode(.middle)
                if showsParent {
                    Text(node.url.deletingLastPathComponent().lastPathComponent)
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !node.isFolder, let date = modified {
                Text(date.agenda(.dateTime.day().month(.abbreviated).year()))
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .help(node.url.path(percentEncoded: false))
    }

    private var modified: Date? {
        try? node.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
