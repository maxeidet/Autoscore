//
//  GameView.swift
//  Dartify
//

import SwiftUI
import UIKit

/// The match screen on the phone: camera with the board overlay, every player's score, the current visit
/// (tap a dart to correct it), and the winner card at the end.
struct GameView: View {
    let match: MatchController
    /// Back to the home screen, keeping the match so it can be resumed.
    let onLeave: () -> Void
    /// The match is over and saved; start the same match again.
    let onRematch: () -> Void
    /// The match is over and saved; go home.
    let onFinish: () -> Void

    @State private var camera = CameraController()
    @State private var showDebug = false
    @State private var editing: DartSlot?

    private var game: X01Game { match.game }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            BoardOverlay(detection: camera.detection, darts: match.visit)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                topBar
                PlayerStrip(game: game)
                Spacer()
                if showDebug {
                    DebugPanel(debug: camera.isLocked ? camera.dartState?.debug ?? DetectionDebug() : camera.detection.debug)
                }
                VisitPanel(match: match, edit: { editing = DartSlot(index: $0) })
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            if game.isFinished {
                WinnerCard(
                    game: game,
                    undo: match.undo,
                    rematch: { match.recordIfFinished(); onRematch() },
                    home: { match.recordIfFinished(); onFinish() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: game.isFinished)
        .sheet(item: $editing, onDismiss: camera.endEditing) { slot in
            DartEditor(
                slot: slot.index,
                current: slot.index < match.visit.count ? match.visit[slot.index].score : nil,
                pick: { match.correctDart(at: slot.index, to: $0) }
            )
            .presentationDetents([.medium, .large])
            .onAppear(perform: camera.beginEditing)
        }
        .task { await camera.start() }
        .task(id: match.id) { match.attach(camera) }
        .onChange(of: camera.status, initial: true) { _, status in
            Scoreboard.shared.cameraStatus = status
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            match.detach()
            camera.stop()
            Scoreboard.shared.cameraStatus = ""
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Menu {
                if !camera.isLocked {
                    Button("Lock board now", systemImage: "lock", action: camera.lockNow)
                        .disabled(camera.detection.boardToImage == nil)
                }
                Button("Recalibrate", systemImage: "scope", action: camera.recalibrate)
                Toggle("Debug view", systemImage: "ladybug", isOn: $showDebug)
                Divider()
                Button("Leave match", systemImage: "house", role: .destructive, action: onLeave)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Soft.slate)
                    .frame(width: 44, height: 44)
                    .softFloat(Circle())
            }

            Text("\(game.config.startingScore)" + (game.config.legs > 1 ? " · Leg \(game.leg)" : "") + " · R\(game.round)")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Soft.slate)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(height: 36)
                .softFloat(Capsule())

            Spacer()

            if !camera.status.isEmpty {
                Label(camera.status, systemImage: "camera.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(Accent.coral.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Accent.coral.tint, in: Capsule())
            } else if Scoreboard.shared.tvConnected {
                Image(systemName: "tv")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Accent.mint.ink)
                    .frame(width: 36, height: 36)
                    .background(Accent.mint.tint, in: Circle())
            }
        }
    }
}

// MARK: - Players

/// Compact score cards for every player, like the React app's compact `ScoreDisplay`.
private struct PlayerStrip: View {
    let game: X01Game

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(game.players.enumerated()), id: \.element.id) { i, player in
                PlayerCard(
                    player: player,
                    accent: Accent.slot(i),
                    isCurrent: i == game.currentPlayerIndex && !game.isFinished,
                    isBust: i == game.currentPlayerIndex && game.isBust,
                    dartsInVisit: game.visitDarts.count,
                    checkout: i == game.currentPlayerIndex ? game.checkoutHint : nil,
                    showLegs: game.config.legs > 1
                )
            }
        }
    }
}

private struct PlayerCard: View {
    let player: X01Player
    let accent: Accent
    let isCurrent: Bool
    let isBust: Bool
    let dartsInVisit: Int
    let checkout: String?
    let showLegs: Bool

    var body: some View {
        VStack(spacing: 4) {
            SoftAvatar(name: player.name, size: 28, accent: accent)
            Text(player.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isCurrent ? Soft.slate : Soft.slateSoft)
                .lineLimit(1)
            if showLegs {
                Text("Legs \(player.legsWon)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Soft.subtle)
            }
            Text("\(player.scoreLeft)")
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()
                .displayTracking()
                .contentTransition(.numericText())
                .foregroundStyle(isCurrent ? Soft.slate : Soft.slateSoft)
            Text(checkout.map { "Out: \($0)" } ?? "Avg \(player.threeDartAverage.map { String(format: "%.1f", $0) } ?? "0")")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(checkout != nil ? accent.ink : Soft.subtle)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if isCurrent {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i < dartsInVisit ? accent.solid : Soft.track)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(isCurrent ? 1 : 0.78))
                .shadow(color: Soft.shadow.opacity(isCurrent ? 0.18 : 0), radius: 12, y: 8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isBust ? Soft.danger : accent.solid, lineWidth: isCurrent ? 2 : 0)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: player.scoreLeft)
    }
}

