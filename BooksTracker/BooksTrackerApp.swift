import SwiftUI
import SwiftData
import BooksTrackerFeature

// MARK: - Model Container Factory

/// Factory for creating ModelContainer with lazy initialization pattern
@MainActor
class ModelContainerFactory {
    static let shared = ModelContainerFactory()

    private var _container: ModelContainer?

    var container: ModelContainer {
        if let _container = _container {
            return _container
        }

        LaunchMetrics.shared.recordMilestone("ModelContainer creation start")

        let schema = Schema([
            Work.self,
            Edition.self,
            Author.self,
            UserLibraryEntry.self
        ])

        #if targetEnvironment(simulator)
        // Simulator: Use persistent storage (no CloudKit on simulator)
        #if DEBUG
        print("🧪 Running on simulator - using persistent local database")
        #endif
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,  // ← Persist data across launches
            cloudKitDatabase: .none  // Explicitly disable CloudKit on simulator
        )
        #else
        // Device: Enable CloudKit sync via entitlements
        #if DEBUG
        print("📱 Running on device - CloudKit sync enabled")
        #endif
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
            // CloudKit sync will be enabled automatically via entitlements
        )
        #endif

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            LaunchMetrics.shared.recordMilestone("ModelContainer created successfully")
            _container = container
            return container
        } catch {
            // Print detailed error for debugging
            #if DEBUG
            print("❌ ModelContainer creation failed: \(error)")

            #if targetEnvironment(simulator)
            print("💡 Simulator detected - trying persistent fallback")
            #else
            print("💡 Device detected - trying local-only fallback (CloudKit disabled)")
            #endif
            #endif

            // Last resort fallback: Disable CloudKit and use local-only storage
            // This prevents app crashes when CloudKit sync fails or schema migration issues occur
            do {
                let fallbackConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,  // Persist data locally
                    cloudKitDatabase: .none       // Disable CloudKit sync
                )
                let container = try ModelContainer(for: schema, configurations: [fallbackConfig])
                LaunchMetrics.shared.recordMilestone("ModelContainer created (fallback)")
                _container = container
                return container
            } catch {
                // If even fallback fails, crash with detailed error for debugging
                fatalError("Failed to create fallback ModelContainer (local-only mode): \(error)")
            }
        }
    }

    // Lazy LibraryRepository - created on first access
    private var _libraryRepository: LibraryRepository?

    var libraryRepository: LibraryRepository {
        if let _libraryRepository = _libraryRepository {
            return _libraryRepository
        }

        LaunchMetrics.shared.recordMilestone("LibraryRepository creation start")
        let repository = LibraryRepository(modelContext: container.mainContext)
        LaunchMetrics.shared.recordMilestone("LibraryRepository created")
        _libraryRepository = repository
        return repository
    }
}

// MARK: - DTO Mapper Factory

@MainActor
class DTOMapperFactory {
    static let shared = DTOMapperFactory()

    private var _mapper: DTOMapper?

    func mapper(for context: ModelContext) -> DTOMapper {
        if let _mapper = _mapper {
            return _mapper
        }

        LaunchMetrics.shared.recordMilestone("DTOMapper creation start")
        let mapper = DTOMapper(modelContext: context)
        LaunchMetrics.shared.recordMilestone("DTOMapper created")
        _mapper = mapper
        return mapper
    }
}

@main
struct BooksTrackerApp: App {
    @State private var themeStore = iOS26ThemeStore()
    @State private var featureFlags = FeatureFlags.shared

    var body: some Scene {
        WindowGroup {
            let container = ModelContainerFactory.shared.container
            ContentView()
                .onAppear {
                    LaunchMetrics.shared.recordMilestone("ContentView appeared")
                }
                .iOS26ThemeStore(themeStore)
                .modelContainer(container)
                .environment(featureFlags)
                .environment(\.dtoMapper, DTOMapperFactory.shared.mapper(for: container.mainContext))
                .environment(ModelContainerFactory.shared.libraryRepository)
        }
    }
}
