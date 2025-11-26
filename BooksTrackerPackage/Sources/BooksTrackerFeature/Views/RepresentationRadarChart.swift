import SwiftUI
import SwiftData

/// Data model for the radar chart dimensions.
public struct RadarDimension {
    public let name: String
    public let completionPercentage: Double // 0-100
    public let isComplete: Bool

    public init(name: String, completionPercentage: Double, isComplete: Bool) {
        self.name = name
        self.completionPercentage = completionPercentage
        self.isComplete = isComplete
    }
}

/// Complete data for rendering the radar chart.
public struct RadarChartData {
    public let dimensions: [RadarDimension]

    public init(dimensions: [RadarDimension]) {
        self.dimensions = dimensions
    }

    /// Overall completion percentage across all dimensions.
    public var overallCompletionPercentage: Double {
        let total = Double(dimensions.count)
        let complete = Double(dimensions.filter(\.isComplete).count)
        return (complete / total) * 100
    }
}

/// Interactive 5-axis radar chart for diversity representation stats.
public struct RepresentationRadarChart: View {
    private let data: RadarChartData
    private let onAddData: (String) -> Void

    @State private var chartModel: ChartModel?

    private let chartSize: CGFloat = 280
    private let chartRadius: CGFloat = 120
    private let gridLevels: [CGFloat] = [0.25, 0.5, 0.75, 1.0]
    private let dimensionCount = 5
    private let angleStep: Double = .pi * 2 / 5 // 72 degrees

    public init(data: RadarChartData, onAddData: @escaping (String) -> Void) {
        self.data = data
        self.onAddData = onAddData
    }

    public var body: some View {
        chartContent
            .frame(width: chartSize, height: chartSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
            .task {
                chartModel = ChartModel(data: data, radius: chartRadius, angleStep: angleStep)
            }
    }

    private var chartContent: some View {
        GeometryReader { geometry in
            ZStack {
                canvasView
                tapTargetsView
            }
        }
    }

    private var canvasView: some View {
        Canvas { context, size in
            guard let model = chartModel else { return }
            drawChart(in: context, size: size, model: model)
        }
        .frame(width: chartSize, height: chartSize)
    }

    @ViewBuilder
    private var tapTargetsView: some View {
        if let model = chartModel {
            ForEach(Array(model.missingIndices), id: \.self) { index in
                let point = model.dataPoints[index]
                Button(action: { onAddData(data.dimensions[index].name) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.clear))
                }
                .position(x: point.x + chartSize/2, y: point.y + chartSize/2)
                .accessibilityLabel(
                    "Add \(data.dimensions[index].name) data. Currently \(Int(data.dimensions[index].completionPercentage))% complete."
                )
            }
        }
    }

    private var accessibilityDescription: String {
        "Diversity radar chart. \(Int(data.overallCompletionPercentage))% complete overall. " +
        data.dimensions.enumerated().map { index, dim in
            "\(dim.name): \(Int(dim.completionPercentage))%"
        }.joined(separator: ". ")
    }

    private func drawChart(in context: GraphicsContext, size: CGSize, model: ChartModel) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // Grid lines (concentric pentagons)
        context.stroke(
            Path { path in
                for level in gridLevels {
                    let radius = model.maxRadius * level
                    path.addPolygon(center: center, radius: radius, sides: dimensionCount, startAngle: -.pi / 2)
                }
            },
            with: .color(.secondary.opacity(0.3)),
            lineWidth: 1
        )

        // Axis lines from center
        context.stroke(
            Path { path in
                for i in 0..<dimensionCount {
                    let angle = model.startAngle + Double(i) * model.angleStep
                    let vector = AngleVector(angle: angle)
                    let endPoint = center.adding(vector.scaled(by: model.maxRadius))
                    path.move(to: center)
                    path.addLine(to: endPoint)
                }
            },
            with: .color(.secondary.opacity(0.5)),
            lineWidth: 1
        )

        // Ghost polygon (100% target outline) - MVP Sprint 1
        context.stroke(
            Path { path in
                path.addPolygon(center: center, radius: model.maxRadius, sides: dimensionCount, startAngle: -.pi / 2)
            },
            with: .color(.secondary.opacity(0.4)),
            style: StrokeStyle(lineWidth: 2, dash: [8, 4])
        )

        // Filled polygon showing actual scores - MVP Sprint 1
        let dataPolygonPath = Path { path in
            for (i, point) in model.dataPoints.enumerated() {
                let screenPoint = CGPoint(x: point.x + center.x, y: point.y + center.y)
                if i == 0 {
                    path.move(to: screenPoint)
                } else {
                    path.addLine(to: screenPoint)
                }
            }
            path.closeSubpath()
        }
        
