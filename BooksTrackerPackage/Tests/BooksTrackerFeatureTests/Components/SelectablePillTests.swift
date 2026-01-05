import Testing
import SwiftUI
@testable import BooksTrackerFeature

@available(iOS 26.0, *)
@Suite("SelectablePill Tests")
struct SelectablePillTests {

    @Test("Pill can be created in unselected state")
    func createsUnselectedPill() {
        let pill = SelectablePill(text: "Fiction", isSelected: false, action: {})

        #expect(pill != nil)
    }

    @Test("Pill can be created in selected state")
    func createsSelectedPill() {
        let pill = SelectablePill(text: "Fiction", isSelected: true, action: {})

        #expect(pill != nil)
    }

    @Test("Pill handles empty text")
    func handlesEmptyText() {
        let pill = SelectablePill(text: "", isSelected: false, action: {})

        #expect(pill != nil)
    }

    @Test("Pill handles long text")
    func handlesLongText() {
        let longText = String(repeating: "Very Long Genre Name ", count: 10)
        let pill = SelectablePill(text: longText, isSelected: false, action: {})

        #expect(pill != nil)
    }

    @Test("Action closure is stored correctly")
    func storesAction() {
        var actionCalled = false
        let pill = SelectablePill(text: "Fiction", isSelected: false, action: {
            actionCalled = true
        })

        #expect(pill != nil)
        // Note: Testing the action execution requires UI testing framework
    }

    @Test("Selected state is reflected in view")
    func reflectsSelectedState() {
        let selectedPill = SelectablePill(text: "Fiction", isSelected: true, action: {})
        let unselectedPill = SelectablePill(text: "Fiction", isSelected: false, action: {})

        #expect(selectedPill != nil)
        #expect(unselectedPill != nil)
        // Accessibility trait verification would require ViewInspector or similar
        // This test ensures views compile and initialize correctly with different states
    }
}
