# Settings & Library Reset – Product Requirements Document

## Executive Summary
Settings provides users with app customization options (themes, AI provider selection, experimental features) accessible via a gear icon in the Library tab. Library Reset offers a comprehensive data clearing feature within Settings, allowing users and developers to start fresh by deleting all books, authors, reading progress, and canceling any in‑flight backend enrichment jobs. Combining these documents clarifies the relationship between UI configuration and the destructive reset action, ensuring a single source of truth for stakeholders.

## Problem Statement
- **User Pain**: Users need a discoverable way to customize the app and a reliable method to completely clear their library without reinstalling the app.
- **Developer Pain**: Developers require a quick way to reset test data for CSV import and other features.

## Target Users
| Persona | Use Cases |
|---------|-----------|
| End User | Change theme, enable experimental features, reset library after bad import. |
| Developer | Test CSV import, onboarding flow, reset data frequently. |
| Beta Tester | Validate new features with a fresh library. |

## User Stories & Acceptance Criteria
### Settings
- **Access Settings**: Gear icon in Library toolbar opens Settings sheet.
- **Change Theme**: Select from 5 curated themes; UI updates instantly and persists.
- **AI Provider**: Choose Gemini (default) – other providers not currently supported.
- **Experimental Features**: Toggle flags (e.g., barcode scanner).

### Library Reset
- **Access Reset**: Reset button appears in Settings → Library Management section.
- **Confirmation Dialog**: Single dialog requires user confirmation.
- **Data Deletion**: All Works, Editions, Authors, UserLibraryEntries deleted.
- **Auxiliary Cleanup**: Search history, enrichment queue, feature flags reset; backend enrichment jobs canceled.
- **Post‑Reset Feedback**: Success toast displayed.

## Success Metrics
| Metric | Target |
|--------|--------|
| Settings Discoverability | 60%+ users find Settings within first week |
| Theme Adoption | 40%+ users change default theme |
| Reset Speed | <2 s completion |
| Reset Completeness | 100% data deleted, backend jobs canceled |
| Accidental Reset Prevention | 0 resets without confirmation |

## Technical Implementation
### Architecture Overview
- **Settings Sheet** (`SettingsView.swift`): UI sections for Appearance, Library Management, AI Features, Advanced.
- **Library Reset Flow** (`SettingsView.performLibraryReset()`):
  1. Cancel backend jobs via `EnrichmentQueue.shared.cancelBackendJob(jobId:)`.
  2. Batch delete SwiftData models.
  3. Clear auxiliary data (search history, feature flags, enrichment queue).
  4. Show success toast.

### Backend Cancellation
POST `/api/enrichment/cancel` → Durable Object `ProgressWebSocketDO.cancelJob()` → status set to `canceled` → WebSocket broadcast.

## UI Specification
### Settings Screen Layout (Sheet)
```
┌─────────────────────────────────────┐
│ Settings                [Done]      │
├─────────────────────────────────────┤
│ APPEARANCE                         │
│ Theme: Liquid Blue          [>]
│ Follow System Appearance   [✓]
│                                   │
│ LIBRARY MANAGEMENT                 │
│ AI‑Powered CSV Import      [>]
│ Reset Library          [Red Text]
│                                   │
│ AI FEATURES                        │
│ Tab Bar Minimize on Scroll [✓]
└─────────────────────────────────────┘
```
- **Reset Confirmation Dialog** with Cancel and Reset (red) buttons.
- **Success Toast**: "Library reset successfully".

## Implementation Files
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/SettingsView.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/EnrichmentQueue.swift`
- Backend: `cloudflare-workers/api-worker/src/handlers/enrichment.ts`, `ProgressWebSocketDO.ts`

## Testing Strategy
### Manual QA
- Open Settings, change theme, verify immediate UI update.
- Open Settings → Library Management, tap Reset, confirm dialog, verify all data cleared and backend job canceled.
- Perform CSV import, trigger Reset mid‑enrichment, ensure cancellation.
- Verify toast and empty Library view.

### Edge Cases
- Reset while offline (network request fails) – local delete still succeeds.
- Large library (1000+ books) – reset completes <2 s.
- Crash during reset – operation idempotent; re‑run completes.

## Future Enhancements
- **Backup Before Reset**: Auto‑export CSV of current library.
- **Selective Reset Options**: Delete only read books, wishlist, etc.
- **Undo Reset**: Soft delete with 5‑minute undo window.
- **Analytics**: Capture reset reasons to improve UX.

## Dependencies
- SwiftUI, SwiftData, UserDefaults (theme, flags)
- EnrichmentQueue (backend job tracking)
- CloudKit sync (deletes propagate to other devices)

## Success Criteria (Shipped)
- ✅ Settings accessible via gear icon.
- ✅ Theme changes apply instantly and persist.
- ✅ Library Reset completes <2 s, deletes all data, cancels backend jobs.
- ✅ Confirmation dialog prevents accidental resets.
- ✅ Post‑reset toast displayed.
- ✅ CloudKit sync propagates empty library.

---
*Documentation generated on 2025‑11‑19.*
