import SwiftUI
import SwiftData

/// A card displaying a single goal with progress visualization
@available(iOS 26.0, *)
public struct GoalCard: View {
    @Bindable var goal: Goal
    @Environment(\.iOS26ThemeStore) private var themeStore

    public init(goal: Goal) {
        self.goal = goal
    }

    private var estimatedCompletionText: String? {
        guard let estimatedDate = goal.estimatedCompletionDate else {
            return nil
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Est. completion: \(formatter.localizedString(for: estimatedDate, relativeTo: Date()))"
    }

    private var deadlineText: String? {
        guard let deadline = goal.deadline else {
            return nil
        }

        if goal.isOverdue {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Overdue by \(formatter.localizedString(for: deadline, relativeTo: Date()).replacingOccurrences(of: "in ", with: ""))"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Due \(formatter.localizedString(for: deadline, relativeTo: Date()))"
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with title and status
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: goal.goalType.icon)
                            .foregroundColor(goal.status.color)
                            .font(.title3)

                        Text(goal.displayName)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }

                    Text(goal.goalType.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status badge
                HStack(spacing: 4) {
                    Text(goal.statusEmoji)
                        .font(.caption)
                    Text(goal.status.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(goal.status.color.opacity(0.15))
                .foregroundColor(goal.status.color)
                .clipShape(Capsule())
            }

            // Progress visualization
            HStack(spacing: 20) {
                // Progress ring
                GoalProgressRing(
                    progress: goal.progressPercentage,
                    size: 80,
                    lineWidth: 8
                )

                // Progress details
                VStack(alignment: .leading, spacing: 8) {
                    // Current progress
                    Text(goal.progressDisplay)
                        .font(.title3)
                        .fontWeight(.bold)

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Track
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))

                            // Progress
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [goal.status.color, goal.status.color.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * goal.progressPercentage)
                                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: goal.progressPercentage)
                        }
                    }
                    .frame(height: 8)

                    // Deadline or estimated completion
                    if let deadlineText = deadlineText {
                        HStack(spacing: 4) {
                            Image(systemName: goal.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                                .foregroundColor(goal.isOverdue ? .red : .secondary)
                                .font(.caption2)
                            Text(deadlineText)
                                .font(.caption)
                                .foregroundColor(goal.isOverdue ? .red : .secondary)
                        }
                    } else if let estimatedText = estimatedCompletionText {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                            Text(estimatedText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Notes (if any)
            if let notes = goal.notes, !notes.isEmpty {
                Divider()

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "note.text")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .offset(y: 2)

                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    goal.isCompleted ? goal.status.color.opacity(0.5) : Color.clear,
                    lineWidth: 2
                )
        )
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Active Goals") {
    let goal1 = Goal(
        title: "2026 Reading Challenge",
        goalType: .booksRead,
        targetCount: 52,
        currentProgress: 15,
        status: .active,
        deadline: Calendar.current.date(byAdding: .month, value: 10, to: Date()),
        notes: "Focusing on diverse authors and genres this year"
    )

    let goal2 = Goal(
        title: "Epic Fantasy Marathon",
        goalType: .pagesRead,
        targetCount: 10000,
        currentProgress: 7500,
        status: .active,
        deadline: Calendar.current.date(byAdding: .month, value: 3, to: Date())
    )

    let goal3 = Goal(
        title: "New Authors Discovery",
        goalType: .authorsExplored,
        targetCount: 20,
        currentProgress: 5,
        status: .active
    )

    return ScrollView {
        VStack(spacing: 20) {
            GoalCard(goal: goal1)
            GoalCard(goal: goal2)
            GoalCard(goal: goal3)
        }
        .padding()
    }
}

@available(iOS 26.0, *)
#Preview("Goal States") {
    let completed = Goal(
        title: "Summer Reading Sprint",
        goalType: .booksRead,
        targetCount: 10,
        currentProgress: 10,
        status: .completed,
        notes: "Completed on August 15, 2026!"
    )

    let overdue = Goal(
        title: "Classics Challenge",
        goalType: .booksRead,
        targetCount: 12,
        currentProgress: 6,
        status: .active,
        deadline: Calendar.current.date(byAdding: .day, value: -10, to: Date())
    )

    let paused = Goal(
        title: "Sci-Fi Deep Dive",
        goalType: .pagesRead,
        targetCount: 5000,
        currentProgress: 1200,
        status: .paused,
        notes: "Taking a break to read some lighter material"
    )

    return ScrollView {
        VStack(spacing: 20) {
            GoalCard(goal: completed)
            GoalCard(goal: overdue)
            GoalCard(goal: paused)
        }
        .padding()
    }
}
