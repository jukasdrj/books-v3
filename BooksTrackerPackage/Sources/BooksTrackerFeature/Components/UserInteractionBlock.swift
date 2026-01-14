import SwiftUI

/// Bento Box Module: User Interaction & Status
/// Allows quick actions: Rate, Change Status, Edit
@available(iOS 26.0, *)
struct UserInteractionBlock: View {
    @Bindable var work: Work
    @Environment(\.modelContext) private var modelContext
    @State private var showingEditSheet = false

    var body: some View {
        GlassCard(title: "Actions", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 16) {
                // 1. Reading Status Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("STATUS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(1)

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
                    }
                }

                Divider()

                // 2. Rating
                if let entry = work.userEntry {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR RATING")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .tracking(1)

                        StarRatingView(
                            rating: Binding(
                                get: { entry.personalRating ?? 0 },
                                set: { newValue in
                                    entry.personalRating = newValue
                                    try? modelContext.save()
                                }
                            ),
                            size: .standard,
                            accessibilityLabel: "Your Rating"
                        )
                    }
                } else {
                    Button {
                        addToLibrary()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add to Library to Rate")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            Text("Edit Details Coming Soon")
        }
    }

    private func addToLibrary() {
        let entry = UserLibraryEntry(readingStatus: .toRead)
        modelContext.insert(entry)
        entry.work = work
        try? modelContext.save()
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

