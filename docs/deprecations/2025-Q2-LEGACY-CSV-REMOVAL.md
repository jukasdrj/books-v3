# Legacy CSV Import Removal Plan

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
- [ ] Gemini import used by 95%+ of CSV importers
- [ ] Zero critical bugs in Gemini import (30-day window)
- [ ] No support tickets about legacy import in 14 days
- [ ] App Store review sentiment positive on import feature

## Timeline

- **v3.1.0 (Jan 2025):** Deprecation warnings, promote Gemini
- **v3.2.0 (Mar 2025):** Hide legacy UI, show migration alert
- **v3.3.0 (May 2025):** Delete legacy code, clean up docs

---

**Next Steps:** Create GitHub issue to track removal tasks.
