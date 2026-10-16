//
//  HeatMapView.swift
//  Dartify
//
//  Where the main user's darts land, as glowing blobs over a faded board photo.
//

import SwiftUI

struct HeatMapView: View {
    let darts: [DartThrow]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let points = darts.compactMap { dart in
                TapBoardView.viewPoint(for: DetectedDart(x: dart.x ?? .nan, y: dart.y ?? .nan, score: dart.score), size: size)
            }
            ZStack {
                BoardPhoto()
                    .saturation(0)
                    .opacity(0.45)
                Canvas { context, _ in
                    // Wide, faint blobs add up where darts cluster; small bright cores mark each dart.
                    blobs(points, in: &context, radius: size * 0.07, color: Accent.coral.solid, alpha: blobAlpha)
                    blobs(points, in: &context, radius: size * 0.022, color: .yellow, alpha: 0.5)
                }
                .clipShape(Circle())
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Heat map of \(darts.count) darts")
    }

    /// Fainter blobs the more darts there are, so a big history doesn't turn into one solid patch.
    private var blobAlpha: Double { min(0.6, max(0.12, 6 / Double(max(darts.count, 1)))) }

    private func blobs(_ points: [CGPoint], in context: inout GraphicsContext, radius: CGFloat, color: Color, alpha: Double) {
        let gradient = Gradient(colors: [color.opacity(alpha), color.opacity(0)])
        for p in points {
            let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect),
                         with: .radialGradient(gradient, center: p, startRadius: 0, endRadius: radius))
        }
    }
}

extension [DartThrow] {
    /// The most-hit beds, e.g. ["T20", "S20", "S1"], misses left out.
    func topBeds(_ count: Int) -> [String] {
        let labels = map(\.score).filter { $0.ring != .miss }.map(\.label)
        let tally = Dictionary(labels.map { ($0, 1) }, uniquingKeysWith: +)
        return tally.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.prefix(count).map(\.key)
    }
}

#Preview {
    let darts = (0..<40).map { i in
        DartThrow(DetectedDart(x: Double(i % 7) * 3 - 9, y: 103 + Double(i % 5) * 4 - 8,
                               score: BoardGeometry.score(x: Double(i % 7) * 3 - 9, y: 103 + Double(i % 5) * 4 - 8)))
    }
    HeatMapView(darts: darts)
        .padding()
        .background(Soft.canvas)
}
