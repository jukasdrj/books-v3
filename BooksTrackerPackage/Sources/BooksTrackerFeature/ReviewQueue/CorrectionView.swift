//
//  CorrectionView.swift
//  BooksTrackerFeature
//
//  Edit and correct AI-detected book information with cropped spine image
//

import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit

/// Correction UI for editing AI-detected book metadata
@MainActor
public struct CorrectionView: View {
    @Bindable var work: Work
    let reviewModel: ReviewQueueModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore

    @State private var editedTitle: String
    @State private var editedAuthor: String
    @State private var selectedFormat: EditionFormat
    @State private var croppedImage: UIImage?
    @State private var isSaving = false
    @State private var showingManualMatch = false
    @FocusState private var focusedField: Field?

    public init(work: Work, reviewModel: ReviewQueueModel) {
        self.work = work
        self.reviewModel = reviewModel

        // Initialize edit fields with current values
        _editedTitle = State(initialValue: work.title)
        _editedAuthor = State(initialValue: work.authorNames)

        // Initialize format from work's primary edition, or default to hardcover
        let initialFormat = work.primaryEdition?.format ?? .hardcover
        _selectedFormat = State(initialValue: initialFormat)
    }

    private enum Field {
        case title, author
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Cropped spine image
                croppedSpineImageView

                // Edit fields
                editFieldsView

                // Action buttons
                actionButtonsView

                // Bottom spacer
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(themeStore.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Review Book")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadCroppedImage()
        }
        .sheet(isPresented: $showingManualMatch) {
            ManualMatchView(work: work)
        }
    }

    // MARK: - Cropped Spine Image

