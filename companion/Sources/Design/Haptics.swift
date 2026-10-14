import SwiftUI

/// Haptics fire from the event that caused them, in the same frame as the visual change. Few, and each with a meaning:
/// a soft tap for a command sent, success for a session that started or a pairing that worked, a warning for a drift.
extension View {
    func tapFeedback<T: Equatable>(_ trigger: T) -> some View { sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: trigger) }
    func successFeedback<T: Equatable>(_ trigger: T) -> some View { sensoryFeedback(.success, trigger: trigger) }
    func selectionFeedback<T: Equatable>(_ trigger: T) -> some View { sensoryFeedback(.selection, trigger: trigger) }
    func driftFeedback<T: Equatable>(_ trigger: T) -> some View { sensoryFeedback(.warning, trigger: trigger) }
}
