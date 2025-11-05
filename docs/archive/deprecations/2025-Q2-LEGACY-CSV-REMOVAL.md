# Legacy CSV Import Removal Plan

**STATUS:** ✅ COMPLETED (October 27, 2025)

**Removal Details:**
- Version: v3.3.0
- Date: October 27, 2025
- Commits:
  - b6180e8 - Remove legacy CSV import UI from Settings
  - 48699f5 - Remove legacy CSV import orchestration
  - 88697b8 - Delete legacy CSV import UI files
  - 262a4d4 - Delete CSV parsing actor and Live Activity components
  - dfaec7c - Remove legacy CSV import documentation
  - 79d88c5 - Remove legacy CSV import test files
  - 622172b - Remove unused CSVImportService

---

**Deprecation Date:** January 27, 2025 (v3.1.0)
**Removal Target:** Q2 2025 (v3.3.0)
**Reason:** Replaced by Gemini AI-powered import with zero configuration

## What's Being Removed

### Files to Delete

1. `CSVImportFlowView.swift` - Main UI (manual column mapping)
2. `CSVImportSupportingViews.swift` - Column mapping UI components
3. `CSVParsingActor.swift` - Manual CSV parsing logic
4. `EnrichmentQueue.swift` - Background enrichment queue
5. `EnrichmentService.swift` - Enrichment orchestration
6. `ImportActivityAttributes.swift` - Live Activity for background import
7. `ImportLiveActivityView.swift` - Live Activity UI
8. `BackgroundImportBanner.swift` - In-app progress banner
9. `IMPORT_LIVE_ACTIVITY_GUIDE.md` - Implementation docs
10. `VISUAL_DESIGN_SPECS.md` - Design specs

**Total:** ~15,000 lines of code

### Dependencies to Keep

- `CSVImportService.swift` - Core import logic (may be useful for other features)
- `BookSearchAPIService.swift` - Used by other features

## Migration Path for Users

**Before removal:**
1. Deprecation notice in Settings (v3.1.0)
2. In-app banner in legacy flow (v3.1.0)
3. Release notes mention deprecation (v3.1.0)
4. App Store description highlights AI import (v3.1.0)

**During removal:**
1. Remove UI access in Settings (v3.2.0)
2. Show migration alert if user tries to access (v3.2.0)
3. Delete files in v3.3.0
4. Update documentation

**After removal:**
1. Monitor analytics for usage drop-off
2. Watch for support tickets about missing feature
3. Provide support article linking to AI import

## Risk Assessment

**Low Risk** - Migration is straightforward:
- Gemini import is strictly superior (zero config vs manual)
- No data loss (both save to same SwiftData models)
- Users benefit from easier workflow
- Backend already deployed and tested

**Metrics to Monitor:**
- CSV import feature usage (expect 90%+ using Gemini after v3.1.0)
- Support tickets about "can't find column mapping"
- App Store reviews mentioning import difficulty

## Rollback Plan

If Gemini import has critical bugs:
1. Restore Settings button for legacy import
2. Remove deprecation warnings
3. Fix Gemini issues
4. Re-deprecate when stable

## Success Criteria

Safe to remove legacy import when:
- [x] Gemini import used by 95%+ of CSV importers
- [x] Zero critical bugs in Gemini import (30-day window)
- [x] No support tickets about legacy import in 14 days
- [x] App Store review sentiment positive on import feature

**Status:** All criteria met as of October 27, 2025. Removal completed successfully.

## Timeline

- **v3.1.0 (Jan 2025):** Deprecation warnings, promote Gemini
- **v3.2.0 (Mar 2025):** Hide legacy UI, show migration alert
- **v3.3.0 (May 2025):** Delete legacy code, clean up docs

---

**Next Steps:** Create GitHub issue to track removal tasks.
