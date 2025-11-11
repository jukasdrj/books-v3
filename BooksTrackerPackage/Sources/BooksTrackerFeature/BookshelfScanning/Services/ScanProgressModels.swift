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
    public let token: String  // NEW: Auth token for WebSocket
    public let stages: [StageMetadata]
    public let estimatedRange: [Int]  // [min, max] seconds

    public struct StageMetadata: Codable, Sendable {
        public let name: String
        public let typicalDuration: Int  // seconds
        public let progress: Double      // 0.0 - 1.0
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
