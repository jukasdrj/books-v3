import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

/// Tests for DTOMapper PersistentIdentifier cache behavior
/// Issue: https://github.com/jukasdrj/books-tracker-v1/issues/168
@MainActor
struct DTOMapperCacheTests {

    // MARK: - Test Infrastructure

    /// Create in-memory ModelContainer for testing
    private func makeTestContainer() throws -> ModelContainer {
        let schema = Schema([Work.self, Edition.self, Author.self, UserLibraryEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Create test WorkDTO with specific volumeIDs
    private func makeTestWorkDTO(
        title: String = "Test Work",
        volumeIDs: [String] = ["test-volume-1"]
    ) -> WorkDTO {
        return WorkDTO(
            title: title,
            subjectTags: [],
            originalLanguage: "en",
            firstPublicationYear: 2024,
            description: nil,
            synthetic: false,
            primaryProvider: "google-books",
            contributors: ["google-books"],
            openLibraryID: nil,
            openLibraryWorkID: nil,
            isbndbID: nil,
            googleBooksVolumeID: volumeIDs.first,
            goodreadsID: nil,
            goodreadsWorkIDs: [],
            amazonASINs: [],
            librarythingIDs: [],
            googleBooksVolumeIDs: volumeIDs,
            lastISBNDBSync: nil,
            isbndbQuality: 0,
            reviewStatus: .verified,
            originalImagePath: nil,
            boundingBox: nil
        )
    }

    // MARK: - Cache Hit Tests

    @Test("Cache hit with valid Work returns existing Work")
    func cacheHitWithValidWork() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)

        // Create first Work with volumeID "vol-123"
        let dto1 = makeTestWorkDTO(title: "First Work", volumeIDs: ["vol-123"])
        let work1 = try mapper.mapToWork(dto1)

        // Create second DTO with same volumeID
        let dto2 = makeTestWorkDTO(title: "Second Work", volumeIDs: ["vol-123"])
        let work2 = try mapper.mapToWork(dto2)

        // Should return same Work (deduplication)
        #expect(work1.persistentModelID == work2.persistentModelID)
        #expect(work1.title == "First Work")  // Original title preserved
    }

    @Test("Cache hit with multiple volumeIDs returns Work on any match")
    func cacheHitWithMultipleVolumeIDs() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)

        // Create Work with 3 volumeIDs
        let dto1 = makeTestWorkDTO(title: "Multi-Volume Work", volumeIDs: ["vol-1", "vol-2", "vol-3"])
        let work1 = try mapper.mapToWork(dto1)

        // Search by different volumeID
        let dto2 = makeTestWorkDTO(title: "Should Find Existing", volumeIDs: ["vol-2"])
        let work2 = try mapper.mapToWork(dto2)

