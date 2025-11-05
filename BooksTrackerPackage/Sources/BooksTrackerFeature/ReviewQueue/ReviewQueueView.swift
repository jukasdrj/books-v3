//
//  ReviewQueueView.swift
//  BooksTrackerFeature
//
//  Review Queue for human-in-the-loop correction of AI-detected books
//

import SwiftUI
import SwiftData

#if canImport(UIKit)

/// Review Queue for correcting low-confidence AI detections
@MainActor
public struct ReviewQueueView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore

    @State private var reviewModel = ReviewQueueModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                themeStore.backgroundGradient
                    .ignoresSafeArea()

                if reviewModel.isLoading {
                    loadingView
                } else if let errorMessage = reviewModel.errorMessage {
                    errorView(message: errorMessage)
                } else if reviewModel.isEmpty {
                    emptyStateView
                } else {
                    reviewListView
                }
            }
            .navigationTitle("Review Queue")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await reviewModel.loadReviewQueue(modelContext: modelContext)
            }
        }
    }

    // MARK: - Review List

    private var reviewListView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Queue summary card
                queueSummaryCard

                // Books needing review
                VStack(spacing: 12) {
                    ForEach(reviewModel.worksNeedingReview) { work in
                        ReviewQueueRowView(work: work)
                            .onTapGesture {
                                reviewModel.selectWork(work)
                            }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationDestination(item: $reviewModel.selectedWork) { work in
            CorrectionView(work: work, reviewModel: reviewModel)
        }
    }

    // MARK: - Queue Summary Card

    private var queueSummaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Books Needing Review")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(reviewModel.queueCount) book\(reviewModel.queueCount == 1 ? "" : "s") with low confidence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text("Tap a book to verify or correct AI-detected information")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading Review Queue...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Error Loading Queue")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                Task {
                    await reviewModel.loadReviewQueue(modelContext: modelContext)
                }
            } label: {
                Text("Retry")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background {
                        Capsule()
                            .fill(themeStore.primaryColor)
                    }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("All Clear!")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text("No books require review at this time")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Review Queue Row

struct ReviewQueueRowView: View {
    @Bindable var work: Work
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .frame(width: 60, height: 90)
                .overlay {
                    Image(systemName: "book.closed")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }

            // Book info
            VStack(alignment: .leading, spacing: 6) {
                Text(work.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !work.authorNames.isEmpty {
                    Text("by \(work.authorNames)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Review status badge
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                    Text("Needs Review")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(.orange.opacity(0.15))
                }
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
                }
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var container: ModelContainer = {
        let container = try! ModelContainer(for: Work.self, Author.self)
        let context = container.mainContext

        // Create sample work needing review
        let author = Author(name: "F. Scott Fitzgerald")
        let work = Work(
            title: "The Great Gatsby",
            originalLanguage: "English",
            firstPublicationYear: 1925
        )
        work.reviewStatus = .needsReview

        context.insert(author)
        context.insert(work)
        work.authors = [author]

        return container
    }()

    ReviewQueueView()
        .modelContainer(container)
        .environment(BooksTrackerFeature.iOS26ThemeStore())
}

#endif