        // Fill the polygon with semi-transparent color
        context.fill(dataPolygonPath, with: .color(.green.opacity(0.2)))

        // Data polygon segments (outline)
        for i in 0..<dimensionCount {
            let currentPoint = model.dataPoints[i]
            let nextPoint = model.dataPoints[(i + 1) % dimensionCount]
            let currentScreenPoint = CGPoint(x: currentPoint.x + center.x, y: currentPoint.y + center.y)
            let nextScreenPoint = CGPoint(x: nextPoint.x + center.x, y: nextPoint.y + center.y)

            let isCurrentComplete = data.dimensions[i].isComplete

            let segmentPath = Path { p in
                p.move(to: currentScreenPoint)
                p.addLine(to: nextScreenPoint)
            }

            if isCurrentComplete {
                context.stroke(segmentPath, with: .color(.green), lineWidth: 2)
            } else {
                context.stroke(
                    segmentPath,
                    with: .color(.secondary.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 2, dash: [5, 5])
                )
            }
        }

        // Center percentage label - MVP Sprint 1
        let percentageText = Text("\(Int(data.overallCompletionPercentage))%")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.primary)
        
        let percentageRect = CGRect(
            x: center.x - 30,
            y: center.y - 12,
            width: 60,
            height: 24
        )
        context.draw(percentageText, in: percentageRect)

        // Axis labels
        for (i, dimension) in data.dimensions.enumerated() {
            let angle = model.startAngle + Double(i) * model.angleStep
            let vector = AngleVector(angle: angle)
            let labelPoint = center.adding(vector.scaled(by: model.maxRadius + 25))
            let labelRect = CGRect(
                x: labelPoint.x - 20,
                y: labelPoint.y - 6,
                width: 40,
                height: 12
            )

            context.draw(
                Text(dimension.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary),
                in: labelRect
            )
        }
    }
}

// MARK: - Private Models

private struct ChartModel {
    let dataPoints: [CGPoint]
    let maxRadius: CGFloat
    let startAngle: Double
    let angleStep: Double
    let missingIndices: [Int]

    init(data: RadarChartData, radius: CGFloat, angleStep: Double) {
        let startAngleValue = -Double.pi / 2 // Top of chart

        self.angleStep = angleStep
        self.startAngle = startAngleValue
        self.maxRadius = radius

        // Calculate data points
        self.dataPoints = (0..<5).map { i in
            let normalizedValue = data.dimensions[i].completionPercentage / 100
            let r = radius * normalizedValue
            let theta = startAngleValue + Double(i) * angleStep
            return .init(x: r * CGFloat(cos(theta)), y: r * CGFloat(sin(theta)))
        }

        self.missingIndices = data.dimensions.enumerated()
            .filter { !$0.element.isComplete }
            .map { $0.offset }
    }
}

private extension Path {
    mutating func addPolygon(center: CGPoint, radius: CGFloat, sides: Int, startAngle: Double) {
        let angleStep = .pi * 2 / Double(sides)
        for i in 0..<sides {
            let angle = startAngle + angleStep * Double(i)
            let vector = AngleVector(angle: angle)
            let point = center.adding(vector.scaled(by: radius))
            if i == 0 {
                move(to: point)
            } else {
                addLine(to: point)
            }
        }
        closeSubpath()
    }
}

private struct AngleVector {
    let x: CGFloat
    let y: CGFloat

    init(angle: Double) {
        self.x = CGFloat(cos(angle))
        self.y = CGFloat(sin(angle))
    }

    func toPoint() -> CGPoint {
        CGPoint(x: x, y: y)
    }

    func scaled(by factor: CGFloat) -> CGPoint {
        CGPoint(x: factor * x, y: factor * y)
    }
}

private extension CGPoint {
    func adding(_ other: CGPoint) -> CGPoint {
        CGPoint(x: self.x + other.x, y: self.y + other.y)
    }
}

#Preview {
    RepresentationRadarChart(
        data: RadarChartData(dimensions: [
            RadarDimension(name: "Cultural", completionPercentage: 80, isComplete: true),
            RadarDimension(name: "Gender", completionPercentage: 50, isComplete: true),
            RadarDimension(name: "Translation", completionPercentage: 0, isComplete: false),
            RadarDimension(name: "Own Voices", completionPercentage: 100, isComplete: true),
            RadarDimension(name: "Accessible", completionPercentage: 0, isComplete: false)
        ]),
        onAddData: { dimension in
            print("Add data for \(dimension)")
        }
    )
}
