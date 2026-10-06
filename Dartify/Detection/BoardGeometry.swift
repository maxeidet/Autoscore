//
//  BoardGeometry.swift
//  Dartify
//

import Foundation

/// A projective transform between two planes, stored row-major with m[8] normalised to 1.
nonisolated struct Homography: Sendable, Equatable {
    var m: [Double]

    func apply(_ x: Double, _ y: Double) -> (x: Double, y: Double)? {
        let w = m[6] * x + m[7] * y + m[8]
        guard abs(w) > 1e-12 else { return nil }
        return ((m[0] * x + m[1] * y + m[2]) / w, (m[3] * x + m[4] * y + m[5]) / w)
    }

    var inverse: Homography? {
        let a = m
        let c00 = a[4] * a[8] - a[5] * a[7]
        let c01 = a[5] * a[6] - a[3] * a[8]
        let c02 = a[3] * a[7] - a[4] * a[6]
        let det = a[0] * c00 + a[1] * c01 + a[2] * c02
        guard abs(det) > 1e-12 else { return nil }
        let inv = [
            c00, a[2] * a[7] - a[1] * a[8], a[1] * a[5] - a[2] * a[4],
            c01, a[0] * a[8] - a[2] * a[6], a[2] * a[3] - a[0] * a[5],
            c02, a[1] * a[6] - a[0] * a[7], a[0] * a[4] - a[1] * a[3],
        ].map { $0 / det }
        return Homography(normalizing: inv)
    }

    init?(normalizing m: [Double]) {
        guard m.count == 9, abs(m[8]) > 1e-12 else { return nil }
        self.m = m.map { $0 / m[8] }
    }

    /// Least-squares fit (h33 = 1) mapping `from` points onto `to` points, with Hartley-style normalisation.
    static func fit(from: [(x: Double, y: Double)], to: [(x: Double, y: Double)]) -> Homography? {
        guard from.count == to.count, from.count >= 4,
              let tFrom = normalization(from), let tTo = normalization(to)
        else { return nil }

        var ata = [Double](repeating: 0, count: 64)
        var atb = [Double](repeating: 0, count: 8)
        for (p, q) in zip(from, to) {
            let (x, y) = (tFrom.scale * (p.x - tFrom.mx), tFrom.scale * (p.y - tFrom.my))
            let (u, v) = (tTo.scale * (q.x - tTo.mx), tTo.scale * (q.y - tTo.my))
            for (row, rhs) in [([x, y, 1, 0, 0, 0, -x * u, -y * u], u), ([0, 0, 0, x, y, 1, -x * v, -y * v], v)] {
                for i in 0..<8 {
                    atb[i] += row[i] * rhs
                    for j in 0..<8 { ata[i * 8 + j] += row[i] * row[j] }
                }
            }
        }
        guard let h = LinearSolver.solve(&ata, &atb, n: 8) else { return nil }

        // Undo the normalisation: H = T_to⁻¹ · Hn · T_from.
        let hn = h + [1]
        let s1 = tFrom.scale, s2 = tTo.scale
        let tf = [s1, 0, -s1 * tFrom.mx, 0, s1, -s1 * tFrom.my, 0, 0, 1]
        let ttInv = [1 / s2, 0, tTo.mx, 0, 1 / s2, tTo.my, 0, 0, 1]
        return Homography(normalizing: multiply(ttInv, multiply(hn, tf)))
    }

    /// Element-wise blend of two normalised homographies (fine for small frame-to-frame changes).
    func blended(toward other: Homography, alpha: Double) -> Homography {
        Homography(normalizing: zip(m, other.m).map { $0 + ($1 - $0) * alpha }) ?? other
    }

    private static func normalization(_ pts: [(x: Double, y: Double)]) -> (mx: Double, my: Double, scale: Double)? {
        let n = Double(pts.count)
        let mx = pts.reduce(0) { $0 + $1.x } / n
        let my = pts.reduce(0) { $0 + $1.y } / n
        let meanDist = pts.reduce(0) { $0 + hypot($1.x - mx, $1.y - my) } / n
        guard meanDist > 1e-9 else { return nil }
        return (mx, my, sqrt(2) / meanDist)
    }

    private static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        var r = [Double](repeating: 0, count: 9)
        for i in 0..<3 {
            for j in 0..<3 {
                var sum = 0.0
                for k in 0..<3 { sum += a[i * 3 + k] * b[k * 3 + j] }
                r[i * 3 + j] = sum
            }
        }
        return r
    }
}

