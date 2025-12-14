import SwiftUI

// MARK: - Animation Timing Constants

enum RadarChartAnimation {
    static let axisDraw: TimeInterval = 0.4
    static let axisStagger: TimeInterval = 0.1
    static let gridFade: TimeInterval = 0.2
    static let polygonMorph: TimeInterval = 0.3
    static let counterUpdate: TimeInterval = 0.5
    static let axisPulse: TimeInterval = 0.2
}

@MainActor
public struct RadarChartView: View {
    let metrics: [DiversityMetric]
    private let axisCount = DiversityMetric.Axis.allCases.count

    // MARK: - Layout Constants
    private let radiusScale: CGFloat = 0.8
    private let labelOffset: CGFloat = 25

    // MARK: - Animation State
    @State private var axisProgress: [Double] = []
    @State private var gridProgress: Double = 0
    @State private var polygonProgress: Double = 0
    @State private var scoreDisplay: Double = 0
    @State private var axisPulseProgress: [Double] = []
    @State private var previousMetrics: [DiversityMetric] = []
    @State private var isInitialized = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    // 1. Draw Axis Lines with animation
                    drawAxes(context: &context, center: center, radius: radius)

                    // 2. Draw Ghost Polygon (100% Target)
                    drawGhostPolygon(context: &context, center: center, radius: radius)

