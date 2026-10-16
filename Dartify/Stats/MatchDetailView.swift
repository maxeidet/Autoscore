//
//  MatchDetailView.swift
//  Dartify
//
//  One finished match from the stats history: the result, its numbers, a heat map and every visit.
//

import SwiftData
import SwiftUI

struct MatchDetailView: View {
    let match: MatchStat
    @State private var appeared = false

    private var visits: [VisitLog] { match.visitLog }
    private var legs: [Int] { Array(Set(visits.map(\.leg))).sorted() }
    private var doubleRate: Double? {
        match.doubleAttempts > 0 ? Double(match.doublesHit) / Double(match.doubleAttempts) : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                resultSection.rise(0, appeared)
                if match.isX01 { numbersSection.rise(1, appeared) }
                if !match.dartLog.isEmpty { heatMapSection.rise(2, appeared) }
                visitsSection.rise(3, appeared)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Soft.canvas.ignoresSafeArea())
        .navigationTitle(match.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear { appeared = true }
    }

    // MARK: - Result

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShellTitle(systemImage: match.isX01 ? "scope" : "flame.fill", title: match.title) {
                SoftBadge(accent: match.won ? .mint : .coral, text: match.won ? "Won" : "Lost")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Text(match.opponents.isEmpty ? "Solo game." : "vs \(match.opponents.formatted(.list(type: .and))).")
                .font(.system(size: 26, weight: .semibold))
                .displayTracking()
                .foregroundStyle(Soft.slate)
                .padding(.horizontal, 16)
                .padding(.top, 20)
            Text(match.date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Soft.subtle)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 20)

            HStack(alignment: .top, spacing: 0) {
                if match.isX01 {
                    LabeledValue(label: "Average", value: match.average.map { String(format: "%.1f", $0) })
                    LabeledValue(label: "Darts", value: "\(match.darts)")
                    if match.legsWon + match.legsLost > 1 {
                        LabeledValue(label: "Legs", value: "\(match.legsWon)–\(match.legsLost)")
                    }
                } else {
                    LabeledValue(label: "Darts", value: "\(match.darts)")
                    LabeledValue(label: "Points taken", value: "\(match.kills)")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard()
        }
        .padding(8)
        .softShell()
    }

    // MARK: - Numbers

    private var numbersSection: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            RecordTile(systemImage: "trophy.fill", accent: .azure, value: match.highestCheckout, label: "Checkout")
            RecordTile(systemImage: "bolt.fill", accent: .coral, value: match.bestLegDarts, label: "Best leg", unit: "darts")
            RecordTile(systemImage: "arrow.up.right", accent: .mint, value: match.highestVisit, label: "Best visit")
            RecordTile(systemImage: "scope", accent: .orchid,
                       text: doubleRate.map { $0.formatted(.percent.precision(.fractionLength(0))) },
                       label: match.doubleAttempts > 0 ? "Doubles · \(match.doublesHit)/\(match.doubleAttempts)" : "Doubles")
        }
        .padding(8)
        .softShell()
    }

    // MARK: - Heat map

    private var heatMapSection: some View {
        let darts = match.dartLog
        return VStack(spacing: 0) {
            ShellTitle(systemImage: "circle.hexagongrid.fill", title: "Heat map") {
                Text("\(darts.count) darts")
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Soft.subtle)
            }
            .padding(16)

            HeatMapView(darts: darts)
                .frame(maxWidth: 320)
                .padding(16)
                .frame(maxWidth: .infinity)
                .softCard()
        }
        .padding(8)
        .softShell()
    }

    // MARK: - Visits

    private var visitsSection: some View {
        VStack(spacing: 8) {
            ShellTitle(systemImage: "list.number", title: "Visits")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if visits.isEmpty {
                Text("Darts weren't saved for this match. Matches you play from now on keep every dart.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Soft.subtle)
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .softCard()
            } else {
                ForEach(legs, id: \.self) { leg in
                    VStack(alignment: .leading, spacing: 0) {
                        if legs.count > 1 {
                            Text("Leg \(leg)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Soft.subtle)
                                .padding(.horizontal, 6)
                                .padding(.bottom, 8)
                        }
                        let legVisits = visits.filter { $0.leg == leg }
                        ForEach(Array(legVisits.enumerated()), id: \.offset) { i, visit in
                            if i > 0 { Divider() }
                            VisitRow(number: i + 1, visit: visit)
                        }
                    }
                    .padding(12)
                    .softCard()
                }
            }
        }
        .padding(8)
        .softShell()
    }
}

/// "3   T20  S20  S5   85   331"
private struct VisitRow: View {
    let number: Int
    let visit: VisitLog

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Soft.subtle)
                .frame(width: 22, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    DartChip(dart: i < visit.darts.count ? visit.darts[i] : nil)
                }
            }
            Spacer(minLength: 8)
            if visit.isBust {
                SoftBadge(accent: .coral, text: "Bust")
            } else if visit.isCheckout {
                SoftBadge(accent: .mint, text: "Out")
            }
            if let scored = visit.scored {
                Text("\(scored)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(visit.isBust ? Soft.subtle : Soft.slate)
                    .frame(width: 36, alignment: .trailing)
            }
            if let left = visit.left {
                Text("\(left)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Soft.subtle)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// One dart's label, tinted by ring; an empty slot for darts not thrown.
private struct DartChip: View {
    let dart: DartThrow?

    private var accent: Accent? {
        switch dart?.score.ring {
        case .treble: .coral
        case .double: .mint
        case .bull, .outerBull: .azure
        default: nil
        }
    }

    var body: some View {
        Text(dart?.score.label ?? "–")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(accent?.ink ?? (dart?.score.ring == .miss || dart == nil ? Soft.subtle : Soft.slate))
            .frame(width: 44, height: 28)
            .background(accent?.tint ?? Soft.track, in: Capsule())
    }
}

#Preview {
    let visits = [
        VisitLog(leg: 1, darts: [.init(score: .init(ring: .treble, number: 20)), .init(score: .init(ring: .single, number: 20)),
                                 .init(score: .init(ring: .single, number: 5))], scored: 85, left: 416),
        VisitLog(leg: 1, darts: [.init(score: .init(ring: .miss, number: 0))], scored: 0, left: 416, isBust: true),
    ]
    NavigationStack {
        MatchDetailView(match: MatchStat(mode: "x01", title: "501", won: true, opponents: ["Anna"], darts: 6, points: 85,
                                         visitLog: visits))
    }
    .modelContainer(for: MatchStat.self, inMemory: true)
}
