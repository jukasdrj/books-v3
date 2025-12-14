import SwiftUI

/// Bento Box Module: DNABlock
/// Displays essential bibliographic metadata (DNA) for a book.
struct DNABlock: View {
    let work: Work
    @State private var showTechnicalDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "book.closed")
                    .foregroundColor(.blue)
                Text("DNA")
                    .font(.headline)
            }

            Divider()

            // Essential metadata
            // Essential metadata
            if let year = work.primaryEdition?.publicationYear {
                 MetadataRow(label: "Published", value: year)
            }
            
            if let original = work.firstPublicationYear {
                MetadataRow(label: "Original", value: "\(original) \(work.originalLanguage.map { "(\($0))" } ?? "")")
            }
            if let publisher = work.primaryEdition?.publisher {
                MetadataRow(label: "Publisher", value: publisher)
            }

            // Expandable technical details
            Button(action: { withAnimation { showTechnicalDetails.toggle() } }) {
                HStack {
                    Text("Technical Details")
                        .font(.caption)
                    Spacer()
                    Image(systemName: showTechnicalDetails ? "chevron.up" : "chevron.down")
                }
                .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            if showTechnicalDetails {
                VStack(alignment: .leading, spacing: 4) {
                    if let isbn = work.primaryEdition?.primaryISBN {
                         MetadataRow(label: "ISBN", value: isbn, font: .caption)
                    }
                    if let format = work.primaryEdition?.format.displayName {
                        MetadataRow(label: "Format", value: format, font: .caption)
                    }
                    if let lang = work.originalLanguage {
                        MetadataRow(label: "Language", value: lang, font: .caption)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground)) // slightly distinct background
        .cornerRadius(12)
    }
}

struct MetadataRow: View {
    let label: String
    let value: String
    var font: Font = .subheadline

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(font)
                .foregroundColor(.tertiaryLabel) // More muted
            Text(value)
                .font(font.weight(.regular)) // Regular weight instead of medium
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(.secondary) // Greyed out/Secondary
            Spacer()
        }
    }
}

// Extension for semantic colors if needed
extension Color {
    static let tertiaryLabel = Color(UIColor.tertiaryLabel)
}
