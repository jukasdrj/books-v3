# Migration History

This document tracks major architectural changes and refactorings in the BooksTrack codebase.
For rollback or historical reference, use the git tags listed below.

---

## November 2025: Security Audit Implementation

**Decision:** Implemented critical security hardening for backend infrastructure

**Components:**
1. **Rate Limiting** - KV-based token bucket (10 req/min per IP)
2. **Request Size Validation** - 10MB CSV / 5MB image limits
3. **CORS Whitelist** - Replaced wildcard '*' with domain whitelist

**Motivation:**
- Prevent denial-of-wallet attacks on AI/enrichment endpoints
- Block CSRF attacks from malicious websites
- Prevent worker memory crashes from oversized requests

**Affected Files:**
- `cloudflare-workers/api-worker/src/index.js` (13 CORS fixes)
- `cloudflare-workers/api-worker/src/middleware/` (rate-limiter.js, cors.js, size-validator.js)

**Deployment:** Version `1dc336b1-b561-4713-a373-70b977c5075c` (Nov 4, 2025)

**See:** `SECURITY_AUDIT_2025-11-03.md`, `docs/plans/2025-11-04-security-audit-implementation.md`

---

## November 2025: iOS Data Layer Refactoring

**Decision:** Extracted EditionSelection strategy pattern and ReadingStatusParser service

**Motivation:**
- `primaryEdition` computed property was 43 lines (hard to test)
- `ReadingStatus.from()` was 65 lines of switch statements
- Adding new strategies/formats required modifying model files

**Refactorings:**
1. **EditionSelection Strategy Pattern** - 4 strategies (Auto, Recent, Hardcover, Manual)
2. **ReadingStatusParser Service** - Fuzzy matching with Levenshtein distance
3. **@Bindable Documentation** - Added usage guides to all SwiftData models

**Affected Files:**
- `Work.swift` - primaryEdition refactored (43 lines → 20 lines)
- `UserLibraryEntry.swift` - ReadingStatus.from() refactored (65 lines → 3 lines)
- NEW: `EditionSelectionStrategy.swift` (205 lines)
- NEW: `ReadingStatusParser.swift` (209 lines)
- NEW: Test suites (47 tests total)

**Benefits:**
- Each strategy testable in isolation
- Fuzzy matching handles typos ("currenty reading" → .reading)
- SwiftData reactivity patterns documented

**See:** `docs/plans/2025-11-04-security-audit-implementation.md` (Component 2)

---

## October 2025: Monolith Consolidation

**Decision:** Consolidated distributed Cloudflare Workers into single monolith

**Reason:**
- Simpler architecture for current scale (<1000 users)
- Reduced operational complexity
- Direct function calls instead of RPC overhead

**Removed:**
- `cloudflare-workers/_archived/personal-library-cache-warmer/`
- `cloudflare-workers/_archived/enrichment-worker/`
- `cloudflare-workers/_archived/ai-worker/`

**View old code:** `git checkout v3.0.0-pre-monolith` (if tag exists)

**See:** `cloudflare-workers/MONOLITH_ARCHITECTURE.md` for new design

---

## October 2025: VisionKit Barcode Scanner

**Decision:** Migrated from custom AVFoundation camera to Apple VisionKit DataScannerViewController

**Reason:**
- Native Apple barcode scanning (zero custom camera code)
- Built-in guidance UI ("Move Closer", "Slow Down")
- Automatic capability checking (A12+ chip required)
- Pinch-to-zoom, tap-to-scan gestures included

**Removed:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/_archive/BarcodeDetectionService.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/_archive/CameraManager.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/_archive/ModernCameraPreview.swift`

**View old code:** Archived files in `_archive/` directory (pre-deletion)

**See:** `docs/plans/2025-10-30-visionkit-barcode-scanner-design.md`

---

## September 2025: iOS SwiftData Refactoring

**Decision:** Removed ViewModel layer in favor of @Observable + @State

**Reason:**
- SwiftData models already observable
- ViewModels created unnecessary indirection
- Simpler state management with @Bindable

**Pattern Before:**
```swift
class LibraryViewModel: ObservableObject {
    @Published var works: [Work] = []
    // ... indirection layer
}
```

**Pattern After:**
```swift
@State private var searchModel = SearchModel()  // @Observable
@Bindable var work: Work  // Direct SwiftData binding
```

**Removed:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/_archive/ViewModels/` (if existed)

**View old code:** `git checkout v2.8.0-pre-swiftdata-refactor` (if tag exists)

**See:** `docs/architecture/STATE_MANAGEMENT.md` for patterns

---

## Rollback Instructions

### Backend Security (November 2025)

If rate limiting causes false positives:
```bash
# Adjust limits in wrangler.toml
[[unsafe.bindings]]
name = "RATE_LIMITER"
simple = { limit = 20, period = 60 }  # Increase to 20 req/min
```

If CORS breaks iOS app:
```javascript
// Add Capacitor/Ionic origins to src/middleware/cors.js
const ALLOWED_ORIGINS = [
  // ... existing origins
  'capacitor://localhost',
  'ionic://localhost'
];
```

### iOS Data Layer (November 2025)

If EditionSelection breaks UI:
```bash
git revert <commit-hash>  # Revert strategy pattern
# Work.primaryEdition will revert to original 43-line implementation
```

If ReadingStatusParser fails imports:
```bash
git revert <commit-hash>  # Revert parser service
# ReadingStatus.from() will revert to original 65-line switch statement
```

---

## Best Practices for Future Migrations

1. **Tag before major changes:** `git tag v3.x.0-pre-<feature-name>`
2. **Document in this file** before deleting archived code
3. **Keep archived code for 1-2 release cycles** before permanent deletion
4. **Test rollback procedure** in staging environment
5. **Update CLAUDE.md** with new patterns after migration

---

**Last Updated:** November 4, 2025
**Maintainer:** Development Team
