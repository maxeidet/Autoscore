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
        var scoreLeft: Int
        var legsWon: Int
        var average: Double?
        var seat: Int
    }

    struct Match: Equatable {
        var title: String
        var players: [Player]
        var currentIndex: Int
        var visit: [BoardScore]
        var visitScore: Int
        var isBust: Bool
        var checkout: String?
        var showLegs: Bool
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
