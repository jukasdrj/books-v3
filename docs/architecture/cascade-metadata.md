# Cascade Metadata System - Technical Design

**Feature:** Cascade Metadata
**Sprint:** Sprint 2
**Priority:** HIGH ✨ (NEW - User-requested feature)
**Complexity:** LOW
**Created:** November 20, 2025

---

## Overview

The Cascade Metadata System automatically propagates author-level metadata to all works by that author in the user's library, reducing repetitive data entry and rewarding power users who curate large collections (100+ books).

**User Story:**
> "As a power user with many books by the same author, when I add cultural background information about an author once, I want it to automatically apply to all their books so I don't have to enter it repeatedly."

---

## Goals

### Primary Goals
1. **Efficiency:** Reduce metadata entry friction by 80%+ for multi-book authors
2. **Consistency:** Ensure consistent author metadata across all their works
3. **Transparency:** Make it clear which data is cascaded vs. manually entered
4. **Flexibility:** Allow work-level overrides when needed (e.g., co-authored books)

### Secondary Goals
5. **Gamification Integration:** Show cascade impact in completion percentage
6. **Progressive Profiling:** Make contextual prompts less repetitive
7. **Data Quality:** Increase metadata completion rate

---

## User Interview Insight

**Quote:**
> "If I add a fact about an author, that would apply to other works by the same author. I love badges. Data driven and want to see and build trends."

**Key Takeaways:**
- User explicitly requested this feature
- Motivation: Build trends, see data patterns
- Wants to feel rewarded for curation efforts
- 100+ books/year reading goal = power user who benefits most

---

## Data Model

### AuthorMetadata (SwiftData Model)

```swift
import SwiftData
import Foundation

@Model
final class AuthorMetadata {
    @Attribute(.unique) var authorId: String
    var culturalBackground: [String]
    var genderIdentity: String?
    var nationality: [String]
    var languages: [String]
    var marginalizedIdentities: [String]

    // Cascade tracking
    var cascadedToWorkIds: [String]
    var lastUpdated: Date
    var contributedBy: String // userId

    // Override tracking
    @Relationship(deleteRule: .cascade) var workOverrides: [WorkOverride]

    init(
        authorId: String,
        culturalBackground: [String] = [],
        genderIdentity: String? = nil,
        nationality: [String] = [],
        languages: [String] = [],
        marginalizedIdentities: [String] = [],
        contributedBy: String
    ) {
        self.authorId = authorId
        self.culturalBackground = culturalBackground
        self.genderIdentity = genderIdentity
        self.nationality = nationality
        self.languages = languages
        self.marginalizedIdentities = marginalizedIdentities
        self.cascadedToWorkIds = []
        self.lastUpdated = Date()
        self.contributedBy = contributedBy
    }
}

@Model
final class WorkOverride {
    var workId: String
    var field: String // e.g., "culturalBackground", "genderIdentity"
    var customValue: String
    var reason: String? // e.g., "Co-authored with different background"
    var createdAt: Date

    @Relationship(inverse: \AuthorMetadata.workOverrides) var authorMetadata: AuthorMetadata?

    init(workId: String, field: String, customValue: String, reason: String? = nil) {
        self.workId = workId
        self.field = field
        self.customValue = customValue
        self.reason = reason
        self.createdAt = Date()
    }
}
```

---

## Architecture

### Service Layer

