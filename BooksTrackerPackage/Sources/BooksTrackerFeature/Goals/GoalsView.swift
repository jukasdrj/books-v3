import SwiftUI
import SwiftData

/// Main Goals view - displays all reading goals with progress tracking
@MainActor
@available(iOS 26.0, *)
public struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore

    @Query(
        filter: #Predicate<Goal> { $0.statusRawValue != "Abandoned" },
        sort: [
            SortDescriptor(\Goal.statusRawValue, order: .forward),
            SortDescriptor(\Goal.dateCreated, order: .reverse)
        ]
    ) private var goals: [Goal]

    @State private var showingCreateGoal = false
    @State private var selectedGoal: Goal?
    @State private var showingGoalDetail = false

    public init() {}

    public var body: some View {
        ZStack {
            // Themed background
            themeStore.backgroundGradient
                .ignoresSafeArea()

            Group {
                if goals.isEmpty {
                    emptyStateView
                } else {
                    goalsListView
                }
            }
        }
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateGoal = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
        .sheet(isPresented: $showingCreateGoal) {
            CreateGoalSheet()
        }
        .sheet(item: $selectedGoal) { goal in
            GoalDetailSheet(goal: goal)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "target")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Text("No Goals Yet")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Set reading goals to track your progress and stay motivated throughout the year.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                showingCreateGoal = true
            } label: {
                Label("Create Your First Goal", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    private var goalsListView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Summary card
                summaryCard

                // Goals list
                VStack(spacing: 16) {
                    ForEach(activeGoals) { goal in
                        Button {
                            selectedGoal = goal
                            showingGoalDetail = true
                        } label: {
                            GoalCard(goal: goal)
                        }
                        .buttonStyle(.plain)
                    }

                    // Completed goals section
                    if !completedGoals.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Completed")
                                    .font(.headline)
                                Spacer()
                                Text("\(completedGoals.count)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)

                            ForEach(completedGoals) { goal in
                                Button {
                                    selectedGoal = goal
                                    showingGoalDetail = true
                                } label: {
                                    GoalCard(goal: goal)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .padding()
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Progress")
                        .font(.headline)
                    Text("\(activeGoals.count) active • \(completedGoals.count) completed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Quick stats
            HStack(spacing: 20) {
                statBox(
                    value: "\(totalProgress)",
                    label: "Total Progress",
                    icon: "arrow.up.circle.fill",
                    color: .blue
                )

                statBox(
                    value: "\(averageProgress)%",
                    label: "Avg. Complete",
                    icon: "percent",
                    color: .green
                )

                statBox(
                    value: "\(overdueCount)",
                    label: "Overdue",
                    icon: "exclamationmark.triangle.fill",
                    color: .red
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }

    private func statBox(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }

    // MARK: - Computed Properties

    private var activeGoals: [Goal] {
        goals.filter { $0.status == .active || $0.status == .paused }
    }

    private var completedGoals: [Goal] {
        goals.filter { $0.status == .completed }
    }

    private var totalProgress: Int {
        goals.reduce(0) { $0 + $1.currentProgress }
    }

    private var averageProgress: Int {
        guard !goals.isEmpty else { return 0 }
        let totalPercentage = goals.reduce(0.0) { $0 + $1.progressPercentage }
        return Int((totalPercentage / Double(goals.count)) * 100)
    }

    private var overdueCount: Int {
        goals.filter { $0.isOverdue }.count
    }
}

// MARK: - Goal Detail Sheet

@available(iOS 26.0, *)
struct GoalDetailSheet: View {
    @Bindable var goal: Goal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingDeleteAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Large progress ring
                    GoalProgressRing(
                        progress: goal.progressPercentage,
                        size: 200,
                        lineWidth: 20
                    )
                    .padding(.vertical)

                    // Goal details
                    VStack(alignment: .leading, spacing: 16) {
                        detailRow(icon: "flag.fill", label: "Goal Type", value: goal.goalType.displayName)
                        detailRow(icon: "target", label: "Target", value: "\(goal.targetCount) \(goal.goalType.unitName)")
                        detailRow(icon: "chart.bar.fill", label: "Progress", value: goal.progressDisplay)

                        if let deadline = goal.deadline {
                            detailRow(
                                icon: "calendar",
                                label: "Deadline",
                                value: deadline.formatted(date: .abbreviated, time: .omitted)
                            )
                        }

                        if let notes = goal.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "note.text")
                                        .foregroundColor(.secondary)
                                    Text("Notes")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                }

                                Text(notes)
                                    .font(.body)
                                    .foregroundColor(.primary)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )

                    // Milestones
                    if !goal.milestoneHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text("Milestones")
                                    .font(.headline)
                            }
                            .padding(.horizontal)

                            ForEach(goal.milestoneHistory, id: \.self) { milestone in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(Color.yellow)
                                        .frame(width: 8, height: 8)
                                        .offset(y: 6)

                                    Text(milestone)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }

                    // Action buttons
                    VStack(spacing: 12) {
                        if goal.status == .active {
                            Button {
                                goal.pause()
                            } label: {
                                Label("Pause Goal", systemImage: "pause.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        } else if goal.status == .paused {
                            Button {
                                goal.resume()
                            } label: {
                                Label("Resume Goal", systemImage: "play.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete Goal", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top)
                }
                .padding()
            }
            .navigationTitle(goal.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Goal?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    modelContext.delete(goal)
                    try? modelContext.save()
                    dismiss()
                }
            } message: {
                Text("This action cannot be undone. All progress and milestones will be permanently deleted.")
            }
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}


// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Goals View with Data") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, configurations: config)

    let goal1 = Goal(
        title: "2026 Reading Challenge",
        goalType: .booksRead,
        targetCount: 52,
        currentProgress: 15,
        status: .active,
        deadline: Calendar.current.date(byAdding: .month, value: 10, to: Date()),
        notes: "Focusing on diverse authors"
    )

    let goal2 = Goal(
        title: "Page Turner",
        goalType: .pagesRead,
        targetCount: 10000,
        currentProgress: 7500,
        status: .active
    )

    let goal3 = Goal(
        title: "Author Discovery",
        goalType: .authorsExplored,
        targetCount: 20,
        currentProgress: 20,
        status: .completed
    )

    container.mainContext.insert(goal1)
    container.mainContext.insert(goal2)
    container.mainContext.insert(goal3)

    return NavigationStack {
        GoalsView()
    }
    .modelContainer(container)
}

@available(iOS 26.0, *)
#Preview("Empty Goals View") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, configurations: config)

    return NavigationStack {
        GoalsView()
    }
    .modelContainer(container)
}
