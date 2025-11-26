import SwiftUI

@MainActor
public struct WorkflowProgressView: View {
    let workflowId: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    private let importService = WorkflowImportService()

    @State private var status: WorkflowStatus = .running
    @State private var currentStep: String = "validate-isbn"
    @State private var errorMessage: String?
    @State private var timeElapsed: TimeInterval = 0.0

    private let steps = ["validate-isbn", "fetch-metadata", "upload-cover", "save-database"]
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    public var body: some View {
        VStack(spacing: 20) {
            Text("Importing Book...")
                .font(.largeTitle)
                .bold()

            ForEach(steps, id: \.self) { step in
                HStack {
                    Image(systemName: stepIcon(for: step))
                        .foregroundColor(stepColor(for: step))
                    Text(step)
                        .foregroundColor(stepColor(for: step))
                    Spacer()
                }
                .padding(.horizontal)
            }

            if status == .complete {
                Text("Import Successful!")
                    .foregroundColor(.green)
                    .bold()
                Button("Done", action: onDismiss)
            }

            if let errorMessage = errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
                Button("Retry", action: onRetry)
            }
        }
        .padding()
        .task {
            await pollWorkflowStatus()
        }
        .onReceive(timer) { _ in
            if status == .running {
                timeElapsed += 0.1
                if timeElapsed >= 30.0 {
                    self.status = .failed
                    self.errorMessage = "Import timed out."
                    timer.upstream.connect().cancel()
                }
            }
        }
    }

    private func pollWorkflowStatus() async {
        while status == .running {
            do {
                let response = try await importService.getWorkflowStatus(workflowId: workflowId)
                self.status = response.status
                self.currentStep = response.currentStep ?? ""

                if status == .complete {
                    break
                } else if status == .failed {
                    if response.result?.success == false {
                        self.errorMessage = "Import failed at step: \(currentStep)"
                    } else {
                        self.errorMessage = "An unknown error occurred."
                    }
                    break
                }

            } catch {
                self.status = .failed
                self.errorMessage = error.localizedDescription
                break
            }

            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func stepIcon(for step: String) -> String {
        let stepIndex = steps.firstIndex(of: step) ?? -1
        let currentStepIndex = steps.firstIndex(of: currentStep) ?? -1

        if status == .complete {
            return "checkmark.circle.fill"
        } else if stepIndex < currentStepIndex {
            return "checkmark.circle.fill"
        } else if step == currentStep && status == .running {
            return "ellipsis.circle.fill"
        } else if status == .failed && step == currentStep {
            return "xmark.circle.fill"
        } else {
            return "circle"
        }
    }

    private func stepColor(for step: String) -> Color {
        let stepIndex = steps.firstIndex(of: step) ?? -1
        let currentStepIndex = steps.firstIndex(of: currentStep) ?? -1

        if status == .complete {
            return .green
        } else if stepIndex < currentStepIndex {
            return .green
        } else if step == currentStep && status == .running {
            return .blue
        } else if status == .failed && step == currentStep {
            return .red
        } else {
            return .gray
        }
    }
}
