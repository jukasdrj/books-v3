import SwiftUI

struct RadarChartView: View {
    let metrics: [DiversityMetric]
    let maxValue: Double = 1.0
    let overallScore: Double
    var onMetricTapped: ((DiversityMetric) -> Void)? = nil

    @State private var animateChart = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 * 0.8

            ZStack {
                Canvas { context, _ in
                    drawGhostPolygon(context: context, center: center, radius: radius)
                    drawFilledPolygon(context: context, center: center, radius: radius)
                    drawAxisLines(context: context, center: center, radius: radius)
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Text("\(Int(overallScore * 100))%")
                        .font(.title.bold())
                        .foregroundColor(.primary)
                        .opacity(animateChart ? 1.0 : 0.0)
                }

                // Labels and Buttons
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    let angle = Angle(degrees: Double(index) * (360.0 / Double(metrics.count)) - 90)
                    let labelPoint = CGPoint(
                        x: center.x + (radius + 25) * CGFloat(cos(angle.radians)),
                        y: center.y + (radius + 25) * CGFloat(sin(angle.radians))
                    )

                    if metric.value == nil {
                        Button(action: { onMetricTapped?(metric) }) {
                            HStack(spacing: 4) {
                                Text(metric.label).font(.caption)
                                Image(systemName: "plus.circle.fill")
                            }
                        }
                        .position(labelPoint)
                    } else {
                        Text(metric.label)
                            .font(.caption)
                            .position(labelPoint)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0)) {
                animateChart = true
            }
        }
    }

    private func drawAxisLines(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        for i in 0..<metrics.count {
            let angle = Angle(degrees: Double(i) * (360.0 / Double(metrics.count)) - 90)
            let endPoint = CGPoint(
                x: center.x + radius * CGFloat(cos(angle.radians)),
                y: center.y + radius * CGFloat(sin(angle.radians))
            )

            var path = Path()
            path.move(to: center)
            path.addLine(to: endPoint)

            let strokeStyle = metrics[i].value == nil ? StrokeStyle(lineWidth: 1, dash: [5, 5]) : StrokeStyle(lineWidth: 1)
            context.stroke(path, with: .color(.gray.opacity(0.5)), style: strokeStyle)
        }
    }

    private func drawGhostPolygon(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        var ghostPath = Path()
        for i in 0..<metrics.count {
            let angle = Angle(degrees: Double(i) * (360.0 / Double(metrics.count)) - 90)
            let point = CGPoint(
                x: center.x + radius * CGFloat(cos(angle.radians)),
                y: center.y + radius * CGFloat(sin(angle.radians))
            )
            if i == 0 {
                ghostPath.move(to: point)
            } else {
                ghostPath.addLine(to: point)
            }
        }
        ghostPath.closeSubpath()
        context.stroke(ghostPath, with: .color(.gray.opacity(0.2)), lineWidth: 2)
    }

    private func drawFilledPolygon(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        var filledPath = Path()
        for i in 0..<metrics.count {
            let value = (metrics[i].value ?? 0.0) * (animateChart ? 1.0 : 0.0)
            let angle = Angle(degrees: Double(i) * (360.0 / Double(metrics.count)) - 90)
            let point = CGPoint(
                x: center.x + radius * CGFloat(value) * CGFloat(cos(angle.radians)),
                y: center.y + radius * CGFloat(value) * CGFloat(sin(angle.radians))
            )
            if i == 0 {
                filledPath.move(to: point)
            } else {
                filledPath.addLine(to: point)
            }
        }
        filledPath.closeSubpath()
        context.fill(filledPath, with: .color(Color.accentColor.opacity(0.5)))
        context.stroke(filledPath, with: .color(Color.accentColor), lineWidth: 2)
    }
}
