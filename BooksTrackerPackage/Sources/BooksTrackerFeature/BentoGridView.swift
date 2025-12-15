import SwiftUI

/// Bento Box Grid Layout
/// Stacked layout for better legibility on mobile - each block gets full width
struct BentoDashboardLayout<C1: View, C2: View, C3: View, C4: View>: View {
    @ViewBuilder let dnaBlock: () -> C1
    @ViewBuilder let diversityBlock: () -> C2
    @ViewBuilder let interactionBlock: () -> C3
    @ViewBuilder let readingProgressBlock: () -> C4

    var body: some View {
        VStack(spacing: 16) {
            // Row 1: DNA + Diversity side by side on larger screens, stacked on smaller
            ViewThatFits(in: .horizontal) {
                // Wide layout: side by side
                HStack(alignment: .top, spacing: 12) {
                    dnaBlock()
                        .frame(maxWidth: .infinity)
                    diversityBlock()
                        .frame(maxWidth: .infinity)
                }

                // Narrow layout: stacked
                VStack(spacing: 12) {
                    diversityBlock()
                        .frame(maxWidth: .infinity)
                    dnaBlock()
                        .frame(maxWidth: .infinity)
                }
            }

            // Row 2: Interaction/Stats (Full Width)
            interactionBlock()
                .frame(maxWidth: .infinity)

            // Row 3: Reading Progress (Full Width)
            readingProgressBlock()
                .frame(maxWidth: .infinity)
        }
    }
}
