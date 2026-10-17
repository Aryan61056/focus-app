import SwiftUI

/// The website's entrance: content rises 18 pt and fades in over about 0.6 s on a strong ease-out, each block a beat after the last.
/// It plays once per launch for a given key, so changing tabs and coming back is quiet. Reduce Motion fades without the rise.
private struct Reveal: ViewModifier {
    var index: Int
    var key: String
    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static var played: Set<String> = []

    init(index: Int, key: String) {
        self.index = index; self.key = key
        _shown = State(initialValue: Self.played.contains(key))
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .onAppear {
                guard !shown else { return }
                Self.played.insert(key)
                // The stagger stops growing after six blocks, so a long page never makes the last one wait.
                let delay = Double(min(index, 6)) * 0.06
                withAnimation(reduceMotion ? .easeOut(duration: 0.2).delay(delay) : .timingCurve(0.23, 1, 0.32, 1, duration: 0.62).delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// `index` is the block's place in the page's stagger; `key` names the page so it only plays the first time it is shown.
    func reveal(_ index: Int = 0, key: String) -> some View { modifier(Reveal(index: index, key: key)) }
}
