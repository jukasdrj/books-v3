# ResponseEnvelope Decoder Architecture Proposal

**Question:** Should we create a unified ResponseEnvelope decoder or keep specialized implementations?

**Date:** November 30, 2025  
**Status:** Architecture Decision Record

---

## Current State Analysis

### Implementation Distribution

| Service | Current Pattern | Line Count | Duplication |
|---------|----------------|------------|-------------|
| **Bookshelf Scanning** | Generic `unwrapEnvelope<T>()` | 24 lines | ✅ Reusable |
| **CSV Import** | Manual decode × 3 endpoints | ~45 lines | ❌ Duplicated |
| **V2 Enrichment** | Manual decode × 2 cases | ~30 lines | ❌ Duplicated |
| **Batch Enrichment** | Manual decode | ~15 lines | ❌ Duplicated |
| **Search API** | Uses `decodeEnvelope()` in BooksTrackAPI | ~15 lines | ✅ Shared |

**Total Duplication:** ~105 lines of nearly identical decode logic

### Current Error Type Landscape

Each service has its own error enum:
```swift
// EnrichmentAPIClient.swift
enum EnrichmentError: Error {
    case apiError(String)
    case invalidResponse
    case circuitBreakerOpen(retryAfter: Int, failureRate: Double)
    // ... 10+ more cases
}

// GeminiCSVImportService.swift
enum GeminiCSVImportError: Error {
    case serverError(Int, String)
    case decodingFailed(Error)
    case networkError(Error)
    // ... 7+ more cases
}

// BookshelfAIService.swift
enum BookshelfAIError: Error {
    case apiError(code: String, message: String)
    case resultsExpired
    case decodingFailed(Error)
    // ... 9+ more cases
}
```

**Problem:** Can't use one error type for all services (domain-specific errors)

---

## Architecture Options

### Option 1: Current State - Specialized Per Service ❌

**Keep manual decoding in each service**

```swift
// In each service file (duplicated 10+ times)
let envelope = try decoder.decode(ResponseEnvelope<T>.self, from: data)

if let error = envelope.error {
    throw ServiceSpecificError.apiError(error.message)
}

guard let result = envelope.data else {
    throw ServiceSpecificError.invalidResponse
}

return result
```

**Pros:**
- ✅ No abstraction overhead
- ✅ Full control per service
- ✅ No dependencies between services

**Cons:**
- ❌ ~105 lines of duplication
- ❌ Inconsistent error handling
- ❌ Hard to update when ResponseEnvelope changes
- ❌ Testing duplicated across services

**Verdict:** ❌ **NOT RECOMMENDED** - Too much duplication

---

### Option 2: Generic Protocol ❌

```swift
protocol ResponseEnvelopeDecoder {
    associatedtype ErrorType: Error
    func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T
    func mapError(_ envelopeError: ResponseEnvelope<T>.ErrorInfo) -> ErrorType
}
```

**Pros:**
- ✅ Type-safe per service
- ✅ Enforces consistent pattern

**Cons:**
- ❌ Over-engineered for simple task
- ❌ Protocol complexity (associated types)
- ❌ Still need implementation per service
- ❌ Swift protocol limitations

**Verdict:** ❌ **NOT RECOMMENDED** - Too complex

---

### Option 3: Shared Utility with Generic Error Type ⚠️

```swift
// Common/ResponseEnvelopeDecoder.swift
public enum ResponseEnvelopeError: Error, LocalizedError {
    case apiError(code: String?, message: String)
    case missingData
    case decodingFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .apiError(let code, let message):
            return code != nil ? "\(message) (Code: \(code!))" : message
        case .missingData:
            return "Response data is missing"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

public struct ResponseEnvelopeDecoder {
    public static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        
        do {
            let envelope = try decoder.decode(ResponseEnvelope<T>.self, from: data)
            
            if let error = envelope.error {
                throw ResponseEnvelopeError.apiError(
                    code: error.code,
                    message: error.message
                )
            }
            
            guard let result = envelope.data else {
                throw ResponseEnvelopeError.missingData
            }
            
            return result
            
        } catch let error as DecodingError {
            throw ResponseEnvelopeError.decodingFailed(error)
        } catch let error as ResponseEnvelopeError {
            throw error
        } catch {
            throw ResponseEnvelopeError.decodingFailed(error)
        }
    }
}
```

