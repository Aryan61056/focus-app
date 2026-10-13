import Foundation
import FocusJudge

/// The local checks on an explanation, before the model sees it. They cost nothing and stop the cheap ways through:
/// one word, keyboard mashing, the same word over and over, or a sentence that never mentions what is on the screen.
/// They do not decide whether the explanation is true. That is the on-device model's job, against the window itself (Verification.swift).
public enum OverrideClaim {
    public enum Issue: Equatable, Sendable {
        case tooShort, repetitive, notAboutWindow, injected
        public var message: String {
            switch self {
            case .tooShort: return "Write a sentence or two: what you are doing in this window and how it connects to the task."
            case .repetitive: return "Say it in your own words. Repeated words do not count."
            case .notAboutWindow: return "Describe what is in this window, such as the page, the file or what you are reading."
            case .injected: return "Focus ignores instructions aimed at it. Describe the window instead."
            }
        }
    }

    /// Every message, for the copy tests.
    public static var messagesForTesting: [String] { [Issue.tooShort, .repetitive, .notAboutWindow, .injected].map(\.message) }

    public static let minWords = 8, minCharacters = 40, maxCharacters = 280

    static let stop: Set<String> = ["this", "that", "with", "from", "have", "been", "were", "what", "when", "where", "which", "while", "about", "into",
                                    "because", "need", "just", "some", "they", "them", "then", "than", "there", "here", "your", "yours", "mine", "also",
                                    "doing", "using", "looking", "trying", "working", "window", "page", "task", "help", "helps", "for", "and", "the"]

    static func tokens(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }
    /// A word and its near forms share a stem: "integration" and "integrals" both start "integ".
    static func stem(_ w: String) -> String { String(w.prefix(5)) }
    static func content(_ s: String) -> Set<String> { Set(tokens(s).filter { $0.count >= 4 && !stop.contains($0) }.map(stem)) }

    public static func tidy(_ s: String) -> String {
        let one = s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return String(one.prefix(maxCharacters))
    }

    public static func assess(_ raw: String, window: WindowSnapshot?) -> Issue? {
        let claim = tidy(raw)
        let words = tokens(claim)
        guard words.count >= minWords, claim.count >= minCharacters else { return .tooShort }
        guard Set(words).count >= 6 else { return .repetitive }
        if let w = window {
            let evidence = content([w.app, w.title, w.url, w.documentPath, w.text].joined(separator: " "))
            // With no title or address to compare to (Accessibility off), this check cannot run and the model decides alone.
            if !evidence.isEmpty, content(claim).isDisjoint(with: evidence) { return .notAboutWindow }
        }
        var probe = Moment(task: "", app: "", windowTitle: "")
        probe.windowText = claim
        if Rules.looksInjected(probe) { return .injected }
        return nil
    }
}
