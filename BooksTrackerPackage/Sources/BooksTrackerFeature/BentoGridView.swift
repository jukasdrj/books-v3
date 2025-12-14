import SwiftUI

/// Bento Box Grid Layout (Rigid)
/// Fixed 2-column layout for strict alignment.
struct BentoDashboardLayout<C1: View, C2: View, C3: View, C4: View>: View {
    @ViewBuilder let dnaBlock: () -> C1
    @ViewBuilder let diversityBlock: () -> C2
    @ViewBuilder let interactionBlock: () -> C3
    @ViewBuilder let readingProgressBlock: () -> C4

    var body: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            // Row 1: DNA (Top Left) | Diversity (Top Right)
            GridRow(alignment: .top) {
                dnaBlock()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                
                diversityBlock()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            
            // Row 2: Interaction/Stats (Full Width)
            GridRow {
                interactionBlock()
                    .gridCellColumns(2)
            }
            
            // Row 3: Reading Progress (Full Width)
            GridRow {
                readingProgressBlock()
                    .gridCellColumns(2)
            }
        }
        .padding(.horizontal, 20)
    }
}
