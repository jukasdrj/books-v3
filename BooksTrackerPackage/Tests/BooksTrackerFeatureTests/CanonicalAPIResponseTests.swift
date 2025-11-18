//
//  CanonicalAPIResponseTests.swift
//  BooksTrackerFeatureTests
//
//  Created by Claude on 2025-10-30.
//  Tests for canonical v1 API response parsing
//

import Testing
import Foundation
@testable import BooksTrackerFeature

// MARK: - ResponseEnvelope Decoding Tests

@Suite("Canonical API Response Parsing")
struct CanonicalAPIResponseTests {

    // MARK: - Success Case Tests

    @Test("Decode successful BookSearchResponse")
    func testDecodeSuccessfulBookSearchResponse() throws {
        let json = """
        {
          "data": {
            "works": [
              {
                "title": "1984",
                "subjectTags": ["Fiction", "Dystopian"],
                "originalLanguage": "en",
                "firstPublicationYear": 1949,
                "description": "A dystopian social science fiction novel",
                "synthetic": false,
                "primaryProvider": "google-books",
                "contributors": ["google-books"],
                "openLibraryID": null,
                "openLibraryWorkID": "OL1168007W",
                "isbndbID": null,
                "googleBooksVolumeID": "kotPYEqx7kMC",
                "goodreadsID": null,
                "goodreadsWorkIDs": [],
                "amazonASINs": [],
                "librarythingIDs": [],
                "googleBooksVolumeIDs": ["kotPYEqx7kMC"],
                "lastISBNDBSync": null,
                "isbndbQuality": 0,
                "reviewStatus": "verified",
                "originalImagePath": null,
                "boundingBox": null
              }
            ],
            "authors": [
              {
                "name": "George Orwell",
                "gender": "Male"
              }
            ],
            "totalResults": 1
          },
          "metadata": {
            "timestamp": "2025-10-30T12:00:00Z",
            "processingTime": 123,
            "provider": "google-books",
            "cached": false
          }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let envelope = try decoder.decode(ResponseEnvelope<BookSearchResponse>.self, from: data)

        // Verify success case
        guard let searchResponse = envelope.data else {
            Issue.record("Expected data in envelope, got nil")
            return
        }

        let metadata = envelope.metadata

        // Verify works array
        #expect(searchResponse.works.count == 1)
        let work = searchResponse.works[0]
        #expect(work.title == "1984")
        #expect(work.firstPublicationYear == 1949)
        #expect(work.openLibraryWorkID == "OL1168007W")
        #expect(work.googleBooksVolumeIDs == ["kotPYEqx7kMC"])
        #expect(work.primaryProvider == "google-books")
        #expect(work.synthetic == false)

        // Verify authors array
        #expect(searchResponse.authors.count == 1)
        #expect(searchResponse.authors[0].name == "George Orwell")

        // Verify metadata
        #expect(metadata.provider == "google-books")
        #expect(metadata.cached == false)
        #expect(metadata.processingTime == 123)
    }

    @Test("Decode failure ResponseEnvelope")
    func testDecodeFailureResponse() throws {
        let json = """
        {
          "data": null,
          "error": {
            "message": "Book not found",
            "code": "NOT_FOUND"
          },
          "metadata": {
            "timestamp": "2025-10-30T12:00:00Z",
            "processingTime": 45,
            "provider": "google-books",
            "cached": false
          }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let envelope = try decoder.decode(ResponseEnvelope<BookSearchResponse>.self, from: data)

        // Verify failure case
        guard let error = envelope.error else {
            Issue.record("Expected error in envelope, got nil")
            return
        }

        let metadata = envelope.metadata

        #expect(error.message == "Book not found")
        #expect(error.code == "NOT_FOUND")
        #expect(metadata.processingTime == 45)
    }

    // MARK: - WorkDTO Validation Tests

    @Test("WorkDTO required fields")
    func testWorkDTORequiredFields() throws {
        let json = """
        {
          "title": "The Great Gatsby",
          "subjectTags": ["Fiction", "Classic"],
          "goodreadsWorkIDs": [],
          "amazonASINs": [],
          "librarythingIDs": [],
          "googleBooksVolumeIDs": [],
          "isbndbQuality": 0,
          "reviewStatus": "verified"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let workDTO = try decoder.decode(WorkDTO.self, from: data)

        #expect(workDTO.title == "The Great Gatsby")
        #expect(workDTO.subjectTags == ["Fiction", "Classic"])
        #expect(workDTO.googleBooksVolumeIDs.isEmpty)
        #expect(workDTO.reviewStatus == .verified)
    }

    @Test("WorkDTO optional fields")
    func testWorkDTOOptionalFields() throws {
        let json = """
        {
          "title": "Test Book",
          "subjectTags": [],
          "originalLanguage": "en",
          "firstPublicationYear": 2020,
          "description": "A test book",
          "synthetic": true,
          "primaryProvider": "openlibrary",
          "contributors": ["openlibrary", "google-books"],
          "googleBooksVolumeIDs": ["ABC123", "DEF456"],
          "goodreadsWorkIDs": [],
          "amazonASINs": [],
          "librarythingIDs": [],
          "isbndbQuality": 85,
          "reviewStatus": "needsReview"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let workDTO = try decoder.decode(WorkDTO.self, from: data)

        #expect(workDTO.originalLanguage == "en")
        #expect(workDTO.firstPublicationYear == 2020)
        #expect(workDTO.description == "A test book")
        #expect(workDTO.synthetic == true)
        #expect(workDTO.primaryProvider == "openlibrary")
        #expect(workDTO.contributors == ["openlibrary", "google-books"])
        #expect(workDTO.googleBooksVolumeIDs == ["ABC123", "DEF456"])
        #expect(workDTO.isbndbQuality == 85)
        #expect(workDTO.reviewStatus == .needsReview)
    }

    // MARK: - Edge Case Tests

    @Test("Empty works array")
    func testEmptyWorksArray() throws {
        let json = """
        {
          "data": {
            "works": [],
            "authors": [],
            "totalResults": 0
          },
          "metadata": {
            "timestamp": "2025-10-30T12:00:00Z",
            "processingTime": 10,
            "provider": "google-books",
            "cached": true
          }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let envelope = try decoder.decode(ResponseEnvelope<BookSearchResponse>.self, from: data)

        guard let searchResponse = envelope.data else {
            Issue.record("Expected data in envelope")
            return
        }

        #expect(searchResponse.works.isEmpty)
        #expect(searchResponse.authors.isEmpty)
        #expect(searchResponse.totalResults == 0)
    }

    @Test("Malformed JSON throws error")
    func testMalformedJSON() {
        let json = """
        {
          "data": {
            "works": [
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: Error.self) {
            try decoder.decode(ResponseEnvelope<BookSearchResponse>.self, from: data)
        }
    }

    @Test("Missing required metadata field throws error")
    func testMissingRequiredFields() {
        // Missing 'metadata' field
        let json = """
        {
          "data": {
            "works": [],
            "authors": []
          }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: Error.self) {
            try decoder.decode(ResponseEnvelope<BookSearchResponse>.self, from: data)
        }
    }

    // MARK: - Edge Case Tests (Issue #217)

    @Test("EditionDTO with missing ISBNs decodes successfully")
    func testEditionDTO_missingISBN_decodesSuccessfully() throws {
        let json = """
        {
          "title": "Unknown Book",
          "publisher": "Unknown",
          "publicationDate": "2020",
          "format": "unknown",
          "coverImageURL": null,
          "contributors": [],
          "isbns": []
        }
        """
        let edition = try JSONDecoder().decode(EditionDTO.self, from: json.data(using: .utf8)!)

        #expect(edition.isbn == nil)
        #expect(edition.isbns.isEmpty)
        #expect(edition.title == "Unknown Book")
    }

    @Test("WorkDTO round-trip serialization preserves data")
    func testWorkDTO_roundTripSerialization_preservesData() throws {
        let original = WorkDTO(
            title: "The Hobbit",
            subjectTags: ["fantasy", "adventure"],
            originalLanguage: "en",
            firstPublicationYear: 1937,
            description: "A fantasy novel",
            synthetic: false,
            primaryProvider: "google-books",
            contributors: ["google-books"],
            openLibraryID: nil,
            openLibraryWorkID: "OL26320A",
            isbndbID: nil,
            googleBooksVolumeID: "hFfhrCWiLSMC",
            goodreadsID: nil,
            goodreadsWorkIDs: [],
            amazonASINs: [],
            librarythingIDs: [],
            googleBooksVolumeIDs: ["hFfhrCWiLSMC"],
            lastISBNDBSync: nil,
            isbndbQuality: 0,
            reviewStatus: .verified,
            originalImagePath: nil,
            boundingBox: nil
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkDTO.self, from: encoded)

        #expect(decoded.title == original.title)
        #expect(decoded.openLibraryWorkID == original.openLibraryWorkID)
        #expect(decoded.synthetic == original.synthetic)
        #expect(decoded.firstPublicationYear == original.firstPublicationYear)
    }
}
