import SwiftUI

// Friends (docs/SOCIAL.md). The owner asked for this page to feel fun rather than analytical, then for it to stay grown-up and quiet
// ("not for kids", "not too much text", 2026-10-16). So: a low podium with small rank badges, a race track per friend, a soft color per
// friend, one Cheer button, and every explanation behind an info button. Amber still marks only slips; Reduce Motion drops the motion.

/// A friend's color: one of six soft hues, picked from their id so a person keeps the same color on every Mac. You are always green.
/// `soft` fills avatars, bubbles and tracks; `strong` is for shapes only (tracks, rings), never for small text.
struct FriendHue {
    var soft: Color
    var strong: Color
    static let all: [FriendHue] = [
        FriendHue(soft: Color(light: 0xE3EEFB, dark: 0x1E2A3A), strong: Color(light: 0x3F7BC8, dark: 0x82AEE8)),   // sky
        FriendHue(soft: Color(light: 0xEDE7F8, dark: 0x2A2538), strong: Color(light: 0x7A5CC4, dark: 0xAE98E6)),   // lilac
        FriendHue(soft: Color(light: 0xF8E9DF, dark: 0x3A281F), strong: Color(light: 0xC56B3A, dark: 0xE7A27C)),   // clay
        FriendHue(soft: Color(light: 0xF6EFD6, dark: 0x36301C), strong: Color(light: 0xA88412, dark: 0xD9BC62)),   // ochre
        FriendHue(soft: Color(light: 0xF7E4EA, dark: 0x3A2229), strong: Color(light: 0xB95576, dark: 0xE496AF)),   // rose
        FriendHue(soft: Color(light: 0xDDF0EF, dark: 0x1C3232), strong: Color(light: 0x2A8A8C, dark: 0x74C6C7)),   // teal
    ]
    static let you = FriendHue(soft: Tokens.accentSoft, strong: Tokens.accent)
    static func of(_ id: String, you: Bool) -> FriendHue {
        if you { return .you }
        // djb2: stable across launches, unlike hashValue.
        let h = id.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return all[Int(h % UInt32(all.count))]
    }
}

struct FriendsView: View {
    @Bindable var c: SessionController
    @Bindable var friends: FriendsStore
    @State private var removing: Scoreboard.Entry?
    var board: Scoreboard.Board { friends.board }

    var body: some View {
        Group {
            if friends.sharing {
                PanelLayout(panelWidth: 272) {
                    page.padding(.horizontal, Space.xl).padding(.top, Space.l).padding(.bottom, Space.xl)
                } side: {
                    FocusPanelColumn { FriendsPanel(c: c, friends: friends) }
                }
            } else {
                Scroller { FriendsIntro(c: c, friends: friends).padding(Space.xl) }
            }
        }
        .task(id: friends.sharing) { if friends.sharing { await friends.refresh() } }
        .confirmationDialog("Remove \(removing?.name ?? "this friend")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) { if let r = removing { Task { await friends.remove(r.id) } }; removing = nil }
        } message: {
            Text("You stop seeing each other's weeks.")
        }
    }

