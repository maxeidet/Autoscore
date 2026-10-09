//
//  TapBoardView.swift
//  Dartify
//
//  Tap scoring on a photo of a board, after the React app's DartboardSVG: press and drag to aim with a
//  magnifier, lift to throw. The dart lands where the magnifier last pointed, not where the finger lifts,
//  because fingers drift a few points on release.
//

import SwiftUI

struct TapBoardView: View {
    /// Darts of the current visit, drawn as numbered markers.
    let darts: [DetectedDart]
    var disabled = false
    let onThrow: (DetectedDart) -> Void

    /// Where the finger is aiming, in board view coordinates, while pressing.
    @State private var aim: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            board(size: size)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func board(size: CGFloat) -> some View {
        let aimedScore = aim.map { Self.score(at: $0, size: size) }

        return ZStack {
            BoardPhoto()
            ForEach(Array(darts.prefix(3).enumerated()), id: \.offset) { i, dart in
                if let point = Self.viewPoint(for: dart, size: size) {
                    DartMarker(number: i + 1, boardSize: size)
                        .position(point)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .frame(width: size, height: size)
        .opacity(disabled ? 0.5 : 1)
        .contentShape(Circle())
        .gesture(aimGesture(size: size))
        .allowsHitTesting(!disabled)
        .overlay {
            if let aim, let aimedScore {
                Loupe(aim: aim, boardSize: size, label: aimedScore.label)
                    .position(x: aim.x, y: aim.y - 100)
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: darts)
        .animation(.easeOut(duration: 0.2), value: disabled)
        .sensoryFeedback(.selection, trigger: aimedScore)
        .sensoryFeedback(.impact(weight: .medium), trigger: darts.count) { old, new in new > old }
    }

    private func aimGesture(size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { aim = $0.location }
            .onEnded { _ in
                guard let point = aim else { return }
                aim = nil
                onThrow(Self.dart(at: point, size: size))
            }
    }

    // MARK: - Geometry

    /// Ring edges measured off the board photo, as fractions of its half-width (the React app's dartboardMath.ts),
    /// so hit-testing lines up with what's drawn.
    private enum R {
        static let bullseye = 0.031
        static let bull = 0.072
        static let trebleInner = 0.431
        static let trebleOuter = 0.472
        static let doubleInner = 0.71
        static let doubleOuter = 0.752
    }

    /// Board millimetres per photo half-width: the double ring's outer edge is the standard 170 mm.
    private static let mmPerHalfWidth = BoardGeometry.doubleOuter / R.doubleOuter

    /// Offset from the centre as fractions of the half-width, with y up.
    private static func unit(_ p: CGPoint, size: CGFloat) -> (x: Double, y: Double) {
        let half = Double(size) / 2
        return ((Double(p.x) - half) / half, (half - Double(p.y)) / half)
    }

    static func score(at p: CGPoint, size: CGFloat) -> BoardScore {
        let (x, y) = unit(p, size: size)
        let r = hypot(x, y)
        if r <= R.bullseye { return BoardScore(ring: .bull, number: 0) }
        if r <= R.bull { return BoardScore(ring: .outerBull, number: 0) }
        if r > R.doubleOuter { return BoardScore(ring: .miss, number: 0) }

        // Degrees clockwise from the top, shifted half a segment so 20 spans -9°…9°.
        var degrees = atan2(x, y) * 180 / .pi + 9
        if degrees < 0 { degrees += 360 }
        let number = BoardGeometry.order[Int(degrees / 18) % 20]

        let ring: BoardScore.Ring
        if r >= R.trebleInner && r <= R.trebleOuter { ring = .treble }
        else if r >= R.doubleInner { ring = .double }
        else { ring = .single }
        return BoardScore(ring: ring, number: number)
    }

    /// The dart for a tap, positioned in board millimetres like a camera dart.
    private static func dart(at p: CGPoint, size: CGFloat) -> DetectedDart {
        let (x, y) = unit(p, size: size)
        return DetectedDart(x: x * mmPerHalfWidth, y: y * mmPerHalfWidth, score: score(at: p, size: size))
    }

    /// Where to draw a dart's marker: its exact spot, or the middle of its bed for darts entered by hand.
    private static func viewPoint(for dart: DetectedDart, size: CGFloat) -> CGPoint? {
        let half = Double(size) / 2
        if dart.hasPosition {
            return CGPoint(x: half + dart.x / mmPerHalfWidth * half, y: half - dart.y / mmPerHalfWidth * half)
        }

        let r: Double
        switch dart.score.ring {
        case .miss: return nil
        case .bull: r = R.bullseye * 0.5
        case .outerBull: r = (R.bullseye + R.bull) / 2
        case .treble: r = (R.trebleInner + R.trebleOuter) / 2
        case .double: r = (R.doubleInner + R.doubleOuter) / 2
        case .single: r = (R.trebleOuter + R.doubleInner) / 2
        }
        let index = BoardGeometry.order.firstIndex(of: dart.score.number) ?? 0
        let angle = Double(index) * 18 * .pi / 180
        return CGPoint(x: half + r * half * sin(angle), y: half - r * half * cos(angle))
    }
}

// MARK: - Pieces

private struct BoardPhoto: View {
    var body: some View {
        Image("TapBoard")
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .clipShape(Circle())
            .background(Circle().fill(.white).softShadow(near: 0.08, far: 0.18, radius: 24, y: 10))
    }
}

/// A thin ring with a pinpoint centre on the landing spot, and the dart number in a tag beside it.
private struct DartMarker: View {
    let number: Int
    let boardSize: CGFloat

    var body: some View {
        let ring = max(5, boardSize * 0.016)
        let tag = max(6, boardSize * 0.019)
        ZStack {
            Circle().stroke(.white.opacity(0.9), lineWidth: 3.5)
                .frame(width: ring * 2, height: ring * 2)
            Circle().stroke(Soft.charcoal, lineWidth: 1.5)
                .frame(width: ring * 2, height: ring * 2)
            Circle().fill(Soft.charcoal)
                .overlay(Circle().stroke(.white, lineWidth: 1))
                .frame(width: 4, height: 4)
            Text("\(number)")
                .font(.system(size: tag * 1.15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: tag * 2, height: tag * 2)
                .background(Soft.charcoal, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .offset(x: ring + tag * 0.55, y: -(ring + tag * 0.55))
        }
        .allowsHitTesting(false)
    }
}

/// Magnified view of the board around the finger, shown above it so the finger doesn't hide the target.
private struct Loupe: View {
    let aim: CGPoint
    let boardSize: CGFloat
    let label: String

    private let diameter: CGFloat = 120
    private let zoom: CGFloat = 2.5

    var body: some View {
        BoardPhoto()
            .frame(width: boardSize * zoom, height: boardSize * zoom)
            .offset(x: diameter / 2 - aim.x * zoom, y: diameter / 2 - aim.y * zoom)
            .frame(width: diameter, height: diameter, alignment: .topLeading)
            .background(Soft.canvas)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .fill(.white.opacity(0.2))
                    .stroke(.white, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().fill(.red).frame(width: 2, height: 2))
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
            .overlay(alignment: .bottom) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Soft.charcoal, in: Capsule())
                    .padding(.bottom, 8)
            }
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: Soft.shadow.opacity(0.3), radius: 16, y: 12)
    }
}

#Preview {
    @Previewable @State var darts: [DetectedDart] = []
    TapBoardView(darts: darts, disabled: darts.count >= 3) { darts.append($0) }
        .padding()
        .background(Soft.canvas)
}
