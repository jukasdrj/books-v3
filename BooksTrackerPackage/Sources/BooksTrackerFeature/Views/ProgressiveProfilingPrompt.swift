import SwiftUI
import SwiftData

/// Progressive profiling prompt shown after reading sessions (>= 5 minutes)
/// Asks 3-5 questions about the work to enrich diversity metadata
@available(iOS 26.0, *)
public struct ProgressiveProfilingPrompt: View {
    let work: Work
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore

    @State private var currentQuestionIndex = 0
    @State private var answers: [String: String] = [:]
    @State private var showSuccessState = false

    // Questions to ask (filtered based on missing data)
    @State private var questions: [ProfileQuestion] = []

    public init(work: Work, onComplete: @escaping () -> Void) {
        self.work = work
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                if showSuccessState {
                    successView
                } else {
                    questionnaireView
                }
            }
            .navigationTitle("Help Us Learn")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadQuestions()
        }
    }

    // MARK: - Questionnaire View

    private var questionnaireView: some View {
        VStack(spacing: 24) {
            // Progress indicator
            progressIndicator

            // Current question
            if currentQuestionIndex < questions.count {
                let question = questions[currentQuestionIndex]

                VStack(alignment: .leading, spacing: 16) {
                    // Question header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(question.title)
                            .font(.title2.bold())
                            .foregroundStyle(.primary)

                        if let subtitle = question.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                        .frame(height: 8)

                    // Answer options
                    ForEach(question.options, id: \.self) { option in
                        optionButton(for: option, question: question)
                    }
                }
                .padding()
            }

            Spacer()
        }
        .padding()
    }

    private var progressIndicator: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<questions.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= currentQuestionIndex ? themeStore.primaryColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                }
            }

            Text("Question \(currentQuestionIndex + 1) of \(questions.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func optionButton(for option: String, question: ProfileQuestion) -> some View {
        Button(action: {
            selectAnswer(option, for: question)
        }) {
            HStack {
                Text(option)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .systemBackground).opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.green)

            // Success message
            VStack(spacing: 12) {
                Text("Thank You!")
                    .font(.title.bold())
                    .foregroundStyle(.primary)

                Text("Your input helps us understand your reading diversity better.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Done button
            Button(action: {
                dismiss()
                onComplete()
            }) {
                HStack {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Done")
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeStore.primaryColor)
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Question Loading

    private func loadQuestions() async {
        // Build questions based on missing data
        var questionsToAsk: [ProfileQuestion] = []

        // 1. Cultural Origin (if missing)
        if work.primaryAuthor?.culturalRegion == nil {
            questionsToAsk.append(
                ProfileQuestion(
                    dimension: "culturalOrigins",
                    title: "What is the author's cultural background?",
                    subtitle: "Help us track representation from different regions",
                    options: CulturalRegion.allCases.map { $0.displayName }
                )
            )
        }

        // 2. Gender (if missing or unknown)
        if work.primaryAuthor == nil || work.primaryAuthor?.gender == .unknown {
            questionsToAsk.append(
                ProfileQuestion(
                    dimension: "genderDistribution",
                    title: "What is the author's gender identity?",
                    subtitle: "Helps track gender diversity in your reading",
                    options: AuthorGender.allCases.filter { $0 != .unknown }.map { $0.displayName }
                )
            )
        }

        // 3. Original Language / Translation (if missing)
        if work.originalLanguage == nil || work.originalLanguage?.isEmpty == true {
            questionsToAsk.append(
                ProfileQuestion(
                    dimension: "translationStatus",
                    title: "What is the book's original language?",
                    subtitle: "Helps track translated works",
                    options: [
                        "English",
                        "Spanish",
                        "French",
                        "German",
                        "Chinese",
                        "Japanese",
                        "Korean",
                        "Arabic",
                        "Portuguese",
                        "Other"
                    ]
                )
            )
        }

        // Limit to 3-5 questions (take first 3-5)
        await MainActor.run {
            questions = Array(questionsToAsk.prefix(5))
        }
    }

    // MARK: - Answer Selection

    private func selectAnswer(_ answer: String, for question: ProfileQuestion) {
        // Save answer
        answers[question.dimension] = answer

        // Move to next question or show success
        if currentQuestionIndex < questions.count - 1 {
            withAnimation {
                currentQuestionIndex += 1
            }
        } else {
            // All questions answered - save and show success
            saveAnswers()
            withAnimation {
                showSuccessState = true
            }
        }
    }

    private func saveAnswers() {
        let statsService = DiversityStatsService(modelContext: modelContext)
        let workId = work.persistentModelID

        Task {
            for (dimension, value) in answers {
                do {
                    try await statsService.updateDiversityData(
                        workId: workId,
                        dimension: dimension,
                        value: value
                    )
                } catch {
                    #if DEBUG
                    print("❌ Failed to save \(dimension): \(error)")
                    #endif
                }
            }
        }
    }
}

// MARK: - Supporting Types

private struct ProfileQuestion {
    let dimension: String // "culturalOrigins", "genderDistribution", "translationStatus"
    let title: String
    let subtitle: String?
    let options: [String]
}

// MARK: - Preview

#Preview {
    @Previewable @State var container: ModelContainer = {
        let container = try! ModelContainer(for: Work.self, Author.self)
        let context = container.mainContext

        let author = Author(name: "Sample Author")
        let work = Work(title: "Sample Book")

        context.insert(author)
        context.insert(work)

        work.authors = [author]

        return container
    }()

    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    ProgressiveProfilingPrompt(work: Work(title: "Sample Book"), onComplete: {
        print("Profiling complete")
    })
    .modelContainer(container)
    .environment(\.iOS26ThemeStore, themeStore)
}
