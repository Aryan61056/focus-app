import SwiftUI

// Friends (docs/SOCIAL.md). The owner asked for this page to feel fun rather than analytical (2026-10-16), so it is the one place that
// steps outside Workspace's "not too playful": a podium, medals, emoji avatars, a soft color per friend, cheers that pop. The rest still
// holds: amber only for slips, no flashing, Reduce Motion gets a fade, and nothing on the page names an app, site or task.

/// A friend's color: one of six soft hues, picked from their id so a person keeps the same color on every Mac. You are always green.
/// `soft` fills avatars, bubbles and tracks; `strong` is for shapes only (bars, rings), never for small text.
struct FriendHue {
    var soft: Color
    var strong: Color
    static let all: [FriendHue] = [
        FriendHue(soft: Color(light: 0xDCEBFF, dark: 0x1E2F45), strong: Color(light: 0x2F74D0, dark: 0x7FB2F5)),   // sky
        FriendHue(soft: Color(light: 0xEDE3FF, dark: 0x2F2645), strong: Color(light: 0x7B55D6, dark: 0xB59CF5)),   // lilac
        FriendHue(soft: Color(light: 0xFFE6D6, dark: 0x45291D), strong: Color(light: 0xD9692E, dark: 0xF5A57A)),   // peach
        FriendHue(soft: Color(light: 0xFFF2C7, dark: 0x40361A), strong: Color(light: 0xC29300, dark: 0xEBCB6A)),   // butter
        FriendHue(soft: Color(light: 0xFFE0EA, dark: 0x45212D), strong: Color(light: 0xD04A78, dark: 0xF290B2)),   // rose
        FriendHue(soft: Color(light: 0xD6F3F3, dark: 0x1B3A3B), strong: Color(light: 0x1F8F92, dark: 0x6FD0D2)),   // teal
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
    @State private var board = Scoreboard.Board.focused
    @State private var removing: Scoreboard.Entry?

    var body: some View {
        Group {
            if friends.sharing {
                PanelLayout(panelWidth: 288) {
                    Scroller { page.padding(.horizontal, Space.xl).padding(.top, Space.l).padding(.bottom, Space.xl) }
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
            Text("You stop seeing each other's weeks. You can invite them again later.")
        }
    }

    var page: some View {
        let entries = friends.entries(board)
        // The podium holds the first three ranked people; everyone else races below it.
        let podium = Array(entries.filter { $0.rank != nil }.prefix(3))
        let rest = entries.filter { e in !podium.contains { $0.id == e.id } }
        return VStack(alignment: .leading, spacing: Space.xl) {
            header(entries)
            if entries.count <= 1 {
                Lonely(friends: friends)
            } else {
                if !podium.isEmpty {
                    Podium(entries: podium, board: board, friends: friends, removing: $removing).id(board)
                }
                if !rest.isEmpty {
                    RaceList(entries: rest, leader: entries.map(\.focusedSeconds).max() ?? 0, board: board, friends: friends, removing: $removing)
                }
                Text(board == .focused
                     ? "Ranked by time on task. Slips are Focus's calls, and Focus can be wrong. A fresh board every week."
                     : "Ranked by slips per hour on task, after an hour of focus. Focus can be wrong. A fresh board every week.")
                    .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 880, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }

    func header(_ entries: [Scoreboard.Entry]) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(alignment: .center, spacing: Space.m) {
                Text("This week's board").font(Tokens.rounded(.title2, .bold)).lineLimit(1).fixedSize()
                Spacer(minLength: Space.s)
                // The full label when there is room; the icon alone in a narrow window, never a squeezed title.
                ViewThatFits(in: .horizontal) {
                    invite.labelStyle(.titleAndIcon)
                    invite.labelStyle(.iconOnly).help("Invite a friend")
                }
            }
            Text(Self.leadLine(entries, board: board)).font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.xs) {
                ForEach(Scoreboard.Board.allCases) { b in
                    Button { board = b } label: {
                        Label(b.rawValue, systemImage: b == .focused ? "timer" : "scope").labelStyle(.titleAndIcon).fixedSize()
                    }
                    .buttonStyle(ChoiceStyle(on: board == b))
                }
                Spacer(minLength: Space.xs)
                Text(Self.weekTitle(.now)).font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.ink2).monospacedDigit().fixedSize()
                    .padding(.horizontal, Space.xs).frame(height: 22).background(Capsule().fill(Tokens.control))
            }
            .padding(.top, Space.xs)
        }
    }

    var invite: some View {
        Button { Task { await friends.invite() } } label: { Label("Invite a friend", systemImage: "person.badge.plus") }
            .buttonStyle(FocusButtonStyle(.primary)).fixedSize()
    }

    /// One friendly line about the race, from the numbers on the board. Never about what anyone was doing.
    static func leadLine(_ entries: [Scoreboard.Entry], board: Scoreboard.Board) -> String {
        guard entries.count > 1, let top = entries.first, top.rank == 1 else { return "Invite friends and see whose week goes furthest." }
        let you = entries.first { $0.isYou }
        switch board {
        case .focused:
            if top.isYou { return "You're out in front with \(durationText(top.focusedSeconds)). Keep it rolling." }
            if let you, top.focusedSeconds > you.focusedSeconds {
                return "\(top.name) leads with \(durationText(top.focusedSeconds)). You're \(durationText(top.focusedSeconds - you.focusedSeconds)) behind."
            }
            return "\(top.name) leads with \(durationText(top.focusedSeconds))."
        case .steady:
            if top.isYou { return "Your week is the steadiest on the board." }
            return "\(top.name) has the steadiest week so far."
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

/// First, second and third on steps, second on the left and third on the right. The steps rise into place when the page opens.
struct Podium: View {
    var entries: [Scoreboard.Entry]
    var board: Scoreboard.Board
    @Bindable var friends: FriendsStore
    @Binding var removing: Scoreboard.Entry?
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let order = [1, 0, 2].filter { $0 < entries.count }
        HStack(alignment: .bottom, spacing: Space.m) {
            ForEach(order, id: \.self) { i in
                PodiumPlace(entry: entries[i], place: i, board: board, up: up || reduceMotion, friends: friends, removing: $removing)
                    .frame(maxWidth: 240)
            }
        }
        .frame(maxWidth: .infinity)
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

    static let medals = ["\u{1F947}", "\u{1F948}", "\u{1F949}"]
    static let heights: [CGFloat] = [118, 88, 66]
    /// The steps themselves: gold, silver and bronze, soft enough to sit under text.
    static let steps = [Color(light: 0xFFEDB8, dark: 0x5C4A17), Color(light: 0xE8EBEF, dark: 0x3A3F46), Color(light: 0xF8DCC8, dark: 0x58361F)]

    var body: some View {
        let k = TextScale.shared.factor
        let hue = FriendHue.of(entry.id, you: entry.isYou)
        let rank = min(3, max(1, entry.rank ?? place + 1))
        VStack(spacing: Space.xs) {
            ZStack(alignment: .topTrailing) {
                FriendAvatar(name: entry.name, emoji: entry.emoji, hue: hue, size: place == 0 ? 76 : 62)
                Text(Self.medals[rank - 1]).font(.system(size: (place == 0 ? 28 : 24) * k)).offset(x: 10, y: -8)
                    .accessibilityHidden(true)
            }
            .padding(.bottom, Space.xxs)
            Text(entry.isYou ? "You" : entry.name).font(Tokens.rounded(.headline, .bold)).lineLimit(1)
            Text(board == .focused ? durationText(entry.focusedSeconds) : (entry.slipsPerHour.map { String(format: "%.1f slips an hour", $0) } ?? "\(entry.slips) slips"))
                .font(Tokens.rounded(.callout, .semibold)).foregroundStyle(Tokens.ink).monospacedDigit().lineLimit(1)
            HStack(spacing: Space.xxs) { StreakChip(days: entry.streak); SlipChip(slips: entry.slips) }
            action.frame(height: 32 * k)
            // The step, with the place written large on it.
            RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).fill(Self.steps[rank - 1])
                .overlay(alignment: .top) {
                    Text("\(rank)").font(Tokens.rounded(.display, .heavy)).foregroundStyle(Tokens.ink.opacity(0.22)).padding(.top, Space.xs)
                }
                .frame(height: Self.heights[place] * k)
                .scaleEffect(x: 1, y: up ? 1 : 0.05, anchor: .bottom)
                .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(Double(2 - place) * 0.08), value: up)
        }
        .contextMenu { if !entry.isYou { Button("Remove \(entry.name)\u{2026}") { removing = entry } } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowLabel(entry))
    }

    @ViewBuilder var action: some View {
        if entry.isYou {
            Text("That's you").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
        } else if !friends.seesYou(entry.id) {
            InviteBackChip(name: entry.name, friends: friends)
        } else {
            QuickCheer(entry: entry, friends: friends)
        }
    }
}

// MARK: the race

/// Everyone after the podium, each on a track as long as the leader's week.
struct RaceList: View {
    var entries: [Scoreboard.Entry]
    var leader: Double
    var board: Scoreboard.Board
    @Bindable var friends: FriendsStore
    @Binding var removing: Scoreboard.Entry?
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                if i > 0 { Divider().overlay(Tokens.line).padding(.leading, 76) }
                RaceRow(entry: e, leader: leader, board: board, friends: friends, removing: $removing)
            }
        }
        .padding(.vertical, Space.xxs)
        .modifier(CardSurface(radius: Tokens.radiusFloat))
    }
}

