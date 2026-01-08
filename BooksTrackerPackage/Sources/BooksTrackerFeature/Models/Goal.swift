import Foundation
import SwiftData
import SwiftUI

/// Represents a reading goal with progress tracking and deadlines
///
/// # Usage with @Bindable
///
/// ```swift
/// struct GoalDetailView: View {
///     @Bindable var goal: Goal
///
///     var body: some View {
///         Text(goal.progressDisplay)
///         ProgressView(value: goal.progressPercentage)
///     }
/// }
/// ```
@Model
public final class Goal {
    /// Stable identifier for CloudKit sync (survives sync)
    public var uuid: UUID = UUID()

    // MARK: - Core Properties

    /// User-provided goal title (e.g., "2026 Reading Challenge")
    public var title: String = ""

    /// Type of goal (books read, pages read, etc.)
    public var goalTypeRawValue: String = GoalType.booksRead.rawValue

    /// Target count to achieve (e.g., 52 books, 10000 pages)
    public var targetCount: Int = 0

    /// Current progress value
    public var currentProgress: Int = 0

    /// Current status of the goal
    public var statusRawValue: String = GoalStatus.active.rawValue

    // MARK: - Enum Accessors

    /// Type of goal (computed from raw value)
    public var goalType: GoalType {
        get { GoalType(rawValue: goalTypeRawValue) ?? .booksRead }
        set { goalTypeRawValue = newValue.rawValue }
    }

    /// Status of goal (computed from raw value)
    public var status: GoalStatus {
        get { GoalStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    // MARK: - Temporal Tracking

    /// When the goal was created
    public var dateCreated: Date = Date()

    /// When goal period started (can be backdated)
    public var startDate: Date = Date()

    /// Optional deadline for goal completion
    public var deadline: Date?

    /// When the goal was completed (if status == .completed)
    public var completionDate: Date?

    /// Last time goal metadata was modified
    public var lastModified: Date = Date()

    // MARK: - Metadata

    /// Optional user notes about the goal
    public var notes: String?

    /// Whether this goal is private (hidden from sharing features)
    public var isPrivate: Bool = false

    /// Milestone history for major achievements
    @Attribute(.externalStorage)
    public var milestoneHistory: [String] = []

    // MARK: - Relationships

    /// Relationship to progress snapshots (cascade delete when goal deleted)
    @Relationship(deleteRule: .cascade, inverse: \GoalProgress.goal)
    public var progressSnapshots: [GoalProgress]?

    /// Optional UUIDs for targeted works (if goalType filters by specific books)
    @Attribute(.externalStorage)
    public var targetWorkUUIDs: [UUID] = []

    /// Optional UUIDs for targeted authors (if goalType filters by specific authors)
    @Attribute(.externalStorage)
    public var targetAuthorUUIDs: [UUID] = []

    // MARK: - Computed Properties

    /// Progress as percentage (0.0 to 1.0)
    public var progressPercentage: Double {
        guard targetCount > 0 else { return 0.0 }
        return min(1.0, Double(currentProgress) / Double(targetCount))
    }

    /// Days remaining until deadline (nil if no deadline)
    public var daysRemaining: Int? {
        guard let deadline = deadline else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: deadline)
        return components.day
    }

    /// Whether goal is overdue
    public var isOverdue: Bool {
        guard let deadline = deadline else { return false }
        return Date() > deadline && status == .active
    }

    /// Whether goal is completed
    public var isCompleted: Bool {
        status == .completed || currentProgress >= targetCount
    }

    /// Status emoji for UI display
    public var statusEmoji: String {
        if isCompleted {
            return "🎉"
        } else if isOverdue {
            return "⏰"
        } else if progressPercentage >= 0.75 {
            return "🔥"
        } else if progressPercentage >= 0.5 {
            return "📈"
        } else {
            return "🎯"
        }
    }

    /// Display name combining type and title
    public var displayName: String {
        if title.isEmpty {
            return goalType.displayName
        }
        return title
    }

    /// Progress display string (e.g., "15 / 52 Books")
    public var progressDisplay: String {
        "\(currentProgress) / \(targetCount) \(goalType.unitName)"
    }

    /// Estimated completion date based on current pace (nil if not enough data)
    public var estimatedCompletionDate: Date? {
        guard status == .active,
              currentProgress > 0,
              currentProgress < targetCount,
              let startDate = effectiveStartDate else {
            return nil
        }

        let calendar = Calendar.current
        let daysSinceStart = calendar.dateComponents([.day], from: startDate, to: Date()).day ?? 1
        guard daysSinceStart > 0 else { return nil }

        let progressPerDay = Double(currentProgress) / Double(max(daysSinceStart, 1))
        guard progressPerDay > 0 else { return nil }

        let remainingProgress = targetCount - currentProgress
        let daysToFinish = Double(remainingProgress) / progressPerDay

        return calendar.date(byAdding: .day, value: Int(ceil(daysToFinish)), to: Date())
    }

    /// Effective start date (use startDate if set, otherwise dateCreated)
    private var effectiveStartDate: Date? {
        return startDate
    }

    // MARK: - Validation

    /// Validate goal data integrity
    public func isValid() -> Bool {
        // Title can be empty (will use goalType.displayName)
        guard targetCount > 0 else { return false }
        guard currentProgress >= 0 else { return false }

        // If deadline exists, it should be after start date
        if let deadline = deadline {
            guard deadline > startDate else { return false }
        }

        return true
    }

    // MARK: - Mutations

    /// Update progress and check for milestones
    public func updateProgress(_ newProgress: Int) {
        let oldProgress = currentProgress
        currentProgress = max(0, min(newProgress, targetCount))

        // Check for milestone achievements
        let oldPercentage = targetCount > 0 ? Double(oldProgress) / Double(targetCount) : 0
        let newPercentage = progressPercentage

        // Record major milestones (25%, 50%, 75%, 100%)
        let milestones = [0.25, 0.5, 0.75, 1.0]
        for milestone in milestones {
            if oldPercentage < milestone && newPercentage >= milestone {
                let milestoneText = "Reached \(Int(milestone * 100))% on \(Date().formatted(date: .abbreviated, time: .omitted))"
                milestoneHistory.append(milestoneText)
            }
        }

        // Auto-complete if target reached
        if currentProgress >= targetCount && status == .active {
            status = .completed
            completionDate = Date()
        }

        touch()
    }

    /// Record a milestone achievement
    public func addMilestone(_ milestone: String) {
        milestoneHistory.append("\(milestone) on \(Date().formatted(date: .abbreviated, time: .omitted))")
        touch()
    }

    /// Update last modified timestamp
    public func touch() {
        lastModified = Date()
    }

    /// Pause an active goal
    public func pause() {
        guard status == .active else { return }
        status = .paused
        touch()
    }

    /// Resume a paused goal
    public func resume() {
        guard status == .paused else { return }
        status = .active
        touch()
    }

    /// Abandon a goal
    public func abandon() {
        guard status == .active || status == .paused else { return }
        status = .abandoned
        touch()
    }

    // MARK: - Initializer

    public init(
        title: String = "",
        goalType: GoalType = .booksRead,
        targetCount: Int = 0,
        currentProgress: Int = 0,
        status: GoalStatus = .active,
        startDate: Date = Date(),
        deadline: Date? = nil,
        notes: String? = nil,
        isPrivate: Bool = false
    ) {
        self.title = title
        self.goalTypeRawValue = goalType.rawValue
        self.targetCount = targetCount
        self.currentProgress = currentProgress
        self.statusRawValue = status.rawValue
        self.startDate = startDate
        self.deadline = deadline
        self.notes = notes
        self.isPrivate = isPrivate
    }
}

// MARK: - Enums

/// Type of reading goal
public enum GoalType: String, Codable, CaseIterable, Identifiable, Sendable {
    case booksRead = "Books Read"
    case pagesRead = "Pages Read"
    case authorsExplored = "Authors Explored"
    case genresExplored = "Genres Explored"
    case readingStreak = "Reading Streak (Days)"
    case readingTime = "Reading Time (Hours)"

