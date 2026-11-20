//
//  X01Bot.swift
//  Dartify
//
//  A computer opponent for X01 that plays at a chosen 3-dart average.
//
//  Each dart is aimed at a spot on the board (treble 20 while scoring, the right bed when it can finish) and lands
//  with a random scatter around it, like a real throw. The size of that scatter is what sets the level: it is
//  calibrated by simulating legs until the bot's average matches the one asked for.
//

import Foundation

nonisolated struct X01Bot: Sendable {
    /// Standard deviation of the scatter sideways, in millimetres. Darts spread a little more up and down.
    let spread: Double
    private static let verticalStretch = 1.2

    // MARK: - Throwing

    /// The bot's next dart in this game, with the spot it landed on.
    func throwDart<R: RandomNumberGenerator>(in game: X01Game, using rng: inout R) -> DetectedDart {
        let target = Self.aim(game: game)
        let (dx, dy) = Self.gaussianPair(using: &rng)
        let x = target.x + dx * spread
        let y = target.y + dy * spread * Self.verticalStretch
        return DetectedDart(x: x, y: y, score: BoardGeometry.score(x: x, y: y))
    }

    func throwDart(in game: X01Game) -> DetectedDart {
        var rng = SystemRandomNumberGenerator()
        return throwDart(in: game, using: &rng)
    }

    // MARK: - Calibration

    /// A bot whose 3-dart average over whole legs of this format comes out at `average`.
    /// Takes a fraction of a second, so call it off the main thread.
    static func calibrated(average: Double, config: X01Config) -> X01Bot {
        var legConfig = config
        legConfig.legs = 1
        // Wider scatter means a lower average, so search the spread between a near-perfect and a wild thrower.
        var low = 1.0, high = 200.0
        for _ in 0..<18 {
            let mid = (low + high) / 2
            if simulatedAverage(spread: mid, config: legConfig) > average { low = mid } else { high = mid }
        }
        return X01Bot(spread: (low + high) / 2)
    }

    /// Average over a fixed set of simulated legs. The same random numbers are used for every spread, so the
    /// result changes smoothly with the spread and the search above settles.
    static func simulatedAverage(spread: Double, config: X01Config, legs: Int = 800) -> Double {
        let bot = X01Bot(spread: spread)
        var rng = SplitMix64(seed: 0xDA27)
        var points = 0, darts = 0
        let me = [(id: UUID(), name: "Bot")]
        for _ in 0..<legs {
            var game = X01Game(config: config, playerNames: me)
            // A cap so a very wild thrower can't stall the calibration.
            var thrown = 0
            while !game.isFinished && thrown < 600 {
                if game.isVisitOver {
                    game.endVisit()
                } else {
                    game.throwDart(bot.throwDart(in: game, using: &rng).score)
                    thrown += 1
                }
            }
            points += game.players[0].pointsScored
            darts += game.players[0].dartsThrown
        }
        return darts > 0 ? Double(points) / Double(darts) * 3 : 0
    }

    // MARK: - Aiming

    /// Where to aim the next dart, in board millimetres.
    static func aim(game: X01Game) -> (x: Double, y: Double) {
        let player = game.currentPlayer
        let score = player.scoreLeft
        let dartsLeft = 3 - game.visitDarts.count
        if !player.hasStarted { return spot(.double, 20) }
        return game.config.doubleOut
            ? doubleOutAim(score: score, dartsLeft: dartsLeft)
            : straightOutAim(score: score)
    }

    private static func doubleOutAim(score: Int, dartsLeft: Int) -> (x: Double, y: Double) {
        // A known finish that fits in the darts left: go for its first dart.
        if let route = X01Checkouts.routes[score] {
            let darts = route.split(separator: " ")
            if darts.count <= dartsLeft, let first = darts.first, let target = parse(first) {
                return target
            }
        }
        if score > 100 { return spot(.treble, 20) }
        // No finish this visit: leave a good double, preferring ones that split into other doubles.
        for leave in [32, 40, 16, 24, 36, 20, 8, 12, 28, 18, 10, 4, 30, 34, 38, 26, 22, 14, 6, 2] {
            let need = score - leave
            if (1...20).contains(need) { return spot(.single, need) }
            if need > 0, need % 3 == 0, (1...20).contains(need / 3) { return spot(.treble, need / 3) }
        }
        return score >= 62 ? spot(.treble, 20) : spot(.single, 1)
    }

    private static func straightOutAim(score: Int) -> (x: Double, y: Double) {
        switch score {
        case 50: return (0, 0)
        case 25: return spot(.outerBull, 0)
        case 1...20: return spot(.single, score)
        case 21...40 where score % 2 == 0: return spot(.double, score / 2)
        case 21...60 where score % 3 == 0: return spot(.treble, score / 3)
        case 21...40: return spot(.single, score - 20)
        case 41...60: return spot(.single, score - 40)
        default: return spot(.treble, 20)
        }
    }

    /// "T20", "S5", "D16" or "Bull" from a checkout route.
    private static func parse(_ token: Substring) -> (x: Double, y: Double)? {
        if token == "Bull" { return (0, 0) }
        guard let number = Int(token.dropFirst()), (1...20).contains(number) else { return nil }
        switch token.first {
        case "T": return spot(.treble, number)
        case "D": return spot(.double, number)
        case "S": return spot(.single, number)
        default: return nil
        }
    }

    /// The middle of a bed: trebles and doubles in the middle of their ring, singles in the big outer single.
    private static func spot(_ ring: BoardScore.Ring, _ number: Int) -> (x: Double, y: Double) {
        let radius: Double = switch ring {
        case .treble: (BoardGeometry.trebleInner + BoardGeometry.trebleOuter) / 2
        case .double: (BoardGeometry.doubleInner + BoardGeometry.doubleOuter) / 2
        case .single: (BoardGeometry.trebleOuter + BoardGeometry.doubleInner) / 2
        case .outerBull: (BoardGeometry.bullRadius + BoardGeometry.outerBullRadius) / 2
        case .bull, .miss: 0
        }
        let index = BoardGeometry.order.firstIndex(of: number) ?? 0
        return BoardGeometry.point(radius: radius, degrees: BoardGeometry.segmentAngle(index))
    }

    /// Two independent standard normal numbers (Box–Muller).
    private static func gaussianPair<R: RandomNumberGenerator>(using rng: inout R) -> (Double, Double) {
        let u1 = Double.random(in: .ulpOfOne..<1, using: &rng)
        let u2 = Double.random(in: 0..<1, using: &rng)
        let r = (-2 * log(u1)).squareRoot()
        return (r * cos(2 * .pi * u2), r * sin(2 * .pi * u2))
    }
}

/// Small seeded generator, so calibration gives the same answer every time.
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension SavedPlayer {
    /// The computer opponent. Never saved with the players; it only exists in a match's roster.
    static let bot = SavedPlayer(id: UUID(uuidString: "B0700000-0000-4000-8000-000000000001")!, name: "Bot")

    var isBot: Bool { id == Self.bot.id }
}
