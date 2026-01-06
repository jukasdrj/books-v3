# BooksTrack Master TODO

**Version:** 3.7.5 (Build 189+)
**Last Updated:** January 5, 2026
**Status:** Production (App Store Live)

---

## 🎯 Current Sprint (Q1 2026)

### P0 - Critical (Ship This Week)
- [ ] None currently

### P1 - High Priority (Ship This Month)
- [ ] **Test Suite Cleanup** - Remove placeholder tests and migrate XCTest → Testing framework
  - [ ] Delete `BooksTrackerFeatureTests.swift` (empty placeholder)
  - [ ] Delete `TabBarAccessibilityTests.swift` (stub tests)
  - [ ] Migrate `CombinedImportTests.swift` to Testing framework
  - [ ] Migrate `WeeklyRecommendationsServiceTests.swift` to Testing framework
  - Reference: `archive/test-reports/TEST_CLEANUP_REPORT.md`

- [ ] **Reading Insights "Code Red" - Basic Working System**
  - [ ] Implement Phase 4 interactive filtering (tap dimension → filter library)
  - [ ] Fix TODOs in `Insights/InsightsView.swift` (lines 95, 109, 209, 220, 228)
  - [ ] Ensure basic drill-down works reliably before adding polish
  - [ ] Performance testing with 500+ book libraries

- [ ] **Flutter Feature Parity Roadmap**
  - [ ] Complete Flutter PRD sections for all 9 shipped iOS features
  - [ ] Create Flutter Feature Parity Matrix
  - [ ] Establish Flutter v1.0 launch criteria (full parity required)

### P2 - Medium Priority (Next Quarter)
- [ ] **Reading Goals System** (NEW - v3.8)
  - [x] Create Reading Goals PRD ✅ (Jan 5, 2026)
  - [ ] Implement quantitative goals (books/year, pages/week, reading streaks)
  - [ ] Add diversity challenge goals (X books from Y region/gender)
  - [ ] Support category-specific goals (genre targets)
  - [ ] Goal progress tracking and notifications

- [ ] **Series Tracking** (NEW - v3.8)
  - [x] Create Series Tracking PRD ✅ (Jan 5, 2026)
  - [ ] Auto-detect series from Google Books/OpenLibrary metadata
  - [ ] Manual series creation and assignment
  - [ ] Series completion % visualization
  - [ ] "Next in series" recommendations

- [ ] **Award Tracking** (NEW - v3.8)
  - [x] Create Award Tracking PRD ✅ (Jan 5, 2026)
  - [ ] Badge system for Pulitzer, Booker, Nobel, National Book Award
  - [ ] Award metadata enrichment from backend
  - [ ] Award-based filtering and statistics

- [ ] **Diversity Data Enrichment**
  - [ ] Add manual diversity data entry sheet (`WorkDetailView.swift:490`)
  - [ ] Improve author gender/cultural region detection
  - [ ] Add bulk edit capabilities for diversity dimensions

- [ ] **Search Improvements**
  - [ ] Move `recentSearches` to viewState (`SearchModel.swift:43`)
  - [ ] Implement "Navigate to recent searches" (`SearchView/SearchView+EmptyStates.swift:161`)
  - [ ] Add search history persistence

- [ ] **API Enhancements**
  - [ ] Implement pagination beyond first page (`Services/V3BooksService.swift:175`)
  - [ ] Add multi-page result fetching
  - [ ] Optimize network caching strategy

---

## 🔮 Stretch Goals (Future Releases)

### Reading Experience
- [ ] **Reading Session Deep Dive**
  - [ ] Add session-level notes
  - [ ] Track reading speed (pages/hour)
  - [ ] Export reading history to CSV

- [ ] **Analytics & Suggestions** (v4.0 - bendv3 Integration)
  - [ ] Wait for bendv3 suggestions system build
  - [ ] Instrument review queue corrections (`ReviewQueue/CorrectionView.swift:397`)
  - [ ] Track search API fallbacks (`Services/BookSearchAPIService.swift:512`)
  - [ ] Monitor enrichment errors (`Common/EnrichmentAPIClient.swift:534`)
  - [ ] AI-powered reading recommendations

### Data Quality
- [ ] **Enhanced Metadata**
  - [ ] Multiple index support for Work model (pending SwiftData updates - `Work.swift:56`)
  - [ ] Add book series tracking
  - [ ] Publisher data enrichment
  - [ ] Award/prize tracking

- [ ] **Cover Art Improvements**
  - [ ] Fallback to edition covers from Work-level
  - [ ] User-uploaded custom covers
  - [ ] High-res cover downloads

### Performance
- [ ] **Optimization Sprint**
  - [ ] Profile app launch time (target: <400ms cold start)
  - [ ] Optimize SwiftData queries with compound predicates
  - [ ] Reduce memory footprint in large libraries (>1000 books)

### Platform Expansion
- [ ] **Cross-Platform PRD Implementation**
  - [ ] Flutter app (see `docs/product/README.md`)
  - [ ] Android native app
  - [ ] Web companion dashboard

