import Foundation
import OSLog

/// Service for logging application analytics events.
/// This acts as a wrapper around the underlying analytics implementation (currently OSLog),
/// allowing for easy swap to a real SDK (e.g., Firebase, Mixpanel) in the future.
@MainActor
public final class AnalyticsService {
    public static let shared = AnalyticsService()

    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "Analytics")

    private init() {}

    /// Log an analytics event with optional properties.
    /// - Parameters:
    ///   - name: The name of the event to log.
    ///   - parameters: A dictionary of properties associated with the event.
    public func logEvent(_ name: String, parameters: [String: Any] = [:]) {
        if parameters.isEmpty {
            logger.info("📊 Event: \(name, privacy: .public)")
        } else {
            // Convert dictionary to string for logging purposes.
            // Using a simple description for values is sufficient for basic logging.
            let props = parameters.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            logger.info("📊 Event: \(name, privacy: .public) | Properties: [\(props, privacy: .public)]")
        }
    }
}
