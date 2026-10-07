//
//  MatchController.swift
//  Dartify
//

import Foundation
import Observation

/// Runs a local match (X01 or Killer): turns camera darts into game moves, handles corrections and undo,
/// announces scores and keeps the TV scoreboard in sync.
///
/// The current visit is replayed from the state at its start every time it changes, so a correction
/// to any dart (say, a single that was really a double) re-scores the whole visit correctly.
@Observable
final class MatchController: Identifiable {
    let id = UUID()
    let settings: MatchSettings
    let roster: [SavedPlayer]

    /// The game including the darts of the current visit.
    private(set) var state: GameState
    /// Darts of the current visit, with their board positions when the camera found them.
    private(set) var visit: [DetectedDart] = []
    /// Set once the finished match has been saved to the history.
    private(set) var isRecorded = false

    @ObservationIgnored private var visitStart: GameState
    @ObservationIgnored private var undoStack: [(start: GameState, visit: [DetectedDart])] = []
    @ObservationIgnored private weak var camera: CameraController?
    @ObservationIgnored private let announcer = Announcer.shared
    @ObservationIgnored private let scoreboard = Scoreboard.shared

    init(settings: MatchSettings, players: [SavedPlayer]) {
        self.settings = settings
        roster = players
        let state = GameState(settings: settings, players: players)
        self.state = state
        visitStart = state
        syncScoreboard()
    }

    var canUndo: Bool { !visit.isEmpty || !undoStack.isEmpty }
    var isFinished: Bool { state.isFinished }

    /// Connects the camera: its darts drive the match, and it learns when a visit is over.
    func attach(_ camera: CameraController) {
        self.camera = camera
        camera.onDart = { [weak self] dart in self?.dartDetected(dart) }
        camera.onDartsPulled = { [weak self] in self?.dartsPulled() }
        camera.setVisit(visit, complete: state.isVisitOver)
        if case .killer = state, undoStack.isEmpty, visit.isEmpty { announceNumbers() }
        announceUp()
    }

    // MARK: - Input

    func dartDetected(_ dart: DetectedDart) {
        // After a bust, checkout or three darts the visit is over; further darts don't count.
        guard !state.isVisitOver else { return }
        visit.append(dart)
        let outcome = replay()
        announcer.say(dart.score.spoken)
        announce(outcome)
    }

    /// Darts pulled out of the board: the visit is done.
    func dartsPulled() {
        guard !visit.isEmpty else { return }
        commitVisit()
    }

    /// "Next" button: end the visit now (unthrown darts are misses) and start fresh from the board as it is.
    func nextVisit() {
        guard !state.isFinished else { return }
        commitVisit()
        camera?.startNewVisit()
    }

    /// Replaces dart `index` of the current visit, appends it when `index` is past the end,
    /// or removes it when `score` is nil.
    func correctDart(at index: Int, to score: BoardScore?) {
        if let score {
            if index < visit.count {
                visit[index].score = score
            } else if !state.isVisitOver {
                visit.append(DetectedDart(x: .nan, y: .nan, score: score))
            }
        } else if index < visit.count {
            visit.remove(at: index)
        }
        let outcome = replay()
        if let score {
            announcer.say("Corrected. \(score.spoken)", interrupt: true)
            announce(outcome)
        } else {
            announcer.say("Dart removed", interrupt: true)
        }
    }

    /// Removes the last dart; with no darts this visit, reopens the previous visit for correcting.
    func undo() {
        if !visit.isEmpty {
            visit.removeLast()
        } else if let previous = undoStack.popLast() {
            visitStart = previous.start
            visit = previous.visit
        }
        replay()
    }

    /// Saves a finished X01 match to the history (once); the season stats are X01 stats.
    func recordIfFinished() {
        guard case .x01(let game) = state, game.isFinished, !isRecorded else { return }
        LocalStore.shared.record(game)
        isRecorded = true
    }

    func detach() {
        camera?.onDart = nil
        camera?.onDartsPulled = nil
        camera = nil
    }

    // MARK: - Game flow

    @discardableResult
    private func replay() -> GameState.Outcome? {
        var s = visitStart
        var counted: [DetectedDart] = []
        var outcome: GameState.Outcome?
        for dart in visit where !s.isVisitOver {
            outcome = s.throwDart(dart.score)
            counted.append(dart)
        }
        visit = counted
        state = s
        camera?.setVisit(visit, complete: state.isVisitOver)
        syncScoreboard()
        return outcome
    }

    private func commitVisit() {
        guard !state.isFinished else { return }
        undoStack.append((visitStart, visit))
        var s = state
        s.endVisit()
        visitStart = s
        visit = []
        state = s
        camera?.setVisit([], complete: false)
        syncScoreboard()
        announceUp()
    }