```swift
import SwiftData

@MainActor
final class CascadeMetadataService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Author Metadata Management

    /// Updates author metadata and cascades to all works
    func updateAuthorMetadata(
        authorId: String,
        culturalBackground: [String]? = nil,
        genderIdentity: String? = nil,
        nationality: [String]? = nil,
        languages: [String]? = nil,
        marginalizedIdentities: [String]? = nil,
        userId: String
    ) async throws {
        // Fetch or create author metadata
        let metadata = try fetchOrCreateAuthorMetadata(authorId: authorId, userId: userId)

        // Update fields
        if let culturalBackground { metadata.culturalBackground = culturalBackground }
        if let genderIdentity { metadata.genderIdentity = genderIdentity }
        if let nationality { metadata.nationality = nationality }
        if let languages { metadata.languages = languages }
        if let marginalizedIdentities { metadata.marginalizedIdentities = marginalizedIdentities }

        metadata.lastUpdated = Date()

        // Cascade to all works by this author
        try await cascadeToWorks(authorId: authorId, metadata: metadata)

        try modelContext.save()
    }

    /// Cascades author metadata to all works
    private func cascadeToWorks(authorId: String, metadata: AuthorMetadata) async throws {
        // Fetch all works by this author
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { work in
                work.authors.contains { $0.id == authorId }
            }
        )

        let works = try modelContext.fetch(descriptor)

        // Update each work's enrichment data
        for work in works {
            // Skip if work has an override for this field
            let hasOverride = metadata.workOverrides.contains { $0.workId == work.id }

            if !hasOverride {
                // Update work's enrichment with cascaded data
                try await updateWorkEnrichment(work: work, metadata: metadata)

                // Track cascade
                if !metadata.cascadedToWorkIds.contains(work.id) {
                    metadata.cascadedToWorkIds.append(work.id)
                }
            }
        }
    }

    /// Updates work enrichment with cascaded author metadata
    private func updateWorkEnrichment(work: Work, metadata: AuthorMetadata) async throws {
        // Fetch or create enrichment for this work
        let enrichment = try fetchOrCreateEnrichment(workId: work.id)

        // Cascade author metadata
        enrichment.authorCulturalBackground = metadata.culturalBackground.joined(separator: ", ")
        enrichment.authorGenderIdentity = metadata.genderIdentity
        enrichment.isCascaded = true // Mark as auto-filled
        enrichment.lastEnriched = Date()
    }

    // MARK: - Override Management

    /// Creates a work-specific override for author metadata
    func createOverride(
        authorId: String,
        workId: String,
        field: String,
        customValue: String,
        reason: String?
    ) throws {
        let metadata = try fetchOrCreateAuthorMetadata(authorId: authorId, userId: "current-user")

        let override = WorkOverride(
            workId: workId,
            field: field,
            customValue: customValue,
            reason: reason
        )

        metadata.workOverrides.append(override)

        try modelContext.save()
    }

    /// Removes a work override, re-cascading author metadata
    func removeOverride(authorId: String, workId: String, field: String) async throws {
        let metadata = try fetchOrCreateAuthorMetadata(authorId: authorId, userId: "current-user")

        // Remove override
        metadata.workOverrides.removeAll { $0.workId == workId && $0.field == field }

        // Re-cascade to this work
        try await cascadeToWorks(authorId: authorId, metadata: metadata)

        try modelContext.save()
    }

    // MARK: - Helper Methods

    private func fetchOrCreateAuthorMetadata(authorId: String, userId: String) throws -> AuthorMetadata {
        let descriptor = FetchDescriptor<AuthorMetadata>(
            predicate: #Predicate { $0.authorId == authorId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        } else {
            let newMetadata = AuthorMetadata(authorId: authorId, contributedBy: userId)
            modelContext.insert(newMetadata)
            return newMetadata
        }
    }

    private func fetchOrCreateEnrichment(workId: String) throws -> BookEnrichment {
        // Implementation depends on BookEnrichment model
        // Placeholder for now
        fatalError("Implement BookEnrichment fetching")
    }
}
```

---

## UI/UX Design

### Progressive Profiling Integration

**Scenario:** User completes reading session, sees post-session prompt.

**OLD FLOW:**
```
📖 Great session! 30 minutes, 24 pages

Quick question: What's the author's cultural background?

[🌍 European] [🌏 Asian] [🌎 Latin American]
[🌍 African] [🌏 Middle Eastern] [Other] [Skip]
```

**NEW FLOW (with cascade):**
```
📖 Great session! 30 minutes, 24 pages

Quick question: What's Chimamanda Ngozi Adichie's cultural background?

[🌍 European] [🌏 Asian] [🌎 Latin American]
[🌍 African] [🌏 Middle Eastern] [Other] [Skip]

ℹ️ This will apply to all 5 books by this author in your library.
```

**After submission:**
```
✅ Cultural background saved!

📚 Updated 5 books:
- Americanah
- Half of a Yellow Sun
- Purple Hibiscus
- The Thing Around Your Neck
- Dear Ijeawele

🏆 +5 Curator Points
```

---

### Visual Indicators

**Book Detail View:**

