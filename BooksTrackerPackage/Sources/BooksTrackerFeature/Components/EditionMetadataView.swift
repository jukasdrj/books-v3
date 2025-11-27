import SwiftUI

/// Displays edition-specific metadata (publisher, ISBN, page count, etc.)
@available(iOS 26.0, *)
struct EditionMetadataView: View {
    let work: Work
    let edition: Edition?

    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let edition = edition {
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

                // ISBN
                if let isbn = edition.primaryISBN {
                    metadataRow(
                        icon: "barcode",
                        label: "ISBN",
                        value: isbn
                    )
                }

                // Format
                metadataRow(
                    icon: "book",
                    label: "Format",
                    value: edition.format.displayName
                )

                // Original Language
                if let language = edition.originalLanguage {
                    metadataRow(
                        icon: "globe",
                        label: "Language",
                        value: language
                    )
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

    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(themeStore.primaryColor)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}
