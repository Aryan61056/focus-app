import SwiftUI
import FocusLinkNet

/// Words for each state. Calm, second person, and never naming what you drifted to: the Mac does not know it as a fact, and a
/// false accusation costs more than a miss.
extension SessionState.Phase {
    var label: LocalizedStringKey {
        switch self {
        case .idle: "Ready"
        case .onTask: "On task"
        case .unsure: "Not sure"
        case .drifting: "Drifting"
        case .recovering: "Getting back"
        case .paused: "Paused"
        case .onBreak: "On a break"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "circle"
        case .onTask: "checkmark.circle"
        case .unsure: "questionmark.circle"
        case .drifting: "arrow.uturn.left.circle"
        case .recovering: "arrow.trianglehead.clockwise"
        case .paused: "pause.circle"
        case .onBreak: "cup.and.saucer"
        }
    }

    func detail(task: String) -> LocalizedStringKey? {
        switch self {
        case .unsure: "Focus can't tell about this one. Nothing happens unless it keeps up."
        case .drifting: "This doesn't look like \(task). Head back when you're ready."
        case .recovering: "Nice. Getting back to \(task)."
        case .onBreak: "Take your time. Your session is waiting."
        default: nil
        }
    }

    var tint: Color { self == .drifting ? Palette.drift : self == .onTask || self == .recovering ? Palette.accent : Palette.ink2 }
}
