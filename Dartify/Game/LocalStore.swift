//
//  LocalStore.swift
//  Dartify
//

import Foundation
import Observation

struct SavedPlayer: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
}

/// A finished match, kept for the home screen's season stats.
struct MatchRecord: Codable, Identifiable {
    struct PlayerResult: Codable {
        var name: String
        var points: Int
        var darts: Int
        var legsWon: Int
    }

    let id: UUID
    var date: Date
    var startingScore: Int
    var players: [PlayerResult]
    var winnerName: String
    var highestCheckout: Int?
    var bestLegDarts: Int?
}

/// Saved players and match history, persisted as JSON in UserDefaults.
@Observable
final class LocalStore {
    static let shared = LocalStore()

    private(set) var players: [SavedPlayer]
    private(set) var matches: [MatchRecord]

    private let playersKey = "dartify.players"
    private let matchesKey = "dartify.matches"

    private init() {
        let defaults = UserDefaults.standard
        players = defaults.data(forKey: playersKey).flatMap { try? JSONDecoder().decode([SavedPlayer].self, from: $0) } ?? []
        matches = defaults.data(forKey: matchesKey).flatMap { try? JSONDecoder().decode([MatchRecord].self, from: $0) } ?? []
    }

    @discardableResult
    func addPlayer(named name: String) -> SavedPlayer? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = players.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let player = SavedPlayer(id: UUID(), name: trimmed)
        players.append(player)
        save(players, key: playersKey)
        return player
    }

    func removePlayer(_ player: SavedPlayer) {
        players.removeAll { $0.id == player.id }
        save(players, key: playersKey)
    }

    func record(_ game: X01Game) {
        guard let winner = game.winnerIndex else { return }
        matches.append(MatchRecord(
            id: UUID(),
            date: .now,
            startingScore: game.config.startingScore,
            players: game.players.map { .init(name: $0.name, points: $0.pointsScored, darts: $0.dartsThrown, legsWon: $0.legsWon) },
            winnerName: game.players[winner].name,
            highestCheckout: game.highestCheckout,
            bestLegDarts: game.bestLegDarts
        ))
        save(matches, key: matchesKey)
    }

    // MARK: - Season stats

    var threeDartAverage: Double? {
        let points = matches.flatMap(\.players).reduce(0) { $0 + $1.points }
        let darts = matches.flatMap(\.players).reduce(0) { $0 + $1.darts }
        return darts > 0 ? Double(points) / Double(darts) * 3 : nil
    }

    var highestCheckout: Int? { matches.compactMap(\.highestCheckout).max() }
    var bestLegDarts: Int? { matches.compactMap(\.bestLegDarts).min() }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
