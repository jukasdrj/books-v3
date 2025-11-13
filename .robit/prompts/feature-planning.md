# Feature Planning Template

Use this template when planning new features for BooksTrack (or adapt for other projects).

---

## 📋 Feature Overview

**Feature Name:** [Short, descriptive name]

**Problem Statement:** [What user pain point does this solve?]

**Target Users:** [Who needs this feature?]
- Primary: [e.g., "Power readers who track 100+ books/year"]
- Secondary: [e.g., "Casual readers discovering new books"]

**Success Metrics:** [How do we measure success?]
- [Metric 1, e.g., "80% of users enable feature in first week"]
- [Metric 2, e.g., "10% increase in books added per user"]
- [Metric 3, e.g., "95% accuracy (low false positives)"]

---

## 🎯 Requirements

### Functional Requirements

**Must Have (P0):**
1. [Core functionality, e.g., "User can scan bookshelf photo"]
2. [Essential feature, e.g., "AI detects ISBNs from spines"]
3. [Critical behavior, e.g., "Books added to library automatically"]

**Should Have (P1):**
1. [Important but not blocking launch, e.g., "Progress indicator during AI processing"]
2. [Nice-to-have enhancement, e.g., "Batch scanning (5 photos)"]

**Could Have (P2):**
1. [Future enhancement, e.g., "Auto-rotate photos for best angle"]
2. [Low-priority polish, e.g., "Undo scan action"]

### Non-Functional Requirements

**Performance:**
- [Metric, e.g., "AI processing completes in <40s"]
- [Constraint, e.g., "Works with 4-5MB photos (no resizing)"]

**Accessibility:**
- [WCAG AA compliance, e.g., "4.5:1 contrast for all UI text"]
- [VoiceOver support, e.g., "All buttons have accessibility labels"]

**Security:**
- [Privacy requirement, e.g., "Photos deleted after processing"]
- [Data protection, e.g., "No user data stored in backend"]

---

## 🏗️ Architecture

### Data Model Changes

**New Models:** (if any)
```swift
@Model
public class DetectedBook {
    public var isbn: String
    public var confidence: Double  // 0.0-1.0
    public var boundingBox: BoundingBox?
    // ...
}
```

**Model Changes:** (if modifying existing)
- `Work` → Add `lastScanDate: Date?` (track when last scanned)
- `UserLibraryEntry` → Add `source: SourceType` (manual, scan, import)

### API Changes

**New Endpoints:**
- `POST /api/scan-bookshelf?jobId={uuid}` - Upload photo for AI scan
- `GET /ws/progress?jobId={uuid}` - WebSocket for real-time progress

**Modified Endpoints:**
- `POST /v1/enrichment/batch` - Add support for scanned books

### UI Components

**New Views:**
- `ShelfScannerView` - Camera + capture UI
- `ReviewQueueView` - Human-in-the-loop corrections
- `ScanResultsView` - Display detected books

**Modified Views:**
- `LibraryView` - Show scanned books with badge
- `SettingsView` - Add AI provider selection

---

## 🔄 User Flow

**Happy Path:**
```
1. User taps "Scan Bookshelf" tab
2. Camera permission requested (if first time)
3. User aims camera at bookshelf
4. User taps capture button
5. Photo preprocessed (resize to 3072px @ 90% quality)
6. Uploading... (progress indicator)
7. WebSocket established for real-time progress
8. AI processing... (25-40s)
9. Results shown (list of detected books with confidence)
10. High confidence (≥0.6) → Added to library automatically
11. Low confidence (<0.6) → Review Queue (user confirms)
12. Success confirmation (haptic + toast)
```

**Error Paths:**
- Camera permission denied → Show permission prompt with Settings link
- Upload fails → Retry with exponential backoff (3 attempts)
- AI processing fails → Show error, offer manual add option
- WebSocket disconnects → Fall back to polling (AdaptivePollingStrategy)
- Low confidence results → Review Queue (human-in-the-loop)

---

## 🧪 Testing Strategy

### Unit Tests

**Services:**
- `EnrichmentQueue.enqueue()` - Handles new scanned books
- `DTOMapper.mapToModels()` - Converts DetectedBook to Work/Edition
- `ISBNValidator.validate()` - Detects malformed ISBNs

**Models:**
- `DetectedBook` - SwiftData persistence
- `Work.addFromScan()` - Creates Work from AI result

### Integration Tests

**API:**
- `POST /api/scan-bookshelf` - Returns valid DetectedBook[]
- `GET /ws/progress` - Sends progress updates in real-time
- Backend enrichment - Fetches full metadata for ISBNs

**UI:**
- Camera permission flow (simulator + real device)
- Photo capture + upload (real device only)
- WebSocket connection + progress updates
- Review Queue workflow (accept/reject/edit)

### Manual Testing

