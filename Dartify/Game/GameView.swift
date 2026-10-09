//
//  GameView.swift
//  Dartify
//

import SwiftUI
import UIKit

/// The match screen on the phone: the camera with the board overlay (or a board to tap, for tap scoring),
/// every player's score, the current visit (tap a dart to correct it), and the winner card at the end.
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
    @Environment(\.colorScheme) private var colorScheme

    private var usesCamera: Bool { match.input == .camera }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !usesCamera {
                Soft.canvas.ignoresSafeArea()
            } else if let backdrop {
                Color.clear
                    .overlay(backdrop.resizable().scaledToFill())
                    .clipped()
                    .ignoresSafeArea()
            } else {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
            }

            if usesCamera {
                LiveBoardOverlay(camera: camera, darts: match.visit)
                    .ignoresSafeArea()
            }

            VStack(spacing: 10) {
                topBar
                switch match.state {
                case .x01(let game): PlayerStrip(game: game)
                case .killer(let game): KillerStrip(game: game)
                }
                if usesCamera {
                    Spacer()
                    if showDebug {
                        LiveDebugPanel(camera: camera)
                    }
                } else {
                    TapBoardView(darts: match.visit, disabled: match.state.isVisitOver || match.isFinished) {
                        match.dartDetected($0)
                    }
                    .padding(.vertical, 4)
                }
                VisitPanel(match: match, edit: { editing = DartSlot(index: $0) })
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            if let summary = match.winnerSummary {
                WinnerCard(
                    summary: summary,
                    undo: match.undo,
                    rematch: { match.recordIfFinished(); onRematch() },
                    home: { match.recordIfFinished(); onFinish() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: match.isFinished)
        // The tap board sits on the light canvas, so keep the glass and text in light mode there.
        .environment(\.colorScheme, usesCamera ? colorScheme : .light)
        .sheet(item: $editing, onDismiss: { if usesCamera { camera.endEditing() } }) { slot in
            DartEditor(
                slot: slot.index,
                current: slot.index < match.visit.count ? match.visit[slot.index].score : nil,
                pick: { match.correctDart(at: slot.index, to: $0) }
            )
            .presentationDetents([.medium, .large])
            .onAppear { if usesCamera { camera.beginEditing() } }
        }
        .task { if usesCamera && backdrop == nil { await camera.start() } }
        .task(id: match.id) { match.attach(usesCamera ? camera : nil) }
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
                    if usesCamera {
                        if !camera.isLocked {
                            // No `.disabled` on the board here: that reads `detection`, which changes every frame
                            // and rebuilds the open menu so taps get lost. `lockNow` ignores it when there's no board.
                            Button("Lock board now", systemImage: "lock", action: camera.lockNow)
                        }
                        Button("Recalibrate", systemImage: "scope", action: camera.recalibrate)
                        Toggle("Debug view", systemImage: "ladybug", isOn: $showDebug)
                        Divider()
                    }
                    Button("Leave match", systemImage: "house", role: .destructive, action: onLeave)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: Circle())
                }

                Text(match.title)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .glassEffect(.regular, in: Capsule())

                Spacer()

                CameraStatusBadge(camera: usesCamera ? camera : nil)
            }
        }
    }
}

// MARK: - Live camera views
//
// `camera.detection` changes on every frame. Reading it only inside these small views keeps GameView's body
// (and the open menu) from re-rendering at frame rate.

private struct LiveBoardOverlay: View {
    let camera: CameraController
    let darts: [DetectedDart]

    var body: some View {
        BoardOverlay(detection: camera.detection, darts: darts)
    }
}

private struct LiveDebugPanel: View {
    let camera: CameraController

    var body: some View {
        DebugPanel(debug: camera.isLocked ? camera.dartState?.debug ?? DetectionDebug() : camera.detection.debug)
    }
}

/// Camera status pill, or the TV icon when the camera is fine. Also mirrors the status to the TV scoreboard.
/// No camera (tap scoring) shows just the TV icon.
private struct CameraStatusBadge: View {
    let camera: CameraController?

