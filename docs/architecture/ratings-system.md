# Ratings System - Technical Design

**Feature:** Ratings System (Rotten Tomatoes Model)
**Sprint:** Sprint 3
**Priority:** CRITICAL (Part of Book Enrichment System)
**Complexity:** MEDIUM
**Created:** November 20, 2025

---

## Overview

The Ratings System allows users to rate books on a 1-5 star scale and compare their ratings against critics' aggregated scores (Goodreads) and the BooksTrack community average. Inspired by Rotten Tomatoes' "Tomatometer vs. Audience Score" model.

**User Story:**
> "As a reader who quit Goodreads because it asked too much, I want a simple rating system where I can see how my taste compares to critics and the community, without overwhelming forms or social pressure."

---

## Goals

### Primary Goals
1. **Simplicity:** One-tap rating (1-5 stars), no review required
2. **Comparison:** See user rating vs. critics vs. community
3. **Privacy:** Ratings are local-first, optional community sharing
4. **Integration:** Ratings feed AI recommendation engine

### Secondary Goals
5. **Insights:** Show rating patterns (harsh critic, generous reader, etc.)
6. **Gamification:** Reward rating consistency and completion
7. **Discovery:** "Books you rated 5 stars but critics panned"

---

## User Interview Insight

**Quote:**
> "For curation and suggestions, auto-fill as much as possible. I'd love a Rotten Tomatoes type system where I see my rating vs critics vs others."

**Key Takeaways:**
- Wants comparison, not just personal rating
- Quit Goodreads due to complexity → keep it simple
- Ratings feed recommendations (AI)
- No interest in writing reviews (just stars)

---

## Data Model

### UserRating (SwiftData Model)

```swift
import SwiftData
import Foundation

@Model
final class UserRating {
    @Attribute(.unique) var id: String
    var workId: String
    var userId: String
    var rating: Double // 1.0 - 5.0 (allow half-stars)
    var ratedAt: Date
    var lastUpdated: Date

    // Optional context
    var ratingContext: String? // e.g., "Loved the characters but slow pacing"
    var isRecommended: Bool // Binary recommendation (Netflix-style)

    // Privacy controls
    var shareWithCommunity: Bool // Opt-in for community average
    var isPrivate: Bool // Hide from reading circles

    // Gamification
    var contributesToStreak: Bool

    @Relationship(inverse: \Work.userRating) var work: Work?

    init(
        id: String = UUID().uuidString,
        workId: String,
        userId: String,
        rating: Double,
        isRecommended: Bool = false,
        shareWithCommunity: Bool = true
    ) {
        self.id = id
        self.workId = workId
        self.userId = userId
        self.rating = rating
        self.ratedAt = Date()
        self.lastUpdated = Date()
        self.isRecommended = isRecommended
        self.shareWithCommunity = shareWithCommunity
        self.isPrivate = false
        self.contributesToStreak = true
    }
}
```

### RatingComparison (Computed, Not Stored)

```swift
struct RatingComparison {
    let userRating: Double // 1.0-5.0
    let criticsRating: Double? // Goodreads average (fetched from API)
    let communityRating: Double? // BooksTrack community average
    let totalUserRatings: Int // Number of user ratings
    let totalCriticReviews: Int // Number of critic reviews

    // Computed insights
    var userVsCritics: RatingDifference {
        guard let critics = criticsRating else { return .notAvailable }
        let diff = userRating - critics
        if diff > 1.5 { return .muchHigher }
        if diff > 0.5 { return .higher }
        if abs(diff) <= 0.5 { return .similar }
        if diff < -0.5 { return .lower }
        return .muchLower
    }

    var userVsCommunity: RatingDifference {
        guard let community = communityRating else { return .notAvailable }
        let diff = userRating - community
        if diff > 1.5 { return .muchHigher }
        if diff > 0.5 { return .higher }
        if abs(diff) <= 0.5 { return .similar }
        if diff < -0.5 { return .lower }
        return .muchLower
    }
}

enum RatingDifference {
    case muchHigher, higher, similar, lower, muchLower, notAvailable

    var description: String {
        switch self {
        case .muchHigher: return "You loved it way more!"
        case .higher: return "You liked it more"
        case .similar: return "You agree"
        case .lower: return "You liked it less"
        case .muchLower: return "You disagree strongly"
        case .notAvailable: return "No comparison available"
        }
    }

    var emoji: String {
        switch self {
        case .muchHigher: return "🔥"
        case .higher: return "👍"
        case .similar: return "✅"
        case .lower: return "👎"
        case .muchLower: return "❌"
        case .notAvailable: return "🤷"
        }
    }
}
```

