import SwiftUI

/// Springs, named for what they are used for. Everything a finger can touch is a spring so it can be interrupted and reversed;
/// damping stays at 1 (no overshoot) unless the motion carried momentum.
enum Motion {
    /// Layout and state changes.
    static let settle = Animation.smooth(duration: 0.45)
    /// Press feedback: fast enough to feel attached to the finger.
    static let press = Animation.spring(response: 0.22, dampingFraction: 1)
    /// The ring and numbers following the Mac.
    static let follow = Animation.spring(response: 0.7, dampingFraction: 1)
    /// A card the user flicked or a choice that landed: a little give.
    static let land = Animation.spring(response: 0.35, dampingFraction: 0.8)
}

extension View {
    /// Reduce Motion keeps the change but drops the travel: a short fade instead of a spring.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View { modifier(MotionModifier(animation: animation, value: value)) }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View { content.animation(reduceMotion ? .easeInOut(duration: 0.15) : animation, value: value) }
}

/// Scales slightly while pressed, from the moment the finger lands, and springs back when it lifts or slides away.
struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.97
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