    var page: some View {
        let entries = friends.entries(board)
        // The podium holds the first three ranked people; everyone else races below it.
        let podium = Array(entries.filter { $0.rank != nil }.prefix(3))
        let rest = entries.filter { e in !podium.contains { $0.id == e.id } }
        return VStack(alignment: .leading, spacing: Space.l) {
            header(entries)
            if case .failed(let why) = friends.status { SyncNotice(why: why, since: friends.lastSync, friends: friends) }
            if friends.firstLoad && entries.count <= 1 {
                PodiumSkeleton()
            } else if entries.count <= 1 {
                Lonely(friends: friends)
            } else {
                if !podium.isEmpty {
                    Podium(entries: podium, board: board, friends: friends, removing: $removing).id(board)
                }
                if !rest.isEmpty {
                    RaceList(entries: rest, leader: entries.map(\.focusedSeconds).max() ?? 0, steadiest: entries.compactMap(\.slipsPerHour).min(),
                             board: board, friends: friends, removing: $removing)
                }
            }
        }
        .frame(maxWidth: 760, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }

    func header(_ entries: [Scoreboard.Entry]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .center, spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week").font(Tokens.text(.headline, .semibold)).lineLimit(1).fixedSize()
                    Text(Self.leadLine(entries, board: board)).font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s)
                // The full label when there is room; the icon alone in a narrow window.
                ViewThatFits(in: .horizontal) {
                    invite.labelStyle(.titleAndIcon)
                    invite.labelStyle(.iconOnly).help("Invite a friend")
                }
            }
            HStack(spacing: Space.xs) {
                ForEach(Scoreboard.Board.allCases) { b in
                    Button(b.rawValue) { friends.board = b }.buttonStyle(ChoiceStyle(on: board == b)).fixedSize()
                }
                InfoTip(text: board == .focused
                        ? "Ranked by time on task. Slips are Hushd's calls, and Hushd can be wrong. Starts over every week."
                        : "Ranked by slips per hour on task, after an hour of focus. Hushd can be wrong. Starts over every week.")
                Spacer(minLength: Space.xs)
                Text(Self.weekTitle(.now)).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit().fixedSize()
            }
        }
    }

    var invite: some View {
        Button { Task { await friends.invite() } } label: { Label("Invite", systemImage: "person.badge.plus") }
            .buttonStyle(FocusButtonStyle(.secondary, small: true)).fixedSize()
    }

    /// One short line about the race, from the numbers on the board. Never about what anyone was doing.
    static func leadLine(_ entries: [Scoreboard.Entry], board: Scoreboard.Board) -> String {
        guard entries.count > 1, let top = entries.first, top.rank == 1 else { return "Invite friends to start a race." }
        let you = entries.first { $0.isYou }
        switch board {
        case .focused:
            if top.isYou {
                let second = entries.dropFirst().first?.focusedSeconds ?? 0
                return top.focusedSeconds - second >= 60 ? "You're ahead by \(durationText(top.focusedSeconds - second))." : "You're in front."
            }
            guard let you else { return "\(top.name) leads with \(durationText(top.focusedSeconds))." }
            if you.focusedSeconds < 60 { return "\(top.name) leads. One session gets you on the board." }
            let gap = top.focusedSeconds - you.focusedSeconds
            if gap < 60 { return "Neck and neck with \(top.name)." }
            if gap <= 45 * 60 { return "\(durationText(gap)) behind \(top.name). One session could do it." }
            return "\(top.name) leads. You're \(durationText(gap)) behind."
        case .steady:
            if top.isYou { return "Your week is the steadiest." }
            if let you, you.rank == nil { return "\(top.name) is steadiest. An hour of focus puts you on this board." }
            return "\(top.name) has the steadiest week."
        }
    }

    /// "Oct 11 to 17" (or "Sep 28 to Oct 4"), the calendar week the board covers, in the Mac's own date style.
    static func weekTitle(_ now: Date, calendar cal: Calendar = .current) -> String {
        guard let w = cal.dateInterval(of: .weekOfYear, for: now), let last = cal.date(byAdding: .day, value: -1, to: w.end) else { return "This week" }
        let sameMonth = cal.component(.month, from: w.start) == cal.component(.month, from: last)
        let end = last.formatted(sameMonth ? .dateTime.day() : .dateTime.month(.abbreviated).day())
        return "\(w.start.formatted(.dateTime.month(.abbreviated).day())) to \(end)"
    }
}

// MARK: podium

/// First, second and third, second on the left and third on the right, on low steps that rise into place when the board opens.
struct Podium: View {
    var entries: [Scoreboard.Entry]
    var board: Scoreboard.Board
    @Bindable var friends: FriendsStore
    @Binding var removing: Scoreboard.Entry?
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let order = [1, 0, 2].filter { $0 < entries.count }
        HStack(alignment: .bottom, spacing: Space.s) {
            ForEach(order, id: \.self) { i in
                PodiumPlace(entry: entries[i], place: i, board: board, up: up || reduceMotion, friends: friends, removing: $removing)
                    .frame(maxWidth: 200)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.m).padding(.horizontal, Space.m)
        .modifier(CardSurface())
        .onAppear { up = true }
    }
}

struct PodiumPlace: View {
    var entry: Scoreboard.Entry
    var place: Int
    var board: Scoreboard.Board
    var up: Bool
    @Bindable var friends: FriendsStore
    @Binding var removing: Scoreboard.Entry?

    static let heights: [CGFloat] = [34, 22, 14]
    /// The steps: gold, silver and bronze, soft enough to sit quietly under the people.
    static let steps = [Color(light: 0xF6E7B4, dark: 0x4A3D17), Color(light: 0xE6E8EC, dark: 0x34383E), Color(light: 0xF1DCCB, dark: 0x45301F)]

