//
//  ProfileView.swift
//  Dartify
//
//  Profile in the soft style: a ticket-like card with your stats, then your players and recent matches.
//

import SwiftData
import SwiftUI

struct ProfileView: View {
    @Query(sort: \MatchStat.date, order: .reverse) private var myMatches: [MatchStat]
    @State private var store = LocalStore.shared
    @State private var tab: Tab = .players
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var nameError: String?
    @State private var addingPlayer = false
    @State private var newPlayer = ""
    @State private var appeared = false

    private enum Tab: Hashable { case players, matches }

    /// The main user's saved stats (SwiftData), the same numbers the Stats page shows.
    private var me: StatSummary { StatSummary(matches: myMatches) }
    /// The linked main player's name; nil until one is picked or added.
    private var myName: String? { store.mainPlayer?.name }
    private var recentMatches: [MatchRecord] { Array(store.matches.suffix(5).reversed()) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                profileSection.rise(0, appeared)
                listSection.rise(1, appeared)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Soft.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        // Home hides the bar; show it again here so the back button (and swipe back) is available.
        .toolbar(.visible, for: .navigationBar)
        .onAppear { appeared = true }
        .sensoryFeedback(.success, trigger: myName)
        .sensoryFeedback(.impact(weight: .light), trigger: store.players.count)
    }

    // MARK: - Profile ticket

    private var profileSection: some View {
        VStack(spacing: 0) {
            ShellTitle(systemImage: "person.crop.circle.fill", title: "Profile") {
                SoftIconButton(systemImage: editingName ? "xmark" : "pencil", size: 40, action: toggleNameEditing)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)

            VStack(spacing: 0) {
                identityRow
                    .padding(20)
                statGrid
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                Perforation()
                footer
                    .padding(20)
            }
            .softCard()
        }
        .padding(8)
        .softShell()
    }

    @ViewBuilder private var identityRow: some View {
        if editingName {
            VStack(alignment: .leading, spacing: 8) {
                PillField(systemImage: "at", placeholder: "Your name", text: $nameDraft, autofocus: true, onSubmit: saveName) {
                    Button("Save", action: saveName)
                        .buttonStyle(PillButtonStyle())
                        .disabled(nameDraft.trimmed.isEmpty)
                }
                .textInputAutocapitalization(.words)
                if let nameError {
                    Text(nameError)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Soft.danger)
                        .padding(.leading, 16)
                }
            }
            .transition(.blurReplace)
        } else if myName == nil && !store.players.isEmpty {
            playerPicker
                .transition(.blurReplace)
        } else {
            Button(action: toggleNameEditing) {
                HStack(spacing: 16) {
                    SoftAvatar(name: myName ?? "?", size: 60, accent: .azure)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(myName ?? "Add your name")
                            .font(.system(size: 24, weight: .semibold))
                            .displayTracking()
                            .foregroundStyle(myName == nil ? Soft.subtle : Soft.slate)
                        identitySubtitle
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Soft.subtle)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(SoftPressStyle())
            .transition(.blurReplace)
        }
    }

