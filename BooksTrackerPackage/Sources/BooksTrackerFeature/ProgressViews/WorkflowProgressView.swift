import SwiftUI

/// Progress view for Cloudflare Workflow import
///
/// Displays step-by-step progress of the workflow execution:
/// 1. validate-isbn (12ms)
/// 2. fetch-metadata (1-2s)
/// 3. upload-cover (~300ms)
/// 4. save-database (~50ms)
///
/// ## Usage
///
/// ```swift
/// WorkflowProgressView(isbn: "9780747532743")
/// ```
@available(iOS 26.0, *)
public struct WorkflowProgressView: View {
    
    // MARK: - Properties
    
    let isbn: String
    let source: WorkflowSource
    
    @State private var workflowId: String?
    @State private var status: WorkflowStatus = .running
    @State private var currentStep: String = "validate-isbn"
    @State private var result: WorkflowResult?
    @State private var errorMessage: String?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    private let service = WorkflowImportService()
    
    // Workflow steps in order
    private let steps = [
        "validate-isbn",
        "fetch-metadata",
        "upload-cover",
        "save-database"
    ]
    
    // MARK: - Initialization
    
    public init(isbn: String, source: WorkflowSource = .googleBooks) {
        self.isbn = isbn
        self.source = source
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 32) {
            // Header
            headerView
            
            // Progress Steps
            if status == .running || status == .complete {
                stepsView
            }
            
            // Result or Error
            if status == .complete, let result = result {
                completionView(result: result)
            } else if status == .failed {
                failureView
            }
        }
        .padding()
        .task {
            await startWorkflow()
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.system(size: 48))
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, isActive: status == .running)
            
            Text(statusTitle)
                .font(.title2)
                .fontWeight(.semibold)
        }
    }
    
    private var stepsView: some View {
        VStack(spacing: 16) {
            ForEach(steps, id: \.self) { step in
                StepRow(
                    step: step,
                    currentStep: currentStep,
                    status: status
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
    
    private func completionView(result: WorkflowResult) -> some View {
        VStack(spacing: 16) {
            Text(result.title)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(themeStore.primaryColor)
        }
        .padding()
    }
    
    private var failureView: some View {
        VStack(spacing: 16) {
            Text(errorMessage ?? "Import failed")
                .font(.body)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                Task {
                    await startWorkflow()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    // MARK: - Computed Properties
    
    private var statusIcon: String {
        switch status {
        case .running:
            return "clock.arrow.circlepath"
        case .complete:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .running:
            return themeStore.primaryColor
        case .complete:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var statusTitle: String {
        switch status {
        case .running:
            return "Importing Book..."
        case .complete:
            return "Import Complete"
        case .failed:
            return "Import Failed"
        }
    }
    
    // MARK: - Workflow Logic
    
    private func startWorkflow() async {
        do {
            // Reset state
            status = .running
            currentStep = "validate-isbn"
            errorMessage = nil
            
            // Create workflow
            let id = try await service.createWorkflow(isbn: isbn, source: source)
            workflowId = id
            
            // Poll for completion
            let finalStatus = try await service.pollUntilComplete(
                workflowId: id,
                pollingInterval: .milliseconds(500),
                timeout: .seconds(30)
            ) { statusResponse in
                await MainActor.run {
                    self.currentStep = statusResponse.currentStep ?? self.currentStep
                }
            }
            
            // Update final state
            status = finalStatus.status
            result = finalStatus.result
            
        } catch let error as WorkflowImportError {
            status = .failed
            errorMessage = error.errorDescription
        } catch {
            status = .failed
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Step Row Component

@available(iOS 26.0, *)
private struct StepRow: View {
    let step: String
    let currentStep: String
    let status: WorkflowStatus
    
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: stepIcon)
                .font(.system(size: 20))
                .foregroundStyle(stepColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(stepTitle)
                    .font(.body)
                    .fontWeight(isCurrentStep ? .semibold : .regular)
                
                Text(stepDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isCurrentStep && status == .running {
                ProgressView()
                    .controlSize(.small)
            } else if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var isCurrentStep: Bool {
        step == currentStep
    }
    
    private var isCompleted: Bool {
        guard let currentIndex = steps.firstIndex(of: currentStep),
              let stepIndex = steps.firstIndex(of: step) else {
            return false
        }
        return stepIndex < currentIndex || status == .complete
    }
    
    private var stepIcon: String {
        switch step {
        case "validate-isbn":
            return "checkmark.shield"
        case "fetch-metadata":
            return "book.closed"
        case "upload-cover":
            return "photo.on.rectangle"
        case "save-database":
            return "externaldrive"
        default:
            return "circle"
        }
    }
    
    private var stepColor: Color {
        if isCompleted {
            return .green
        } else if isCurrentStep {
            return themeStore.primaryColor
        } else {
            return .secondary
        }
    }
    
    private var stepTitle: String {
        switch step {
        case "validate-isbn":
            return "Validate ISBN"
        case "fetch-metadata":
            return "Fetch Metadata"
        case "upload-cover":
            return "Upload Cover"
        case "save-database":
            return "Save to Database"
        default:
            return step
        }
    }
    
    private var stepDescription: String {
        switch step {
        case "validate-isbn":
            return "~12ms"
        case "fetch-metadata":
            return "1-2 seconds"
        case "upload-cover":
            return "~300ms"
        case "save-database":
            return "~50ms"
        default:
            return ""
        }
    }
    
    private let steps = [
        "validate-isbn",
        "fetch-metadata",
        "upload-cover",
        "save-database"
    ]
}
