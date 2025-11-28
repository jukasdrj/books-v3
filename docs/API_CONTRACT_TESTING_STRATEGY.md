# API Contract Testing Strategy

> **Purpose:** This document outlines testing strategies to catch mismatches between the API contract (`docs/API_CONTRACT.md`, `docs/openapi.yaml`) and the Swift codebase.

## Overview

The BooksTrack iOS app communicates with a Cloudflare Workers API. Mismatches between the API contract and Swift DTOs can cause:
- **Runtime crashes** when JSON decoding fails
- **Silent data loss** when fields are missing
- **Feature regressions** when new API fields aren't captured

This testing strategy provides multiple layers of protection.

## Testing Layers

### 1. Contract Compliance Tests (`APIContractComplianceTests.swift`)

**Purpose:** Verify Swift DTOs correctly implement the API contract.

**What They Test:**
- Response envelope structure (Section 3)
- Required and optional fields (Section 4)
- Error response formats (Section 6)
- Job status and WebSocket messages (Sections 7-8)
- Enum value alignment

**Example:**
```swift
@Test("Success response matches contract structure (Section 3.1)")
func successResponseMatchesContract() throws {
    let json = """
    {
      "data": { "works": [], "editions": [], "authors": [], "resultCount": 0 },
      "metadata": { "timestamp": "2025-11-27T10:30:00Z", "cached": false }
    }
    """
    let response = try JSONDecoder().decode(ResponseEnvelope<BookSearchResponse>.self, from: json.data(using: .utf8)!)
    #expect(response.data != nil, "Success responses must have non-null data field")
}
```

### 2. Defensive Decoding Tests

**Purpose:** Ensure DTOs don't crash when backend violates the contract.

**What They Test:**
- Missing required fields default to sensible values
- Malformed data is handled gracefully
- Unknown enum values don't crash

**Example:**
```swift
@Test("WorkDTO decodes when backend omits required fields")
func workDTOHandlesMissingRequiredFields() throws {
    let json = """
    { "title": "Minimal Book" }
    """
    let work = try JSONDecoder().decode(WorkDTO.self, from: json.data(using: .utf8)!)
    #expect(work.subjectTags.isEmpty)  // Defaults to []
}
```

### 3. Round-Trip Snapshot Tests

**Purpose:** Verify encode/decode preserves all data.

**What They Test:**
- All DTO fields survive serialization
- No data corruption during JSON conversion
- Field naming consistency

**Example:**
```swift
@Test("WorkDTO round-trip preserves all contract fields")
func workDTORoundTrip() throws {
    let original = WorkDTO(title: "Test", ...)
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(WorkDTO.self, from: encoded)
    #expect(decoded == original)
}
```

### 4. Live API Integration Tests (`APIIntegrationTests.swift`)

**Purpose:** Verify real API responses are parseable.

**What They Test:**
- Production API returns valid JSON
- Response structure matches expectations
- New API features are backwards compatible

**Example:**
```swift
@Test("GET /v1/search/isbn returns valid results")
func testSearchISBN_Valid() async throws {
    let (data, _) = try await URLSession.shared.data(from: url)
    let envelope = try JSONDecoder().decode(ApiResponse<BookSearchResponse>.self, from: data)
    #expect(envelope.data != nil)
}
```

## When to Run Tests

| Test Type | When to Run |
|-----------|-------------|
| Contract Compliance | Every PR affecting `DTOs/`, `Services/` |
| Defensive Decoding | Every PR affecting `DTOs/` |
| Round-Trip Snapshots | Every PR affecting `DTOs/` |
| Live API Integration | Pre-release, backend deployments |

## Detecting Contract Drift

### Symptoms of Drift

1. **Build Warnings in DTOs:** Compiler warnings about unused fields
2. **Test Failures:** Contract tests fail when API changes
3. **Runtime Errors:** Decoding errors in production logs
4. **Silent Bugs:** Features stop working without errors

### Automated Detection

Add this CI check to detect drift:

```yaml
# .github/workflows/contract-check.yml
- name: Run Contract Tests
  run: |
    cd BooksTrackerPackage
    swift test --filter APIContractComplianceTests
```

## Handling Contract Changes

### When Backend Adds a Field

1. Update `docs/API_CONTRACT.md`
2. Update `docs/openapi.yaml`
3. Add field to Swift DTO (optional by default)
4. Add contract compliance test
5. Add defensive decoding test

### When Backend Removes a Field

1. Update `docs/API_CONTRACT.md`
2. Update `docs/openapi.yaml`
3. Mark Swift field as deprecated
4. Update tests to expect missing field
5. Remove after deprecation period (90 days)

### When Backend Changes Field Type

1. **DON'T** modify DTO immediately
2. Add defensive decoding to handle both types
3. Add contract test for new type
4. Coordinate migration with backend team
5. Remove old type support after backend migration

## Best Practices

### DTO Design

```swift
// ✅ Good: Defensive decoding with defaults
public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(String.self, forKey: .title)
    // Provide defaults for fields backend might omit
    subjectTags = try container.decodeIfPresent([String].self, forKey: .subjectTags) ?? []
}

// ❌ Bad: Assumes all fields are always present
public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(String.self, forKey: .title)
    subjectTags = try container.decode([String].self, forKey: .subjectTags)  // Crashes if missing!
}
```

### Test Design

```swift
// ✅ Good: Tests both happy path AND edge cases
@Test("WorkDTO decodes with all fields")
@Test("WorkDTO decodes with minimal fields")
@Test("WorkDTO decodes when backend omits required fields")

// ❌ Bad: Only tests happy path
@Test("WorkDTO decodes from JSON")
```

### Contract Documentation

- Keep `API_CONTRACT.md` as single source of truth
- Update contract BEFORE changing DTOs
- Document breaking changes in changelog
- Use semantic versioning for API changes

## File Organization

```
BooksTrackerPackage/Tests/BooksTrackerFeatureTests/
├── APIContractComplianceTests.swift    # Contract structure tests
├── DTOTests.swift                       # DTO unit tests
├── CanonicalAPIResponseTests.swift      # Response parsing tests
├── APIIntegrationTests.swift            # Live API tests
├── APIErrorTests.swift                  # Error handling tests
└── WebSocketHelpersTests.swift          # WebSocket message tests
```

## Related Documentation

- **API Contract:** `docs/API_CONTRACT.md`
- **OpenAPI Spec:** `docs/openapi.yaml`
- **DTO Design:** Referenced in each DTO file header
- **Backend:** https://github.com/jukasdrj/bookstrack-backend

## Maintenance

- Review contract tests quarterly
- Update when API version changes
- Remove deprecated field tests after migration
- Add new tests for each API endpoint