    // MARK: - Text for the screens

    var title: String {
        switch state {
        case .x01(let g):
            "\(g.config.startingScore)" + (g.config.legs > 1 ? " · Leg \(g.leg)" : "") + " · R\(g.round)"
        case .killer(let g):
            "Killer · R\(g.round)"
        }
    }

    var isBust: Bool {
        if case .x01(let g) = state { return g.isBust }
        return false
    }

    /// Small line above the visit total.
    var statusLine: String {
        let name = state.currentPlayerName
        switch state {
        case .x01(let g):
            if let leg = g.legWinnerIndex { return "Leg to \(g.players[leg].name) – pull your darts" }
            if g.isVisitOver { return "\(name) – pull your darts" }
            if let hint = g.checkoutHint { return "\(name) · \(g.currentPlayer.scoreLeft) · \(hint)" }
            return "\(name) · dart \(g.visitDarts.count + 1)"
        case .killer(let g):
            if g.isVisitOver { return "\(name) – pull your darts" }
            let player = g.currentPlayer
            if player.isKiller { return "\(name) 💀 · hit your rivals' numbers" }
            return "\(name) · hit \(player.number) to reach \(KillerConfig.killerPoints)"
        }
    }

    /// Big text in the visit panel: the visit total in X01, the player's points in Killer.
    var visitHeadline: String {
        switch state {
        case .x01(let g):
            return g.isBust ? "BUST" : "\(g.visitScore)"
        case .killer(let g):
            let player = g.currentPlayer
            return player.isKiller ? "💀 KILLER" : "\(player.points) / \(KillerConfig.killerPoints)"
        }
    }

    /// One line per player for the resume card, e.g. "Max 416" or "Max 2pt".
    var playerSummaries: [String] {
        switch state {
        case .x01(let g): g.players.map { "\($0.name) \($0.scoreLeft)" }
        case .killer(let g): g.players.map { "\($0.name) \($0.isOut ? "out" : "\($0.points)pt")" }
        }
    }

    struct WinnerSummary {
        var name: String
        var seat: Int
        var subtitle: String
        /// Per player: a value and its label, e.g. ("58.4", "avg").
        var stats: [(name: String, value: String, label: String)]
    }

    var winnerSummary: WinnerSummary? {
        guard let winner = state.winnerIndex else { return nil }
        switch state {
        case .x01(let g):
            return WinnerSummary(
                name: g.players[winner].name,
                seat: winner,
                subtitle: "Finished in \(g.players[winner].dartsThrown) darts",
                stats: g.players.map {
                    ($0.name, $0.threeDartAverage.map { String(format: "%.1f", $0) } ?? "–",
                     g.config.legs > 1 ? "\($0.legsWon) legs" : "avg")
                }
            )
        case .killer(let g):
            return WinnerSummary(
                name: g.players[winner].name,
                seat: winner,
                subtitle: "Last one standing after \(g.round) rounds",
                stats: g.players.map { ($0.name, "\($0.pointsTaken)", "taken") }
            )
        }
    }

    // MARK: - Announcements

    private func announce(_ outcome: GameState.Outcome?) {
        switch outcome {
        case .x01(let result): announce(x01: result)
        case .killer(let events): announce(killer: events)
        case nil: break
        }
    }

    private func announce(x01 outcome: X01Game.Outcome) {
        guard case .x01(let g) = state else { return }
        let name = g.currentPlayer.name
        switch outcome {
        case .bust: announcer.say("Bust")
        case .notStarted: announcer.say("No score")
        case .legWon: announcer.say("Game shot! Leg, \(name)")
        case .matchWon: announcer.say("Game shot, and the match! \(name) wins")
        case .scored: if g.visitDarts.count == 3 { announcer.say("\(g.visitScore)") }
        }
    }

    private func announce(killer events: [KillerGame.Event]) {
        guard case .killer(let g) = state else { return }
        for event in events {
            switch event {
            case .ownHit(let player, let points):
                if !g.players[player].isKiller { announcer.say("\(points) \(points == 1 ? "point" : "points")") }
            case .becameKiller(let player):
                announcer.say("\(g.players[player].name) is a killer!")
            case .lostKiller(let player):
                announcer.say("\(g.players[player].name) is no longer a killer")
            case .hit(let player, let count):
                announcer.say("\(g.players[player].name) loses \(count)")
            case .eliminated(let player):
                announcer.say("\(g.players[player].name) is out!")
            case .won(let player):
                announcer.say("\(g.players[player].name) wins!")
            }
        }
    }

