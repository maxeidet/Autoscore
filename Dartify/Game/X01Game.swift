//
//  X01Game.swift
//  Dartify
//
//  X01 (301 / 501 / 701) rules, ported from the React app's x01Engine.ts. Pure value type, no UI.
//

import Foundation

nonisolated struct X01Config: Sendable, Equatable, Codable {
    var startingScore = 501
    var doubleOut = true
    var doubleIn = false
    /// Best of this many legs; 1 is a single leg.
    var legs = 1

    var legsToWin: Int { legs / 2 + 1 }

    /// The setup screen's summary sentence, e.g. "501, double out."
    var headline: String {
        "\(startingScore)\(doubleIn ? ", double in" : "")\(doubleOut ? ", double out" : ", straight out")."
    }
}

nonisolated struct X01Player: Sendable, Equatable, Identifiable, Codable {
    let id: UUID
    var name: String
    var scoreLeft: Int
    var dartsThrown = 0
    var legsWon = 0
    /// Points that counted (busts and darts before a double-in don't), for the 3-dart average.
    var pointsScored = 0
    /// With double-in, a player scores nothing until they hit a double.
    var hasStarted: Bool

    var threeDartAverage: Double? {
        dartsThrown > 0 ? Double(pointsScored) / Double(dartsThrown) * 3 : nil
    }
}

nonisolated struct X01Visit: Sendable, Equatable, Codable {
    var playerIndex: Int
    var darts: [BoardScore]
    var isBust: Bool
    var scored: Int
    /// Set when this visit's last dart won the leg.
    var checkout: Int?
}

nonisolated struct X01Game: Sendable, Equatable {
    enum Outcome: Sendable, Equatable {
        case scored(Int)
        /// Double-in is on and the player hasn't hit a double yet.
        case notStarted
        case bust
        case legWon
        case matchWon
    }

    let config: X01Config
    private(set) var players: [X01Player]
    private(set) var currentPlayerIndex = 0
    private(set) var round = 1
    private(set) var leg = 1
    /// Darts thrown in the current visit (0–3).
    private(set) var visitDarts: [BoardScore] = []
    private(set) var isBust = false
    /// Who won the leg with the last dart; the next leg starts when the visit ends.
    private(set) var legWinnerIndex: Int?
    private(set) var winnerIndex: Int?
    private(set) var history: [X01Visit] = []
    /// Fewest darts used to win a leg in this match, and the highest checkout.
    private(set) var bestLegDarts: Int?
    private(set) var highestCheckout: Int?

    private var visitStartScore: Int
    private var legStartDarts: [Int]

    init(config: X01Config, playerNames: [(id: UUID, name: String)]) {
        self.config = config
        players = playerNames.map {
            X01Player(id: $0.id, name: $0.name, scoreLeft: config.startingScore, hasStarted: !config.doubleIn)
        }
        visitStartScore = config.startingScore
        legStartDarts = players.map { _ in 0 }
    }

    var currentPlayer: X01Player { players[currentPlayerIndex] }
    var isFinished: Bool { winnerIndex != nil }
    /// The visit is over (bust, leg won or three darts) and waits for the darts to be pulled.
    var isVisitOver: Bool { isBust || legWinnerIndex != nil || isFinished || visitDarts.count >= 3 }
    var visitScore: Int { isBust ? 0 : visitStartScore - currentPlayer.scoreLeft }

    /// Suggested finish for the current player, when one exists.
    var checkoutHint: String? {
        let left = currentPlayer.scoreLeft
        guard currentPlayer.hasStarted, !isVisitOver else { return nil }
        if config.doubleOut {
            guard (2...170).contains(left) else { return nil }
            return X01Checkouts.routes[left]
        }
        return nil
    }

    @discardableResult
    mutating func throwDart(_ dart: BoardScore) -> Outcome {
        precondition(!isVisitOver, "visit is over; call endVisit() first")
        var player = players[currentPlayerIndex]
        visitDarts.append(dart)
        player.dartsThrown += 1

        let isDouble = dart.ring == .double || dart.ring == .bull
        if !player.hasStarted {
            guard isDouble else {
                players[currentPlayerIndex] = player
                return .notStarted
            }
            player.hasStarted = true
        }

        let remaining = player.scoreLeft - dart.points
        let bust = remaining < 0
            || (config.doubleOut && remaining == 1)
            || (config.doubleOut && remaining == 0 && !isDouble)
        if bust {
            // Back to the score at the start of the visit; this visit's points don't count.
            player.pointsScored -= visitStartScore - player.scoreLeft
            player.scoreLeft = visitStartScore
            players[currentPlayerIndex] = player
            isBust = true
            return .bust
        }

        player.scoreLeft = remaining
        player.pointsScored += dart.points
        guard remaining == 0 else {
            players[currentPlayerIndex] = player
            return .scored(dart.points)
        }

        // Leg won.
        player.legsWon += 1
        let legDarts = player.dartsThrown - legStartDarts[currentPlayerIndex]
        bestLegDarts = min(bestLegDarts ?? .max, legDarts)
        highestCheckout = max(highestCheckout ?? 0, visitStartScore)
        players[currentPlayerIndex] = player
        if player.legsWon >= config.legsToWin {
            winnerIndex = currentPlayerIndex
            recordVisit(checkout: visitStartScore)
            return .matchWon
        }
        legWinnerIndex = currentPlayerIndex
        return .legWon
    }

    /// Ends the current visit (unthrown darts count as misses, like the React app) and moves on:
    /// to the next player, or to a fresh leg after a leg win.
    mutating func endVisit() {
        guard !isFinished else { return }
        let missing = 3 - visitDarts.count
        if missing > 0 && legWinnerIndex == nil {
            players[currentPlayerIndex].dartsThrown += missing
        }
        recordVisit(checkout: legWinnerIndex != nil ? visitStartScore : nil)

        if legWinnerIndex != nil {
            // Fresh leg: everyone back to the starting score; who starts rotates every leg.
            let legsPlayed = players.reduce(0) { $0 + $1.legsWon }
            for i in players.indices {
                players[i].scoreLeft = config.startingScore
                players[i].hasStarted = !config.doubleIn
            }
            legStartDarts = players.map(\.dartsThrown)
            currentPlayerIndex = legsPlayed % players.count
            leg += 1
            round = 1
            legWinnerIndex = nil
        } else {
            currentPlayerIndex = (currentPlayerIndex + 1) % players.count
            if currentPlayerIndex == (leg - 1) % players.count { round += 1 }
        }
        visitDarts = []
        isBust = false
        visitStartScore = players[currentPlayerIndex].scoreLeft
    }

    private mutating func recordVisit(checkout: Int?) {
        history.append(X01Visit(
            playerIndex: currentPlayerIndex,
            darts: visitDarts,
            isBust: isBust,
            scored: visitScore,
            checkout: checkout
        ))
    }
}