```
┌─────────────────────────────────────┐
│  Americanah                         │
│  by Chimamanda Ngozi Adichie        │
│                                     │
│  📊 Enrichment: 80% Complete        │
│                                     │
│  ✅ Cultural Background: African    │
│     (Auto-filled from author)       │
│                                     │
│  ✅ Gender Identity: Female         │
│     (Auto-filled from author)       │
│                                     │
│  ⚪ Genres: [Tap to add]            │
│                                     │
│  [Override Author Data]             │
└─────────────────────────────────────┘
```

**Author Profile View:**

```
┌─────────────────────────────────────┐
│  Chimamanda Ngozi Adichie           │
│                                     │
│  ✅ Cultural Background: African    │
│  ✅ Gender Identity: Female         │
│  ✅ Nationality: Nigerian           │
│  ✅ Languages: English, Igbo        │
│                                     │
│  📚 Applied to 5 books              │
│  🏆 Curator Level: Gold             │
│                                     │
│  [View All Books by This Author]    │
└─────────────────────────────────────┘
```

---

## Implementation Plan

### Sprint 2 Tasks

**Week 1: Data Model & Service Layer**
1. ✅ Create `AuthorMetadata` SwiftData model
2. ✅ Create `WorkOverride` SwiftData model
3. ✅ Implement `CascadeMetadataService`
4. ✅ Write unit tests for cascade logic

**Week 2: UI Integration & Testing**
5. ✅ Update progressive profiling prompts with cascade messaging
6. ✅ Add visual indicators (auto-filled badges)
7. ✅ Implement override UI in book detail view
8. ✅ Add author profile view
9. ✅ Integration testing
10. ✅ Real device testing

---

## Edge Cases

### 1. Co-Authored Books
**Scenario:** Book has multiple authors with different backgrounds.

**Solution:**
- Cascade uses primary author's metadata by default
- User can create work-specific override
- Override reason field explains why (e.g., "Co-author with different background")

**Example:**
- "Good Omens" by Neil Gaiman & Terry Pratchett
- Primary author: Neil Gaiman (British)
- Override: "Co-authored with Terry Pratchett (British), set in England"

---

### 2. Author Changes Over Time
**Scenario:** Author's identity evolves (e.g., comes out as trans, changes nationality).

**Solution:**
- Allow user to update author metadata at any time
- Re-cascade to all works automatically
- Show "Updated X books" confirmation

**Example:**
- User updates author's gender identity
- All 12 books by that author get updated metadata
- Completion percentage increases

---

### 3. Conflicting Data from APIs
**Scenario:** API provides different author metadata than user-entered.

**Solution:**
- User-entered cascade metadata takes precedence
- API data used only when no user metadata exists
- Show "Verify this information" prompt if conflict detected

---

### 4. Partial Metadata
**Scenario:** User adds cultural background but not gender identity.

**Solution:**
- Cascade only populated fields
- Leave unpopulated fields empty (no cascade)
- Progress ring shows partial completion

---

## Performance Considerations

### Batch Updates
- Cascade operations run asynchronously
- Use batch updates for large author catalogs (100+ books)
- Show progress indicator for >10 books

### Caching
- Cache author metadata in memory
- Invalidate cache on update
- Reduce database queries

### Query Optimization
- Index `AuthorMetadata.authorId` for fast lookups
- Use batch fetch for work-author relationships
- Limit cascade to user's library (not all works)

---

## Gamification Integration

### Curator Points System

**Actions:**
- Add author metadata (first time): **+10 points**
- Update author metadata: **+2 points**
- Cascade triggers: **+1 point per book** (auto-awarded)

**Badges:**
- 🥉 **Bronze Curator:** 50 points (5 authors completed)
- 🥈 **Silver Curator:** 200 points (20 authors completed)
- 🥇 **Gold Curator:** 500 points (50 authors completed)
- 💎 **Diamond Curator:** 1000 points (100 authors completed)

**Visual Feedback:**
```
✅ Cultural background saved!

📚 Updated 5 books
🏆 +15 Curator Points (10 base + 5 cascade)

Progress: 🥉 Bronze Curator → 🥈 Silver Curator (180/200)
```

---

## Testing Strategy

### Unit Tests

