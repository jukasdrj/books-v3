import SwiftUI

/// Quick Fact Pill - Horizontal Scrollable Metadata Display
/// Displays concise book metadata in pill format (pages, genre, year, rating, etc.)
struct QuickFactPill: View {
    let icon: String // SF Symbol name
    let text: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(icon) \(text)")
    }
}

#Preview {
    VStack(spacing: 12) {
        QuickFactPill(icon: "book.pages", text: "384 pages")
        QuickFactPill(icon: "tag", text: "Science Fiction")
        QuickFactPill(icon: "calendar", text: "2021")
        QuickFactPill(icon: "star.fill", text: "4.5", color: .orange)
        QuickFactPill(icon: "checkmark.circle.fill", text: "Owned", color: .green)
    }
    .padding()
}