struct RaceRow: View {
    var entry: Scoreboard.Entry
    var leader: Double
    var board: Scoreboard.Board
    @Bindable var friends: FriendsStore
    @Binding var removing: Scoreboard.Entry?

    var body: some View {
        let k = TextScale.shared.factor
        // Cheers at the right when the row has room, under the track when it does not, so chips and names never get cut.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s) {
                lead
                details.frame(minWidth: 220 * k, maxWidth: .infinity, alignment: .leading)
                // One width for every row's action, so all the tracks end at the same place.
                action.frame(width: 160 * k, alignment: .trailing)
            }
            HStack(alignment: .top, spacing: Space.s) {
                lead
                VStack(alignment: .leading, spacing: Space.xs) { details; action.fixedSize() }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .background { if entry.isYou { RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).fill(Tokens.accentSoft.opacity(0.5)).padding(.horizontal, Space.xxs) } }
        .contextMenu { if !entry.isYou { Button("Remove \(entry.name)\u{2026}") { removing = entry } } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowLabel(entry))
    }

    var hue: FriendHue { FriendHue.of(entry.id, you: entry.isYou) }

    var lead: some View {
        HStack(spacing: Space.s) {
            Text(entry.rank.map(String.init) ?? "\u{2013}").font(Tokens.rounded(.title3, .bold)).foregroundStyle(Tokens.ink2).monospacedDigit()
                .frame(width: 26 * TextScale.shared.factor)
            FriendAvatar(name: entry.name, emoji: entry.emoji, hue: hue, size: 40)
        }
    }

    var details: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.xs) {
                Text(entry.isYou ? "You" : entry.name).font(Tokens.text(.body, .semibold)).lineLimit(1)
                StreakChip(days: entry.streak).fixedSize()
                SlipChip(slips: entry.slips).fixedSize()
            }
            RaceTrack(fraction: leader > 0 ? entry.focusedSeconds / leader : 0, hue: hue, label: trackLabel)
        }
    }

    var trackLabel: String {
        if board == .focused { return durationText(entry.focusedSeconds) }
        return entry.slipsPerHour.map { String(format: "%.1f an hour", $0) } ?? "Needs an hour"
    }

    @ViewBuilder var action: some View {
        if entry.isYou { Color.clear }
        else if !friends.seesYou(entry.id) { InviteBackChip(name: entry.name, friends: friends) }
        else { QuickCheer(entry: entry, friends: friends) }
    }
}

