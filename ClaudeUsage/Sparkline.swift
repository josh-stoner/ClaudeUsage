import SwiftUI

/// Minimal inline time-series sparkline for the Plan tab meter rows.
/// R4: smooth Bézier curves, gradient area fill, glow underlay.
/// Values are normalised to min/max range so the chart always fills the height.
struct Sparkline: View {
    /// Ordered (oldest → newest) raw utilization values (0–100).
    let values: [Double]
    let tint: Color
    var width: CGFloat  = 28
    var height: CGFloat = 16

    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2 else { return }
            let pts    = normalise(values, in: size)
            let smooth = smoothPath(through: pts)

            // Gradient area fill — tint → clear
            var fill = smooth
            fill.addLine(to: CGPoint(x: pts.last!.x, y: size.height))
            fill.addLine(to: CGPoint(x: pts[0].x,    y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(
                Gradient(stops: [
                    .init(color: tint.opacity(0.32), location: 0.0),
                    .init(color: tint.opacity(0.00), location: 1.0),
                ]),
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint:   CGPoint(x: size.width / 2, y: size.height)
            ))

            // Glow underlay
            ctx.stroke(smooth, with: .color(tint.opacity(0.22)),
                       style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))

            // Crisp stroke
            ctx.stroke(smooth, with: .color(tint.opacity(0.82)),
                       style: StrokeStyle(lineWidth: 1, lineJoin: .round))
        }
        .frame(width: width, height: height)
        .drawingGroup()
    }

    // MARK: Private

    private func normalise(_ vals: [Double], in size: CGSize) -> [CGPoint] {
        let mn    = vals.min() ?? 0
        let mx    = vals.max() ?? 1
        let range = max(mx - mn, 1e-6)
        return vals.enumerated().map { i, v in
            let x = size.width  * CGFloat(i) / CGFloat(vals.count - 1)
            let y = size.height * (1 - CGFloat((v - mn) / range))
            return CGPoint(x: x, y: y)
        }
    }

    /// Quadratic-midpoint smooth path — data points are Bézier controls,
    /// midpoints between adjacent points are curve endpoints.
    private func smoothPath(through pts: [CGPoint]) -> Path {
        var path = Path()
        guard pts.count >= 2 else { return path }

        path.move(to: pts[0])

        if pts.count == 2 {
            path.addLine(to: pts[1])
            return path
        }

        for i in 1..<pts.count - 1 {
            let prev = pts[i - 1]
            let curr = pts[i]
            let next = pts[i + 1]
            let mid1 = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
            let mid2 = CGPoint(x: (curr.x + next.x) / 2, y: (curr.y + next.y) / 2)
            if i == 1 { path.addLine(to: mid1) }
            path.addQuadCurve(to: mid2, control: curr)
        }
        path.addLine(to: pts.last!)
        return path
    }
}
