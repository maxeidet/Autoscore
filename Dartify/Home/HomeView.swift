//
//  HomeView.swift
//  Dartify
//
//  Home screen in the React app's soft style: header, resume card, season stats and game modes.
//

import SwiftUI

struct HomeView: View {
    @State private var store = LocalStore.shared
    @State private var match: MatchController?
    @State private var showingGame = false
    @State private var showingSetup = false
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header.rise(0, appeared)
                if let match, !match.game.isFinished {
                    ResumeCard(match: match, resume: { showingGame = true }, discard: { self.match = nil })
                        .rise(1, appeared)
                }
                statsSection.rise(2, appeared)
                playSection.rise(3, appeared)
                Text("Dartify · camera scoring")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Soft.subtle)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Soft.canvas.ignoresSafeArea())
        .onAppear { appeared = true }
        .sheet(isPresented: $showingSetup) {
            MatchSetupSheet { config, players in
                match = MatchController(config: config, players: players)
                showingGame = true
            }
        }
        .fullScreenCover(isPresented: $showingGame) {
            if let match {
                GameView(
                    match: match,
                    onLeave: { showingGame = false },
                    onRematch: { self.match = MatchController(config: match.config, players: match.roster) },
                    onFinish: {
                        showingGame = false
                        self.match = nil
                    }
                )
            }
        }
        .onChange(of: match == nil) { _, noMatch in
            if noMatch { Scoreboard.shared.match = nil }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Image("BDCLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 36)
                Text(greeting)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Soft.subtle)
            }
            Spacer()
            if Scoreboard.shared.tvConnected {
                Image(systemName: "tv")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Accent.mint.ink)
                    .frame(width: 48, height: 48)
                    .softFloat(Circle())
            }
        }
        .padding(.horizontal, 8)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 5 { return "Late session" }
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: - Stats

    private var statsSection: some View {
        let average = store.threeDartAverage
        let played = store.matches.count
        let headline = if let average {
            "Averaging \(String(format: "%.1f", average)) a visit."
        } else if played > 0 {
            "\(played) \(played == 1 ? "game" : "games") in the books."
        } else {
            "No games yet. The board is waiting."
        }

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ShellTitle(systemImage: "chart.pie.fill", title: "Season")
                Text(headline)
                    .font(.system(size: 26, weight: .semibold))
                    .displayTracking()
                    .foregroundStyle(Soft.slate)
                    .padding(.top, 20)
                if played > 0 && average != nil {
                    Text("\(played) \(played == 1 ? "game" : "games") played")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Soft.subtle)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)

            HStack(spacing: 0) {
                StatTile(systemImage: "target", accent: .mint, value: average.map { String(format: "%.1f", $0) }, label: "3-dart avg")
                Divider().padding(.vertical, 16)
                StatTile(systemImage: "trophy.fill", accent: .azure, value: store.highestCheckout.map(String.init), label: "High out")
                Divider().padding(.vertical, 16)
                StatTile(systemImage: "flame.fill", accent: .coral, value: store.bestLegDarts.map(String.init), label: "Best leg")
            }
            .padding(8)
            .softCard()
        }
        .padding(8)
        .softShell()
    }

    // MARK: - Play

    private var playSection: some View {
        VStack(spacing: 8) {
            ShellTitle(systemImage: "target", title: "Play")
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ModeRow(systemImage: "scope", accent: .mint, title: "X01", subtitle: "301 · 501 · 701", badge: "Classic") {
                showingSetup = true
            }
            ModeRow(systemImage: "clock", accent: .azure, title: "Around the Clock", subtitle: "Hit 1 to 20 in order", badge: "Soon")
            ModeRow(systemImage: "globe", accent: .orchid, title: "Round the World", subtitle: "Points on every number", badge: "Soon")
            ModeRow(systemImage: "list.bullet.rectangle", accent: .coral, title: "Cricket", subtitle: "Close out 15 to 20 and bull", badge: "Soon")

            Button {
                showingSetup = true
            } label: {
                Label("New match", systemImage: "plus")
            }
            .buttonStyle(SoftPrimaryButtonStyle())
            .padding(.top, 4)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .padding(8)
        .softShell()
    }
}

/// Game mode row: tinted icon tile, title, subtitle and a badge. No action means "coming soon".
private struct ModeRow: View {
    let systemImage: String
    let accent: Accent
    let title: String
    let subtitle: String
    let badge: String
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent.ink)
                    .frame(width: 54, height: 54)
                    .background(accent.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(action == nil ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .displayTracking()
                        .foregroundStyle(action == nil ? Soft.subtle : Soft.slate)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Soft.subtle)
                }
                .lineLimit(1)
                Spacer()
                SoftBadge(accent: accent, text: badge)
            }
            .padding(10)
            .padding(.trailing, 6)
            .softCard()
        }
        .buttonStyle(SoftPressStyle())
        .disabled(action == nil)
    }
}

/// "Pick up where you left off" card for a match in progress.
private struct ResumeCard: View {
    let match: MatchController
    let resume: () -> Void
    let discard: () -> Void

    var body: some View {
        let game = match.game
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Accent.mint.ink).frame(width: 8, height: 8)
                    Text("In progress")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Accent.mint.ink)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Accent.mint.tint, in: Capsule())
                Spacer()
                Text("Round \(game.round)")
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Soft.subtle)
            }

            Text("Pick up where you left off.")
                .font(.system(size: 22, weight: .semibold))
                .displayTracking()
                .foregroundStyle(Soft.slate)
                .padding(.top, 16)

            HStack(spacing: 12) {
                HStack(spacing: -8) {
                    ForEach(Array(game.players.prefix(4).enumerated()), id: \.element.id) { i, player in
                        SoftAvatar(name: player.name, size: 30, accent: Accent.slot(i))
                    }
                }
                Text(game.players.map { "\($0.name) \($0.scoreLeft)" }.joined(separator: " · "))
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Soft.slateSoft)
                    .lineLimit(1)
            }
            .padding(.top, 12)

            Button(action: resume) {
                Label("Resume game", systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(SoftPrimaryButtonStyle(height: 52))
            .padding(.top, 20)

            Button("Discard match", role: .destructive, action: discard)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Soft.subtle)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .padding(20)
        .softCard()
        .padding(8)
        .softShell()
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}

private extension View {
    /// Staggered entrance for the stacked cards (`.soft-rise`).
    func rise(_ index: Int, _ appeared: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.spring(response: 0.52, dampingFraction: 0.86).delay(Double(index) * 0.06), value: appeared)
    }
}

#Preview {
    HomeView()
}