    var body: some View {
        let k = TextScale.shared.factor
        let rank = min(3, max(1, entry.rank ?? place + 1))
        VStack(spacing: Space.xxs) {
            FriendAvatar(name: entry.name, emoji: entry.emoji, hue: FriendHue.of(entry.id, you: entry.isYou), size: place == 0 ? 52 : 44)
                .overlay(alignment: .bottomTrailing) { RankBadge(rank: rank).offset(x: 3, y: 3) }
                .padding(.bottom, Space.xxs)
            Text(entry.isYou ? "You" : entry.name).font(Tokens.text(.body, .semibold)).lineLimit(1)
            Text(board == .focused ? durationText(entry.focusedSeconds) : (entry.slipsPerHour.map { String(format: "%.1f slips/h", $0) } ?? "\(entry.slips) slips"))
                .font(Tokens.rounded(.body, .semibold)).monospacedDigit().lineLimit(1)
            Meta(streak: entry.streak, slips: entry.slips)
            action.frame(height: 30 * k).padding(.top, Space.xxs)
            RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous).fill(Self.steps[rank - 1])
                .frame(height: Self.heights[place] * k)
                .scaleEffect(x: 1, y: up ? 1 : 0.05, anchor: .bottom)
                .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(Double(2 - place) * 0.06), value: up)
                .padding(.top, Space.xs)
        }
        .contextMenu { if !entry.isYou { Button("Remove \(entry.name)\u{2026}") { removing = entry } } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowLabel(entry))
    }

    @ViewBuilder var action: some View {
        if entry.isYou {
            let got = friends.cheersThisWeek
            if got > 0 {
                Label("\(got)", systemImage: "hands.clap").font(Tokens.text(.caption, .medium)).foregroundStyle(Tokens.ink2).monospacedDigit()
                    .help(got == 1 ? "1 cheer this week" : "\(got) cheers this week")
            }
        } else if !friends.seesYou(entry.id) {
            InviteBack(name: entry.name, friends: friends)
        } else {
            CheerButton(entry: entry, friends: friends)
        }
    }
}

/// The place, as a small coin on the avatar: gold, silver, bronze. Dark digits, so it reads in either appearance.
struct RankBadge: View {
    var rank: Int
    static let fills = [Color(red: 0.95, green: 0.79, blue: 0.30), Color(red: 0.80, green: 0.82, blue: 0.86), Color(red: 0.85, green: 0.61, blue: 0.42)]
    var body: some View {
        Text("\(rank)").font(.system(size: 10 * TextScale.shared.factor, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
            .frame(width: 18 * TextScale.shared.factor, height: 18 * TextScale.shared.factor)
            .background(Circle().fill(Self.fills[max(0, min(2, rank - 1))]))
            .overlay { Circle().strokeBorder(Tokens.window2, lineWidth: 1.5) }
            .accessibilityHidden(true)
    }
}

// MARK: the race

/// Everyone after the podium, each on a track.
struct RaceList: View {
    var entries: [Scoreboard.Entry]
    var leader: Double
    /// The lowest slips per hour on the board, for the Fewest slips tracks.
    var steadiest: Double?
    var board: Scoreboard.Board
    @Bindable var friends: FriendsStore
    @Binding var removing: Scoreboard.Entry?
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                if i > 0 { Divider().overlay(Tokens.line).padding(.leading, 64) }
                RaceRow(entry: e, leader: leader, steadiest: steadiest, board: board, friends: friends, removing: $removing)
            }
        }
        .padding(.vertical, Space.xxs)
        .modifier(CardSurface())
    }
}

struct RaceRow: View {
    var entry: Scoreboard.Entry
    var leader: Double
    var steadiest: Double?
    var board: Scoreboard.Board
    @Bindable var friends: FriendsStore
    @Binding var removing: Scoreboard.Entry?