**Usage in Each Service:**
```swift
// EnrichmentAPIClient.swift
do {
    let book = try ResponseEnvelopeDecoder.decode(EnrichedBookDTO.self, from: data)
    return book
} catch let error as ResponseEnvelopeError {
    // Map to service-specific error
    switch error {
    case .apiError(let code, let message):
        if code == "CIRCUIT_BREAKER_OPEN" {
            throw EnrichmentError.circuitBreakerOpen(...)
        }
        throw EnrichmentError.apiError(message)
    case .missingData:
        throw EnrichmentError.invalidResponse
    case .decodingFailed(let underlying):
        throw EnrichmentError.decodingFailed(underlying)
    }
}
```

**Pros:**
- ✅ Single decoder implementation (~20 lines)
- ✅ Eliminates ~105 lines of duplication
- ✅ Type-safe generic
- ✅ Easy to test
- ✅ Services retain domain errors

**Cons:**
- ⚠️ Requires error mapping in each service
- ⚠️ Two-step error handling
- ⚠️ Generic error type might not fit all cases

**Verdict:** ⚠️ **VIABLE** - Good balance but adds mapping layer

---

### Option 4: Extension on Data ✅ **RECOMMENDED**

```swift
// Common/Data+ResponseEnvelope.swift
public extension Data {
    /// Decode ResponseEnvelope and extract data payload
    /// - Parameter type: The expected payload type
    /// - Returns: Decoded payload of type T
    /// - Throws: ResponseEnvelopeError for API/decoding errors
    func decodeEnvelope<T: Codable>(
        _ type: T.Type
    ) throws -> T {
        let decoder = JSONDecoder()
        
        do {
            let envelope = try decoder.decode(ResponseEnvelope<T>.self, from: self)
            
            if let error = envelope.error {
                throw ResponseEnvelopeError.apiError(
                    code: error.code,
                    message: error.message,
                    details: error.details
                )
            }
            
            guard let result = envelope.data else {
                throw ResponseEnvelopeError.missingData
            }
            
            return result
            
        } catch let error as DecodingError {
            throw ResponseEnvelopeError.decodingFailed(error)
        } catch let error as ResponseEnvelopeError {
            throw error
        } catch {
            throw ResponseEnvelopeError.decodingFailed(error)
        }
    }
}

public enum ResponseEnvelopeError: Error, LocalizedError {
    case apiError(code: String?, message: String, details: [String: Any]?)
    case missingData
    case decodingFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .apiError(let code, let message, _):
            if let code = code {
                return "\(message) (Code: \(code))"
            }
            return message
        case .missingData:
            return "Response envelope contains no data"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
    
    // Helper to extract typed details
    public func detail<T>(_ key: String) -> T? {
        switch self {
        case .apiError(_, _, let details):
            return details?[key] as? T
        default:
            return nil
        }
    }
}
```

**Usage - Simple Case:**
```swift
// EnrichmentAPIClient.swift - Simple mapping
let book = try data.decodeEnvelope(EnrichedBookDTO.self)
```

**Usage - Complex Error Handling:**
```swift
// EnrichmentAPIClient.swift - Circuit breaker specific handling
do {
    let book = try data.decodeEnvelope(EnrichedBookDTO.self)
    return book
} catch let error as ResponseEnvelopeError {
    switch error {
    case .apiError(let code, let message, _) where code == "CIRCUIT_BREAKER_OPEN":
        let retryAfter: Int = error.detail("retryAfter") ?? 60
        let failureRate: Double = error.detail("failureRate") ?? 0.0
        throw EnrichmentError.circuitBreakerOpen(
            retryAfter: retryAfter,
            failureRate: failureRate
        )
    case .apiError(_, let message, _):
        throw EnrichmentError.apiError(message)
    case .missingData:
        throw EnrichmentError.invalidResponse
    case .decodingFailed(let underlying):
        throw EnrichmentError.decodingFailed(underlying)
    }
}
```

**Usage - CSV Import (Minimal Mapping):**
```swift
// GeminiCSVImportService.swift
do {
    let importResponse = try data.decodeEnvelope(GeminiCSVImportResponse.self)
    return (jobId: importResponse.jobId, authToken: importResponse.authToken)
} catch {
    throw GeminiCSVImportError.decodingFailed(error)
}
```

