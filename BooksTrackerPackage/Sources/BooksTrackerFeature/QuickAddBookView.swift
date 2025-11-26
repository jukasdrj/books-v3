import SwiftUI
import SwiftData

/// View for directly adding a book to library after V2 enrichment
/// Shown after ISBN barcode scan with enriched book data
@MainActor
@available(iOS 26.0, *)
public struct QuickAddBookView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let enrichmentResponse: V2EnrichmentResponse
    @State private var readingStatus: ReadingStatus = .toRead
    @State private var isAdding = false
    @State private var showingSuccess = false
    
    public init(enrichmentResponse: V2EnrichmentResponse) {
        self.enrichmentResponse = enrichmentResponse
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Book cover
                    if let coverUrl = enrichmentResponse.coverUrl,
                       let url = URL(string: coverUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 200, maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(radius: 8)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 200, height: 300)
                                .overlay {
                                    ProgressView()
                                }
                        }
                    }
                    
                    // Book info
                    VStack(spacing: 12) {
                        Text(enrichmentResponse.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text(enrichmentResponse.authors.joined(separator: ", "))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        if let publisher = enrichmentResponse.publisher {
                            Text(publisher)
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        
                        if let publishedDate = enrichmentResponse.publishedDate {
                            Text(publishedDate)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Reading status picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add to Library")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        Picker("Reading Status", selection: $readingStatus) {
                            ForEach(ReadingStatus.allCases, id: \.self) { status in
                                Text(status.displayName)
                                    .tag(status)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }
                    
                    // Add button
                    Button(action: addToLibrary) {
                        HStack {
                            if isAdding {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                Text("Add to Library")
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(themeStore.primaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isAdding)
                    .padding(.horizontal)
                }
                .padding(.vertical, 24)
            }
            .background {
                themeStore.backgroundGradient
                    .ignoresSafeArea()
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Added to Library!", isPresented: $showingSuccess) {
                Button("View Library") {
                    dismiss()
                    // Post notification to switch to library tab
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCoordinator.postSwitchToLibraryTab()
                    }
                }
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("\(enrichmentResponse.title) has been added to your library.")
            }
        }
    }
    
    private func addToLibrary() {
        isAdding = true
        
        Task {
            // Create work
            let work = Work(title: enrichmentResponse.title, authors: [])
            modelContext.insert(work)
            
            // Set publication year
            if let publishedDate = enrichmentResponse.publishedDate {
                work.firstPublicationYear = extractYear(from: publishedDate)
            }
            
            // Create author
            if !enrichmentResponse.authors.isEmpty {
                let authorName = enrichmentResponse.authors.first ?? "Unknown Author"
                let author = Author(name: authorName)
                modelContext.insert(author)
                work.authors = [author]
            }
            
            // Create edition
            let edition = Edition(
                isbn: enrichmentResponse.isbn,
                publisher: enrichmentResponse.publisher,
                publicationDate: enrichmentResponse.publishedDate,
                pageCount: enrichmentResponse.pageCount,
                format: .paperback,
                coverImageURL: enrichmentResponse.coverUrl
            )
            modelContext.insert(edition)
            edition.work = work
            
            // Create library entry
            let entry = UserLibraryEntry(
                work: work,
                edition: edition,
                readingStatus: readingStatus,
                dateAdded: Date()
            )
            modelContext.insert(entry)
            
            // Save
            try? modelContext.save()
            
            isAdding = false
            showingSuccess = true
        }
    }
    
    private func extractYear(from dateString: String) -> Int? {
        // Try full ISO date format first
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        
        if let date = isoFormatter.date(from: dateString) {
            let calendar = Calendar.current
            return calendar.component(.year, from: date)
        }
        
        // Try just year
        if let year = Int(dateString.prefix(4)) {
            return year
        }
        
        return nil
    }
}

// MARK: - ReadingStatus Extension

extension ReadingStatus {
    var displayName: String {
        switch self {
        case .toRead: return "To Read"
        case .reading: return "Reading"
        case .finished: return "Finished"
        case .wishlist: return "Wishlist"
        case .dnf: return "DNF"
        case .onHold: return "On Hold"
        @unknown default: return "Unknown"
        }
    }
}
