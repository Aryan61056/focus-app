import SwiftUI

// The license screens: the key step inside the welcome, the full-window gate for a Mac that has no valid key, and Settings > License.
// Everything here animates on a change (a group filling, a refusal, an accepted key) and is still when nothing changes: no timers.

/// The setup flow's ground: the window color with two soft green lights that move to a new place on each step. They are radial
/// gradients, not blurs, and they only move when the step changes, so a window left open costs nothing.
struct SetupBackdrop: View {
    var step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private static let lights: [(UnitPoint, UnitPoint)] = [
        (.init(x: 0.5, y: -0.05), .init(x: 1.0, y: 1.1)), (.init(x: 0.15, y: 0.1), .init(x: 0.9, y: 0.95)),
        (.init(x: 0.85, y: 0.05), .init(x: 0.1, y: 1.0)), (.init(x: 0.5, y: 0.0), .init(x: 0.5, y: 1.15)),
    ]
    var body: some View {
        let (top, low) = Self.lights[min(max(step, 0), Self.lights.count - 1)]
        let strength = scheme == .dark ? 0.26 : 0.16
        ZStack {
            Tokens.window
            RadialGradient(colors: [Tokens.accent.opacity(strength), .clear], center: top, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Tokens.accent.opacity(strength * 0.55), .clear], center: low, startRadius: 0, endRadius: 440)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.7), value: step)
        .ignoresSafeArea()
    }
}

/// The bottom bar's round glass Back button.
struct GlassBack: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).frame(width: 36, height: 36).contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .glassSurface(Circle(), interactive: true)
        .accessibilityLabel("Back")
    }
}

/// The main action as a green glass capsule. Its words change in place (Activate, Checking, Continue) without the button jumping.
struct GlassPrimary: View {
    var title: String
    var busy = false
    var enabled = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small).tint(Tokens.onAccent).transition(.scale.combined(with: .opacity)) }
                Text(title).font(Tokens.text(.callout, .semibold)).contentTransition(.interpolate)
            }
            .foregroundStyle(Tokens.onAccent).padding(.horizontal, 22).frame(height: 36).contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .glassSurface(Capsule(), tint: Tokens.accent.opacity(enabled ? 0.9 : 0.35), interactive: enabled, fallback: Tokens.accent)
        .opacity(enabled ? 1 : 0.7)
        .disabled(!enabled)
        .animation(.smooth(duration: 0.28), value: title)
        .animation(.smooth(duration: 0.28), value: busy)
        .animation(.smooth(duration: 0.28), value: enabled)
    }
}

/// A small give under the click, for buttons that sit on glass.
struct PressScale: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(reduceMotion ? nil : Motion.notchPress, value: configuration.isPressed)
    }
}

/// Side to side, three times: the key field says no.
struct Shake: GeometryEffect {
    var times: CGFloat
    var animatableData: CGFloat { get { times } set { times = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 9 * sin(times * .pi * 6) * (1 - times), y: 0))
    }
}

// MARK: the key step

/// Type or paste the key; five groups fill as it grows. Accepts the key on Return. Shows what went wrong in a line under the field,
/// and, once accepted, a pass for this Mac.
struct LicenseStep: View {
    @Bindable var license: LicenseCenter
    /// Headline when no key is on this Mac.
    var title = "Enter your key"
    var line = "Beta keys come from hushd.store. One key works on two Macs."
    var onActivated: () -> Void = {}
    @State private var shake: CGFloat = 0
    @State private var shown = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var accepted: Bool { license.holdsKey }