**Real Device (iPhone 15 Pro, iOS 26.0):**
- [ ] Camera works (no lag, no crash)
- [ ] Photo quality adequate (3072px readable)
- [ ] Upload completes (4-5MB in <5s on WiFi)
- [ ] WebSocket updates smooth (8ms latency)
- [ ] AI results accurate (90%+ for clear spines)
- [ ] Low confidence → Review Queue
- [ ] High confidence → Library immediately
- [ ] Haptic feedback appropriate (success/error)
- [ ] Accessibility (VoiceOver, Dynamic Type)

---

## 🚀 Implementation Plan

### Phase 1: Foundation (Week 1)
- [ ] Design data models (DetectedBook, BoundingBox)
- [ ] Implement camera UI (VisionKit DataScannerViewController)
- [ ] Photo preprocessing (resize, quality)
- [ ] Unit tests for models

### Phase 2: Backend Integration (Week 2)
- [ ] Implement `/api/scan-bookshelf` endpoint
- [ ] Gemini 2.0 Flash API integration
- [ ] WebSocket progress (ProgressWebSocketDO)
- [ ] Unit tests for backend services

### Phase 3: iOS Integration (Week 3)
- [ ] APIClient.scanBookshelf() method
- [ ] WebSocket client (URLSessionWebSocketTask)
- [ ] DTOMapper for DetectedBook → Work/Edition
- [ ] Integration tests (API + DTOMapper)

### Phase 4: UI Polish (Week 4)
- [ ] Review Queue UI (accept/reject/edit)
- [ ] Progress indicators (WebSocket-driven)
- [ ] Error handling UI (retry, manual add)
- [ ] Accessibility pass (VoiceOver, labels)

### Phase 5: Testing & Launch (Week 5)
- [ ] Real device testing (5+ devices)
- [ ] Performance testing (large photos, slow network)
- [ ] Beta testing (TestFlight, 10 users)
- [ ] Documentation (feature doc, workflow diagram)
- [ ] App Store submission

---

## 🎯 Acceptance Criteria

**Feature is complete when:**
- ✅ User can capture bookshelf photo with camera
- ✅ AI detects ISBNs with 90%+ accuracy (clear spines)
- ✅ WebSocket progress updates in real-time (8ms latency)
- ✅ High confidence books (≥0.6) added to library automatically
- ✅ Low confidence books (<0.6) go to Review Queue
- ✅ Review Queue allows accept/reject/edit
- ✅ All error cases handled gracefully (retry, fallback, manual add)
- ✅ Zero warnings, all tests pass
- ✅ Real device tested (5+ devices)
- ✅ Accessibility compliant (VoiceOver, WCAG AA)
- ✅ Documentation complete (PRD, workflow, feature doc)

---

## 📊 Risks & Mitigation

### Technical Risks

**Risk:** AI accuracy < 90% (too many false positives)
- **Likelihood:** Medium
- **Impact:** High (users lose trust in feature)
- **Mitigation:** Implement Review Queue (human-in-the-loop), set conservative confidence threshold (0.6), allow manual correction

**Risk:** WebSocket disconnects frequently (network issues)
- **Likelihood:** Low
- **Impact:** Medium (poor UX, but not broken)
- **Mitigation:** Fallback to polling (AdaptivePollingStrategy), auto-reconnect, show progress indicator

**Risk:** Large photos (10MB+) fail to upload (timeout)
- **Likelihood:** Low
- **Impact:** Medium (user frustration)
- **Mitigation:** Preprocess to 3072px @ 90% quality (400-600KB), retry with exponential backoff

### Product Risks

**Risk:** Users don't understand feature (skip tutorial)
- **Likelihood:** Medium
- **Impact:** Medium (low adoption)
- **Mitigation:** In-app tutorial on first launch, contextual hints, demo video in App Store

**Risk:** Feature too slow (AI processing >60s)
- **Likelihood:** Low
- **Impact:** High (users give up)
- **Mitigation:** Optimize Gemini prompt, show progress indicator, set user expectation ("Processing may take up to 40 seconds")

---

## 🔗 Related Documents

**PRD:** `docs/product/Bookshelf-Scanner-PRD.md` (product requirements)
**Workflow:** `docs/workflows/bookshelf-scanner-workflow.md` (visual flow)
**Feature Doc:** `docs/features/BOOKSHELF_SCANNER.md` (implementation details)
**Architecture:** `.robit/architecture.md` (system design)

---

## 📝 Notes & Open Questions

**Open Questions:**
- Q: Should we support batch scanning (5 photos)?
  - A: Yes, implement in v3.2.0 (Phase 2 enhancement)

- Q: What if user scans same bookshelf twice?
  - A: Deduplication by ISBN (existing logic handles it)

- Q: Should we store original photo?
  - A: No, delete after processing (privacy + storage cost)

**Design Decisions:**
- Use VisionKit DataScannerViewController (not custom camera)
- Gemini 2.0 Flash (not Cloudflare AI - too small context)
- WebSocket (not polling - better UX)
- Review Queue (not auto-add all - too risky)

**Future Enhancements:**
- Batch scanning (5 photos in one session)
- Auto-rotate photos for best angle
- OCR fallback if Gemini unavailable
- Offline mode (queue scans, process when online)

---

**Use this template for all new features. Adapt sections for project-specific needs.**
