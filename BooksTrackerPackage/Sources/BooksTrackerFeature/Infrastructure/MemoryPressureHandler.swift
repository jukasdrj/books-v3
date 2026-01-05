#if canImport(UIKit)
import UIKit
#endif

// MARK: - Memory Pressure Handler

/// Cleans up image cache when memory pressure occurs
struct MemoryPressureHandler {
    static let shared = MemoryPressureHandler()

    private init() {
        #if canImport(UIKit)
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Self.cleanupImageCache()
        }
        #endif
    }

    private static func cleanupImageCache() {
        CachedAsyncImageCache.shared.cache.removeAllObjects()
        #if DEBUG
        print("🧹 MEMORY: Cleared image cache due to memory pressure")
        #endif
    }
}

// MARK: - Cached Image Cache

/// Shared cache for all CachedAsyncImage instances
/// - Thread-safe via NSCache's internal synchronization
/// - Limits: 100 images, 50MB total
final class CachedAsyncImageCache: @unchecked Sendable {
    static let shared = CachedAsyncImageCache()

    let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        return cache
    }()

    private init() {}
}
