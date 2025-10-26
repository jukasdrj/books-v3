import Testing
import SwiftData
@testable import BooksTrackerFeature

@MainActor
struct LibraryResetIntegrationTests {

    @Test("Settings reset to defaults after library reset", .disabled("AIProviderSettings class no longer exists - test needs update"))
    func testSettingsResetToDefaults() async throws {
        // GIVEN: AIProviderSettings and FeatureFlags with non-default values
        // let aiSettings = AIProviderSettings.shared
        let featureFlags = FeatureFlags.shared

        // Change to non-default values
        // aiSettings.selectedProvider = .cloudflare
        featureFlags.enableTabBarMinimize = false

        // WHEN: Reset methods are called
        // aiSettings.resetToDefaults()
        featureFlags.resetToDefaults()

        // THEN: Settings are restored to defaults
        // #expect(aiSettings.selectedProvider == .gemini)
        #expect(featureFlags.enableTabBarMinimize == true)
    }

    @Test("EnrichmentQueue tracks and clears job ID")
    func testEnrichmentQueueJobIdTracking() async throws {
        // GIVEN: EnrichmentQueue with no job ID
        let queue = EnrichmentQueue.shared
        #expect(queue.getCurrentJobId() == nil)

        // WHEN: Job ID is set
        let testJobId = "test-job-123"
        queue.setCurrentJobId(testJobId)

        // THEN: Job ID is tracked
        #expect(queue.getCurrentJobId() == testJobId)

        // WHEN: Job ID is cleared
        queue.clearCurrentJobId()

        // THEN: Job ID is nil
        #expect(queue.getCurrentJobId() == nil)
    }
}