/// A rounded track filled in the person's color up to their share of the leader's time, with the time riding at the end.
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
                    Capsule().fill(hue.strong).frame(width: max(10, g.size.width * min(1, fraction)))
                        .scaleEffect(x: shown || reduceMotion ? 1 : 0.02, anchor: .leading)
                }
            }
            .frame(height: 10)
            Text(label).font(Tokens.rounded(.callout, .semibold)).monospacedDigit().lineLimit(1).fixedSize()
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.15)) { shown = true } }
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
            if let emoji { Text(emoji).font(.system(size: size * 0.52 * k)) }
            else { Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()).font(.system(size: size * 0.42 * k, weight: .bold, design: .rounded)).foregroundStyle(Tokens.ink) }
        }
        .frame(width: size * k, height: size * k)
        .overlay { Circle().strokeBorder(hue.strong.opacity(0.45), lineWidth: 2) }
        .accessibilityHidden(true)
    }
}

/// Focus days in a row, with a flame. Hidden under two days, so a new streak is never a "1" that reads like a warning.
struct StreakChip: View {
    var days: Int
    var body: some View {
        if days >= 2 {
            Text("\u{1F525} \(days)").font(Tokens.text(.caption, .semibold)).monospacedDigit()
                .padding(.horizontal, 7).frame(height: 20).background(Capsule().fill(Tokens.control))
                .help("\(days) focus days in a row").accessibilityLabel("\(days) focus days in a row")
        }
    }
}

