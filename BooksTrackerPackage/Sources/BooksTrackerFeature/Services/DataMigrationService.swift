import Foundation
import SwiftData

/// Service for handling data migrations between app versions
@MainActor
public final class DataMigrationService {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Migrate existing Work records to have UUIDs
    /// This is needed when adding the uuid field to Work for the first time
    public func migrateWorksToUUID() throws {
        let descriptor = FetchDescriptor<Work>()
        let allWorks = try modelContext.fetch(descriptor)

        var migratedCount = 0
        for work in allWorks {
            // Check if uuid is the default (all zeros) which indicates it needs migration
            // SwiftData initializes UUID() for new fields, but we want unique values
            if work.uuid == UUID(uuidString: "00000000-0000-0000-0000-000000000000") ||
               allWorks.filter({ $0.uuid == work.uuid }).count > 1 {
                work.uuid = UUID()
                migratedCount += 1
            }
        }

        if migratedCount > 0 {
            try modelContext.save()
            #if DEBUG
            print("✅ Migrated \(migratedCount) Work records to have unique UUIDs")
            #endif
        }
    }
}