    var body: some View {
        VStack(spacing: Space.xl) {
            ZStack {
                if accepted, let info = license.info {
                    PassCard(info: info, daysLeft: license.daysLeft(), status: license.status)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                } else {
                    keyCard.transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 214)
            .animation(reduceMotion ? Motion.reduced : .spring(response: 0.5, dampingFraction: 0.82), value: accepted)

            VStack(spacing: Space.xs) {
                Text(accepted ? "You\u{2019}re in" : title).font(Tokens.rounded(.display, .semibold)).multilineTextAlignment(.center)
                    .contentTransition(.interpolate).accessibilityAddTraits(.isHeader)
                Text(accepted ? "Hushd is active on this Mac." : line).font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 460)
                    .contentTransition(.interpolate)
            }
            .animation(.smooth(duration: 0.3), value: accepted)

            Group {
                if let e = license.error {
                    Label(e, systemImage: "exclamationmark.circle").font(Tokens.text(.callout)).foregroundStyle(Tokens.slip)
                        .multilineTextAlignment(.center).transition(.opacity.combined(with: .offset(y: 4)))
                } else if !accepted {
                    Label("Only your key and a code for this Mac go to hushd.store. Never your work.", systemImage: "lock")
                        .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).transition(.opacity)
                }
            }
            .frame(minHeight: 20)
            .animation(.smooth(duration: 0.25), value: license.error)
        }
        .opacity(shown ? 1 : 0).offset(y: shown || reduceMotion ? 0 : 10)
        .onAppear { withAnimation(reduceMotion ? Motion.reduced : Motion.out(0.4)) { shown = true }; focused = !accepted }
        .onChange(of: license.error) { _, e in
            guard e != nil, !reduceMotion else { return }
            shake = 0; withAnimation(.linear(duration: 0.36)) { shake = 1 }
        }
    }

    // MARK: the card where the key goes

    var formatted: String { LicenseKey.format(license.draft) }
    var body5: [String] {
        let parts = formatted.split(separator: "-").dropFirst().map(String.init)
        return (0..<LicenseKey.groups).map { $0 < parts.count ? parts[$0] : "" }
    }

    var keyCard: some View {
        VStack(spacing: Space.l) {
            ZStack {
                Image(systemName: "key.fill").font(.system(size: 22, weight: .medium)).foregroundStyle(Tokens.accent)
                    .symbolEffect(.bounce, value: formatted.count / 6)
            }
            .frame(width: 52, height: 52).background(Circle().fill(Tokens.accentSoft))

            ZStack {
                // What is typed is drawn in the field below; the hidden-looking real field only catches typing, paste and Return.
                HStack(spacing: Space.xs) {
                    Text(LicenseKey.prefix).font(.system(.callout, design: .monospaced, weight: .semibold)).foregroundStyle(Tokens.ink2)
                    ForEach(0..<LicenseKey.groups, id: \.self) { i in
                        Text(body5[i].isEmpty ? String(repeating: "\u{2022}", count: LicenseKey.groupSize).prefix(LicenseKey.groupSize) : Substring(body5[i]))
                            .font(.system(.callout, design: .monospaced, weight: .medium))
                            .foregroundStyle(body5[i].isEmpty ? Tokens.ink2.opacity(0.35) : Tokens.ink)
                            .contentTransition(.interpolate)
                    }
                }
                .padding(.horizontal, Space.m).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: Tokens.radiusInset + 4, style: .continuous).fill(Tokens.well.opacity(0.85)))
                .overlay { RoundedRectangle(cornerRadius: Tokens.radiusInset + 4, style: .continuous)
                    .strokeBorder(license.error != nil ? Tokens.slip : focused ? Tokens.accent : Tokens.line, lineWidth: focused || license.error != nil ? 1.5 : 0.5) }
                TextField("", text: Binding(get: { license.draft }, set: { license.draft = LicenseKey.format($0); license.clearError() }))
                    .textFieldStyle(.plain).opacity(0.015).focused($focused)
                    .frame(height: 48).onSubmit { Task { await submit() } }
                    .accessibilityLabel("License key")
            }
            .modifier(Shake(times: shake))
            .animation(.smooth(duration: 0.2), value: focused)

            // Five groups, five lights: each fills when its group is complete.
            HStack(spacing: 6) {
                ForEach(0..<LicenseKey.groups, id: \.self) { i in
                    Capsule().fill(body5[i].count == LicenseKey.groupSize ? Tokens.accent : Tokens.track).frame(width: 28, height: 4)
                        .scaleEffect(y: body5[i].count == LicenseKey.groupSize ? 1.4 : 1)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: formatted)
            .accessibilityHidden(true)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(Rectangle()).onTapGesture { focused = true }
    }

    func submit() async {
        guard LicenseKey.isComplete(formatted), !license.busy else { return }
        if await license.activate(formatted) { onActivated() }
    }
}

