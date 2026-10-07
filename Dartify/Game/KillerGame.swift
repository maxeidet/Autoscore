//
//  KillerGame.swift
//  Dartify
//
//  Killer (house rules): everyone gets a number and starts on 0 points. Hitting your own number counts up
//  to 3 (single 1, double 2, treble 3) and anything past 3 counts back down, so you never have more than 3.
//  You're a killer exactly while you're on 3. Killers take points off other players by hitting their numbers.
//  Below 0 you're out; the last player left wins.
//

import Foundation

nonisolated struct KillerConfig: Sendable, Equatable, Codable {
    /// Points needed to be a killer.
    static let killerPoints = 3

    var headline: String { "Killer, first to \(Self.killerPoints)." }
    var rule: String { "Hit your number to reach \(Self.killerPoints) and become a killer" }
}

nonisolated struct KillerPlayer: Sendable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var number: Int
    var points = 0
    var dartsThrown = 0
    /// Points taken off other players.
    var pointsTaken = 0

    var isKiller: Bool { points == KillerConfig.killerPoints }
    var isOut: Bool { points < 0 }
}

nonisolated struct KillerGame: Sendable, Equatable {
    enum Event: Sendable, Equatable {
        /// The current player's own number moved their points (up while building, down past 3).
        case ownHit(player: Int, points: Int)
        case becameKiller(Int)
        case lostKiller(Int)
        /// A killer took `count` points off `player`.
        case hit(player: Int, count: Int)
        case eliminated(Int)
        case won(Int)
    }

    let config: KillerConfig
    private(set) var players: [KillerPlayer]
    private(set) var currentPlayerIndex = 0
    private(set) var round = 1
    private(set) var visitDarts: [BoardScore] = []
    private(set) var winnerIndex: Int?

    /// `numbers` defaults to distinct random numbers 1–20.
    init(config: KillerConfig, playerNames: [(id: UUID, name: String)], numbers: [Int]? = nil) {
        self.config = config
        let numbers = numbers ?? Array((1...20).shuffled().prefix(playerNames.count))
        players = zip(playerNames, numbers).map { KillerPlayer(id: $0.id, name: $0.name, number: $1) }
    }

    var currentPlayer: KillerPlayer { players[currentPlayerIndex] }
    var isFinished: Bool { winnerIndex != nil }
    var isVisitOver: Bool { isFinished || visitDarts.count >= 3 }

    /// Points a dart is worth: single 1, double 2, treble 3. Bull and misses are worth nothing.
    static func value(of dart: BoardScore) -> Int {
        switch dart.ring {
        case .single: 1
        case .double: 2
        case .treble: 3
        case .miss, .outerBull, .bull: 0
        }
    }

    @discardableResult
    mutating func throwDart(_ dart: BoardScore) -> [Event] {
        precondition(!isVisitOver, "visit is over; call endVisit() first")
        visitDarts.append(dart)
        players[currentPlayerIndex].dartsThrown += 1

        let value = Self.value(of: dart)
        guard value > 0,
              let owner = players.firstIndex(where: { $0.number == dart.number && !$0.isOut })
        else { return [] }

        var events: [Event] = []
        if owner == currentPlayerIndex {
            // Count up to 3, then the rest back down: 6 - (points + value) once past 3.
            let wasKiller = players[owner].isKiller
            let total = players[owner].points + value
            let max = KillerConfig.killerPoints
            players[owner].points = total <= max ? total : 2 * max - total
            events.append(.ownHit(player: owner, points: players[owner].points))
            if !wasKiller && players[owner].isKiller { events.append(.becameKiller(owner)) }
            if wasKiller && !players[owner].isKiller { events.append(.lostKiller(owner)) }
        } else if players[currentPlayerIndex].isKiller {
            let wasKiller = players[owner].isKiller
            players[owner].points -= value
            players[currentPlayerIndex].pointsTaken += value
            events.append(.hit(player: owner, count: value))
            if players[owner].isOut {
                events.append(.eliminated(owner))
            } else if wasKiller {
                events.append(.lostKiller(owner))
            }
        }

        let alive = players.indices.filter { !players[$0].isOut }
        if alive.count == 1 {
            winnerIndex = alive[0]
            events.append(.won(alive[0]))
        }
        return events
    }

    /// Moves on to the next player still in the game.
    mutating func endVisit() {
        guard !isFinished else { return }
        var next = currentPlayerIndex
        repeat {
            next = (next + 1) % players.count
            if next == 0 { round += 1 }
        } while players[next].isOut && next != currentPlayerIndex
        currentPlayerIndex = next
        visitDarts = []
    }
}
