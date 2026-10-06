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
    /// Shown instead of the camera feed (Xcode previews have no camera).
    var backdrop: Image?

    @State private var camera = CameraController()
    @State private var showDebug = false
    @State private var editing: DartSlot?

    private var game: X01Game { match.game }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let backdrop {
                Color.clear
                    .overlay(backdrop.resizable().scaledToFill())
                    .clipped()
                    .ignoresSafeArea()
            } else {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
            }

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
        .task { if backdrop == nil { await camera.start() } }
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

    /// Glass controls floating over the camera: menu, match info and camera status.
    private var topBar: some View {
        GlassEffectContainer(spacing: 10) {
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
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: Circle())
                }

                Text("\(game.config.startingScore)" + (game.config.legs > 1 ? " · Leg \(game.leg)" : "") + " · R\(game.round)")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .glassEffect(.regular, in: Capsule())

                Spacer()

                if !camera.status.isEmpty {
                    Label(camera.status, systemImage: "camera.viewfinder")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .glassEffect(.regular.tint(Accent.coral.solid.opacity(0.55)), in: Capsule())
                } else if Scoreboard.shared.tvConnected {
                    Image(systemName: "tv")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.tint(Accent.mint.solid.opacity(0.55)), in: Circle())
                }
            }
        }
    }
}

// MARK: - Players

/// Glass score cards for every player, like the React app's compact `ScoreDisplay`.
/// The current player's card is tinted with their seat colour (red on a bust).
private struct PlayerStrip: View {
    let game: X01Game

    var body: some View {
        GlassEffectContainer(spacing: 8) {
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
                .lineLimit(1)
            if showLegs {
                Text("Legs \(player.legsWon)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text("\(player.scoreLeft)")
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()
                .displayTracking()
                .contentTransition(.numericText())
            Text(checkout.map { "Out: \($0)" } ?? "Avg \(player.threeDartAverage.map { String(format: "%.1f", $0) } ?? "0")")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if isCurrent {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i < dartsInVisit ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .foregroundStyle(isCurrent ? .primary : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassEffect(glass, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: player.scoreLeft)
    }

    private var glass: Glass {
        if isBust { return .regular.tint(Soft.danger.opacity(0.6)) }
        if isCurrent { return .regular.tint(accent.solid.opacity(0.55)) }
        return .regular
    }
}

// MARK: - Visit

/// The current visit: three glass darts (tap to correct), the visit score and checkout, undo and next.
private struct VisitPanel: View {
    let match: MatchController

    let edit: (Int) -> Void

    private var game: X01Game { match.game }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
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
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(game.isBust ? "BUST" : "\(game.visitScore)")
                            .font(.system(size: 30, weight: .semibold))
                            .monospacedDigit()
                            .displayTracking()
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .glassEffect(
                        game.isBust ? .regular.tint(Soft.danger.opacity(0.6)) : .regular,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )

                    Button(action: match.undo) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .disabled(!match.canUndo)

                    Button(action: match.nextVisit) {
                        Label("Next", systemImage: "chevron.right")
                            .font(.system(size: 17, weight: .semibold))
                            .padding(.horizontal, 8)
                            .frame(height: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Soft.charcoal)
                    .disabled(game.isFinished)
                }
            }
        }
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

/// One dart of the visit as interactive glass, tinted like the React app's tap grid:
/// doubles mint, trebles coral, bull red, 25 dark, singles clear.
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
            .foregroundStyle(score == nil ? .secondary : .primary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .glassEffect(glass.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var glass: Glass {
        switch score?.ring {
        case .double: .regular.tint(Accent.mint.solid.opacity(0.6))
        case .treble: .regular.tint(Accent.coral.solid.opacity(0.6))
        case .bull: .regular.tint(Soft.danger.opacity(0.7))
        case .outerBull: .regular.tint(Soft.charcoal.opacity(0.7))
        case .single, .miss, nil: .regular
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
/*
#Preview("Mid-visit") {
    GameView(match: .preview(), onLeave: {}, onRematch: {}, onFinish: {}, backdrop: Image("PreviewBoard"))
}

#Preview("Bust") {
    GameView(match: .preview(bust: true), onLeave: {}, onRematch: {}, onFinish: {}, backdrop: Image("PreviewBoard"))
}

#Preview("Winner") {
    GameView(match: .preview(finished: true), onLeave: {}, onRematch: {}, onFinish: {}, backdrop: Image("PreviewBoard"))
}
*/