                    // 3. Draw Filled Polygon (Actual Values) with morphing
                    drawFilledPolygon(context: &context, center: center, radius: radius)
                }
                .frame(width: chartSize, height: chartSize)

                // 4. Draw Axis Labels/Icons
                axisLabels(size: chartSize)

                // 5. Center Label with animated counter
                centerLabel
                    .frame(width: chartSize, height: chartSize)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear {
            startInitialAnimation()
        }
        .onChange(of: metrics) { oldValue, newValue in
            handleMetricsChange(from: oldValue, to: newValue)
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
            Text(String(format: "%.0f%%", scoreDisplay * 100))
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text("Overall Score")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func axisLabels(size: CGFloat) -> some View {
        let radius: CGFloat = size / 2 * radiusScale
        let centerOffset: CGFloat = size / 2
        return ZStack {
            ForEach(0..<axisCount, id: \.self) { i in
                axisLabelView(index: i, radius: radius, centerOffset: centerOffset)
            }
        }
    }

    @ViewBuilder
    private func axisLabelView(index i: Int, radius: CGFloat, centerOffset: CGFloat) -> some View {
        let axis = DiversityMetric.Axis.allCases[i]
        let angle: Double = (2 * .pi / Double(axisCount)) * Double(i) - .pi / 2
        let xPos: CGFloat = cos(angle) * (radius + labelOffset)
        let yPos: CGFloat = sin(angle) * (radius + labelOffset)
        let metric = metricsByAxis[axis]
        let isMissing = metric?.isMissing == true

        VStack {
            if isMissing {
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
        .position(x: centerOffset + xPos, y: centerOffset + yPos)
    }

    private func drawAxes(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for i in 0..<axisCount {
            let axis = DiversityMetric.Axis.allCases[i]
            let angle = (2 * .pi / Double(axisCount)) * Double(i) - .pi / 2

            // Get animation progress for this axis
            let progress = axisProgress.indices.contains(i) ? axisProgress[i] : 0
            let animatedRadius = radius * progress

            let endPoint = CGPoint(
                x: center.x + cos(angle) * animatedRadius,
                y: center.y + sin(angle) * animatedRadius
            )

            let metric = metricsByAxis[axis]

            var path = Path()
            path.move(to: center)
            path.addLine(to: endPoint)

            // Calculate color with pulse effect
            let baseOpacity: CGFloat = 0.5
            let pulseOpacity = calculatePulseOpacity(for: i, baseOpacity: baseOpacity)

            if metric?.isMissing == true {
                context.stroke(path, with: .color(.gray.opacity(pulseOpacity)), style: StrokeStyle(lineWidth: 1, dash: [5]))
            } else {
                context.stroke(path, with: .color(.gray.opacity(pulseOpacity)), lineWidth: 1)
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
        // Grid fades in after axes are drawn
        let opacity: Double = 0.8 * gridProgress
        context.stroke(path, with: .color(.gray.opacity(opacity)), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
    }

    private func drawFilledPolygon(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        var path = Path()
        for i in 0..<axisCount {
            let axis = DiversityMetric.Axis.allCases[i]
            let metric = metricsByAxis[axis]
            let currentScore = metric?.isMissing == false ? metric?.score ?? 0 : 0

            // For morphing: interpolate between previous and current score
            let previousScore: Double
            if !previousMetrics.isEmpty {
                let previousMetricsByAxis = Dictionary(uniqueKeysWithValues: previousMetrics.map { ($0.axis, $0) })
                let prevMetric = previousMetricsByAxis[axis]
                previousScore = prevMetric?.isMissing == false ? prevMetric?.score ?? 0 : 0
            } else {
                previousScore = 0
            }

            // Interpolate score based on polygon animation progress
            let interpolatedScore = previousScore + (currentScore - previousScore) * polygonProgress

            let angle = (2 * .pi / Double(axisCount)) * Double(i) - .pi / 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius * interpolatedScore,
                y: center.y + sin(angle) * radius * interpolatedScore
            )

            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        // Polygon appears after grid
        let fillOpacity: Double = 0.4 * polygonProgress
        context.fill(path, with: .color(.accentColor.opacity(fillOpacity)))
        let strokeOpacity: Double = polygonProgress
        context.stroke(path, with: .color(.accentColor.opacity(strokeOpacity)), lineWidth: 2)
    }

    // MARK: - Animation Handlers

    private func startInitialAnimation() {
        guard !isInitialized else { return }
        isInitialized = true

        // Initialize animation arrays
        axisProgress = Array(repeating: 0, count: axisCount)
        axisPulseProgress = Array(repeating: 0, count: axisCount)

        if reduceMotion {
            // Disable animations for accessibility
            axisProgress = Array(repeating: 1, count: axisCount)
            gridProgress = 1
            polygonProgress = 1
            scoreDisplay = overallScore
        } else {
            // Axes draw outward with stagger
            for i in 0..<axisCount {
                let delay = Double(i) * RadarChartAnimation.axisStagger
                withAnimation(.easeOut(duration: RadarChartAnimation.axisDraw).delay(delay)) {
                    axisProgress[i] = 1
                }
            }

            // Grid appears after axes
            let gridDelay = Double(axisCount - 1) * RadarChartAnimation.axisStagger + RadarChartAnimation.axisDraw
            withAnimation(.easeInOut(duration: RadarChartAnimation.gridFade).delay(gridDelay)) {
                gridProgress = 1
            }

            // Polygon fills after grid
            let polygonDelay = gridDelay + RadarChartAnimation.polygonMorph * 0.3
            withAnimation(.easeInOut(duration: RadarChartAnimation.polygonMorph).delay(polygonDelay)) {
                polygonProgress = 1
            }

            // Score counter starts after polygon
            let scoreDelay = polygonDelay + RadarChartAnimation.polygonMorph
            animateCounter(to: overallScore, duration: RadarChartAnimation.counterUpdate, delay: scoreDelay)
        }
    }

    private func handleMetricsChange(from oldValue: [DiversityMetric], to newValue: [DiversityMetric]) {
        // Skip if nothing actually changed
        guard oldValue != newValue else { return }

        if reduceMotion {
            // No animation for accessibility
            scoreDisplay = overallScore
            previousMetrics = []
        } else {
            // Store previous metrics for morphing
            previousMetrics = oldValue

            // Reset polygon for morphing animation
            polygonProgress = 0
            withAnimation(.easeInOut(duration: RadarChartAnimation.polygonMorph)) {
                polygonProgress = 1
            }

            // Update score counter
            animateCounter(to: overallScore, duration: RadarChartAnimation.counterUpdate)

            // Pulse updated axes
            pulseUpdatedAxes()
        }
    }

    private func pulseUpdatedAxes() {
        // Find which axes changed
        guard !previousMetrics.isEmpty else { return }

        let previousMetricsByAxis = Dictionary(uniqueKeysWithValues: previousMetrics.map { ($0.axis, $0) })

        for i in 0..<axisCount {
            let axis = DiversityMetric.Axis.allCases[i]
            let currentMetric = metricsByAxis[axis]
            let previousMetric = previousMetricsByAxis[axis]

            let currentScore = currentMetric?.isMissing == false ? currentMetric?.score ?? 0 : 0
            let previousScore = previousMetric?.isMissing == false ? previousMetric?.score ?? 0 : 0

            if abs(currentScore - previousScore) > 0.01 {
                // This axis changed, pulse it
                let delay = Double(i) * 0.05
                withAnimation(.easeInOut(duration: RadarChartAnimation.axisPulse).delay(delay)) {
                    axisPulseProgress[i] = 1
                }
                // Reset after pulse
                Task {
                    try? await Task.sleep(for: .seconds(RadarChartAnimation.axisPulse + delay))
                    axisPulseProgress[i] = 0
                }
            }
        }
    }

    private func animateCounter(to targetScore: Double, duration: TimeInterval, delay: TimeInterval = 0) {
        let startScore = scoreDisplay
        let animationDuration = duration

        Task {
            // Start the counter animation after delay
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }

            let animationStart = Date()
            let frameInterval: Duration = .milliseconds(16) // ~60fps

            while true {
                let elapsed = Date().timeIntervalSince(animationStart)
                let progress = min(elapsed / animationDuration, 1.0)

                // Ease-out animation curve
                let easedProgress = 1 - pow(1 - progress, 3)
                scoreDisplay = startScore + (targetScore - startScore) * easedProgress

                if progress >= 1.0 {
                    scoreDisplay = targetScore
                    break
                }

                try? await Task.sleep(for: frameInterval)
            }
        }
    }

    private func calculatePulseOpacity(for axisIndex: Int, baseOpacity: CGFloat) -> Double {
        // Only pulse axes that recently changed during data updates
        guard axisPulseProgress.indices.contains(axisIndex) else { return Double(baseOpacity) }

        let pulseValue = axisPulseProgress[axisIndex]
        if pulseValue > 0 {
            let pulseIntensity = sin(pulseValue * .pi)
            return Double(baseOpacity + (1 - baseOpacity) * CGFloat(pulseIntensity) * 0.5)
        }
        return Double(baseOpacity)
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
