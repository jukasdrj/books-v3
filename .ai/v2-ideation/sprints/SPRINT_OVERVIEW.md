# BooksTracker v2 - Sprint Planning Overview

**Planning Date:** November 20, 2025
**Last Updated:** November 20, 2025 (Revised based on user interview insights)
**Target Release:** Q4 2026
**Current Branch:** `ideation/exploration`

> **🔄 MAJOR UPDATE:** Sprint priorities revised based on user interview. See [USER_INTERVIEW_INSIGHTS.md](../USER_INTERVIEW_INSIGHTS.md).

---

## Sprint Structure

Each sprint is **2 weeks** with the following structure:
- **Week 1:** Implementation & unit tests
- **Week 2:** Integration, testing, documentation

---

## Release Phases

### Phase 1: Engagement Foundation (Q1 2026)
**Goal:** Enable diversity tracking, reading habit analytics, and book enrichment

**REVISED SPRINT PLAN:**

- **Sprint 1:** EnhancedDiversityStats (Foundation) + ReadingSession Model & Timer UI
- **Sprint 2:** Cascade Metadata System + Session Analytics & Streak Tracking
- **Sprint 3:** Book Enrichment System (Ratings + Metadata + Annotations)
- **Sprint 4:** Enhanced Diversity Analytics (Advanced Features)

**Key Deliverables:**
- ✨ **NEW:** Representation Radar chart (diversity visualization)
- ✨ **NEW:** Cascade metadata (add author info once, applies to all books)
- ✨ **NEW:** Ratings system (user vs. critics vs. community)
- Reading session tracking with timer
- Streak tracking and reading pace analytics
- Book enrichment system (ratings-first, annotations optional)
- Improved diversity analytics dashboard