    var body: some View {
        let k = TextScale.shared.factor
        // The action at the right when the row has room, under the track when it does not, so nothing gets cut.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s) {
                lead
                details.frame(minWidth: 200 * k, maxWidth: .infinity, alignment: .leading)
                action.frame(width: 104 * k, alignment: .trailing)
            }
            HStack(alignment: .top, spacing: Space.s) {
                lead
                VStack(alignment: .leading, spacing: Space.xs) { details; action.fixedSize() }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
        .background { if entry.isYou { RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous).fill(Tokens.accentSoft.opacity(0.45)).padding(.horizontal, Space.xxs) } }
        .contextMenu { if !entry.isYou { Button("Remove \(entry.name)\u{2026}") { removing = entry } } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowLabel(entry))
    }

    var hue: FriendHue { FriendHue.of(entry.id, you: entry.isYou) }

    var lead: some View {
        HStack(spacing: Space.s) {
            Text(entry.rank.map(String.init) ?? "\u{2013}").font(Tokens.rounded(.body, .semibold)).foregroundStyle(Tokens.ink2).monospacedDigit()
                .frame(width: 18 * TextScale.shared.factor)
            FriendAvatar(name: entry.name, emoji: entry.emoji, hue: hue, size: 32)
        }
    }

    var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: Space.xs) {
                Text(entry.isYou ? "You" : entry.name).font(Tokens.text(.body, .semibold)).lineLimit(1)
                Meta(streak: entry.streak, slips: entry.slips).fixedSize()
            }
            RaceTrack(fraction: fraction, hue: hue, label: trackLabel)
        }
    }

    /// How far along the track: time against the leader's on Most focused; on Fewest slips the steadiest week is a full track and
    /// more slips per hour make it shorter. Someone not ranked yet has an empty track.
    var fraction: Double {
        switch board {
        case .focused: return leader > 0 ? entry.focusedSeconds / leader : 0
        case .steady:
            guard let r = entry.slipsPerHour else { return 0 }
            guard r > 0 else { return 1 }
            return (steadiest ?? r) / r
        }
    }

    var trackLabel: String {
        if board == .focused { return durationText(entry.focusedSeconds) }
        return entry.slipsPerHour.map { String(format: "%.1f/h", $0) } ?? "Under 1 h"
    }

    @ViewBuilder var action: some View {
        if entry.isYou { Color.clear.frame(height: 1) }
        else if !friends.seesYou(entry.id) { InviteBack(name: entry.name, friends: friends) }
        else { CheerButton(entry: entry, friends: friends) }
    }
}

/// A rounded track filled in the person's color up to their share of the leader, with the figure at the end.
struct RaceTrack: View {
    var fraction: Double
    var hue: FriendHue
    var label: String
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: Space.xs) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(hue.soft)
                    Capsule().fill(hue.strong).frame(width: max(6, g.size.width * min(1, fraction)))
                        .scaleEffect(x: shown || reduceMotion ? 1 : 0.02, anchor: .leading)
                }
            }
            .frame(height: 6)
            Text(label).font(Tokens.rounded(.callout, .semibold)).monospacedDigit().lineLimit(1).fixedSize()
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.9).delay(0.1)) { shown = true } }
        .accessibilityHidden(true)
    }
}

func rowLabel(_ e: Scoreboard.Entry) -> String {
    let rank = e.rank.map { "Place \($0)" } ?? "Not ranked yet"
    let slips = e.slips == 1 ? "1 slip" : "\(e.slips) slips"
    return "\(rank), \(e.isYou ? "you" : e.name), \(durationText(e.focusedSeconds)) on task, \(slips), \(e.streak) focus days in a row"
}

// MARK: small pieces

