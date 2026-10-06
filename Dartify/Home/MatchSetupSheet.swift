//
//  MatchSetupSheet.swift
//  Dartify
//
//  X01 match setup, after the React app's MatchSetupSheet.
//

import SwiftUI

struct MatchSetupSheet: View {
    let start: (X01Config, [SavedPlayer]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = LocalStore.shared

    @State private var startingScore = 501
    @State private var doubleOut = true
    @State private var doubleIn = false
    @State private var bestOf = false
    @State private var legs = 3
    @State private var numPlayers = 2
    @State private var selected: [SavedPlayer] = []
    @State private var newName = ""

    private var config: X01Config {
        X01Config(startingScore: startingScore, doubleOut: doubleOut, doubleIn: doubleIn, legs: bestOf ? legs : 1)
    }

    private var remaining: Int { numPlayers - selected.count }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 12) {
                    formatCard
                    playersCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            Button {
                start(config, selected)
                dismiss()
            } label: {
                Label(remaining == 0 ? "Start match" : "Pick \(remaining) more \(remaining == 1 ? "player" : "players")",
                      systemImage: "play.fill")
            }
            .buttonStyle(SoftPrimaryButtonStyle())
            .disabled(remaining != 0)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Soft.shell)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("X01", systemImage: "target")
                    .font(.system(size: 21, weight: .semibold))
                    .displayTracking()
                    .foregroundStyle(Soft.slateSoft)
                Spacer()
                SoftIconButton(systemImage: "xmark", size: 36) { dismiss() }
            }
            Text(config.headline)
                .font(.system(size: 28, weight: .semibold))
                .displayTracking()
                .foregroundStyle(Soft.slate)
                .padding(.top, 20)
                .contentTransition(.numericText())
            Text("\(bestOf ? "Best of \(legs) legs" : "First to zero wins") · \(numPlayers) \(numPlayers == 1 ? "player" : "players")")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Soft.subtle)
                .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: config)
    }

    private var formatCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(systemImage: "slider.horizontal.3", title: "Format")

            Field(label: "Starting score") {
                SoftSegmented(options: [301, 501, 701].map { ($0, "\($0)") }, selection: $startingScore)
            }
            Field(label: "Players") {
                SoftSegmented(options: (1...4).map { ($0, "\($0)") }, selection: $numPlayers)
            }
            .onChange(of: numPlayers) { _, n in
                if selected.count > n { selected = Array(selected.prefix(n)) }
            }

            Divider().overlay(Soft.line)

            VStack(spacing: 0) {
                SoftToggleRow(label: "Double out", description: "Finish on a double", isOn: $doubleOut)
                SoftToggleRow(label: "Double in", description: "Start scoring with a double", isOn: $doubleIn)
                SoftToggleRow(label: "Best of X legs", description: "Play a multi-leg match", isOn: $bestOf)
            }

            if bestOf {
                Field(label: "Legs") {
                    SoftSegmented(options: [3, 5, 7].map { ($0, "\($0)") }, selection: $legs)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .softCard()
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: bestOf)
    }

    private var playersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(systemImage: "person.2", title: "Who's playing", trailing: "\(selected.count) of \(numPlayers)")

            Text("Tap players in throwing order.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Soft.subtle)

            FlowLayout(spacing: 8) {
                ForEach(store.players) { player in
                    PlayerChip(
                        player: player,
                        order: selected.firstIndex(of: player),
                        disabled: selected.count >= numPlayers && !selected.contains(player),
                        toggle: { toggle(player) }
                    )
                    .contextMenu {
                        Button("Remove player", systemImage: "trash", role: .destructive) {
                            selected.removeAll { $0 == player }
                            store.removePlayer(player)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus")
                    .foregroundStyle(Soft.subtle)
                TextField("Add player", text: $newName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Soft.slate)
                    .submitLabel(.done)
                    .onSubmit(addPlayer)
                if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add", action: addPlayer)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Accent.mint.ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Soft.track.opacity(0.7), in: Capsule())
            .overlay(Capsule().stroke(Color(hex: 0xE4E5E8), lineWidth: 1))
        }
        .padding(20)
        .softCard()
    }

    private func toggle(_ player: SavedPlayer) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if let index = selected.firstIndex(of: player) {
                selected.remove(at: index)
            } else if selected.count < numPlayers {
                selected.append(player)
            }
        }
    }

    private func addPlayer() {
        guard let player = store.addPlayer(named: newName) else { return }
        newName = ""
        if !selected.contains(player) && selected.count < numPlayers {
            withAnimation { selected.append(player) }
        }
    }
}

/// A saved player; selected players show their throwing order in their seat colour.
private struct PlayerChip: View {
    let player: SavedPlayer
    let order: Int?
    let disabled: Bool
    let toggle: () -> Void

    var body: some View {
        let accent = order.map(Accent.slot) ?? Accent.forName(player.name)
        Button(action: toggle) {
            HStack(spacing: 8) {
                SoftAvatar(name: player.name, size: 28, accent: accent)
                Text(player.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(order != nil ? accent.ink : Soft.slate)
                if let order {
                    Text("\(order + 1)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(accent.solid, in: Circle())
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, order != nil ? 6 : 14)
            .frame(height: 38)
            .background(order != nil ? accent.tint : .white, in: Capsule())
            .overlay(Capsule().stroke(order != nil ? accent.solid.opacity(0.5) : Soft.line, lineWidth: 1))
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(SoftPressStyle())
        .disabled(disabled)
    }
}

private struct SectionLabel: View {
    let systemImage: String
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Label {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Soft.slate)
            } icon: {
                Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)).foregroundStyle(Soft.subtle)
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Soft.subtle)
            }
        }
    }
}

private struct Field<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Soft.subtle)
                .padding(.leading, 4)
            content
        }
    }
}

/// Wraps chips onto new lines as needed.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: [Int] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                rows.append((current, y, x - spacing, rowHeight))
                y += rowHeight + spacing
                current = []
                x = 0
                rowHeight = 0
            }
            current.append(index)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        if !current.isEmpty { rows.append((current, y, x - spacing, rowHeight)) }
        return rows
    }
}
