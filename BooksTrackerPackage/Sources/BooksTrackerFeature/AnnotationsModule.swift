import SwiftUI

struct AnnotationsModule: View {
    @Bindable var work: Work
    @Environment(\.modelContext) private var modelContext
    @State private var showingNotesEditor = false

    private var libraryEntry: UserLibraryEntry? {
        work.userLibraryEntries?.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader(title: "Annotations", icon: "pencil.and.ruler.fill")

            Spacer()

            // Star Rating
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Rating")
                    .font(.caption)
                    .foregroundColor(.secondary)

                StarRatingView(rating: Binding(
                    get: { libraryEntry?.personalRating ?? 0 },
                    set: { newRating in
                        guard let entry = libraryEntry else { return }
                        entry.personalRating = newRating
                        try? modelContext.save()
                    }
                ))
            }

            Spacer()

            // Notes Button
            Button(action: {
                showingNotesEditor.toggle()
            }) {
                HStack {
                    Image(systemName: "note.text")
                    Text("View Notes")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .sheet(isPresented: $showingNotesEditor) {
            NotesEditorView(
                notes: Binding(
                    get: { libraryEntry?.notes ?? "" },
                    set: { newNotes in
                        libraryEntry?.notes = newNotes.isEmpty ? nil : newNotes
                        try? modelContext.save()
                    }
                ),
                workTitle: work.title
            )
            .iOS26SheetGlass()
        }
    }
}
