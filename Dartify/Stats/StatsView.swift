//
//  StatsView.swift
//  Dartify
//
//  The main user's stats from SwiftData: a headline average, form over recent games, records and history.
//

import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    @State private var store = LocalStore.shared
    @Query(sort: \MatchStat.date, order: .reverse) private var allMatches: [MatchStat]
    @Environment(\.modelContext) private var context
    @State private var filter: Filter = .all
    @State private var selectedMatch: Int?
    @State private var appeared = false

    private enum Filter: Hashable { case all, x01, killer }

    private var matches: [MatchStat] {
        switch filter {
        case .all: allMatches
        case .x01: allMatches.filter(\.isX01)
        case .killer: allMatches.filter { !$0.isX01 }
        }
    }

    private var summary: StatSummary { StatSummary(matches: matches) }
    private var myName: String { store.mainPlayer?.name ?? "" }

    /// The last 20 X01 averages, oldest first, numbered for the chart's x axis.
    private var form: [FormPoint] {
        let recent = matches.filter(\.isX01).prefix(20).reversed()
        return recent.enumerated().compactMap { i, match in
            match.average.map { FormPoint(id: i + 1, average: $0, date: match.date) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.mainPlayer == nil {
                    EmptyStatsCard(systemImage: "person.crop.circle.badge.questionmark", title: "Pick your player first",
                                   message: "Stats are saved for your player. Choose or add it on your profile, then play a match.")
                } else {
                    overviewSection.rise(0, appeared)
                    if filter != .killer { formSection.rise(1, appeared) }
                    recordsSection.rise(2, appeared)
                    historySection.rise(3, appeared)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Soft.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear { appeared = true }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShellTitle(systemImage: "chart.bar.fill", title: "Stats") {
                SoftSegmented(options: [(value: Filter.all, label: "All"), (value: Filter.x01, label: "X01"),
                                        (value: Filter.killer, label: "Killer")], selection: $filter)
                    .frame(width: 200)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Text(headline)
                .font(.system(size: 26, weight: .semibold))
                .displayTracking()
                .foregroundStyle(Soft.slate)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 20) {
                if filter != .killer {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.average.map { String(format: "%.1f", $0) } ?? "–")
                            .font(.system(size: 52, weight: .semibold))
                            .displayTracking()
                            .monospacedDigit()
                            .foregroundStyle(summary.average == nil ? Soft.subtle : Soft.slate)
                            .contentTransition(.numericText())
                        Text("3-dart average")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Soft.subtle)
                    }
                }
                HStack(alignment: .top, spacing: 0) {
                    LabeledValue(label: "Played", value: summary.played > 0 ? "\(summary.played)" : nil)
                    LabeledValue(label: "Wins", value: summary.played > 0 ? "\(summary.wins)" : nil)
                    LabeledValue(label: "Win rate", value: summary.winRate.map { $0.formatted(.percent.precision(.fractionLength(0))) })
                    LabeledValue(label: "Streak", value: summary.streak > 0 ? "\(summary.streak)" : nil)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard()
        }
        .padding(8)
        .softShell()
        .animation(.snappy, value: filter)
    }

    private var headline: String {
        if summary.played == 0 { return "No games yet, \(myName). The board is waiting." }
        if summary.streak >= 2 { return "\(summary.streak) wins in a row. Keep it going." }
        if let average = summary.average, filter != .killer {
            return "Averaging \(String(format: "%.1f", average)) a visit."
        }
        return "\(summary.wins) of \(summary.played) won."
    }

    // MARK: - Form chart

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShellTitle(systemImage: "waveform.path.ecg", title: "Form") {
                if form.count >= 2 {
                    Text("Last \(form.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Soft.subtle)
                }
            }
            .padding(16)

            Group {
                if form.count >= 2 {
                    formChart
                } else {
                    Text("Play two X01 matches to see your form.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Soft.subtle)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding(16)
            .softCard()
        }
        .padding(8)
        .softShell()
    }

    private var formChart: some View {
        let overall = summary.average ?? 0
        let selected = form.first { $0.id == selectedMatch }

        return Chart {
            RuleMark(y: .value("Overall", overall))
                .foregroundStyle(Soft.subtle.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))

            ForEach(form) { point in
                LineMark(x: .value("Match", point.id), y: .value("Average", point.average))
                    .foregroundStyle(Accent.azure.solid)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Match", point.id), y: .value("Average", point.average))
                    .foregroundStyle(Accent.azure.solid)
                    .symbolSize(point.id == selectedMatch ? 110 : 50)
            }

            if let selected {
                RuleMark(x: .value("Match", selected.id))
                    .foregroundStyle(Soft.subtle.opacity(0.35))
                    .annotation(position: .top, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f", selected.average))
                                .font(.system(size: 15, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Soft.slate)
                            Text(selected.date, format: .dateTime.day().month(.abbreviated))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Soft.subtle)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .softFloat(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
            }
        }
        .chartXSelection(value: $selectedMatch)
        .chartXAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(Soft.line)
                AxisValueLabel().foregroundStyle(Soft.subtle)
            }
        }
        .frame(height: 180)
        .padding(.top, 24)
        .sensoryFeedback(.selection, trigger: selectedMatch)
        .accessibilityLabel("Three-dart average over the last \(form.count) X01 matches")
    }

    // MARK: - Records

    private var recordsSection: some View {
        VStack(spacing: 8) {
            ShellTitle(systemImage: "trophy.fill", title: "Records")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                if filter == .killer {
                    RecordTile(systemImage: "scope", accent: .coral, value: summary.kills, label: "Points taken")
                    RecordTile(systemImage: "flame.fill", accent: .mint, value: summary.streak, label: "Win streak")
                } else {
                    RecordTile(systemImage: "trophy.fill", accent: .azure, value: summary.highestCheckout, label: "High out")
                    RecordTile(systemImage: "bolt.fill", accent: .coral, value: summary.bestLegDarts, label: "Best leg", unit: "darts")
                    RecordTile(systemImage: "arrow.up.right", accent: .mint, value: summary.highestVisit, label: "Best visit")
                    RecordTile(systemImage: "target", accent: .orchid,
                               text: summary.bestMatchAverage.map { String(format: "%.1f", $0) }, label: "Best match avg")
                    RecordTile(systemImage: "star.fill", accent: .coral, value: summary.oneEighties, label: "180s")
                    RecordTile(systemImage: "flame.fill", accent: .azure, value: summary.ton40Plus, label: "140+")
                }
            }
        }
        .padding(8)
        .softShell()
    }

    // MARK: - History

    private var historySection: some View {
        VStack(spacing: 8) {
            ShellTitle(systemImage: "clock.arrow.circlepath", title: "History")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if matches.isEmpty {
                EmptyStatsCard(systemImage: "target", title: "No matches yet",
                               message: "Finished games you play as \(myName) show up here.")
            } else {
                ForEach(matches.prefix(25)) { match in
                    HistoryCard(match: match)
                        .contextMenu {
                            Button("Delete from stats", systemImage: "trash", role: .destructive) {
                                withAnimation(.snappy) {
                                    context.delete(match)
                                    try? context.save()
                                }
                            }
                        }
                }
            }
        }
        .padding(8)
        .softShell()
    }
}

