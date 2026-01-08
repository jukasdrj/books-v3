import Foundation
import SwiftData

/// Represents a progress snapshot for a reading goal
///
/// # Usage with @Bindable
///
/// ```swift
/// struct ProgressHistoryView: View {
///     var progressSnapshots: [GoalProgress]
///
///     var body: some View {
///         ForEach(progressSnapshots) { snapshot in
///             Text("\(snapshot.progressValue) on \(snapshot.recordedDate.formatted())")
///         }
///     }
/// }
/// ```
@Model
public final class GoalProgress {
    /// Stable identifier for CloudKit sync
    public var uuid: UUID = UUID()

    /// When this progress snapshot was recorded
    public var recordedDate: Date = Date()

    /// Progress value at time of recording
    public var progressValue: Int = 0

    /// Optional note about this progress update
    public var note: String?

    /// Optional milestone description (e.g., "Reached halfway!")
    public var milestone: String?

    // MARK: - Relationships

    /// Relationship to parent goal (inverse defined on Goal.progressSnapshots)
    public var goal: Goal?

    /// Denormalized goal UUID for efficient bulk queries (stable across CloudKit sync)
    public var goalUUID: UUID?

    // MARK: - Computed Properties

    /// Display text for this progress snapshot
    public var displayText: String {
        if let milestone = milestone {
            return "\(milestone) - \(progressValue)"
        }
        return "\(progressValue)"
    }

    // MARK: - Initializer

    public init(
        recordedDate: Date = Date(),
        progressValue: Int = 0,
        note: String? = nil,
        milestone: String? = nil
    ) {
        self.recordedDate = recordedDate
        self.progressValue = progressValue
        self.note = note
        self.milestone = milestone
    }
}
