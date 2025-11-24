# Planned Resolutions for GitHub Issues

This document outlines the resolution plan and status for the issues listed in `.github/issue-resolution-comments.md`.

## Issue #426 - Rate Limit Countdown Timer UI
**Status:** In Progress
**Plan:**
- `RateLimitBanner` component is already created.
- `BookshelfScannerView` already integrates it.
- **Action:** Update `GeminiCSVImportView.swift` to include `RateLimitBanner` and handle `rateLimited` error state.

## Issue #428 - CORS Error Handling
**Status:** Planned
**Plan:**
- **Action:** Add `corsBlocked` case to `ApiErrorCode.swift`.
- **Action:** Update `BookSearchAPIService.swift` and `EnrichmentAPIClient.swift` to detect CORS errors (e.g., status 0 or null origin) and map them to `ApiErrorCode.corsBlocked`.

## Issue #434 - Visual Press Feedback
**Status:** ✅ Resolved
**Notes:**
- `ScaleButtonStyle.swift` has been created.
- Applied to book cards in `iOS26LiquidLibraryView.swift` via `.buttonStyle(ScaleButtonStyle())`.

## Issue #435 - Tighten Adaptive Grid Range
**Status:** ✅ Resolved
**Notes:**
- `iOS26LiquidLibraryView.swift` now uses `horizontalSizeClass` to switch between fixed column counts (2 for compact, 4 for regular) and an adaptive fallback with a tighter range (160-180), implementing "Option 2".

## Issue #436 - Skeleton Screens for Library Load
**Status:** ✅ Resolved
**Notes:**
- `BookCardSkeleton.swift` has been created.
- `iOS26LiquidLibraryView.swift` implements `skeletonLoadingView` which is shown while `isLoading` is true.

## Issue #437 - Cover Image Prefetching in Search
**Status:** In Progress
**Plan:**
- `ImagePrefetcher` exists but usage in `SearchView+Results.swift` is suboptimal (only prefetches near end of list).
- **Action:** Update `prefetchImages` in `SearchView+Results.swift` to prefetch the *next N* images from the current index.
- **Action:** Add Low Power Mode check (reduce prefetch count from 10 to 3).
- **Action:** Add memory pressure monitoring to cancel prefetching.

## Dead Code Issue - iOS26AdaptiveBookCard Non-Functional Buttons
**Status:** ✅ Resolved
**Notes:**
- `iOS26AdaptiveBookCard.swift`, `iOS26FloatingBookCard.swift`, and `iOS26LiquidListRow.swift` have been cleaned up. Non-functional "Add to Library" buttons have been removed.
