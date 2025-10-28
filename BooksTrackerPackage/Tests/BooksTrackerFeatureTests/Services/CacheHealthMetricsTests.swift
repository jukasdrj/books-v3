import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("CacheHealthMetrics")
@MainActor
struct CacheHealthMetricsTests {

    @Test("STALE status counts as cache miss")
    @MainActor
    func staleStatusCountsAsMiss() {
        let metrics = CacheHealthMetrics()

        // 1 HIT + 1 STALE = 50% hit rate
        metrics.update(from: ["X-Cache-Status": "HIT"], responseTime: 100)
        metrics.update(from: ["X-Cache-Status": "STALE"], responseTime: 150)

        #expect(metrics.cacheHitRate == 0.5)
    }

    @Test("EXPIRED status counts as cache miss")
    @MainActor
    func expiredStatusCountsAsMiss() {
        let metrics = CacheHealthMetrics()

        // 1 HIT + 1 EXPIRED = 50% hit rate
        metrics.update(from: ["X-Cache-Status": "HIT"], responseTime: 100)
        metrics.update(from: ["X-Cache-Status": "EXPIRED"], responseTime: 200)

        #expect(metrics.cacheHitRate == 0.5)
    }

    @Test("BYPASS status counts as cache miss")
    @MainActor
    func bypassStatusCountsAsMiss() {
        let metrics = CacheHealthMetrics()

        // 2 HIT + 1 BYPASS = 66.67% hit rate
        metrics.update(from: ["X-Cache-Status": "HIT"], responseTime: 80)
        metrics.update(from: ["X-Cache-Status": "HIT"], responseTime: 90)
        metrics.update(from: ["X-Cache-Status": "BYPASS"], responseTime: 300)

        let expectedRate = 2.0 / 3.0  // 0.6666...
        #expect(abs(metrics.cacheHitRate - expectedRate) < 0.01)
    }

    @Test("REVALIDATED status counts as cache miss")
    @MainActor
    func revalidatedStatusCountsAsMiss() {
        let metrics = CacheHealthMetrics()

        // 1 HIT + 1 REVALIDATED = 50% hit rate
        metrics.update(from: ["X-Cache-Status": "HIT"], responseTime: 100)
        metrics.update(from: ["X-Cache-Status": "REVALIDATED"], responseTime: 250)

        #expect(metrics.cacheHitRate == 0.5)
    }
}
