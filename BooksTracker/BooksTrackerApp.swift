import SwiftUI
import SwiftData
import BooksTrackerFeature
import OSLog

// MARK: - Model Container Factory Protocol

/// Protocol abstraction for ModelContainer factory
/// Enables dependency injection and testability
@MainActor
protocol ModelContainerFactoryProtocol {
    /// Get or create ModelContainer with optional reset callback
    /// - Parameter onResetNeeded: Callback invoked when database reset is needed (errorMessage, resetAction)
    func container(onResetNeeded: ((String, @escaping () -> Void) -> Void)?) -> ModelContainer

    /// Get LibraryRepository instance
    var libraryRepository: LibraryRepository { get }
}

// MARK: - Model Container Factory

/// Factory for creating ModelContainer with lazy initialization pattern
@MainActor
final class ModelContainerFactory: ModelContainerFactoryProtocol {
    private var _container: ModelContainer?
    private var resetCallback: ((String, @escaping () -> Void) -> Void)?

    /// Get or create ModelContainer with optional reset callback
    /// - Parameter onResetNeeded: Callback invoked when database reset is needed (errorMessage, resetAction)
    func container(onResetNeeded: ((String, @escaping () -> Void) -> Void)? = nil) -> ModelContainer {
        self.resetCallback = onResetNeeded
        return container
    }

