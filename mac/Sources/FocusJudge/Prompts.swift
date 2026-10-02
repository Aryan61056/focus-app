import Foundation

public enum PromptVersion: Sendable { case v1, v2, v3 }

/// Prompt construction, byte-identical to eval/focus_eval/prompts.py (checked by tools/check_prompt_parity.py).
public enum Prompts {
    public static let maxTextScalars = 1200  // the Apple system model has a ~4K-token context window

    public static func instructions(_ version: PromptVersion) -> String {
        switch version { case .v1: return PromptText.instructionsV1; case .v2: return PromptText.instructionsV2; case .v3: return PromptText.instructionsV3 }
    }

    /// Screen-derived single-line fields must not be able to start new prompt lines.
    static func oneLine(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Screen text must not be able to close or reopen the <window_text> block.
    static func neutralize(_ text: String) -> String {
        text.replacingOccurrences(of: "<window_text", with: "< window_text")
            .replacingOccurrences(of: "</window_text", with: "< /window_text")
    }

    static func clip(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.prefix(maxTextScalars)))
    }

    public static func prompt(for m: Moment, includeText: Bool = true) -> String {
        var lines = ["Task: \(m.task)"]
        if !m.project.context.isEmpty { lines.append("Project context: \(m.project.context)") }
        lines.append("")
        lines.append("Window right now:")
        lines.append("app: \(oneLine(m.app))")
        lines.append("title: \(oneLine(m.windowTitle))")
        if !m.url.isEmpty { lines.append("url: \(oneLine(m.url))") }
        if !m.documentPath.isEmpty { lines.append("document: \(oneLine(m.documentPath))") }
        let text = includeText ? m.windowText : ""
        if !text.isEmpty {
            lines.append("<window_text>")
            lines.append(neutralize(clip(text)))
            lines.append("</window_text>")
        }
        return lines.joined(separator: "\n")
    }
}
