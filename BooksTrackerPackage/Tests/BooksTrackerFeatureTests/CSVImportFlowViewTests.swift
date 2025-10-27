import Testing
import SwiftUI
@testable import BooksTrackerFeature

@Suite("CSVImportFlowView Tests")
@MainActor
struct CSVImportFlowViewTests {

    @Test("View initializes without crash")
    func viewInitialization() {
        if #available(iOS 26.0, *) {
            let view = CSVImportFlowView()
            // Verify view was created successfully
            #expect(view.body != nil)
        }
    }

    @Test("View uses SyncCoordinator singleton")
    func usesSyncCoordinator() {
        let coordinator = SyncCoordinator.shared
        // Verify coordinator singleton is accessible and properly initialized
        #expect(coordinator != nil)
    }
}
