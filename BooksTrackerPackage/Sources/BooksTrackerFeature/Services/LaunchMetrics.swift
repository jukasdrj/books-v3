import Foundation

/// Tracks app launch performance metrics
@MainActor
public final class LaunchMetrics {
    public static let shared = LaunchMetrics()

    private let launchStartTime: CFAbsoluteTime
    private var milestones: [(String, CFAbsoluteTime)] = []

    private init() {
        launchStartTime = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        print("🚀 Launch tracking started")
        #endif
    }

    /// Record a milestone during app launch
    public func recordMilestone(_ name: String) {
        let timestamp = CFAbsoluteTimeGetCurrent()
        milestones.append((name, timestamp))
        #if DEBUG
        let elapsed = (timestamp - launchStartTime) * 1000
        print("⏱️ \(name): +\(Int(elapsed))ms")
        #endif
    }

    /// Get total launch time
    public func totalLaunchTime() -> Double? {
        guard let lastMilestone = milestones.last else { return nil }
        return (lastMilestone.1 - launchStartTime) * 1000
    }

    /// Print full launch report
    public func printReport() {
        #if DEBUG
        guard !milestones.isEmpty else { return }
        print("\n📊 Launch Performance Report")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        for (name, timestamp) in milestones {
            let elapsed = (timestamp - launchStartTime) * 1000
            print("  \(name): +\(Int(elapsed))ms")
        }
        if let total = totalLaunchTime() {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("  Total: \(Int(total))ms")
        }
        print()
        #endif
    }
}
