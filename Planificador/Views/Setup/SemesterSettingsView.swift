import AgendaCore
import SwiftData
import SwiftUI

/// Term dates and recess ranges (weeks off, holidays) where classes don't happen.
struct SemesterSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var semester: Semester

    @State private var newBreakStart = Date.now
    @State private var newBreakEnd = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Semestre \(semester.name)").font(.title3.weight(.semibold))
            Form {
                Section {
                    LabeledContent("Periodo", value: periodText)
                } footer: {
                    Text("Cada semestre ocupa su mitad del año; tus clases fijas se repiten dentro de ese periodo.")
                }
                Section {
                    if semester.breaks.isEmpty {
                        Text("Sin recesos").foregroundStyle(.secondary)
                    }
                    ForEach(Array(semester.breaks.enumerated()), id: \.offset) { index, range in
                        HStack {
                            Text(format(range))
                            Spacer()
                            Button(role: .destructive) {
                                semester.breaks.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                    }
                    HStack {
                        DatePicker("Desde", selection: $newBreakStart, displayedComponents: .date)
                        DatePicker("Hasta", selection: $newBreakEnd, in: newBreakStart..., displayedComponents: .date)
                        Button("Agregar") { addBreak() }
                    }
                } header: {
                    Text("Recesos y festivos")
                } footer: {
                    Text("Opcional. Las clases fijas no aparecen en estos días (semana de receso, festivos).")
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Listo") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560, height: 520)
    }

    private func addBreak() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: newBreakStart)
        // Inclusive of the last day.
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: newBreakEnd)) ?? start
        semester.breaks.append(DateInterval(start: start, end: max(start, end)))
        semester.breaks.sort { $0.start < $1.start }
    }

    private var periodText: String {
        let style = Date.FormatStyle(date: .long, time: .omitted)
        return "\(semester.startDate.formatted(style)) – \(semester.endDate.formatted(style))"
    }

    private func format(_ range: DateInterval) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        let lastDay = range.end.addingTimeInterval(-1)
        return "\(range.start.formatted(style)) – \(lastDay.formatted(style))"
    }
}