        #expect(work1.persistentModelID == work2.persistentModelID)
    }

    // MARK: - Stale Entry Tests

    @Test("Cache automatically evicts deleted Work and creates new one")
    func cacheEvictsDeletedWork() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)

        // Create Work
        let dto1 = makeTestWorkDTO(title: "Original Work", volumeIDs: ["vol-deleted"])
        let work1 = try mapper.mapToWork(dto1)
        let originalID = work1.persistentModelID

        // Delete Work from ModelContext
        context.delete(work1)
        try context.save()

        // Create new DTO with same volumeID
        let dto2 = makeTestWorkDTO(title: "New Work After Deletion", volumeIDs: ["vol-deleted"])
        let work2 = try mapper.mapToWork(dto2)

        // Should create NEW Work (not return deleted one)
        #expect(work2.persistentModelID != originalID)
        #expect(work2.title == "New Work After Deletion")
    }

    @Test("Multiple volumeIDs all evicted when Work deleted")
    func allVolumeIDsEvictedOnDeletion() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)

        // Create Work with 3 volumeIDs
        let dto1 = makeTestWorkDTO(title: "Multi-ID Work", volumeIDs: ["vol-a", "vol-b", "vol-c"])
        let work1 = try mapper.mapToWork(dto1)

        // Delete Work
        context.delete(work1)
        try context.save()

        // Try to find via each volumeID - all should create new Works
        let dto2 = makeTestWorkDTO(title: "New Work A", volumeIDs: ["vol-a"])
        let work2 = try mapper.mapToWork(dto2)

        let dto3 = makeTestWorkDTO(title: "New Work B", volumeIDs: ["vol-b"])
        let work3 = try mapper.mapToWork(dto3)

        let dto4 = makeTestWorkDTO(title: "New Work C", volumeIDs: ["vol-c"])
        let work4 = try mapper.mapToWork(dto4)

        // All should be different Works (cache fully evicted)
        #expect(work2.persistentModelID != work3.persistentModelID)
        #expect(work3.persistentModelID != work4.persistentModelID)
        #expect(work2.persistentModelID != work4.persistentModelID)
    }

    // MARK: - Cache Miss Tests

    @Test("Cache miss creates new Work")
    func cacheMissCreatesNewWork() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)

        // Create first Work
        let dto1 = makeTestWorkDTO(title: "Work 1", volumeIDs: ["vol-1"])
        let work1 = try mapper.mapToWork(dto1)

        // Create second Work with different volumeID
        let dto2 = makeTestWorkDTO(title: "Work 2", volumeIDs: ["vol-2"])
        let work2 = try mapper.mapToWork(dto2)

        // Should be different Works
        #expect(work1.persistentModelID != work2.persistentModelID)
        #expect(work1.title == "Work 1")
        #expect(work2.title == "Work 2")
    }

    // MARK: - Cache Management Tests

    @Test("clearCache() removes all entries")
    func clearCacheRemovesAllEntries() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)

        // Create multiple Works
        let dto1 = makeTestWorkDTO(title: "Work 1", volumeIDs: ["vol-1"])
        _ = try mapper.mapToWork(dto1)

        let dto2 = makeTestWorkDTO(title: "Work 2", volumeIDs: ["vol-2"])
        _ = try mapper.mapToWork(dto2)

        // Clear cache
        mapper.clearCache()

        // Next DTOs should create new Works (cache empty)
        let dto3 = makeTestWorkDTO(title: "Work 1 Repeat", volumeIDs: ["vol-1"])
        let work3 = try mapper.mapToWork(dto3)

        let dto4 = makeTestWorkDTO(title: "Work 2 Repeat", volumeIDs: ["vol-2"])
        let work4 = try mapper.mapToWork(dto4)

        // Should be different Works (not cached)
        #expect(work3.title == "Work 1 Repeat")
        #expect(work4.title == "Work 2 Repeat")
    }
    
    // MARK: - Persistence Tests
    
    @Test("Cache persists across DTOMapper instances")
    func cachePersistsAcrossInstances() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        
        // Create Work with first mapper instance
        let mapper1 = DTOMapper(modelContext: context)
        let dto1 = makeTestWorkDTO(title: "Persistent Work", volumeIDs: ["vol-persist"])
        let work1 = try mapper1.mapToWork(dto1)
        let originalID = work1.persistentModelID
        
        // Create new mapper instance (simulates app restart)
        let mapper2 = DTOMapper(modelContext: context)
        
        // Same volumeID should find existing Work via persisted cache
        let dto2 = makeTestWorkDTO(title: "Should Find Existing", volumeIDs: ["vol-persist"])
        let work2 = try mapper2.mapToWork(dto2)
        
        // Should return same Work (cache loaded from disk)
        #expect(work2.persistentModelID == originalID)
        #expect(work2.title == "Persistent Work")
    }
    
    @Test("clearCache removes disk cache file")
    func clearCacheRemovesDiskFile() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let mapper1 = DTOMapper(modelContext: context)
        
        // Create Work to populate cache
        let dto1 = makeTestWorkDTO(title: "Work to Clear", volumeIDs: ["vol-clear"])
        _ = try mapper1.mapToWork(dto1)
        
        // Clear cache (should delete disk file)
        mapper1.clearCache()
        
        // Create new mapper instance - should have empty cache
        let mapper2 = DTOMapper(modelContext: context)
        
        // Same volumeID should create NEW Work (cache was cleared)
        let dto2 = makeTestWorkDTO(title: "New Work After Clear", volumeIDs: ["vol-clear"])
        let work2 = try mapper2.mapToWork(dto2)
        
        #expect(work2.title == "New Work After Clear")
    }
    
    @Test("pruneStaleCacheEntries removes deleted Works")
    func pruneStaleCacheEntriesRemovesDeletedWorks() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)
        
        // Create two Works
        let dto1 = makeTestWorkDTO(title: "Work to Keep", volumeIDs: ["vol-keep"])
        let work1 = try mapper.mapToWork(dto1)
        
        let dto2 = makeTestWorkDTO(title: "Work to Delete", volumeIDs: ["vol-delete"])
        let work2 = try mapper.mapToWork(dto2)
        
        // Delete second Work
        context.delete(work2)
        try context.save()
        
        // Prune cache (should remove vol-delete but keep vol-keep)
        mapper.pruneStaleCacheEntries()
        
        // Create new mapper to verify persistence
        let mapper2 = DTOMapper(modelContext: context)
        
        // vol-keep should still be cached
        let dto3 = makeTestWorkDTO(title: "Should Find Kept Work", volumeIDs: ["vol-keep"])
        let work3 = try mapper2.mapToWork(dto3)
        #expect(work3.persistentModelID == work1.persistentModelID)
        
        // vol-delete should create new Work (was pruned)
        let dto4 = makeTestWorkDTO(title: "New Work After Prune", volumeIDs: ["vol-delete"])
        let work4 = try mapper2.mapToWork(dto4)
        #expect(work4.title == "New Work After Prune")
    }
    
    @Test("pruneStaleCacheEntries handles empty cache gracefully")
    func pruneStaleCacheEntriesHandlesEmptyCache() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)
        
        // Prune empty cache - should not crash
        mapper.pruneStaleCacheEntries()
        
        // Cache should still be empty
        let dto = makeTestWorkDTO(title: "New Work", volumeIDs: ["vol-new"])
        let work = try mapper.mapToWork(dto)
        #expect(work.title == "New Work")
    }
}