**Usage - Bookshelf (Keep Current Helper):**
```swift
// BookshelfAIService.swift - Can keep unwrapEnvelope() as-is or migrate
private func unwrapEnvelope<T: Codable>(_ data: Data) throws -> T {
    // Could delegate to data.decodeEnvelope() but keep service-specific error mapping
    do {
        return try data.decodeEnvelope(T.self)
    } catch let error as ResponseEnvelopeError {
        // Map to BookshelfAIError
        switch error {
        case .apiError(let code, let message, _):
            throw BookshelfAIError.apiError(code: code ?? "UNKNOWN", message: message)
        case .missingData:
            throw BookshelfAIError.invalidResponse
        case .decodingFailed(let underlying):
            throw BookshelfAIError.decodingFailed(underlying)
        }
    }
}
```

---

## Comparison Matrix

| Criteria | Option 1<br>(Current) | Option 2<br>(Protocol) | Option 3<br>(Utility) | Option 4<br>(Extension) |
|----------|------------|-----------|----------|------------|
| **Code Duplication** | ❌ High | ⚠️ Medium | ✅ Low | ✅ Low |
| **Discoverability** | ✅ Obvious | ❌ Hidden | ⚠️ Requires import | ✅ Autocomplete |
| **Type Safety** | ✅ Full | ✅ Full | ✅ Full | ✅ Full |
| **Simplicity** | ✅ Simple | ❌ Complex | ⚠️ Medium | ✅ Simple |
| **Flexibility** | ✅ Full control | ⚠️ Protocol limits | ✅ Good | ✅ Good |
| **Error Handling** | ⚠️ Inconsistent | ⚠️ Forced | ⚠️ Two-step | ⚠️ Two-step |
| **Migration Cost** | ✅ None | ❌ High | ⚠️ Medium | ⚠️ Medium |
| **Maintenance** | ❌ Error-prone | ⚠️ Complex | ✅ Single source | ✅ Single source |
| **Testing** | ❌ Per service | ⚠️ Per impl | ✅ Once | ✅ Once |

---

## Recommendation: Option 4 (Data Extension) ✅

### Why This Is Best:

1. **Ergonomic API**
   ```swift
   // Beautiful, discoverable syntax
   let book = try data.decodeEnvelope(EnrichedBookDTO.self)
   ```

2. **Eliminates Duplication**
   - Removes ~105 lines of duplicated code
   - Single implementation, tested once
   - Consistent error handling

3. **Flexible Error Handling**
   - Services can map errors as needed
   - Circuit breaker logic preserved
   - Domain errors retained

4. **Autocomplete Discovery**
   - Type `data.` → Xcode suggests `decodeEnvelope()`
   - No need to remember utility class name
   - Standard Swift pattern (like `String.data(using:)`)

5. **Backward Compatible**
   - Existing `unwrapEnvelope()` can delegate to extension
   - Gradual migration possible
   - No breaking changes

6. **Details Dictionary Support**
   - Generic `details: [String: Any]?` for custom error data
   - Type-safe `detail<T>()` helper
   - Supports circuit breaker, rate limit, etc.

---

## Implementation Plan

### Phase 1: Create Extension (30 minutes)

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/Data+ResponseEnvelope.swift`

```swift
import Foundation

// MARK: - ResponseEnvelope Decoding Error

public enum ResponseEnvelopeError: Error, LocalizedError {
    case apiError(code: String?, message: String, details: [String: Any]?)
    case missingData
    case decodingFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .apiError(let code, let message, _):
            if let code = code {
                return "\(message) (Code: \(code))"
            }
            return message
        case .missingData:
            return "Response envelope contains no data"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
    
    /// Extract typed detail value from API error
    public func detail<T>(_ key: String) -> T? {
        switch self {
        case .apiError(_, _, let details):
            return details?[key] as? T
        default:
            return nil
        }
    }
}

// MARK: - Data Extension

