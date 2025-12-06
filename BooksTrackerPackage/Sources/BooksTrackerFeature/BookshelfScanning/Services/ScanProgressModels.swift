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
    public let authToken: String  // Auth token for SSE/WebSocket (canonical)

    @available(*, deprecated, message: "Use authToken instead. Removal: March 1, 2026")
    public let token: String?  // Deprecated field, backward compatibility only

    // API Contract v3.2: SSE endpoints
    public let sseUrl: String?      // SSE stream endpoint (preferred) - V3 returns as "streamUrl"
    public let statusUrl: String?   // Polling fallback endpoint
    public let status: String?      // V3 job status field (e.g., "initialized")

    // Deprecated WebSocket endpoint (V1/V2 legacy only)
    @available(*, deprecated, message: "WebSocket is V1/V2 legacy only. V3 uses SSE exclusively. Removal: 90 days post-V3 GA")
    public let websocketUrl: String?

    public let stages: [StageMetadata]?  // Optional for V3 (may not be present initially)
    public let estimatedRange: [Int]?    // Optional for V3 - [min, max] seconds

    public struct StageMetadata: Codable, Sendable {
        public let name: String
        public let typicalDuration: Int  // seconds
        public let progress: Double      // 0.0 - 1.0
    }

    // Custom decoding to handle both V3 and legacy response formats
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        jobId = try container.decode(String.self, forKey: .jobId)

        // V3 fields (optional)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        stages = try container.decodeIfPresent([StageMetadata].self, forKey: .stages)
        estimatedRange = try container.decodeIfPresent([Int].self, forKey: .estimatedRange)

        // Decode SSE/WebSocket URLs (API Contract v3.2)
        // V3 returns "streamUrl", legacy returns "sseUrl" - support both
        if let streamUrl = try? container.decode(String.self, forKey: .streamUrl) {
            sseUrl = streamUrl  // V3 format
        } else {
            sseUrl = try container.decodeIfPresent(String.self, forKey: .sseUrl)  // Legacy format
        }

        statusUrl = try container.decodeIfPresent(String.self, forKey: .statusUrl)
        websocketUrl = try container.decodeIfPresent(String.self, forKey: .websocketUrl)

        // Prefer authToken, fallback to token for legacy responses
        // V3 doesn't return authToken initially - it's embedded in the streamUrl or provided separately
        if let authTokenValue = try? container.decode(String.self, forKey: .authToken) {
            authToken = authTokenValue
        } else if let tokenValue = try? container.decode(String.self, forKey: .token) {
            // Legacy response - only has token field
            authToken = tokenValue
        } else {
            // V3 may not include authToken in initial response - use empty string as placeholder
            // The SSE stream URL itself provides authentication
            authToken = ""
        }

        // token property is deprecated - decode from JSON if present, otherwise nil
        token = try? container.decode(String.self, forKey: .token)
    }

    // Custom encoding (encode as legacy format for backward compatibility)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(jobId, forKey: .jobId)
        try container.encode(authToken, forKey: .authToken)
        try container.encodeIfPresent(token, forKey: .token)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(stages, forKey: .stages)
        try container.encodeIfPresent(estimatedRange, forKey: .estimatedRange)
        try container.encodeIfPresent(sseUrl, forKey: .sseUrl)
        try container.encodeIfPresent(statusUrl, forKey: .statusUrl)
        try container.encodeIfPresent(websocketUrl, forKey: .websocketUrl)
    }

    private enum CodingKeys: String, CodingKey {
        case jobId, authToken, token, status, stages, estimatedRange
        case sseUrl, streamUrl, statusUrl, websocketUrl  // API Contract v3.2 + V3
    }
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
