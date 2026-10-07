//
//  Scoreboard.swift
//  Dartify
//

import Observation

/// What the TV shows. The match and camera write it; the external-display scene reads it.
@Observable
final class Scoreboard {
    static let shared = Scoreboard()

    struct Player: Equatable {
        var name: String
        /// The big number: score left in X01, the player's number in Killer.
        var value: String
        /// Small line under it, e.g. "Legs 1 · Avg 58.4" or "2 / 3".
        var detail: String
        var seat: Int
        /// Killer only: points towards becoming a killer (nil when out or not Killer).
        var killerPoints: Int? = nil
        var isKiller = false
        var isOut = false
    }

    struct Match: Equatable {
        var title: String
        var players: [Player]
        var currentIndex: Int
        var visit: [BoardScore]
        /// Visit total in X01, the current player's points in Killer.
        var visitHeadline: String
        var isBust: Bool
        /// Checkout route in X01.
        var hint: String?
        /// Big message such as "BUST", "Leg – Max" or "Max wins".
        var banner: String?
        var winner: String?
    }

    /// Camera status; empty when the camera is ready to score.
    var cameraStatus = ""
    var match: Match?
    /// True while an external display (AirPlay or cable) is connected.
    var tvConnected = false
}