public extension Data {
    /// Decode ResponseEnvelope and extract data payload
    ///
    /// Decodes a ResponseEnvelope<T> from JSON data, checks for API errors,
    /// and returns the unwrapped payload of type T.
    ///
    /// - Parameter type: The expected payload type (e.g., `EnrichedBookDTO.self`)
    /// - Returns: Decoded payload of type T
    /// - Throws: `ResponseEnvelopeError` for API errors, missing data, or decoding failures
    ///
    /// Example:
    /// ```swift
    /// let book = try data.decodeEnvelope(EnrichedBookDTO.self)
    /// ```
    func decodeEnvelope<T: Codable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        
        do {
            let envelope = try decoder.decode(ResponseEnvelope<T>.self, from: self)
            
            // Check for API error in envelope
            if let error = envelope.error {
                throw ResponseEnvelopeError.apiError(
                    code: error.code,
                    message: error.message,
                    details: error.details
                )
            }
            
            // Ensure data payload exists
            guard let result = envelope.data else {
                throw ResponseEnvelopeError.missingData
            }
            
            return result
            
        } catch let error as DecodingError {
            throw ResponseEnvelopeError.decodingFailed(error)
        } catch let error as ResponseEnvelopeError {
            throw error
        } catch {
            throw ResponseEnvelopeError.decodingFailed(error)
        }
    }
}
```

### Phase 2: Migrate Services (1-2 hours)

#### 2.1 EnrichmentAPIClient.swift

**Before:**
```swift
let envelope = try decoder.decode(ResponseEnvelope<EnrichedBookDTO>.self, from: data)

if let error = envelope.error {
    throw EnrichmentError.apiError(error.message)
}

guard let book = envelope.data else {
    throw EnrichmentError.invalidResponse
}

return book
```

**After:**
```swift
do {
    return try data.decodeEnvelope(EnrichedBookDTO.self)
} catch let error as ResponseEnvelopeError {
    switch error {
    case .apiError(let code, let message, _) where code == "CIRCUIT_BREAKER_OPEN":
        let retryAfter: Int = error.detail("retryAfter") ?? 60
        let failureRate: Double = error.detail("failureRate") ?? 0.0
        throw EnrichmentError.circuitBreakerOpen(
            retryAfter: retryAfter,
            failureRate: failureRate
        )
    case .apiError(_, let message, _):
        throw EnrichmentError.apiError(message)
    case .missingData, .decodingFailed:
        throw EnrichmentError.invalidResponse
    }
}
```

#### 2.2 GeminiCSVImportService.swift

**Before:**
```swift
let envelope = try decoder.decode(ResponseEnvelope<GeminiCSVImportResponse>.self, from: data)

if let error = envelope.error {
    throw GeminiCSVImportError.serverError(httpResponse.statusCode, error.message)
}

guard let importResponse = envelope.data else {
    throw GeminiCSVImportError.serverError(httpResponse.statusCode, "No data")
}
```

**After:**
```swift
do {
    let importResponse = try data.decodeEnvelope(GeminiCSVImportResponse.self)
    return (jobId: importResponse.jobId, authToken: importResponse.authToken)
} catch {
    throw GeminiCSVImportError.decodingFailed(error)
}
```

#### 2.3 BookshelfAIService.swift

**Before:**
```swift
private func unwrapEnvelope<T: Codable>(_ data: Data) throws -> T {
    let decoder = JSONDecoder()
    let envelope = try decoder.decode(ResponseEnvelope<T>.self, from: data)
    
    guard let result = envelope.data else {
        if let error = envelope.error {
            throw BookshelfAIError.apiError(code: error.code ?? "UNKNOWN", message: error.message)
        }
        throw BookshelfAIError.apiError(code: "NO_DATA", message: "Missing results data")
    }
    
    return result
}
```

**After:**
```swift
private func unwrapEnvelope<T: Codable>(_ data: Data) throws -> T {
    do {
        return try data.decodeEnvelope(T.self)
    } catch let error as ResponseEnvelopeError {
        switch error {
        case .apiError(let code, let message, _):
            throw BookshelfAIError.apiError(code: code ?? "UNKNOWN", message: message)
        case .missingData:
            throw BookshelfAIError.apiError(code: "NO_DATA", message: "Missing results data")
        case .decodingFailed(let underlying):
            throw BookshelfAIError.decodingFailed(underlying)
        }
    }
}
```

### Phase 3: Add Tests (30 minutes)

```swift
// Tests/BooksTrackerFeatureTests/DataResponseEnvelopeTests.swift
import XCTest
@testable import BooksTrackerFeature

