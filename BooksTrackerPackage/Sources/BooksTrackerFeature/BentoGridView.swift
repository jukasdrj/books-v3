import SwiftUI

struct BentoGridView<C1: View, C2: View, C3: View, C4: View>: View {
    let readingProgress: C1
    let readingHabits: C2
    let diversity: C3
    let annotations: C4

    init(
        @ViewBuilder readingProgress: () -> C1,
        @ViewBuilder readingHabits: () -> C2,
        @ViewBuilder diversity: () -> C3,
        @ViewBuilder annotations: () -> C4
    ) {
        self.readingProgress = readingProgress()
        self.readingHabits = readingHabits()
        self.diversity = diversity()
        self.annotations = annotations()
    }

    var body: some View {
        Grid(alignment: .top, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                readingProgress
                readingHabits
            }
            GridRow {
                diversity
                annotations
            }
        }
        .padding(.horizontal, 20)
    }
}
