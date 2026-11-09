import SwiftUI

/// The task form shared by the task editor and by "New Task" in the calendar, so both offer the same
/// options: due date and time, priority, "Create reminder" and notes. `extra` sits between the
/// reminder and the notes (the editor puts subtasks and work blocks there).
struct TaskFormCards<Extra: View>: View {
    @Environment(AppState.self) private var appState
    @Binding var hasDue: Bool
    @Binding var dueDay: Date
    @Binding var dueTime: Date
    @Binding var hasTime: Bool
    @Binding var priority: Int
    @Binding var createsReminder: Bool
    @Binding var notes: String
    @ViewBuilder var extra: Extra

    var body: some View {
        Card {
            CardRow(icon: "calendar", iconColor: hasDue ? .accentColor : .secondary) {
                CardToggle(title: "Due date", isOn: $hasDue)
            }
            if hasDue {
                CardDivider()
                CardRow(icon: "calendar.badge.exclamationmark") {
                    Text("Day")
                    Spacer()
                    DatePill(date: $dueDay, showsIcon: false)
                }
                CardDivider()
                CardRow(icon: "clock", iconColor: hasTime ? .accentColor : .secondary) {
                    Text("Time")
                    Spacer()
                    if hasTime {
                        TimePill(time: $dueTime, showsIcon: false)
                    }
                    Toggle("Time", isOn: $hasTime).toggleStyle(.switch).labelsHidden()
                }
            }
            CardDivider()
            CardRow(icon: "exclamationmark.circle") {
                Text("Priority")
                Spacer()
                Chip(title: "None", isSelected: priority == 0) { priority = 0 }
                Chip(title: "! High", colorHex: "#F0A33A", isSelected: priority == 1, showsDot: false) { priority = 1 }
                Chip(title: "!! Urgent", colorHex: "#E5534B", isSelected: priority == 2, showsDot: false) { priority = 2 }
            }
        }

        Card {
            CardRow(icon: "checklist", iconColor: createsReminder ? .accentColor : .secondary) {
                CardToggle(title: "Create reminder", isOn: $createsReminder)
            }
            if createsReminder {
                CardNote(text: reminderNote)
            }
        }
        .animation(Theme.Motion.snappy, value: createsReminder)
        .onChange(of: createsReminder) {
            if createsReminder { Task { await appState.reminders.requestAccess() } }
        }

        extra

        Card {
            CardRow(icon: "text.alignleft") { CardTextField(placeholder: "Notes", text: $notes, axis: .vertical) }
        }
    }

    private var reminderNote: String {
        switch appState.reminders.access {
        case .granted: "Synced with Reminders and your iPhone. Turning this off removes the reminder."
        case .notDetermined: "Agenda will ask for access to Reminders."
        case .denied: "Agenda can’t reach Reminders. Allow it in System Settings › Privacy & Security › Reminders."
        }
    }
}

extension TaskFormCards where Extra == EmptyView {
    init(hasDue: Binding<Bool>, dueDay: Binding<Date>, dueTime: Binding<Date>, hasTime: Binding<Bool>,
         priority: Binding<Int>, createsReminder: Binding<Bool>, notes: Binding<String>) {
        self.init(hasDue: hasDue, dueDay: dueDay, dueTime: dueTime, hasTime: hasTime,
                  priority: priority, createsReminder: createsReminder, notes: notes) { EmptyView() }
    }
}
