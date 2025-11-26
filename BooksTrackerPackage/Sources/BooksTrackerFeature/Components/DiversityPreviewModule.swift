import SwiftUI

struct DiversityPreviewModule: View {
    let work: Work

    private var diversityScore: DiversityScore {
        DiversityScore(work: work)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.radar")
                Text("Diversity Score")
                    .font(.headline)
                Spacer()
                Text("\(Int(diversityScore.overallScore * 100))%")
                    .font(.headline.bold())
                    .foregroundColor(.accentColor)
            }

            SimplifiedRadarChart(metrics: diversityScore.metrics)
                .frame(height: 100)

            Text("Representation Radar")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
        )
    }
}

private struct SimplifiedRadarChart: View {
    let metrics: [DiversityMetric]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 * 0.9

            // Draw ghost polygon
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
            context.stroke(ghostPath, with: .color(.gray.opacity(0.2)), lineWidth: 1)

            // Draw filled polygon
            var filledPath = Path()
            for i in 0..<metrics.count {
                let value = metrics[i].value ?? 0.0
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
            context.fill(filledPath, with: .color(Color.accentColor.opacity(0.6)))
        }
    }
}