final class DataResponseEnvelopeTests: XCTestCase {
    
    func testDecodeEnvelopeSuccess() throws {
        let json = """
        {
            "success": true,
            "data": {
                "isbn": "9780439064873",
                "title": "Harry Potter"
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let book = try data.decodeEnvelope(TestBookDTO.self)
        
        XCTAssertEqual(book.isbn, "9780439064873")
        XCTAssertEqual(book.title, "Harry Potter")
    }
    
    func testDecodeEnvelopeAPIError() {
        let json = """
        {
            "success": false,
            "error": {
                "code": "NOT_FOUND",
                "message": "Book not found"
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        
        XCTAssertThrowsError(try data.decodeEnvelope(TestBookDTO.self)) { error in
            guard case ResponseEnvelopeError.apiError(let code, let message, _) = error else {
                XCTFail("Expected apiError")
                return
            }
            XCTAssertEqual(code, "NOT_FOUND")
            XCTAssertEqual(message, "Book not found")
        }
    }
    
    func testDecodeEnvelopeMissingData() {
        let json = """
        {
            "success": true
        }
        """
        
        let data = json.data(using: .utf8)!
        
        XCTAssertThrowsError(try data.decodeEnvelope(TestBookDTO.self)) { error in
            XCTAssertTrue(error is ResponseEnvelopeError)
            if case ResponseEnvelopeError.missingData = error {
                // Expected
            } else {
                XCTFail("Expected missingData error")
            }
        }
    }
    
    func testDecodeEnvelopeWithDetails() throws {
        let json = """
        {
            "success": false,
            "error": {
                "code": "CIRCUIT_BREAKER_OPEN",
                "message": "Circuit breaker is open",
                "details": {
                    "retryAfter": 60,
                    "failureRate": 0.75
                }
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        
        do {
            _ = try data.decodeEnvelope(TestBookDTO.self)
            XCTFail("Should have thrown")
        } catch let error as ResponseEnvelopeError {
            let retryAfter: Int? = error.detail("retryAfter")
            let failureRate: Double? = error.detail("failureRate")
            
            XCTAssertEqual(retryAfter, 60)
            XCTAssertEqual(failureRate, 0.75)
        }
    }
}

private struct TestBookDTO: Codable {
    let isbn: String
    let title: String
}
```

---

## Migration Strategy

### Gradual Rollout (Recommended)

1. **Week 1:** Add extension, don't change any existing code
2. **Week 2:** Migrate 1 service (EnrichmentAPIClient) and test
3. **Week 3:** Migrate remaining services if Week 2 succeeds
4. **Week 4:** Remove old helper methods

### Big Bang (Faster but Riskier)

1. Add extension
2. Migrate all services in one PR
3. Test thoroughly
4. Deploy

---

## Success Metrics

| Metric | Before | After | Target |
|--------|--------|-------|--------|
| Lines of Code | ~105 duplicated | ~30 shared | <50 |
| Test Coverage | Per-service | Centralized | 100% |
| Consistency | Variable | Uniform | ✅ |
| Maintenance Points | 10+ files | 1 file | 1 |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Breaking existing code | Low | High | Gradual migration + tests |
| Error mapping complexity | Medium | Low | Document patterns |
| Details dictionary type safety | Low | Medium | Generic helper method |
| Developer adoption | Low | Low | Good naming + docs |

---

## Decision

**RECOMMENDED:** ✅ Implement Option 4 (Data Extension)

**Rationale:**
1. Eliminates 75% of duplication (~105 → ~30 lines)
2. Standard Swift pattern (discoverable via autocomplete)
3. Flexible enough for all current use cases
4. Easy to test and maintain
5. Backward compatible with gradual migration

**Next Steps:**
1. Create `Data+ResponseEnvelope.swift` extension
2. Add comprehensive unit tests
3. Migrate EnrichmentAPIClient first (highest impact)
4. Monitor for issues, then migrate remaining services

---

**Decision Date:** November 30, 2025  
**Decided By:** Architecture Review  
**Status:** Proposed - Awaiting Implementation