---

## 🧪 Technical Debt

### Code Quality
- [ ] **SwiftLint Compliance**
  - [ ] Review architectural warnings (Build 189+ strict rules)
  - [ ] Add custom rules for SwiftData patterns
  - [ ] Enforce documentation coverage

- [ ] **Test Coverage**
  - [ ] Increase UI test coverage (currently smoke tests only)
  - [ ] Add integration tests for CloudKit sync
  - [ ] Performance regression tests

### Documentation
- [x] Archive stale docs (PR guides, test reports) ✅
- [x] Clean up build logs from root ✅
- [x] Create master TODO.md ✅
- [x] Create Reading Goals PRD ✅
- [x] Create Series Tracking PRD ✅ (Jan 5, 2026)
- [x] Create Award Tracking PRD ✅ (Jan 5, 2026)
- [x] Sync OpenAPI spec and organize documentation structure ✅ (PR #192, Jan 6, 2026)
- [x] Documentation refactor & API sync ✅ (PR #193, Jan 6, 2026)
- [x] Rename docs/prd/ → docs/product/ for clarity ✅ (Jan 6, 2026)
- [ ] Update all 12 existing PRDs with Flutter implementation sections
- [ ] Create Flutter Feature Parity Matrix document
- [ ] Update Insights PRD with Phase 4 'basic working system' approach
- [ ] Verify all PRDs reflect API v2.4.1 contracts
- [ ] Update CHANGELOG.md (consolidate old entries - LOW PRIORITY)
- [ ] Add architecture decision records (ADRs - FUTURE)

### Dependencies
- [ ] Audit Swift package dependencies for updates
- [ ] Review OpenAPI generator version
- [ ] Update Swift Testing to latest stable

---

## 🎨 Design System

### iOS 26 Liquid Glass
- [ ] **Accessibility Audit**
  - [ ] WCAG AAA compliance review (currently AA)
  - [ ] VoiceOver script testing
  - [ ] Dynamic Type scaling validation

- [ ] **Theme Expansion**
  - [ ] Add user-customizable color palettes
  - [ ] Seasonal theme variants
  - [ ] Reading mode (sepia, dark, OLED black)

---

## 📦 App Store Optimization

### Marketing
- [ ] Update App Store screenshots (feature new Insights UI)
- [ ] Refresh product description with AI scanning highlights
- [ ] Add localized metadata (Spanish, French, German)

### Engagement
- [ ] Implement App Store review prompts (after 10 books added)
- [ ] Add SharePlay support for book recommendations
- [ ] StoreKit 2 migration for future IAP

---

## 🚧 Known Issues & Limitations

### iOS 26 Specific
- [x] ~~Keyboard broken with `.navigationBarDrawer` - FIXED~~
- [ ] Widget provisioning profile (deferred to v1.13.0 - `BooksTrackerWidgets/BooksTrackerWidgetsBundle.swift:17`)

### Backend API
- [ ] CSV import row number accuracy for database errors (Issue #242)
- [ ] WebSocket hibernation adoption (v2.4.1 - 70% cost savings)

### SwiftData
- [ ] Multiple index support for compound queries (FB tracked - `Work.swift:56`)
- [ ] Relationship deletion cascade edge cases

---

## 📊 Success Metrics (Q1 2026)

### User Engagement
- Target: 80% DAU/MAU ratio (currently: measure after analytics)
- Target: Average 5 books added per user per week
- Target: 70% feature discovery rate (AI scanner, CSV import)

### Technical Quality
- Build time: <30s clean build (currently: 25s ✅)
- Test suite: 100% pass rate (currently: 370+ tests ✅)
- Crash-free rate: 99.9% (currently: measure after analytics)

### App Store
- Rating: Maintain 4.8+ stars
- Reviews: 50+ reviews in Q1
- Downloads: 1000+ new users

---

## 🗂️ Archive References

- **Completed PRs:** `archive/completed-prs/PR242_FRONTEND_INTEGRATION_GUIDE.md`
- **Test Reports:** `archive/test-reports/TEST_CLEANUP_REPORT.md`
- **Deprecated Docs:** `archive/deprecated-docs/CLAUDE_FULL.md`
- **Old AI Context:** `archive/deprecated-ai-context/`
- **Legacy GitHub Agents:** `archive/deprecated-github-agents/`

---

## 🔗 Quick Links

- **PRD Index:** `docs/product/README.md`
- **API Contracts:** `docs/product/Canonical-Data-Contracts-PRD.md`
- **Testing Guide:** `AGENTS.md` (Testing section)
- **Claude Code Guide:** `CLAUDE.md`
- **Change History:** `CHANGELOG.md`

---

**Notes:**
- Items marked with file references can be found via grep/search
- Analytics TODOs blocked until SDK integration
- Insights Phase 4 requires design review before implementation
- SwiftData limitations tracked with Apple Feedback Assistant

**Last Review:** January 5, 2026
