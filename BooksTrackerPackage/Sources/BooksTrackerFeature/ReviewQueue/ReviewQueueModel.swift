//
//  ReviewQueueModel.swift
//  BooksTrackerFeature
//
//  Manages Review Queue state for human-in-the-loop correction workflow
//

import Foundation
import SwiftData
import Observation

/// Manages Review Queue state and operations
@MainActor
@Observable
public class ReviewQueueModel {
    /// Works needing human review (confidence < 0.60 or user-edited)
    public var worksNeedingReview: [Work] = []

    /// Currently selected work for correction
    public var selectedWork: Work?

    /// Whether the queue is currently loading
    public var isLoading = false

    /// Error message if queue loading fails
    public var errorMessage: String?

    public init() {}

    // MARK: - Queue Management

    /// Load all works requiring human review
    public func loadReviewQueue(modelContext: ModelContext) async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch all works - filter in memory since enum comparison not supported in predicates
            let descriptor = FetchDescriptor<Work>(
                sortBy: [SortDescriptor(\.title)]
            )

            let allWorks = try modelContext.fetch(descriptor)
            worksNeedingReview = allWorks.filter { $0.reviewStatus == .needsReview }

            // Analytics: Track queue viewed
            logAnalyticsEvent("review_queue_viewed", properties: [
                "queue_count": worksNeedingReview.count
            ])

        } catch {
            errorMessage = "Failed to load review queue: \(error.localizedDescription)"
            #if DEBUG
            print("❌ ReviewQueueModel: Failed to load queue - \(error)")
            #endif
        }

        isLoading = false
    }

    /// Remove a work from the review queue (after verification/correction)
    public func removeFromQueue(_ work: Work) {
        worksNeedingReview.removeAll { $0.persistentModelID == work.persistentModelID }
    }

    /// Select a work for correction
    public func selectWork(_ work: Work) {
        selectedWork = work
    }

    /// Clear selected work
    public func clearSelection() {
        selectedWork = nil
    }

    // MARK: - Computed Properties

    /// Number of works needing review
    public var queueCount: Int {
        worksNeedingReview.count
    }

    /// Whether the queue is empty
    public var isEmpty: Bool {
        worksNeedingReview.isEmpty
    }

    // MARK: - Analytics

    /// Log analytics event (placeholder for real analytics SDK)
    private func logAnalyticsEvent(_ eventName: String, properties: [String: Any] = [:]) {
        #if DEBUG
        print("📊 Analytics: \(eventName) - \(properties)")
        #endif
        // TODO: Replace with real analytics SDK (Firebase, Mixpanel, etc.)
    }
}
