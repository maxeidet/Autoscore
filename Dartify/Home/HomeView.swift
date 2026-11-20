//
//  HomeView.swift
//  Dartify
//
//  Home screen in the React app's soft style: header, resume card, season stats and game modes.
//

import SwiftData
import SwiftUI

struct HomeView: View {
    @State private var store = LocalStore.shared
    /// The main user's matches, the same data the stats page shows.
    @Query(sort: \MatchStat.date, order: .reverse) private var statMatches: [MatchStat]
    @State private var match: MatchController?
    @State private var showingGame = false
    @State private var setupMode: SetupMode?
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header.rise(0, appeared)
                if let match, !match.isFinished {
                    ResumeCard(match: match, resume: { showingGame = true }, discard: { self.match = nil })
                        .rise(1, appeared)
                }
                NavigationLink {
                    StatsView()
                } label: {
                    statsSection
                }
                .buttonStyle(SoftPressStyle())
                .rise(2, appeared)
                playSection.rise(3, appeared)
                
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Soft.canvas.ignoresSafeArea())
        .onAppear { appeared = true }
        .sheet(item: $setupMode) { mode in
            MatchSetupSheet(mode: mode) { settings, players, input, bots in
                match = MatchController(settings: settings, players: players, input: input, bots: bots)
                showingGame = true
            }
        }
        .fullScreenCover(isPresented: $showingGame) {
            if let match {
                GameView(
                    match: match,
                    onLeave: { showingGame = false },
                    onRematch: { self.match = match.rematch() },
                    onFinish: {
                        showingGame = false
                        self.match = nil
                    }
                )
            }
        }
        .onChange(of: match == nil) { _, noMatch in
            if noMatch { Scoreboard.shared.match = nil }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Image("BDCLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 36)
                Text(greeting)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Soft.subtle)
            }
            Spacer()
            HStack(spacing: 8) {
                if Scoreboard.shared.tvConnected {
                    Image(systemName: "tv")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Accent.mint.ink)
                        .frame(width: 48, height: 48)
                        .softFloat(Circle())
                }
                NavigationLink {
                    ProfileView()
                } label: {
                    Image(systemName: "person.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
        }
        .padding(.horizontal, 8)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 5 { return "Late session" }
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: - Stats

    private var statsSection: some View {
        let summary = StatSummary(matches: statMatches)
        let average = summary.average
        let played = summary.played
        let headline = if let average {
            "Averaging \(String(format: "%.1f", average)) a visit."
        } else if played > 0 {
            "\(played) \(played == 1 ? "game" : "games") in the books."
        } else {
            "No games yet. The board is waiting."
        }

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ShellTitle(systemImage: "chart.pie.fill", title: "Season")
                Text(headline)
                    .font(.system(size: 26, weight: .semibold))
                    .displayTracking()
                    .foregroundStyle(Soft.slate)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                if played > 0 && average != nil {
                    Text("\(played) \(played == 1 ? "game" : "games") played")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Soft.subtle)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)

            SeasonBoard(
                average: average.map { String(format: "%.1f", $0) },
                highOut: summary.highestCheckout.map(String.init),
                bestLeg: summary.bestLegDarts.map(String.init)
            )
        }
        .padding(8)
        .softShell()
    }

    // MARK: - Play

    private var playSection: some View {
        VStack(spacing: 8) {
            ShellTitle(systemImage: "target", title: "Play")
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ModeRow(glyph: .x01, title: "X01", subtitle: "301 · 501 · 701") { setupMode = .x01 }
                ModeDivider()
                ModeRow(glyph: .killer, title: "Killer", subtitle: "Reach 3, then hunt the others") { setupMode = .killer }
                ModeDivider()
                ModeRow(glyph: .aroundTheClock, title: "Around the Clock", subtitle: "Hit 1 to 20 in order")
                ModeDivider()
                ModeRow(glyph: .roundTheWorld, title: "Round the World", subtitle: "Points on every number")
                ModeDivider()
                ModeRow(glyph: .cricket, title: "Cricket", subtitle: "Close out 15 to 20 and bull")
            }
            .padding(.vertical, 4)
            .softCard()
            /*
            Button {
                setupMode = .x01
            } label: {
                Label("New match", systemImage: "plus")
            }
            .buttonStyle(SoftPrimaryButtonStyle())
            .padding(.top, 4)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
             */
        }
        .padding(8)
        .softShell()
    }
}

/// The season numbers as three soft tinted tiles in the seat colours: a big coloured number and its label, no icons.
private struct SeasonBoard: View {
    let average: String?
    let highOut: String?
    let bestLeg: String?

    var body: some View {
        HStack(spacing: 8) {
            tile(average, label: "3-dart avg", accent: .mint)
            tile(highOut, label: "High out", accent: .azure)
            tile(bestLeg, label: "Best leg", unit: "darts", accent: .coral)
        }
        .padding(8)
        .softCard()
    }

    private func tile(_ value: String?, label: String, unit: String? = nil, accent: Accent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "–")
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                    .displayTracking()
                    .foregroundStyle(value == nil ? accent.ink.opacity(0.35) : accent.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit, value != nil {
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent.ink.opacity(0.7))
                }
            }
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent.ink.opacity(0.75))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(accent.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Game mode row: a small board showing where the mode is played, title and subtitle.
/// No action means the mode isn't built yet.
private struct ModeRow: View {
    let glyph: ModeGlyph
    let title: String
    let subtitle: String
    var action: (() -> Void)?

    private var isSoon: Bool { action == nil }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 14) {
                ModeBoard(glyph: glyph, isLive: !isSoon)
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .displayTracking()
                        .foregroundStyle(isSoon ? Soft.slateSoft : Soft.slate)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSoon ? Soft.subtle : Soft.slateSoft)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                if isSoon {
                    Text("Soon")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Soft.subtle)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Soft.subtle)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .disabled(isSoon)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isSoon ? "Coming soon" : "")
    }
}

