//
//  ScoreboardView.swift
//  Dartify
//

import SwiftUI

/// Full-screen TV scoreboard in the app's light soft style: every player's remaining score, the current visit,
/// checkout and match banners.
struct ScoreboardView: View {
    let model: Scoreboard

    var body: some View {
        ZStack {
            Soft.canvas.ignoresSafeArea()

            if let match = model.match {
                matchView(match)
            } else {
                VStack(spacing: 24) {
                    Text("DARTIFY")
                        .font(.system(size: 96, weight: .black))
                        .foregroundStyle(Accent.mint.ink)
                    Text("Start a match on your iPhone")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Soft.slateSoft)
                }
            }
        }
    }

    private func matchView(_ match: Scoreboard.Match) -> some View {
        VStack(spacing: 44) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text("DARTIFY")
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(Accent.mint.ink)
                Text(match.title)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Soft.subtle)
                Spacer()
                if !model.cameraStatus.isEmpty {
                    Label(model.cameraStatus, systemImage: "camera.viewfinder")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Accent.coral.ink)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Accent.coral.tint, in: Capsule())
                }
            }

            HStack(spacing: 28) {
                ForEach(Array(match.players.enumerated()), id: \.offset) { i, player in
                    PlayerColumn(player: player, isCurrent: i == match.currentIndex && match.winner == nil)
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 28) {
                ForEach(0..<3, id: \.self) { i in
                    DartCard(score: i < match.visit.count ? match.visit[i] : nil)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(match.visitHeadline)
                        .font(.system(size: 96, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(match.isBust ? Soft.danger : Soft.slate)
                    Text(match.hint.map { "↳ \($0)" } ?? " ")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Accent.slot(match.currentIndex).ink)
                }
                .frame(width: 360, alignment: .leading)
            }
        }
        .padding(70)
        .overlay {
            if let banner = match.banner {
                Text(banner)
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                    .padding(.vertical, 36)
                    .background(bannerColor(match), in: Capsule())
                    .shadow(color: Soft.shadow.opacity(0.3), radius: 40, y: 20)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: match)
    }

    private func bannerColor(_ match: Scoreboard.Match) -> Color {
        if match.isBust { return Soft.danger }
        if match.winner != nil { return Accent.mint.ink }
        return Accent.azure.ink
    }
}

private struct PlayerColumn: View {
    let player: Scoreboard.Player
    let isCurrent: Bool

    var body: some View {
        let accent = Accent.slot(player.seat)
        VStack(spacing: 18) {
            if player.isKiller {
                KillerBadge(size: 44)
            }
            HStack(spacing: 14) {
                Text(String(player.name.prefix(1)).uppercased())
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(accent.ink)
                    .frame(width: 56, height: 56)
                    .background(isCurrent ? .white : accent.tint, in: Circle())
                Text(player.name)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Soft.slate)
                    .lineLimit(1)
            }
            Text(player.value)
                .font(.system(size: isCurrent ? 170 : 120, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(isCurrent ? Soft.slate : Soft.slateSoft)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let points = player.killerPoints {
                KillerPips(points: points, size: 26, filled: player.isKiller ? Soft.danger : accent.solid)
            }
            Text(player.detail)
                .font(.system(size: 28, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Soft.subtle)
        }
        .opacity(player.isOut ? 0.35 : 1)
        .overlay {
            if player.isOut {
                Text("OUT")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(Soft.danger)
                    .rotationEffect(.degrees(-12))
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(player.isKiller ? Soft.danger.opacity(0.12) : isCurrent ? accent.tint : .white)
                .softShadow(near: 0.04, far: isCurrent ? 0.16 : 0.08, radius: 24, y: 14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(player.isKiller ? Soft.danger : accent.solid, lineWidth: isCurrent ? 5 : player.isKiller ? 3 : 0)
        )
        .scaleEffect(isCurrent ? 1 : 0.96)
    }
}

private struct DartCard: View {
    let score: BoardScore?

    var body: some View {
        VStack(spacing: 8) {
            Text(score?.label ?? "–")
                .font(.system(size: 80, weight: .heavy, design: .rounded))
            Text(score.map { "\($0.points)" } ?? " ")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .opacity(0.7)
        }
        .foregroundStyle(foreground)
        .monospacedDigit()
        .frame(maxWidth: .infinity, minHeight: 190)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(background)
                .softShadow(near: 0.04, far: score == nil ? 0 : 0.10, radius: 18, y: 10)
        }
    }

    /// Same colours as the phone's dart boxes: doubles mint, trebles coral, bull red, 25 dark, singles white.
    private var background: Color {
        switch score?.ring {
        case .double: Accent.mint.tint
        case .treble: Accent.coral.tint
        case .bull: Soft.danger
        case .outerBull: Soft.charcoal
        case .single: .white
        case .miss, nil: Soft.track
        }
    }

    private var foreground: Color {
        switch score?.ring {
        case .double: Accent.mint.ink
        case .treble: Accent.coral.ink
        case .bull, .outerBull: .white
        case .single: Soft.slate
        case .miss, nil: Soft.subtle
        }
    }
}

#Preview("X01", traits: .landscapeLeft) {
    let model = Scoreboard()
    model.match = .init(
        title: "501 · Leg 2 · R4",
        players: [
            .init(name: "Max", value: "141", detail: "Legs 1 · Avg 58.4", seat: 0),
            .init(name: "Anna", value: "236", detail: "Legs 0 · Avg 47.1", seat: 1),
            .init(name: "Leo", value: "301", detail: "Legs 0 · Avg 39.0", seat: 2),
        ],
        currentIndex: 0,
        visit: [BoardScore(ring: .treble, number: 20)],
        visitHeadline: "60",
        isBust: false,
        hint: "T19 D12",
        banner: nil,
        winner: nil
    )
    return ScoreboardView(model: model)
}

#Preview("Killer", traits: .landscapeLeft) {
    let model = Scoreboard()
    model.match = .init(
        title: "Killer · R3",
        players: [
            .init(name: "Max", value: "7", detail: "1 / 3", seat: 0, killerPoints: 1),
            .init(name: "Anna", value: "12", detail: "3 / 3", seat: 1, killerPoints: 3, isKiller: true),
            .init(name: "Leo", value: "20", detail: "Out", seat: 2, isOut: true),
            .init(name: "Sara", value: "5", detail: "0 / 3", seat: 3, killerPoints: 0),
        ],
        currentIndex: 3,
        visit: [BoardScore(ring: .double, number: 5)],
        visitHeadline: "2 / 3",
        isBust: false,
        hint: nil,
        banner: nil,
        winner: nil
    )
    return ScoreboardView(model: model)
}
