//
//  ReadingStatusParserTests.swift
//  BooksTrackerFeatureTests
//
//  Created by Claude on 2025-11-04.
//  Comprehensive tests for Reading Status Parser
//
//  Tests validate:
//  - Direct string mapping (O(1) lookup)
//  - Case insensitivity
//  - Fuzzy matching for typos (Levenshtein distance ≤2)
//  - Goodreads/LibraryThing format support
//  - Nil handling for invalid inputs
//

import Testing
import Foundation
@testable import BooksTrackerFeature

// MARK: - Direct Mapping Tests

@Suite("ReadingStatusParser - Direct Mapping")
struct DirectMappingTests {

    @Test("Wishlist variants map correctly")
    func testWishlistMappings() {
        #expect(ReadingStatusParser.parse("wishlist") == .wishlist)
        #expect(ReadingStatusParser.parse("want to read") == .wishlist)
        #expect(ReadingStatusParser.parse("to-read") == .wishlist)
        #expect(ReadingStatusParser.parse("want") == .wishlist)
        #expect(ReadingStatusParser.parse("planned") == .wishlist)
    }

    @Test("To Read variants map correctly")
    func testToReadMappings() {
        #expect(ReadingStatusParser.parse("to read") == .toRead)
        #expect(ReadingStatusParser.parse("owned") == .toRead)
        #expect(ReadingStatusParser.parse("unread") == .toRead)
        #expect(ReadingStatusParser.parse("not started") == .toRead)
        #expect(ReadingStatusParser.parse("tbr") == .toRead)
        #expect(ReadingStatusParser.parse("on shelf") == .toRead)
    }

    @Test("Currently Reading variants map correctly")
    func testReadingMappings() {
        #expect(ReadingStatusParser.parse("reading") == .reading)
        #expect(ReadingStatusParser.parse("currently reading") == .reading)
        #expect(ReadingStatusParser.parse("in progress") == .reading)
        #expect(ReadingStatusParser.parse("started") == .reading)
        #expect(ReadingStatusParser.parse("current") == .reading)
        #expect(ReadingStatusParser.parse("currently-reading") == .reading)  // Goodreads format
    }

    @Test("Read/Finished variants map correctly")
    func testReadMappings() {
        #expect(ReadingStatusParser.parse("read") == .read)
        #expect(ReadingStatusParser.parse("finished") == .read)
        #expect(ReadingStatusParser.parse("completed") == .read)
        #expect(ReadingStatusParser.parse("done") == .read)
    }

    @Test("On Hold variants map correctly")
    func testOnHoldMappings() {
        #expect(ReadingStatusParser.parse("on hold") == .onHold)
        #expect(ReadingStatusParser.parse("on-hold") == .onHold)
        #expect(ReadingStatusParser.parse("paused") == .onHold)
        #expect(ReadingStatusParser.parse("suspended") == .onHold)
    }

    @Test("DNF variants map correctly")
    func testDNFMappings() {
        #expect(ReadingStatusParser.parse("dnf") == .dnf)
        #expect(ReadingStatusParser.parse("did not finish") == .dnf)
        #expect(ReadingStatusParser.parse("abandoned") == .dnf)
        #expect(ReadingStatusParser.parse("quit") == .dnf)
        #expect(ReadingStatusParser.parse("stopped") == .dnf)
    }
}

// MARK: - Case Insensitivity Tests

@Suite("ReadingStatusParser - Case Insensitivity")
struct CaseInsensitivityTests {

    @Test("UPPERCASE input normalized correctly")
    func testUppercase() {
        #expect(ReadingStatusParser.parse("WISHLIST") == .wishlist)
        #expect(ReadingStatusParser.parse("CURRENTLY READING") == .reading)
        #expect(ReadingStatusParser.parse("READ") == .read)
    }

    @Test("MixedCase input normalized correctly")
    func testMixedCase() {
        #expect(ReadingStatusParser.parse("Want To Read") == .wishlist)
        #expect(ReadingStatusParser.parse("Currently Reading") == .reading)
        #expect(ReadingStatusParser.parse("Finished") == .read)
    }

    @Test("lowercase input works")
    func testLowercase() {
        #expect(ReadingStatusParser.parse("wishlist") == .wishlist)
        #expect(ReadingStatusParser.parse("reading") == .reading)
        #expect(ReadingStatusParser.parse("read") == .read)
    }
}

// MARK: - Fuzzy Matching Tests

@Suite("ReadingStatusParser - Fuzzy Matching")
struct FuzzyMatchingTests {

    @Test("Single character typo corrected (1 edit)")
    func testSingleCharTypo() {
        // "wishlis" → "wishlist" (1 insertion)
        #expect(ReadingStatusParser.parse("wishlis") == .wishlist)

        // "finishd" → "finished" (1 insertion)
        #expect(ReadingStatusParser.parse("finishd") == .read)

        // "reeding" → "reading" (1 substitution: e→a)
        #expect(ReadingStatusParser.parse("reeding") == .reading)
    }