private struct ModeDivider: View {
    var body: some View {
        Rectangle()
            .fill(Soft.line)
            .frame(height: 1)
            .padding(.leading, 76)
            .padding(.trailing, 14)
    }
}

/// Which beds light up on a mode's board.
private enum ModeGlyph {
    case x01, killer, aroundTheClock, roundTheWorld, cricket

    enum Bed { case segment(Int), treble(Int), bull }

    /// Beds with their strength; a fading run reads as "in order".
    var beds: [(bed: Bed, strength: Double)] {
        switch self {
        case .x01: [(.treble(20), 1)]
        case .killer: [(.segment(7), 1)]
        case .aroundTheClock: [(.segment(1), 1), (.segment(2), 0.6), (.segment(3), 0.3)]
        case .roundTheWorld: [(.segment(20), 1), (.segment(1), 0.6), (.segment(18), 0.3)]
        case .cricket: (15...20).map { (.segment($0), 1) } + [(.bull, 1)]
        }
    }
}

/// A plain dartboard in greys with the mode's beds in board red (grey when the mode isn't playable yet).
private struct ModeBoard: View {
    let glyph: ModeGlyph
    let isLive: Bool

    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let mm = r / BoardGeometry.doubleOuter

            // Board face with alternating wedges.
            context.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)), with: .color(Soft.track))
            for index in 0..<20 where index.isMultiple(of: 2) {
                context.fill(wedge(index: index, from: BoardGeometry.outerBullRadius * mm, to: r, center: center),
                             with: .color(Color(hex: 0xDEDFE3)))
            }

            let highlight = isLive ? Soft.danger : Soft.subtle
            for (bed, strength) in glyph.beds {
                let path: Path = switch bed {
                case .segment(let n):
                    wedge(index: index(of: n), from: BoardGeometry.outerBullRadius * mm, to: r, center: center)
                case .treble(let n):
                    wedge(index: index(of: n), from: BoardGeometry.trebleInner * mm, to: BoardGeometry.trebleOuter * mm + 1, center: center)
                case .bull:
                    Path(ellipseIn: CGRect(x: center.x - BoardGeometry.outerBullRadius * mm, y: center.y - BoardGeometry.outerBullRadius * mm,
                                           width: 2 * BoardGeometry.outerBullRadius * mm, height: 2 * BoardGeometry.outerBullRadius * mm))
                }
                context.fill(path, with: .color(highlight.opacity(strength)))
            }

            // Treble and double wires, so it reads as a board.
            for radius in [BoardGeometry.trebleInner, BoardGeometry.trebleOuter, BoardGeometry.doubleInner] {
                let d = radius * mm
                context.stroke(Path(ellipseIn: CGRect(x: center.x - d, y: center.y - d, width: 2 * d, height: 2 * d)),
                               with: .color(.white.opacity(0.9)), lineWidth: 0.75)
            }
        }
    }

    private func index(of number: Int) -> Int { BoardGeometry.order.firstIndex(of: number) ?? 0 }

    /// An annular sector for segment `index`, between two radii in points.
    private func wedge(index: Int, from inner: CGFloat, to outer: CGFloat, center: CGPoint) -> Path {
        let mid = BoardGeometry.segmentAngle(index)
        let angles = stride(from: mid - 9, through: mid + 9, by: 1.5).map { $0 * .pi / 180 }
        // Board angles go counter-clockwise with y up; the canvas has y down.
        func point(_ radius: CGFloat, _ a: Double) -> CGPoint {
            CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y - radius * CGFloat(sin(a)))
        }
        var path = Path()
        path.move(to: point(outer, angles[0]))
        for a in angles.dropFirst() { path.addLine(to: point(outer, a)) }
        for a in angles.reversed() { path.addLine(to: point(inner, a)) }
        path.closeSubpath()
        return path
    }
}

/// "Pick up where you left off" card for a match in progress.
private struct ResumeCard: View {
    let match: MatchController
    let resume: () -> Void
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Accent.mint.ink).frame(width: 8, height: 8)
                    Text("In progress")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Accent.mint.ink)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Accent.mint.tint, in: Capsule())
                Spacer()
                Text(match.title)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Soft.subtle)
            }

            Text("Pick up where you left off.")
                .font(.system(size: 22, weight: .semibold))
                .displayTracking()
                .foregroundStyle(Soft.slate)
                .padding(.top, 16)

            HStack(spacing: 12) {
                HStack(spacing: -8) {
                    ForEach(Array(match.state.playerNames.prefix(4).enumerated()), id: \.offset) { i, name in
                        SoftAvatar(name: name, size: 30, accent: Accent.slot(i))
                    }
                }
                Text(match.playerSummaries.joined(separator: " · "))
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Soft.slateSoft)
                    .lineLimit(1)
            }
            .padding(.top, 12)

            Button(action: resume) {
                Label("Resume game", systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(SoftPrimaryButtonStyle(height: 52))
            .padding(.top, 20)

            Button("Discard match", role: .destructive, action: discard)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Soft.subtle)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .padding(20)
        .softCard()
        .padding(8)
        .softShell()
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}

extension View {
    /// Staggered entrance for the stacked cards (`.soft-rise`).
    func rise(_ index: Int, _ appeared: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.spring(response: 0.52, dampingFraction: 0.86).delay(Double(index) * 0.06), value: appeared)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: MatchStat.self, inMemory: true)
}