/// A person's face on the board: their emoji, or their first letter, on their own soft color.
struct FriendAvatar: View {
    var name: String
    var emoji: String?
    var hue: FriendHue
    var size: CGFloat = 40
    var body: some View {
        let k = TextScale.shared.factor
        ZStack {
            Circle().fill(hue.soft)
            if let emoji { Text(emoji).font(.system(size: size * 0.5 * k)) }
            else { Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()).font(.system(size: size * 0.4 * k, weight: .semibold, design: .rounded)).foregroundStyle(Tokens.ink) }
        }
        .frame(width: size * k, height: size * k)
        .overlay { Circle().strokeBorder(hue.strong.opacity(0.35), lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

/// Streak and slips in one quiet line: a flame and a number, then slips in amber (the only amber on the page).
struct Meta: View {
    var streak: Int
    var slips: Int
    var body: some View {
        HStack(spacing: Space.xs) {
            if streak >= 2 {
                Label("\(streak)", systemImage: "flame.fill").labelStyle(Tight()).foregroundStyle(Tokens.ink2)
                    .help("\(streak) focus days in a row")
            }
            Text(slips == 0 ? "No slips" : (slips == 1 ? "1 slip" : "\(slips) slips"))
                .foregroundStyle(slips == 0 ? Tokens.ink2 : Tokens.slipInk)
        }
        .font(Tokens.text(.caption, .medium)).monospacedDigit().lineLimit(1)
    }
    struct Tight: LabelStyle {
        func makeBody(configuration: Configuration) -> some View { HStack(spacing: 2) { configuration.icon.imageScale(.small); configuration.title } }
    }
}

/// Explanations live here, not on the page: hover for the tooltip, click for the same words in a popover.
struct InfoTip: View {
    var text: String
    @State private var open = false
    var body: some View {
        Button { open.toggle() } label: { Image(systemName: "info.circle").font(Tokens.symbol(12)).foregroundStyle(Tokens.ink2).hitTarget() }
            .buttonStyle(.plain)
            .help(text)
            .accessibilityLabel("About this").accessibilityHint(text)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                Text(text).font(Tokens.text(.caption)).fixedSize(horizontal: false, vertical: true).frame(width: 240, alignment: .leading).padding(Space.s)
            }
    }
}

/// A friend who shares with you but cannot see yours yet.
struct InviteBack: View {
    var name: String
    @Bindable var friends: FriendsStore
    var body: some View {
        Button { Task { await friends.invite() } } label: { Label("Invite back", systemImage: "arrow.uturn.backward") }
            .buttonStyle(FocusButtonStyle(.plain, small: true)).fixedSize()
            .help("\(name) can't see your week yet")
            .accessibilityLabel("\(name) can't see your week yet. Invite back.")
    }
}

/// One Cheer button. The picker holds the five emoji and five lines; what you sent floats up from the button and the button says Sent.
struct CheerButton: View {
    var entry: Scoreboard.Entry
    @Bindable var friends: FriendsStore
    @State private var open = false
    @State private var flying: CheerKind = .fire
    @State private var flights = 0
    @State private var sent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let left = friends.cheersLeft(for: entry.id)
        Button { open = true } label: {
            Label(sent ? "Sent" : (left == 0 ? "Cheered" : "Cheer"), systemImage: sent || left == 0 ? "checkmark" : "hands.clap")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(FocusButtonStyle(.secondary, small: true)).fixedSize()
        .disabled(left == 0 || sent)
        .help(left == 0 ? "You've cheered \(entry.name) three times today" : "Cheer \(entry.name) on")
        .accessibilityLabel(left == 0 ? "Cheered \(entry.name) today" : "Cheer \(entry.name) on")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            CheerPicker(name: entry.name, left: left) { k in open = false; send(k) }
        }
        .overlay(alignment: .top) { flight }
        .animation(Motion.out(0.2), value: sent)
    }

    /// Rests invisible; each send plays it once.
    var flight: some View {
        Text(flying.isEmoji ? flying.text : "\u{1F4AC}").font(.system(size: 18))
            .keyframeAnimator(initialValue: Flight(), trigger: flights) { v, f in
                v.opacity(f.opacity).scaleEffect(f.scale).offset(y: f.rise)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) { LinearKeyframe(1, duration: 0.05); LinearKeyframe(1, duration: 0.4); CubicKeyframe(0, duration: 0.3) }
                KeyframeTrack(\.scale) { SpringKeyframe(1.2, duration: 0.3, spring: .smooth); CubicKeyframe(1, duration: 0.45) }
                KeyframeTrack(\.rise) { CubicKeyframe(-30, duration: 0.75) }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }

    struct Flight { var opacity = 0.0, scale = 0.7, rise = 0.0 }

    func send(_ k: CheerKind) {
        flying = k
        if !reduceMotion { flights += 1 }
        Task {
            guard await friends.send(k, to: entry.id) else { return }
            sent = true
            try? await Task.sleep(for: .seconds(1.6))
            sent = false
        }
    }
}

/// Every cheer: the five emoji, then the five lines. Nothing to type.
struct CheerPicker: View {
    var name: String
    var left: Int
    var pick: (CheerKind) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: 2) {
                ForEach(CheerKind.emoji, id: \.self) { k in
                    Button { pick(k) } label: { Text(k.text).font(.system(size: 18)).frame(width: 34, height: 32) }
                        .buttonStyle(CheerButtonStyle()).accessibilityLabel(k.spoken)
                }
            }
            Divider().overlay(Tokens.line)
            VStack(spacing: 0) {
                ForEach(CheerKind.lines, id: \.self) { k in
                    Button { pick(k) } label: { Text(k.text).font(Tokens.text(.body)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Space.xs).frame(height: 28) }
                        .buttonStyle(CheerButtonStyle())
                }
            }
        }
        .padding(Space.s).frame(width: 196)
        .help(left == 1 ? "1 more today" : "\(left) more today")
    }
}

