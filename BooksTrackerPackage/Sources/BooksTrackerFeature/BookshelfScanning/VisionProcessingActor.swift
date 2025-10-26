import Foundation
import SwiftUI

#if canImport(Vision)
import Vision
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Vision Processing Actor

/// Global actor for Vision framework operations (on-device OCR and rectangle detection)
/// All Vision API calls are isolated to this actor for thread safety and performance
@globalActor
public actor VisionProcessingActor {
    public static let shared = VisionProcessingActor()

    private init() {}

    // MARK: - Book Spine Detection

    /// Detect book spines from a bookshelf photo
    /// Phase 1: Detect rectangles → Phase 2: OCR text → Phase 3: Parse metadata
    #if canImport(UIKit)
    public func detectBooks(in images: [UIImage]) async throws -> [DetectedBook] {
        var allDetectedBooks: [DetectedBook] = []

        for image in images {
            // Step 1: Detect potential book spines (vertical rectangles)
            let spineRegions = try await detectBookSpines(in: image)

            // Step 2: OCR each detected spine region
            for (index, region) in spineRegions.enumerated() {
                guard let croppedImage = cropImage(image, to: region) else {
                    continue
                }

                let ocrResult = try await recognizeText(in: croppedImage)

                // Step 3: Parse book metadata from OCR text
                let detectedBook = parseBookMetadata(
                    from: ocrResult.text,
                    confidence: ocrResult.confidence,
                    boundingBox: region,
                    index: index
                )

                allDetectedBooks.append(detectedBook)
            }
        }

        return allDetectedBooks
    }
    #endif

    // MARK: - Rectangle Detection (Book Spines)

    /// Detect vertical rectangles that likely represent book spines
    #if canImport(UIKit)
    private func detectBookSpines(in image: UIImage) async throws -> [CGRect] {
        guard let cgImage = image.cgImage else {
            throw VisionError.invalidImage
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CGRect], Error>) in
            let request = VNDetectRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRectangleObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                // Filter for vertical rectangles (book spines)
                // Note: self access is safe here as VNDetectRectanglesRequest is @Sendable
                let spines = observations
                    .filter { observation in
                        let box = observation.boundingBox
                        let aspectRatio = box.width / box.height
                        return aspectRatio < 0.5 && box.height > 0.1 && observation.confidence > 0.6
                    }
                    .map { $0.boundingBox }

                continuation.resume(returning: spines)
            }

            // Configure for book spine detection
            request.minimumAspectRatio = 0.15  // Very narrow rectangles
            request.maximumAspectRatio = 0.5   // Not too wide
            request.minimumSize = 0.05         // At least 5% of image
            request.quadratureTolerance = 15.0 // Allow perspective distortion
            request.minimumConfidence = 0.6    // Moderate confidence threshold

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    #endif

    /// Determine if a rectangle observation is likely a book spine
    private func isLikelyBookSpine(_ observation: VNRectangleObservation) -> Bool {
        let box = observation.boundingBox
        let aspectRatio = box.width / box.height

        // Book spines are tall and narrow
        guard aspectRatio < 0.5 else { return false }

        // Must be reasonably sized (not too small)
        guard box.height > 0.1 else { return false }

        // Confidence threshold
        guard observation.confidence > 0.6 else { return false }

        return true
    }

    // MARK: - Text Recognition (OCR)

    /// OCR result with text and confidence
    private struct OCRResult {
        let text: String
        let confidence: Double
    }

    /// Recognize text from an image using Vision framework
    #if canImport(UIKit)
    private func recognizeText(in image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw VisionError.invalidImage
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OCRResult, Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: OCRResult(text: "", confidence: 0.0))
                    return
                }

                // Extract text and calculate average confidence
                var allText: [String] = []
                var confidenceScores: [Float] = []

                for observation in observations {
                    if let candidate = observation.topCandidates(1).first {
                        allText.append(candidate.string)
                        confidenceScores.append(candidate.confidence)
                    }
                }

                let combinedText = allText.joined(separator: " ")
                let avgConfidence = confidenceScores.isEmpty ? 0.0 : Double(confidenceScores.reduce(0, +)) / Double(confidenceScores.count)

                continuation.resume(returning: OCRResult(text: combinedText, confidence: avgConfidence))
            }

            // Configure for best accuracy (book spines require precise OCR)
            request.revision = VNRecognizeTextRequestRevision3  // iOS 26: Live Text technology
            request.recognitionLevel = .accurate               // Deep learning model
            request.recognitionLanguages = ["en-US", "en-GB"]  // Configure per user locale
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.05                   // Filter small text (copyright notices)

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    #endif

    // MARK: - Metadata Parsing

    #if canImport(UIKit)
    /// Parse book metadata (ISBN, title, author) from OCR text
    private func parseBookMetadata(
        from text: String,
        confidence: Double,
        boundingBox: CGRect,
        index: Int
    ) -> DetectedBook {
        // Extract ISBN (13-digit or 10-digit)
        let isbn = extractISBN(from: text)

        // Extract title (usually largest text)
        let title = extractTitle(from: text)

        // Extract author (often prefixed by "by", "BY", or smaller text)
        let author = extractAuthor(from: text)

        // Determine status based on confidence and extracted data
        let status: DetectionStatus
        if confidence < 0.5 {
            status = .uncertain
        } else if isbn != nil || (title != nil && author != nil) {
            status = .detected
        } else {
            status = .uncertain
        }

        return DetectedBook(
            isbn: isbn,
            title: title,
            author: author,
            confidence: confidence,
            boundingBox: boundingBox,
            rawText: text,
            status: status
        )
    }

    /// Extract ISBN from text (13-digit or 10-digit format)
    private func extractISBN(from text: String) -> String? {
        // Pattern: ISBN-13 (978/979 prefix) or ISBN-10
        let patterns = [
            "(?:ISBN(?:-13)?:?\\s*)?([0-9]{13})",        // ISBN-13
            "(?:ISBN(?:-10)?:?\\s*)?([0-9]{9}[0-9X])"   // ISBN-10
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                    if let range = Range(match.range(at: 1), in: text) {
                        let isbn = String(text[range])
                        // Validate ISBN checksum (basic check)
                        if isbn.count == 13 || isbn.count == 10 {
                            return isbn
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Extract book title (heuristic: longest capitalized phrase)
    private func extractTitle(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Find longest line (likely the title)
        let title = lines.max(by: { $0.count < $1.count })

        // Clean up common artifacts
        return title?.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Extract author name (heuristic: line after "by" or secondary text)
    private func extractAuthor(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Look for "by [Author Name]" pattern
        for line in lines {
            if let range = line.range(of: "by ", options: .caseInsensitive) {
                let author = String(line[range.upperBound...])
                if !author.isEmpty {
                    return author
                }
            }
        }

        // Fallback: second-longest line (often the author)
        if lines.count >= 2 {
            let sorted = lines.sorted(by: { $0.count > $1.count })
            return sorted[1]
        }

        return nil
    }
    #endif

    // MARK: - Image Processing Utilities

    /// Crop image to specified bounding box (normalized coordinates 0.0 - 1.0)
    #if canImport(UIKit)
    private func cropImage(_ image: UIImage, to normalizedRect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        // Convert normalized coordinates to pixel coordinates
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        // Vision coordinates: origin at bottom-left, flip Y axis
        let rect = CGRect(
            x: normalizedRect.origin.x * width,
            y: (1.0 - normalizedRect.origin.y - normalizedRect.height) * height,
            width: normalizedRect.width * width,
            height: normalizedRect.height * height
        )

        guard let cropped = cgImage.cropping(to: rect) else { return nil }

        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
    #endif
}

// MARK: - Vision Errors

public enum VisionError: Error, LocalizedError {
    case invalidImage
    case processingFailed(String)
    case noTextDetected

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid image format. Please select a valid photo."
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        case .noTextDetected:
            return "No text detected in image. Try a clearer photo with better lighting."
        }
    }
}

#endif  // canImport(Vision)
