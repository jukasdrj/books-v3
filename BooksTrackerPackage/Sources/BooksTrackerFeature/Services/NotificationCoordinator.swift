import Foundation
import SwiftUI

@MainActor
public final class NotificationCoordinator {
    public init() {}

    // MARK: - Type-Safe Posting (Static Methods)

    @MainActor
    public static func postEnrichmentStarted(totalBooks: Int) {
        let payload = EnrichmentStartedPayload(totalBooks: totalBooks)
        NotificationCenter.default.post(
            name: .enrichmentStarted,
            object: nil,
            userInfo: ["payload": payload]
        )
    }

    @MainActor
    public static func postEnrichmentProgress(completed: Int, total: Int, currentTitle: String) {
        let payload = EnrichmentProgressPayload(
            completed: completed,
            total: total,
            currentTitle: currentTitle
        )
        NotificationCenter.default.post(
            name: .enrichmentProgress,
            object: nil,
            userInfo: ["payload": payload]
        )
    }

    @MainActor
    public static func postEnrichmentCompleted() {
        NotificationCenter.default.post(
            name: .enrichmentCompleted,
            object: nil
        )
    }

    @MainActor
    public static func postEnrichmentFailed(error: String) {
        let payload = EnrichmentFailedPayload(errorMessage: error)
        NotificationCenter.default.post(
            name: .enrichmentFailed,
            object: nil,
            userInfo: ["payload": payload]
        )
    }

    @MainActor
    public static func postSearchForAuthor(authorName: String) {
        let payload = SearchForAuthorPayload(authorName: authorName)
        NotificationCenter.default.post(
            name: .searchForAuthor,
            object: nil,
            userInfo: ["payload": payload]
        )
    }

    @MainActor
    public static func postSwitchToLibraryTab() {
        NotificationCenter.default.post(
            name: .switchToLibraryTab,
            object: nil
        )
    }

    // MARK: - Type-Safe Extraction

    nonisolated public func extractEnrichmentStarted(from notification: Notification) -> EnrichmentStartedPayload? {
        notification.userInfo?["payload"] as? EnrichmentStartedPayload
    }

    nonisolated public func extractEnrichmentProgress(from notification: Notification) -> EnrichmentProgressPayload? {
        notification.userInfo?["payload"] as? EnrichmentProgressPayload
    }

    nonisolated public func extractSearchForAuthor(from notification: Notification) -> SearchForAuthorPayload? {
        notification.userInfo?["payload"] as? SearchForAuthorPayload
    }

    nonisolated public func extractEnrichmentFailed(from notification: Notification) -> EnrichmentFailedPayload? {
        notification.userInfo?["payload"] as? EnrichmentFailedPayload
    }

    // MARK: - Centralized Notification Handling

    /// Handles all app notifications in a single stream. Call from ContentView.task { }.
    public func handleNotifications(
        onSwitchToLibrary: @escaping @MainActor () -> Void,
        onEnrichmentStarted: @escaping @MainActor (EnrichmentStartedPayload) -> Void,
        onEnrichmentProgress: @escaping @MainActor (EnrichmentProgressPayload) -> Void,
        onEnrichmentCompleted: @escaping @MainActor () -> Void,
        onEnrichmentFailed: @escaping @MainActor (EnrichmentFailedPayload) -> Void,
        onSearchForAuthor: @escaping @MainActor (SearchForAuthorPayload) -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in NotificationCenter.default.notifications(named: .switchToLibraryTab) {
                    await MainActor.run {
                        onSwitchToLibrary()
                    }
                }
            }

            group.addTask {
                for await notification in NotificationCenter.default.notifications(named: .enrichmentStarted) {
                    if let payload = self.extractEnrichmentStarted(from: notification) {
                        await MainActor.run {
                            onEnrichmentStarted(payload)
                        }
                    }
                }
            }

            group.addTask {
                for await notification in NotificationCenter.default.notifications(named: .enrichmentProgress) {
                    if let payload = self.extractEnrichmentProgress(from: notification) {
                        await MainActor.run {
                            onEnrichmentProgress(payload)
                        }
                    }
                }
            }

            group.addTask {
                for await _ in NotificationCenter.default.notifications(named: .enrichmentCompleted) {
                    await MainActor.run {
                        onEnrichmentCompleted()
                    }
                }
            }

            group.addTask {
                for await notification in NotificationCenter.default.notifications(named: .enrichmentFailed) {
                    if let payload = self.extractEnrichmentFailed(from: notification) {
                        await MainActor.run {
                            onEnrichmentFailed(payload)
                        }
                    }
                }
            }

            group.addTask {
                for await notification in NotificationCenter.default.notifications(named: .searchForAuthor) {
                    if let payload = self.extractSearchForAuthor(from: notification) {
                        await MainActor.run {
                            onSearchForAuthor(payload)
                        }
                    }
                }
            }
        }
    }
}
