import Testing
import SwiftUI
import UIKit
@testable import BooksTrackerFeature

/// A SwiftUI host view to embed `RepresentationRadarChart` and allow data updates
/// via `@State`, which triggers re-renders for performance measurement.
@MainActor
private struct TestHostView: View {
    @State var chartData: RadarChartData

    init(initialData: RadarChartData) {
        _chartData = State(initialValue: initialData)
    }

    var body: some View {
        RepresentationRadarChart(data: chartData, onAddData: { _ in })
            .frame(width: 280, height: 280)
    }

    func updateData(_ newData: RadarChartData) {
        chartData = newData
    }
}

/// Performance tests for the `RepresentationRadarChart` component.
/// Measures CPU-bound work of SwiftUI's layout and update cycle for the Canvas-based chart.
@Test(timeLimit: .seconds(60))
@MainActor
func testRadarChartRenderPerformance() async throws {
    // 1. Prepare realistic initial data
    let initialData = RadarChartData(dimensions: [
        RadarDimension(name: "Cultural", completionPercentage: 80, isComplete: true),
        RadarDimension(name: "Gender", completionPercentage: 50, isComplete: true),
        RadarDimension(name: "Translation", completionPercentage: 0, isComplete: false),
        RadarDimension(name: "Own Voices", completionPercentage: 100, isComplete: true),
        RadarDimension(name: "Accessible", completionPercentage: 0, isComplete: false)
    ])

    // 2. Create TestHostView and embed in UIHostingController
    let hostView = TestHostView(initialData: initialData)
    let hostingController = UIHostingController(rootView: hostView)

    // 3. Add to dummy view hierarchy
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
    window.rootViewController = UIViewController()
    window.isHidden = false
    window.rootViewController?.view.addSubview(hostingController.view)
    hostingController.view.frame = window.rootViewController!.view.bounds
    hostingController.view.setNeedsLayout()
    hostingController.view.layoutIfNeeded()

    // Give SwiftUI time to process initial layout and .task
    try await Task.sleep(for: .milliseconds(50))

    // 4. Warm-up iterations (10 runs to prime caches)
    for i in 0..<10 {
        let newData = RadarChartData(dimensions: [
            RadarDimension(name: "Cultural", completionPercentage: Double((i * 10) % 100), isComplete: true),
            RadarDimension(name: "Gender", completionPercentage: Double(((i + 1) * 10) % 100), isComplete: true),
            RadarDimension(name: "Translation", completionPercentage: Double(((i + 2) * 10) % 100), isComplete: false),
            RadarDimension(name: "Own Voices", completionPercentage: Double(((i + 3) * 10) % 100), isComplete: true),
            RadarDimension(name: "Accessible", completionPercentage: Double(((i + 4) * 10) % 100), isComplete: false)
        ])
        hostView.updateData(newData)
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(5))
    }

    // 5. Measure performance for 100 iterations
    let metrics = await measure(iterations: 100) {
        let randomCompletion = Double.random(in: 0...100)
        let newData = RadarChartData(dimensions: [
            RadarDimension(name: "Cultural", completionPercentage: randomCompletion, isComplete: true),
            RadarDimension(name: "Gender", completionPercentage: (randomCompletion + 20).truncatingRemainder(dividingBy: 100), isComplete: true),
            RadarDimension(name: "Translation", completionPercentage: (randomCompletion + 40).truncatingRemainder(dividingBy: 100), isComplete: false),
            RadarDimension(name: "Own Voices", completionPercentage: (randomCompletion + 60).truncatingRemainder(dividingBy: 100), isComplete: true),
            RadarDimension(name: "Accessible", completionPercentage: (randomCompletion + 80).truncatingRemainder(dividingBy: 100), isComplete: false)
        ])

        hostView.updateData(newData)
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()

        try await Task.sleep(for: .milliseconds(1))
    }

    // 6. Report P95 latency and assert <200ms threshold
    let p95 = metrics.p95
    print("RadarChart Render Performance - P95: \(p95.formatted(.measurement(width: .wide)))")

    #expect(p95 < .milliseconds(200), "RadarChart P95 render time exceeded 200ms: \(p95.formatted(.measurement(width: .wide)))")

    // 7. Cleanup
    hostingController.willMove(toParent: nil)
    hostingController.view.removeFromSuperview()
    hostingController.removeFromParent()
    window.isHidden = true
    window.rootViewController = nil
}
