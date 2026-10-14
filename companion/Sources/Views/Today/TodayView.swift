import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showPairing = false

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop(phase: model.state.phase)
                ScrollView {
                    Group {
                        if model.connection == .unpaired { UnpairedView(onAdd: { showPairing = true }) }
                        else if model.state.isActive { ActiveSessionView() }
                        else { ReadyView() }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { ConnectionChip() } }
            .toolbarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showPairing) { PairingView() }
        .driftFeedback(model.driftCount)
    }
}
