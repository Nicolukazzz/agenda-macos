import AgendaCore
import SwiftData
import SwiftUI

/// What a search result leads to. The sheet closes and the caller opens it.
enum SearchTarget {
    case task(TaskItem)
    /// The calendar's week on this day.
    case event(Date)
    case note(URL, Area)
}

/// ⌘K: one field over tasks, events and the notes of every course. Return opens the first result.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    let semester: Semester
    var onOpen: (SearchTarget) -> Void

    @Query private var tasks: [TaskItem]
    @Query private var blocks: [Block]
    @State private var query = ""
    @State private var notes: [IndexedNote] = []

    private let math = CalendarMath()
    private static let perSection = 8

    /// A note's text, read once when the sheet opens.
    struct IndexedNote: Sendable {
        let url: URL
        let title: String
        let text: String
        let areaID: PersistentIdentifier
    }

    var body: some View {
        let results = results
        SheetScaffold(eyebrow: "Search", width: 620) {
            SearchField(text: $query, prompt: "Tasks, events and notes", autofocus: true)
                .onSubmit { if let first = results.first { open(first.target) } }
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Searches titles, notes, places and the text of every note in your courses. Return opens the first result.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
            } else if results.isEmpty {
                EmptyState(title: "No Results", systemImage: "magnifyingglass", message: "Nothing matches “\(query)”.")
                    .frame(height: 220)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        section("Tasks", results.filter { $0.kind == .task })
                        section("Events", results.filter { $0.kind == .event })
                        section("Notes", results.filter { $0.kind == .note })
                    }
                }
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            ActionBar(primaryTitle: "Done") { dismiss() }
        }
        .task { notes = await Self.index(semester.sortedAreas) }
    }

    // MARK: Results

    private struct Result: Identifiable {
        enum Kind { case task, event, note }
        let id: String
        let kind: Kind
        let title: String
        let detail: String
        let colorHex: String
        let icon: String
        let target: SearchTarget
    }

    private var results: [Result] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return taskResults(query) + eventResults(query) + noteResults(query)
    }

    private func taskResults(_ query: String) -> [Result] {
        tasks
            .filter { task in
                guard task.area.map({ $0.semester?.isActive == true }) ?? true else { return false }
                return SearchText.matches(task.title, query) || SearchText.matches(task.notes, query)
            }
            .sorted(by: TaskListView.order)
            .prefix(Self.perSection)
            .map { task in
                let due = task.dueDate.map { $0.agenda(task.dueHasTime ? .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute() : .dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
                let detail = [task.isDone ? "Done" : due, task.area?.name, SearchText.snippet(task.notes, query)].compactMap { $0 }.joined(separator: " · ")
                return Result(id: "t\(CalendarFeed.key(for: task))", kind: .task, title: task.title, detail: detail,
                              colorHex: task.displayColorHex, icon: task.isDone ? "checkmark.circle.fill" : "circle", target: .task(task))
            }
    }

    /// One result per event or series, dated on its next occurrence (or its last one, if all are past).
    private func eventResults(_ query: String) -> [Result] {
        let now = Date.now
        let ahead = DateInterval(start: math.startOfDay(now), end: math.add(days: 200, to: now))
        return blocks
            .filter { block in
                guard block.area.map({ $0.semester?.isActive == true }) ?? true else { return false }
                return [block.title, block.location, block.notes].contains { SearchText.matches($0, query) }
            }
            .map { block in (block, CalendarFeed.items(for: [block], in: ahead, breaks: semester.breaks, math: math).first?.start ?? block.start) }
            .sorted { ($0.1 < now ? 1 : 0, abs($0.1.timeIntervalSince(now))) < ($1.1 < now ? 1 : 0, abs($1.1.timeIntervalSince(now))) }
            .prefix(Self.perSection)
            .map { block, date in
                let when = block.isAllDay ? date.agenda(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    : date.agenda(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                let detail = [block.recurrence != nil ? "\(when), every week" : when, block.location.isEmpty ? nil : block.location]
                    .compactMap { $0 }.joined(separator: " · ")
                return Result(id: "e\(CalendarFeed.key(for: block))", kind: .event, title: block.title, detail: detail,
                              colorHex: block.area?.colorHex ?? Theme.Palette.noAreaHex, icon: "calendar", target: .event(date))
            }
    }

    private func noteResults(_ query: String) -> [Result] {
        let areas = Dictionary(uniqueKeysWithValues: semester.sortedAreas.map { ($0.persistentModelID, $0) })
        return notes
            .filter { SearchText.matches($0.title, query) || SearchText.matches($0.text, query) }
            .prefix(Self.perSection)
            .compactMap { note in
                guard let area = areas[note.areaID] else { return nil }
                let detail = [area.name, SearchText.snippet(note.text, query)].compactMap { $0 }.joined(separator: " · ")
                return Result(id: "n\(note.url.path(percentEncoded: false))", kind: .note, title: note.title, detail: detail,
                              colorHex: area.colorHex, icon: "note.text", target: .note(note.url, area))
            }
    }

    private func section(_ title: String, _ items: [Result]) -> some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionHeader(title, detail: "\(items.count)")
                    Card {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { CardDivider() }
                            Button { open(item.target) } label: {
                                CardRow(icon: item.icon, iconColor: Color(hex: item.colorHex)) {
                                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                        Text(item.title).lineLimit(1)
                                        if !item.detail.isEmpty {
                                            Text(item.detail).font(Theme.Font.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                                .hoverHighlight()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func open(_ target: SearchTarget) {
        dismiss()
        onOpen(target)
    }

    // MARK: Note index

    /// Reads every `.md` in each course's `Notas/` off the main thread. Files are capped so a huge one can't stall it.
    private static func index(_ areas: [Area]) async -> [IndexedNote] {
        let folders = areas.compactMap { area in
            area.folderURL.map { ($0.appending(path: NoteNaming.notesFolderName, directoryHint: .isDirectory), area.persistentModelID) }
        }
        return await Task.detached(priority: .userInitiated) {
            folders.flatMap { folder, areaID -> [IndexedNote] in
                let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                return files.filter { $0.pathExtension.lowercased() == "md" }.compactMap { url in
                    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
                    defer { try? handle.close() }
                    let text = (try? handle.read(upToCount: 256 * 1024)).map { String(decoding: $0, as: UTF8.self) } ?? ""
                    return IndexedNote(url: url, title: NoteNaming.displayTitle(fileName: url.lastPathComponent, contents: text), text: text, areaID: areaID)
                }
            }
        }.value
    }
}
