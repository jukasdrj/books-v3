import SwiftUI

struct NotesEditorView: View {
    @Binding var notes: String
    let workTitle: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Notes for \(workTitle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top)

                TextEditor(text: $notes)
                    .focused($isTextEditorFocused)
                    .font(.body)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        if notes.isEmpty {
                            VStack {
                                HStack {
                                    Text("Add your thoughts...")
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 20)
                                        .padding(.top, 8)
                                    Spacer()
                                }
                                Spacer()
                            }
                        }
                    }

                Spacer()
            }
            .padding()
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                isTextEditorFocused = true
            }
        }
    }
}
