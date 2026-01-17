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

// MARK: - V3 Scan Job Data (inner data from ResponseEnvelope)

/// V3 API response data for POST /v3/jobs/scans
/// This is the inner `data` object from ResponseEnvelope<ScanJobData>
///
/// Backend returns:
/// ```json
/// {
///   "success": true,
///   "data": {
///     "jobId": "uuid",
///     "status": "queued",
///     "streamUrl": "https://api.oooefam.net/v3/jobs/scans/{jobId}/stream",
///     "token": "auth-token"
///   },
///   "metadata": { ... }
/// }
/// ```
public struct ScanJobData: Codable, Sendable {
    public let jobId: String
    public let status: String?
    public let streamUrl: String?   // V3 field name (maps to sseUrl)
    public let token: String?       // V3 field name (maps to authToken)
    public let statusUrl: String?   // Polling fallback endpoint
    public let stages: [StageMetadata]?
    public let estimatedRange: [Int]?

    public struct StageMetadata: Codable, Sendable {
        public let name: String
        public let typicalDuration: Int  // seconds
        public let progress: Double      // 0.0 - 1.0
    }
}

// MARK: - Scan Job Response (from POST /scan)

/// Unified scan job response that works with both V3 ResponseEnvelope and legacy flat responses.
/// Use `ScanJobResponse.decode(from:)` for proper handling.
public struct ScanJobResponse: Codable, Sendable {
    public let jobId: String
    public let authToken: String  // Auth token for SSE/WebSocket (canonical)

    /// **DEPRECATED:** Use `authToken` instead. Removal: March 1, 2026
    /// Kept for API backward compatibility only - always nil in new code
    public let token: String?

    // API Contract v3.2: SSE endpoints
    public let sseUrl: String?      // SSE stream endpoint (preferred) - V3 returns as "streamUrl"
    public let statusUrl: String?   // Polling fallback endpoint
    public let status: String?      // V3 job status field (e.g., "initialized")

    /// **DEPRECATED:** WebSocket is V1/V2 legacy only. V3 uses SSE exclusively. Removal: 90 days post-V3 GA
    /// Kept for API backward compatibility only - always nil in new code
    public let websocketUrl: String?

    public let stages: [ScanJobData.StageMetadata]?  // Optional for V3 (may not be present initially)
    public let estimatedRange: [Int]?    // Optional for V3 - [min, max] seconds

    // MARK: - V3 ResponseEnvelope Decoding

    /// Decode from V3 API response (wrapped in ResponseEnvelope)
    /// This is the preferred method for V3 API responses.
    ///
    /// - Parameter data: Raw JSON data from the API
    /// - Returns: ScanJobResponse with mapped fields
    /// - Throws: DecodingError if response cannot be decoded
    public static func decode(from data: Data) throws -> ScanJobResponse {
        let decoder = JSONDecoder()

        // Try V3 ResponseEnvelope format first
        if let envelope = try? decoder.decode(ApiResponse<ScanJobData>.self, from: data) {
            switch envelope {
            case .success(let scanData, _):
                return ScanJobResponse(
                    jobId: scanData.jobId,
                    authToken: scanData.token ?? "",  // Map token → authToken
                    sseUrl: scanData.streamUrl,       // Map streamUrl → sseUrl
                    statusUrl: scanData.statusUrl,
                    status: scanData.status,
                    stages: scanData.stages,
                    estimatedRange: scanData.estimatedRange
                )
            case .failure(let error, _):
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "API error: \(error.message ?? "Unknown error") (code: \(error.code ?? "unknown"))"
                    )
                )
            }
        }

        // Fall back to legacy flat format
        return try decoder.decode(ScanJobResponse.self, from: data)
    }

    // MARK: - Memberwise Init

    public init(
        jobId: String,
        authToken: String,
        sseUrl: String?,
        statusUrl: String?,
        status: String?,
        stages: [ScanJobData.StageMetadata]?,
        estimatedRange: [Int]?
    ) {
        self.jobId = jobId
        self.authToken = authToken
        self.token = nil  // Deprecated, always nil
        self.sseUrl = sseUrl
        self.statusUrl = statusUrl
        self.status = status
        self.websocketUrl = nil  // Deprecated, always nil
        self.stages = stages
        self.estimatedRange = estimatedRange
    }

    // MARK: - Legacy Flat Response Decoding

    // Custom decoding to handle legacy flat response format
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        jobId = try container.decode(String.self, forKey: .jobId)

        // V3 fields (optional)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        stages = try container.decodeIfPresent([ScanJobData.StageMetadata].self, forKey: .stages)
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

        // token property is deprecated - no longer populated
        token = nil
    }

    // Custom encoding (encode with authToken only, deprecated fields omitted)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(jobId, forKey: .jobId)
        try container.encode(authToken, forKey: .authToken)
        // token is deprecated - no longer encoded
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(stages, forKey: .stages)
        try container.encodeIfPresent(estimatedRange, forKey: .estimatedRange)
        try container.encodeIfPresent(sseUrl, forKey: .sseUrl)
        try container.encodeIfPresent(statusUrl, forKey: .statusUrl)
        // websocketUrl is deprecated - no longer encoded
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
