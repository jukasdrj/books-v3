# Phase 3: Response Envelope Unification Implementation Plan

**Created:** November 12, 2025
**Status:** Ready for Implementation
**Risk Level:** Low (feature flag enables instant rollback)

## Executive Summary

Unify response envelope format across all v1 endpoints using feature flag approach. Backend serves dual formats, iOS handles both gracefully. Zero-risk deployment with instant rollback capability.

## Problem Statement

Current v1 endpoints return discriminated union format:
```typescript
{ success: boolean, data: T, meta: ResponseMeta }
```

Target unified envelope format:
```typescript
{ data: T | null, metadata: ResponseMetadata, error?: ApiError }
```

Migration must maintain backward compatibility with existing iOS clients during gradual rollout.

## Approach

**Selected:** Feature Flag (Approach B)
**Rejected:**
- Big Bang (too risky, would break all iOS clients during deployment window)
- API Versioning (/v2/*) (unnecessary complexity, doubles maintenance burden)

### Why Feature Flags?

1. **Zero Risk:** Instant rollback via environment variable toggle (no deployment needed)
2. **Gradual Migration:** iOS clients adopt new format at their own pace
3. **Testing Flexibility:** Staging can test unified format while production uses legacy
4. **No Breaking Changes:** Old iOS clients continue working indefinitely

## Implementation Phases

### Phase 1: Backend Infrastructure (2-3 hours)

#### Task 1.1: Feature Flag Setup

Add to `wrangler.toml`:
```toml
[vars]
ENABLE_UNIFIED_ENVELOPE = "false"  # Default: legacy format

[env.staging]
name = "books-api-proxy-staging"

[env.staging.vars]
ENABLE_UNIFIED_ENVELOPE = "true"   # Test new format in staging
```

#### Task 1.2: Create Envelope Helpers

Create `src/utils/envelope-helpers.ts`:
```typescript
import type { ResponseEnvelope, ResponseMetadata, ApiError, SuccessResponse, ErrorResponse } from '../types/responses.js';

export function createUnifiedSuccessResponse<T>(
  data: T,
  meta: { timestamp: string; processingTime?: number; provider?: string; cached?: boolean }
): ResponseEnvelope<T> {
  return {
    data,
    metadata: {
      timestamp: meta.timestamp,
      processingTime: meta.processingTime,
      provider: meta.provider,
      cached: meta.cached
    },
    error: undefined
  };
}

export function createUnifiedErrorResponse(
  message: string,
  code?: string,
  details?: any
): ResponseEnvelope<null> {
  return {
    data: null,
    metadata: { timestamp: new Date().toISOString() },
    error: { message, code, details }
  };
}

// Adapter function: converts legacy response objects to unified envelope
export function adaptToUnifiedEnvelope<T>(
  legacyResponse: SuccessResponse<T> | ErrorResponse,
  useUnifiedEnvelope: boolean
): Response {
  if (!useUnifiedEnvelope) {
    return Response.json(legacyResponse);
  }

  if (legacyResponse.success) {
    return Response.json(createUnifiedSuccessResponse(
      legacyResponse.data,
      legacyResponse.meta
    ));
  } else {
    return Response.json(createUnifiedErrorResponse(
      legacyResponse.error.message,
      legacyResponse.error.code,
      legacyResponse.error.details
    ), { status: 400 });
  }
}
```

#### Task 1.3: Wire Up Flag to V1 Endpoints

Update 3 handlers with identical pattern:
- `src/handlers/v1/search-title.ts` (lines 60-70)
- `src/handlers/v1/search-isbn.ts` (lines 80-90)
- `src/handlers/v1/search-advanced.ts` (lines 95-105)

Pattern for each handler:
```typescript
import { adaptToUnifiedEnvelope } from '../../utils/envelope-helpers.js';

export async function handleSearchTitle(request, env, ctx) {
  // ... existing logic ...

  // At top of handler function
  const useUnifiedEnvelope = env.ENABLE_UNIFIED_ENVELOPE === 'true';

  // ... search logic ...

  // Replace final return statement
  const responseObject = createSuccessResponseObject(bookSearchResponse, meta);
  return adaptToUnifiedEnvelope(responseObject, useUnifiedEnvelope);
}
```

### Phase 2: Backend Testing (1 hour)

#### Task 2.1: Unit Tests

Create `tests/utils/envelope-helpers.test.ts`:
```typescript
import { describe, test, expect } from 'vitest';
import {
  createUnifiedSuccessResponse,
  createUnifiedErrorResponse,
  adaptToUnifiedEnvelope
} from '../../src/utils/envelope-helpers';

describe('Envelope Helpers', () => {
  test('createUnifiedSuccessResponse includes all metadata fields', () => {
    const data = { works: [], editions: [], authors: [] };
    const meta = {
      timestamp: '2025-11-12T00:00:00Z',
      processingTime: 150,
      provider: 'google',
      cached: true
    };

    const result = createUnifiedSuccessResponse(data, meta);

    expect(result.data).toBe(data);
    expect(result.metadata.timestamp).toBe(meta.timestamp);
    expect(result.metadata.processingTime).toBe(150);
    expect(result.metadata.provider).toBe('google');
    expect(result.metadata.cached).toBe(true);
    expect(result.error).toBeUndefined();
  });

  test('createUnifiedErrorResponse includes error details', () => {
    const result = createUnifiedErrorResponse('Not found', 'E_NOT_FOUND', { suggestion: 'Try different query' });

    expect(result.data).toBeNull();
    expect(result.error?.message).toBe('Not found');
    expect(result.error?.code).toBe('E_NOT_FOUND');
    expect(result.error?.details).toEqual({ suggestion: 'Try different query' });
  });

  test('adaptToUnifiedEnvelope preserves legacy format when flag OFF', async () => {
    const legacyResponse = {
      success: true,
      data: { works: [] },
      meta: { timestamp: '2025-11-12T00:00:00Z' }
    };

    const response = adaptToUnifiedEnvelope(legacyResponse, false);
    const body = await response.json();

    expect(body).toHaveProperty('success');
    expect(body.success).toBe(true);
    expect(body).toHaveProperty('data');
    expect(body).toHaveProperty('meta');
  });

  test('adaptToUnifiedEnvelope returns unified format when flag ON', async () => {
    const legacyResponse = {
      success: true,
      data: { works: [] },
      meta: { timestamp: '2025-11-12T00:00:00Z' }
    };

    const response = adaptToUnifiedEnvelope(legacyResponse, true);
    const body = await response.json();

    expect(body).toHaveProperty('data');
    expect(body).toHaveProperty('metadata');
    expect(body).toHaveProperty('error');
    expect(body.data.works).toBeDefined();
  });
});
```

#### Task 2.2: Integration Tests

Update existing handler tests to include dual-format validation:

**Example for `tests/handlers/v1/search-title.test.ts`:**
```typescript
describe('handleSearchTitle with feature flag', () => {
  test('returns unified envelope when flag enabled', async () => {
    const env = { ...mockEnv, ENABLE_UNIFIED_ENVELOPE: 'true' };
    const request = new Request('https://api.example.com/v1/search/title?q=test');
    const response = await handleSearchTitle(request, env, ctx);
    const body = await response.json();

    // Verify unified envelope structure
    expect(body).toHaveProperty('data');
    expect(body).toHaveProperty('metadata');
    expect(body).toHaveProperty('error');
    expect(body.data.works).toBeDefined();
    expect(body.metadata.timestamp).toBeDefined();
  });

  test('returns legacy envelope when flag disabled', async () => {
    const env = { ...mockEnv, ENABLE_UNIFIED_ENVELOPE: 'false' };
    const request = new Request('https://api.example.com/v1/search/title?q=test');
    const response = await handleSearchTitle(request, env, ctx);
    const body = await response.json();

    // Verify legacy discriminated union structure
    expect(body).toHaveProperty('success');
    expect(body).toHaveProperty('data');
    expect(body).toHaveProperty('meta');
    expect(body.success).toBe(true);
  });
});
```

Repeat pattern for `search-isbn.test.ts` and `search-advanced.test.ts`.

### Phase 3: iOS Implementation (4-5 hours)

#### Task 3.1: Response Models

Create `BooksTrackerPackage/Sources/BooksTrackerFeature/Models/API/ResponseEnvelope.swift`:
```swift
import Foundation

/// Unified response envelope (Phase 3 format)
public struct ResponseEnvelope<T: Codable>: Codable {
    public let data: T?
    public let metadata: ResponseMetadata
    public let error: ApiError?

    public init(data: T?, metadata: ResponseMetadata, error: ApiError?) {
        self.data = data
        self.metadata = metadata
        self.error = error
    }
}

/// Response metadata for unified envelope
public struct ResponseMetadata: Codable {
    public let timestamp: String
    public let traceId: String?
    public let processingTime: Int?
    public let provider: String?
    public let cached: Bool?

    public init(timestamp: String, traceId: String? = nil, processingTime: Int? = nil, provider: String? = nil, cached: Bool? = nil) {
        self.timestamp = timestamp
        self.traceId = traceId
        self.processingTime = processingTime
        self.provider = provider
        self.cached = cached
    }
}

/// API error structure
public struct ApiError: Codable {
    public let message: String
    public let code: String?
    public let details: [String: AnyCodable]?

    public init(message: String, code: String? = nil, details: [String: AnyCodable]? = nil) {
        self.message = message
        self.code = code
        self.details = details
    }
}

/// Type-erased Codable wrapper for heterogeneous dictionaries
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Unsupported type"))
        }
    }
}
```

#### Task 3.2: DTOMapper Updates

Update `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift`:
```swift
extension DTOMapper {
    /// Parse search response with dual-format support (Phase 3)
    /// Tries unified envelope first, falls back to legacy format
    public func parseSearchResponse(_ data: Data) throws -> BookSearchResponse {
        // Strategy: Try new envelope first, fallback to legacy

        // Attempt 1: Unified envelope format (Phase 3)
        if let envelope = try? decoder.decode(ResponseEnvelope<BookSearchResponse>.self, from: data) {
            guard let responseData = envelope.data else {
                let errorMessage = envelope.error?.message ?? "Unknown error"
                throw ParsingError.missingData(message: errorMessage)
            }
            return responseData
        }

        // Attempt 2: Legacy format (ApiResponse discriminated union)
        if let legacy = try? decoder.decode(ApiResponse<BookSearchResponse>.self, from: data) {
            switch legacy {
            case .success(let responseData):
                return responseData
            case .error(let error):
                throw ParsingError.apiError(message: error.message, code: error.code)
            }
        }

        // Both parsing attempts failed
        throw ParsingError.unknownFormat
    }
}

/// Parsing errors
public enum ParsingError: Error, LocalizedError {
    case missingData(message: String)
    case apiError(message: String, code: String?)
    case unknownFormat

    public var errorDescription: String? {
        switch self {
        case .missingData(let message):
            return "Missing data: \(message)"
        case .apiError(let message, let code):
            return "API error [\(code ?? "UNKNOWN")]: \(message)"
        case .unknownFormat:
            return "Unknown response format (not legacy or unified envelope)"
        }
    }
}
```

#### Task 3.3: Service Layer Updates

No changes needed:
- `SearchService.swift` - Already calls `DTOMapper.parseSearchResponse()`
- `EnrichmentService.swift` - Already uses canonical DTOs

#### Task 3.4: iOS Tests

Create `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/ResponseEnvelopeTests.swift`:
```swift
import Testing
import Foundation
@testable import BooksTrackerFeature

struct ResponseEnvelopeTests {
    let decoder = JSONDecoder()

    @Test func testUnifiedEnvelopeDecoding() throws {
        let json = """
        {
          "data": { "works": [], "editions": [], "authors": [] },
          "metadata": { "timestamp": "2025-11-12T00:00:00Z", "provider": "google" },
          "error": null
        }
        """

        let envelope = try decoder.decode(ResponseEnvelope<BookSearchResponse>.self, from: json.data(using: .utf8)!)

        #expect(envelope.data != nil)
        #expect(envelope.metadata.provider == "google")
        #expect(envelope.error == nil)
    }

    @Test func testUnifiedEnvelopeErrorDecoding() throws {
        let json = """
        {
          "data": null,
          "metadata": { "timestamp": "2025-11-12T00:00:00Z" },
          "error": { "message": "Not found", "code": "E_NOT_FOUND" }
        }
        """

        let envelope = try decoder.decode(ResponseEnvelope<BookSearchResponse>.self, from: json.data(using: .utf8)!)

        #expect(envelope.data == nil)
        #expect(envelope.error?.message == "Not found")
        #expect(envelope.error?.code == "E_NOT_FOUND")
    }

    @Test func testDTOMapperHandlesLegacyFormat() throws {
        let mapper = DTOMapper()

        let legacyJSON = """
        {
          "success": true,
          "data": { "works": [], "editions": [], "authors": [] },
          "meta": { "timestamp": "2025-11-12T00:00:00Z" }
        }
        """

        let result = try mapper.parseSearchResponse(legacyJSON.data(using: .utf8)!)
        #expect(result.works.isEmpty)
        #expect(result.editions.isEmpty)
        #expect(result.authors.isEmpty)
    }

    @Test func testDTOMapperHandlesUnifiedFormat() throws {
        let mapper = DTOMapper()

        let unifiedJSON = """
        {
          "data": { "works": [], "editions": [], "authors": [] },
          "metadata": { "timestamp": "2025-11-12T00:00:00Z" },
          "error": null
        }
        """

        let result = try mapper.parseSearchResponse(unifiedJSON.data(using: .utf8)!)
        #expect(result.works.isEmpty)
        #expect(result.editions.isEmpty)
        #expect(result.authors.isEmpty)
    }

    @Test func testDTOMapperThrowsOnUnknownFormat() throws {
        let mapper = DTOMapper()

        let invalidJSON = """
        { "unknown": "format" }
        """

        #expect(throws: ParsingError.self) {
            try mapper.parseSearchResponse(invalidJSON.data(using: .utf8)!)
        }
    }
}
```

Update `MockAPIClient.swift`:
```swift
class MockAPIClient: APIClient {
    enum ResponseFormat {
        case legacy
        case unified
    }

    var responseFormat: ResponseFormat = .legacy

    func searchByTitle(_ query: String) async throws -> BookSearchResponse {
        if responseFormat == .unified {
            return mockUnifiedEnvelopeResponse()
        } else {
            return mockLegacyResponse()
        }
    }

    private func mockUnifiedEnvelopeResponse() -> BookSearchResponse {
        // Return mock data in unified envelope format
        return BookSearchResponse(works: [], editions: [], authors: [])
    }

    private func mockLegacyResponse() -> BookSearchResponse {
        // Return mock data in legacy format
        return BookSearchResponse(works: [], editions: [], authors: [])
    }
}
```

### Phase 4: Staging Validation (1-2 hours)

#### Task 4.1: Deploy Backend to Staging

```bash
cd canon/cloudflare-workers/api-worker
wrangler deploy --env staging
# Verify ENABLE_UNIFIED_ENVELOPE=true in staging
```

#### Task 4.2: iOS Testing Against Staging

Update `APIConfiguration.swift`:
```swift
struct APIConfiguration {
    #if DEBUG
    static let baseURL = "https://staging.books-api-proxy.workers.dev"
    #else
    static let baseURL = "https://books-api-proxy.jukasdrj.workers.dev"
    #endif
}
```

Test scenarios:
1. Search by title - verify unified envelope parsing works
2. Search by ISBN - verify unified envelope parsing works
3. Advanced search - verify unified envelope parsing works
4. Error scenarios (404, 500) - verify error envelope parsing
5. Network failures - verify fallback behavior

#### Task 4.3: Backward Compatibility Test

Flip flag OFF in staging:
```bash
wrangler secret put ENABLE_UNIFIED_ENVELOPE --env staging
# Enter: false
```

Re-run all iOS tests - should still pass (legacy format fallback active).

### Phase 5: Production Deployment (1 hour + monitoring)

#### Deployment Sequence

```
Phase A: Backend Deploy (Day 0)
    |
    v
Monitor 24 hours (flag=false)
    |
    v
Phase B: iOS Release (Day 1)
    |
    v
Wait for 70%+ adoption (7-14 days)
    |
    v
Phase C: Feature Flag Flip (Day 8-15)
    |
    v
Monitor + Potential Rollback
```

**Phase A: Backend Deploy (Day 0)**
```bash
cd canon/cloudflare-workers/api-worker
wrangler deploy  # Production deploy with flag=false
```

Monitor for 24 hours:
- Error rate (should be unchanged)
- Response times (should be unchanged)
- Cache hit rates (should be unchanged)

**Phase B: iOS Release (Day 1)**
1. Submit iOS build to App Store Connect
2. Release to 100% of users
3. Monitor crash rate and error telemetry
4. Wait 7-14 days for 70%+ adoption (check App Store Connect analytics)

**Phase C: Feature Flag Flip (Day 8-15)**
```bash
wrangler secret put ENABLE_UNIFIED_ENVELOPE
# Enter: true
```

Monitor for 1 hour:
- iOS crash rate (should not increase)
- Backend error rate (should not increase)
- Search success rate (should remain 95%+)

If issues detected:
```bash
# INSTANT ROLLBACK (no deploy needed)
wrangler secret put ENABLE_UNIFIED_ENVELOPE
# Enter: false
```

## Dependencies Matrix

```
Backend Infrastructure
    |
    v
Backend Testing
    |
    v
iOS Implementation
    |
    v
iOS Testing
    |
    v
Staging Validation
    |
    v
Production Backend Deploy (flag OFF)
    |
    v
Production iOS Release
    |
    v
Wait for 70% adoption (7-14 days)
    |
    v
Production Flag Flip (flag ON)
    |
    v
Monitor + Potential Rollback
```

**Critical Dependency:** iOS MUST be deployed and adopted (70%+) BEFORE flipping the feature flag in production. Otherwise, old iOS clients will receive new envelope format and fail to parse responses.

## Risk Mitigation

1. **Feature Flag:** Enables instant rollback via environment variable (no deployment needed)
2. **Dual-Format iOS:** iOS handles both formats gracefully (no crash if flag flipped early)
3. **Staging Validation:** Catches parsing issues before production
4. **Gradual Rollout:** Prevents mass breakage
5. **Monitoring:** Real-time error tracking with immediate rollback capability

## Success Criteria

- [ ] Zero increase in iOS crash rate
- [ ] <1% increase in backend error rate
- [ ] All 3 v1 endpoints return unified envelope when flag=true
- [ ] Backward compatibility validated (flag=false works)
- [ ] Staging tests pass for both formats
- [ ] Production monitoring shows stable metrics

## Rollback Procedure

```bash
# Instant rollback (no deploy needed)
wrangler secret put ENABLE_UNIFIED_ENVELOPE
# Enter: false
```

Rollback triggers:
- iOS crash rate increases >2%
- Backend error rate increases >5%
- Search success rate drops below 90%
- Customer complaints increase significantly

## Documentation Updates

### Update CLAUDE.md

Add under "V1 Endpoints (Canonical)" section:

```markdown
**Response Envelope Unification (Phase 3 - Nov 2025):**
- Feature flag: `ENABLE_UNIFIED_ENVELOPE` (default: false, staging: true)
- Dual-format support: Legacy discriminated union + unified envelope
- iOS gracefully handles both formats (automatic fallback)
- Migration status: Backend ready, iOS deployed, flag flip pending adoption
```

### Create Feature Doc

File: `docs/features/UNIFIED_RESPONSE_ENVELOPE.md`

Sections:
- Overview (why unified envelope)
- Format comparison (legacy vs unified)
- Feature flag behavior
- iOS fallback strategy
- Rollback procedures
- Success metrics

## GitHub Issue Template

Create issue after plan approval:

**Title:** Phase 3: Response Envelope Unification (Feature Flag Migration)

**Labels:** enhancement, backend, ios, canonical-contracts

**Description:**
```markdown
## Goal
Unify response envelope format across all v1 endpoints using feature flag.

## Phases
- [ ] Backend infrastructure + tests (3h)
- [ ] iOS dual-format support + tests (5h)
- [ ] Staging validation (2h)
- [ ] Production deploy (1h)
- [ ] Monitor adoption (14 days)
- [ ] Flip flag to true

## Plan Document
`docs/plans/2025-11-12-phase3-response-envelope-unification.md`

## Risk Level
Low (instant rollback via environment variable)
```

## Post-Implementation Tasks

**After Flag Flip (Day 28+):**
1. Monitor for 7 days with flag=true
2. Create deprecation notice for legacy format
3. Plan legacy code removal (Phase 4 - future)
4. Update API documentation
5. Close GitHub issue

**Deprecation Timeline:**
- Day 28: Flag flipped to true (unified format active)
- Day 35: Monitor complete, legacy format officially deprecated
- Day 90: Plan legacy code removal (requires separate RFC)

## References

- Design Doc: `docs/plans/2025-10-29-canonical-data-contracts-design.md`
- Phase 1-2 Implementation: `docs/plans/2025-10-29-canonical-data-contracts-implementation.md`
- Response Types: `cloudflare-workers/api-worker/src/types/responses.ts`
- iOS DTOs: `BooksTrackerPackage/Sources/BooksTrackerFeature/Models/API/`

## Implementation Checklist

### Pre-Implementation Verification
- [ ] Verify wrangler.toml supports `[vars]` and `[env.staging.vars]`
- [ ] Confirm iOS DTOMapper exists with parseSearchResponse() method
- [ ] Ensure staging environment configured

### Day 1: Backend Foundation
- [ ] Create `src/utils/envelope-helpers.ts`
- [ ] Write unit tests (TDD approach)
- [ ] Migrate `search-title.ts` handler
- [ ] Add integration test with flag toggle
- [ ] Verify locally with `wrangler dev`

### Day 2: Backend Completion
- [ ] Migrate `search-isbn.ts` handler
- [ ] Migrate `search-advanced.ts` handler
- [ ] Add integration tests for both handlers
- [ ] Run full test suite
- [ ] Deploy to staging
- [ ] Verify all 3 endpoints in staging

### Day 3-4: iOS Implementation
- [ ] Create `ResponseEnvelope.swift`
- [ ] Add Codable tests
- [ ] Update `DTOMapper.swift` with dual-format parsing
- [ ] Add DTOMapper tests
- [ ] Update `MockAPIClient.swift`
- [ ] Run iOS test suite
- [ ] Build iOS app

### Day 5: Staging Validation
- [ ] Point iOS to staging
- [ ] Test all 3 search endpoints
- [ ] Test error scenarios
- [ ] Flip flag OFF, retest
- [ ] Verify backward compatibility

### Day 6: Production Deploy
- [ ] Deploy backend (flag=false)
- [ ] Monitor for 24 hours
- [ ] Submit iOS to App Store
- [ ] Create GitHub Issue for flag flip

### Day 21-28: Flag Flip
- [ ] Verify 70%+ iOS adoption
- [ ] Flip flag to true
- [ ] Monitor for 1 hour
- [ ] Rollback if issues detected

---

**This plan is ready for implementation.** All backend work, iOS work, and validation tasks are detailed with specific file paths, code examples, test strategies, and deployment procedures.
