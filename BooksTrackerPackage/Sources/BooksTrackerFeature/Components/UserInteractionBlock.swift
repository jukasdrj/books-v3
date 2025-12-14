import SwiftUI

/// Bento Box Module: User Interaction & Status
/// Allows quick actions: Rate, Change Status, Edit
struct UserInteractionBlock: View {
    @Bindable var work: Work
    @Environment(\.modelContext) private var modelContext
    @State private var showingEditSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.accentColor)
                Text("Actions")
                    .font(.headline)
                Spacer()
                
                // Edit Button
                Button(action: { showingEditSheet = true }) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // 1. Reading Status Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("STATUS")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.accentColor) // "Pull user in" with color
                    .tracking(1) // Uppercase tracking
                
                Menu {
                    ForEach(ReadingStatus.allCases) { status in
                         Button {
                             updateStatus(to: status)
                         } label: {
                             if let current = work.userEntry?.readingStatus, current == status {
                                 Label(status.displayName, systemImage: "checkmark")
                             } else {
                                 Text(status.displayName)
                             }
                         }
                    }
                } label: {
                    StatusCapsule(status: work.userEntry?.readingStatus ?? .toRead)
                        .shadow(color: (work.userEntry?.readingStatus ?? .toRead).color.opacity(0.3), radius: 4, x: 0, y: 2) // Add depth
                }
            }
            
            Divider().padding(.vertical, 4)
            
            // 2. Rating
            if let entry = work.userEntry {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR RATING")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.accentColor)
                        .tracking(1)
                    
                    InteractiveRatingView(rating: Binding(
                        get: { entry.personalRating ?? 0 },
                        set: { newValue in
                            entry.personalRating = newValue
                            try? modelContext.save()
                        }
                    ))
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                }
            } else {
                 Button {
                     // Add to Lib logic
                 } label: {
                     HStack {
                         Image(systemName: "plus.circle.fill")
                         Text("Add to Library to Rate")
                     }
                     .font(.subheadline.bold())
                     .foregroundColor(.white)
                     .padding()
                     .background(Color.accentColor)
                     .cornerRadius(8)
                     .shadow(radius: 2)
                 }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .sheet(isPresented: $showingEditSheet) {
             // Placeholder for Edit Sheet
             Text("Edit Details Coming Soon")
        }
    }

    private func updateStatus(to status: ReadingStatus) {
        if let entry = work.userEntry {
            entry.readingStatus = status
        } else {
            // Create new entry if none exists
            let entry = UserLibraryEntry(readingStatus: status)
            modelContext.insert(entry)
            entry.work = work
        }
        try? modelContext.save()
    }
}

// Sub-component for Status Display
struct StatusCapsule: View {
    let status: ReadingStatus
    
    var body: some View {
        HStack {
            Image(systemName: status.systemImage)
            Text(status.displayName)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(status.color.opacity(0.15))
        .foregroundColor(status.color)
        .cornerRadius(8)
    }
}

// Sub-component for Interactive Rating
struct InteractiveRatingView: View {
    @Binding var rating: Double
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= Int(rating) ? "star.fill" : "star")
                    .foregroundColor(.yellow)
                    .font(.title3)
                    .onTapGesture {
                        withAnimation {
                            rating = Double(index)
                        }
                    }
            }
        }
    }
}
