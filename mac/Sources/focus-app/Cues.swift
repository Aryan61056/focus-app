import AppKit
import AVFoundation
import FocusUI

/// A tap on the trackpad. macOS only plays it on a Force Touch trackpad while a finger rests on it, so this is a bonus cue.
enum Haptics {
    @MainActor static func play(_ p: HapticPattern) {
        for delay in p.taps {
            if delay == 0 { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) } }
        }
    }
}

/// The Mac's own voice. System voices run on this Mac; nothing is sent anywhere. One line at a time, and a new line replaces one still playing.
@MainActor final class Voice {
    private let synth = AVSpeechSynthesizer()
    func say(_ text: String) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier.replacingOccurrences(of: "_", with: "-")) ?? AVSpeechSynthesisVoice(language: "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        u.volume = 0.7
        synth.speak(u)
    }
}
