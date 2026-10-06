//
//  BoardDetector.swift
//  Dartify
//

import CoreGraphics
import CoreVideo
import Foundation

nonisolated struct DetectionResult: Sendable {
    /// Size of the analysed camera frame; ellipses are in this frame's pixel coordinates.
    var imageSize: CGSize
    /// Outer edge of the double ring.
    var outer: Ellipse?
    /// Inner edge of the double ring.
    var inner: Ellipse?
    /// Maps board millimetres (origin at the bull, y up) to frame pixels.
    var boardToImage: Homography?
    var found: Bool
    var debug = DetectionDebug()

    static let none = DetectionResult(imageSize: .zero, outer: nil, inner: nil, boardToImage: nil, found: false)
}

/// Diagnostics for tuning: what the detector saw and where it gave up.
nonisolated struct DetectionDebug: @unchecked Sendable {
    var lines: [String] = []
    /// Downsampled view: red/green pixels as classified, everything else grey, candidate ellipses drawn on top.
    var mask: CGImage?
}

/// Finds the dartboard's double ring (the outermost band of alternating red/green segments),
/// then the segment wires and bull, and fits a board → image homography.
nonisolated final class BoardDetector {
    private static let red: UInt8 = 1
    private static let green: UInt8 = 2

    private let targetWidth = 240
    private let binCount = 90
    private let historyLength = 6
    private let requiredHits = 4

    // Per-frame working buffers, reused between frames.
    private var width = 0
    private var height = 0
    private var labels: [UInt8] = []
    private var mask: [UInt8] = []
    private var temp: [UInt8] = []
    private var componentIDs: [Int32] = []
    private var stack: [Int32] = []
    private var preview: [UInt8] = []

    // Temporal state.
    private var history: [Bool] = []
    private var smoothedOuter: Ellipse?
    private var smoothedInner: Ellipse?
    private var smoothedHomography: Homography?

    private var debugLines: [String] = []

    private struct Component {
        var red = 0
        var green = 0
        var sumX = 0
        var sumY = 0
        var minX = Int.max
        var maxX = Int.min
        var minY = Int.max
        var maxY = Int.min
    }

    private struct RawDetection {
        var outer: Ellipse
        var inner: Ellipse?
        var boardToImage: Homography?
    }

    /// Full-resolution BGRA pixels; only valid while the pixel buffer is locked.
    private struct Frame {
        let base: UnsafePointer<UInt8>
        let width: Int
        let height: Int
        let rowBytes: Int

        func label(_ p: (x: Double, y: Double)) -> UInt8 {
            guard p.x >= 0, p.y >= 0 else { return 0 }
            let x = Int(p.x), y = Int(p.y)
            guard x < width, y < height else { return 0 }
            let px = base + y * rowBytes + x * 4
            return BoardDetector.classify(r: px[2], g: px[1], b: px[0])
        }
    }

    func process(_ pixelBuffer: CVPixelBuffer) -> DetectionResult {
        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        debugLines.removeAll()

        var raw: RawDetection?
        if CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let frame = Frame(
                    base: UnsafePointer(base.assumingMemoryBound(to: UInt8.self)),
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer),
                    rowBytes: CVPixelBufferGetBytesPerRow(pixelBuffer)
                )
                raw = detect(frame)
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        } else {
            log("✗ unsupported pixel format")
        }

        var result = stabilize(raw, imageSize: imageSize)
        result.debug = DetectionDebug(lines: debugLines, mask: makePreviewImage())
        return result
    }

    private func log(_ line: String) {
        debugLines.append(line)
    }

    private func reject(_ reason: String) -> RawDetection? {
        log("✗ \(reason)")
        return nil
    }

    // MARK: - Single-frame detection

    private func detect(_ frame: Frame) -> RawDetection? {
        let step = buildLabels(frame)
        let redCount = labels.reduce(0) { $0 + ($1 == Self.red ? 1 : 0) }
        let greenCount = labels.reduce(0) { $0 + ($1 == Self.green ? 1 : 0) }
        log("grid \(width)x\(height) step \(step) | red \(redCount) green \(greenCount)")

        buildDilatedMask()
        let components = labelComponents()
        guard let ringID = selectRing(components) else { return reject("no ring-shaped red+green blob") }
        let ring = components[Int(ringID)]

        let (outerPoints, innerPoints) = edgePoints(of: ring, id: ringID)
        guard outerPoints.count >= binCount / 2 else {
            return reject("edge points \(outerPoints.count) < \(binCount / 2) (ring incomplete?)")
        }

        guard let outerFit = EllipseFit.ransac(outerPoints, threshold: 1.5) else { return reject("ellipse fit failed") }
        let outer = outerFit.ellipse
        drawEllipse(outer, r: 255, g: 230, b: 0)
        log(String(format: "fit c=(%.0f,%.0f) a=%.1f b=%.1f b/a=%.2f inliers=%.2f",
                   outer.cx, outer.cy, outer.a, outer.b, outer.b / outer.a, outerFit.inlierRatio))
        guard outerFit.inlierRatio >= 0.6 else { return reject("inliers < 0.6") }
        guard outer.b / outer.a >= 0.35 else { return reject("too flat (b/a < 0.35)") }
        guard 2 * outer.b >= 0.15 * Double(width) else { return reject("too small") }
        guard outer.cx > 0, outer.cx < Double(width), outer.cy > 0, outer.cy < Double(height) else {
            return reject("center outside frame")
        }

        let transitions = colorTransitions(along: outer)
        log("red↔green transitions \(transitions) (want 14...26)")
        guard (14...26).contains(transitions) else { return reject("transitions out of range") }

        var coarseInner: Ellipse?
        if let innerFit = EllipseFit.ransac(innerPoints, threshold: 1.5),
           innerFit.inlierRatio >= 0.5 {
            let e = innerFit.ellipse
            let ratio = e.a / outer.a
            if ratio > 0.85, ratio < 1, hypot(e.cx - outer.cx, e.cy - outer.cy) < 0.1 * outer.a {
                coarseInner = e
                drawEllipse(e, r: 0, g: 220, b: 255)
            }
        }
        log("✓ ring")

        // Everything below works in full-resolution pixels.
        let s = Double(step)
        let refined = refineRing(outer.scaled(by: s), frame)
        let inner = refined.inner ?? coarseInner?.scaled(by: s)
        let homography = calibrate(outer: refined.outer, frame: frame, components: components, step: step)
        return RawDetection(outer: refined.outer, inner: inner, boardToImage: homography)
    }

    /// Re-measures the double ring's edges at full resolution along rays from the coarse ellipse's center.
    private func refineRing(_ coarse: Ellipse, _ frame: Frame) -> (outer: Ellipse, inner: Ellipse?) {
        var outerPoints: [(x: Double, y: Double)] = []
        var innerPoints: [(x: Double, y: Double)] = []
        let rays = 180
        for k in 0..<rays {
            let phi = Double(k) / Double(rays) * 2 * .pi
            let dx = cos(phi), dy = sin(phi)
            // `radial` is linear along a ray from the center, so this is the distance to the coarse edge.
            let edge = 1 / coarse.radial(coarse.cx + dx, coarse.cy + dy)
            var first: Double?
            var last: Double?
            var s = edge * 0.88
            while s <= edge * 1.08 {
                if frame.label((coarse.cx + s * dx, coarse.cy + s * dy)) != 0 {
                    if first == nil { first = s }
                    last = s
                }
                s += 0.5
            }
            guard let first, let last, last - first >= 1 else { continue }
            outerPoints.append((coarse.cx + (last + 0.25) * dx, coarse.cy + (last + 0.25) * dy))
            innerPoints.append((coarse.cx + (first - 0.25) * dx, coarse.cy + (first - 0.25) * dy))
        }

        guard let outerFit = EllipseFit.ransac(outerPoints, threshold: 2), outerFit.inlierRatio >= 0.6 else {
            log("refine: kept coarse ellipse")
            return (coarse, nil)
        }
        let outer = outerFit.ellipse
        var inner: Ellipse?
        if let innerFit = EllipseFit.ransac(innerPoints, threshold: 2), innerFit.inlierRatio >= 0.5,
           (0.88..<1).contains(innerFit.ellipse.a / outer.a) {
            inner = innerFit.ellipse
        }
        log(String(format: "refined a=%.1f (coarse %.1f) inliers=%.2f inner=%@",
                   outer.a, coarse.a, outerFit.inlierRatio, inner.map { String(format: "%.3f", $0.a / outer.a) } ?? "none"))
        return (outer, inner)
    }

    /// Finds the 20 segment wires along the double ring, works out which segment is 20,
    /// and fits the board → image homography (refined with the bull when it is visible).
    private func calibrate(outer: Ellipse, frame: Frame, components: [Component], step: Int) -> Homography? {
        let n = 1440
        var sequence = [UInt8](repeating: 0, count: n)
        for k in 0..<n {
            let t = Double(k) / Double(n) * 2 * .pi
            var redVotes = 0, greenVotes = 0
            for scale in [0.965, 0.975, 0.985] {
                switch frame.label(outer.point(at: t, scale: scale)) {
                case Self.red: redVotes += 1
                case Self.green: greenVotes += 1
                default: break
                }
            }
            if redVotes + greenVotes >= 2 { sequence[k] = redVotes >= greenVotes ? Self.red : Self.green }
        }

        let runs = colorRuns(sequence)
        guard runs.count == 20 else {
            log("✗ calibration: \(runs.count) color runs (want 20)")
            return nil
        }

        func ringPoint(_ index: Double, scale: Double) -> (x: Double, y: Double) {
            outer.point(at: index / Double(n) * 2 * .pi, scale: scale)
        }

        // Segment 20 is the red run pointing most upward in the image (assumes a normally hung board).
        var top = -1
        var bestUp = -Double.infinity
        for (i, run) in runs.enumerated() where run.label == Self.red {
            let p = ringPoint(Double(run.from + run.to) / 2, scale: 1)
            let up = -(p.y - outer.cy) / hypot(p.x - outer.cx, p.y - outer.cy)
            if up > bestUp {
                bestUp = up
                top = i
            }
        }
        guard top >= 0 else { return nil }

        // Each wire is the middle of the gap between two runs; sample it at the ring's outer, middle and inner radius.
        // Increasing ellipse parameter runs clockwise on screen, matching the board's clockwise numbering.
        let ringSamples: [(radius: Double, scale: Double)] = [
            (BoardGeometry.doubleOuter, 1),
            ((BoardGeometry.doubleOuter + BoardGeometry.doubleInner) / 2, 0.976),
            (BoardGeometry.doubleInner, BoardGeometry.doubleInner / BoardGeometry.doubleOuter),
        ]
        var boardPoints: [(x: Double, y: Double)] = []
        var imagePoints: [(x: Double, y: Double)] = []
        for k in 0..<20 {
            let a = runs[(top + k) % 20], b = runs[(top + k + 1) % 20]
            var next = b.from
            while next < a.to { next += n }
            let wire = Double(a.to + next) / 2
            let angle = BoardGeometry.boundaryAngle(after: k)
            for sample in ringSamples {
                boardPoints.append(BoardGeometry.point(radius: sample.radius, degrees: angle))
                imagePoints.append(ringPoint(wire, scale: sample.scale))
            }
        }

        guard var homography = Homography.fit(from: boardPoints, to: imagePoints) else {
            log("✗ calibration: homography fit failed")
            return nil
        }

        // The ellipse center is not the board center under perspective; the bull pins it down.
        if let predicted = homography.apply(0, 0),
           let bull = findBull(near: predicted, components, step: step, ringRadius: outer.a) {
            for _ in 0..<6 {
                boardPoints.append((0, 0))
                imagePoints.append(bull)
            }
            homography = Homography.fit(from: boardPoints, to: imagePoints) ?? homography
            log(String(format: "bull at (%.0f,%.0f), %.1f px from prediction",
                       bull.x, bull.y, hypot(bull.x - predicted.x, bull.y - predicted.y)))
        } else {
            log("bull not found")
        }

        let errors = zip(boardPoints, imagePoints).compactMap { board, image in
            homography.apply(board.x, board.y).map { hypot($0.x - image.x, $0.y - image.y) }
        }
        let meanError = errors.reduce(0, +) / Double(max(1, errors.count))
        log(String(format: "calibrated: top run %d, reprojection %.1f px", top, meanError))
        guard meanError < 0.03 * outer.a else {
            log("✗ calibration: reprojection error too high")
            return nil
        }
        return homography
    }

    /// The bull is a small mixed red/green blob close to where the homography puts the board center.
    private func findBull(near p: (x: Double, y: Double), _ components: [Component], step: Int, ringRadius: Double) -> (x: Double, y: Double)? {
        let s = Double(step)
        var best: (x: Double, y: Double)?
        var bestDistance = 0.15 * ringRadius
        for c in components where c.green > 0 && c.red + c.green >= 4 {
            let colored = Double(c.red + c.green)
            let x = (Double(c.sumX) / colored + 0.5) * s
            let y = (Double(c.sumY) / colored + 0.5) * s
            // Outer bull diameter is about 0.19 × the double ring radius.
            let size = Double(max(c.maxX - c.minX, c.maxY - c.minY) + 1) * s
            guard size < 0.3 * ringRadius else { continue }
            let d = hypot(x - p.x, y - p.y)
            if d < bestDistance {
                bestDistance = d
                best = (x, y)
            }
        }
        return best
    }

    /// Downsamples the BGRA frame and classifies each sample as red, green or neither. Returns the step used.
    private func buildLabels(_ frame: Frame) -> Int {
        let step = max(1, frame.width / targetWidth)
        let w = frame.width / step, h = frame.height / step

        if w != width || h != height {
            width = w
            height = h
            labels = [UInt8](repeating: 0, count: w * h)
            mask = labels
            temp = labels
            componentIDs = [Int32](repeating: -1, count: w * h)
            preview = [UInt8](repeating: 255, count: w * h * 4)
        }

        let src = frame.base
        let rowBytes = frame.rowBytes
        labels.withUnsafeMutableBufferPointer { out in
            preview.withUnsafeMutableBufferPointer { pre in
                for y in 0..<h {
                    let row = src + y * step * rowBytes
                    for x in 0..<w {
                        let p = row + x * step * 4
                        let label = Self.classify(r: p[2], g: p[1], b: p[0])
                        let i = y * w + x
                        out[i] = label
                        switch label {
                        case Self.red: (pre[i * 4], pre[i * 4 + 1], pre[i * 4 + 2]) = (255, 40, 40)
                        case Self.green: (pre[i * 4], pre[i * 4 + 1], pre[i * 4 + 2]) = (40, 255, 40)
                        default:
                            let gray = UInt8((Int(p[0]) + Int(p[1]) + Int(p[2])) / 6)
                            (pre[i * 4], pre[i * 4 + 1], pre[i * 4 + 2]) = (gray, gray, gray)
                        }
                    }
                }
            }
        }

        // HSV at the frame center, to check how the camera sees the colors.
        let center = src + (frame.height / 2) * rowBytes + (frame.width / 2) * 4
        let hsv = Self.hsv(r: center[2], g: center[1], b: center[0])
        log(String(format: "center h=%.0f s=%.2f v=%.2f → %@", hsv.h, hsv.s, hsv.v,
                   ["none", "RED", "GREEN"][Int(Self.classify(r: center[2], g: center[1], b: center[0]))]))
        return step
    }

    private static func hsv(r: UInt8, g: UInt8, b: UInt8) -> (h: Double, s: Double, v: Double) {
        let r = Int(r), g = Int(g), b = Int(b)
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        guard maxC > 0, delta > 0 else { return (0, 0, Double(maxC) / 255) }

        var hue: Double
        if maxC == r {
            hue = 60 * Double(g - b) / Double(delta)
            if hue < 0 { hue += 360 }
        } else if maxC == g {
            hue = 60 * (Double(b - r) / Double(delta) + 2)
        } else {
            hue = 60 * (Double(r - g) / Double(delta) + 4)
        }
        return (hue, Double(delta) / Double(maxC), Double(maxC) / 255)
    }

    private static func classify(r: UInt8, g: UInt8, b: UInt8) -> UInt8 {
        let (hue, saturation, value) = hsv(r: r, g: g, b: b)
        guard value >= 0.2 else { return 0 }
        if (hue < 15 || hue > 335) && saturation > 0.4 { return red }
        if hue >= 80 && hue <= 175 && saturation > 0.3 { return green }
        return 0
    }

    /// 3×3 dilation of the colored pixels so adjacent ring segments join into one component.
    private func buildDilatedMask() {
        let w = width, h = height
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let l = x > 0 ? labels[i - 1] : 0
                let r = x < w - 1 ? labels[i + 1] : 0
                temp[i] = (labels[i] | l | r) != 0 ? 1 : 0
            }
        }
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let u = y > 0 ? temp[i - w] : 0
                let d = y < h - 1 ? temp[i + w] : 0
                mask[i] = (temp[i] | u | d) != 0 ? 1 : 0
            }
        }
    }

    /// 4-connected components of the dilated mask, with stats over the original colored pixels.
    private func labelComponents() -> [Component] {
        let w = width, h = height
        for i in componentIDs.indices { componentIDs[i] = -1 }

        var components: [Component] = []
        for start in 0..<(w * h) where mask[start] != 0 && componentIDs[start] < 0 {
            let id = Int32(components.count)
            var c = Component()
            stack.removeAll(keepingCapacity: true)
            stack.append(Int32(start))
            componentIDs[start] = id

            while let top = stack.popLast() {
                let i = Int(top), x = i % w, y = i / w
                let label = labels[i]
                if label != 0 {
                    if label == Self.red { c.red += 1 } else { c.green += 1 }
                    c.sumX += x
                    c.sumY += y
                    c.minX = min(c.minX, x); c.maxX = max(c.maxX, x)
                    c.minY = min(c.minY, y); c.maxY = max(c.maxY, y)
                }
                if x > 0 { visit(i - 1, id) }
                if x < w - 1 { visit(i + 1, id) }
                if y > 0 { visit(i - w, id) }
                if y < h - 1 { visit(i + w, id) }
            }
            components.append(c)
        }
        return components
    }

    private func visit(_ i: Int, _ id: Int32) {
        if mask[i] != 0 && componentIDs[i] < 0 {
            componentIDs[i] = id
            stack.append(Int32(i))
        }
    }

    /// Picks the largest thin, mixed red/green component. A plain red surround has no green,
    /// and a solid red/green object is too dense to be a ring.
    private func selectRing(_ components: [Component]) -> Int32? {
        let minSpan = Int(Double(width) * 0.15)
        var best: Int32?
        var bestArea = 0
        var notes: [(size: Int, text: String)] = []

        for (index, c) in components.enumerated() {
            let colored = c.red + c.green
            let greenFraction = colored > 0 ? Double(c.green) / Double(colored) : 0
            let boxW = colored > 0 ? c.maxX - c.minX + 1 : 0
            let boxH = colored > 0 ? c.maxY - c.minY + 1 : 0
            let area = max(1, boxW * boxH)
            let density = Double(colored) / Double(area)

            var reason: String?
            if colored < 60 { reason = "tiny" }
            else if greenFraction < 0.2 || greenFraction > 0.8 { reason = "not mixed" }
            else if min(boxW, boxH) < minSpan { reason = "small box" }
            else if density >= 0.3 { reason = "too dense" }

            if colored >= 60 {
                notes.append((colored, String(format: "blob px=%d g%%=%.0f box=%dx%d dens=%.2f %@",
                                              colored, greenFraction * 100, boxW, boxH, density, reason ?? "OK")))
            }
            if reason == nil, area > bestArea {
                bestArea = area
                best = Int32(index)
            }
        }

        log("blobs: \(components.count) total, \(notes.count) with ≥60 px")
        for note in notes.sorted(by: { $0.size > $1.size }).prefix(4) { log(note.text) }
        return best
    }

    /// For each angular bin around the ring's centroid: the furthest pixel (outer edge) and nearest pixel (inner edge).
    private func edgePoints(of ring: Component, id: Int32) -> (outer: [(x: Double, y: Double)], inner: [(x: Double, y: Double)]) {
        let w = width
        let colored = Double(ring.red + ring.green)
        let cx = Double(ring.sumX) / colored + 0.5
        let cy = Double(ring.sumY) / colored + 0.5

        var maxDist = [Double](repeating: -1, count: binCount)
        var minDist = [Double](repeating: .infinity, count: binCount)
        var maxPoint = [(x: Double, y: Double)](repeating: (0, 0), count: binCount)
        var minPoint = maxPoint

        for y in ring.minY...ring.maxY {
            for x in ring.minX...ring.maxX {
                let i = y * w + x
                guard componentIDs[i] == id, labels[i] != 0 else { continue }
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let dx = px - cx, dy = py - cy
                let d = dx * dx + dy * dy
                var bin = Int((atan2(dy, dx) + .pi) / (2 * .pi) * Double(binCount))
                if bin >= binCount { bin = 0 }
                if d > maxDist[bin] { maxDist[bin] = d; maxPoint[bin] = (px, py) }
                if d < minDist[bin] { minDist[bin] = d; minPoint[bin] = (px, py) }
            }
        }

        var outer: [(x: Double, y: Double)] = []
        var inner: [(x: Double, y: Double)] = []
        for bin in 0..<binCount where maxDist[bin] >= 0 {
            outer.append(maxPoint[bin])
            inner.append(minPoint[bin])
        }
        return (outer, inner)
    }

    /// Counts red↔green changes around the double ring. A real double ring has 20 (10 red + 10 green segments).
    /// At each angle every pixel across the ring band votes, since the ring can be only ~2 px thick in the grid.
    private func colorTransitions(along e: Ellipse) -> Int {
        let samples = 720
        let bandScales = stride(from: 0.88, through: 1.04, by: 0.02).map { $0 }
        var sequence: [UInt8] = []
        sequence.reserveCapacity(samples)
        for k in 0..<samples {
            let t = Double(k) / Double(samples) * 2 * .pi
            var redVotes = 0, greenVotes = 0
            for scale in bandScales {
                let p = e.point(at: t, scale: scale)
                let x = Int(p.x), y = Int(p.y)
                guard x >= 0, y >= 0, x < width, y < height else { continue }
                switch labels[y * width + x] {
                case Self.red: redVotes += 1
                case Self.green: greenVotes += 1
                default: break
                }
            }
            if redVotes + greenVotes > 0 {
                sequence.append(redVotes >= greenVotes ? Self.red : Self.green)
            }
        }
        guard !sequence.isEmpty else { return 0 }

        // Run-length encode, drop runs much shorter than a segment (720 / 20 = 36 samples), then merge neighbouring runs of the same color.
        var runs: [(label: UInt8, length: Int)] = []
        for label in sequence {
            if let last = runs.last, last.label == label {
                runs[runs.count - 1].length += 1
            } else {
                runs.append((label, 1))
            }
        }
        if runs.count > 1, runs.first!.label == runs.last!.label {
            runs[0].length += runs.removeLast().length
        }
        var colors: [UInt8] = []
        for run in runs where run.length >= samples / 80 {
            if colors.last != run.label { colors.append(run.label) }
        }
        if colors.count > 1, colors.first == colors.last { colors.removeLast() }
        return colors.count > 1 ? colors.count : 0
    }

    /// Splits a circular label sequence (0 = no color) into single-color runs, bridging short gaps and dropping
    /// runs too short to be a segment. Indices may fall outside 0..<count when a run wraps around the start.
    private func colorRuns(_ sequence: [UInt8]) -> [(label: UInt8, from: Int, to: Int)] {
        let n = sequence.count
        let minLength = n / 80
        // Start where a run begins so no run straddles the end of the array.
        guard let start = (0..<n).first(where: { sequence[$0] != 0 && sequence[($0 + n - 1) % n] != sequence[$0] }) else {
            return []
        }

        var runs: [(label: UInt8, from: Int, to: Int)] = []
        for j in 0..<n {
            let label = sequence[(start + j) % n]
            guard label != 0 else { continue }
            if let last = runs.last, last.label == label, j - last.to <= minLength {
                runs[runs.count - 1].to = j
            } else {
                runs.append((label, j, j))
            }
        }

        var merged: [(label: UInt8, from: Int, to: Int)] = []
        for run in runs where run.to - run.from + 1 >= minLength {
            if let last = merged.last, last.label == run.label {
                merged[merged.count - 1].to = run.to
            } else {
                merged.append(run)
            }
        }
        if merged.count > 1, merged.first!.label == merged.last!.label {
            let last = merged.removeLast()
            merged[0].from = last.from - n
        }
        return merged.map { ($0.label, $0.from + start, $0.to + start) }
    }

    // MARK: - Debug image

    private func drawEllipse(_ e: Ellipse, r: UInt8, g: UInt8, b: UInt8) {
        for k in 0..<360 {
            let p = e.point(at: Double(k) / 360 * 2 * .pi)
            let x = Int(p.x), y = Int(p.y)
            guard x >= 0, y >= 0, x < width, y < height else { continue }
            let i = (y * width + x) * 4
            (preview[i], preview[i + 1], preview[i + 2]) = (r, g, b)
        }
    }

    private func makePreviewImage() -> CGImage? {
        guard width > 0, height > 0,
              let provider = CGDataProvider(data: Data(preview) as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    // MARK: - Temporal smoothing

    private func stabilize(_ raw: RawDetection?, imageSize: CGSize) -> DetectionResult {
        history.append(raw != nil)
        if history.count > historyLength { history.removeFirst() }
        let hits = history.filter { $0 }.count

        if let raw {
            smoothedOuter = blend(smoothedOuter, raw.outer)
            // `blend` returns the new ellipse unchanged when it restarts, so older state belongs elsewhere.
            let restarted = smoothedOuter == raw.outer
            if let inner = raw.inner {
                smoothedInner = blend(restarted ? nil : smoothedInner, inner)
            } else if restarted {
                smoothedInner = nil
            }
            if let h = raw.boardToImage {
                smoothedHomography = (restarted ? nil : smoothedHomography)?.blended(toward: h, alpha: 0.5) ?? h
            } else if restarted {
                smoothedHomography = nil
            }
        } else if hits == 0 {
            smoothedOuter = nil
            smoothedInner = nil
            smoothedHomography = nil
        }

        let found = hits >= requiredHits && smoothedOuter != nil
        log("hits \(hits)/\(history.count) → \(found ? "FOUND" : "searching")\(smoothedHomography != nil ? " + calibrated" : "")")
        return DetectionResult(
            imageSize: imageSize,
            outer: found ? smoothedOuter : nil,
            inner: found ? smoothedInner : nil,
            boardToImage: found ? smoothedHomography : nil,
            found: found
        )
    }

    /// Exponential moving average; jumps straight to the new ellipse if the board moved a lot.
    private func blend(_ old: Ellipse?, _ new: Ellipse) -> Ellipse {
        guard let old, hypot(new.cx - old.cx, new.cy - old.cy) < 0.25 * new.a else { return new }
        let alpha = 0.5
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * alpha }

        // Ellipse orientation is π-periodic.
        var dAngle = new.angle - old.angle
        while dAngle > .pi / 2 { dAngle -= .pi }
        while dAngle < -.pi / 2 { dAngle += .pi }

        return Ellipse(
            cx: mix(old.cx, new.cx),
            cy: mix(old.cy, new.cy),
            a: mix(old.a, new.a),
            b: mix(old.b, new.b),
            angle: old.angle + dAngle * alpha
        )
    }
}
