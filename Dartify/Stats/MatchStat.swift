//
//  MatchStat.swift
//  Dartify
//
//  The main user's results, one row per finished match, stored with SwiftData so they survive app restarts.
//  Only the main player (LocalStore.mainPlayer, linked by id) is saved; other players aren't tracked.
//

import Foundation
import SwiftData

@Model
final class MatchStat {
    var date: Date
    /// "x01" or "killer" (a plain string keeps SwiftData predicates simple).
    var mode: String
    /// "501", "301", "Killer"…
    var title: String
    var won: Bool
    var opponents: [String]
    var darts: Int
    /// Points that counted, for the 3-dart average (X01 only).
    var points: Int
    var legsWon: Int
    var legsLost: Int
    var highestVisit: Int
    var tonPlus: Int
    var ton40Plus: Int
    var oneEighties: Int
    var highestCheckout: Int?
    var bestLegDarts: Int?
    /// Killer: points taken off other players.
    var kills: Int

    init(date: Date = .now, mode: String, title: String, won: Bool, opponents: [String], darts: Int, points: Int = 0,
         legsWon: Int = 0, legsLost: Int = 0, highestVisit: Int = 0, tonPlus: Int = 0, ton40Plus: Int = 0,
         oneEighties: Int = 0, highestCheckout: Int? = nil, bestLegDarts: Int? = nil, kills: Int = 0) {
        self.date = date
        self.mode = mode
        self.title = title
        self.won = won
        self.opponents = opponents
        self.darts = darts
        self.points = points
        self.legsWon = legsWon
        self.legsLost = legsLost
        self.highestVisit = highestVisit
        self.tonPlus = tonPlus
        self.ton40Plus = ton40Plus
        self.oneEighties = oneEighties
        self.highestCheckout = highestCheckout
        self.bestLegDarts = bestLegDarts
        self.kills = kills
    }

    var isX01: Bool { mode == "x01" }
    var average: Double? { isX01 && darts > 0 ? Double(points) / Double(darts) * 3 : nil }
}

extension MatchStat {
    /// Player `me`'s numbers from a finished X01 match, worked out from the visit history.
    static func x01(_ game: X01Game, player me: Int) -> MatchStat {
        var legDarts = 0
        var bestLeg: Int?
        var highestCheckout: Int?
        var highestVisit = 0, tonPlus = 0, ton40Plus = 0, oneEighties = 0

        for visit in game.history {
            if visit.playerIndex == me {
                // Unthrown darts count as misses, except on the visit that checked out.
                legDarts += visit.checkout != nil ? visit.darts.count : 3
                if !visit.isBust {
                    highestVisit = max(highestVisit, visit.scored)
                    if visit.scored >= 100 { tonPlus += 1 }
                    if visit.scored >= 140 { ton40Plus += 1 }
                    if visit.scored == 180 { oneEighties += 1 }
                }
                if let checkout = visit.checkout {
                    bestLeg = min(bestLeg ?? .max, legDarts)
                    highestCheckout = max(highestCheckout ?? 0, checkout)
                }
            }
            if visit.checkout != nil { legDarts = 0 }
        }

        let player = game.players[me]
        let others = game.players.indices.filter { $0 != me }
        return MatchStat(
            mode: "x01",
            title: "\(game.config.startingScore)",
            won: game.winnerIndex == me,
            opponents: others.map { game.players[$0].name },
            darts: player.dartsThrown,
            points: player.pointsScored,
            legsWon: player.legsWon,
            legsLost: others.reduce(0) { $0 + game.players[$1].legsWon },
            highestVisit: highestVisit,
            tonPlus: tonPlus,
            ton40Plus: ton40Plus,
            oneEighties: oneEighties,
            highestCheckout: highestCheckout,
            bestLegDarts: bestLeg
        )
    }

    static func killer(_ game: KillerGame, player me: Int) -> MatchStat {
        let player = game.players[me]
        return MatchStat(
            mode: "killer",
            title: "Killer",
            won: game.winnerIndex == me,
            opponents: game.players.indices.filter { $0 != me }.map { game.players[$0].name },
            darts: player.dartsThrown,
            kills: player.pointsTaken
        )
    }
}

/// Owns the SwiftData container and saves finished matches for the main user.
enum StatsStore {
    static let container: ModelContainer = {
        let schema = Schema([Item.self, MatchStat.self])
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// Saves the main player's result when they played in this finished match; does nothing otherwise.
    /// `roster` is the match's players in seat order, the same order as the game's players.
    static func record(_ state: GameState, roster: [SavedPlayer]) {
        guard state.isFinished,
              let mainID = LocalStore.shared.mainPlayerID,
              let me = roster.firstIndex(where: { $0.id == mainID })
        else { return }

        let stat: MatchStat = switch state {
        case .x01(let game): .x01(game, player: me)
        case .killer(let game): .killer(game, player: me)
        }
        let context = container.mainContext
        context.insert(stat)
        try? context.save()
    }
}

/// Totals over a set of the main user's matches (newest first).
struct StatSummary {
    let matches: [MatchStat]

    private var x01: [MatchStat] { matches.filter(\.isX01) }

    var played: Int { matches.count }
    var wins: Int { matches.count(where: \.won) }
    var winRate: Double? { played > 0 ? Double(wins) / Double(played) : nil }
    /// Current winning streak, counting back from the latest match.
    var streak: Int { matches.prefix(while: \.won).count }

    var average: Double? {
        let darts = x01.reduce(0) { $0 + $1.darts }
        return darts > 0 ? Double(x01.reduce(0) { $0 + $1.points }) / Double(darts) * 3 : nil
    }
    var bestMatchAverage: Double? { x01.compactMap(\.average).max() }
    var highestCheckout: Int? { x01.compactMap(\.highestCheckout).max() }
    var bestLegDarts: Int? { x01.compactMap(\.bestLegDarts).min() }
    var highestVisit: Int? { x01.map(\.highestVisit).max().flatMap { $0 > 0 ? $0 : nil } }
    var oneEighties: Int { x01.reduce(0) { $0 + $1.oneEighties } }
    var ton40Plus: Int { x01.reduce(0) { $0 + $1.ton40Plus } }
    var tonPlus: Int { x01.reduce(0) { $0 + $1.tonPlus } }
    var kills: Int { matches.reduce(0) { $0 + $1.kills } }
}