    private var croppedSpineImageView: some View {
        VStack(spacing: 12) {
            if let croppedImage = croppedImage {
                Image(uiImage: croppedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .frame(height: 200)
                    .overlay {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Loading image...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
            }

            Text("AI-Detected Spine")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Edit Fields

    private var editFieldsView: some View {
        VStack(spacing: 16) {
            // Title field
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Book Title", text: $editedTitle)
                    .textFieldStyle(.plain)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }
                    .focused($focusedField, equals: .title)
            }

            // Author field
            VStack(alignment: .leading, spacing: 8) {
                Text("Author")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Author Name", text: $editedAuthor)
                    .textFieldStyle(.plain)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }
                    .focused($focusedField, equals: .author)
            }

            // Format picker (Hardcover / Paperback / Digital)
            VStack(alignment: .leading, spacing: 8) {
                Text("Format")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Format", selection: $selectedFormat) {
                    HStack {
                        Image(systemName: "book.closed.fill")
                        Text("Hardcover")
                    }.tag(EditionFormat.hardcover)

                    HStack {
                        Image(systemName: "book.closed")
                        Text("Paperback")
                    }.tag(EditionFormat.paperback)

                    HStack {
                        Image(systemName: "ipad")
                        Text("Digital")
                    }.tag(EditionFormat.ebook)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtonsView: some View {
        VStack(spacing: 12) {
            // Search for Match button (new feature)
            Button {
                showingManualMatch = true
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.title3)
                    
                    Text("Search for Match")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.blue.gradient)
                }
            }
            .disabled(isSaving)
            
            // Save Corrections button
            Button {
                Task {
                    await saveCorrections()
                }
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                    }

                    Text(hasChanges ? "Save Corrections" : "Mark as Verified")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(themeStore.primaryColor.gradient)
                }
            }
            .disabled(isSaving || editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            // Cancel button
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    }
            }
            .disabled(isSaving)
        }
    }

    // MARK: - Logic

    /// Whether the user made any changes to title/author/format
    private var hasChanges: Bool {
        let titleChanged = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines) != work.title
        let authorChanged = editedAuthor.trimmingCharacters(in: .whitespacesAndNewlines) != work.authorNames
        let formatChanged = selectedFormat != (work.primaryEdition?.format ?? .hardcover)

        return titleChanged || authorChanged || formatChanged
    }

    /// Load and crop the spine image from the original bookshelf photo
    private func loadCroppedImage() {
        guard let imagePath = work.originalImagePath,
              let boundingBox = work.boundingBox else {
            #if DEBUG
            print("⚠️ CorrectionView: Missing originalImagePath or boundingBox")
            #endif
            return
        }

        Task {
            croppedImage = await cropSpineImage(imagePath: imagePath, boundingBox: boundingBox)
        }
    }

    /// Crop spine region from original bookshelf image
    private func cropSpineImage(imagePath: String, boundingBox: CGRect) async -> UIImage? {
        // Load image from temporary storage
        guard let originalImage = UIImage(contentsOfFile: imagePath) else {
            #if DEBUG
            print("⚠️ CorrectionView: Failed to load image from \(imagePath)")
            #endif
            return nil
        }

        guard let cgImage = originalImage.cgImage else {
            #if DEBUG
            print("⚠️ CorrectionView: Failed to get CGImage")
            #endif
            return nil
        }

        // Convert normalized coordinates (0.0-1.0) to pixel coordinates
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        let cropRect = CGRect(
            x: boundingBox.origin.x * imageWidth,
            y: boundingBox.origin.y * imageHeight,
            width: boundingBox.width * imageWidth,
            height: boundingBox.height * imageHeight
        )

        // Crop the image
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            #if DEBUG
            print("⚠️ CorrectionView: Failed to crop image")
            #endif
            return nil
        }

        return UIImage(cgImage: croppedCGImage)
    }

    /// Save corrections or mark as verified
    private func saveCorrections() async {
        isSaving = true
        focusedField = nil

        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthor = editedAuthor.trimmingCharacters(in: .whitespacesAndNewlines)

        // Track changes for analytics
        let hadTitleChange = trimmedTitle != work.title
        let hadAuthorChange = trimmedAuthor != work.authorNames
        let hadFormatChange = selectedFormat != (work.primaryEdition?.format ?? .hardcover)

        // Update work if changes were made
        if hasChanges {
            work.title = trimmedTitle

            // Update author
            if !trimmedAuthor.isEmpty {
                // Clear existing authors
                work.authors?.removeAll()

                // Add new author
                let author = Author(name: trimmedAuthor)
                modelContext.insert(author)
                work.authors = [author]
            }

            // Update or create edition with selected format
            if let primaryEdition = work.primaryEdition {
                // Update existing edition's format
                primaryEdition.format = selectedFormat
            } else {
                // Create new edition with selected format
                let edition = Edition(
                    isbn: nil,
                    publisher: nil,
                    publicationDate: nil,
                    pageCount: nil,
                    format: selectedFormat
                )
                modelContext.insert(edition)
                work.editions = [edition]
            }

            // Mark as user-edited
            work.reviewStatus = .userEdited

            // Analytics: Track correction saved
            logAnalyticsEvent("review_queue_correction_saved", properties: [
                "had_title_change": hadTitleChange,
                "had_author_change": hadAuthorChange,
                "had_format_change": hadFormatChange
            ])
        } else {
            // No changes - mark as verified
            work.reviewStatus = .verified

            // Analytics: Track verified without changes
            logAnalyticsEvent("review_queue_verified_without_changes")
        }

        // Save context
        do {
            try modelContext.save()

            // Remove from review queue
            reviewModel.removeFromQueue(work)

            // Dismiss view
            dismiss()

        } catch {
            #if DEBUG
            print("❌ CorrectionView: Failed to save - \(error)")
            #endif
        }

        isSaving = false
    }

    // MARK: - Analytics

    /// Log analytics event (placeholder for real analytics SDK)
    private func logAnalyticsEvent(_ eventName: String, properties: [String: Any] = [:]) {
        #if DEBUG
        print("📊 Analytics: \(eventName) - \(properties)")
        #endif
        // TODO: Replace with real analytics SDK (Firebase, Mixpanel, etc.)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var container: ModelContainer = {
        let container = try! ModelContainer(for: Work.self, Author.self)
        let context = container.mainContext

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

    let context = container.mainContext
    let work = try! context.fetch(FetchDescriptor<Work>()).first!
    let model = ReviewQueueModel()
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    NavigationStack {
        CorrectionView(work: work, reviewModel: model)
            .modelContainer(container)
            .environment(themeStore)
    }
}

#endif  // canImport(UIKit)
