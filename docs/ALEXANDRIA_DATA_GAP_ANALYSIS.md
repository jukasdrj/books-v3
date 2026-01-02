# Alexandria → bendv3 Data Gap Analysis

**Date:** January 2, 2026
**Author:** Claude Code
**Status:** Investigation Complete

## Executive Summary

This document analyzes the data flow from Alexandria (book metadata service) through bendv3 (API gateway) to the iOS frontend. The investigation reveals that **author demographic data is not currently exposed** through the V3 API, despite being critical for the Diversity Insights feature.

## System Architecture

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  Alexandria │ ───► │   bendv3    │ ───► │  iOS App    │
│  (metadata) │      │ (API gate)  │      │ (frontend)  │
└─────────────┘      └─────────────┘      └─────────────┘
     ???                  V3 API           V3Book DTO
```

## Data Currently Provided by V3 API

### What bendv3 Exposes

| Data Field | Provided | Notes |
|------------|----------|-------|
| `isbn` | ✅ Yes | 13-digit ISBN |
| `isbn10` | ✅ Yes | 10-digit ISBN (optional) |
| `title` | ✅ Yes | Book title |
| `subtitle` | ✅ Yes | Optional |
| `authors` | ⚠️ Partial | **Strings only** - no author objects |
| `publisher` | ✅ Yes | Optional |
| `publishedDate` | ✅ Yes | Optional |
| `description` | ✅ Yes | Book synopsis |
| `pageCount` | ✅ Yes | Optional |
| `categories` | ✅ Yes | Genres/subjects |
| `language` | ✅ Yes | ISO language code |
| `coverUrl` | ✅ Yes | High-res cover |
| `thumbnailUrl` | ✅ Yes | Low-res thumbnail |
| `workKey` | ✅ Yes | Open Library work ID |
| `editionKey` | ✅ Yes | Open Library edition ID |
| `provider` | ✅ Yes | Data source tag |
| `quality` | ✅ Yes | 0-100 quality score |

**Source:** `BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/V3/V3Book.swift`

### What bendv3 Does NOT Expose

| Data Field | Needed For | Current Workaround |
|------------|------------|-------------------|
| Author gender | Diversity Insights | User manual entry |
| Author cultural background | Diversity Insights | User manual entry |
| Author nationality | Diversity Insights | User manual entry |
| Author biography | Author profiles | Not available |
| Author birth year | Author profiles | User manual entry |
| Author death year | Author profiles | User manual entry |
| Author photo URL | Author profiles | Not available |

## Evidence from Codebase

### V3ToV2Mapper.swift (Lines 100-116)

When mapping V3 API responses to internal models, author demographic fields are hardcoded to empty/unknown values:

```swift
AuthorDTO(
    name: authorName,
    gender: .unknown,        // V3 doesn't provide gender
    culturalRegion: nil,     // NOT PROVIDED BY API
    nationality: nil,        // NOT PROVIDED BY API
    birthYear: nil,          // NOT PROVIDED BY API
    deathYear: nil,          // NOT PROVIDED BY API
    ...
)
```

### Author.swift Model Requirements

The iOS app's `Author` SwiftData model expects:

```swift
@Model
final class Author {
    var name: String
    var gender: AuthorGender           // female, male, non-binary, other, unknown
    var culturalRegion: CulturalRegion? // Africa, Asia, Europe, etc.
    var nationality: String?
    var birthYear: Int?
    var deathYear: Int?
}
```

**Source:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Author.swift:26-122`

## Impact on Features

### Diversity Insights (v3.1.0)

The Diversity Insights feature calculates 5 metrics:

| Metric | Data Source | API Provides? |
|--------|-------------|---------------|
| Cultural representation | `author.culturalRegion` | ❌ No |
| Gender representation | `author.gender` | ❌ No |
| Translation diversity | `book.originalLanguage` | ✅ Yes |
| Own-voices | `book.isOwnVoices` | ❌ No |
| Accessibility | `book.accessibilityTags` | ❌ No |

**Result:** 60% of diversity metrics require user-entered data, making the feature labor-intensive.

**Source:** `docs/prd/Diversity-Insights-PRD.md`

### Current User Workaround

1. **Progressive Profiling Sheet** - Prompts users to manually enter author demographics
2. **Cascade Metadata System** - Once entered, author data propagates to all their books

**Sources:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/ProgressiveProfilingSheet.swift`
- `BooksTrackerPackage/Services/CascadeMetadataService.swift`

## Open Questions for bendv3/Alexandria Team

### 1. Does Alexandria Have This Data?

Does the Alexandria PostgreSQL database contain author demographic information that simply isn't exposed via the V3 API?

If yes, the API could be extended to return rich author objects:

```json
{
  "authors": [
    {
      "id": "OL123456A",
      "name": "Toni Morrison",
      "biography": "Chloe Anthony Wofford Morrison was an American novelist...",
      "gender": "female",
      "culturalRegion": "North America",
      "nationality": "American",
      "birthYear": 1931,
      "deathYear": 2019,
      "photoUrl": "https://cdn.alexandria.oooefam.net/authors/OL123456A.jpg"
    }
  ]
}
```

### 2. If Not, What's the Enrichment Plan?

Potential data sources for author demographics:
- **Open Library** - Has author records with some biographical data
- **Wikidata** - Structured data including gender, nationality, birth/death
- **ISNI** - International Standard Name Identifier database
- **VIAF** - Virtual International Authority File

### 3. API Contract Extension

If Alexandria adds author demographics, the V3 API contract would need:

```yaml
# Proposed V3Book schema extension
V3Author:
  type: object
  properties:
    id:
      type: string
      description: Unique author identifier (e.g., Open Library ID)
    name:
      type: string
    biography:
      type: string
      nullable: true
    gender:
      type: string
      enum: [female, male, non-binary, other, unknown]
      nullable: true
    culturalRegion:
      type: string
      nullable: true
    nationality:
      type: string
      nullable: true
    birthYear:
      type: integer
      nullable: true
    deathYear:
      type: integer
      nullable: true
    photoUrl:
      type: string
      format: uri
      nullable: true
```

## Recommendations

### Short-term (iOS App)

1. **Continue using Progressive Profiling** - Best available option until API support
2. **Improve Cascade Metadata** - Better author name matching/deduplication
3. **Add data quality indicators** - Show users which books need author data

### Medium-term (bendv3/Alexandria)

1. **Audit Alexandria database** - Determine what author data exists
2. **Design V3Author schema** - If data exists, plan API extension
3. **Prioritize high-value authors** - Start with frequently-appearing authors

### Long-term (Ecosystem)

1. **Integrate external sources** - Wikidata, Open Library author records
2. **Community contributions** - Allow users to contribute author data back
3. **ML classification** - Infer demographics from names/biographies (with caveats)

## Related Files

| File | Purpose |
|------|---------|
| `DTOs/V3/V3Book.swift` | V3 API book model |
| `Services/V3ToV2Mapper.swift` | API response mapping |
| `Models/Author.swift` | SwiftData author model |
| `Models/AuthorMetadata.swift` | User-entered author data |
| `Services/CascadeMetadataService.swift` | Metadata propagation |
| `Views/ProgressiveProfilingSheet.swift` | Manual data entry UI |
| `docs/prd/Diversity-Insights-PRD.md` | Feature requirements |

## Conclusion

The V3 API provides comprehensive **book** metadata but lacks **author** demographic data critical for diversity features. The iOS app works around this with user-entered data and cascading, but this creates friction and limits feature adoption.

**Next step:** Clarify with bendv3/Alexandria team whether this data exists in Alexandria and can be exposed, or if new data sources need to be integrated.