    /// Everyone's number at the start of a Killer game.
    private func announceNumbers() {
        guard case .killer(let g) = state else { return }
        announcer.say(g.players.map { "\($0.name), \($0.number)" }.joined(separator: ". "))
    }

    /// Who's up: "Max, you require 40", "Anna, killer", "Leo, number 7", or just the name.
    private func announceUp() {
        guard !state.isFinished else { return }
        switch state {
        case .x01(let g):
            let player = g.currentPlayer
            announcer.say(g.checkoutHint != nil ? "\(player.name), you require \(player.scoreLeft)" : player.name)
        case .killer(let g):
            let player = g.currentPlayer
            announcer.say(player.isKiller ? "\(player.name), killer" : "\(player.name), number \(player.number)")
        }
    }

    // MARK: - TV

    private func syncScoreboard() {
        let players: [Scoreboard.Player]
        let banner: String?
        let hint: String?
        switch state {
        case .x01(let g):
            players = g.players.enumerated().map { i, p in
                let avg = "Avg \(p.threeDartAverage.map { String(format: "%.1f", $0) } ?? "–")"
                return .init(name: p.name, value: "\(p.scoreLeft)",
                             detail: g.config.legs > 1 ? "Legs \(p.legsWon) · \(avg)" : avg, seat: i)
            }
            if let winner = g.winnerIndex {
                banner = "\(g.players[winner].name) wins"
            } else if let legWinner = g.legWinnerIndex {
                banner = "Leg – \(g.players[legWinner].name)"
            } else {
                banner = g.isBust ? "BUST" : nil
            }
            hint = g.checkoutHint
        case .killer(let g):
            players = g.players.enumerated().map { i, p in
                .init(name: p.name, value: "\(p.number)", detail: p.isOut ? "Out" : "\(p.points) / \(KillerConfig.killerPoints)",
                      seat: i, killerPoints: p.isOut ? nil : p.points, isKiller: p.isKiller, isOut: p.isOut)
            }
            banner = g.winnerIndex.map { "\(g.players[$0].name) wins" }
            hint = nil
        }

        let match = Scoreboard.Match(
            title: title,
            players: players,
            currentIndex: state.currentPlayerIndex,
            visit: visit.map(\.score),
            visitHeadline: visitHeadline,
            isBust: isBust,
            hint: hint,
            banner: banner,
            winner: state.winnerIndex.map { state.playerNames[$0] }
        )
        if scoreboard.match != match { scoreboard.match = match }
    }
}

#if DEBUG
extension MatchController {
    /// A three-player best-of-3 X01 match partway through, for SwiftUI previews.
    static func preview(bust: Bool = false, finished: Bool = false) -> MatchController {
        let players = ["Max", "Anna", "Leo"].map { SavedPlayer(id: UUID(), name: $0) }
        let startingScore = finished || bust ? 101 : 501
        let match = MatchController(
            settings: .x01(X01Config(startingScore: startingScore, doubleOut: true, doubleIn: false, legs: finished ? 1 : 3)),
            players: players
        )
        if finished {
            match.throwPreviewDarts([.init(ring: .treble, number: 20), .init(ring: .single, number: 1), .init(ring: .double, number: 20)])
            return match
        }
        match.throwPreviewDarts([.init(ring: .treble, number: 20), .init(ring: .single, number: 20), .init(ring: .single, number: 5)])
        match.dartsPulled()
        match.throwPreviewDarts(bust
            ? [.init(ring: .treble, number: 20), .init(ring: .treble, number: 20), .init(ring: .treble, number: 20)]
            : [.init(ring: .treble, number: 19), .init(ring: .double, number: 16)])
        return match
    }

    /// A four-player Killer game: Anna is a killer, Leo is out, Max is on 1, and it's Sara's turn.
    static func killerPreview() -> MatchController {
        let players = ["Max", "Anna", "Leo", "Sara"].map { SavedPlayer(id: UUID(), name: $0) }
        let match = MatchController(settings: .killer(KillerConfig()), players: players)
        guard case .killer(let g) = match.state else { return match }
        let n = g.players.map(\.number)
        match.throwPreviewDarts([.init(ring: .double, number: n[0])])          // Max 2
        match.dartsPulled()
        match.throwPreviewDarts([.init(ring: .treble, number: n[1]),           // Anna 3 → killer
                                 .init(ring: .treble, number: n[2]),           // Leo −3 → out
                                 .init(ring: .single, number: n[0])])          // Max 2 → 1
        match.dartsPulled()
        return match
    }

    private func throwPreviewDarts(_ darts: [BoardScore]) {
        for score in darts { dartDetected(DetectedDart(x: .nan, y: .nan, score: score)) }
    }
}
#endif
