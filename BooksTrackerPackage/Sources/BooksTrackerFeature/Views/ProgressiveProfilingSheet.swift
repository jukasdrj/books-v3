import SwiftUI
import SwiftData

/// Progressive profiling sheet shown after reading sessions (>= 5 minutes)
/// Asks 3-5 questions about the work to enrich diversity metadata
@available(iOS 26.0, *)
public struct ProgressiveProfilingSheet: View {

    // MARK: - Points Configuration

    private enum ProfilingPoints {
        static let culturalOrigins = 15
        static let genderDistribution = 10
        static let translationStatus = 5
        static let cascadeMultiplier = 5
    }
    let work: Work
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.curatorPointsService) private var curatorPointsService

    @State private var currentQuestionIndex = 0
    @State private var answers: [String: String] = [:]
    @State private var showCelebration = false
    @State private var showCascadeConfirmation = false
    @State private var pendingCascadeAnswer: (answer: String, question: ProfileQuestion)?
    @State private var affectedWorksCount = 0
    @State private var pointsAwarded = 0

    // Questions to ask (filtered based on missing data)
    @State private var questions: [ProfileQuestion] = []

    public init(work: Work, onComplete: @escaping () -> Void) {
        self.work = work
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                if showCelebration {
                    CelebrationView(pointsAwarded: pointsAwarded)
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                dismiss()
                                onComplete()
                            }
                        }
                } else if showCascadeConfirmation {
                    cascadeConfirmationView
                } else {
                    questionnaireView
                }
            }
            .navigationTitle("Add Book Information")
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

    // MARK: - Cascade Confirmation View

    private var cascadeConfirmationView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Cascade icon
            VStack(spacing: 16) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(themeStore.primaryColor)

                VStack(spacing: 8) {
                    Text("Apply to All Books?")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    if let author = work.primaryAuthor {
                        Text("This will apply to all \(affectedWorksCount) books by \(author.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // Gamification preview
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        Text("+\(affectedWorksCount * 5) Curator Points")
                            .font(.caption.bold())
                            .foregroundColor(themeStore.primaryColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .fill(themeStore.primaryColor.opacity(0.1))
                    }
                    .padding(.top, 4)
                }
            }

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                // Confirm cascade
                Button(action: {
                    confirmCascade()
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Yes, Apply to All")
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

                // Just this book
                Button(action: {
                    skipCascade()
                }) {
                    Text("Just This Book")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
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
        // Check if this is an author-level question that should trigger cascade
        let isAuthorQuestion = question.isAuthorLevel

        if isAuthorQuestion, let author = work.primaryAuthor {
            // Count affected works
            Task {
                let count = await countAffectedWorks(authorId: author.persistentModelID)
                await MainActor.run {
                    affectedWorksCount = count

                    // Only show cascade confirmation if there are multiple works
                    if count > 1 {
                        pendingCascadeAnswer = (answer, question)
                        withAnimation {
                            showCascadeConfirmation = true
                        }
                    } else {
                        // Single work, just save and continue
                        answers[question.dimension] = answer
                        moveToNextQuestion()
                    }
                }
            }
        } else {
            // Not an author question, just save and continue
            answers[question.dimension] = answer
            moveToNextQuestion()
        }
    }

    private func moveToNextQuestion() {
        if currentQuestionIndex < questions.count - 1 {
            withAnimation {
                currentQuestionIndex += 1
            }
        } else {
            // All questions answered - save and show success
            saveAnswers()
            awardPoints()
            withAnimation {
                showCelebration = true
            }
        }
    }

    private func awardPoints() {
        var totalPoints = 0
        for (dimension, _) in answers {
            switch dimension {
            case "culturalOrigins":
                totalPoints += ProfilingPoints.culturalOrigins
            case "genderDistribution":
                totalPoints += ProfilingPoints.genderDistribution
            case "translationStatus":
                totalPoints += ProfilingPoints.translationStatus
            default:
                break
            }
        }

        if affectedWorksCount > 1 {
            totalPoints += affectedWorksCount * ProfilingPoints.cascadeMultiplier
        }

        self.pointsAwarded = totalPoints
        curatorPointsService?.awardPoints(totalPoints, for: "Progressive Profiling Contribution")
    }


    private func confirmCascade() {
        guard let pending = pendingCascadeAnswer else { return }

        // Save answer
        answers[pending.question.dimension] = pending.answer

        // Trigger cascade
        Task {
            await applyCascade(answer: pending.answer, question: pending.question)
            await MainActor.run {
                pendingCascadeAnswer = nil
                showCascadeConfirmation = false
                moveToNextQuestion()
            }
        }
    }

    private func skipCascade() {
        guard let pending = pendingCascadeAnswer else { return }

        // Save answer for just this work (no cascade)
        answers[pending.question.dimension] = pending.answer

        withAnimation {
            pendingCascadeAnswer = nil
            showCascadeConfirmation = false
            moveToNextQuestion()
        }
    }

    private func countAffectedWorks(authorId: PersistentIdentifier) async -> Int {
        do {
            let descriptor = FetchDescriptor<Work>()
            let allWorks = try modelContext.fetch(descriptor)

            let count = allWorks.filter { work in
                guard let authors = work.authors else { return false }
                return authors.contains(where: { $0.persistentModelID == authorId })
            }.count

            return count
        } catch {
            #if DEBUG
            print("❌ Failed to count affected works: \(error)")
            #endif
            return 1
        }
    }

    private func applyCascade(answer: String, question: ProfileQuestion) async {
        guard let author = work.primaryAuthor else { return }

        let cascadeService = BooksTrackerFeature.CascadeMetadataService(modelContext: modelContext)
        let authorId = author.persistentModelID.hashValue.description

        do {
            // Map question dimension to AuthorMetadata fields
            switch question.dimension {
            case "culturalOrigins":
                try await cascadeService.updateAuthorMetadata(
                    authorId: authorId,
                    culturalBackground: [answer],
                    userId: "default-user"
                )
            case "genderDistribution":
                try await cascadeService.updateAuthorMetadata(
                    authorId: authorId,
                    genderIdentity: answer,
                    userId: "default-user"
                )
            default:
                break
            }
        } catch {
            #if DEBUG
            print("❌ Failed to apply cascade: \(error)")
            #endif
        }
    }

    private func saveAnswers() {
        let statsService = DiversityStatsService(modelContext: modelContext)
        guard let entry = work.userLibraryEntries?.first else { return }
        let entryId = entry.persistentModelID

        Task {
            for (dimension, value) in answers {
                do {
                    try await statsService.updateDiversityData(
                        entryId: entryId,
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

    /// Whether this question is about the author (triggers cascade)
    var isAuthorLevel: Bool {
        dimension == "culturalOrigins" || dimension == "genderDistribution"
    }
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

    ProgressiveProfilingSheet(work: Work(title: "Sample Book"), onComplete: {
        print("Profiling complete")
    })
    .modelContainer(container)
    .environment(\.iOS26ThemeStore, themeStore)
}
