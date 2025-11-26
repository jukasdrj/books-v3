import SwiftUI

@MainActor
public struct RadarChartView: View {
    let metrics: [DiversityMetric]
    private let axisCount = DiversityMetric.Axis.allCases.count

    // MARK: - Layout Constants
    private let radiusScale: CGFloat = 0.8
    private let labelOffset: CGFloat = 25

    /// Pre-computed dictionary for O(1) metric lookups by axis
    private let metricsByAxis: [DiversityMetric.Axis: DiversityMetric]

    public init(metrics: [DiversityMetric]) {
        self.metrics = metrics
        self.metricsByAxis = Dictionary(uniqueKeysWithValues: metrics.map { ($0.axis, $0) })
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                let chartSize = min(geometry.size.width, geometry.size.height)
                let center = CGPoint(x: chartSize / 2, y: chartSize / 2)
                let radius = chartSize / 2 * radiusScale

                Canvas { context, _ in
                    // 1. Draw Axis Lines
                    drawAxes(context: &context, center: center, radius: radius)

                    // 2. Draw Ghost Polygon (100% Target)
                    drawGhostPolygon(context: &context, center: center, radius: radius)

                    // 3. Draw Filled Polygon (Actual Values)
                    drawFilledPolygon(context: &context, center: center, radius: radius)
                }
                .frame(width: chartSize, height: chartSize)

                // 4. Draw Axis Labels/Icons
                axisLabels(size: chartSize)

                // 5. Center Label
                centerLabel
                    .frame(width: chartSize, height: chartSize)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var overallScore: Double {
        let validMetrics = metrics.filter { !$0.isMissing }
        guard !validMetrics.isEmpty else { return 0 }
        let totalScore = validMetrics.reduce(0) { $0 + $1.score }
        return totalScore / Double(validMetrics.count)
    }

    private var centerLabel: some View {
        VStack {
            Text(String(format: "%.0f%%", overallScore * 100))
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text("Overall Score")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func axisLabels(size: CGFloat) -> some View {
        let radius = size / 2 * radiusScale
        return ZStack {
            ForEach(0..<axisCount, id: \.self) { i in
                let axis = DiversityMetric.Axis.allCases[i]
                let angle = (2 * .pi / Double(axisCount)) * Double(i) - .pi / 2
                let point = CGPoint(
                    x: cos(angle) * (radius + labelOffset),
                    y: sin(angle) * (radius + labelOffset)
                )
                let metric = metricsByAxis[axis]

                VStack {
                    if metric?.isMissing == true {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: axis.systemImage)
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                    Text(axis.rawValue)
                        .font(.caption)
                }
                .position(x: size / 2 + point.x, y: size / 2 + point.y)
            }
        }
    }

    private func drawAxes(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for i in 0..<axisCount {
            let axis = DiversityMetric.Axis.allCases[i]
            let angle = (2 * .pi / Double(axisCount)) * Double(i) - .pi / 2
            let endPoint = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )

            let metric = metricsByAxis[axis]

            var path = Path()
            path.move(to: center)
            path.addLine(to: endPoint)

            if metric?.isMissing == true {
                context.stroke(path, with: .color(.gray.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [5]))
            } else {
                context.stroke(path, with: .color(.gray.opacity(0.5)), lineWidth: 1)
            }
        }
    }

    private func drawGhostPolygon(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        var path = Path()
        for i in 0..<axisCount {
            let angle = (2 * .pi / Double(axisCount)) * Double(i) - .pi / 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        context.stroke(path, with: .color(.gray.opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
    }

    private func drawFilledPolygon(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        var path = Path()
        for i in 0..<axisCount {
            let axis = DiversityMetric.Axis.allCases[i]
            let metric = metricsByAxis[axis]
            let score = metric?.isMissing == false ? metric?.score ?? 0 : 0

            let angle = (2 * .pi / Double(axisCount)) * Double(i) - .pi / 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius * score,
                y: center.y + sin(angle) * radius * score
            )

            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        context.fill(path, with: .color(.accentColor.opacity(0.4)))
        context.stroke(path, with: .color(.accentColor), lineWidth: 2)
    }
}

#if DEBUG
struct RadarChartView_Previews: PreviewProvider {
    static var previews: some View {
        RadarChartView(metrics: DiversityMetric.sample)
            .padding(40)
            .background(Color(.systemBackground))
            .frame(height: 350)
    }
}
#endif
