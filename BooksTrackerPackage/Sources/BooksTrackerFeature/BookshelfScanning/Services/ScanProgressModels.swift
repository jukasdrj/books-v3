import Foundation

#if canImport(UIKit)

// MARK: - PollableJob Implementation

/// Metadata for bookshelf scan polling
public struct BookshelfScanMetadata: Sendable {
    public let booksDetected: Int
    public let serverElapsedTime: Int

    public init(booksDetected: Int, serverElapsedTime: Int) {
        self.booksDetected = booksDetected
        self.serverElapsedTime = serverElapsedTime
    }
}

// MARK: - Scan Job Response (from POST /scan)

public struct ScanJobResponse: Codable, Sendable {
    public let jobId: String
    public let authToken: String  // Auth token for WebSocket (canonical)

    @available(*, deprecated, message: "Use authToken instead. Removal: March 1, 2026")
    public let token: String?  // Deprecated field, backward compatibility only

    public let stages: [StageMetadata]
    public let estimatedRange: [Int]  // [min, max] seconds

    public struct StageMetadata: Codable, Sendable {
        public let name: String
        public let typicalDuration: Int  // seconds
        public let progress: Double      // 0.0 - 1.0
    }

    // Custom decoding to handle both authToken and token fields
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        jobId = try container.decode(String.self, forKey: .jobId)
        stages = try container.decode([StageMetadata].self, forKey: .stages)
        estimatedRange = try container.decode([Int].self, forKey: .estimatedRange)

        // Prefer authToken, fallback to token for legacy responses
        let decodedAuthToken = try? container.decode(String.self, forKey: .authToken)
        let decodedToken = try? container.decode(String.self, forKey: .token)

        if let authTokenValue = decodedAuthToken {
            authToken = authTokenValue
            token = decodedToken  // Optional, may be present
        } else if let tokenValue = decodedToken {
            // Legacy response - only has token field
            authToken = tokenValue
            token = tokenValue
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.authToken,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected authToken or token field"
                )
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case jobId, authToken, token, stages, estimatedRange
    }
}

// MARK: - Job Status Response (from GET /scan/status/:jobId)

public struct JobStatusResponse: Codable, Sendable {
    public let stage: String
    public let elapsedTime: Int      // Server time (source of truth)
    public let booksDetected: Int
    public let result: BookshelfAIResponse?
    public let error: String?
}

// MARK: - Progress State (iOS-side)

@MainActor
@Observable
public class ScanProgressState {
    public var currentStage: String = "uploading"
    public var progress: Double = 0.0
    public var estimatedRange: [Int] = [40, 70]
    public var elapsedTime: Int = 0         // From server
    public var localElapsedTime: Double = 0 // From local timer
    public var booksDetected: Int = 0

    public var stageDisplayName: String {
        switch currentStage {
        case "uploading": return "Uploading image"
        case "analyzing": return "Analyzing with AI"
        case "enriching": return "Enriching metadata"
        case "complete": return "Complete"
        default: return "Processing"
        }
    }

    public var progressPercentage: Int {
        Int(progress * 100)
    }

    public var estimatedRemainingText: String {
        let min = max(0, estimatedRange[0] - elapsedTime)
        let max = max(0, estimatedRange[1] - elapsedTime)

        if min <= 0 && max <= 0 {
            return "Almost done"
        } else if min < 10 {
            return "A few seconds"
        } else if max - min < 10 {
            return "About \(max)s remaining"
        } else {
            return "\(min)-\(max)s remaining"
        }
    }

    public init() {}
}

#endif  // canImport(UIKit)
