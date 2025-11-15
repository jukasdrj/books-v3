import SwiftUI

@MainActor
@available(iOS 26.0, *)
struct AlphabeticalIndexView: View {
    let works: [Work]
    let scrollProxy: ScrollViewProxy

    private var indexLetters: [String] {
        let firstLetters = works.compactMap { $0.title.first?.uppercased() }
        let uniqueLetters = Array(Set(firstLetters)).sorted()
        return uniqueLetters
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(indexLetters, id: \.self) { letter in
                Button(action: {
                    if let work = works.first(where: { $0.title.uppercased().starts(with: letter) }) {
                        withAnimation {
                            scrollProxy.scrollTo(work.id, anchor: .top)
                        }
                    }
                }) {
                    Text(letter)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, minHeight: 16)
                }
                .accessibilityLabel("Jump to section \(letter)")
            }
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}