/// Slips in amber, the only amber on the page; a clean week gets a green chip instead.
struct SlipChip: View {
    var slips: Int
    var body: some View {
        Text(slips == 0 ? "No slips" : (slips == 1 ? "1 slip" : "\(slips) slips"))
            .font(Tokens.text(.caption, .semibold)).monospacedDigit()
            .foregroundStyle(slips == 0 ? Tokens.accentInk : Tokens.slipInk)
            .padding(.horizontal, 7).frame(height: 20)
            .background(Capsule().fill(slips == 0 ? Tokens.accentSoft : Tokens.slipSoft))
    }
}

/// A friend who shares with you but cannot see yours yet.
struct InviteBackChip: View {
    var name: String
    @Bindable var friends: FriendsStore
    var body: some View {
        Button { Task { await friends.invite() } } label: {
            Label("Invite back", systemImage: "arrow.uturn.backward").font(Tokens.text(.caption, .semibold)).lineLimit(1)
                .padding(.horizontal, Space.s).frame(height: 26)
                .background(Capsule().strokeBorder(Tokens.accent.opacity(0.6), lineWidth: 1))
                .foregroundStyle(Tokens.accentInk).contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(name) can't see your week yet. Invite them back.")
        .accessibilityLabel("\(name) can't see your week yet. Invite back.")
    }
}

/// Three emoji to send in one click, and more behind the last button. The sent emoji floats up and fades.
struct QuickCheer: View {
    var entry: Scoreboard.Entry
    @Bindable var friends: FriendsStore
    @State private var more = false
    @State private var flying: CheerKind = .fire
    @State private var flights = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let left = friends.cheersLeft(for: entry.id)
        Group {
            if left == 0 {
                Label("Cheered today", systemImage: "checkmark").font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.ink2)
            } else {
                buttons(left)
            }
        }
        .overlay(alignment: .top) { flight }
    }

    func buttons(_ left: Int) -> some View {
        HStack(spacing: 2) {
            ForEach([CheerKind.fire, .clap, .strong], id: \.self) { k in
                Button { send(k) } label: { Text(k.text).font(.system(size: 17)).frame(width: 30, height: 28) }
                    .buttonStyle(CheerButtonStyle())
                    .help("Send \(k.spoken.lowercased())").accessibilityLabel("Send \(entry.name) \(k.spoken.lowercased())")
            }
            Button { more = true } label: { Image(systemName: "ellipsis.bubble").font(Tokens.symbol(14)).foregroundStyle(Tokens.ink2).frame(width: 30, height: 28) }
                .buttonStyle(CheerButtonStyle())
                .help("More cheers").accessibilityLabel("More cheers for \(entry.name)")
                .popover(isPresented: $more, arrowEdge: .bottom) {
                    CheerPicker(name: entry.name, left: left) { k in more = false; send(k) }
                }
        }
        .padding(2)
        .background(Capsule().fill(Tokens.control))
    }

    /// Rests invisible; each send plays it once.
    var flight: some View {
        Text(flying.isEmoji ? flying.text : "\u{1F4AC}").font(.system(size: 24))
            .keyframeAnimator(initialValue: Flight(), trigger: flights) { v, f in
                v.opacity(f.opacity).scaleEffect(f.scale).offset(y: f.rise)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) { LinearKeyframe(1, duration: 0.05); LinearKeyframe(1, duration: 0.45); CubicKeyframe(0, duration: 0.3) }
                KeyframeTrack(\.scale) { SpringKeyframe(1.35, duration: 0.3, spring: .bouncy); CubicKeyframe(1, duration: 0.5) }
                KeyframeTrack(\.rise) { CubicKeyframe(-40, duration: 0.8) }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }

    struct Flight { var opacity = 0.0, scale = 0.6, rise = 0.0 }

    func send(_ k: CheerKind) {
        flying = k
        if !reduceMotion { flights += 1 }
        Task { _ = await friends.send(k, to: entry.id) }
    }
}

