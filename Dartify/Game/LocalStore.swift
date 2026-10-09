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
    /// The phone's owner, the one player whose stats are saved. Linked by id, so renaming keeps the stats.
    private(set) var mainPlayerID: UUID? {
        didSet { UserDefaults.standard.set(mainPlayerID?.uuidString, forKey: mainPlayerKey) }
    }

    private let playersKey = "dartify.players"
    private let matchesKey = "dartify.matches"
    private let mainPlayerKey = "dartify.mainPlayer"

    private init() {
        let defaults = UserDefaults.standard
        players = defaults.data(forKey: playersKey).flatMap { try? JSONDecoder().decode([SavedPlayer].self, from: $0) } ?? []
        matches = defaults.data(forKey: matchesKey).flatMap { try? JSONDecoder().decode([MatchRecord].self, from: $0) } ?? []
        mainPlayerID = defaults.string(forKey: mainPlayerKey).flatMap(UUID.init)
        migrateMainPlayer()
    }

    // MARK: - Main player

    var mainPlayer: SavedPlayer? { players.first { $0.id == mainPlayerID } }

    func isMain(_ player: SavedPlayer) -> Bool { player.id == mainPlayerID }

    func setMainPlayer(_ player: SavedPlayer) {
        mainPlayerID = player.id
    }

    /// Makes the player with this name the main player, adding them if they don't exist yet.
    @discardableResult
    func makeMainPlayer(named name: String) -> SavedPlayer? {
        guard let player = addPlayer(named: name) else { return nil }
        mainPlayerID = player.id
        return player
    }

    /// Renames a player, here and in the match history. Fails when another player already has the name.
    @discardableResult
    func rename(_ player: SavedPlayer, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = players.firstIndex(where: { $0.id == player.id }) else { return false }
        if players.contains(where: { $0.id != player.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return false
        }
        let old = players[index].name
        players[index].name = trimmed
        for m in matches.indices {
            for p in matches[m].players.indices where matches[m].players[p].name == old {
                matches[m].players[p].name = trimmed
            }
            if matches[m].winnerName == old { matches[m].winnerName = trimmed }
        }
        save(players, key: playersKey)
        save(matches, key: matchesKey)
        return true
    }

    /// One-time switch (Oct 2026) from the old name-matched profile to a linked main player: links the existing
    /// "Max" player and renames him "Maxo", as the owner asked; otherwise links the player matching the old
    /// profile name. Runs once; safe to delete after it has run on the phone.
    private func migrateMainPlayer() {
        let defaults = UserDefaults.standard
        let migratedKey = "dartify.mainPlayerMigrated"
        guard mainPlayerID == nil, !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)

        func player(named name: String) -> SavedPlayer? {
            players.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        if let max = player(named: "Max") {
            mainPlayerID = max.id
            rename(max, to: "Maxo")
        } else if let legacy = defaults.string(forKey: "dartify.username"), let match = player(named: legacy) {
            mainPlayerID = match.id
        }
    }

    // MARK: - Players

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

    /// Removes a player; the main player can't be removed.
    func removePlayer(_ player: SavedPlayer) {
        guard !isMain(player) else { return }
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
