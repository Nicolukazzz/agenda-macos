import AgendaCore
import SwiftData
import SwiftUI

/// Term period and recess ranges (weeks off, holidays) where classes don't happen.
struct SemesterSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var semester: Semester

    @State private var newBreakStart = Date.now
    @State private var newBreakEnd = Date.now

    private let math = CalendarMath()

    var body: some View {
        SheetScaffold(eyebrow: "Semester \(semester.name)") {
            Card {
                CardRow(icon: "calendar") {
                    Text("Period")
                    Spacer()
                    Text(periodText).foregroundStyle(.secondary)
                }
                CardNote(text: "Each semester covers its half of the year; weekly classes repeat within it.")
            }

            SectionHeader("Breaks and Holidays", detail: "Optional")
            Card {
                if semester.breaks.isEmpty {
                    CardRow(icon: "sun.horizon") {
                        Text("No breaks").foregroundStyle(.secondary)
                    }
                }
                ForEach(semester.breaks, id: \.start) { range in
                    CardRow(icon: "sun.horizon") {
                        Text(format(range))
                        Spacer()
                        IconButton(title: "Remove Break", systemImage: "minus", role: .destructive) {
                            withAnimation(Theme.Motion.snappy) { semester.breaks.removeAll { $0 == range } }
                        }
                    }
                    CardDivider()
                }
                CardRow(icon: "plus") {
                    DatePill(date: $newBreakStart, showsIcon: false)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    DatePill(date: $newBreakEnd, showsIcon: false)
                    Spacer()
                    Button("Add") { addBreak() }
                        .buttonStyle(.glass)
                        .disabled(newBreakEnd < newBreakStart)
                }
                CardNote(text: "Weekly classes don’t appear on these days.")
            }
        } footer: {
            ActionBar(cancelTitle: nil, primaryTitle: "Done") { dismiss() }
        }
    }

    private var periodText: String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        return "\(semester.startDate.agenda(style)) – \(semester.endDate.agenda(style))"
    }

    private func addBreak() {
        let start = math.startOfDay(newBreakStart)
        // Inclusive of the last day.
        let end = math.add(days: 1, to: math.startOfDay(newBreakEnd))
        withAnimation(Theme.Motion.snappy) {
            semester.breaks.append(DateInterval(start: start, end: max(start, end)))
            semester.breaks.sort { $0.start < $1.start }
        }
    }

    private func format(_ range: DateInterval) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        return "\(range.start.agenda(style)) – \(range.end.addingTimeInterval(-1).agenda(style))"
    }
}