---

## Architecture

### Service Layer

```swift
import SwiftData

@MainActor
final class RatingsService {
    private let modelContext: ModelContext
    private let apiClient: BookAPIClient

    init(modelContext: ModelContext, apiClient: BookAPIClient) {
        self.modelContext = modelContext
        self.apiClient = apiClient
    }

    // MARK: - User Ratings

    /// Creates or updates a user rating
    func rateWork(
        workId: String,
        userId: String,
        rating: Double,
        isRecommended: Bool = false,
        shareWithCommunity: Bool = true
    ) async throws {
        // Validate rating
        guard (1.0...5.0).contains(rating) else {
            throw RatingsError.invalidRating
        }

        // Fetch or create rating
        let userRating = try fetchOrCreateRating(workId: workId, userId: userId)

        // Update rating
        userRating.rating = rating
        userRating.isRecommended = isRecommended
        userRating.shareWithCommunity = shareWithCommunity
        userRating.lastUpdated = Date()

        try modelContext.save()

        // Update AI preference profile
        try await updatePreferenceProfile(workId: workId, rating: rating)

        // Optionally share with community (federated learning)
        if shareWithCommunity {
            try await shareCommunityRating(workId: workId, rating: rating)
        }
    }

    /// Fetches rating comparison (user vs. critics vs. community)
    func fetchRatingComparison(workId: String, userId: String) async throws -> RatingComparison {
        // Fetch user rating
        let userRating = try fetchOrCreateRating(workId: workId, userId: userId)

        // Fetch critics rating from Goodreads API
        let criticsRating = try await apiClient.fetchGoodreadsRating(workId: workId)

        // Fetch community rating (anonymized aggregate)
        let communityRating = try await fetchCommunityRating(workId: workId)

        return RatingComparison(
            userRating: userRating.rating,
            criticsRating: criticsRating?.averageRating,
            communityRating: communityRating?.average,
            totalUserRatings: communityRating?.count ?? 0,
            totalCriticReviews: criticsRating?.ratingsCount ?? 0
        )
    }

    // MARK: - Community Ratings (Privacy-Safe)

    /// Fetches anonymized community rating for a work
    private func fetchCommunityRating(workId: String) async throws -> CommunityRating? {
        // Federated learning approach:
        // 1. Request aggregate stats from server (no individual ratings)
        // 2. Server returns: { average: 4.2, count: 127 } (no user IDs)
        // 3. Local ratings NOT sent to server unless user opts in

        // Placeholder for federated learning endpoint
        // return try await apiClient.fetchCommunityRating(workId: workId)
        return nil // MVP: No community ratings yet
    }

    /// Shares user rating with community (opt-in, anonymized)
    private func shareCommunityRating(workId: String, rating: Double) async throws {
        // Federated learning approach:
        // 1. User's rating contributes to local model
        // 2. Model weights (not raw rating) shared with server
        // 3. Server aggregates model weights from all users
        // 4. Updated community model returned to users

        // Placeholder for federated learning
        // try await apiClient.shareFederatedRating(workId: workId, modelWeights: weights)
    }

    // MARK: - Rating Insights

    /// Analyzes user's rating patterns
    func analyzeRatingPatterns(userId: String) async throws -> RatingPatternInsights {
        let descriptor = FetchDescriptor<UserRating>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.ratedAt, order: .reverse)]
        )

        let ratings = try modelContext.fetch(descriptor)

        let avgRating = ratings.map(\.rating).reduce(0, +) / Double(ratings.count)
        let stdDev = calculateStandardDeviation(ratings.map(\.rating))

        // Classify rating style
        let style: RatingStyle
        if avgRating >= 4.5 {
            style = .generous
        } else if avgRating <= 2.5 {
            style = .harsh
        } else if stdDev < 0.5 {
            style = .consistent
        } else if stdDev > 1.5 {
            style = .varied
        } else {
            style = .balanced
        }

        return RatingPatternInsights(
            totalRatings: ratings.count,
            averageRating: avgRating,
            standardDeviation: stdDev,
            ratingStyle: style,
            mostCommonRating: findMode(ratings.map { Int($0.rating) }),
            ratingDistribution: calculateDistribution(ratings)
        )
    }

    // MARK: - Helper Methods

    private func fetchOrCreateRating(workId: String, userId: String) throws -> UserRating {
        let descriptor = FetchDescriptor<UserRating>(
            predicate: #Predicate { $0.workId == workId && $0.userId == userId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        } else {
            let newRating = UserRating(workId: workId, userId: userId, rating: 0)
            modelContext.insert(newRating)
            return newRating
        }
    }

    private func updatePreferenceProfile(workId: String, rating: Double) async throws {
        // Update AI preference profile with new rating
        // Higher ratings increase affinity for similar books
        // Implemented in Sprint 5 (AI recommendations)
    }

    private func calculateStandardDeviation(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }

    private func findMode(_ values: [Int]) -> Int {
        let counts = values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? 0
    }

    private func calculateDistribution(_ ratings: [UserRating]) -> [Int: Int] {
        ratings.reduce(into: [:]) { counts, rating in
            let star = Int(rating.rating)
            counts[star, default: 0] += 1
        }
    }
}

// MARK: - Supporting Types

struct RatingPatternInsights {
    let totalRatings: Int
    let averageRating: Double
    let standardDeviation: Double
    let ratingStyle: RatingStyle
    let mostCommonRating: Int
    let ratingDistribution: [Int: Int] // Star rating -> count
}

enum RatingStyle {
    case generous, harsh, consistent, varied, balanced

    var description: String {
        switch self {
        case .generous: return "Generous Rater"
        case .harsh: return "Harsh Critic"
        case .consistent: return "Consistent Rater"
        case .varied: return "Varied Taste"
        case .balanced: return "Balanced Rater"
        }
    }

    var emoji: String {
        switch self {
        case .generous: return "⭐⭐⭐⭐⭐"
        case .harsh: return "⭐⭐"
        case .consistent: return "📊"
        case .varied: return "🎲"
        case .balanced: return "⚖️"
        }
    }
}

enum RatingsError: Error {
    case invalidRating
    case notFound
}

struct CommunityRating {
    let average: Double
    let count: Int
}
```

