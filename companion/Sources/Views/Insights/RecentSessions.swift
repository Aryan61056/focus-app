import SwiftUI
import FocusLinkNet

struct RecentSessions: View {
    let sessions: [Insights.Digest]

    var body: some View {
        if !sessions.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("Recent sessions").padding(.bottom, 8)
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, s in
                        if index > 0 { Divider().overlay(Palette.line) }
                        row(s)
                    }
                }
            }
        }
    }

    private func row(_ s: Insights.Digest) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.task).font(.body.weight(.medium)).lineLimit(1)
                Text(s.start, format: .dateTime.weekday(.abbreviated).hour().minute()).font(.footnote).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(s.onTaskSeconds.spokenText).font(.body.monospacedDigit())
                Text(s.drifts == 0 ? "No slips" : (s.drifts == 1 ? "1 slip" : "\(s.drifts) slips")).font(.footnote).foregroundStyle(Palette.ink2)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
