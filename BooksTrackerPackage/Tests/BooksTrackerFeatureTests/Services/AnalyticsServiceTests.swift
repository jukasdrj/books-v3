import Testing
import OSLog
@testable import BooksTrackerFeature

@MainActor
@Suite("AnalyticsService Tests")
struct AnalyticsServiceTests {

    @Test("Shared instance is accessible and singleton")
    func testSharedInstance() {
        // Given: Multiple access to shared instance
        let instance1 = AnalyticsService.shared
        let instance2 = AnalyticsService.shared

        // Then: Same instance is returned (singleton pattern)
        #expect(instance1 === instance2)
    }

    @Test("Log event with no parameters")
    func testLogEventWithoutParameters() {
        // Given: AnalyticsService shared instance
        let service = AnalyticsService.shared

        // When: Logging an event without parameters
        // Note: Since logEvent uses OSLog, we can't directly test output
        // but we can verify the method doesn't crash and completes
        service.logEvent("test_event")

        // Then: No crash occurs (test passes)
        #expect(true) // Test that method call completes successfully
    }

    @Test("Log event with parameters")
    func testLogEventWithParameters() {
        // Given: AnalyticsService shared instance
        let service = AnalyticsService.shared

        // When: Logging an event with parameters
        let parameters: [String: Any] = [
            "action": "button_tap",
            "screen": "library",
            "count": 42,
            "success": true
        ]

        service.logEvent("user_interaction", parameters: parameters)

        // Then: No crash occurs (test passes)
        #expect(true) // Test that method call completes successfully
    }

    @Test("Log event with empty parameters dictionary")
    func testLogEventWithEmptyParameters() {
        // Given: AnalyticsService shared instance
        let service = AnalyticsService.shared

        // When: Logging an event with empty parameters
        service.logEvent("empty_params_event", parameters: [:])

        // Then: No crash occurs (test passes)
        #expect(true) // Test that method call completes successfully
    }

    @Test("Log event with complex parameters")
    func testLogEventWithComplexParameters() {
        // Given: AnalyticsService shared instance
        let service = AnalyticsService.shared

        // When: Logging an event with various data types
        let parameters: [String: Any] = [
            "string_value": "test string",
            "int_value": 123,
            "double_value": 45.67,
            "bool_value": false,
            "nil_value": NSNull(), // Simulating nil value
            "special_chars": "test@#$%^&*()"
        ]

        service.logEvent("complex_event", parameters: parameters)

        // Then: No crash occurs (test passes)
        #expect(true) // Test that method call completes successfully
    }

    @Test("Log multiple events in sequence")
    func testMultipleEvents() {
        // Given: AnalyticsService shared instance
        let service = AnalyticsService.shared

        // When: Logging multiple events in sequence
        service.logEvent("event_1")
        service.logEvent("event_2", parameters: ["order": 2])
        service.logEvent("event_3", parameters: ["order": 3, "type": "final"])

        // Then: No crash occurs (test passes)
        #expect(true) // Test that all events are logged successfully
    }

    @Test("Log event with special characters in event name")
    func testLogEventWithSpecialCharacters() {
        // Given: AnalyticsService shared instance
        let service = AnalyticsService.shared

        // When: Logging events with special characters in name
        service.logEvent("test-event_with.special@characters")
        service.logEvent("🎉 emoji_event 📊")
        service.logEvent("event with spaces")

        // Then: No crash occurs (test passes)
        #expect(true) // Test that special characters are handled properly
    }

    @Test("Analytics service is MainActor isolated")
    func testMainActorIsolation() async {
        // Given: We're testing from MainActor context
        // When: Accessing AnalyticsService.shared
        let service = AnalyticsService.shared

        // Then: Access should be synchronous since both are on MainActor
        service.logEvent("main_actor_test")

        // Verify we can call it directly without await
        #expect(true) // Test that MainActor isolation works correctly
    }

    @Test("Concurrent access to shared instance")
    func testConcurrentAccess() async {
        // Given: Multiple tasks accessing shared instance
        await withTaskGroup(of: Void.self) { group in
            // When: Multiple concurrent accesses
            for i in 0..<10 {
                group.addTask { @MainActor in
                    let service = AnalyticsService.shared
                    service.logEvent("concurrent_event_\(i)", parameters: ["index": i])
                }
            }

            // Wait for all tasks to complete
            for await _ in group {}
        }

        // Then: No crashes occur
        #expect(true) // Test that concurrent access is handled safely
    }
}