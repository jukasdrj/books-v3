import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Advanced Search Criteria Model

/// Encapsulates advanced search criteria with optional fields
@Observable
public class AdvancedSearchCriteria {
    var authorName: String = ""
    var bookTitle: String = ""
    var isbn: String = ""
    var yearStart: String = ""
    var yearEnd: String = ""

    /// Check if any criteria is filled
    var hasAnyCriteria: Bool {
        !authorName.isEmpty || !bookTitle.isEmpty || !isbn.isEmpty ||
        !yearStart.isEmpty || !yearEnd.isEmpty
    }

    /// Clear all criteria
    func clear() {
        authorName = ""
        bookTitle = ""
        isbn = ""
        yearStart = ""
        yearEnd = ""
    }

    /// Build search query from filled criteria
    func buildSearchQuery() -> String? {
        guard hasAnyCriteria else { return nil }

        // Priority order: ISBN > Author+Title > Author > Title
        if !isbn.isEmpty {
            return isbn
        }

        if !authorName.isEmpty && !bookTitle.isEmpty {
            return "\(authorName) \(bookTitle)"
        }

        if !authorName.isEmpty {
            return authorName
        }

        if !bookTitle.isEmpty {
            return bookTitle
        }

        return nil
    }

    /// Determine search scope based on filled criteria
    func determineSearchScope() -> SearchScope {
        // ISBN has highest priority
        if !isbn.isEmpty {
            return .isbn
        }

        // If both author and title filled, use general search
        if !authorName.isEmpty && !bookTitle.isEmpty {
            return .all
        }

        // Single field searches use specific scopes
        if !authorName.isEmpty {
            return .author
        }

        if !bookTitle.isEmpty {
            return .title
        }

        return .all
    }
}

// MARK: - Advanced Search View

