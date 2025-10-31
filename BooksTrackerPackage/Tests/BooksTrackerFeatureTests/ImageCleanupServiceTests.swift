//
//  ImageCleanupServiceTests.swift
//  BooksTrackerFeatureTests
//
//  Tests for ImageCleanupService including orphaned file cleanup
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@Suite("Image Cleanup Service Tests")
@MainActor
struct ImageCleanupServiceTests {

    @Test func cleansUpOrphanedFilesOlderThan24Hours() async throws {
        // Setup in-memory SwiftData container
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        // Create an orphaned temp file (not referenced by any Work)
        let tempDir = FileManager.default.temporaryDirectory
        let orphanedFilename = "bookshelf_scan_\(UUID().uuidString).jpg"
        let orphanedFileURL = tempDir.appendingPathComponent(orphanedFilename)

        // Create a dummy image file
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG header
        try imageData.write(to: orphanedFileURL)

        // Set file modification date to 25 hours ago (older than 24-hour threshold)
        let attributes = [FileAttributeKey.modificationDate: Date().addingTimeInterval(-25 * 3600)]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: orphanedFileURL.path)

        // Verify file exists before cleanup
        #expect(FileManager.default.fileExists(atPath: orphanedFileURL.path))

        // Run orphaned file cleanup
        await ImageCleanupService.shared.cleanupOrphanedFiles(in: context, olderThan: 24 * 3600)

        // Verify orphaned file was deleted
        #expect(!FileManager.default.fileExists(atPath: orphanedFileURL.path))
    }

    @Test func doesNotDeleteOrphanedFilesYoungerThan24Hours() async throws {
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        // Create an orphaned temp file (not referenced by any Work)
        let tempDir = FileManager.default.temporaryDirectory
        let recentFilename = "bookshelf_scan_\(UUID().uuidString).jpg"
        let recentFileURL = tempDir.appendingPathComponent(recentFilename)

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        try imageData.write(to: recentFileURL)

        // Set file modification date to 12 hours ago (younger than 24-hour threshold)
        let attributes = [FileAttributeKey.modificationDate: Date().addingTimeInterval(-12 * 3600)]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: recentFileURL.path)

        // Verify file exists before cleanup
        #expect(FileManager.default.fileExists(atPath: recentFileURL.path))

        // Run orphaned file cleanup
        await ImageCleanupService.shared.cleanupOrphanedFiles(in: context, olderThan: 24 * 3600)

        // Verify recent file was NOT deleted
        #expect(FileManager.default.fileExists(atPath: recentFileURL.path))

        // Cleanup test file
        try? FileManager.default.removeItem(at: recentFileURL)
    }

    @Test func doesNotDeleteFilesReferencedByWorks() async throws {
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        // Create a temp file referenced by a Work
        let tempDir = FileManager.default.temporaryDirectory
        let referencedFilename = "bookshelf_scan_\(UUID().uuidString).jpg"
        let referencedFileURL = tempDir.appendingPathComponent(referencedFilename)

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        try imageData.write(to: referencedFileURL)

        // Set file modification date to 25 hours ago
        let attributes = [FileAttributeKey.modificationDate: Date().addingTimeInterval(-25 * 3600)]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: referencedFileURL.path)

        // Create a Work that references this file
        let work = Work(title: "Test Book", originalLanguage: "English", firstPublicationYear: nil)
        work.originalImagePath = referencedFileURL.path
        work.reviewStatus = .needsReview
        context.insert(work)
        try context.save()

        // Verify file exists before cleanup
        #expect(FileManager.default.fileExists(atPath: referencedFileURL.path))

        // Run orphaned file cleanup
        await ImageCleanupService.shared.cleanupOrphanedFiles(in: context, olderThan: 24 * 3600)

        // Verify referenced file was NOT deleted (even though it's old)
        #expect(FileManager.default.fileExists(atPath: referencedFileURL.path))

        // Cleanup test file
        try? FileManager.default.removeItem(at: referencedFileURL)
    }
}
