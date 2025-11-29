import Foundation

/// Errors specific to polling operations
public enum PollingError: Error, LocalizedError, Sendable {
    case maxAttemptsReached
    case cancelled
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .maxAttemptsReached:
            return "Polling reached maximum attempts without completion."
        case .cancelled:
            return "Polling was cancelled."
        case .apiError(let message):
            return "Polling failed with API error: \(message)"
        }
    }
}

/// Utility for creating polling-based AsyncThrowingStream
/// Used as fallback when SSE is not available (backward compatibility)
public struct PollingUtility {
    /// Creates an AsyncThrowingStream that periodically calls a given closure.
    /// Polling stops when the closure returns `nil` (indicating no more data or task completion),
    /// or when `isCompleted` evaluates to `true` based on the last received value.
    ///
    /// - Parameters:
    ///   - initialDelay: Small initial delay before first poll (default: 0.5 seconds)
    ///   - interval: Time between polling attempts (default: 3.0 seconds)
    ///   - maxAttempts: Maximum number of polling attempts (nil = unlimited)
    ///   - perform: Closure that encapsulates the API call and returns the data, or nil to stop
    ///   - isCompleted: Condition to check if polling should stop based on the received value
    ///
    /// - Returns: AsyncThrowingStream of the polled data type
    public static func createStream<T: Sendable>(
        initialDelay: TimeInterval = 0.5, // Small initial delay before first poll
        interval: TimeInterval = 3.0,
        maxAttempts: Int? = nil,
        // The `perform` closure should encapsulate the API call and return the data, or nil to stop.
        perform: @escaping @Sendable () async throws -> T?,
        // A condition to check if polling should stop based on the received value.
        // E.g., for a job status, `isCompleted: { $0.status == "COMPLETED" || $0.status == "FAILED" }`
        isCompleted: @escaping @Sendable (T) -> Bool
    ) -> AsyncThrowingStream<T, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(for: .seconds(initialDelay))
                } catch {
                    continuation.finish(throwing: PollingError.cancelled)
                    return
                }

                var attempts = 0
                while !Task.isCancelled {
                    if let maxAttempts = maxAttempts, attempts >= maxAttempts {
                        continuation.finish(throwing: PollingError.maxAttemptsReached)
                        return
                    }

                    do {
                        let result = try await perform()
                        if let value = result {
                            continuation.yield(value)
                            if isCompleted(value) {
                                continuation.finish()
                                return
                            }
                        } else {
                            // If perform returns nil, it implies no more data or task is done.
                            continuation.finish()
                            return
                        }
                    } catch {
                        continuation.finish(throwing: PollingError.apiError(error.localizedDescription))
                        return
                    }

                    attempts += 1
                    do {
                        try await Task.sleep(for: .seconds(interval))
                    } catch {
                        continuation.finish(throwing: PollingError.cancelled)
                        return
                    }
                }
                continuation.finish(throwing: PollingError.cancelled)
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
