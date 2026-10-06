//
//  CameraOverlays.swift
//  Dartify
//
//  Views drawn over the camera: board wireframe and darts, detector debug panel, dart correction keypad.
//

import SwiftUI

extension Color {
    static let magenta = Color(red: 0.9, green: 0.1, blue: 0.8)
}

struct DartSlot: Identifiable {
    let index: Int
    var id: Int { index }
}

/// Keypad for correcting a dart: pick single/double/treble and a number, or 25, bull, miss, or remove the dart.
struct DartEditor: View {
    let slot: Int
    let current: BoardScore?
    let pick: (BoardScore?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ring = BoardScore.Ring.single

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Ring", selection: $ring) {
                    Text("Single").tag(BoardScore.Ring.single)
                    Text("Double").tag(BoardScore.Ring.double)
                    Text("Treble").tag(BoardScore.Ring.treble)
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                    ForEach(1...20, id: \.self) { number in
                        Button("\(number)") { choose(BoardScore(ring: ring, number: number)) }
                            .font(.title3.monospacedDigit())
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.bordered)
                    }
                }

                HStack {
                    Button("25") { choose(BoardScore(ring: .outerBull, number: 0)) }
                    Button("Bull") { choose(BoardScore(ring: .bull, number: 0)) }
                    Button("Miss") { choose(BoardScore(ring: .miss, number: 0)) }
                }
                .buttonStyle(.bordered)
                .font(.title3)

                if current != nil {
                    Button("Remove dart", role: .destructive) { choose(nil) }
                }
                Spacer()
            }
            .padding()
            .navigationTitle(current.map { "Dart \(slot + 1): \($0.label)" } ?? "Add dart \(slot + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if let current, [.single, .double, .treble].contains(current.ring) { ring = current.ring }
        }
    }

    private func choose(_ score: BoardScore?) {
        pick(score)
        dismiss()
    }
}

/// Detector diagnostics: classified mask (red/green, rest grey, yellow = candidate fit) and per-stage log lines.
struct DebugPanel: View {
    let debug: DetectionDebug

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if let mask = debug.mask {
                Image(decorative: mask, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120)
                    .border(.white.opacity(0.6))
            }
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(debug.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .allowsHitTesting(false)
    }
}

/// Draws a white guide circle while searching, the double ring once found,
/// and the full board wireframe with segment numbers once calibrated.
struct BoardOverlay: View {
    let detection: DetectionResult
    var tap: CGPoint?
    var darts: [DetectedDart] = []

    var body: some View {
        Canvas { context, size in
            let toView = Self.imageToView(image: detection.imageSize, view: size)

            if detection.found, let homography = detection.boardToImage {
                drawBoard(homography, toView, in: &context)
                for dart in darts where dart.hasPosition {
                    guard let p = homography.apply(dart.x, dart.y) else { continue }
                    let v = CGPoint(x: p.x, y: p.y).applying(toView)
                    context.fill(Path(ellipseIn: CGRect(x: v.x - 5, y: v.y - 5, width: 10, height: 10)), with: .color(.yellow))
                    context.draw(
                        Text(dart.score.label).font(.caption.bold()).foregroundStyle(.yellow),
                        at: CGPoint(x: v.x, y: v.y - 14)
                    )
                }
                if let tap, let p = homography.apply(tap.x, tap.y) {
                    let v = CGPoint(x: p.x, y: p.y).applying(toView)
                    context.fill(Path(ellipseIn: CGRect(x: v.x - 6, y: v.y - 6, width: 12, height: 12)), with: .color(Color.magenta))
                }
            } else if detection.found, let outer = detection.outer {
                context.stroke(path(for: outer, toView), with: .color(.green), lineWidth: 3)
                if let inner = detection.inner {
                    context.stroke(path(for: inner, toView), with: .color(.green), lineWidth: 2)
                }
            } else {
                let d = min(size.width, size.height) * 0.8
                let rect = CGRect(x: (size.width - d) / 2, y: (size.height - d) / 2, width: d, height: d)
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(.white.opacity(0.8)),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
            }

            // Crosshair marking the pixel reported as "center h/s/v" in the debug panel.
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            var cross = Path()
            cross.move(to: CGPoint(x: c.x - 10, y: c.y)); cross.addLine(to: CGPoint(x: c.x + 10, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - 10)); cross.addLine(to: CGPoint(x: c.x, y: c.y + 10))
            context.stroke(cross, with: .color(.yellow), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }

    private func drawBoard(_ h: Homography, _ toView: CGAffineTransform, in context: inout GraphicsContext) {
        func view(_ p: (x: Double, y: Double)) -> CGPoint? {
            h.apply(p.x, p.y).map { CGPoint(x: $0.x, y: $0.y).applying(toView) }
        }

        var wires = Path()
        for radius in BoardGeometry.ringRadii {
            let points = (0...120).compactMap { view(BoardGeometry.point(radius: radius, degrees: Double($0) * 3)) }
            wires.addLines(points)
        }
        for index in 0..<20 {
            let angle = BoardGeometry.boundaryAngle(after: index)
            if let a = view(BoardGeometry.point(radius: BoardGeometry.outerBullRadius, degrees: angle)),
               let b = view(BoardGeometry.point(radius: BoardGeometry.doubleOuter, degrees: angle)) {
                wires.move(to: a)
                wires.addLine(to: b)
            }
        }
        context.stroke(wires, with: .color(.green), lineWidth: 1.5)

        for (index, number) in BoardGeometry.order.enumerated() {
            if let p = view(BoardGeometry.point(radius: 192, degrees: BoardGeometry.segmentAngle(index))) {
                context.draw(
                    Text("\(number)").font(.caption.bold()).foregroundStyle(.green),
                    at: p
                )
            }
        }
    }

    /// Same aspect-fill mapping the preview layer uses.
    static func imageToView(image: CGSize, view: CGSize) -> CGAffineTransform {
        guard image.width > 0, image.height > 0 else { return .identity }
        let scale = max(view.width / image.width, view.height / image.height)
        let dx = (view.width - image.width * scale) / 2
        let dy = (view.height - image.height * scale) / 2
        return CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: dx, y: dy))
    }

    private func path(for e: Ellipse, _ toView: CGAffineTransform) -> Path {
        let unit = Path(ellipseIn: CGRect(x: -e.a, y: -e.b, width: 2 * e.a, height: 2 * e.b))
        let placement = CGAffineTransform(rotationAngle: e.angle)
            .concatenating(CGAffineTransform(translationX: e.cx, y: e.cy))
            .concatenating(toView)
        return unit.applying(placement)
    }
}