**Key Changes from Original Plan:**
- **Moved diversity stats from Sprint 4 → Sprint 1** (user's #1 priority)
- **Added Cascade Metadata to Sprint 2** (NEW feature request)
- **Renamed "UserAnnotation" → "Book Enrichment System"** (ratings + metadata + annotations)

---

### Phase 2: Intelligence Layer (Q2 2026)
**Goal:** Add AI-powered insights and personalized recommendations

- **Sprint 5:** UserPreferenceProfile & Local AI Foundation
- **Sprint 6:** Pattern Recognition Engine
- **Sprint 7:** Recommendation System (Federated Learning)
- **Sprint 8:** Advanced Reading Insights

**Key Deliverables:**
- Local AI preference modeling
- Reading pattern recognition
- Privacy-preserving recommendations
- Advanced analytics dashboard

---

### Phase 3: Social Features (Q3 2026) ⚠️ OPTIONAL - PENDING USER RESEARCH
**Goal:** Privacy-first social reading features (IF validated by broader user research)

**User Interview Insight:** ReadingCircle ranked #5 (last). User has no social interest. May pivot this phase based on research.

- **Sprint 9:** ReadingCircle Foundation (IF validated)
- **Sprint 10:** Private Sharing & Invitations (IF validated)
- **Sprint 11:** Group Challenges & Goals (IF validated)
- **Sprint 12:** Community Recommendations (IF validated)

**Key Deliverables (if proceeding):**
- Private reading circles
- Secure sharing mechanisms
- Group reading challenges
- Anonymous community insights

**Alternative Plan (if social features not validated):**
- Additional polish and performance optimization
- Advanced discovery features (wishlist, want-to-read shelves)
- Content warnings and accessibility enhancements
- Community-requested features from user research

---

### Phase 4: Discovery & Polish (Q4 2026)
**Goal:** Enhanced discovery features and final polish

- **Sprint 13:** Price Tracking & Format Discovery
- **Sprint 14:** Enhanced Content Metadata (Series, Awards)
- **Sprint 15:** Accessibility Features & Content Warnings
- **Sprint 16:** Final Polish & Performance Optimization

**Key Deliverables:**
- Multi-retailer price tracking
- Comprehensive content metadata
- Accessibility improvements
- Performance optimization

---

## Current Sprint Status

### Active Sprint: None (Planning Phase)
**Next Sprint:** Sprint 1 (ReadingSession Model & Timer UI)
**Start Date:** TBD (Post user research validation)

---

## Sprint Documentation

Each sprint has its own detailed planning document:

- [`sprints/sprint-01-reading-session.md`](sprint-01-reading-session.md) - ReadingSession Model & Timer UI
- [`sprints/sprint-02-session-analytics.md`](sprint-02-session-analytics.md) - Session Analytics & Streaks
- [`sprints/sprint-03-annotations.md`](sprint-03-annotations.md) - UserAnnotation System
- [`sprints/sprint-04-diversity-stats.md`](sprint-04-diversity-stats.md) - Enhanced Diversity Stats

*(Additional sprints documented as planning progresses)*

---

## Technical Design Docs

Detailed technical specifications by feature area:

- [`technical-design/reading-sessions.md`](../technical-design/reading-sessions.md) - ReadingSession architecture
- [`technical-design/annotations.md`](../technical-design/annotations.md) - Annotation system design
- [`technical-design/ai-recommendations.md`](../technical-design/ai-recommendations.md) - Local AI architecture
- [`technical-design/social-features.md`](../technical-design/social-features.md) - Privacy-first social design

---

## Decision Records

Key architectural and design decisions:

- [`decisions/001-local-first-ai.md`](../decisions/001-local-first-ai.md) - Why local AI vs cloud
- [`decisions/002-swiftdata-migration.md`](../decisions/002-swiftdata-migration.md) - Schema migration strategy
- [`decisions/003-federated-learning.md`](../decisions/003-federated-learning.md) - Federated learning approach

---

## Feature Tracking

Features are tracked using GitHub issues with labels:
- `v2:phase-1` - Engagement Foundation features
- `v2:phase-2` - Intelligence Layer features
- `v2:phase-3` - Social Features
- `v2:phase-4` - Discovery & Polish

**Issue Template:** See [`.ai/v2-ideation/ISSUE_TEMPLATE.md`](../ISSUE_TEMPLATE.md)

---

## Success Metrics

### Phase 1 (Engagement Foundation)
- [ ] Users can track reading sessions with timer
- [ ] Streak tracking shows daily/weekly/monthly patterns
- [ ] Annotation system supports notes, highlights, bookmarks
- [ ] Enhanced diversity stats show intersectional data

### Phase 2 (Intelligence Layer)
- [ ] Local AI provides personalized recommendations
- [ ] Pattern recognition identifies reading habits
- [ ] Insights dashboard shows actionable data
- [ ] Zero user data sent to cloud

### Phase 3 (Social Features)
- [ ] Users can create private reading circles
- [ ] Secure sharing with E2E encryption
- [ ] Group challenges track collective progress
- [ ] Anonymous community insights available

### Phase 4 (Discovery & Polish)
- [ ] Price tracking across multiple retailers
- [ ] Series and awards data integrated
- [ ] Content warnings and accessibility info available
- [ ] App performance optimized for large libraries

---

## Next Actions

1. **User Research Validation** (Week of Nov 25, 2025)
   - Validate priority ranking with beta users
   - Gather feedback on ReadingSession timer UI mockups
   - Test annotation system concepts

2. **Sprint 1 Planning** (Week of Dec 2, 2025)
   - Finalize technical specs for ReadingSession model
   - Design timer UI and UX flow
   - Plan SwiftData schema migration
   - Create detailed task breakdown

3. **Development Environment Setup**
   - Create `feature/v2-reading-sessions` branch
   - Set up test fixtures for ReadingSession
   - Configure CI/CD for v2 features

---

**Last Updated:** November 20, 2025
**Maintained by:** oooe (jukasdrj)
**Status:** Planning Phase
