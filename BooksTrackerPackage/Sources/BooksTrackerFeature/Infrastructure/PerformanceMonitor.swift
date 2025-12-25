import SwiftUI

// MARK: - Performance Monitoring

/// Tracks view render times and identifies slow components
/// - Usage: `.performanceMonitor("ViewName")`
@MainActor
struct PerformanceMonitor: ViewModifier {
    let identifier: String
    @State private var renderStartTime: CFTimeInterval = 0

    func body(content: Content) -> some View {
        content
            .onAppear {
                renderStartTime = CACurrentMediaTime()
            }
            .onDisappear {
                let renderTime = CACurrentMediaTime() - renderStartTime
                if renderTime > 0.016 { // Alert if slower than 60fps
                    #if DEBUG
                    print("⚠️ PERFORMANCE: \(identifier) took \(renderTime * 1000)ms to render")
                    #endif
                }
            }
    }
}

extension View {
    func performanceMonitor(_ identifier: String) -> some View {
        modifier(PerformanceMonitor(identifier: identifier))
    }
}