/// Every cheer: the five emoji, then the five lines. Nothing to type.
struct CheerPicker: View {
    var name: String
    var left: Int
    var pick: (CheerKind) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Cheer \(name) on").font(Tokens.rounded(.callout, .bold))
            HStack(spacing: Space.xxs) {
                ForEach(CheerKind.emoji, id: \.self) { k in
                    Button { pick(k) } label: { Text(k.text).font(.system(size: 22)).frame(width: 38, height: 38) }
                        .buttonStyle(CheerButtonStyle()).accessibilityLabel(k.spoken)
                }
            }
            VStack(spacing: 2) {
                ForEach(CheerKind.lines, id: \.self) { k in
                    Button { pick(k) } label: { Text(k.text).font(Tokens.text(.body)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Space.xs).frame(height: 30) }
                        .buttonStyle(CheerButtonStyle())
                }
            }
            Text(left == 1 ? "1 more today" : "\(left) more today").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
        }
        .padding(Space.m).frame(width: 248)
    }
}

struct CheerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @State private var hover = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous).fill(configuration.isPressed ? Tokens.controlHover : (hover ? Tokens.window2 : Color.clear)))
                .scaleEffect(scale)
                .contentShape(RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous))
                .onHover { hover = $0 }
                .animation(.spring(response: 0.22, dampingFraction: 0.6), value: hover)
                .animation(.spring(response: 0.18, dampingFraction: 0.7), value: configuration.isPressed)
        }
        var scale: CGFloat {
            if reduceMotion { return 1 }
            return configuration.isPressed ? 0.88 : (hover ? 1.08 : 1)
        }
    }
}

/// Nobody else on the board yet.
struct Lonely: View {
    @Bindable var friends: FriendsStore
    var body: some View {
        VStack(spacing: Space.m) {
            Text("\u{1F44B}").font(.system(size: 44)).accessibilityHidden(true)
            VStack(spacing: Space.xxs) {
                Text("It's just you so far").font(Tokens.rounded(.title3, .bold))
                Text("Invite a friend. When you've both accepted, your weeks race side by side here.")
                    .font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).multilineTextAlignment(.center).frame(maxWidth: 380).fixedSize(horizontal: false, vertical: true)
            }
            Button { Task { await friends.invite() } } label: { Label("Invite a friend", systemImage: "person.badge.plus") }
                .buttonStyle(FocusButtonStyle(.primary))
        }
        .padding(.vertical, 40).frame(maxWidth: .infinity)
        .modifier(CardSurface(radius: Tokens.radiusFloat))
    }
}

