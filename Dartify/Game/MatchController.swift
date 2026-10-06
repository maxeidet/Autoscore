//
//  MatchController.swift
//  Dartify
//

import Foundation
import Observation

/// Runs a local X01 match: turns camera darts into game moves, handles corrections and undo,
/// announces scores and keeps the TV scoreboard in sync.
///
/// The current visit is replayed from the state at its start every time it changes, so a correction
/// to any dart (say, a single that was really a double) re-scores the whole visit correctly.
@Observable
final class MatchController: Identifiable {
    let id = UUID()
    let config: X01Config
    let roster: [SavedPlayer]

    /// The game including the darts of the current visit.
    private(set) var game: X01Game
    /// Darts of the current visit, with their board positions when the camera found them.
    private(set) var visit: [DetectedDart] = []
    /// Set once the finished match has been saved to the history.
    private(set) var isRecorded = false

    @ObservationIgnored private var visitStart: X01Game
    @ObservationIgnored private var undoStack: [(start: X01Game, visit: [DetectedDart])] = []
    @ObservationIgnored private weak var camera: CameraController?
    @ObservationIgnored private let announcer = Announcer.shared
    @ObservationIgnored private let scoreboard = Scoreboard.shared

    init(config: X01Config, players: [SavedPlayer]) {
        self.config = config
        roster = players
        let game = X01Game(config: config, playerNames: players.map { (id: $0.id, name: $0.name) })
        self.game = game
        visitStart = game
        syncScoreboard()
    }

    var canUndo: Bool { !visit.isEmpty || !undoStack.isEmpty }

    /// Connects the camera: its darts drive the match, and it learns when a visit is over.
    func attach(_ camera: CameraController) {
        self.camera = camera
        camera.onDart = { [weak self] dart in self?.dartDetected(dart) }
        camera.onDartsPulled = { [weak self] in self?.dartsPulled() }
        camera.setVisit(visit, complete: game.isVisitOver)
        announceUp()
    }

    // MARK: - Input

    func dartDetected(_ dart: DetectedDart) {
        // After a bust or checkout the visit is over; further darts don't count.
        guard !game.isVisitOver else { return }
        visit.append(dart)
        let outcome = replay()
        announce(dart.score, outcome: outcome)
    }

    /// Darts pulled out of the board: the visit is done.
    func dartsPulled() {
        guard !visit.isEmpty else { return }
        commitVisit()
    }

    /// "Next" button: end the visit now (unthrown darts are misses) and start fresh from the board as it is.
    func nextVisit() {
        guard !game.isFinished else { return }
        commitVisit()
        camera?.startNewVisit()
    }

    /// Replaces dart `index` of the current visit, appends it when `index` is past the end,
    /// or removes it when `score` is nil.
    func correctDart(at index: Int, to score: BoardScore?) {
        if let score {
            if index < visit.count {
                visit[index].score = score
            } else if !game.isVisitOver {
                visit.append(DetectedDart(x: .nan, y: .nan, score: score))
            }
        } else if index < visit.count {
            visit.remove(at: index)
        }
        let outcome = replay()
        if let score {
            announcer.say("Corrected. \(score.spoken)", interrupt: true)
            announce(outcome: outcome)
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

    /// Saves the finished match to the history (once).
    func recordIfFinished() {
        guard game.isFinished, !isRecorded else { return }
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
    private func replay() -> X01Game.Outcome? {
        var g = visitStart
        var counted: [DetectedDart] = []
        var outcome: X01Game.Outcome?
        for dart in visit where !g.isVisitOver {
            outcome = g.throwDart(dart.score)
            counted.append(dart)
        }
        visit = counted
        game = g
        camera?.setVisit(visit, complete: game.isVisitOver)
        syncScoreboard()
        return outcome
    }

    private func commitVisit() {
        guard !game.isFinished else { return }
        undoStack.append((visitStart, visit))
        var g = game
        g.endVisit()
        visitStart = g
        visit = []
        game = g
        camera?.setVisit([], complete: false)
        syncScoreboard()
        announceUp()
    }

    // MARK: - Announcements

    private func announce(_ dart: BoardScore, outcome: X01Game.Outcome?) {
        announcer.say(dart.spoken)
        announce(outcome: outcome)
    }

    private func announce(outcome: X01Game.Outcome?) {
        let name = game.currentPlayer.name
        switch outcome {
        case .bust:
            announcer.say("Bust")
        case .notStarted:
            announcer.say("No score")
        case .legWon:
            announcer.say("Game shot! Leg, \(name)")
        case .matchWon:
            announcer.say("Game shot, and the match! \(name) wins")
        case .scored, nil:
            if visit.count == 3 { announcer.say("\(game.visitScore)") }
        }
    }

    /// "Max, you require 40" when a checkout is on, otherwise just the name.
    private func announceUp() {
        guard !game.isFinished else { return }
        let player = game.currentPlayer
        if game.checkoutHint != nil {
            announcer.say("\(player.name), you require \(player.scoreLeft)")
        } else {
            announcer.say(player.name)
        }
    }

    // MARK: - TV

    private func syncScoreboard() {
        let banner: String?
        if let winner = game.winnerIndex {
            banner = "\(game.players[winner].name) wins"
        } else if let legWinner = game.legWinnerIndex {
            banner = "Leg – \(game.players[legWinner].name)"
        } else if game.isBust {
            banner = "BUST"
        } else {
            banner = nil
        }

        let match = Scoreboard.Match(
            title: "\(config.startingScore)" + (config.legs > 1 ? " · Best of \(config.legs)" : ""),
            players: game.players.enumerated().map { i, p in
                .init(name: p.name, scoreLeft: p.scoreLeft, legsWon: p.legsWon, average: p.threeDartAverage, seat: i)
            },
            currentIndex: game.currentPlayerIndex,
            visit: visit.map(\.score),
            visitScore: game.visitScore,
            isBust: game.isBust,
            checkout: game.checkoutHint,
            showLegs: config.legs > 1,
            banner: banner,
            winner: game.winnerIndex.map { game.players[$0].name }
        )
        if scoreboard.match != match { scoreboard.match = match }
    }
}
