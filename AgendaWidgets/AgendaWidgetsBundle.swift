import SwiftUI
import WidgetKit

@main
struct AgendaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MoneySummaryWidget()
        MoneyQuickLogWidget()
    }
}
