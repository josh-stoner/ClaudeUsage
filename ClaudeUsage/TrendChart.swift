import SwiftUI

/// Full-size utilization chart for the Trends tab.
/// R4: smooth Bézier curves, gradient area fill, glow underlay, glowing peak dot.
/// Absolute 0–100 Y-axis so charts across different buckets are visually comparable.
struct TrendChart: View {
    let values: [Double]   // ordered oldest → newest, values 0–100
    let tint: Color
    var height: CGFloat = 52
    var warningThreshold: Double = 80  // dashed guide line

    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2 else { return }
            let pts    = points(for: values, in: size)
            let smooth = smoothPath(through: pts)

            // Gradient area fill — hero data-viz treatment (tint → clear)
            var fill = smooth
            fill.addLine(to: CGPoint(x: pts.last!.x, y: size.height))
            fill.addLine(to: CGPoint(x: pts[0].x,    y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(
                Gradient(stops: [
                    .init(color: tint.opacity(0.40), location: 0.0),
                    .init(color: tint.opacity(0.00), location: 1.0),
                ]),
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint:   CGPoint(x: size.width / 2, y: size.height)
            ))

            // 80% threshold dashed guide
            let guideY = size.height * CGFloat(1 - warningThreshold / 100)
            var guide = Path()
            guide.move(to: CGPoint(x: 0,           y: guideY))
            guide.addLine(to: CGPoint(x: size.width, y: guideY))
            ctx.stroke(guide, with: .color(.white.opacity(0.13)),
                       style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))

            // Glow underlay — two wide, low-opacity passes simulate soft neon edge
            ctx.stroke(smooth, with: .color(tint.opacity(0.16)),
                       style: StrokeStyle(lineWidth: 5.0, lineJoin: .round))
            ctx.stroke(smooth, with: .color(tint.opacity(0.28)),
                       style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))

            // Crisp hairline stroke
            ctx.stroke(smooth, with: .color(tint.opacity(0.90)),
                       style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))

            // Peak-value dot with glow ring
            if let peakIdx = values.indices.max(by: { values[$0] < values[$1] }) {
                let pt = pts[peakIdx]
                let glowRing = Path(ellipseIn: CGRect(x: pt.x - 5.5, y: pt.y - 5.5, width: 11, height: 11))
                ctx.fill(glowRing, with: .color(tint.opacity(0.35)))
                let dot = Path(ellipseIn: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5))
                ctx.fill(dot, with: .color(tint.opacity(0.96)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .drawingGroup()
    }

    // MARK: Private

    private func points(for vals: [Double], in size: CGSize) -> [CGPoint] {
        vals.enumerated().map { i, v in
            let x = size.width  * CGFloat(i) / CGFloat(vals.count - 1)
            let y = size.height * CGFloat(1 - v / 100.0)
            return CGPoint(x: x, y: max(0, min(y, size.height)))
        }
    }

    /// Quadratic-midpoint smooth path — each data point is a Bézier control point,
    /// midpoints between adjacent data points are the curve endpoints.
    /// Produces a C¹-continuous curve with no cusps.
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