```swift
@Test("Cascade metadata to all works by author")
func testCascadeMetadata() async throws {
    let service = CascadeMetadataService(modelContext: testContext)

    // Given: 3 works by same author
    let author = createTestAuthor(id: "author-1")
    let work1 = createTestWork(authorId: "author-1")
    let work2 = createTestWork(authorId: "author-1")
    let work3 = createTestWork(authorId: "author-1")

    // When: Update author metadata
    try await service.updateAuthorMetadata(
        authorId: "author-1",
        culturalBackground: ["African"],
        genderIdentity: "Female",
        userId: "user-1"
    )

    // Then: All 3 works should have cascaded metadata
    let enrichment1 = try fetchEnrichment(workId: work1.id)
    let enrichment2 = try fetchEnrichment(workId: work2.id)
    let enrichment3 = try fetchEnrichment(workId: work3.id)

    #expect(enrichment1.authorCulturalBackground == "African")
    #expect(enrichment2.authorCulturalBackground == "African")
    #expect(enrichment3.authorCulturalBackground == "African")
    #expect(enrichment1.isCascaded == true)
}

@Test("Override prevents cascade for specific work")
func testWorkOverride() async throws {
    let service = CascadeMetadataService(modelContext: testContext)

    // Given: Author metadata exists
    try await service.updateAuthorMetadata(
        authorId: "author-1",
        culturalBackground: ["British"],
        userId: "user-1"
    )

    // When: Create override for work-1
    try service.createOverride(
        authorId: "author-1",
        workId: "work-1",
        field: "culturalBackground",
        customValue: "American",
        reason: "Co-author with different background"
    )

    // Then: work-1 has override, work-2 has cascaded data
    let enrichment1 = try fetchEnrichment(workId: "work-1")
    let enrichment2 = try fetchEnrichment(workId: "work-2")

    #expect(enrichment1.authorCulturalBackground == "American")
    #expect(enrichment2.authorCulturalBackground == "British")
}
```

---

## Migration Strategy

### Backward Compatibility
- Existing works without author metadata remain unchanged
- No migration needed for v1 data
- Progressive enhancement only

### Rollout Plan
1. **Sprint 2, Week 1:** Data model + service layer
2. **Sprint 2, Week 2:** UI integration + testing
3. **Sprint 3:** User onboarding (explain cascade feature)
4. **Sprint 4:** Analytics (track cascade usage)

---

## Success Metrics

### Quantitative
- [ ] 80%+ reduction in repeated author metadata entry
- [ ] 50%+ increase in metadata completion rate
- [ ] 70%+ of users with 10+ books use cascade feature
- [ ] <100ms cascade time for 10 books

### Qualitative
- [ ] User feedback: "Saves so much time"
- [ ] No confusion about cascaded vs. manual data
- [ ] Override feature used <5% of the time (most cascades are correct)

---

## Future Enhancements (Post-Sprint 2)

### 1. Bulk Override
- Apply override to multiple works at once
- Use case: Anthology with multiple authors

### 2. Author Profile Suggestions
- AI suggests author metadata based on existing works
- User reviews and approves suggestions

### 3. Community Cascade
- Anonymized author metadata from community
- Federated learning for author profiles
- Opt-in, privacy-preserving

### 4. Smart Cascade Rules
- "Always use primary author for co-authored works"
- "Never cascade nationality to translated works"
- User-defined cascade preferences

---

## Open Questions

1. **Should we cascade to works added in the future?**
   - **Answer:** Yes, any new work by an author with metadata should auto-cascade.

2. **How do we handle anonymously authored books?**
   - **Answer:** No cascade. Leave author fields empty.

3. **Should cascade trigger re-calculation of diversity stats?**
   - **Answer:** Yes, but debounce by 5 seconds to batch updates.

4. **Can users see cascade history (audit log)?**
   - **Answer:** v2.1 feature. Not critical for MVP.

---

## Dependencies

### Requires (Sprint 1)
- `EnhancedDiversityStats` model
- `BookEnrichment` model
- Progressive profiling UI

### Enables (Sprint 3+)
- Ratings system (cascade author popularity)
- AI recommendations (richer author metadata)
- Community contributions (shared author profiles)

---

**Document Owner:** Technical Team
**Last Updated:** November 20, 2025
**Status:** Ready for Sprint 2 Implementation
**Estimated Effort:** 1 sprint (2 weeks)
