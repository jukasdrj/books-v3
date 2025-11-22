import SwiftUI
import SwiftData

/// A SwiftUI sheet allowing users to override specific author metadata for a given work.
/// This override prevents cascade updates for the selected fields for THIS work only.
@available(iOS 26.0, *)
@MainActor
public struct OverrideSheet: View {
    let work: Work
    let authorMetadata: AuthorMetadata
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore

    // MARK: - State Variables for Form Fields
    @State private var culturalBackground: [String] = []
    @State private var newCulturalBackgroundItem: String = ""

    @State private var genderIdentity: String = ""

    @State private var nationality: [String] = []
    @State private var newNationalityItem: String = ""

    @State private var languages: [String] = []
    @State private var newLanguageItem: String = ""

    @State private var marginalizedIdentities: [String] = []
    @State private var newMarginalizedIdentityItem: String = ""

    @State private var showingErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    public init(work: Work, authorMetadata: AuthorMetadata, onSave: @escaping () -> Void) {
        self.work = work
        self.authorMetadata = authorMetadata
        self.onSave = onSave
    }

    /// Computed property to determine if any changes have been made to enable the Save button.
    private var hasChanges: Bool {
        culturalBackground.sorted() != authorMetadata.culturalBackground.sorted() ||
        genderIdentity != (authorMetadata.genderIdentity ?? "") ||
        nationality.sorted() != authorMetadata.nationality.sorted() ||
        languages.sorted() != authorMetadata.languages.sorted() ||
        marginalizedIdentities.sorted() != authorMetadata.marginalizedIdentities.sorted()
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WarningCard()
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                Form {
                    // MARK: - Cultural Background Section
                    MetadataFieldRow(label: "Cultural Background") {
                        MultiSelectInput(
                            items: $culturalBackground,
                            newItemText: $newCulturalBackgroundItem,
                            placeholder: "Add culture...",
                            themeStore: themeStore
                        )
                    }

                    // MARK: - Gender Identity Section
                    MetadataFieldRow(label: "Gender Identity") {
                        TextField("Enter gender identity", text: $genderIdentity)
                            .textFieldStyle(RoundedBorderTextFieldStyle(themeStore: themeStore))
                            .accessibilityLabel("Gender Identity input field")
                    }

                    // MARK: - Nationality Section
                    MetadataFieldRow(label: "Nationality") {
                        MultiSelectInput(
                            items: $nationality,
                            newItemText: $newNationalityItem,
                            placeholder: "Add nationality...",
                            themeStore: themeStore
                        )
                    }

                    // MARK: - Languages Section
                    MetadataFieldRow(label: "Languages") {
                        MultiSelectInput(
                            items: $languages,
                            newItemText: $newLanguageItem,
                            placeholder: "Add language...",
                            themeStore: themeStore
                        )
                    }

                    // MARK: - Marginalized Identities Section
                    MetadataFieldRow(label: "Marginalized Identities") {
                        MultiSelectInput(
                            items: $marginalizedIdentities,
                            newItemText: $newMarginalizedIdentityItem,
                            placeholder: "Add identity...",
                            themeStore: themeStore
                        )
                    }
                }
                .background(Color.clear)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Override Metadata")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel override")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveOverride() }
                    }
                    .disabled(!hasChanges)
                    .accessibilityLabel("Save override changes")
                }
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
        .task {
            loadDefaults()
        }
    }

    /// Loads the initial metadata values from `authorMetadata` into the form's state.
    private func loadDefaults() {
        culturalBackground = authorMetadata.culturalBackground
        genderIdentity = authorMetadata.genderIdentity ?? ""
        nationality = authorMetadata.nationality
        languages = authorMetadata.languages
        marginalizedIdentities = authorMetadata.marginalizedIdentities
    }

    /// Attempts to save the overridden metadata by creating a `WorkOverride` entity.
    private func saveOverride() async {
        let cascadeService = CascadeMetadataService(modelContext: modelContext)
        let workId = work.persistentModelID.hashValue.description

        do {
            // CascadeMetadataService.createOverride() is field-by-field
            // For now, save culturalBackground and genderIdentity (the two supported fields)

            if culturalBackground.sorted() != authorMetadata.culturalBackground.sorted() {
                try cascadeService.createOverride(
                    authorId: authorMetadata.authorId,
                    workId: workId,
                    field: "culturalBackground",
                    customValue: culturalBackground.joined(separator: ", "),
                    reason: "User override from OverrideSheet"
                )
            }

            if genderIdentity != (authorMetadata.genderIdentity ?? "") {
                try cascadeService.createOverride(
                    authorId: authorMetadata.authorId,
                    workId: workId,
                    field: "genderIdentity",
                    customValue: genderIdentity,
                    reason: "User override from OverrideSheet"
                )
            }

            // TODO: Add support for nationality, languages, marginalizedIdentities
            // once CascadeMetadataService.createOverride supports them

            onSave()
            dismiss()
        } catch {
            errorMessage = "Failed to save override: \(error.localizedDescription)"
            showingErrorAlert = true
            #if DEBUG
            print("❌ Error saving override: \(error)")
            #endif
        }
    }

    // MARK: - Nested Supporting Views

    /// A card displaying a warning message about the scope of the override.
    private struct WarningCard: View {
        @Environment(\.iOS26ThemeStore) private var themeStore

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)

                Text("This override applies only to THIS work and will prevent cascade updates for these fields from the author's general metadata.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.orange.opacity(0.5), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Warning: Metadata override applies only to this work.")
        }
    }

    /// A reusable row for a metadata field, including a label and content.
    private struct MetadataFieldRow<Content: View>: View {
        let label: String
        @ViewBuilder let content: Content

        var body: some View {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(label)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)

                    content
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .padding(.vertical, 4)
            )
            .listRowSeparator(.hidden)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
        }
    }

    /// A view for managing a list of multi-selectable items with an add new item functionality.
    private struct MultiSelectInput: View {
        @Binding var items: [String]
        @Binding var newItemText: String
        let placeholder: String
        let themeStore: iOS26ThemeStore

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if !items.isEmpty {
                    FlowLayout(alignment: .leading, spacing: 8) {
                        ForEach(items, id: \.self) { item in
                            MultiSelectChip(text: item, isSelected: .constant(true), themeStore: themeStore) {
                                items.removeAll { $0 == item }
                            }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("Remove \(item) from list")
                        }
                    }
                }

                HStack {
                    TextField(placeholder, text: $newItemText)
                        .textFieldStyle(RoundedBorderTextFieldStyle(themeStore: themeStore))
                        .accessibilityLabel("Add new item text field")

                    Button("Add") {
                        addItem()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themeStore.primaryColor)
                    .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add new item")
                }
                .padding(.vertical, 4)
            }
        }

        private func addItem() {
            let trimmedItem = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedItem.isEmpty && !items.contains(trimmedItem) {
                items.append(trimmedItem)
                newItemText = ""
            }
        }
    }

    /// A visual chip for displaying and interacting with a single item in a multi-select list.
    private struct MultiSelectChip: View {
        let text: String
        @Binding var isSelected: Bool
        let themeStore: iOS26ThemeStore
        var action: (() -> Void)? = nil

        var body: some View {
            Text(text)
                .font(.caption)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(isSelected ? themeStore.primaryColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(20)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? .clear : Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onTapGesture {
                    action?()
                }
                .accessibilityAddTraits(action != nil ? .isButton : [])
                .accessibilityLabel(text)
                .accessibilityHint(action != nil ? "Tap to remove" : "")
        }
    }

    /// A custom `TextFieldStyle` for rounded borders.
    private struct RoundedBorderTextFieldStyle: TextFieldStyle {
        let themeStore: iOS26ThemeStore

        func _body(configuration: TextField<Self._Label>) -> some View {
            configuration
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.clear)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .background(.ultraThinMaterial)
                .cornerRadius(8)
        }
    }

    /// A simple FlowLayout for chips.
    private struct FlowLayout: Layout {
        var alignment: HorizontalAlignment = .leading
        var spacing: CGFloat = 8

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let containerWidth = proposal.width ?? 0
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)

                if currentX + subviewSize.width > containerWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                currentX += subviewSize.width + spacing
                lineHeight = max(lineHeight, subviewSize.height)
            }

            let totalHeight = currentY + lineHeight
            return CGSize(width: containerWidth, height: totalHeight)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let containerWidth = bounds.width
            var currentX: CGFloat = bounds.minX
            var currentY: CGFloat = bounds.minY
            var lineHeight: CGFloat = 0
            var lineViews: [(subview: LayoutSubviews.Element, size: CGSize)] = []

            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)

                if currentX + subviewSize.width > containerWidth && !lineViews.isEmpty {
                    placeLine(lineViews: lineViews, currentY: currentY, lineHeight: lineHeight, bounds: bounds, containerWidth: containerWidth)

                    currentX = bounds.minX
                    currentY += lineHeight + spacing
                    lineHeight = 0
                    lineViews.removeAll()
                }

                lineViews.append((subview, subviewSize))
                currentX += subviewSize.width + spacing
                lineHeight = max(lineHeight, subviewSize.height)
            }

            if !lineViews.isEmpty {
                placeLine(lineViews: lineViews, currentY: currentY, lineHeight: lineHeight, bounds: bounds, containerWidth: containerWidth)
            }
        }

        private func placeLine(lineViews: [(subview: LayoutSubviews.Element, size: CGSize)], currentY: CGFloat, lineHeight: CGFloat, bounds: CGRect, containerWidth: CGFloat) {
            var lineX: CGFloat = bounds.minX

            if alignment == .center {
                let totalWidth = lineViews.reduce(0) { $0 + $1.size.width + spacing } - spacing
                lineX += (containerWidth - totalWidth) / 2
            } else if alignment == .trailing {
                let totalWidth = lineViews.reduce(0) { $0 + $1.size.width + spacing } - spacing
                lineX += (containerWidth - totalWidth)
            }

            for (subview, subviewSize) in lineViews {
                subview.place(at: CGPoint(x: lineX, y: currentY + (lineHeight - subviewSize.height) / 2), proposal: ProposedViewSize(subviewSize))
                lineX += subviewSize.width + spacing
            }
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Override Sheet") {
    @Previewable @State var container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Work.self, Author.self, AuthorMetadata.self, WorkOverride.self,
            configurations: config
        )
        let context = container.mainContext

        let author = Author(name: "Haruki Murakami")
        let work = Work(title: "1Q84")
        context.insert(author)
        context.insert(work)
        work.authors = [author]

        let metadata = AuthorMetadata(
            authorId: author.persistentModelID.hashValue.description,
            contributedBy: "default-user"
        )
        metadata.culturalBackground = ["Japanese", "American"]
        metadata.genderIdentity = "Male"
        metadata.nationality = ["Japanese"]
        metadata.languages = ["English", "Japanese"]
        metadata.marginalizedIdentities = []
        context.insert(metadata)

        return container
    }()

    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    // Need to fetch the metadata from container
    let context = container.mainContext
    let descriptor = FetchDescriptor<AuthorMetadata>()
    let metadata = try! context.fetch(descriptor).first!
    let workDescriptor = FetchDescriptor<Work>()
    let work = try! context.fetch(workDescriptor).first!

    OverrideSheet(work: work, authorMetadata: metadata) {
        print("✅ Override saved in preview")
    }
    .modelContainer(container)
    .environment(\.iOS26ThemeStore, themeStore)
}
