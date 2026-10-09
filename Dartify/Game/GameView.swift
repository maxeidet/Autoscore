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
                case .x01(let game): PlayerStrip(game: game, input: match.input)
                case .killer(let game): KillerStrip(game: game, input: match.input)
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

/// What the current player should do now, shown as a pill on their turn card.
private struct TurnHint {
    var systemImage: String
    var text: String
    /// Highlighted, e.g. a checkout route.
    var emphasis = false

    /// The visit is over and waits for the next one: pull the darts (camera) or press Next (tap board).
    static func visitDone(_ prefix: String, input: ScoringInput) -> TurnHint {
        TurnHint(systemImage: input == .camera ? "hand.raised" : "chevron.right.circle",
                 text: "\(prefix) · \(input == .camera ? "pull your darts" : "tap Next")")
    }
}

/// X01: a large glass card for the player whose turn it is, then the others in the order they throw next.
private struct PlayerStrip: View {
    let game: X01Game
    let input: ScoringInput

    var body: some View {
        let i = game.currentPlayerIndex
        let player = game.players[i]
        let others = upNext(after: i, count: game.players.count)

        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                TurnCard(
                    name: player.name,
                    accent: Accent.slot(i),
                    score: "\(player.scoreLeft)",
                    scoreCaption: "to go",
                    visit: game.isBust ? "BUST" : "\(game.visitScore)",
                    visitCaption: "this visit",
                    stats: [("Avg", player.threeDartAverage.map { String(format: "%.1f", $0) } ?? "–"),
                            ("Darts", "\(player.dartsThrown)")]
                        + (game.config.legs > 1 ? [("Legs", "\(player.legsWon)")] : []),
                    hint: hint,
                    dartsInVisit: game.visitDarts.count,
                    alert: game.isBust ? Soft.danger : nil
                )
                if !others.isEmpty {
                    WaitingRow {
                        ForEach(others, id: \.self) { j in
                            WaitingChip(name: game.players[j].name, accent: Accent.slot(j), value: "\(game.players[j].scoreLeft)")
                        }
                    }
                }
            }
        }
    }

    /// Nothing while the player is simply throwing; the bars on the card already show the darts.
    private var hint: TurnHint? {
        if let leg = game.legWinnerIndex { return .visitDone("Leg to \(game.players[leg].name)", input: input) }
        if game.isBust { return .visitDone("Bust", input: input) }
        if game.isVisitOver { return .visitDone("Visit done", input: input) }
        if let route = game.checkoutHint { return TurnHint(systemImage: "target", text: route, emphasis: true) }
        return nil
    }
}

/// Killer: the same turn card (their number, points and what to hit), then the others.
private struct KillerStrip: View {
    let game: KillerGame
    let input: ScoringInput

    var body: some View {
        let i = game.currentPlayerIndex
        let player = game.players[i]
        let others = upNext(after: i, count: game.players.count)

        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                TurnCard(
                    name: player.name,
                    accent: Accent.slot(i),
                    score: "\(player.number)",
                    scoreCaption: "your number",
                    visit: player.isKiller ? "KILLER" : "\(player.points)/\(KillerConfig.killerPoints)",
                    visitCaption: "points",
                    stats: [("Taken", "\(player.pointsTaken)"), ("Darts", "\(player.dartsThrown)")],
                    hint: hint,
                    dartsInVisit: game.visitDarts.count,
                    alert: player.isKiller ? Soft.danger : nil,
                    isKiller: player.isKiller
                )
                if !others.isEmpty {
                    WaitingRow {
                        ForEach(others, id: \.self) { j in
                            let p = game.players[j]
                            WaitingChip(
                                name: "\(p.name) · \(p.number)",
                                accent: Accent.slot(j),
                                value: p.isOut ? "OUT" : p.isKiller ? "💀" : "\(p.points)/\(KillerConfig.killerPoints)",
                                isOut: p.isOut
                            )
                        }
                    }
                }
            }
        }
    }

    private var hint: TurnHint? {
        let player = game.currentPlayer
        if game.isVisitOver { return .visitDone("Visit done", input: input) }
        if player.isKiller { return TurnHint(systemImage: "scope", text: "Hit your rivals' numbers", emphasis: true) }
        return TurnHint(systemImage: "number", text: "Hit \(player.number) to reach \(KillerConfig.killerPoints)")
    }
}