    private var status: String { camera?.status ?? "" }

    var body: some View {
        Group {
            if !status.isEmpty {
                Label(status, systemImage: "camera.viewfinder")
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
        .onChange(of: status, initial: true) { _, status in
            Scoreboard.shared.cameraStatus = status
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

// MARK: - Killer players

/// Glass cards for a Killer game: each player's number, points towards killer, 💀 for killers, OUT when out.
private struct KillerStrip: View {
    let game: KillerGame

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            // Up to four cards in a row, a second row for five or six players.
            let rows = game.players.count > 4
                ? [Array(game.players.indices.prefix(3)), Array(game.players.indices.dropFirst(3))]
                : [Array(game.players.indices)]
            VStack(spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { i in
                            KillerCard(
                                player: game.players[i],
                                accent: Accent.slot(i),
                                isCurrent: i == game.currentPlayerIndex && !game.isFinished,
                                dartsInVisit: game.visitDarts.count
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct KillerCard: View {
    let player: KillerPlayer
    let accent: Accent
    let isCurrent: Bool
    let dartsInVisit: Int

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                SoftAvatar(name: player.name, size: 28, accent: accent)
                if player.isKiller {
                    KillerBadge(size: 13)
                        .offset(x: 16, y: -8)
                }
            }
            Text(player.name)
                .font(.system(size: 12, weight: .semibold))
                .strikethrough(player.isOut)
                .lineLimit(1)
            Text("\(player.number)")
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()
                .displayTracking()
            if player.isOut {
                Text("OUT")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Soft.danger)
            } else if player.isKiller {
                Text("KILLER")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Soft.danger)
            } else {
                KillerPips(points: player.points, filled: accent.solid)
            }
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
        .opacity(player.isOut ? 0.45 : 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassEffect(glass, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: player.points)
    }

    private var glass: Glass {
        if player.isKiller { return .regular.tint(Soft.danger.opacity(isCurrent ? 0.6 : 0.35)) }
        if isCurrent { return .regular.tint(accent.solid.opacity(0.55)) }
        return .regular
    }
}

// MARK: - Visit

/// The current visit: three glass darts (tap to correct), the visit score and checkout, undo and next.
private struct VisitPanel: View {
    let match: MatchController

    let edit: (Int) -> Void

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
                        Text(match.statusLine)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(match.visitHeadline)
                            .font(.system(size: 30, weight: .semibold))
                            .monospacedDigit()
                            .displayTracking()
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .glassEffect(
                        match.isBust ? .regular.tint(Soft.danger.opacity(0.6)) : .regular,
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
                    .disabled(match.isFinished)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: match.visit)
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
    let summary: MatchController.WinnerSummary
    let undo: () -> Void
    let rematch: () -> Void
    let home: () -> Void

    var body: some View {
        let accent = Accent.slot(summary.seat)
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
                    Text("\(summary.name) wins.")
                        .font(.system(size: 28, weight: .semibold))
                        .displayTracking()
                        .foregroundStyle(Soft.slate)
                        .padding(.top, 16)
                    Text(summary.subtitle)
                        .font(.system(size: 15))
                        .monospacedDigit()
                        .foregroundStyle(Soft.subtle)
                        .padding(.top, 6)

                    HStack(spacing: 0) {
                        ForEach(Array(summary.stats.enumerated()), id: \.offset) { i, stat in
                            VStack(spacing: 4) {
                                SoftAvatar(name: stat.name, size: 28, accent: Accent.slot(i))
                                Text(stat.value)
                                    .font(.system(size: 17, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Soft.slate)
                                Text(stat.label)
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

#Preview("Killer") {
    GameView(match: .killerPreview(), onLeave: {}, onRematch: {}, onFinish: {}, backdrop: Image("PreviewBoard"))
}

#Preview("Winner") {
    GameView(match: .preview(finished: true), onLeave: {}, onRematch: {}, onFinish: {}, backdrop: Image("PreviewBoard"))
}
*/
