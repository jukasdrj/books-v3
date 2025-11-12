import SwiftData
import Foundation

@MainActor
public final class SampleDataGenerator {
    private let modelContext: ModelContext
    private let sampleDataAddedKey = "SampleDataAdded"

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Adds sample data only if library is empty. Optimized check (fetchLimit=1).
    /// ✅ DEBUG-ONLY: Sample data is only added in development builds (#385)
    public func setupSampleDataIfNeeded() {
        #if DEBUG
        // Check UserDefaults first - if sample data was added before, skip check
        if UserDefaults.standard.bool(forKey: sampleDataAddedKey) {
            print("✅ Sample data previously added - skipping check")
            return
        }

        guard isLibraryEmpty() else {
            print("✅ Library not empty - skipping sample data")
            return
        }

        addSampleData()

        // Mark that sample data was added
        UserDefaults.standard.set(true, forKey: sampleDataAddedKey)
        print("✅ Sample data added (DEBUG mode only)")
        #endif
    }

    /// Reset sample data flag (call when library is reset)
    public func resetSampleDataFlag() {
        UserDefaults.standard.removeObject(forKey: sampleDataAddedKey)
        #if DEBUG
        print("🔄 Sample data flag reset")
        #endif
    }

    // MARK: - Private Helpers

    private func isLibraryEmpty() -> Bool {
        var descriptor = FetchDescriptor<Work>()
        descriptor.fetchLimit = 1  // Only check existence, don't fetch all Works

        let works = (try? modelContext.fetch(descriptor)) ?? []
        return works.isEmpty
    }

    private func addSampleData() {
        // Sample Authors - insert BEFORE relating
        let kazuoIshiguro = Author(
            name: "Kazuo Ishiguro",
            gender: .male,
            culturalRegion: .asia
        )

        let octaviaButler = Author(
            name: "Octavia E. Butler",
            gender: .female,
            culturalRegion: .northAmerica
        )

        let chimamandaNgozi = Author(
            name: "Chimamanda Ngozi Adichie",
            gender: .female,
            culturalRegion: .africa
        )

        modelContext.insert(kazuoIshiguro)
        modelContext.insert(octaviaButler)
        modelContext.insert(chimamandaNgozi)

        // Sample Works - insert BEFORE relating
        let klaraAndTheSun = Work(
            title: "Klara and the Sun",
            originalLanguage: "English",
            firstPublicationYear: 2021
        )

        let kindred = Work(
            title: "Kindred",
            originalLanguage: "English",
            firstPublicationYear: 1979
        )

        let americanah = Work(
            title: "Americanah",
            originalLanguage: "English",
            firstPublicationYear: 2013
        )

        modelContext.insert(klaraAndTheSun)
        modelContext.insert(kindred)
        modelContext.insert(americanah)

        // Set relationships AFTER insert (insert-before-relate pattern)
        klaraAndTheSun.authors = [kazuoIshiguro]
        kindred.authors = [octaviaButler]
        americanah.authors = [chimamandaNgozi]

        // Sample Editions - insert BEFORE relating
        let klaraEdition = Edition(
            isbn: "9780571364893",
            publisher: "Faber & Faber",
            publicationDate: "2021",
            pageCount: 303,
            format: .hardcover
        )

        let kindredEdition = Edition(
            isbn: "9780807083697",
            publisher: "Beacon Press",
            publicationDate: "1979",
            pageCount: 287,
            format: .paperback
        )

        let americanahEdition = Edition(
            isbn: "9780307455925",
            publisher: "Knopf",
            publicationDate: "2013",
            pageCount: 477,
            format: .ebook
        )

        modelContext.insert(klaraEdition)
        modelContext.insert(kindredEdition)
        modelContext.insert(americanahEdition)

        // Link editions to works AFTER insert
        klaraEdition.work = klaraAndTheSun
        kindredEdition.work = kindred
        americanahEdition.work = americanah

        // Sample Library Entries
        let klaraEntry = UserLibraryEntry.createOwnedEntry(
            for: klaraAndTheSun,
            edition: klaraEdition,
            status: .reading,
            context: modelContext
        )
        klaraEntry.readingProgress = 0.35
        klaraEntry.dateStarted = Calendar.current.date(byAdding: .day, value: -7, to: Date())

        let kindredEntry = UserLibraryEntry.createOwnedEntry(
            for: kindred,
            edition: kindredEdition,
            status: .read,
            context: modelContext
        )
        kindredEntry.dateCompleted = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        kindredEntry.personalRating = 5.0

        _ = UserLibraryEntry.createWishlistEntry(for: americanah, context: modelContext)

        // Save context
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("Failed to save sample data: \(error)")
            #endif
        }
    }
}
