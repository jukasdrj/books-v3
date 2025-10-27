import Foundation
#if os(iOS)
import UIKit

/// Extension for HTTP polling fallback (DEPRECATED - WebSocket-only now)
/// This entire file is deprecated and will be removed in future versions.
/// The monolith refactor eliminates polling in favor of WebSocket-only progress updates.
extension BookshelfAIService {

    /// Process bookshelf image using HTTP polling (DEPRECATED - WebSocket-only now)
    /// - Parameters:
    ///   - image: UIImage to process
    ///   - jobId: Pre-generated job identifier
    ///   - provider: AI provider (Gemini or Cloudflare)
    ///   - progressHandler: Closure for progress updates (called every 2s)
    /// - Returns: Tuple of detected books and suggestions
    /// - Throws: BookshelfAIError for failures
    @available(*, deprecated, message: "Polling removed - WebSocket-only architecture")
    internal func processViaPolling(
        image: UIImage,
        jobId: String,
        provider: AIProvider,
        progressHandler: @MainActor @escaping (Double, String) -> Void
    ) async throws(BookshelfAIError) -> ([DetectedBook], [SuggestionViewModel]) {
        print("📊 Using HTTP polling fallback for job \(jobId)")

        // STEP 1: Compress image
        let config = provider.preprocessingConfig
        let processedImage = image.resizeForAI(maxDimension: config.maxDimension)

        guard let compressedData = processedImage.jpegData(compressionQuality: 0.8) else {
            throw .imageCompressionFailed
        }

        // STEP 2: Upload image
        // UPDATED: Use unified api-worker endpoint
        let baseURL = "https://api-worker.jukasdrj.workers.dev"
        let uploadURL = URL(string: "\(baseURL)/api/scan-bookshelf?jobId=\(jobId)")!
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue(provider.rawValue, forHTTPHeaderField: "X-AI-Provider")
        uploadRequest.httpBody = compressedData

        do {
            let (_, response) = try await URLSession.shared.data(for: uploadRequest)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw BookshelfAIError.serverError(500, "Upload failed")
            }
            print("✅ Image uploaded with jobId: \(jobId) (polling mode)")
        } catch {
            throw .networkError(error)
        }

        // STEP 3: Poll for status every 2 seconds
        let maxPolls = 40  // 40 polls * 2s = 80s timeout
        var pollCount = 0

        while pollCount < maxPolls {
            pollCount += 1

            do {
                let status = try await pollJobStatus(jobId: jobId)

                // Calculate progress from stage
                let (progress, statusMessage) = mapStageToProgress(stage: status.stage, elapsed: status.elapsedTime)

                await MainActor.run {
                    progressHandler(progress, statusMessage)
                }

                print("📊 Poll #\(pollCount): \(Int(progress * 100))% - \(statusMessage)")

                // Check if complete
                if let result = status.result {
                    print("✅ Polling complete after \(pollCount) polls")

                    let detectedBooks = result.books.compactMap { aiBook in
                        self.convertToDetectedBook(aiBook)
                    }
                    let suggestions = SuggestionGenerator.generateSuggestions(from: result)

                    return (detectedBooks, suggestions)
                }

                // Check if errored
                if let error = status.error {
                    throw BookshelfAIError.serverError(500, "Job failed: \(error)")
                }

                // Wait 2 seconds before next poll
                try await Task.sleep(for: .seconds(2))

            } catch {
                throw .networkError(error)
            }
        }

        // Timeout after maxPolls
        throw BookshelfAIError.serverError(408, "Polling timeout after \(pollCount) polls")
    }

    /// Map stage string to progress percentage and display message
    private func mapStageToProgress(stage: String, elapsed: Int) -> (Double, String) {
        switch stage.lowercased() {
        case "uploading":
            return (0.1, "Uploading image...")
        case "analyzing":
            return (0.3, "Analyzing image quality...")
        case "processing":
            return (0.5, "Processing with AI...")
        case "extracting":
            return (0.7, "Extracting book details...")
        case "complete", "completed":
            return (1.0, "Complete!")
        default:
            // Estimate based on elapsed time (typical: 25-40s)
            let estimatedProgress = min(0.9, Double(elapsed) / 40.0)
            return (estimatedProgress, "Processing... (\(elapsed)s)")
        }
    }
}

#endif  // os(iOS)

