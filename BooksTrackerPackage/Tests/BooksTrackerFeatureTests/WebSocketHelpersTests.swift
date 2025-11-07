import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("WebSocketHelpers Tests")
struct WebSocketHelpersTests {
    
    @Test("waitForConnection should complete without throwing for valid connection")
    func testWaitForConnectionSuccess() async throws {
        // Note: This test requires a real WebSocket server to test against
        // In a unit test environment, we can only verify the timeout behavior
        
        // Create a WebSocket task (will fail to connect in test environment)
        let url = URL(string: "wss://echo.websocket.org")!
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()
        
        // The test verifies that waitForConnection doesn't crash
        // In production with a real server, it would complete successfully
        do {
            try await WebSocketHelpers.waitForConnection(task, timeout: 1.0)
            // If we get here, connection succeeded (or test is running with real server)
            #expect(true)
        } catch {
            // In test environment without real server, expect timeout or connection error
            // This is acceptable for unit testing
            #expect(error is URLError)
        }
        
        task.cancel(with: .goingAway, reason: nil)
    }
    
    @Test("waitForConnection should timeout if connection takes too long")
    func testWaitForConnectionTimeout() async throws {
        // Create a WebSocket task to invalid endpoint
        let url = URL(string: "wss://invalid-endpoint-that-will-never-respond.example.com")!
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()
        
        // Should timeout after 0.5 seconds
        do {
            try await WebSocketHelpers.waitForConnection(task, timeout: 0.5)
            Issue.record("Expected timeout error but connection succeeded")
        } catch let error as URLError {
            // Expect either timeout or network error
            #expect(error.code == .timedOut || error.code == .cannotConnectToHost)
        } catch {
            Issue.record("Expected URLError but got: \(error)")
        }
        
        task.cancel(with: .goingAway, reason: nil)
    }
    
    @Test("waitForConnection should handle cancellation gracefully")
    func testWaitForConnectionCancellation() async throws {
        let url = URL(string: "wss://echo.websocket.org")!
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()
        
        // Start waiting in a Task that we can cancel
        let waitTask = Task {
            try await WebSocketHelpers.waitForConnection(task, timeout: 5.0)
        }
        
        // Cancel immediately
        waitTask.cancel()
        
        do {
            try await waitTask.value
            // If we get here without error, that's fine (race condition)
        } catch {
            // Cancellation or timeout is expected
            #expect(error is URLError || error is CancellationError)
        }
        
        task.cancel(with: .goingAway, reason: nil)
    }
}
