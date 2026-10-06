//
//  ScoreboardView.swift
//  Dartify
//

import SwiftUI

/// Full-screen TV scoreboard: every player's remaining score, the current visit, checkout and match banners.
struct ScoreboardView: View {
    let model: Scoreboard

    var body: some View {
        ZStack {
            Color(hex: 0x0E1116).ignoresSafeArea()

            if let match = model.match {
                matchView(match)
            } else {
                VStack(spacing: 24) {
                    Text("DARTIFY")
                        .font(.system(size: 96, weight: .black))
                        .foregroundStyle(Accent.mint.solid)
                    Text("Start a match on your iPhone")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private func matchView(_ match: Scoreboard.Match) -> some View {
        VStack(spacing: 44) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text("DARTIFY")
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(Accent.mint.solid)
                Text(match.title)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if !model.cameraStatus.isEmpty {
                    Label(model.cameraStatus, systemImage: "camera.viewfinder")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Accent.coral.solid)
                }
            }

            HStack(spacing: 28) {
                ForEach(Array(match.players.enumerated()), id: \.offset) { i, player in
                    PlayerColumn(player: player, isCurrent: i == match.currentIndex && match.winner == nil, showLegs: match.showLegs)
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 28) {
                ForEach(0..<3, id: \.self) { i in
                    DartCard(score: i < match.visit.count ? match.visit[i] : nil)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(match.isBust ? "BUST" : "\(match.visitScore)")
                        .font(.system(size: 96, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(match.isBust ? Soft.danger : .white)
                    Text(match.checkout.map { "↳ \($0)" } ?? " ")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Accent.slot(match.currentIndex).solid)
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
                    .shadow(radius: 40)
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
    let showLegs: Bool

    var body: some View {
        let accent = Accent.slot(player.seat)
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Text(String(player.name.prefix(1)).uppercased())
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(accent.ink)
                    .frame(width: 56, height: 56)
                    .background(accent.tint, in: Circle())
                Text(player.name)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Text("\(player.scoreLeft)")
                .font(.system(size: isCurrent ? 170 : 120, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(isCurrent ? .white : .white.opacity(0.55))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            HStack(spacing: 28) {
                if showLegs { Text("Legs \(player.legsWon)") }
                Text("Avg \(player.average.map { String(format: "%.1f", $0) } ?? "–")")
            }
            .font(.system(size: 28, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.5))
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            isCurrent ? accent.solid.opacity(0.18) : .white.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 36, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(accent.solid, lineWidth: isCurrent ? 5 : 0)
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
                .foregroundStyle(score == nil ? .white.opacity(0.25) : .white)
            Text(score.map { "\($0.points)" } ?? " ")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(color.opacity(score == nil ? 0.06 : 0.3), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(color.opacity(0.8), lineWidth: score == nil ? 0 : 3))
    }

    /// Board colours: trebles and the bull red, doubles and 25 green, singles neutral.
    private var color: Color {
        switch score?.ring {
        case .treble, .bull: Soft.danger
        case .double, .outerBull: Accent.mint.solid
        case .miss: .gray
        default: .white
        }
    }
}

#Preview(traits: .landscapeLeft) {
    let model = Scoreboard()
    model.match = .init(
        title: "501 · Best of 3",
        players: [
            .init(name: "Max", scoreLeft: 141, legsWon: 1, average: 58.4, seat: 0),
            .init(name: "Anna", scoreLeft: 236, legsWon: 0, average: 47.1, seat: 1),
            .init(name: "Leo", scoreLeft: 301, legsWon: 0, average: 39.0, seat: 2),
        ],
        currentIndex: 0,
        visit: [BoardScore(ring: .treble, number: 20)],
        visitScore: 60,
        isBust: false,
        checkout: "T20 T19 D12",
        showLegs: true,
        banner: nil,
        winner: nil
    )
    return ScoreboardView(model: model)
}