    /// No main player yet: pick yourself from the saved players (or use the pencil to add a new one).
    private var playerPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Which player are you?")
                .font(.system(size: 22, weight: .semibold))
                .displayTracking()
                .foregroundStyle(Soft.slate)
            Text("Your stats are saved for this player.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Soft.subtle)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.players) { player in
                        Button {
                            withAnimation(.snappy) { store.setMainPlayer(player) }
                        } label: {
                            HStack(spacing: 8) {
                                SoftAvatar(name: player.name, size: 28)
                                Text(player.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Soft.slate)
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 14)
                            .frame(height: 38)
                            .softFloat(Capsule())
                        }
                        .buttonStyle(SoftPressStyle())
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
            .padding(.top, 8)
        }
    }

    private var identitySubtitle: Text {
        if myName == nil { return Text("Your stats are saved for this player") }
        if me.played == 0 { return Text("No games yet") }
        return Text("^[\(me.played) match](inflect: true) played")
    }

    private var statGrid: some View {
        HStack(alignment: .top, spacing: 0) {
            StatColumn(label: "Average", value: me.average.map { String(format: "%.1f", $0) })
            StatColumn(label: "Wins", value: me.played > 0 ? "\(me.wins)" : nil)
            StatColumn(label: "Played", value: me.played > 0 ? "\(me.played)" : nil)
            StatColumn(label: "Win rate", value: me.winRate.map { $0.formatted(.percent.precision(.fractionLength(0))) })
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !store.players.isEmpty {
                HStack(spacing: -10) {
                    ForEach(store.players.prefix(3)) { player in
                        SoftAvatar(name: player.name, size: 38)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(store.players.isEmpty ? "No players yet" : "^[\(store.players.count) player](inflect: true)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Soft.slate)
                if let last = store.matches.last {
                    Label("Last game \(last.date, format: .relative(presentation: .named))", systemImage: "checkmark")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Accent.mint.ink)
                } else {
                    Text("Finish a game to start your stats")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Soft.subtle)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            NavigationLink {
                StatsView()
            } label: {
                Label("Stats", systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Soft.slate)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .softFloat(Capsule())
            }
            .buttonStyle(SoftPressStyle())
        }
    }

    private func toggleNameEditing() {
        nameDraft = myName ?? ""
        nameError = nil
        withAnimation(.snappy) { editingName.toggle() }
    }

    /// Renames your player, or (with none linked yet) links the player with this name, adding them if needed.
    private func saveName() {
        guard !nameDraft.trimmed.isEmpty else { return }
        if let me = store.mainPlayer {
            guard store.rename(me, to: nameDraft) else {
                nameError = "Another player is already called \(nameDraft.trimmed)."
                return
            }
        } else {
            store.makeMainPlayer(named: nameDraft)
        }
        withAnimation(.snappy) { editingName = false }
    }

    // MARK: - Players / matches

    private var listSection: some View {
        VStack(spacing: 8) {
            ShellTitle(systemImage: "person.2.fill", title: "Players") {
                SoftSegmented(options: [(value: Tab.players, label: "Roster"), (value: Tab.matches, label: "Recent")], selection: $tab)
                    .frame(width: 176)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            switch tab {
            case .players: playerCards
            case .matches: matchCards
            }

            addControls
                .padding(.top, 4)
        }
        .padding(8)
        .softShell()
    }

    @ViewBuilder private var playerCards: some View {
        if store.players.isEmpty {
            EmptyCard(systemImage: "person.crop.circle.badge.plus", title: "No players yet",
                      message: "Add the people you play with.")
        } else {
            ForEach(store.players) { player in
                let s = stats(for: player.name)
                InfoCard(name: player.name, title: player.name, subtitle: s.summary) {
                    if store.isMain(player) {
                        SoftBadge(accent: .azure, text: "You")
                    } else if s.wins > 0 {
                        SoftBadge(accent: Accent.forName(player.name), text: s.wins == 1 ? "1 win" : "\(s.wins) wins")
                    }
                }
                .contextMenu {
                    // Your own player can't be removed; it holds your stats.
                    if !store.isMain(player) {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            withAnimation(.snappy) { store.removePlayer(player) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var matchCards: some View {
        if recentMatches.isEmpty {
            EmptyCard(systemImage: "target", title: "No matches yet", message: "Finished games show up here.")
        } else {
            ForEach(recentMatches) { match in
                InfoCard(
                    name: match.winnerName,
                    title: "\(match.winnerName) won",
                    subtitle: "\(match.startingScore) · \(match.players.map(\.name).formatted(.list(type: .and)))"
                ) {
                    SoftBadge(accent: Accent.forName(match.winnerName),
                              text: match.date.formatted(.relative(presentation: .named)))
                }
            }
        }
    }

    @ViewBuilder private var addControls: some View {
        if addingPlayer {
            HStack(spacing: 8) {
                PillField(systemImage: "person", placeholder: "Player name", text: $newPlayer,
                          fill: .white, autofocus: true, onSubmit: addPlayer) {
                    Button("Add", action: addPlayer)
                        .buttonStyle(PillButtonStyle())
                        .disabled(newPlayer.trimmed.isEmpty)
                }
                .textInputAutocapitalization(.words)
                SoftIconButton(systemImage: "xmark", size: 52) {
                    withAnimation(.snappy) {
                        addingPlayer = false
                        newPlayer = ""
                    }
                }
            }
            .transition(.blurReplace)
        } else {
            Button {
                withAnimation(.snappy) { addingPlayer = true }
            } label: {
                Label("Add player", systemImage: "plus")
            }
            .buttonStyle(SoftPrimaryButtonStyle(height: 52))
            .transition(.blurReplace)
        }
    }

    private func addPlayer() {
        guard !newPlayer.trimmed.isEmpty else { return }
        withAnimation(.snappy) {
            store.addPlayer(named: newPlayer)
            tab = .players
        }
        newPlayer = ""
    }

    // MARK: - Stats

    private func stats(for name: String) -> PlayerStats {
        var s = PlayerStats()
        guard !name.isEmpty else { return s }
        for match in store.matches {
            guard let result = match.players.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            s.played += 1
            s.points += result.points
            s.darts += result.darts
            if match.winnerName.caseInsensitiveCompare(name) == .orderedSame { s.wins += 1 }
        }
        return s
    }
}

private struct PlayerStats {
    var played = 0
    var wins = 0
    var points = 0
    var darts = 0

    var average: Double? { darts > 0 ? Double(points) / Double(darts) * 3 : nil }
    var winRate: Double? { played > 0 ? Double(wins) / Double(played) : nil }

    var summary: String {
        guard played > 0 else { return "No games yet" }
        let games = played == 1 ? "1 game" : "\(played) games"
        guard let average else { return games }
        return "\(String(format: "%.1f", average)) avg · \(games)"
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Pieces

/// Grey label over a large value, like the ticket's Date / Gate / Seat row.
private struct StatColumn: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Soft.subtle)
            Text(value ?? "–")
                .font(.system(size: 20, weight: .semibold))
                .displayTracking()
                .monospacedDigit()
                .foregroundStyle(value == nil ? Soft.subtle : Soft.slate)
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Dashed tear line with a notch cut out on each side.
private struct Perforation: View {
    var body: some View {
        ZStack {
            DashLine()
                .stroke(Soft.subtle.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 6]))
                .frame(height: 1.5)
                .padding(.horizontal, 20)
            HStack {
                notch.offset(x: -9)
                Spacer()
                notch.offset(x: 9)
            }
        }
        .frame(height: 18)
    }

    private var notch: some View {
        Circle().fill(Soft.shell).frame(width: 18, height: 18)
    }
}

private struct DashLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// One white card per row: avatar, title, subtitle and a trailing badge.
private struct InfoCard<Trailing: View>: View {
    let name: String
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            SoftAvatar(name: name, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .displayTracking()
                    .foregroundStyle(Soft.slate)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Soft.subtle)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
        .padding(14)
        .padding(.trailing, 4)
        .softCard()
        .contentShape(.contextMenuPreview, .rect(cornerRadius: 24))
    }
}

private struct EmptyCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .softCard()
    }
}

/// Pill input that turns white while focused, with a trailing button inside.
private struct PillField<Trailing: View>: View {
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    var fill: Color = Soft.track.opacity(0.7)
    var autofocus = false
    let onSubmit: () -> Void
    @ViewBuilder var trailing: Trailing
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Soft.subtle)
            TextField(placeholder, text: $text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Soft.slate)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(onSubmit)
            trailing
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 52)
        .background(focused ? Color.white : fill, in: Capsule())
        .overlay(Capsule().stroke(focused ? Soft.subtle.opacity(0.35) : Soft.line))
        .animation(.easeOut(duration: 0.15), value: focused)
        .task { if autofocus { focused = true } }
    }
}

/// Small charcoal pill button used inside fields.
private struct PillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Soft.charcoal.opacity(isEnabled ? 1 : 0.25), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .modelContainer(for: MatchStat.self, inMemory: true)
}
