import SwiftUI

enum AppTab: String, Hashable { case today, insights, block, mac }

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = AppTab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .today

    var body: some View {
        @Bindable var model = model
        TabView(selection: $tab) {
            Tab("Today", systemImage: "timer", value: AppTab.today) { TodayView() }
            Tab("Insights", systemImage: "chart.bar.xaxis", value: AppTab.insights) { InsightsView() }
            Tab("Block", systemImage: "shield.lefthalf.filled", value: AppTab.block) { BlockView() }
            Tab("Mac", systemImage: "macbook.and.iphone", value: AppTab.mac) { MacView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .selectionFeedback(tab)
        .successFeedback(model.pairedCount)
        .onOpenURL { model.open($0) }
        .fullScreenCover(isPresented: $model.showingGuard) { GuardBounceView() }
        .overlay(alignment: .top) { LinkingBanner().padding(.top, 4) }
        .sheet(isPresented: $model.showPairingSheet, onDismiss: { model.dismissLinking() }) { PairingView(prefill: model.pendingCode) }
        // Only .background: .inactive also happens when you pull down Control Center, which is not leaving.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.leftApp() } else if phase == .active { model.cameBack() }
        }
    }
}