---

## UI/UX Design

### Book Detail View - Rating Widget

```
┌─────────────────────────────────────┐
│  Americanah                         │
│  by Chimamanda Ngozi Adichie        │
│                                     │
│  📊 Your Rating                     │
│  ⭐⭐⭐⭐⭐ 5.0                       │
│  [Tap to change]                    │
│                                     │
│  📈 Comparison                      │
│  You:       ⭐⭐⭐⭐⭐ 5.0           │
│  Critics:   ⭐⭐⭐⭐ 4.2 (12K)       │
│  Community: ⭐⭐⭐⭐⭐ 4.8 (327)     │
│                                     │
│  🔥 You loved it way more!          │
│                                     │
│  [View Rating Insights]             │
└─────────────────────────────────────┘
```

### Rating Sheet (SwiftUI)

```swift
struct RatingSheet: View {
    @Binding var rating: Double
    @Binding var isRecommended: Bool
    let onSave: (Double, Bool) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Rate this book")
                .font(.title2)
                .fontWeight(.bold)

            // Star rating
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= Int(rating) ? "star.fill" : "star")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                        .onTapGesture {
                            rating = Double(star)
                        }
                }
            }

            Text("\(rating, specifier: "%.1f") stars")
                .font(.headline)
                .foregroundColor(.secondary)

            // Optional: Recommend toggle
            Toggle("Would you recommend this book?", isOn: $isRecommended)
                .padding(.horizontal)

            // Privacy note
            Text("Your rating will contribute to BooksTrack community averages (anonymously).")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Save button
            Button(action: { onSave(rating, isRecommended) }) {
                Text("Save Rating")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}
```