// MARK: - Visit

/// The current visit: three darts (tap to correct), the visit score, checkout, undo and next.
private struct VisitPanel: View {
    let match: MatchController

    let edit: (Int) -> Void

    private var game: X01Game { match.game }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    DartCell(score: i < match.visit.count ? match.visit[i].score : nil) {
                        // Empty slots can be filled in order, for darts the camera missed.
                        if i <= match.visit.count { edit(i) }
                    }
                }
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(game.isBust ? Soft.danger : Soft.subtle)
                    Text(game.isBust ? "BUST" : "\(game.visitScore)")
                        .font(.system(size: 30, weight: .semibold))
                        .monospacedDigit()
                        .displayTracking()
                        .contentTransition(.numericText())
                        .foregroundStyle(game.isBust ? Soft.danger : Soft.slate)
                }
                Spacer()
                Button(action: match.undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(match.canUndo ? Soft.slate : Soft.subtle)
                        .frame(width: 52, height: 52)
                        .softFloat(Circle())
                }
                .buttonStyle(SoftPressStyle())
                .disabled(!match.canUndo)

                Button(action: match.nextVisit) {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 22)
                }
                .buttonStyle(SoftPrimaryButtonStyle(height: 52))
                .fixedSize()
                .disabled(game.isFinished)
            }
        }
        .padding(10)
        .softShell()
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: match.visit)
    }

    private var statusLine: String {
        let name = game.currentPlayer.name
        if let leg = game.legWinnerIndex { return "Leg to \(game.players[leg].name) – pull your darts" }
        if game.isBust { return "\(name) – pull your darts" }
        if game.isVisitOver { return "\(name) – pull your darts" }
        if let hint = game.checkoutHint { return "\(name) · \(game.currentPlayer.scoreLeft) · \(hint)" }
        return "\(name) · dart \(game.visitDarts.count + 1)"
    }
}

/// One dart of the visit, coloured like the React app's tap grid: doubles mint, trebles coral, bull dark.
private struct DartCell: View {
    let score: BoardScore?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(score?.label ?? "–")
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                if let score {
                    Text("\(score.points)")
                        .font(.system(size: 12, weight: .semibold))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(background)
                    .shadow(color: Soft.shadow.opacity(score == nil ? 0 : 0.08), radius: 3, y: 1)
            }
        }
        .buttonStyle(SoftPressStyle())
    }

    private var background: Color {
        switch score?.ring {
        case .double: Accent.mint.tint
        case .treble: Accent.coral.tint
        case .outerBull: Soft.charcoal
        case .bull: Soft.danger
        case .single: .white
        case .miss, nil: Soft.track
        }
    }

    private var foreground: Color {
        switch score?.ring {
        case .double: Accent.mint.ink
        case .treble: Accent.coral.ink
        case .outerBull, .bull: .white
        case .single: Soft.slate
        case .miss, nil: Soft.subtle
        }
    }
}

// MARK: - Winner

private struct WinnerCard: View {
    let game: X01Game
    let undo: () -> Void
    let rematch: () -> Void
    let home: () -> Void

    var body: some View {
        let index = game.winnerIndex ?? 0
        let winner = game.players[index]
        let accent = Accent.slot(index)
        ZStack {
            Color(red: 20 / 255, green: 24 / 255, blue: 32 / 255).opacity(0.32)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(accent.ink)
                        .frame(width: 60, height: 60)
                        .background(accent.tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Text("\(winner.name) wins.")
                        .font(.system(size: 28, weight: .semibold))
                        .displayTracking()
                        .foregroundStyle(Soft.slate)
                        .padding(.top, 16)
                    Text("Finished in \(winner.dartsThrown) darts")
                        .font(.system(size: 15))
                        .monospacedDigit()
                        .foregroundStyle(Soft.subtle)
                        .padding(.top, 6)

                    HStack(spacing: 0) {
                        ForEach(Array(game.players.enumerated()), id: \.element.id) { i, player in
                            VStack(spacing: 4) {
                                SoftAvatar(name: player.name, size: 28, accent: Accent.slot(i))
                                Text(player.threeDartAverage.map { String(format: "%.1f", $0) } ?? "–")
                                    .font(.system(size: 17, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Soft.slate)
                                Text(game.config.legs > 1 ? "\(player.legsWon) legs" : "avg")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Soft.subtle)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity)
                .softCard()

                Button(action: rematch) {
                    Label("Rematch", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SoftPrimaryButtonStyle(height: 54))

                HStack(spacing: 8) {
                    Button("Undo last dart", action: undo)
                        .buttonStyle(SoftSecondaryButtonStyle())
                    Button("Home", action: home)
                        .buttonStyle(SoftSecondaryButtonStyle())
                }
            }
            .padding(8)
            .softShell()
            .padding(.horizontal, 24)
        }
    }
}
