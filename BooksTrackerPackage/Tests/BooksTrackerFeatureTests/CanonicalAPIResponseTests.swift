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

// MARK: - ApiResponse Decoding Tests

@Suite("Canonical API Response Parsing")
struct CanonicalAPIResponseTests {

    // MARK: - Success Case Tests

    @Test("Decode successful BookSearchResponse")
    func testDecodeSuccessfulBookSearchResponse() throws {
        let json = """
        {
          "success": true,
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
          "meta": {
            "timestamp": "2025-10-30T12:00:00Z",
            "processingTime": 123,
            "provider": "google-books",
            "cached": false
          }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let envelope = try decoder.decode(ApiResponse<BookSearchResponse>.self, from: data)

        // Verify success case
        guard case .success(let searchResponse, let meta) = envelope else {
            Issue.record("Expected success case, got failure")
            return
        }

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
        #expect(meta.provider == "google-books")
        #expect(meta.cached == false)
        #expect(meta.processingTime == 123)
    }

    @Test("Decode failure ApiResponse")
    func testDecodeFailureResponse() throws {
        let json = """
        {
          "success": false,
          "error": {
            "message": "Book not found",
            "code": "NOT_FOUND",
            "details": null
          },
          "meta": {
            "timestamp": "2025-10-30T12:00:00Z",
            "processingTime": 45,
            "provider": "google-books",
            "cached": false
          }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let envelope = try decoder.decode(ApiResponse<BookSearchResponse>.self, from: data)

        // Verify failure case
        guard case .failure(let error, let meta) = envelope else {
            Issue.record("Expected failure case, got success")
            return
        }

        #expect(error.message == "Book not found")
        #expect(error.code == .notFound)
        #expect(meta.processingTime == 45)
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
          "success": true,
          "data": {
            "works": [],
            "authors": [],
            "totalResults": 0
          },
          "meta": {
            "timestamp": "2025-10-30T12:00:00Z",
            "processingTime": 10,
            "provider": "google-books",
            "cached": true
          }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let envelope = try decoder.decode(ApiResponse<BookSearchResponse>.self, from: data)

        guard case .success(let searchResponse, _) = envelope else {
            Issue.record("Expected success case")
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
          "success": true,
          "data": {
            "works": [
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: Error.self) {
            try decoder.decode(ApiResponse<BookSearchResponse>.self, from: data)
        }
    }

    @Test("Missing required fields throws error")
    func testMissingRequiredFields() {
        // Missing 'data' field in success case
        let json = """
        {
          "success": true,
          "meta": {
            "timestamp": "2025-10-30T12:00:00Z"
          }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: Error.self) {
            try decoder.decode(ApiResponse<BookSearchResponse>.self, from: data)
        }
    }
}
