import SwiftUI

enum AppTab: String, Hashable { case today, insights, mac }

struct RootView: View {
    @State private var tab = AppTab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .today

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "timer", value: AppTab.today) { TodayView() }
            Tab("Insights", systemImage: "chart.bar.xaxis", value: AppTab.insights) { InsightsView() }
            Tab("Mac", systemImage: "macbook.and.iphone", value: AppTab.mac) { MacView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .selectionFeedback(tab)
    }
}