/// The accepted key as a pass: a check that pops in with one ring spreading from it, then the plan, the key's tail and the days left.
struct PassCard: View {
    var info: LicenseInfo
    var daysLeft: Int?
    var status: LicenseStatus
    @State private var pop = false
    @State private var ring = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.m) {
            ZStack {
                Circle().stroke(Tokens.accent.opacity(ring ? 0 : 0.5), lineWidth: 2).frame(width: 52, height: 52).scaleEffect(ring ? 2.6 : 1)
                Circle().fill(Tokens.accent).frame(width: 56, height: 56).scaleEffect(pop ? 1 : 0.4)
                Image(systemName: "checkmark").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    .scaleEffect(pop ? 1 : 0.2).symbolEffect(.bounce, value: pop)
            }
            .frame(height: 70)
            VStack(spacing: 3) {
                Text(info.plan.capitalized + " access").font(Tokens.rounded(.headline, .semibold))
                Text(detail).font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2).monospacedDigit()
            }
            .opacity(pop ? 1 : 0).offset(y: pop || reduceMotion ? 0 : 6)
        }
        .padding(Space.xl).frame(maxWidth: .infinity)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear {
            guard !reduceMotion else { pop = true; return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.6).delay(0.08)) { pop = true }
            withAnimation(.easeOut(duration: 0.9).delay(0.12)) { ring = true }
        }
        .accessibilityElement(children: .combine)
    }

    var detail: String {
        var parts = ["Key ending \(info.keyHint)"]
        if let d = daysLeft { parts.append(d <= 0 ? "ends today" : d == 1 ? "1 day left" : "\(d) days left") }
        if case .offline(_, let left) = status { parts.append("offline, \(left) days left without a connection") }
        return parts.joined(separator: "  \u{00B7}  ")
    }
}

// MARK: the full-window gate

/// For a Mac that finished the welcome but has no valid key (the key ran out, was turned off, or a newer build wants one). Same step,
/// same backdrop, no welcome around it.
struct LicenseGateView: View {
    @Bindable var c: SessionController
    @Bindable var license: LicenseCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var headline: (title: String, line: String) {
        if case .blocked(let why, _) = license.status {
            switch why {
            case .expired: return ("Your key has run out", "Enter a new key to keep using Hushd. Your sessions and settings are all still here.")
            case .revoked: return ("This key was turned off", "Enter a different key to keep using Hushd. Your sessions and settings are all still here.")
            case .offlineTooLong: return ("Hushd needs to check your key", "Connect to the internet once and it will open. Your sessions and settings are all still here.")
            case .notActivated: return ("This Mac needs activating", "Enter your key again to put this Mac back on it.")
            default: break
            }
        }
        return ("Enter your key", "Beta keys come from hushd.store. One key works on two Macs.")
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.xl)
            LicenseStep(license: license, title: headline.title, line: headline.line)
                .frame(width: WelcomeView.column).id(license.status.isBlocked)
            Spacer(minLength: Space.l)
            LicenseBar(license: license, back: nil, onContinue: { license.acknowledge() })
        }
        .padding(.horizontal, Space.xxl).padding(.bottom, Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SetupBackdrop(step: 1))
        .modifier(PlainTitleBar())
    }
}

extension LicenseStatus {
    var isBlocked: Bool { if case .blocked = self { return true }; return false }
}

/// The bottom bar for the key step. What is typed lives in the center (`draft`), so this button and the field share it.
struct LicenseBar: View {
    @Bindable var license: LicenseCenter
    var back: (() -> Void)?
    var skip: (() -> Void)?
    var onContinue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var accepted: Bool { license.holdsKey }