/// Seats after `current`, in throwing order.
private func upNext(after current: Int, count: Int) -> [Int] {
    (1..<max(count, 1)).map { (current + $0) % count }
}

/// The current player's glass card: big score on the left, this visit on the right, darts thrown,
/// a hint for what to do now and a few stats. A soft glow in their seat colour sits behind the glass.
private struct TurnCard: View {
    let name: String
    let accent: Accent
    let score: String
    let scoreCaption: String
    let visit: String
    let visitCaption: String
    let stats: [(label: String, value: String)]
    let hint: TurnHint?
    let dartsInVisit: Int
    /// Tints the whole card, e.g. red on a bust.
    var alert: Color?
    var isKiller = false

    private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SoftAvatar(name: name, size: 30, accent: accent)
                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                if isKiller { KillerBadge(size: 13) }
                Spacer()
                DartPips(thrown: dartsInVisit)
            }

            HStack(alignment: .lastTextBaseline) {
                BigValue(value: score, caption: scoreCaption, size: 56, alignment: .leading)
                Spacer()
                BigValue(value: visit, caption: visitCaption, size: 30, alignment: .trailing)
            }

            HStack(spacing: 12) {
                if let hint {
                    Label(hint.text, systemImage: hint.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(hint.emphasis ? accent.ink : Soft.slateSoft)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(hint.emphasis ? accent.tint : .white.opacity(0.7), in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
                Spacer(minLength: 0)
                ForEach(stats, id: \.label) { stat in
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(stat.value)
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(stat.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .foregroundStyle(Soft.slate)
        .padding(16)
        .background {
            // Behind the glass, so the glass picks it up as a soft coloured light.
            Circle()
                .fill(accent.solid.opacity(0.45))
                .frame(width: 180, height: 180)
                .blur(radius: 50)
                .offset(x: -70, y: -60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipShape(shape)
                .allowsHitTesting(false)
        }
        .glassEffect(alert.map { .regular.tint($0.opacity(0.5)) } ?? .regular.tint(.white.opacity(0.4)), in: shape)
        // White glass: keep the text dark even in dark mode over the camera.
        .environment(\.colorScheme, .light)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: score)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: visit)
        .animation(.easeOut(duration: 0.2), value: hint?.text)
    }
}

private struct BigValue: View {
    let value: String
    let caption: String
    let size: CGFloat
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(value)
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .displayTracking()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// Three small bars, filled for darts thrown this visit.
private struct DartPips: View {
    let thrown: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i < thrown ? AnyShapeStyle(Soft.slate) : AnyShapeStyle(Soft.slate.opacity(0.15)))
                    .frame(width: 14, height: 5)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: thrown)
        .accessibilityLabel("\(thrown) of 3 darts thrown")
    }
}

/// The waiting players, scrolling sideways when they don't fit.
private struct WaitingRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content }
        }
        .scrollClipDisabled()
    }
}

private struct WaitingChip: View {
    let name: String
    let accent: Accent
    let value: String
    var isOut = false

    var body: some View {
        HStack(spacing: 6) {
            SoftAvatar(name: name, size: 22, accent: accent)
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .strikethrough(isOut)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .frame(height: 32)
        .glassEffect(.regular, in: Capsule())
        .opacity(isOut ? 0.45 : 1)
    }
}

// MARK: - Visit

/// The current visit in one row: three glass darts (tap to correct), undo and next.
/// The visit total and what to do next live on the turn card above.
private struct VisitPanel: View {
    let match: MatchController

    let edit: (Int) -> Void

    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    DartCell(score: i < match.visit.count ? match.visit[i].score : nil) {
                        // Empty slots can be filled in order, for darts the camera missed.
                        if i <= match.visit.count { edit(i) }
                    }
                }

                Button(action: match.undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 50, height: 58)
                        .contentShape(shape)
                        .glassEffect(.regular.interactive(), in: shape)
                }
                .buttonStyle(.plain)
                .disabled(!match.canUndo)
                .opacity(match.canUndo ? 1 : 0.5)

                Button(action: match.nextVisit) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 58)
                        .contentShape(shape)
                        .glassEffect(.regular.tint(Soft.charcoal).interactive(), in: shape)
                }
                .buttonStyle(.plain)
                .disabled(match.isFinished)
                .accessibilityLabel("Next visit")
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