// MARK: the panel

/// The panel at the right: cheers you got, how you look on the board, and the switch.
struct FriendsPanel: View {
    @Bindable var c: SessionController
    @Bindable var friends: FriendsStore
    var body: some View {
        PanelSection(title: "Cheers for you") {
            if friends.cheers.isEmpty {
                Text("When a friend cheers you on, it lands here.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(friends.cheers.prefix(8)) { ch in
                        CheerBubble(cheer: ch, name: friends.name(of: ch.from), emoji: friends.friends.first { $0.id == ch.from }?.emoji)
                    }
                }
            }
        }
        .onAppear { friends.markCheersSeen() }
        .onChange(of: friends.cheers.count) { _, _ in friends.markCheersSeen() }
        Divider().overlay(Tokens.line)
        PanelSection(title: "You on the board") {
            VStack(alignment: .leading, spacing: Space.s) {
                AvatarPicker(selection: Binding(get: { c.prefs.friendEmoji }, set: { c.prefs.friendEmoji = $0; Task { await friends.refresh() } }),
                             name: c.prefs.friendName)
                TextField("Your name", text: Binding(get: { c.prefs.friendName }, set: { c.prefs.friendName = String($0.prefix(40)) }))
                    .wellField(height: 30).font(Tokens.text(.body))
                    .onSubmit { Task { await friends.refresh() } }
                Text("Friends see your daily time on task, slips and streak. Never your tasks, apps, sites or screen.")
                    .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
        Divider().overlay(Tokens.line)
        VStack(alignment: .leading, spacing: Space.xs) {
            Toggle("Share with friends", isOn: Binding(get: { friends.sharing }, set: { on in Task { await friends.setSharing(on) } }))
                .toggleStyle(.switch).controlSize(.small).tint(Tokens.accent).font(Tokens.text(.body))
            FriendsStatusLine(friends: friends)
            Text("Turning this off deletes what you shared.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
        }
    }
}

/// A cheer as a speech bubble from the friend's avatar, in their color.
struct CheerBubble: View {
    var cheer: Cheer
    var name: String
    var emoji: String?
    var body: some View {
        let hue = FriendHue.of(cheer.from, you: false)
        let shape = UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 4, bottomTrailingRadius: 14, topTrailingRadius: 14, style: .continuous)
        HStack(alignment: .bottom, spacing: Space.xs) {
            FriendAvatar(name: name, emoji: emoji, hue: hue, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(cheer.kind.text).font(cheer.kind.isEmoji ? .system(size: 24) : Tokens.text(.body, .medium))
                    .padding(.horizontal, cheer.kind.isEmoji ? Space.xs : Space.s).padding(.vertical, cheer.kind.isEmoji ? 2 : 6)
                    .background(shape.fill(hue.soft))
                Text("\(name) \u{00B7} \(cheer.at.formatted(.relative(presentation: .named)))").font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(cheer.kind.spoken), \(cheer.at.formatted(.relative(presentation: .named)))")
    }
}

/// Twelve avatars and your first letter. A fixed list, so nothing typed travels.
struct AvatarPicker: View {
    @Binding var selection: String
    var name: String
    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(34), spacing: 4), count: 7)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
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
            if e.isEmpty { Text(letter.isEmpty ? "A" : letter).font(.system(size: 14, weight: .bold, design: .rounded)) }
            else { Text(e).font(.system(size: 18)) }
        }
        .frame(width: 32, height: 32)
        .background(Circle().fill(selection == e ? Tokens.accentSoft : Color.clear))
        .overlay { Circle().strokeBorder(selection == e ? Tokens.accent : Color.clear, lineWidth: 2) }
    }
}

