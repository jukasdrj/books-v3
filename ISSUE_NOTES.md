# Issue Notes and Resolutions

This document contains notes and verification status for open GitHub issues, based on codebase analysis.

## Issue #426 - Rate Limit Countdown Timer UI

**Status:** Partially Implemented

- **UI Component:** `RateLimitBanner.swift` exists and implements the countdown logic correctly.
- **Service Layer:** `BookSearchAPIService.swift` currently throws a generic `SearchError.httpError(429)` but does **not** capture the `Retry-After` header or expose a specific `ApiErrorCode.rateLimitExceeded`.
- **Resolution Plan:**
    1. Update `ApiErrorCode` (or `SearchError`) to include `.rateLimitExceeded(retryAfter: Int)`.
    2. Modify `BookSearchAPIService.swift` to check for status 429.
    3. Extract `Retry-After` header (or parse from body) and throw the specific error.
    4. Update views to catch this error and trigger `RateLimitBanner`.

## Issue #428 - CORS Error Handling

**Status:** Not Implemented

- **Service Layer:** `BookSearchAPIService.swift` treats status 0 or network errors generically.
- **Resolution Plan:**
    1. Update `SearchError` to include `.corsBlocked`.
    2. In `BookSearchAPIService`, check for specific network error conditions (e.g., status 0 with specific domains) or backend headers if available.
    3. Implement user-friendly error message for web builds (future proofing).

## Issue #434 - Visual Press Feedback

**Status:** Verified / Implemented

- **Component:** `ScaleButtonStyle.swift` exists and implements the scale effect with optional haptics.
- **Integration:** `iOS26LiquidLibraryView.swift` uses `.buttonStyle(ScaleButtonStyle())` on book cards.
- **Note:** Implementation looks correct and follows iOS 26 HIG.

## Issue #435 - Tighten Adaptive Grid Range

**Status:** Verified / Implemented

- **Integration:** `iOS26LiquidLibraryView.swift` implements the size-class based logic:
  ```swift
  case .compact: return [GridItem(.flexible()), GridItem(.flexible())]
  case .regular: return Array(repeating: GridItem(.flexible()), count: 4)
  ```
- **Note:** This matches the resolution plan.

## Issue #436 - Skeleton Screens for Library Load

**Status:** Verified / Implemented

- **Component:** `BookCardSkeleton.swift` exists.
- **Integration:** `iOS26LiquidLibraryView.swift` has `skeletonLoadingView` and uses `isLoading` state to toggle it.
- **Note:** Implementation looks correct.

## Issue #437 - Cover Image Prefetching in Search

**Status:** Partially Implemented / Needs Review

- **Service:** `ImagePrefetcher.swift` exists and handles background fetching.
- **Integration:** `SearchView+Results.swift` calls `prefetchImages` in `.task`.
- **Issue:** The current logic restricts prefetching to the end of the list:
  ```swift
  guard currentIndex >= items.count - prefetchThreshold else { return }
  ```
  This means images are NOT prefetched during normal scrolling, only when reaching the bottom.
- **Resolution Plan:** Remove the `currentIndex` guard or adjust logic to prefetch `currentIndex + N` regardless of position, to ensure smooth scrolling throughout the list.

## Dead Code Issue - iOS26AdaptiveBookCard Non-Functional Buttons

**Status:** Verified / Resolved

- **Verification:** `iOS26AdaptiveBookCard.swift` no longer contains `addToLibrary()` or `addToWishlist()` methods or the associated buttons.
- **Note:** Dead code has been successfully removed.
