import AgendaCore
import SwiftData
import SwiftUI

enum BlockEditorTarget: Identifiable {
    case new(start: Date, end: Date, area: Area?)
    case existing(CalendarItem)

    var id: String {
        switch self {
        case .new(let start, _, _): "new-\(start.timeIntervalSinceReferenceDate)"
        case .existing(let item): item.id
        }
    }
}

/// Create or edit a calendar block. `#tag` in the title assigns the area.
struct BlockEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let target: BlockEditorTarget
    let semester: Semester

    @State private var title = ""
    @State private var area: Area?
    @State private var day = Date.now
    @State private var startTime = Date.now
    @State private var endTime = Date.now
    @State private var repeats = false
    @State private var weekdays: Set<Int> = []
    @State private var location = ""
    @State private var notes = ""
    @State private var askingScope = false
    @State private var askingDeleteScope = false
    /// Validation messages appear only after a save attempt, never on an untouched form.
    @State private var triedToSave = false

    private let math = CalendarMath()

    private var existing: CalendarItem? {
        if case .existing(let item) = target { return item }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack {
                Text(existing == nil ? "New Event" : "Edit Event").font(Theme.Font.pageTitle)
                Spacer()
                if let area {
                    TagPill(tag: area.tag, colorHex: area.colorHex)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                TagCompletionField(placeholder: "Title (use #course)", text: $title, areas: semester.sortedAreas, onSubmit: attemptSave)
                Text("Type # to pick a course.").font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            .zIndex(1)

            Form {
                LabeledContent("Course") { AreaPicker(selection: $area, areas: semester.sortedAreas) }
                DatePicker("Day", selection: $day, displayedComponents: .date)
                DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: $endTime, displayedComponents: .hourAndMinute)
                Toggle("Repeats every week", isOn: $repeats.animation(Theme.Motion.snappy))
                if repeats {
                    LabeledContent("Days") {
                        HStack(spacing: Theme.Space.xs) {
                            ForEach(Weekdays.order, id: \.self) { weekday in
                                Toggle(Weekdays.short(weekday), isOn: binding(for: weekday))
                                    .toggleStyle(.button)
                            }
                        }
                    }
                    Text("Until the end of semester \(semester.name). Skips breaks.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                TextField("Location", text: $location)
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            if let problem, triedToSave || newEnd <= newStart {
                Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout)
            }

            HStack {
                if existing != nil {
                    Button("Delete", role: .destructive) {
                        if existing?.isRecurring == true { askingDeleteScope = true } else { deleteNow(.allEvents) }
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { attemptSave() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: load)
        .confirmationDialog("This event repeats", isPresented: $askingScope) {
            Button("Only This Event") { save(.onlyThis) }
            Button("All Events") { save(.allEvents) }
        } message: {
            Text("Apply the changes to this day only, or to the whole series?")
        }
        .confirmationDialog("This event repeats", isPresented: $askingDeleteScope) {
            Button("Delete Only This Event", role: .destructive) { deleteNow(.onlyThis) }
            Button("Delete All Events", role: .destructive) { deleteNow(.allEvents) }
        }
    }

    // MARK: State

    private func binding(for weekday: Int) -> Binding<Bool> {
        Binding(
            get: { weekdays.contains(weekday) },
            set: { isOn in if isOn { weekdays.insert(weekday) } else { weekdays.remove(weekday) } })
    }

    private func load() {
        switch target {
        case .new(let start, let end, let preset):
            day = start
            startTime = start
            endTime = end
            area = preset
            weekdays = [math.calendar.component(.weekday, from: start)]
        case .existing(let item):
            let block = item.block
            title = block.title
            area = block.area
            day = item.start
            startTime = item.start
            endTime = item.end
            repeats = block.recurrence != nil
            weekdays = block.recurrence?.weekdays ?? [math.calendar.component(.weekday, from: item.start)]
            location = block.location
            notes = block.notes
        }
    }

    private var resolved: (title: String, area: Area?) {
        let known = Set(semester.sortedAreas.map(\.tag))
        let extracted = TagCompletion.extract(from: title, known: known)
        let taggedArea = extracted.tag.flatMap { tag in semester.sortedAreas.first { $0.tag == tag } }
        return (extracted.title.trimmingCharacters(in: .whitespaces), taggedArea ?? area)
    }

    private var newStart: Date { math.date(day, keepingTimeOf: startTime) }
    private var newEnd: Date { math.date(day, keepingTimeOf: endTime) }

    private var problem: String? {
        if resolved.title.isEmpty && resolved.area == nil { return "Enter a title or pick a course." }
        if newEnd <= newStart { return "The end time must be after the start time." }
        if repeats && weekdays.isEmpty { return "Pick at least one day." }
        return nil
    }

    // MARK: Actions

    private func attemptSave() {
        triedToSave = true
        guard problem == nil else { return }
        if existing?.isRecurring == true { askingScope = true } else { save(.allEvents) }
    }

    private func save(_ scope: ChangeScope) {
        let (cleanTitle, finalArea) = resolved
        let finalTitle = cleanTitle.isEmpty ? (finalArea?.name ?? "") : cleanTitle
        let recurrence = repeats ? WeeklyRecurrence(weekdays: weekdays, until: semester.endDate) : nil

        if let item = existing {
            var block = item.block
            if item.isRecurring && scope == .onlyThis {
                block = BlockActions.detach(item, context: context, math: math)
                block.start = newStart
                block.end = newEnd
            } else if item.isRecurring && recurrence != nil {
                BlockActions.reschedule(item, to: newStart, end: newEnd, scope: .allEvents, context: context, math: math)
                block.recurrence = recurrence
            } else {
                block.start = newStart
                block.end = newEnd
                block.recurrence = recurrence
            }
            block.title = finalTitle
            block.area = finalArea
            block.location = location
            block.notes = notes
        } else {
            let block = Block(title: finalTitle, start: newStart, end: newEnd, area: finalArea, recurrence: recurrence, location: location, notes: notes)
            context.insert(block)
        }
        try? context.save()
        dismiss()
    }

    private func deleteNow(_ scope: ChangeScope) {
        guard let item = existing else { return }
        BlockActions.delete(item, scope: scope, context: context, math: math)
        try? context.save()
        dismiss()
    }
}