nonisolated enum LinearSolver {
    /// Gaussian elimination with partial pivoting on a row-major n×n system.
    static func solve(_ m: inout [Double], _ v: inout [Double], n: Int) -> [Double]? {
        for col in 0..<n {
            var pivot = col
            for r in (col + 1)..<n where abs(m[r * n + col]) > abs(m[pivot * n + col]) {
                pivot = r
            }
            guard abs(m[pivot * n + col]) > 1e-12 else { return nil }
            if pivot != col {
                for c in 0..<n { m.swapAt(pivot * n + c, col * n + c) }
                v.swapAt(pivot, col)
            }
            for r in (col + 1)..<n {
                let f = m[r * n + col] / m[col * n + col]
                for c in col..<n { m[r * n + c] -= f * m[col * n + c] }
                v[r] -= f * v[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = v[r]
            for c in (r + 1)..<n { s -= m[r * n + c] * x[c] }
            x[r] = s / m[r * n + r]
        }
        return x
    }
}

nonisolated struct BoardScore: Sendable, Equatable, Codable {
    enum Ring: Sendable, Codable { case miss, single, double, treble, outerBull, bull }

    var ring: Ring
    /// Segment number 1–20; 0 for bulls and misses.
    var number: Int

    var points: Int {
        switch ring {
        case .miss: 0
        case .single: number
        case .double: 2 * number
        case .treble: 3 * number
        case .outerBull: 25
        case .bull: 50
        }
    }

    var label: String {
        switch ring {
        case .miss: "MISS"
        case .single: "S\(number)"
        case .double: "D\(number)"
        case .treble: "T\(number)"
        case .outerBull: "25"
        case .bull: "BULL"
        }
    }

    /// How a caller would announce the dart.
    var spoken: String {
        switch ring {
        case .miss: "Miss"
        case .single: "\(number)"
        case .double: "Double \(number)"
        case .treble: "Treble \(number)"
        case .outerBull: "Twenty five"
        case .bull: "Bullseye"
        }
    }
}

/// Standard dartboard layout in millimetres. Board coordinates: origin at the bull, x right, y up.
nonisolated enum BoardGeometry {
    /// Segment numbers clockwise starting from the top.
    static let order = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

    static let bullRadius = 6.35
    static let outerBullRadius = 15.9
    static let trebleInner = 99.0
    static let trebleOuter = 107.0
    static let doubleInner = 162.0
    static let doubleOuter = 170.0

    static let ringRadii = [bullRadius, outerBullRadius, trebleInner, trebleOuter, doubleInner, doubleOuter]

    /// Angle in degrees (counter-clockwise from +x) of the wire on the clockwise side of segment `index`.
    static func boundaryAngle(after index: Int) -> Double {
        81 - 18 * Double(index)
    }

    /// Angle in degrees of the centre of segment `index`.
    static func segmentAngle(_ index: Int) -> Double {
        90 - 18 * Double(index)
    }

    static func point(radius: Double, degrees: Double) -> (x: Double, y: Double) {
        let r = degrees * .pi / 180
        return (radius * cos(r), radius * sin(r))
    }

    static func score(x: Double, y: Double) -> BoardScore {
        let r = hypot(x, y)
        if r <= bullRadius { return BoardScore(ring: .bull, number: 0) }
        if r <= outerBullRadius { return BoardScore(ring: .outerBull, number: 0) }
        if r > doubleOuter { return BoardScore(ring: .miss, number: 0) }

        let degrees = atan2(y, x) * 180 / .pi
        var fromTop = (99 - degrees).truncatingRemainder(dividingBy: 360)
        if fromTop < 0 { fromTop += 360 }
        let number = order[min(19, Int(fromTop / 18))]

        let ring: BoardScore.Ring
        if r >= doubleInner { ring = .double }
        else if r >= trebleInner && r <= trebleOuter { ring = .treble }
        else { ring = .single }
        return BoardScore(ring: ring, number: number)
    }
}