### Rating Insights View

```
┌─────────────────────────────────────┐
│  Your Rating Style                  │
│                                     │
│  ⭐⭐⭐⭐⭐ Generous Rater            │
│  You rate books 4.7/5 on average    │
│                                     │
│  📊 Distribution                    │
│  5 stars: ████████████ 54%         │
│  4 stars: ███████ 32%               │
│  3 stars: ██ 10%                    │
│  2 stars: █ 3%                      │
│  1 star:  █ 1%                      │
│                                     │
│  🔍 Insights                        │
│  • You're more generous than critics│
│  • You agree with community 78%     │
│  • Your favorite genre: Fiction     │
│                                     │
│  📚 Books You Loved (Critics Didn't)│
│  1. Book Title (You: 5, Critics: 3.2)│
│  2. Another Book (You: 5, Critics: 3.5)│
│                                     │
│  [View All Ratings]                 │
└─────────────────────────────────────┘
```

---

## Implementation Plan

### Sprint 3 Tasks

**Week 1: Data Model & Service Layer**
1. ✅ Create `UserRating` SwiftData model
2. ✅ Create `RatingsService` with CRUD operations
3. ✅ Implement rating comparison logic
4. ✅ Write unit tests for ratings service

**Week 2: UI Integration & Insights**
5. ✅ Implement `RatingSheet` UI
6. ✅ Add rating widget to book detail view
7. ✅ Implement rating insights view
8. ✅ Add rating patterns analysis
9. ✅ Integration testing
10. ✅ Real device testing

---

## API Integration

### Goodreads Rating Fetch

```swift
struct GoodreadsRating: Codable {
    let averageRating: Double
    let ratingsCount: Int
    let reviewsCount: Int
}

extension BookAPIClient {
    func fetchGoodreadsRating(workId: String) async throws -> GoodreadsRating? {
        // Use existing API orchestration
        // Goodreads rating already available in Work model from v1
        // Just return it directly

        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.id == workId }
        )

        guard let work = try modelContext.fetch(descriptor).first else {
            throw RatingsError.notFound
        }

        return GoodreadsRating(
            averageRating: work.averageRating ?? 0,
            ratingsCount: work.ratingsCount ?? 0,
            reviewsCount: work.reviewsCount ?? 0
        )
    }
}
```

**No additional API calls needed** - Goodreads data already fetched in v1!

---

## Privacy & Security

