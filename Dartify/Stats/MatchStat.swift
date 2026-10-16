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
    /// X01 with double out: darts thrown with a double finish left (2–40 even, or 50), and how many of them checked out.
    var doubleAttempts: Int = 0
    var doublesHit: Int = 0
    /// Every dart the main user threw, JSON-encoded `[DartThrow]`; only matches saved before visits were kept.
    var dartLogData: Data?
    /// The main user's visits in order, JSON-encoded `[VisitLog]`; nil for older matches.
    var visitLogData: Data?

    init(date: Date = .now, mode: String, title: String, won: Bool, opponents: [String], darts: Int, points: Int = 0,
         legsWon: Int = 0, legsLost: Int = 0, highestVisit: Int = 0, tonPlus: Int = 0, ton40Plus: Int = 0,
         oneEighties: Int = 0, highestCheckout: Int? = nil, bestLegDarts: Int? = nil, kills: Int = 0,
         doubleAttempts: Int = 0, doublesHit: Int = 0, visitLog: [VisitLog] = []) {
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
        self.doubleAttempts = doubleAttempts
        self.doublesHit = doublesHit
        visitLogData = try? JSONEncoder().encode(visitLog)
    }

    var isX01: Bool { mode == "x01" }
    var average: Double? { isX01 && darts > 0 ? Double(points) / Double(darts) * 3 : nil }

    var visitLog: [VisitLog] {
        visitLogData.flatMap { try? JSONDecoder().decode([VisitLog].self, from: $0) } ?? []
    }

    var dartLog: [DartThrow] {
        if let visitLogData { return visitLog.flatMap(\.darts) }
        return dartLogData.flatMap { try? JSONDecoder().decode([DartThrow].self, from: $0) } ?? []
    }
}

/// One of the main user's visits: up to three darts and, in X01, what they did to the score.
nonisolated struct VisitLog: Codable, Equatable, Sendable {
    var leg: Int
    var darts: [DartThrow]
    /// X01: points the visit counted (0 on a bust) and the score left after it.
    var scored: Int?
    var left: Int?
    var isBust = false
    var isCheckout = false
}

/// One saved dart: what it scored and, when known, where it landed in board millimetres (origin at the bull, y up).
nonisolated struct DartThrow: Codable, Equatable, Sendable {
    var x: Double?
    var y: Double?
    var score: BoardScore

    /// Keeps the position only when it agrees with the score; a corrected dart still carries the spot where
    /// the camera first saw it, which would put it in the wrong bed.
    init(score: BoardScore) {
        self.score = score
    }

    init(_ dart: DetectedDart) {
        score = dart.score
        if dart.hasPosition, BoardGeometry.score(x: dart.x, y: dart.y) == dart.score {
            x = dart.x
            y = dart.y
        }
    }
}

extension MatchStat {
    /// Player `me`'s numbers from a finished X01 match, worked out from the visit history.
    /// `visitDarts` are the player's visits as the match controller saw them, with board positions.
    static func x01(_ game: X01Game, player me: Int, visitDarts: [[DetectedDart]] = []) -> MatchStat {
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
        let doubles = doubleStats(game, player: me)

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
            bestLegDarts: bestLeg,
            doubleAttempts: doubles.attempts,
            doublesHit: doubles.hit,
            visitLog: visitLog(game, player: me, visitDarts: visitDarts)
        )
    }

    /// The player's visits from the game history, using the controller's darts (which have positions) when they agree.
    private static func visitLog(_ game: X01Game, player me: Int, visitDarts: [[DetectedDart]]) -> [VisitLog] {
        let start = game.config.startingScore
        var log: [VisitLog] = []
        var leg = 1, left = start

        for visit in game.history {
            if visit.playerIndex == me {
                if !visit.isBust { left -= visit.scored }
                let seen = log.count < visitDarts.count ? visitDarts[log.count] : []
                let darts = seen.map(\.score) == visit.darts ? seen.map(DartThrow.init) : visit.darts.map { DartThrow(score: $0) }
                log.append(VisitLog(leg: leg, darts: darts, scored: visit.scored, left: left,
                                    isBust: visit.isBust, isCheckout: visit.checkout != nil))
            }
            if visit.checkout != nil {
                leg += 1
                left = start
            }
        }
        return log
    }

    /// Replays the visits to find each dart thrown with a double finish left, and which of those won the leg.
    private static func doubleStats(_ game: X01Game, player me: Int) -> (attempts: Int, hit: Int) {
        guard game.config.doubleOut else { return (0, 0) }
        let start = game.config.startingScore
        var left = game.players.map { _ in start }
        var started = game.players.map { _ in !game.config.doubleIn }
        var attempts = 0, hit = 0

        for visit in game.history {
            let p = visit.playerIndex
            var score = left[p]
            for dart in visit.darts {
                let isDouble = dart.ring == .double || dart.ring == .bull
                if !started[p] {
                    guard isDouble else { continue }
                    started[p] = true
                }
                if p == me && (score == 50 || (2...40).contains(score) && score.isMultiple(of: 2)) {
                    attempts += 1
                    if isDouble && dart.points == score { hit += 1 }
                }
                score -= dart.points
            }
            if !visit.isBust { left[p] = score }
            if visit.checkout != nil {
                left = left.map { _ in start }
                started = started.map { _ in !game.config.doubleIn }
            }
        }
        return (attempts, hit)
    }

    static func killer(_ game: KillerGame, player me: Int, visitDarts: [[DetectedDart]] = []) -> MatchStat {
        let player = game.players[me]
        return MatchStat(
            mode: "killer",
            title: "Killer",
            won: game.winnerIndex == me,
            opponents: game.players.indices.filter { $0 != me }.map { game.players[$0].name },
            darts: player.dartsThrown,
            kills: player.pointsTaken,
            visitLog: visitDarts.map { VisitLog(leg: 1, darts: $0.map(DartThrow.init)) }
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
    /// `roster` is the match's players in seat order, the same order as the game's players; `visits` holds every
    /// visit's darts with the seat that threw them.
    static func record(_ state: GameState, roster: [SavedPlayer], visits: [(player: Int, darts: [DetectedDart])]) {
        guard state.isFinished,
              let mainID = LocalStore.shared.mainPlayerID,
              let me = roster.firstIndex(where: { $0.id == mainID })
        else { return }

        let mine = visits.filter { $0.player == me }.map(\.darts)
        let stat: MatchStat = switch state {
        case .x01(let game): .x01(game, player: me, visitDarts: mine)
        case .killer(let game): .killer(game, player: me, visitDarts: mine)
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
    var doubleAttempts: Int { x01.reduce(0) { $0 + $1.doubleAttempts } }
    var doublesHit: Int { x01.reduce(0) { $0 + $1.doublesHit } }
    var doubleRate: Double? { doubleAttempts > 0 ? Double(doublesHit) / Double(doubleAttempts) : nil }
    var dartLog: [DartThrow] { matches.flatMap(\.dartLog) }
}
