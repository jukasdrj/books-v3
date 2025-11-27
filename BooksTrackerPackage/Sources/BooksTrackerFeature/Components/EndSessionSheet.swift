import SwiftUI

struct EndSessionSheet: View {
    let workTitle: String
    let currentPage: Int
    let pageCount: Int
    @Binding var endingPage: Int
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isPageFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)

                    Text("End Reading Session")
                        .font(.title2.bold())

                    Text("Update your progress for \(workTitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)

                // Page Input
                VStack(alignment: .leading, spacing: 12) {
                    Text("What page did you reach?")
                        .font(.headline)

                    HStack(spacing: 12) {
                        TextField("Page", value: $endingPage, format: .number)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .focused($isPageFieldFocused)
                            .frame(maxWidth: 120)

                        if pageCount > 0 {
                            Text("of \(pageCount)")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))

                Spacer()

                // Save Button
                Button(action: {
                    onSave()
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Progress")
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.cornerRadius(12))
                }
                .buttonStyle(.plain)
            }
            .padding()
            .navigationTitle("End Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                isPageFieldFocused = true
            }
        }
    }
}