    public var id: Self { self }

    public var displayName: String {
        rawValue
    }

    public var unitName: String {
        switch self {
        case .booksRead: return "Books"
        case .pagesRead: return "Pages"
        case .authorsExplored: return "Authors"
        case .genresExplored: return "Genres"
        case .readingStreak: return "Days"
        case .readingTime: return "Hours"
        }
    }

    public var icon: String {
        switch self {
        case .booksRead: return "book.closed.fill"
        case .pagesRead: return "doc.text.fill"
        case .authorsExplored: return "person.2.fill"
        case .genresExplored: return "tag.fill"
        case .readingStreak: return "flame.fill"
        case .readingTime: return "clock.fill"
        }
    }

    public var description: String {
        switch self {
        case .booksRead: return "Track number of books completed"
        case .pagesRead: return "Track total pages read"
        case .authorsExplored: return "Discover new authors"
        case .genresExplored: return "Explore different genres"
        case .readingStreak: return "Maintain daily reading habit"
        case .readingTime: return "Track hours spent reading"
        }
    }
}

/// Status of a reading goal
public enum GoalStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case active = "Active"
    case completed = "Completed"
    case paused = "Paused"
    case abandoned = "Abandoned"

    public var id: Self { self }

    public var displayName: String {
        rawValue
    }

    public var systemImage: String {
        switch self {
        case .active: return "chart.line.uptrend.xyaxis"
        case .completed: return "checkmark.circle.fill"
        case .paused: return "pause.circle.fill"
        case .abandoned: return "xmark.circle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .active: return .blue
        case .completed: return .green
        case .paused: return .orange
        case .abandoned: return .gray
        }
    }
}
