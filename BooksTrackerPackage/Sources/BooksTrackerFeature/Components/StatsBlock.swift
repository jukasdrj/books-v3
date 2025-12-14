import SwiftUI

/// Bento Box Module: StatsBlock
/// Displays key statistics about the work using MetricView.
struct StatsBlock: View {
    let work: Work
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "chart.bar")
                    .foregroundColor(.orange)
                Text("Stats")
                    .font(.headline)
                Spacer()
            }
            
            Divider()
            
            // Metrics Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                
                // 1. Pages
                if let pages = work.primaryEdition?.pageCount {
                    MetricView(title: "Pages", value: "\(pages)", color: .primary)
                }
                
                // 2. Rating (Personal)
                if let rating = work.userEntry?.personalRating, rating > 0 {
                    MetricView(title: "My Rating", value: String(format: "%.1f", Double(rating)), color: .yellow)
                }
                
                // 3. Editions Count
                let editionCount = work.editions?.count ?? 0
                if editionCount > 0 {
                    MetricView(title: "Editions", value: "\(editionCount)", color: .blue)
                }
                
                // 4. Authors Count
                let authorCount = work.authors?.count ?? 0
                if authorCount > 1 {
                    MetricView(title: "Authors", value: "\(authorCount)", color: .purple)
                }
                
                // 5. Avg Rating (Placeholder if we had it)
                // MetricView(title: "Avg Rating", value: "4.5", color: .orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