    private var container: ModelContainer {
        if let _container = _container {
            return _container
        }

        LaunchMetrics.shared.recordMilestone("ModelContainer creation start")

        let schema = Schema([
            Work.self,
            Edition.self,
            Author.self,
            UserLibraryEntry.self,
            TrendingActivity.self,
            // v2 Sprint 1: Diversity & Reading Sessions
            ReadingSession.self,
            // v2 Sprint 2: Progressive Profiling & Metadata Cascade
            BookEnrichment.self,
            AuthorMetadata.self,
            WorkOverride.self,
            StreakData.self,
            UserSettings.self
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
                migrationPlan: DiversityStatsMigrationPlan.self,
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
            } catch let fallbackError {
                #if DEBUG
                print("❌ Fallback also failed: \(fallbackError)")
                print("💡 Migration failure detected - attempting database reset")
                print("⚠️  DATABASE RESET WARNING: User data will be lost!")
                print("📋 Migration Error Details:")
                print("   - Initial Error: \(error)")
                print("   - Fallback Error: \(fallbackError)")
                #endif

                // If migration failed due to constraint violations, database reset is needed
                // This is a destructive operation but necessary for schema changes
                let fileManager = FileManager.default
                guard let storeURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("default.store") else {
                    fatalError("Failed to locate database file. Fallback error: \(fallbackError)")
                }

                #if DEBUG
                print("📍 Database location: \(storeURL.path)")
                #endif

                // Build error message for user
                let errorMessage = "Initial error: \(error.localizedDescription)\n\nFallback error: \(fallbackError.localizedDescription)"

                // Check if we have a callback to ask the user first
                if let resetCallback = resetCallback {
                    // User confirmation flow (Issue #120 - resolved)
                    // Delete corrupted DB and exit cleanly - fresh DB created on next launch
                    let resetAction = {
                        #if DEBUG
                        print("🗑️ User confirmed database reset")
                        #endif

                        do {
                            try fileManager.removeItem(at: storeURL)
                            #if DEBUG
                            print("🗑️ Removed corrupted database at \(storeURL)")
                            print("✅ Exiting app - fresh database will be created on next launch")
                            #endif
                            // Exit cleanly to allow fresh start on next launch
                            exit(0)
                        } catch {
                            // If we can't delete the file, we're stuck
                            fatalError("Failed to remove corrupted database: \(error)")
                        }
                    }

                    // Trigger alert and suspend initialization
                    resetCallback(errorMessage, resetAction)

                    // Return temp in-memory container to allow app to launch and show alert
                    #if DEBUG
                    print("⚠️ Returning temporary in-memory container while waiting for user decision")
                    #endif
                    let tempConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                    // Force-try is safe here - in-memory container creation should not fail
                    return try! ModelContainer(for: schema, configurations: [tempConfig])
                } else {
                    // No callback - automatic reset (legacy behavior for tests/non-UI contexts)
                    #if DEBUG
                    print("⚠️  No reset callback provided - performing automatic reset")
                    #endif

                    try? fileManager.removeItem(at: storeURL)

                    #if DEBUG
                    print("🗑️ Removed corrupted database at \(storeURL)")
                    print("✅ Attempting fresh database creation...")
                    #endif

                    // Try one more time with fresh database
                    do {
                        let freshConfig = ModelConfiguration(
                            schema: schema,
                            isStoredInMemoryOnly: false,
                            cloudKitDatabase: .none
                        )
                        let container = try ModelContainer(for: schema, configurations: [freshConfig])
                        LaunchMetrics.shared.recordMilestone("ModelContainer created (fresh database - automatic)")
                        _container = container
                        return container
                    } catch {
                        fatalError("Failed to create ModelContainer even with fresh database: \(error)")
                    }
                }
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
        let repository = LibraryRepository(modelContext: container.mainContext, dtoMapper: nil, featureFlags: nil)
        LaunchMetrics.shared.recordMilestone("LibraryRepository created")
        _libraryRepository = repository
        return repository
    }
}

// MARK: - DTO Mapper Factory Protocol

/// Protocol abstraction for DTOMapper factory
/// Enables dependency injection and testability
@MainActor
protocol DTOMapperFactoryProtocol {
    /// Get or create DTOMapper for a given ModelContext
    func mapper(for context: ModelContext) -> DTOMapper
}

// MARK: - DTO Mapper Factory

@MainActor
final class DTOMapperFactory: DTOMapperFactoryProtocol {
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
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "BooksTrackerApp")
    @State private var themeStore = iOS26ThemeStore()
    @State private var featureFlags = FeatureFlags.shared
    @State private var curatorPointsService = CuratorPointsService()
    @State private var capabilitiesService = CapabilitiesService()

    // Dependency injection - no more singletons!
    @State private var modelContainerFactory = ModelContainerFactory()
    @State private var dtoMapperFactory = DTOMapperFactory()

    // Database reset state
    @State private var showDatabaseResetAlert = false
    @State private var databaseResetError: String = ""
    @State private var pendingReset: (() -> Void)?

    var body: some Scene {
        WindowGroup {
            let container = modelContainerFactory.container(
                onResetNeeded: { errorMessage, resetAction in
                    databaseResetError = errorMessage
                    pendingReset = resetAction
                    showDatabaseResetAlert = true
                }
            )
            let dtoMapper = dtoMapperFactory.mapper(for: container.mainContext)

            // Create service instances
            let enrichmentService = EnrichmentService()
            let enrichmentQueue = EnrichmentQueue(enrichmentService: enrichmentService)

            let libraryRepository = LibraryRepository(
                modelContext: container.mainContext,
                dtoMapper: dtoMapper,
                featureFlags: featureFlags,
                enrichmentQueue: enrichmentQueue
            )

            ContentView()
                .onAppear {
                    LaunchMetrics.shared.recordMilestone("ContentView appeared")
                }
                .task {
                    do {
                        let capabilities = try await capabilitiesService.fetchCapabilities()
                        featureFlags.apiCapabilities = capabilities
                    } catch {
                        logger.error("Failed to fetch capabilities: \(error.localizedDescription)")
                    }
                }
                .iOS26ThemeStore(themeStore)
                .modelContainer(container)
                .environment(featureFlags)
                .environment(\.dtoMapper, dtoMapper)
                .environment(libraryRepository)
                .environment(\.enrichmentService, enrichmentService)
                .environment(\.enrichmentQueue, enrichmentQueue)
                .environment(\.curatorPointsService, curatorPointsService)
                .alert("Database Reset Required", isPresented: $showDatabaseResetAlert) {
                    Button("Reset & Lose Data", role: .destructive) {
                        pendingReset?()
                    }
                    Button("Cancel", role: .cancel) {
                        // Exit gracefully instead of crashing (avoids crash report)
                        exit(0)
                    }
                } message: {
                    Text("Migration failed with error:\n\n\(databaseResetError)\n\nResetting will delete all your books and data. This cannot be undone.\n\nIf you cancel, the app will close.")
                }
        }
    }
}