### Local-First Approach
- User ratings stored locally in SwiftData
- No cloud sync by default (user's device only)
- Optional: iCloud sync (end-to-end encrypted)

### Community Ratings (Federated Learning)
- **Opt-in only** - User explicitly chooses to contribute
- **Anonymized aggregation** - Server never sees individual ratings
- **Model weights only** - Local AI model shares learnings, not data
- **Revocable consent** - User can stop sharing at any time

### Implementation (Sprint 7 - Federated Learning)
```swift
// Placeholder for federated learning
func shareFederatedRating(workId: String, rating: Double) async throws {
    // 1. Update local preference model with new rating
    // 2. Compute model weight delta
    // 3. Send delta to server (no raw rating)
    // 4. Server aggregates deltas from all users
    // 5. Server returns updated community model
}
```

---

## Gamification Integration

### Rating Streaks

**Actions:**
- Rate a book: **+5 points**
- Rate 7 days in a row: **+50 points** (Weekly Streak)
- Rate 30 days in a row: **+200 points** (Monthly Streak)

**Badges:**
- 🌟 **Critic Apprentice:** Rate 10 books
- 🌟🌟 **Seasoned Critic:** Rate 50 books
- 🌟🌟🌟 **Master Critic:** Rate 100 books
- 🏆 **Legendary Critic:** Rate 500 books

### Comparison Achievements

- 🔥 **Contrarian:** Disagree with critics 10 times (>2 star difference)
- ✅ **Mainstream:** Agree with critics 50 times (<0.5 star difference)
- 🎯 **Taste Maker:** Your ratings match community 90%+
- 🦄 **Unique Taste:** Your ratings differ from community 70%+

---

## Testing Strategy

### Unit Tests

```swift
@Test("Create user rating")
func testCreateRating() async throws {
    let service = RatingsService(modelContext: testContext, apiClient: mockAPI)

    try await service.rateWork(
        workId: "work-1",
        userId: "user-1",
        rating: 4.5,
        isRecommended: true
    )

    let rating = try fetchRating(workId: "work-1", userId: "user-1")
    #expect(rating.rating == 4.5)
    #expect(rating.isRecommended == true)
}

@Test("Fetch rating comparison")
func testRatingComparison() async throws {
    let service = RatingsService(modelContext: testContext, apiClient: mockAPI)

    // Given: User rated 5 stars, critics rated 3.5
    try await service.rateWork(workId: "work-1", userId: "user-1", rating: 5.0)
    mockAPI.mockGoodreadsRating = GoodreadsRating(averageRating: 3.5, ratingsCount: 1200, reviewsCount: 300)

    // When: Fetch comparison
    let comparison = try await service.fetchRatingComparison(workId: "work-1", userId: "user-1")

    // Then: User rating is much higher than critics
    #expect(comparison.userRating == 5.0)
    #expect(comparison.criticsRating == 3.5)
    #expect(comparison.userVsCritics == .muchHigher)
}

@Test("Analyze rating patterns")
func testRatingPatterns() async throws {
    let service = RatingsService(modelContext: testContext, apiClient: mockAPI)

    // Given: User has rated 10 books, all 5 stars
    for i in 1...10 {
        try await service.rateWork(workId: "work-\(i)", userId: "user-1", rating: 5.0)
    }

    // When: Analyze patterns
    let insights = try await service.analyzeRatingPatterns(userId: "user-1")

    // Then: User is a generous rater
    #expect(insights.averageRating == 5.0)
    #expect(insights.ratingStyle == .generous)
    #expect(insights.totalRatings == 10)
}
```

---

## Migration Strategy

### Backward Compatibility
- No v1 ratings to migrate (new feature)
- No breaking changes to existing models
- Progressive enhancement only

### Rollout Plan
1. **Sprint 3, Week 1:** Data model + service layer
2. **Sprint 3, Week 2:** UI integration + testing
3. **Sprint 4:** User onboarding (explain rating comparison)
4. **Sprint 7:** Federated learning integration (optional)

---

## Success Metrics

### Quantitative
- [ ] 70%+ of users rate at least 10 books
- [ ] 50%+ of users check rating comparison
- [ ] 30%+ opt-in to community rating sharing
- [ ] <200ms to fetch and display rating comparison

### Qualitative
- [ ] User feedback: "Simple and clear"
- [ ] No confusion about user vs. critics vs. community
- [ ] Rotten Tomatoes comparison is intuitive

---

## Future Enhancements (Post-Sprint 3)

### 1. Review Text (Optional)
- Add optional review field (like Letterboxd)
- Private by default
- Share with reading circles (opt-in)

### 2. Half-Star Ratings
- Support 0.5 increments (e.g., 4.5 stars)
- More granular rating scale
- Better matches Goodreads precision

### 3. Rating History
- Track rating changes over time
- "You rated this 4 stars in 2023, 5 stars now"
- Show rating evolution chart

### 4. Import Goodreads Ratings
- One-time import from Goodreads export
- Map Goodreads IDs to BooksTrack works
- Preserve rating history

---

## Dependencies

### Requires (Sprint 1-2)
- `Work` model (already exists in v1)
- `UserPreferenceProfile` model (Sprint 5)

### Enables (Sprint 5+)
- AI recommendations (ratings as input)
- Reading pattern insights (preference analysis)
- Community insights (aggregated ratings)

---

**Document Owner:** Technical Team
**Last Updated:** November 20, 2025
**Status:** Ready for Sprint 3 Implementation
**Estimated Effort:** 1 sprint (2 weeks)
