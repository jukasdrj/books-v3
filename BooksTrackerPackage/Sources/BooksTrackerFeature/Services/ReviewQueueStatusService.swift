import Foundation
import SwiftData
import SwiftUI

#if canImport(UIKit)

/// Service for tracking review queue status and providing real-time updates
@MainActor
@Observable
public class ReviewQueueStatusService {
    /// Works needing human review
    public var reviewQueueCount: Int = 0
    
    /// Whether any items need review
    public var hasItemsNeedingReview: Bool {
        reviewQueueCount > 0
    }
    
    private var modelContext: ModelContext?
    private var queryMonitor: Task<Void, Never>?
    
    public init() {}
    
    /// Start monitoring review queue changes
    public func startMonitoring(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        // Initial count
        updateReviewQueueCount()
        
        // Monitor for changes using a timer-based approach
        // In a production app, you might want to use more sophisticated change detection
        queryMonitor = Task {
            // Check every 5 seconds for changes
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await MainActor.run {
                    updateReviewQueueCount()
                }
            }
        }
    }
    
    /// Stop monitoring
    public func stopMonitoring() {
        queryMonitor?.cancel()
        queryMonitor = nil
        modelContext = nil
    }
    
    /// Update the review queue count
    private func updateReviewQueueCount() {
        guard let modelContext = modelContext else { return }
        
        do {
            // Fetch works needing review
            let descriptor = FetchDescriptor<Work>(
                predicate: #Predicate<Work> { work in
                    work.reviewStatus.rawValue == "needsReview"
                }
            )
            let worksNeedingReview = try modelContext.fetch(descriptor)
            reviewQueueCount = worksNeedingReview.count
            
            #if DEBUG
            print("📊 ReviewQueueStatusService: Updated count to \(reviewQueueCount)")
            #endif
        } catch {
            #if DEBUG
            print("❌ ReviewQueueStatusService: Failed to fetch count - \(error)")
            #endif
            reviewQueueCount = 0
        }
    }
}

#endif