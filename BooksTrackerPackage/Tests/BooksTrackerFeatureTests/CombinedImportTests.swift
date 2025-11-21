import XCTest
@testable import BooksTrackerFeature

@MainActor
final class CombinedImportTests: XCTestCase {
    func testMainTabContainsShelf() {
        XCTAssertTrue(MainTab.allCases.contains(.shelf), "MainTab should include a 'shelf' case for the Scan & Import tab")
    }

    func testCombinedImportViewCanBeInstantiated() {
        // Ensure the view type can be created without runtime issues.
        // We avoid accessing .body or environment-dependent properties here to keep the test lightweight.
        let _ = CombinedImportView()
        XCTAssertTrue(true)
    }
}
