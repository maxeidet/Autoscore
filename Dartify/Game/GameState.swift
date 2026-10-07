//
//  GameState.swift
//  Dartify
//
//  One type for "whichever game is being played", so the match controller, game screen and TV can share
//  everything that works the same way (turns, visits, winners) and switch only where the modes differ.
//

import Foundation

nonisolated enum MatchSettings: Sendable, Equatable {
    case x01(X01Config)
    case killer(KillerConfig)
}

nonisolated enum GameState: Sendable, Equatable {
    case x01(X01Game)
    case killer(KillerGame)

    enum Outcome: Sendable, Equatable {
        case x01(X01Game.Outcome)
        case killer([KillerGame.Event])
    }

    init(settings: MatchSettings, players: [SavedPlayer]) {
        let names = players.map { (id: $0.id, name: $0.name) }
        switch settings {
        case .x01(let config): self = .x01(X01Game(config: config, playerNames: names))
        case .killer(let config): self = .killer(KillerGame(config: config, playerNames: names))
        }
    }

    var currentPlayerIndex: Int {
        switch self {
        case .x01(let g): g.currentPlayerIndex
        case .killer(let g): g.currentPlayerIndex
        }
    }

    var round: Int {
        switch self {
        case .x01(let g): g.round
        case .killer(let g): g.round
        }
    }

    var visitDarts: [BoardScore] {
        switch self {
        case .x01(let g): g.visitDarts
        case .killer(let g): g.visitDarts
        }
    }

    var isVisitOver: Bool {
        switch self {
        case .x01(let g): g.isVisitOver
        case .killer(let g): g.isVisitOver
        }
    }

    var isFinished: Bool { winnerIndex != nil }

    var winnerIndex: Int? {
        switch self {
        case .x01(let g): g.winnerIndex
        case .killer(let g): g.winnerIndex
        }
    }

    var playerNames: [String] {
        switch self {
        case .x01(let g): g.players.map(\.name)
        case .killer(let g): g.players.map(\.name)
        }
    }

    var currentPlayerName: String { playerNames[currentPlayerIndex] }

    @discardableResult
    mutating func throwDart(_ dart: BoardScore) -> Outcome {
        switch self {
        case .x01(var g):
            let outcome = g.throwDart(dart)
            self = .x01(g)
            return .x01(outcome)
        case .killer(var g):
            let events = g.throwDart(dart)
            self = .killer(g)
            return .killer(events)
        }
    }

    mutating func endVisit() {
        switch self {
        case .x01(var g):
            g.endVisit()
            self = .x01(g)
        case .killer(var g):
            g.endVisit()
            self = .killer(g)
        }
    }
}