struct CheerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @State private var hover = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous).fill(configuration.isPressed ? Tokens.controlHover : (hover ? Tokens.control : Color.clear)))
                .contentShape(RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous))
                .onHover { hover = $0 }
                .animation(Motion.hover, value: hover)
        }
    }
}

/// Nobody else on the board yet.
struct Lonely: View {
    @Bindable var friends: FriendsStore
    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "person.2").font(Tokens.symbol(18)).foregroundStyle(Tokens.accent)
                .frame(width: 40, height: 40).background(Circle().fill(Tokens.accentSoft)).accessibilityHidden(true)
            HStack(spacing: Space.xxs) {
                Text("Just you so far").font(Tokens.text(.callout, .semibold))
                InfoTip(text: "When a friend accepts your invite and you accept theirs, you both show up here.")
            }
            Button { Task { await friends.invite() } } label: { Label("Invite a friend", systemImage: "person.badge.plus") }
                .buttonStyle(FocusButtonStyle(.primary))
        }
        .padding(.vertical, Space.xl).frame(maxWidth: .infinity)
        .modifier(CardSurface())
    }
}

/// While the first fetch is on its way: the podium's shape in gray, still (no shimmer that runs forever).
struct PodiumSkeleton: View {
    var body: some View {
        VStack(spacing: Space.s) {
            HStack(alignment: .bottom, spacing: Space.s) {
                ForEach([1, 0, 2], id: \.self) { i in
                    VStack(spacing: Space.xs) {
                        Circle().fill(Tokens.control).frame(width: i == 0 ? 52 : 44, height: i == 0 ? 52 : 44)
                        Capsule().fill(Tokens.control).frame(width: 56, height: 8)
                        RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous).fill(Tokens.control).frame(height: PodiumPlace.heights[i])
                    }
                    .frame(maxWidth: 200)
                }
            }
            HStack(spacing: Space.xs) { ProgressView().controlSize(.small); Text("Loading") }
                .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
        }
        .frame(maxWidth: .infinity).padding(Space.m)
        .modifier(CardSurface())
        .accessibilityElement(children: .ignore).accessibilityLabel("Loading your friends' weeks")
    }
}

/// A sync that failed: the board below is the last one that arrived, and one way to try again.
struct SyncNotice: View {
    var why: String
    var since: Date?
    @Bindable var friends: FriendsStore
    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "icloud.slash").foregroundStyle(Tokens.ink2).accessibilityHidden(true)
            Text("Couldn't update").font(Tokens.text(.body, .medium))
            InfoTip(text: why + (since.map { " Showing the board from \($0.formatted(.relative(presentation: .named)))." } ?? ""))
            Spacer(minLength: Space.s)
            Button("Try again") { Task { await friends.refresh() } }.buttonStyle(FocusButtonStyle(.secondary, small: true))
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
        .background(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).fill(Tokens.well))
    }
}

// MARK: the panel

/// The panel at the right: cheers you got, you on the board, and the switch.
struct FriendsPanel: View {
    @Bindable var c: SessionController
    @Bindable var friends: FriendsStore
    /// Cheers that were new when they came into view; they keep a "New" mark while the page is open.
    @State private var fresh: Set<String> = []

    func absorb() {
        fresh.formUnion(friends.cheers.map(\.id).filter { !friends.seen.contains($0) })
        friends.markCheersSeen()
    }

