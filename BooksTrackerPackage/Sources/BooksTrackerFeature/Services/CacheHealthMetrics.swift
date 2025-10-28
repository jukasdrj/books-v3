import Foundation

/// Observable model tracking cache health metrics from backend headers
@Observable
@MainActor
public final class CacheHealthMetrics {
    // Rolling metrics
    public private(set) var cacheHitRate: Double = 0.0              // 0.0 - 1.0
    public private(set) var averageResponseTime: TimeInterval = 0   // Milliseconds
    public private(set) var imageAvailability: Double = 0.0         // 0.0 - 1.0
    public private(set) var dataCompleteness: Double = 0.0          // 0.0 - 1.0
    public private(set) var lastCacheAge: TimeInterval = 0          // Seconds

    // Internal tracking for rolling averages
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var responseTimes: [TimeInterval] = []
    private let maxResponseSamples = 20  // Keep last 20 requests

    /// Singleton instance
    public static let shared = CacheHealthMetrics()

    private init() {}

    /// Update metrics from HTTP response headers
    /// - Parameters:
    ///   - headers: HTTPURLResponse.allHeaderFields dictionary
    ///   - responseTime: Request duration in milliseconds
    public func update(from headers: [AnyHashable: Any], responseTime: TimeInterval) {
        // Cache status
        if let cacheStatus = headers["X-Cache-Status"] as? String {
            if cacheStatus == "HIT" {
                cacheHits += 1
            } else if cacheStatus == "MISS" {
                cacheMisses += 1
            }

            let totalRequests = cacheHits + cacheMisses
            cacheHitRate = totalRequests > 0 ? Double(cacheHits) / Double(totalRequests) : 0.0
        }

        // Cache age
        if let ageString = headers["X-Cache-Age"] as? String,
           let age = TimeInterval(ageString) {
            lastCacheAge = age
        }

        // Image quality → availability (simplified mapping)
        if let imageQuality = headers["X-Image-Quality"] as? String {
            switch imageQuality {
            case "high": imageAvailability = 1.0
            case "medium": imageAvailability = 0.75
            case "low": imageAvailability = 0.5
            case "missing": imageAvailability = 0.0
            default: break
            }
        }

        // Data completeness
        if let completenessString = headers["X-Data-Completeness"] as? String,
           let completeness = Double(completenessString) {
            dataCompleteness = completeness / 100.0 // Convert percentage to 0-1
        }

        // Response time (rolling average)
        responseTimes.append(responseTime)
        if responseTimes.count > maxResponseSamples {
            responseTimes.removeFirst()
        }
        averageResponseTime = responseTimes.reduce(0, +) / Double(responseTimes.count)
    }

    /// Reset all metrics (useful for testing)
    public func reset() {
        cacheHitRate = 0.0
        averageResponseTime = 0
        imageAvailability = 0.0
        dataCompleteness = 0.0
        lastCacheAge = 0
        cacheHits = 0
        cacheMisses = 0
        responseTimes.removeAll()
    }

    /// Debug description
    public var debugDescription: String {
        """
        📊 Cache Health Metrics:
        - Hit Rate: \(Int(cacheHitRate * 100))%
        - Avg Response: \(Int(averageResponseTime))ms
        - Image Availability: \(Int(imageAvailability * 100))%
        - Data Completeness: \(Int(dataCompleteness * 100))%
        - Last Cache Age: \(Int(lastCacheAge))s
        """
    }
}