    var body: some View {
        HStack(spacing: Space.xs) {
            if let back { GlassBack(action: back) }
            if !accepted { Button("Get a key") { license.getKey() }.buttonStyle(FocusButtonStyle(.plain)) }
            Spacer()
            if let skip, !accepted, !license.enforced { Button("Not now", action: skip).buttonStyle(FocusButtonStyle(.secondary)) }
            if accepted {
                GlassPrimary(title: "Continue", action: onContinue).keyboardShortcut(.defaultAction)
            } else {
                GlassPrimary(title: license.busy ? "Checking" : "Activate", busy: license.busy,
                             enabled: !license.busy && license.draftIsComplete) { Task { _ = await license.activateDraft() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: 760)
    }
}

extension LicenseCenter {
    var draftIsComplete: Bool { LicenseKey.isComplete(LicenseKey.format(draft)) }
    func activateDraft() async -> Bool { await activate(draft) }
}

// MARK: Settings > License

struct LicenseSettings: View {
    @Bindable var license: LicenseCenter
    var sessionActive: Bool
    @State private var confirmDeactivate = false
    @State private var entering = false

    var body: some View {
        Section {
            HStack(spacing: Space.m) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 44, height: 44).background(Circle().fill(tint.opacity(0.14)))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(license.summary).font(Tokens.rounded(.headline, .semibold))
                    Text(detail).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
                }
                Spacer(minLength: 12)
                if license.info != nil {
                    Button(license.busy ? "Checking\u{2026}" : "Check now") { Task { await license.refresh() } }
                        .buttonStyle(FocusButtonStyle(.secondary, small: true)).disabled(license.busy)
                }
            }
            .padding(.vertical, Space.xxs)
            .animation(.smooth(duration: 0.3), value: license.summary)
            if let e = license.error {
                Label(e, systemImage: "exclamationmark.circle").font(Tokens.text(.caption)).foregroundStyle(Tokens.slip)
            }
        } header: { Text("License") }

        Section {
            if license.info == nil {
                LabeledContent("Key") { Button("Enter a key\u{2026}") { entering = true }.buttonStyle(FocusButtonStyle(.primary, small: true)) }
            }
            LabeledContent("Get a key") { Button("hushd.store/beta") { license.getKey() }.buttonStyle(FocusButtonStyle(.plain, small: true)) }
            if license.info != nil {
                LabeledContent {
                    Button("Deactivate this Mac") { confirmDeactivate = true }.buttonStyle(FocusButtonStyle(.plain, small: true)).disabled(license.busy || sessionActive)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use the key on another Mac")
                        Text("Frees this Mac\u{2019}s place on the key. Hushd asks for a key again here.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                    }
                }
            }
        }
        .sheet(isPresented: $entering) { EntrySheet(license: license, done: { entering = false }) }
        .confirmationDialog("Deactivate this Mac?", isPresented: $confirmDeactivate) {
            Button("Deactivate", role: .destructive) { Task { await license.deactivate() } }
        } message: { Text("Your sessions and settings stay. You\u{2019}ll enter a key again to keep using Hushd on this Mac.") }
    }

    var icon: String {
        switch license.status {
        case .unlicensed: return "key"; case .checking, .active: return "checkmark.seal.fill"
        case .offline: return "wifi.slash"; case .blocked: return "exclamationmark.triangle.fill"
        }
    }
    var tint: Color {
        switch license.status {
        case .unlicensed: return Tokens.ink2; case .checking, .active: return Tokens.accent
        case .offline: return Tokens.ink2; case .blocked: return Tokens.slip
        }
    }
    var detail: String {
        guard let info = license.info else { return license.enforced ? "Hushd needs a key to open." : "This is a development build, so it opens without one." }
        var s = "\(info.plan.capitalized)  \u{00B7}  key ending \(info.keyHint)  \u{00B7}  \(info.activations) of \(info.maxActivations) Macs"
        if let d = license.daysLeft() { s += d <= 0 ? "  \u{00B7}  ends today" : "  \u{00B7}  \(d) day\(d == 1 ? "" : "s") left" }
        return s
    }
}

/// Settings > License > Enter a key: the same step, in a sheet.
struct EntrySheet: View {
    @Bindable var license: LicenseCenter
    var done: () -> Void
    var body: some View {
        VStack(spacing: Space.xl) {
            LicenseStep(license: license)
            HStack {
                Button("Cancel") { license.clearError(); done() }.buttonStyle(FocusButtonStyle(.plain))
                Spacer()
                if license.holdsKey {
                    GlassPrimary(title: "Done") { license.acknowledge(); done() }.keyboardShortcut(.defaultAction)
                } else {
                    GlassPrimary(title: license.busy ? "Checking" : "Activate", busy: license.busy, enabled: !license.busy && license.draftIsComplete) {
                        Task { _ = await license.activateDraft() }
                    }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Space.xxl).frame(width: 600).background(Tokens.window)
    }
}
