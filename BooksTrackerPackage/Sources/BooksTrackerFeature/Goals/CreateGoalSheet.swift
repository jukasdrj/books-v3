import SwiftUI
import SwiftData

/// Sheet for creating a new reading goal
@available(iOS 26.0, *)
public struct CreateGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title: String = ""
    @State private var goalType: GoalType = .booksRead
    @State private var targetCount: String = ""
    @State private var hasDeadline: Bool = false
    @State private var deadline: Date = Calendar.current.date(byAdding: .month, value: 12, to: Date()) ?? Date()
    @State private var notes: String = ""
    @State private var isPrivate: Bool = false
    @State private var startDate: Date = Date()

    @State private var showingValidationError: Bool = false
    @State private var validationMessage: String = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // Basic Information
                Section {
                    TextField("Goal Title", text: $title)
                        .autocorrectionDisabled()

                    Picker("Goal Type", selection: $goalType) {
                        ForEach(GoalType.allCases) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }

                    HStack {
                        Text("Target")
                        Spacer()
                        TextField("0", text: $targetCount)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(goalType.unitName)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Goal Details")
                } footer: {
                    Text(goalType.description)
                        .font(.caption)
                }

                // Timeline
                Section("Timeline") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)

                    Toggle("Set Deadline", isOn: $hasDeadline)

                    if hasDeadline {
                        DatePicker(
                            "Deadline",
                            selection: $deadline,
                            in: startDate...,
                            displayedComponents: .date
                        )
                    }
                }

                // Additional Options
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                            .background(Color(.systemBackground))
                    }

                    Toggle("Private Goal", isOn: $isPrivate)
                } header: {
                    Text("Optional")
                } footer: {
                    Text("Private goals won't appear in shared statistics or exports.")
                }

                // Preview
                if isValid {
                    Section("Preview") {
                        previewCard
                    }
                }
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createGoal()
                    }
                    .disabled(!isValid)
                }
            }
            .alert("Invalid Goal", isPresented: $showingValidationError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: goalType.icon)
                    .foregroundColor(.blue)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(effectiveTitle)
                        .font(.headline)
                    Text(goalType.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                // Mini progress ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 4)

                    Circle()
                        .trim(from: 0, to: 0.0)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text("0%")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Target: \(targetCountInt) \(goalType.unitName)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if hasDeadline {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text("Due \(deadline.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            if !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    // MARK: - Validation

    private var isValid: Bool {
        !title.isEmpty && targetCountInt > 0
    }

    private var effectiveTitle: String {
        title.isEmpty ? goalType.displayName : title
    }

    private var targetCountInt: Int {
        Int(targetCount) ?? 0
    }

    // MARK: - Actions

    private func createGoal() {
        guard isValid else {
            validationMessage = "Please provide a title and target greater than 0."
            showingValidationError = true
            return
        }

        // Validate deadline is after start date
        if hasDeadline && deadline <= startDate {
            validationMessage = "Deadline must be after the start date."
            showingValidationError = true
            return
        }

        let goal = Goal(
            title: title,
            goalType: goalType,
            targetCount: targetCountInt,
            currentProgress: 0,
            status: .active,
            startDate: startDate,
            deadline: hasDeadline ? deadline : nil,
            notes: notes.isEmpty ? nil : notes,
            isPrivate: isPrivate
        )

        modelContext.insert(goal)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            validationMessage = "Failed to save goal: \(error.localizedDescription)"
            showingValidationError = true
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Create Goal Sheet") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, configurations: config)

    return CreateGoalSheet()
        .modelContainer(container)
}
