import AgendaCore
import SwiftData
import SwiftUI

// Every design component on one canvas. Check here first when changing a component:
// whatever looks right here looks right everywhere in the app.

#Preview("Component Gallery") {
    @Previewable @State var date = Date.now
    @Previewable @State var end = Date.now.addingTimeInterval(3600)
    @Previewable @State var days: Set<Int> = [3, 5]
    @Previewable @State var on = true
    @Previewable @State var text = ""
    @Previewable @State var hex = CoursePalette.color(at: 2)
    @Previewable @State var area: Area? = nil

    let areas = try! PreviewData.container.mainContext.fetch(FetchDescriptor<Area>(sortBy: [SortDescriptor(\.sortOrder)]))

    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            PageHeader(title: "Page Header", subtitle: "Subtitle") {
                AreaBadge(name: "BD", colorHex: CoursePalette.color(at: 0))
            } trailing: {
                TagPill(tag: "bd", colorHex: CoursePalette.color(at: 0))
                IconButton(title: "Edit", systemImage: "pencil") {}
            }

            SectionHeader("Identity")
            HStack(spacing: Theme.Space.m) {
                AreaDot(hex: hex)
                AreaBadge(name: "Sistemas", colorHex: hex)
                TagPill(tag: "so", colorHex: hex)
                TagPill(tag: "so", colorHex: hex, compact: true)
                ColorSwatchPicker(hex: $hex)
            }

            SectionHeader("Chips")
            CourseChips(selection: $area, areas: areas)
            DurationChips(start: date, end: $end)

            SectionHeader("Card")
            Card {
                CardRow(icon: "calendar") { Text("Day"); Spacer(); DatePill(date: $date, showsIcon: false) }
                CardDivider()
                CardRow(icon: "clock") { Text("Time"); Spacer(); TimePill(time: $date, showsIcon: false) }
                CardDivider()
                CardRow(icon: "repeat") { CardToggle(title: "Repeats every week", isOn: $on) }
                CardDivider()
                CardRow(icon: "calendar.day.timeline.left") { WeekdayCircles(selection: $days) }
                CardDivider()
                CardRow(icon: "mappin.and.ellipse") { CardTextField(placeholder: "Location", text: $text) }
                CardNote(text: "Card note explains the row above.")
            }

            SectionHeader("Pickers")
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                MonthPicker(date: $date)
                TimeList(time: $date, step: 15) {}.frame(height: 220)
            }

            SectionHeader("Feedback")
            Banner(title: "Banner title", message: "/path/to/folder") { Button("Action") {}.buttonStyle(.glass) }
            ValidationMessage(text: "Validation message")

            SectionHeader("Rewards")
            HStack(spacing: Theme.Space.l) {
                CheckCircle(isOn: false, colorHex: hex, size: 17) {}
                CheckCircle(isOn: true, colorHex: hex, size: 17) {}
                ProgressRing(progress: 0.6).frame(width: 34, height: 34)
            }
            DayProgressCard(done: 2, total: 5)
            DayProgressCard(done: 5, total: 5)

            SectionHeader("Peek")
            HStack(alignment: .top, spacing: Theme.Space.l) {
                if let task = try? PreviewData.container.mainContext.fetch(FetchDescriptor<TaskItem>()).first {
                    TaskPeek(task: task).padding(Theme.Space.l).frame(width: Theme.Size.peekWidth).background(.background, in: .rect(cornerRadius: Theme.Radius.card))
                }
            }

            SectionHeader("Actions")
            ActionBar(destructiveTitle: "Delete", primaryTitle: "Save") {}
        }
        .padding(Theme.Space.xl)
    }
    .frame(width: 760, height: 1500)
    .modelContainer(PreviewData.container)
}
