import SwiftUI

/// Bento Box Module: DNABlock
/// Displays essential bibliographic metadata (DNA) for a book.
/// Reordered for reader relevance: page count → original year → format → language → (technical details)
@available(iOS 26.0, *)
struct DNABlock: View {
    let work: Work
    @State private var showTechnicalDetails = false

    var body: some View {
        GlassCard(title: "About", icon: "book.closed") {
            VStack(alignment: .leading, spacing: 8) {
                // Primary: Reader-relevant info
                if let pageCount = work.primaryEdition?.pageCount {
                    MetadataRow(icon: "book.pages", label: "Pages", value: "\(pageCount)")
                }

                if let original = work.firstPublicationYear {
                    let languageNote = work.originalLanguage.map { " (\($0))" } ?? ""
                    MetadataRow(icon: "calendar", label: "First published", value: "\(original)\(languageNote)")
                }

                if let format = work.primaryEdition?.format {
                    MetadataRow(icon: format.icon, label: "Format", value: format.displayName)
                }

                // Secondary: Expandable technical details
                DisclosureGroup(isExpanded: $showTechnicalDetails) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let year = work.primaryEdition?.publicationYear {
                            MetadataRow(icon: "doc.text", label: "This edition", value: year, style: .tertiary)
                        }
                        if let publisher = work.primaryEdition?.publisher {
                            MetadataRow(icon: "building.2", label: "Publisher", value: publisher, style: .tertiary)
                        }
                        if let isbn = work.primaryEdition?.primaryISBN {
                            MetadataRow(icon: "barcode", label: "ISBN", value: isbn, style: .tertiary)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("Edition details")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tint(.secondary)
            }
        }
    }
}

// MARK: - Supporting Views

struct MetadataRow: View {
    let icon: String?
    let label: String
    let value: String
    var style: MetadataRowStyle

    enum MetadataRowStyle {
        case primary, tertiary
    }

    init(icon: String? = nil, label: String, value: String, style: MetadataRowStyle = .primary) {
        self.icon = icon
        self.label = label
        self.value = value
        self.style = style
    }

    // Legacy initializer for backwards compatibility
    init(label: String, value: String, font: Font = .subheadline) {
        self.icon = nil
        self.label = label
        self.value = value
        self.style = font == .caption ? .tertiary : .primary
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(style == .primary ? .subheadline : .caption)
                    .foregroundStyle(style == .primary ? .secondary : .tertiary)
                    .frame(width: 20)
            }
            Text(label)
                .font(style == .primary ? .subheadline : .caption)
                .foregroundStyle(style == .primary ? .secondary : .tertiary)
            Spacer()
            Text(value)
                .font(style == .primary ? .subheadline.weight(.medium) : .caption)
                .foregroundStyle(style == .primary ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