private struct FormPoint: Identifiable {
    let id: Int
    let average: Double
    let date: Date
}

// MARK: - Pieces

private struct LabeledValue: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Soft.subtle)
            Text(value ?? "–")
                .font(.system(size: 20, weight: .semibold))
                .displayTracking()
                .monospacedDigit()
                .foregroundStyle(value == nil ? Soft.subtle : Soft.slate)
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// White card with a tinted icon, a big value and a label.
private struct RecordTile: View {
    let systemImage: String
    let accent: Accent
    let text: String?
    let label: String
    var unit: String?

    init(systemImage: String, accent: Accent, text: String?, label: String, unit: String? = nil) {
        self.systemImage = systemImage
        self.accent = accent
        self.text = text
        self.label = label
        self.unit = unit
    }

    /// Zero counts as "nothing yet" and shows a dash.
    init(systemImage: String, accent: Accent, value: Int?, label: String, unit: String? = nil) {
        self.init(systemImage: systemImage, accent: accent, text: value.flatMap { $0 > 0 ? "\($0)" : nil }, label: label, unit: unit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent.ink)
                .frame(width: 36, height: 36)
                .background(accent.tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(text ?? "–")
                        .font(.system(size: 24, weight: .semibold))
                        .displayTracking()
                        .monospacedDigit()
                        .foregroundStyle(text == nil ? Soft.subtle : Soft.slate)
                    if let unit, text != nil {
                        Text(unit)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Soft.subtle)
                    }
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Soft.subtle)
            }
            .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }
}

private struct HistoryCard: View {
    let match: MatchStat

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: match.isX01 ? "scope" : "flame.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(match.won ? Accent.mint.ink : Soft.slateSoft)
                .frame(width: 48, height: 48)
                .background(match.won ? Accent.mint.tint : Soft.track, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(opponentsLine)
                    .font(.system(size: 17, weight: .semibold))
                    .displayTracking()
                    .foregroundStyle(Soft.slate)
                Text(detailLine)
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Soft.subtle)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            SoftBadge(accent: match.won ? .mint : .coral, text: match.won ? "Won" : "Lost")
        }
        .padding(14)
        .padding(.trailing, 4)
        .softCard()
        .contentShape(.contextMenuPreview, .rect(cornerRadius: 24))
    }

    private var opponentsLine: String {
        match.opponents.isEmpty ? match.title : "vs \(match.opponents.formatted(.list(type: .and)))"
    }

    private var detailLine: String {
        var parts = [match.title]
        if let average = match.average { parts.append("\(String(format: "%.1f", average)) avg") }
        if match.isX01, match.legsWon + match.legsLost > 1 { parts.append("\(match.legsWon)–\(match.legsLost)") }
        parts.append(match.date.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }
}

private struct EmptyStatsCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .softCard()
    }
}

#Preview {
    NavigationStack { StatsView() }
        .modelContainer(for: MatchStat.self, inMemory: true)
}
