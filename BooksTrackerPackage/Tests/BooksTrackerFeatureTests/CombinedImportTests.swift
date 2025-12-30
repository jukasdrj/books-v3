import Testing
@testable import BooksTrackerFeature

@Suite("Combined Import Tests")
@MainActor
struct CombinedImportTests {
    @Test("Main tab contains shelf case")
    func mainTabContainsShelf() {
        #expect(MainTab.allCases.contains(.shelf), "MainTab should include a 'shelf' case for the Scan & Import tab")
    }

    @Test("Combined import view can be instantiated")
    func combinedImportViewCanBeInstantiated() {
        // Ensure the view type can be created without runtime issues.
        // We avoid accessing .body or environment-dependent properties here to keep the test lightweight.
        let _ = CombinedImportView()
        #expect(true)
    }
}