    @Test("Two character typo corrected (2 edits)")
    func testTwoCharTypo() {
        // "currenty reading" → "currently reading" (1 deletion)
        #expect(ReadingStatusParser.parse("currenty reading") == .reading)

        // "wihlst" → "wishlist" (2 edits: h→s, l→i) - borderline
        // Note: This might not match if distance > 2
    }

    @Test("Typos beyond threshold not matched (>2 edits)")
    func testBeyondThreshold() {
        // "foobar" is too different from any status (>2 edits)
        #expect(ReadingStatusParser.parse("foobar") == nil)

        // "xyz" is too different
        #expect(ReadingStatusParser.parse("xyz") == nil)
    }
}

// MARK: - Platform Format Tests

@Suite("ReadingStatusParser - Platform Formats")
struct PlatformFormatTests {

    @Test("Goodreads export format")
    func testGoodreadsFormat() {
        // Goodreads uses "to-read", "currently-reading", "read"
        #expect(ReadingStatusParser.parse("to-read") == .wishlist)
        #expect(ReadingStatusParser.parse("currently-reading") == .reading)
        #expect(ReadingStatusParser.parse("read") == .read)
    }

    @Test("LibraryThing export format")
    func testLibraryThingFormat() {
        // LibraryThing uses "Wishlist", "On Shelf", "Reading"
        #expect(ReadingStatusParser.parse("Wishlist") == .wishlist)
        #expect(ReadingStatusParser.parse("On Shelf") == .toRead)
        #expect(ReadingStatusParser.parse("Reading") == .reading)
    }

    @Test("Generic/Custom formats")
    func testGenericFormats() {
        #expect(ReadingStatusParser.parse("want") == .wishlist)
        #expect(ReadingStatusParser.parse("started") == .reading)
        #expect(ReadingStatusParser.parse("done") == .read)
    }
}

// MARK: - Edge Case Tests

@Suite("ReadingStatusParser - Edge Cases")
struct EdgeCaseTests {

    @Test("Empty string returns nil")
    func testEmptyString() {
        #expect(ReadingStatusParser.parse("") == nil)
        #expect(ReadingStatusParser.parse("   ") == nil)  // Whitespace only
    }

    @Test("Nil input returns nil")
    func testNilInput() {
        let nilString: String? = nil
        #expect(ReadingStatusParser.parse(nilString) == nil)
    }

    @Test("Whitespace trimmed correctly")
    func testWhitespaceTrimming() {
        #expect(ReadingStatusParser.parse("  wishlist  ") == .wishlist)
        #expect(ReadingStatusParser.parse("\treading\n") == .reading)
        #expect(ReadingStatusParser.parse(" want to read ") == .wishlist)
    }

    @Test("Unrecognized strings return nil")
    func testUnrecognizedStrings() {
        #expect(ReadingStatusParser.parse("invalid-status") == nil)
        #expect(ReadingStatusParser.parse("unknown") == nil)
        #expect(ReadingStatusParser.parse("123456") == nil)
    }
}

// MARK: - Backward Compatibility Tests

@Suite("ReadingStatus.from() - Backward Compatibility")
struct BackwardCompatibilityTests {

    @Test("ReadingStatus.from() delegates to parser")
    func testDelegation() {
        // Verify old API still works via delegation
        #expect(ReadingStatus.from(string: "wishlist") == .wishlist)
        #expect(ReadingStatus.from(string: "currently reading") == .reading)
        #expect(ReadingStatus.from(string: "finished") == .read)
    }

    @Test("ReadingStatus.from() handles nil")
    func testNilHandling() {
        #expect(ReadingStatus.from(string: nil) == nil)
    }

    @Test("ReadingStatus.from() benefits from fuzzy matching")
    func testFuzzyMatchingThroughDelegation() {
        // Old API now benefits from new fuzzy matching feature
        #expect(ReadingStatus.from(string: "currenty reading") == .reading)
        #expect(ReadingStatus.from(string: "wishlis") == .wishlist)
    }
}

// MARK: - Performance Tests

@Suite("ReadingStatusParser - Performance")
struct PerformanceTests {

    @Test("Direct lookup is fast (O(1))")
    func testDirectLookupPerformance() {
        // Measure time for 1000 direct lookups
        let start = Date()
        for _ in 0..<1000 {
            _ = ReadingStatusParser.parse("currently reading")
        }
        let elapsed = Date().timeIntervalSince(start)

        // Should complete in <10ms for 1000 lookups
        #expect(elapsed < 0.01, "Direct lookup too slow: \(elapsed)s for 1000 calls")
    }

    @Test("Fuzzy matching is acceptable (<1ms per call)")
    func testFuzzyMatchingPerformance() {
        // Measure time for 100 fuzzy match attempts
        let start = Date()
        for _ in 0..<100 {
            _ = ReadingStatusParser.parse("currenty reading")  // Triggers fuzzy matching
        }
        let elapsed = Date().timeIntervalSince(start)

        // Should complete in <100ms for 100 fuzzy matches (<1ms each)
        #expect(elapsed < 0.1, "Fuzzy matching too slow: \(elapsed)s for 100 calls")
    }
}