    var body: some View {
        PanelSection(title: "Cheers") {
            if friends.cheers.isEmpty {
                Text("None yet").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
            } else {
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(friends.cheers.prefix(6)) { ch in
                        CheerBubble(cheer: ch, name: friends.name(of: ch.from), emoji: friends.friends.first { $0.id == ch.from }?.emoji, new: fresh.contains(ch.id))
                    }
                }
            }
        }
        .onAppear { absorb() }
        .onChange(of: friends.cheers.map(\.id)) { _, _ in absorb() }
        Divider().overlay(Tokens.line)
        PanelSection(title: "You") {
            HStack(spacing: Space.xs) {
                AvatarButton(emoji: Binding(get: { c.prefs.friendEmoji }, set: { c.prefs.friendEmoji = $0; Task { await friends.refresh() } }), name: c.prefs.friendName)
                TextField("Your name", text: Binding(get: { c.prefs.friendName }, set: { c.prefs.friendName = String($0.prefix(40)) }))
                    .wellField(height: 30).font(Tokens.text(.body))
                    .onSubmit { Task { await friends.refresh() } }
                    .accessibilityLabel("Your name on the board")
            }
        }
        Divider().overlay(Tokens.line)
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xxs) {
                Toggle("Share with friends", isOn: Binding(get: { friends.sharing }, set: { on in Task { await friends.setSharing(on) } }))
                    .toggleStyle(.switch).controlSize(.small).tint(Tokens.accent).font(Tokens.text(.body))
                InfoTip(text: FriendsIntro.shared + " Turning this off deletes what you shared.")
            }
            FriendsStatusLine(friends: friends, brief: true)
        }
    }
}

/// A cheer as a speech bubble from the friend's avatar, in their color.
struct CheerBubble: View {
    var cheer: Cheer
    var name: String
    var emoji: String?
    var new = false
    var body: some View {
        let hue = FriendHue.of(cheer.from, you: false)
        let shape = UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 4, bottomTrailingRadius: 12, topTrailingRadius: 12, style: .continuous)
        HStack(alignment: .bottom, spacing: Space.xs) {
            FriendAvatar(name: name, emoji: emoji, hue: hue, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(cheer.kind.text).font(cheer.kind.isEmoji ? .system(size: 17) : Tokens.text(.body))
                    .padding(.horizontal, cheer.kind.isEmoji ? Space.xs : 10).padding(.vertical, cheer.kind.isEmoji ? 2 : 5)
                    .background(shape.fill(hue.soft))
                HStack(spacing: Space.xxs) {
                    if new { Circle().fill(Tokens.accent).frame(width: 6, height: 6).help("New") }
                    Text("\(name) \u{00B7} \(cheer.at.formatted(.relative(presentation: .named)))").font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(new ? "New. " : "")\(name): \(cheer.kind.spoken), \(cheer.at.formatted(.relative(presentation: .named)))")
    }
}

/// Your avatar as a button; a click opens the twelve avatars and your first letter. A fixed list, so nothing typed travels.
struct AvatarButton: View {
    @Binding var emoji: String
    var name: String
    var size: CGFloat = 30
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            FriendAvatar(name: name.isEmpty ? "?" : name, emoji: emoji.isEmpty ? nil : emoji, hue: .you, size: size)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil").font(.system(size: 7, weight: .bold)).foregroundStyle(Tokens.ink2)
                        .frame(width: 13, height: 13).background(Circle().fill(Tokens.window2)).overlay { Circle().strokeBorder(Tokens.line) }
                        .offset(x: 2, y: 2)
                }
        }
        .buttonStyle(.plain).help("Change avatar").accessibilityLabel("Change avatar")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            AvatarPicker(selection: Binding(get: { emoji }, set: { emoji = $0; open = false }), name: name).padding(Space.s)
        }
    }
}

struct AvatarPicker: View {
    @Binding var selection: String
    var name: String
    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(30), spacing: 2), count: 7)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 2) {
            ForEach([""] + FriendCard.avatars, id: \.self) { e in
                Button { selection = e } label: { cell(e) }
                    .buttonStyle(CheerButtonStyle())
                    .accessibilityLabel(e.isEmpty ? "Your first letter" : "Avatar \(e)")
                    .accessibilityAddTraits(selection == e ? .isSelected : [])
            }
        }
    }

    func cell(_ e: String) -> some View {
        let letter = String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        return Group {
            if e.isEmpty { Text(letter.isEmpty ? "A" : letter).font(.system(size: 13, weight: .semibold, design: .rounded)) }
            else { Text(e).font(.system(size: 16)) }
        }
        .frame(width: 28, height: 28)
        .background(Circle().fill(selection == e ? Tokens.accentSoft : Color.clear))
        .overlay { Circle().strokeBorder(selection == e ? Tokens.accent : Color.clear, lineWidth: 1.5) }
    }
}

