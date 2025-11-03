import SwiftUI
import SwiftData
import BooksTrackerFeature

@main
struct BooksTrackerApp: App {
    @State private var themeStore = iOS26ThemeStore()
    @State private var featureFlags = FeatureFlags.shared

    // MARK: - SwiftData Configuration

    /// SwiftData model container - created once and reused
    /// Configured for local storage (CloudKit sync disabled on simulator)
    let modelContainer: ModelContainer = {
        let schema = Schema([
            Work.self,
            Edition.self,
            Author.self,
            UserLibraryEntry.self
        ])

        #if targetEnvironment(simulator)
        // Simulator: Use persistent storage (no CloudKit on simulator)
        print("🧪 Running on simulator - using persistent local database")
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,  // ← Persist data across launches
            cloudKitDatabase: .none  // Explicitly disable CloudKit on simulator
        )
        #else
        // Device: Enable CloudKit sync via entitlements
        print("📱 Running on device - CloudKit sync enabled")
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
            // CloudKit sync will be enabled automatically via entitlements
        )
        #endif

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            // Print detailed error for debugging
            print("❌ ModelContainer creation failed: \(error)")

            #if targetEnvironment(simulator)
            print("💡 Simulator detected - trying persistent fallback")
            #else
            print("💡 Device detected - trying local-only fallback (CloudKit disabled)")
            #endif

            // Last resort fallback: Disable CloudKit and use local-only storage
            // This prevents app crashes when CloudKit sync fails or schema migration issues occur
            do {
                let fallbackConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,  // Persist data locally
                    cloudKitDatabase: .none       // Disable CloudKit sync
                )
                return try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                // If even fallback fails, crash with detailed error for debugging
                fatalError("Failed to create fallback ModelContainer (local-only mode): \(error)")
            }
        }
    }()

    let dtoMapper: DTOMapper

    init() {
        // Create DTOMapper with main context
        self.dtoMapper = DTOMapper(modelContext: modelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .iOS26ThemeStore(themeStore)
                .modelContainer(modelContainer)
                .environment(featureFlags)
                .environment(\.dtoMapper, dtoMapper)
        }
    }
}