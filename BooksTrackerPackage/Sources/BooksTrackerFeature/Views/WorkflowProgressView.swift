import SwiftUI

/// View displaying step-by-step progress of a Cloudflare Workflow import
///
/// Shows the progression through workflow steps (validate → fetch → upload → save)
/// with visual feedback for completed, in-progress, and pending steps.
struct WorkflowProgressView: View {
    let workflowId: String
    let onComplete: (WorkflowResult) -> Void
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @State private var status: WorkflowStatus = .running
    @State private var currentStep: WorkflowStep?
    @State private var errorMessage: String?
    @State private var result: WorkflowResult?

    private let workflowService = WorkflowImportService()
    private let allSteps = WorkflowStep.allCases

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                headerSection
                stepsSection
                Spacer()
                actionSection
            }
            .padding()
            .navigationTitle("Importing Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if status != .running {
                        Button("Close") {
                            onDismiss()
                        }
                    }
                }
            }
            .task {
                await runWorkflow()
            }
        }
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 8) {
            switch status {
            case .running:
                ProgressView()
                    .scaleEffect(1.5)
                    .padding(.bottom, 8)
                Text("Importing your book...")
                    .font(.headline)
                Text("This usually takes a few seconds")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Import Complete!")
                    .font(.headline)
                if let result {
                    Text(result.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("Import Failed")
                    .font(.headline)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.vertical, 24)
    }

    // MARK: - Steps Section

    private var stepsSection: some View {
        VStack(spacing: 16) {
            ForEach(allSteps, id: \.self) { step in
                HStack(spacing: 12) {
                    stepIndicator(for: step)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.displayName)
                            .font(.body)
                            .foregroundStyle(stepTextColor(for: step))
                        if step == currentStep && status == .running {
                            Text("In progress...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func stepIndicator(for step: WorkflowStep) -> some View {
        let stepState = self.stepState(for: step)

        ZStack {
            Circle()
                .fill(stepBackgroundColor(for: stepState))
                .frame(width: 32, height: 32)

            switch stepState {
            case .completed:
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            case .inProgress:
                ProgressView()
                    .scaleEffect(0.7)
            case .failed:
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            case .pending:
                Image(systemName: step.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Action Section

    @ViewBuilder
    private var actionSection: some View {
        switch status {
        case .running:
            EmptyView()

        case .complete:
            Button(action: {
                if let result {
                    onComplete(result)
                }
            }) {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .failed:
            VStack(spacing: 12) {
                Button(action: onRetry) {
                    Text("Try Again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Cancel", action: onDismiss)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step State

    private enum StepState {
        case completed
        case inProgress
        case failed
        case pending
    }

    private func stepState(for step: WorkflowStep) -> StepState {
        guard let currentStep else { return .pending }

        let currentIndex = allSteps.firstIndex(of: currentStep) ?? 0
        let stepIndex = allSteps.firstIndex(of: step) ?? 0

        if status == .complete {
            return .completed
        }

        if status == .failed {
            if step == currentStep {
                return .failed
            }
            if stepIndex < currentIndex {
                return .completed
            }
            return .pending
        }

        // Running
        if stepIndex < currentIndex {
            return .completed
        }
        if step == currentStep {
            return .inProgress
        }
        return .pending
    }

    private func stepBackgroundColor(for state: StepState) -> Color {
        switch state {
        case .completed: return .green
        case .inProgress: return .blue
        case .failed: return .red
        case .pending: return Color(.systemGray5)
        }
    }

    private func stepTextColor(for step: WorkflowStep) -> Color {
        let state = stepState(for: step)
        switch state {
        case .completed, .inProgress: return .primary
        case .failed: return .red
        case .pending: return .secondary
        }
    }

    // MARK: - Workflow Execution

    private func runWorkflow() async {
        do {
            let workflowResult = try await workflowService.pollUntilComplete(
                workflowId: workflowId,
                onProgress: { step in
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.currentStep = step
                        }
                    }
                }
            )

            await MainActor.run {
                withAnimation {
                    self.result = workflowResult
                    self.status = .complete
                }
            }
        } catch let error as WorkflowError {
            await MainActor.run {
                withAnimation {
                    self.errorMessage = error.errorDescription
                    self.status = .failed
                }
            }
        } catch {
            await MainActor.run {
                withAnimation {
                    self.errorMessage = error.localizedDescription
                    self.status = .failed
                }
            }
        }
    }
}

#Preview {
    WorkflowProgressView(
        workflowId: "preview-workflow",
        onComplete: { _ in },
        onRetry: {},
        onDismiss: {}
    )
}