/// One quiet line for where sync stands: updating, when it last worked, or what went wrong.
struct FriendsStatusLine: View {
    @Bindable var friends: FriendsStore
    /// In the panel beside the board, where the page already shows a failed update.
    var brief = false
    var body: some View {
        HStack(spacing: Space.xxs) {
            switch friends.status {
            case .checking, .syncing:
                ProgressView().controlSize(.mini); Text("Updating")
            case .ready:
                Text(friends.lastSync.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Up to date")
                Button { Task { await friends.refresh() } } label: { Image(systemName: "arrow.clockwise").hitTarget() }
                    .buttonStyle(.plain).help("Update now").accessibilityLabel("Update now")
            case .failed where brief:
                Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                Text("Couldn't update")
            case .failed(let why), .unavailable(let why):
                Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                Text(why).fixedSize(horizontal: false, vertical: true)
            case .off:
                EmptyView()
            }
        }
        .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
    }
}

// MARK: before sharing

/// Before sharing: a small podium, a title, one line, your avatar and name, one button. The details sit behind the info button.
struct FriendsIntro: View {
    @Bindable var c: SessionController
    @Bindable var friends: FriendsStore
    @State private var name = ""
    @State private var emoji = ""
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let shared = "Friends see the name and avatar you pick and your daily time on task, slips and streak. Never your tasks, apps, sites or screen. It goes through your iCloud account."

    struct Figure: Identifiable { var id: Int { place }; var emoji: String; var place: Int; var hue: Int }
    static let figures = [Figure(emoji: "\u{1F43C}", place: 1, hue: 1), Figure(emoji: "\u{1F98A}", place: 0, hue: 2), Figure(emoji: "\u{1F438}", place: 2, hue: 5)]

    var body: some View {
        VStack(spacing: Space.l) {
            stage
            VStack(spacing: Space.xxs) {
                Text("Focus with friends").font(Tokens.text(.headline, .semibold))
                HStack(spacing: Space.xxs) {
                    Text("A weekly race, and a cheer when someone needs one.").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
                    InfoTip(text: Self.shared + " Turn it off any time and what you shared is deleted.")
                }
            }
            HStack(spacing: Space.xs) {
                AvatarButton(emoji: $emoji, name: name, size: 34)
                TextField("Your name", text: $name).wellField(height: 34).font(Tokens.text(.body)).frame(width: 200)
                    .onSubmit(turnOn).accessibilityLabel("Your name on the board")
            }
            VStack(spacing: Space.xs) {
                Button(action: turnOn) { Text("Start sharing") }
                    .buttonStyle(FocusButtonStyle(.primary)).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || friends.status == .checking)
                FriendsStatusLine(friends: friends).multilineTextAlignment(.center).frame(maxWidth: 360)
            }
        }
        .padding(.vertical, Space.xxl).padding(.horizontal, Space.xl).frame(maxWidth: .infinity)
        .modifier(CardSurface())
        .frame(maxWidth: 560).frame(maxWidth: .infinity)
        .onAppear {
            if name.isEmpty { name = c.prefs.friendName.isEmpty ? Self.firstName() : c.prefs.friendName }
            if emoji.isEmpty { emoji = c.prefs.friendEmoji }
            up = true
        }
    }

    func turnOn() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        c.prefs.friendName = String(n.prefix(40)); c.prefs.friendEmoji = emoji
        Task { await friends.setSharing(true) }
    }

    /// A suggestion only, from this Mac's account name. It is shown in the field and sent only if you join.
    static func firstName() -> String { NSFullUserName().split(separator: " ").first.map(String.init) ?? "" }

    /// Three made-up friends on a small podium, so the idea is clear before anything is shared.
    var stage: some View {
        HStack(alignment: .bottom, spacing: Space.xs) {
            ForEach(Self.figures) { f in
                VStack(spacing: Space.xs) {
                    FriendAvatar(name: "", emoji: f.emoji, hue: FriendHue.all[f.hue], size: f.place == 0 ? 40 : 34)
                        .overlay(alignment: .bottomTrailing) { RankBadge(rank: f.place + 1).scaleEffect(0.85).offset(x: 3, y: 3) }
                    RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous).fill(PodiumPlace.steps[f.place])
                        .frame(width: 60, height: [28, 18, 10][f.place])
                        .scaleEffect(x: 1, y: up || reduceMotion ? 1 : 0.05, anchor: .bottom)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(Double(2 - f.place) * 0.06), value: up)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
