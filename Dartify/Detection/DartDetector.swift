//
//  DartDetector.swift
//  Dartify
//

import CoreGraphics
import CoreVideo
import Foundation

nonisolated struct DetectedDart: Sendable, Equatable {
    /// Tip position in board millimetres (origin at the bull, y up); NaN for darts entered by hand.
    var x: Double
    var y: Double
    var score: BoardScore

    var hasPosition: Bool { x.isFinite && y.isFinite }
}

nonisolated enum DartEvent: Sendable, Equatable {
    case dart(DetectedDart)
    /// The darts were pulled out of the board.
    case cleared
    /// The whole board changed, so the camera has probably moved and the calibration needs checking.
    case cameraMoved
}

nonisolated struct DartState: Sendable {
    var status = "Starting…"
    /// Something that happened on this frame, delivered once.
    var event: DartEvent?
    var debug = DetectionDebug()
}

/// Watches a calibrated, locked board for darts landing.
///
/// Every frame is warped to a top-down view of the board (1 mm per pixel, ±250 mm so flights sticking out past the board are included) and compared with a reference view
/// taken before the throw. Once the scene is still again, a dart-sized change is a new dart. Seen through the
/// board-plane homography, anything sticking out of the board smears away from the camera, so the tip is the
/// end of the change nearest the camera's position over the board.
nonisolated final class DartDetector {
    private let size = 500
    private let halfSize = 250.0

    // Tuning knobs.
    /// Summed |ΔR|+|ΔG|+|ΔB| above which a pixel counts as clearly changed.
    private let pixelThreshold = 75
    /// Fainter changes (e.g. a steel barrel over a black segment) count when they connect to a clear change.
    private let weakPixelThreshold = 35
    /// Gaps up to this many pixels between changed pieces are bridged when grouping them into blobs.
    private let bridgeRadius = 2
    /// Motion is measured on 5×5 mm blocks, which averages away pixel noise and sub-pixel camera wobble.
    private let blockSize = 5
    /// Mean |Δ(R+G+B)| per pixel, after correcting overall brightness, above which a block counts as moving.
    private let blockThreshold = 30.0
    /// Moving blocks allowed in a still scene; raised automatically when the scene is noisy (flicker, wobble).
    private let minMotionBlocks = 6
    private let maxMotionLimit = 400
    /// Still frames required before a change is evaluated.
    private let stableFramesNeeded = 3
    /// Changed area (mm²) for a dart; more than `maxDartPixels` means darts were pulled or someone is in the way.
    private let minDartPixels = 40
    private let maxDartPixels = 8000
    /// Blobs with fewer clearly changed pixels than this are noise.
    private let minBlobPixels = 8
    private let dartsPerTurn = 3

    private let boardToImage: Homography
    /// Camera position projected onto the board plane, in board millimetres.
    private let cameraFoot: (x: Double, y: Double)?

    private var lookup: [Int32] = []
    private var lookupKey: [Int] = []
    private var current: [UInt8]
    /// Block brightness sums of the previous frame, for motion detection.
    private var previous: [Int]?
    private var blockPixels: [Int] = []
    private var moving: [Bool] = []
    private var motionHistory: [Int] = []
    private var reference: [UInt8]?
    private var changed: [UInt8]
    private var bridged: [UInt8]
    private var componentIDs: [Int32]
    private var stack: [Int32] = []

    private var stableFrames = 0
    /// Darts in the board this turn; decides when a change means the darts were pulled.
    private(set) var darts: [DetectedDart]
    /// The visit ended early (bust or checkout), so the next change means the darts were pulled.
    private(set) var turnComplete: Bool
    private var turnOver: Bool { turnComplete || darts.count >= dartsPerTurn }
    private var event: DartEvent?
    /// Set after a camera check found the board where it was, so a lasting whole-board change is lighting.
    private var cameraConfirmed = false
    private var status = "Hold still…"
    private var lastTip: (x: Double, y: Double)?
    private var debugLines: [String] = []

    init(boardToImage: Homography, focalLength: Double, imageSize: CGSize, darts: [DetectedDart] = [], turnComplete: Bool = false) {
        self.boardToImage = boardToImage
        self.darts = darts
        self.turnComplete = turnComplete
        current = [UInt8](repeating: 0, count: size * size * 3)
        changed = [UInt8](repeating: 0, count: size * size)
        bridged = changed
        componentIDs = [Int32](repeating: -1, count: size * size)

        let pose = Self.cameraPose(boardToImage, focalLength: focalLength, imageSize: imageSize)
        cameraFoot = pose?.foot
        if let pose {
            print(String(format: "[Dartify] camera over board at (%.0f, %.0f) mm, %.0f mm from the board",
                         pose.foot.x, pose.foot.y, pose.distance))
        }
    }

    func nextTurn() {
        darts.removeAll()
        turnComplete = false
        reference = nil
        lastTip = nil
        status = "New turn"
    }

    /// Replaces the turn's darts (after a correction) and whether the visit is over.
    func setDarts(_ darts: [DetectedDart], turnComplete: Bool) {
        self.darts = darts
        self.turnComplete = turnComplete
    }

    /// Resumes after the camera check confirmed the board hasn't moved. The reference is kept, so darts
    /// pulled while someone stood in front of the board are still noticed.
    func resumeAfterCameraCheck() {
        previous = nil
        stableFrames = 0
        cameraConfirmed = true
    }

    func process(_ pixelBuffer: CVPixelBuffer) -> DartState {
        debugLines.removeAll()
        event = nil
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return DartState(status: "Unsupported pixel format")
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            rectify(
                base.assumingMemoryBound(to: UInt8.self),
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer),
                rowBytes: CVPixelBufferGetBytesPerRow(pixelBuffer)
            )
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        update()

        if let foot = cameraFoot { log(String(format: "camera foot (%.0f, %.0f) mm", foot.x, foot.y)) }
        log("darts: " + (darts.isEmpty ? "–" : darts.map(\.score.label).joined(separator: " ")))
        return DartState(status: status, event: event, debug: DetectionDebug(lines: debugLines, mask: makeDebugImage()))
    }

    private func log(_ line: String) {
        debugLines.append(line)
    }

    // MARK: - Throw state machine

    private func update() {
        let blocks = blockSums()
        guard let previous else {
            previous = blocks
            stableFrames = 0
            return
        }
        guard let reference else {
            reference = current
            self.previous = blocks
            stableFrames = 0
            status = "Ready – throw!"
            return
        }

        let motion = blockMotion(blocks, previous)
        self.previous = blocks
        // The limit follows the scene's background level (a low percentile of recent motion), so constant
        // flicker or a slightly wobbly mount doesn't look like movement forever.
        motionHistory.append(motion)
        if motionHistory.count > 45 { motionHistory.removeFirst() }
        let backgroundLevel = motionHistory.sorted()[motionHistory.count / 4]
        let limit = min(maxMotionLimit, max(minMotionBlocks, 2 * backgroundLevel + 4))
        log("motion \(motion) blocks (limit \(limit))")
        guard motion <= limit else {
            stableFrames = 0
            status = "Movement… (\(motion) > \(limit))"
            return
        }
        stableFrames += 1
        guard stableFrames >= stableFramesNeeded else { return }

        let changedPixels = buildChangeMask(current, reference)
        log("changed vs reference \(changedPixels) px")

        if changedPixels < minDartPixels {
            // Nothing new. Refresh the reference so slow lighting drift never adds up to a fake dart.
            self.reference = current
            cameraConfirmed = false
            status = turnOver ? "Turn done – pull darts" : "Ready – throw!"
            return
        }

        if changedPixels > maxDartPixels && changeIsEverywhere() {
            if cameraConfirmed {
                // The board is where it was, so this is a lighting change: accept it as the new normal.
                log("✓ whole-board change after camera check: new reference")
                self.reference = current
                cameraConfirmed = false
            } else {
                log("✗ whole board changed – camera moved?")
                status = "Camera moved? Checking…"
                event = .cameraMoved
            }
            return
        }
        cameraConfirmed = false

        if turnOver || changedPixels > maxDartPixels {
            // Darts pulled out (or the scene changed a lot): start a new turn from this view.
            log("✓ reset: \(turnOver ? "darts pulled" : "large change")")
            self.reference = current
            darts.removeAll()
            turnComplete = false
            lastTip = nil
            status = "New turn – throw!"
            event = .cleared
            return
        }

        self.reference = current
        guard let tip = findTip() else {
            log("✗ no tip found")
            return
        }
        lastTip = tip
        let x = tip.x - halfSize, y = halfSize - tip.y
        let score = BoardGeometry.score(x: x, y: y)
        let dart = DetectedDart(x: x, y: y, score: score)
        darts.append(dart)
        event = .dart(dart)
        status = "Dart \(darts.count): \(score.label)"
        log(String(format: "✓ dart at (%.0f, %.0f) mm → %@", x, y, score.label))
    }

    /// True when changes cover most of the board (a moved camera or a lighting change), not just a few darts.
    private func changeIsEverywhere() -> Bool {
        let sectors = 16
        var counts = [Int](repeating: 0, count: sectors)
        for k in 0..<(size * size) where changed[k] != 0 {
            let x = Double(k % size) + 0.5 - halfSize, y = halfSize - (Double(k / size) + 0.5)
            guard hypot(x, y) <= BoardGeometry.doubleOuter else { continue }
            var angle = atan2(y, x)
            if angle < 0 { angle += 2 * .pi }
            counts[min(sectors - 1, Int(angle / (2 * .pi) * Double(sectors)))] += 1
        }
        let covered = counts.filter { $0 >= 20 }.count
        log("changed sectors \(covered)/\(sectors)")
        return covered >= 12
    }

    // MARK: - Rectification and differencing

    /// Warps the frame into `current`: a top-down RGB view, 1 mm per pixel, ±250 mm around the bull.
    private func rectify(_ base: UnsafeMutablePointer<UInt8>, width: Int, height: Int, rowBytes: Int) {
        if lookupKey != [width, height, rowBytes] {
            buildLookup(width: width, height: height, rowBytes: rowBytes)
        }
        lookup.withUnsafeBufferPointer { table in
            current.withUnsafeMutableBufferPointer { out in
                for k in 0..<(size * size) {
                    let offset = Int(table[k])
                    if offset < 0 {
                        (out[3 * k], out[3 * k + 1], out[3 * k + 2]) = (0, 0, 0)
                    } else {
                        let p = base + offset
                        (out[3 * k], out[3 * k + 1], out[3 * k + 2]) = (p[2], p[1], p[0])
                    }
                }
            }
        }
    }

    private func buildLookup(width: Int, height: Int, rowBytes: Int) {
        lookupKey = [width, height, rowBytes]
        lookup = [Int32](repeating: -1, count: size * size)
        for j in 0..<size {
            for i in 0..<size {
                let x = Double(i) + 0.5 - halfSize
                let y = halfSize - (Double(j) + 0.5)
                guard hypot(x, y) <= halfSize, let p = boardToImage.apply(x, y),
                      p.x >= 0, p.y >= 0, Int(p.x) < width, Int(p.y) < height
                else { continue }
                lookup[j * size + i] = Int32(Int(p.y) * rowBytes + Int(p.x) * 4)
            }
        }

        let blocksPerSide = size / blockSize
        blockPixels = [Int](repeating: 0, count: blocksPerSide * blocksPerSide)
        moving = [Bool](repeating: false, count: blockPixels.count)
        for k in 0..<(size * size) where lookup[k] >= 0 {
            blockPixels[(k / size / blockSize) * blocksPerSide + (k % size) / blockSize] += 1
        }
    }

    /// Sum of R+G+B over each 5×5 mm block of the current view.
    private func blockSums() -> [Int] {
        let blocksPerSide = size / blockSize
        var sums = [Int](repeating: 0, count: blocksPerSide * blocksPerSide)
        current.withUnsafeBufferPointer { cur in
            lookup.withUnsafeBufferPointer { table in
                sums.withUnsafeMutableBufferPointer { out in
                    for j in 0..<size {
                        let row = (j / blockSize) * blocksPerSide
                        for i in 0..<size {
                            let k = j * size + i
                            guard table[k] >= 0 else { continue }
                            out[row + i / blockSize] += Int(cur[3 * k]) + Int(cur[3 * k + 1]) + Int(cur[3 * k + 2])
                        }
                    }
                }
            }
        }
        return sums
    }

    /// Number of blocks whose brightness changed, after scaling out an overall brightness change (flicker).
    private func blockMotion(_ now: [Int], _ before: [Int]) -> Int {
        let total = now.reduce(0, +), totalBefore = before.reduce(0, +)
        let gain = totalBefore > 0 ? Double(total) / Double(totalBefore) : 1
        var count = 0
        for b in now.indices {
            guard blockPixels[b] > 0 else { moving[b] = false; continue }
            moving[b] = abs(Double(now[b]) - gain * Double(before[b])) / Double(blockPixels[b]) > blockThreshold
            if moving[b] { count += 1 }
        }
        return count
    }

    private func difference(_ a: UnsafeBufferPointer<UInt8>, _ b: UnsafeBufferPointer<UInt8>, _ k: Int) -> Int {
        abs(Int(a[3 * k]) - Int(b[3 * k]))
            + abs(Int(a[3 * k + 1]) - Int(b[3 * k + 1]))
            + abs(Int(a[3 * k + 2]) - Int(b[3 * k + 2]))
    }

    /// Fills `changed` with pixels that differ from the reference and returns how many there are.
    /// Hysteresis: blobs are grouped from clear and faint changes (bridging small gaps), and only blobs with
    /// at least `minBlobPixels` clearly changed pixels are kept.
    private func buildChangeMask(_ a: [UInt8], _ b: [UInt8]) -> Int {
        let strong: UInt8 = 2, weak: UInt8 = 1
        a.withUnsafeBufferPointer { a in
            b.withUnsafeBufferPointer { b in
                for k in 0..<(size * size) {
                    let d = difference(a, b, k)
                    changed[k] = d > pixelThreshold ? strong : d > weakPixelThreshold ? weak : 0
                }
            }
        }

        // Dilate (separable box) so nearby pieces of one dart group together.
        for y in 0..<size {
            for x in 0..<size {
                var any: UInt8 = 0
                for dx in -bridgeRadius...bridgeRadius where x + dx >= 0 && x + dx < size {
                    any |= changed[y * size + x + dx]
                }
                componentIDs[y * size + x] = any != 0 ? 1 : 0
            }
        }
        for y in 0..<size {
            for x in 0..<size {
                var any: Int32 = 0
                for dy in -bridgeRadius...bridgeRadius where y + dy >= 0 && y + dy < size {
                    any |= componentIDs[(y + dy) * size + x]
                }
                bridged[y * size + x] = any != 0 ? 1 : 0
            }
        }

        for k in componentIDs.indices { componentIDs[k] = -1 }
        var kept = 0
        var blob: [Int] = []
        for start in 0..<(size * size) where bridged[start] != 0 && componentIDs[start] < 0 {
            blob.removeAll(keepingCapacity: true)
            stack.removeAll(keepingCapacity: true)
            stack.append(Int32(start))
            componentIDs[start] = 0
            var strongCount = 0
            while let top = stack.popLast() {
                let k = Int(top)
                if changed[k] != 0 { blob.append(k) }
                if changed[k] == strong { strongCount += 1 }
                let x = k % size, y = k / size
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < size && ny < size {
                    let n = ny * size + nx
                    if bridged[n] != 0 && componentIDs[n] < 0 {
                        componentIDs[n] = 0
                        stack.append(Int32(n))
                    }
                }
            }
            let keep = strongCount >= minBlobPixels
            for k in blob { changed[k] = keep ? 1 : 0 }
            if keep { kept += blob.count }
        }
        return kept
    }

    // MARK: - Tip

    /// Finds the tip along the change's principal axis. An elongated dart is narrow at the tip and wide at
    /// the flight; when the ends look alike, the tip is the end nearest the camera's position over the board.
    private func findTip() -> (x: Double, y: Double)? {
        var points: [(x: Double, y: Double)] = []
        for k in 0..<(size * size) where changed[k] != 0 {
            points.append((Double(k % size) + 0.5, Double(k / size) + 0.5))
        }
        guard points.count >= minDartPixels else { return nil }

        let n = Double(points.count)
        let cx = points.reduce(0) { $0 + $1.x } / n
        let cy = points.reduce(0) { $0 + $1.y } / n
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in points {
            sxx += (p.x - cx) * (p.x - cx)
            syy += (p.y - cy) * (p.y - cy)
            sxy += (p.x - cx) * (p.y - cy)
        }
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        var axis = (x: cos(theta), y: sin(theta))

        // Rectified pixel coordinates have y pointing down.
        let foot = cameraFoot.map { (x: $0.x + halfSize, y: halfSize - $0.y) } ?? (x: halfSize, y: halfSize)
        if axis.x * (cx - foot.x) + axis.y * (cy - foot.y) < 0 {
            axis = (-axis.x, -axis.y)
        }

        var projections = points.map { ($0.x - cx) * axis.x + ($0.y - cy) * axis.y }
        var minProjection = projections.min() ?? 0
        var maxProjection = projections.max() ?? 0
        let length = maxProjection - minProjection

        // Compare the blob's width over the first and last quarter of its length.
        var tipBy = "camera"
        if length >= 25 {
            func width(from: Double, to: Double) -> Double {
                var lo = Double.infinity, hi = -Double.infinity
                for (p, s) in zip(points, projections) where s >= from && s <= to {
                    let across = -(p.x - cx) * axis.y + (p.y - cy) * axis.x
                    lo = min(lo, across)
                    hi = max(hi, across)
                }
                return hi >= lo ? hi - lo + 1 : 0
            }
            let near = width(from: minProjection, to: minProjection + length / 4)
            let far = width(from: maxProjection - length / 4, to: maxProjection)
            log(String(format: "end widths %.0f / %.0f mm", near, far))
            if near > 1.5 * far {
                // The wide end is nearest the camera, so the dart leans toward it: flip.
                axis = (-axis.x, -axis.y)
                projections = projections.map { -$0 }
                (minProjection, maxProjection) = (-maxProjection, -minProjection)
                tipBy = "width"
            } else if far > 1.5 * near {
                tipBy = "width"
            }
        }
        let tipPoints = zip(points, projections).filter { $0.1 <= minProjection + 2 }.map(\.0)
        let tx = tipPoints.reduce(0) { $0 + $1.x } / Double(tipPoints.count)
        let ty = tipPoints.reduce(0) { $0 + $1.y } / Double(tipPoints.count)

        let mean = (sxx + syy) / (2 * n)
        let spread = sqrt(((sxx - syy) / (2 * n)) * ((sxx - syy) / (2 * n)) + (sxy / n) * (sxy / n))
        let elongation = sqrt((mean + spread) / max(mean - spread, 1e-6))
        log(String(format: "blob %d px, length %.0f mm, elongation %.1f, tip by %@", points.count, length, elongation, tipBy))
        return (tx, ty)
    }

    // MARK: - Camera pose

    /// Recovers where the camera is relative to the board from the homography, assuming square pixels
    /// and the principal point at the image center.
    static func cameraPose(_ h: Homography, focalLength f: Double, imageSize: CGSize) -> (foot: (x: Double, y: Double), distance: Double)? {
        let px = Double(imageSize.width) / 2, py = Double(imageSize.height) / 2
        let m = h.m
        // Columns of K⁻¹·H are λ·[r1 r2 t].
        func column(_ c: Int) -> [Double] {
            [(m[c] - px * m[6 + c]) / f, (m[3 + c] - py * m[6 + c]) / f, m[6 + c]]
        }
        func norm(_ v: [Double]) -> Double { sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) }
        func dot(_ a: [Double], _ b: [Double]) -> Double { a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }

        let a1 = column(0), a2 = column(1), a3 = column(2)
        let n1 = norm(a1), n2 = norm(a2)
        guard n1 > 1e-12, n2 > 1e-12 else { return nil }
        var lambda = 2 / (n1 + n2)
        if a3[2] * lambda < 0 { lambda = -lambda }  // the board is in front of the camera

        let r1 = a1.map { $0 * lambda }, r2 = a2.map { $0 * lambda }, t = a3.map { $0 * lambda }
        let r3 = [r1[1] * r2[2] - r1[2] * r2[1], r1[2] * r2[0] - r1[0] * r2[2], r1[0] * r2[1] - r1[1] * r2[0]]
        // Camera center in board coordinates: C = −Rᵀt.
        return ((-dot(r1, t), -dot(r2, t)), abs(dot(r3, t)))
    }

    // MARK: - Debug image

    /// Top-down board view: changed pixels in red, moving blocks tinted blue, double/treble rings in green,
    /// last tip as a yellow cross.
    private func makeDebugImage() -> CGImage? {
        var rgba = [UInt8](repeating: 255, count: size * size * 4)
        let blocksPerSide = size / blockSize
        for k in 0..<(size * size) {
            let block = (k / size / blockSize) * blocksPerSide + (k % size) / blockSize
            if changed[k] != 0 {
                (rgba[4 * k], rgba[4 * k + 1], rgba[4 * k + 2]) = (255, 0, 0)
            } else if block < moving.count && moving[block] {
                (rgba[4 * k], rgba[4 * k + 1], rgba[4 * k + 2]) = (current[3 * k] / 3, current[3 * k + 1] / 3, 200)
            } else {
                (rgba[4 * k], rgba[4 * k + 1], rgba[4 * k + 2]) = (current[3 * k] / 2, current[3 * k + 1] / 2, current[3 * k + 2] / 2)
            }
        }
        func put(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8)) {
            guard x >= 0, y >= 0, x < size, y < size else { return }
            let k = (y * size + x) * 4
            (rgba[k], rgba[k + 1], rgba[k + 2]) = c
        }
        for radius in [BoardGeometry.trebleInner, BoardGeometry.trebleOuter, BoardGeometry.doubleInner, BoardGeometry.doubleOuter] {
            for step in 0..<720 {
                let a = Double(step) / 720 * 2 * .pi
                put(Int(halfSize + radius * cos(a)), Int(halfSize + radius * sin(a)), (0, 255, 0))
            }
        }
        for dart in darts where dart.hasPosition {
            let x = Int(dart.x + halfSize), y = Int(halfSize - dart.y)
            for d in -3...3 { put(x + d, y, (255, 0, 255)); put(x, y + d, (255, 0, 255)) }
        }
        if let tip = lastTip {
            for d in -6...6 { put(Int(tip.x) + d, Int(tip.y), (255, 255, 0)); put(Int(tip.x), Int(tip.y) + d, (255, 255, 0)) }
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: size, height: size,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
