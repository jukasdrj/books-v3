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
            print("❌ Error details: \(String(describing: error))")

            #if targetEnvironment(simulator)
            print("💡 Simulator detected - trying persistent fallback")
            // Last resort fallback for simulator
            do {
                let fallbackConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,  // Persist data
                    cloudKitDatabase: .none
                )
                return try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                fatalError("Failed to create fallback ModelContainer: \(error)")
            }
            #else
            fatalError("Failed to create ModelContainer: \(error)")
            #endif
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .iOS26ThemeStore(themeStore)
                .modelContainer(modelContainer)
                .environment(featureFlags)
        }
    }
}