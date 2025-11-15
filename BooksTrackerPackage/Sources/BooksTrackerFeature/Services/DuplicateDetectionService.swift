import Foundation
import SwiftData

@MainActor
final class DuplicateDetectionService {
    static func findExistingEntry(
        for work: Work,
        in modelContext: ModelContext
    ) -> UserLibraryEntry? {
        // Multi-criteria matching:
        // 1. Exact ISBN match (highest confidence)
        // 2. Title + Author name match (high confidence)
        // 3. Normalized title match (medium confidence)

        // Try ISBN match first
        if let isbn = work.primaryEdition?.primaryISBN,
           let entry = findByISBN(isbn, in: modelContext) {
            return entry
        }

        // Fall back to title + author
        return findByTitleAndAuthor(work, in: modelContext)
    }

    private static func findByISBN(
        _ isbn: String,
        in modelContext: ModelContext
    ) -> UserLibraryEntry? {
        let predicate = #Predicate<UserLibraryEntry> { entry in
            entry.edition?.primaryISBN == isbn
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private static func findByTitleAndAuthor(
        _ work: Work,
        in modelContext: ModelContext
    ) -> UserLibraryEntry? {
        let title = work.title.lowercased()
        guard let firstAuthor = work.authors?.first?.name.lowercased() else {
            return nil
        }

        // CloudKit does not support filtering on to-many relationships in predicates.
        // SwiftData predicates also don't support lowercased() function.
        // Fetch all entries and filter in-memory for case-insensitive matching.
        let descriptor = FetchDescriptor<UserLibraryEntry>()
        let allEntries = (try? modelContext.fetch(descriptor)) ?? []
        
        return allEntries.first(where: { entry in
            guard let entryTitle = entry.work?.title.lowercased(),
                  entryTitle == title else {
                return false
            }
            
            return entry.work?.authors?.contains(where: { author in
                author.name.lowercased() == firstAuthor
            }) ?? false
        })
    }
}