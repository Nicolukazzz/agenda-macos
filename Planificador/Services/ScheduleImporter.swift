import AgendaCore
import Foundation
import OSLog
import SwiftData

/// Imports timetables dropped as JSON into `Application Support/com.nicolas.agenda/Imports/`.
/// Runs at launch; each file is applied once and then moved to `Imports/Done/`.
/// Re-importing the same slots is a no-op, so a file can never duplicate classes.
@MainActor
enum ScheduleImporter {
    private static let log = Logger(subsystem: "com.nicolas.agenda", category: "ScheduleImporter")

    static var inbox: URL { StoreLoader.storeURL.deletingLastPathComponent().appending(path: "Imports", directoryHint: .isDirectory) }

    static func importPending(into semester: Semester, context: ModelContext) {
        guard !AppEnvironment.isPreview else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []
        for url in files {
            do {
                let file = try JSONDecoder().decode(ScheduleImportFile.self, from: Data(contentsOf: url))
                let added = try apply(file, to: semester, context: context)
                log.info("Imported \(added) class slots from \(url.lastPathComponent, privacy: .public)")
                try archive(url)
            } catch {
                log.error("Schedule import failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    enum ImportError: LocalizedError {
        case wrongSemester(String)
        case invalid([String])

        var errorDescription: String? {
            switch self {
            case .wrongSemester(let name): "File is for semester \(name), not the active one."
            case .invalid(let problems): problems.joined(separator: "; ")
            }
        }
    }

    /// Returns how many new blocks were created.
    @discardableResult
    static func apply(_ file: ScheduleImportFile, to semester: Semester, context: ModelContext, math: CalendarMath = CalendarMath()) throws -> Int {
        guard file.semester == semester.name else { throw ImportError.wrongSemester(file.semester) }
        let areas = semester.sortedAreas
        let problems = file.problems(knownTags: Set(areas.map(\.tag)))
        guard problems.isEmpty else { throw ImportError.invalid(problems) }

        var added = 0
        for slot in file.slots {
            guard
                let area = areas.first(where: { $0.tag == slot.tag }),
                let start = ScheduleImportFile.minutes(from: slot.start),
                let end = ScheduleImportFile.minutes(from: slot.end)
            else { continue }
            let weekdays = Set(slot.weekdays)
            let room = slot.room ?? ""
            let exists = area.blocks.contains { block in
                block.recurrence?.weekdays == weekdays
                    && math.minutesIntoDay(block.start) == start
                    && math.minutesIntoDay(block.end) == end
                    && block.location == room
            }
            guard !exists else { continue }
            context.insert(ClassSchedule.makeBlock(
                area: area, semester: semester, weekdays: weekdays,
                startMinutes: start, endMinutes: end, location: room, math: math))
            added += 1
        }
        try context.save()
        return added
    }

    private static func archive(_ url: URL) throws {
        let done = inbox.appending(path: "Done", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: done, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
        try FileManager.default.moveItem(at: url, to: done.appending(path: "\(stamp)-\(url.lastPathComponent)"))
    }
}
