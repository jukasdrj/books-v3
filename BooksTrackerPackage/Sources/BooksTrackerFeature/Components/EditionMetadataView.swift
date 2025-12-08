import SwiftUI

/// Displays edition-specific metadata (publisher, ISBN, page count, etc.)
@available(iOS 26.0, *)
struct EditionMetadataView: View {
    let work: Work
    let edition: Edition?

    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var showTechnicalDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let edition = edition {
                // MARK: - Essential Metadata (Always Visible)

                // Publisher Information
                if let publisher = edition.publisher {
                    metadataRow(
                        icon: "building.2",
                        label: "Publisher",
                        value: publisher
                    )
                }

                // Publication Date
                if let publicationDate = edition.publicationDate {
                    metadataRow(
                        icon: "calendar",
                        label: "Published",
                        value: publicationDate
                    )
                }

                // Page Count
                if let pageCount = edition.pageCount, pageCount > 0 {
                    metadataRow(
                        icon: "doc.text",
                        label: "Pages",
                        value: "\(pageCount)"
                    )
                }

                // MARK: - Technical Details (Expandable)

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showTechnicalDetails.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("Technical Details")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        Spacer()

                        Image(systemName: showTechnicalDetails ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showTechnicalDetails ? "Hide technical details" : "Show technical details")
                .accessibilityHint("Double tap to \(showTechnicalDetails ? "collapse" : "expand")")

                if showTechnicalDetails {
                    VStack(alignment: .leading, spacing: 12) {
                        // ISBN
                        if let isbn = edition.primaryISBN {
                            metadataRow(
                                icon: "barcode",
                                label: "ISBN",
                                value: isbn,
                                fontSize: .caption
                            )
                        }

                        // Format
                        metadataRow(
                            icon: "book",
                            label: "Format",
                            value: edition.format.displayName,
                            fontSize: .caption
                        )

                        // Original Language
                        if let language = edition.originalLanguage {
                            metadataRow(
                                icon: "globe",
                                label: "Language",
                                value: language,
                                fontSize: .caption
                            )
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                // No edition available
                Text("No edition information available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            }
        }
        .padding()
    }

    private func metadataRow(icon: String, label: String, value: String, fontSize: Font = .subheadline) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(fontSize == .caption ? .caption : .body)
                .foregroundStyle(themeStore.primaryColor)
                .frame(width: 24)

            Text(label)
                .font(fontSize)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(fontSize)
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}