/// One quiet line for where sync stands: updating, when it last worked, or what went wrong in plain words.
struct FriendsStatusLine: View {
    @Bindable var friends: FriendsStore
    var body: some View {
        HStack(spacing: Space.xxs) {
            switch friends.status {
            case .checking, .syncing:
                ProgressView().controlSize(.mini); Text("Updating")
            case .ready:
                Text(friends.lastSync.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Up to date")
                Button { Task { await friends.refresh() } } label: { Image(systemName: "arrow.clockwise").hitTarget() }
                    .buttonStyle(.plain).help("Update now").accessibilityLabel("Update now")
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

/// Before sharing: a little podium of made-up friends, pick a look and a name, one button.
struct FriendsIntro: View {
    @Bindable var c: SessionController
    @Bindable var friends: FriendsStore
    @State private var name = ""
    @State private var emoji = ""
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Figure: Identifiable { var id: Int { place }; var emoji: String; var place: Int; var hue: Int }
    static let figures = [Figure(emoji: "\u{1F43C}", place: 1, hue: 1), Figure(emoji: "\u{1F98A}", place: 0, hue: 2), Figure(emoji: "\u{1F438}", place: 2, hue: 5)]

    var body: some View {
        VStack(spacing: Space.xl) {
            stage
            VStack(spacing: Space.xs) {
                Text("Focus is more fun with friends").font(Tokens.rounded(.title2, .bold)).multilineTextAlignment(.center)
                Text("Race your friends to the most focused week, keep streaks going together, and send a cheer when someone needs one. Only daily totals are shared, never your tasks, apps, sites or screen.")
                    .font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).multilineTextAlignment(.center).frame(maxWidth: 460).fixedSize(horizontal: false, vertical: true)
            }
            form
        }
        .padding(.vertical, 40).padding(.horizontal, Space.xl).frame(maxWidth: .infinity)
        .modifier(CardSurface(radius: Tokens.radiusFloat))
        .frame(maxWidth: 720).frame(maxWidth: .infinity)
        .onAppear {
            if name.isEmpty { name = c.prefs.friendName.isEmpty ? Self.firstName() : c.prefs.friendName }
            if emoji.isEmpty { emoji = c.prefs.friendEmoji }
            up = true
        }
    }

    var form: some View {
        VStack(spacing: Space.s) {
            FriendAvatar(name: name.isEmpty ? "?" : name, emoji: emoji.isEmpty ? nil : emoji, hue: .you, size: 56)
            AvatarPicker(selection: $emoji, name: name).frame(width: 7 * 38)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Your name on the board").font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.ink2)
                TextField("Your name on the board", text: $name).labelsHidden().wellField(height: 34).font(Tokens.text(.body))
                    .onSubmit(turnOn)
            }
            .frame(width: 260)
            Button(action: turnOn) { Label("Join the board", systemImage: "person.2.fill") }
                .buttonStyle(FocusButtonStyle(.primary)).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || friends.status == .checking)
                .padding(.top, Space.xxs)
            FriendsStatusLine(friends: friends).multilineTextAlignment(.center).frame(maxWidth: 360)
            Text("Uses your iCloud account. Turn it off any time and what you shared is deleted.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                .multilineTextAlignment(.center)
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

    /// Three made-up friends on a small podium, so you can see the idea before sharing anything.
    var stage: some View {
        HStack(alignment: .bottom, spacing: Space.s) {
            ForEach(Self.figures) { f in
                VStack(spacing: Space.xs) {
                    ZStack(alignment: .topTrailing) {
                        FriendAvatar(name: "", emoji: f.emoji, hue: FriendHue.all[f.hue], size: f.place == 0 ? 54 : 46)
                        Text(PodiumPlace.medals[f.place]).font(.system(size: 18)).offset(x: 6, y: -6)
                    }
                    RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).fill(PodiumPlace.steps[f.place])
                        .frame(width: 84, height: [72, 52, 38][f.place])
                        .scaleEffect(x: 1, y: up || reduceMotion ? 1 : 0.05, anchor: .bottom)
                        .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(Double(2 - f.place) * 0.08), value: up)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
