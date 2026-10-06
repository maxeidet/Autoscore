//
//  EllipseFit.swift
//  Dartify
//

import Foundation

/// An ellipse in image pixel coordinates (y pointing down).
/// `a` is the semi-major axis, `b` the semi-minor axis, `angle` the direction of the major axis in radians.
nonisolated struct Ellipse: Sendable, Equatable {
    var cx: Double
    var cy: Double
    var a: Double
    var b: Double
    var angle: Double

    func point(at t: Double, scale: Double = 1) -> (x: Double, y: Double) {
        let c = cos(angle), s = sin(angle)
        let u = a * scale * cos(t), v = b * scale * sin(t)
        return (cx + u * c - v * s, cy + u * s + v * c)
    }

    /// 1 on the ellipse, < 1 inside, > 1 outside.
    func radial(_ x: Double, _ y: Double) -> Double {
        let dx = x - cx, dy = y - cy
        let c = cos(angle), s = sin(angle)
        let u = dx * c + dy * s, v = -dx * s + dy * c
        return sqrt(u * u / (a * a) + v * v / (b * b))
    }

    /// Distance to the ellipse measured along the ray from the center (good approximation near the curve).
    func distance(_ x: Double, _ y: Double) -> Double {
        let r = radial(x, y)
        guard r > 1e-9 else { return .infinity }
        return hypot(x - cx, y - cy) * abs(1 - 1 / r)
    }

    func scaled(by s: Double) -> Ellipse {
        Ellipse(cx: cx * s, cy: cy * s, a: a * s, b: b * s, angle: angle)
    }
}

nonisolated enum EllipseFit {
    /// Algebraic least-squares fit of `Ax² + Bxy + Cy² + Dx + Ey = 1` on normalized points.
    static func fit(_ points: [(x: Double, y: Double)]) -> Ellipse? {
        guard points.count >= 5 else { return nil }

        let n = Double(points.count)
        let mx = points.reduce(0) { $0 + $1.x } / n
        let my = points.reduce(0) { $0 + $1.y } / n
        let rms = sqrt(points.reduce(0) { $0 + ($1.x - mx) * ($1.x - mx) + ($1.y - my) * ($1.y - my) } / n)
        guard rms > 1e-9 else { return nil }

        var m = [Double](repeating: 0, count: 25)
        var v = [Double](repeating: 0, count: 5)
        for p in points {
            let x = (p.x - mx) / rms, y = (p.y - my) / rms
            let row = [x * x, x * y, y * y, x, y]
            for i in 0..<5 {
                v[i] += row[i]
                for j in 0..<5 {
                    m[i * 5 + j] += row[i] * row[j]
                }
            }
        }
        guard let k = LinearSolver.solve(&m, &v, n: 5),
              let e = conicToEllipse(A: k[0], B: k[1], C: k[2], D: k[3], E: k[4], F: -1)
        else { return nil }

        return Ellipse(cx: e.cx * rms + mx, cy: e.cy * rms + my, a: e.a * rms, b: e.b * rms, angle: e.angle)
    }

    /// RANSAC around `fit`. Returns the refined ellipse and the fraction of points within `threshold`.
    static func ransac(_ points: [(x: Double, y: Double)], threshold: Double, iterations: Int = 80) -> (ellipse: Ellipse, inlierRatio: Double)? {
        guard points.count >= 5 else { return nil }

        func inliers(of e: Ellipse) -> [(x: Double, y: Double)] {
            points.filter { e.distance($0.x, $0.y) < threshold }
        }

        var best: Ellipse?
        var bestCount = 0
        for _ in 0..<iterations {
            var indices = Set<Int>()
            while indices.count < 5 { indices.insert(Int.random(in: 0..<points.count)) }
            guard let e = fit(indices.map { points[$0] }), e.b / e.a > 0.2 else { continue }
            let count = inliers(of: e).count
            if count > bestCount {
                bestCount = count
                best = e
                if Double(count) > 0.9 * Double(points.count) { break }
            }
        }
        guard let candidate = best else { return nil }

        let support = inliers(of: candidate)
        let refined = fit(support) ?? candidate
        let ratio = Double(inliers(of: refined).count) / Double(points.count)
        return (refined, ratio)
    }

    private static func conicToEllipse(A: Double, B: Double, C: Double, D: Double, E: Double, F: Double) -> Ellipse? {
        let det = 4 * A * C - B * B
        guard det > 1e-12 else { return nil }

        let x0 = (B * E - 2 * C * D) / det
        let y0 = (B * D - 2 * A * E) / det
        let f0 = F + (D * x0 + E * y0) / 2

        let mean = (A + C) / 2
        let diff = sqrt((A - C) * (A - C) / 4 + B * B / 4)
        let l1 = mean - diff, l2 = mean + diff
        let q1 = -f0 / l1, q2 = -f0 / l2
        guard q1 > 0, q2 > 0, q1.isFinite, q2.isFinite else { return nil }

        let (major, minor, lambda) = q1 >= q2 ? (sqrt(q1), sqrt(q2), l1) : (sqrt(q2), sqrt(q1), l2)

        // Eigenvector of [[A, B/2], [B/2, C]] for `lambda` gives the major axis direction.
        let v1 = (B / 2, lambda - A)
        let v2 = (lambda - C, B / 2)
        let n1 = hypot(v1.0, v1.1), n2 = hypot(v2.0, v2.1)
        let angle: Double
        if max(n1, n2) < 1e-12 {
            angle = 0
        } else if n1 >= n2 {
            angle = atan2(v1.1, v1.0)
        } else {
            angle = atan2(v2.1, v2.0)
        }

        return Ellipse(cx: x0, cy: y0, a: major, b: minor, angle: angle)
    }
}