/// Common checkout routes, from the React app.
nonisolated enum X01Checkouts {
    static let routes: [Int: String] = [
        170: "T20 T20 Bull", 167: "T20 T19 Bull", 164: "T20 T18 Bull", 161: "T20 T17 Bull",
        160: "T20 T20 D20", 158: "T20 T20 D19", 157: "T20 T19 D20", 156: "T20 T20 D18",
        155: "T20 T19 D19", 154: "T20 T18 D20", 153: "T20 T19 D18", 152: "T20 T20 D16",
        151: "T20 T17 D20", 150: "T20 T18 D18", 149: "T20 T19 D16", 148: "T20 T16 D20",
        147: "T20 T17 D18", 146: "T20 T18 D16", 145: "T20 T15 D20", 144: "T20 T20 D12",
        143: "T20 T17 D16", 142: "T20 T14 D20", 141: "T20 T19 D12", 140: "T20 T16 D16",
        139: "T20 T13 D20", 138: "T20 T18 D12", 137: "T20 T15 D16", 136: "T20 T20 D8",
        135: "T20 T17 D12", 134: "T20 T14 D16", 133: "T20 T19 D8", 132: "T20 T16 D12",
        131: "T20 T13 D16", 130: "T20 T20 D5", 129: "T19 T16 D12", 128: "T18 T14 D16",
        127: "T20 T17 D8", 126: "T19 T19 D6", 125: "Bull T20 D20", 124: "T20 T16 D8",
        123: "T19 T16 D9", 122: "T18 T18 D7", 121: "T20 T11 D14", 120: "T20 S20 D20",
        119: "T19 T12 D13", 118: "T20 S18 D20", 117: "T20 S17 D20", 116: "T20 S16 D20",
        115: "T20 S15 D20", 114: "T20 S14 D20", 113: "T20 S13 D20", 112: "T20 S12 D20",
        111: "T20 S11 D20", 110: "T20 S10 D20", 109: "T20 S9 D20", 108: "T20 S8 D20",
        107: "T19 S10 D20", 106: "T20 S6 D20", 105: "T20 S5 D20", 104: "T18 S10 D20",
        103: "T19 S6 D20", 102: "T20 S2 D20", 101: "T17 S10 D20", 100: "T20 D20",
        99: "T19 S10 D16", 98: "T20 D19", 97: "T19 D20", 96: "T20 D18", 95: "T19 D19",
        94: "T18 D20", 93: "T19 D18", 92: "T20 D16", 91: "T17 D20", 90: "T18 D18",
        89: "T19 D16", 88: "T20 D14", 87: "T17 D18", 86: "T18 D16", 85: "T15 D20",
        84: "T20 D12", 83: "T17 D16", 82: "T14 D20", 81: "T19 D12", 80: "T20 D10",
        79: "T13 D20", 78: "T18 D12", 77: "T15 D16", 76: "T20 D8", 75: "T17 D12",
        74: "T14 D16", 73: "T19 D8", 72: "T16 D12", 71: "T13 D16", 70: "T18 D8",
        69: "T19 D6", 68: "T20 D4", 67: "T17 D8", 66: "T10 D18", 65: "T19 D4",
        64: "T16 D8", 63: "T13 D12", 62: "T10 D16", 61: "T15 D8", 60: "S20 D20",
        59: "S19 D20", 58: "S18 D20", 57: "S17 D20", 56: "T16 D4", 55: "S15 D20",
        54: "S14 D20", 53: "S13 D20", 52: "S12 D20", 51: "S11 D20", 50: "Bull",
        40: "D20", 38: "D19", 36: "D18", 34: "D17", 32: "D16", 30: "D15", 28: "D14",
        26: "D13", 24: "D12", 22: "D11", 20: "D10", 18: "D9", 16: "D8", 14: "D7",
        12: "D6", 10: "D5", 8: "D4", 6: "D3", 4: "D2", 2: "D1",
    ]
}
