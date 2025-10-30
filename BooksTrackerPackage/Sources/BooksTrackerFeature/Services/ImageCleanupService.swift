//
//  ImageCleanupService.swift
//  BooksTrackerFeature
//
//  Automatic cleanup of temporary bookshelf scan images after review
//

import Foundation
import SwiftData

/// Service for cleaning up temporary bookshelf scan images
/// when all associated books have been reviewed
@MainActor
public class ImageCleanupService {

    /// Shared singleton instance
    public static let shared = ImageCleanupService()

    private init() {}

    // MARK: - Cleanup

    /// Clean up temporary images where all associated works have been reviewed
    /// Call this on app launch to maintain clean temporary storage
    public func cleanupReviewedImages(in modelContext: ModelContext) async {
        do {
            // Fetch all works that have temporary image references
            let descriptor = FetchDescriptor<Work>()
            let allWorks = try modelContext.fetch(descriptor)

            // Group works by their original image path
            let worksWithImages = allWorks.filter { $0.originalImagePath != nil }
            let groupedByImage = Dictionary(grouping: worksWithImages) { $0.originalImagePath! }

            var cleanedCount = 0
            var errorCount = 0

            // Process each image group
            for (imagePath, works) in groupedByImage {
                // Check if all books from this scan have been reviewed
                let allReviewed = works.allSatisfy { work in
                    work.reviewStatus == .verified || work.reviewStatus == .userEdited
                }

                if allReviewed {
                    // Delete the temporary image file
                    if await deleteImageFile(at: imagePath) {
                        // Clear references from all works
                        for work in works {
                            work.originalImagePath = nil
                            work.boundingBox = nil
                        }
                        cleanedCount += 1
                        print("✅ ImageCleanupService: Deleted \(imagePath) (\(works.count) books reviewed)")
                    } else {
                        errorCount += 1
                        print("⚠️ ImageCleanupService: Failed to delete \(imagePath)")
                    }
                }
            }

            // Save changes if any cleanup occurred
            if cleanedCount > 0 {
                try modelContext.save()
                print("🧹 ImageCleanupService: Cleaned up \(cleanedCount) image(s), \(errorCount) error(s)")
            } else {
                print("🧹 ImageCleanupService: No images ready for cleanup")
            }

        } catch {
            print("❌ ImageCleanupService: Failed to cleanup images - \(error)")
        }
    }

    // MARK: - File Operations

    /// Delete image file at specified path
    /// Returns true if successful or file doesn't exist
    private func deleteImageFile(at path: String) async -> Bool {
        let fileManager = FileManager.default

        // Check if file exists
        guard fileManager.fileExists(atPath: path) else {
            // File already deleted - consider this success
            return true
        }

        do {
            try fileManager.removeItem(atPath: path)
            return true
        } catch {
            print("❌ ImageCleanupService: File deletion error - \(error)")
            return false
        }
    }

    // MARK: - Statistics

    /// Get count of temporary images awaiting cleanup
    public func getPendingCleanupCount(in modelContext: ModelContext) -> Int {
        do {
            let descriptor = FetchDescriptor<Work>()
            let allWorks = try modelContext.fetch(descriptor)

            // Group by image path
            let worksWithImages = allWorks.filter { $0.originalImagePath != nil }
            let groupedByImage = Dictionary(grouping: worksWithImages) { $0.originalImagePath! }

            // Count images where all books are reviewed
            return groupedByImage.filter { _, works in
                works.allSatisfy { $0.reviewStatus == .verified || $0.reviewStatus == .userEdited }
            }.count

        } catch {
            print("❌ ImageCleanupService: Failed to get pending count - \(error)")
            return 0
        }
    }

    /// Get count of temporary images still in use (books under review)
    public func getActiveImageCount(in modelContext: ModelContext) -> Int {
        do {
            let descriptor = FetchDescriptor<Work>()
            let allWorks = try modelContext.fetch(descriptor)

            // Group by image path
            let worksWithImages = allWorks.filter { $0.originalImagePath != nil }
            let groupedByImage = Dictionary(grouping: worksWithImages) { $0.originalImagePath! }

            // Count images with at least one book needing review
            return groupedByImage.filter { _, works in
                works.contains { $0.reviewStatus == .needsReview }
            }.count

        } catch {
            print("❌ ImageCleanupService: Failed to get active count - \(error)")
            return 0
        }
    }

    // MARK: - Orphaned File Cleanup

    /// Clean up orphaned temp files not referenced by any Work
    /// Call this on app launch to handle files from failed scans
    /// - Parameters:
    ///   - modelContext: SwiftData context for checking Work references
    ///   - olderThan: Age threshold in seconds (default 24 hours)
    public func cleanupOrphanedFiles(in modelContext: ModelContext, olderThan age: TimeInterval = 86400) async {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory

        do {
            // Get all files in temp directory
            let contents = try fileManager.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            // Filter for bookshelf scan images
            let scanImages = contents.filter { $0.lastPathComponent.hasPrefix("bookshelf_scan_") && $0.pathExtension == "jpg" }

            // Get all referenced image paths from Works
            let descriptor = FetchDescriptor<Work>()
            let allWorks = try modelContext.fetch(descriptor)
            let referencedPaths = Set(allWorks.compactMap { $0.originalImagePath })

            var cleanedCount = 0
            var skippedCount = 0

            for imageURL in scanImages {
                let imagePath = imageURL.path

                // Skip if referenced by any Work
                if referencedPaths.contains(imagePath) {
                    skippedCount += 1
                    continue
                }

                // Check file age
                let attributes = try fileManager.attributesOfItem(atPath: imagePath)
                guard let modificationDate = attributes[.modificationDate] as? Date else {
                    continue
                }

                let fileAge = Date().timeIntervalSince(modificationDate)
                if fileAge > age {
                    // Delete orphaned old file
                    try fileManager.removeItem(at: imageURL)
                    cleanedCount += 1
                    print("🧹 ImageCleanupService: Deleted orphaned file \(imageURL.lastPathComponent) (age: \(Int(fileAge / 3600))h)")
                }
            }

            if cleanedCount > 0 || skippedCount > 0 {
                print("🧹 ImageCleanupService: Orphaned file cleanup complete - deleted: \(cleanedCount), skipped: \(skippedCount) (referenced)")
            }

        } catch {
            print("❌ ImageCleanupService: Orphaned file cleanup failed - \(error)")
        }
    }
}