/// iOS 26 Liquid Glass styled advanced search form
/// Provides multi-field search with author, title, ISBN, and year range
public struct AdvancedSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore

    @State private var criteria = AdvancedSearchCriteria()
    @FocusState private var focusedField: SearchField?

    /// Callback when search is triggered
    let onSearch: (AdvancedSearchCriteria) -> Void

    public init(onSearch: @escaping (AdvancedSearchCriteria) -> Void) {
        self.onSearch = onSearch
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header description
                    headerSection

                    // Search fields
                    VStack(spacing: 20) {
                        authorField
                        titleField
                        isbnField
                        yearRangeFields
                    }
                    .padding(.horizontal)

                    // Action buttons
                    actionButtons
                }
                .padding(.vertical, 24)
            }
            .background(themeStore.backgroundGradient)
            .navigationTitle("Advanced Search")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(themeStore.primaryColor)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        clearAllFields()
                    }
                    .foregroundStyle(.secondary)
                    .disabled(!criteria.hasAnyCriteria)
                }

                // Keyboard dismissal toolbar for number pad fields
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil  // Dismiss keyboard
                    }
                    .foregroundStyle(themeStore.primaryColor)
                    .font(.headline)
                }
            }
        }
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(themeStore.primaryColor.gradient)
                .symbolRenderingMode(.hierarchical)

            Text("Search with Precision")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Text("Fill any combination of fields to find exactly what you're looking for")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.bottom, 8)
    }

    private var authorField: some View {
        GlassSearchField(
            title: "Author",
            icon: "person.fill",
            placeholder: "e.g., Agatha Christie",
            text: $criteria.authorName,
            focused: $focusedField,
            field: .author
        )
        .accessibilityLabel("Author name field")
        .accessibilityHint("Enter the author's name to search for their books")
    }

    private var titleField: some View {
        GlassSearchField(
            title: "Title",
            icon: "book.fill",
            placeholder: "e.g., Murder on the Orient Express",
            text: $criteria.bookTitle,
            focused: $focusedField,
            field: .title
        )
        .accessibilityLabel("Book title field")
        .accessibilityHint("Enter the book title you're searching for")
    }

    private var isbnField: some View {
        GlassSearchField(
            title: "ISBN",
            icon: "barcode",
            placeholder: "e.g., 9780062073488",
            text: $criteria.isbn,
            focused: $focusedField,
            field: .isbn,
            keyboardType: .numberPad
        )
        .accessibilityLabel("ISBN field")
        .accessibilityHint("Enter the ISBN number for exact book identification")
    }

    private var yearRangeFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(themeStore.primaryColor)
                    .font(.system(size: 16, weight: .medium))

                Text("Publication Year")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("From")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("1900", text: $criteria.yearStart)
                        #if canImport(UIKit)
                        .keyboardType(.numberPad)
                        #endif
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(themeStore.primaryColor.opacity(0.3), lineWidth: 1)
                                }
                        }
                        .focused($focusedField, equals: .yearStart)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("To")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("2025", text: $criteria.yearEnd)
                        #if canImport(UIKit)
                        .keyboardType(.numberPad)
                        #endif
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(themeStore.primaryColor.opacity(0.3), lineWidth: 1)
                                }
                        }
                        .focused($focusedField, equals: .yearEnd)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: themeStore.primaryColor.opacity(0.1), radius: 8, y: 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Publication year range")
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Primary search button
            Button {
                performSearch()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))

                    Text("Search")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(themeStore.primaryColor.gradient)
                        .shadow(color: themeStore.primaryColor.opacity(0.3), radius: 12, y: 6)
                }
                .foregroundStyle(.white)
            }
            .disabled(!criteria.hasAnyCriteria)
            .opacity(criteria.hasAnyCriteria ? 1.0 : 0.5)
            .accessibilityLabel("Search button")
            .accessibilityHint("Tap to search with the entered criteria")

            // Criteria summary
            if criteria.hasAnyCriteria {
                criteriaSummary
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var criteriaSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search Criteria:")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if !criteria.authorName.isEmpty {
                    criteriaTag(icon: "person.fill", text: criteria.authorName)
                }
                if !criteria.bookTitle.isEmpty {
                    criteriaTag(icon: "book.fill", text: criteria.bookTitle)
                }
                if !criteria.isbn.isEmpty {
                    criteriaTag(icon: "barcode", text: criteria.isbn)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }

    private func criteriaTag(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(text)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(themeStore.primaryColor.opacity(0.15))
        }
        .foregroundStyle(themeStore.primaryColor)
    }

    // MARK: - Actions

    private func performSearch() {
        // Dismiss keyboard
        focusedField = nil

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Trigger search callback
        onSearch(criteria)

        // Dismiss sheet
        dismiss()
    }

    private func clearAllFields() {
        withAnimation(.spring(duration: 0.3)) {
            criteria.clear()
            focusedField = nil
        }

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - Glass Search Field Component

/// Reusable glass-effect text field for advanced search
private struct GlassSearchField: View {
    @Environment(\.iOS26ThemeStore) private var themeStore

    let title: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<SearchField?>.Binding
    let field: SearchField
    #if canImport(UIKit)
    var keyboardType: UIKeyboardType = .default
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(themeStore.primaryColor)
                    .font(.system(size: 16, weight: .medium))

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                if !text.isEmpty {
                    Button {
                        withAnimation(.spring(duration: 0.2)) {
                            text = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 16))
                    }
                    .accessibilityLabel("Clear \(title)")
                }
            }
            .padding(.horizontal, 4)

            TextField(placeholder, text: $text)
                #if canImport(UIKit)
                .keyboardType(keyboardType)
                #endif
                .textFieldStyle(.plain)
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    focused.wrappedValue == field ?
                                        themeStore.primaryColor :
                                        themeStore.primaryColor.opacity(0.2),
                                    lineWidth: focused.wrappedValue == field ? 2 : 1
                                )
                        }
                        .shadow(
                            color: focused.wrappedValue == field ?
                                themeStore.primaryColor.opacity(0.2) : .clear,
                            radius: 8,
                            y: 4
                        )
                }
                .focused(focused, equals: field)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: themeStore.primaryColor.opacity(0.05), radius: 6, y: 3)
        }
        .animation(.spring(duration: 0.3), value: focused.wrappedValue == field)
    }
}

// MARK: - Search Field Enum

/// Focus tracking for search fields
private enum SearchField: Hashable {
    case author
    case title
    case isbn
    case yearStart
    case yearEnd
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    AdvancedSearchView { criteria in
        print("Search triggered with:", criteria.buildSearchQuery() ?? "empty")
    }
    .environment(BooksTrackerFeature.iOS26ThemeStore())
}
