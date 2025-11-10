import Foundation
#if canImport(UIKit)
import UIKit

/// Service for compressing images to meet size constraints.
/// Uses adaptive cascade strategy for optimal quality/size balance.
/// Extracted from BookshelfAIService for reusability.
public struct ImageCompressionService {

    // MARK: - Initialization

    public init() {}

    // MARK: - Compression

    /// Compress image to fit within size limit using adaptive cascade.
    /// - Parameters:
    ///   - image: UIImage to compress
    ///   - maxSizeBytes: Maximum size in bytes
    /// - Returns: Compressed JPEG data, or nil if compression fails
    public func compress(_ image: UIImage, maxSizeBytes: Int) -> Data? {
        // Adaptive cascade: Try each resolution + quality combination
        let compressionStrategies: [(resolution: CGFloat, qualities: [CGFloat])] = [
            (1920, [0.9, 0.85, 0.8, 0.75, 0.7]),   // Ultra HD
            (1280, [0.85, 0.8, 0.75, 0.7, 0.6]),   // Full HD
            (960,  [0.8, 0.75, 0.7, 0.6, 0.5]),    // HD
            (800,  [0.7, 0.6, 0.5, 0.4])           // VGA (emergency)
        ]

        // Try each resolution cascade
        for (resolution, qualities) in compressionStrategies {
            // Resize image once per resolution
            let resizedImage = image.resizeForAI(maxDimension: resolution)

            // Try quality levels for this resolution
            for quality in qualities {
                if let data = resizedImage.jpegData(compressionQuality: quality),
                   data.count <= maxSizeBytes {
                    #if DEBUG
                    let compressionRatio = Double(data.count) / Double(maxSizeBytes) * 100.0
                    print("[Compression] ✅ Success: \(Int(resolution))px @ \(Int(quality * 100))% quality = \(data.count / 1000)KB (\(String(format: "%.1f", compressionRatio))% of limit)")
                    #endif
                    return data
                }
            }
        }

        // Absolute fallback: Minimal quality thumbnail
        // Should only reach here with extremely problematic images
        let fallbackImage = image.resizeForAI(maxDimension: 640)
        if let data = fallbackImage.jpegData(compressionQuality: 0.3) {
            #if DEBUG
            print("[Compression] ⚠️ Fallback: 640px @ 30% quality = \(data.count / 1000)KB (last resort)")
            #endif
            return data
        }

        #if DEBUG
        print("[Compression] ❌ Failed to compress image within \(maxSizeBytes / 1_000_000)MB limit")
        #endif
        return nil
    }
}
#endif
