# Feature Flags

This document lists the feature flags available in the application, controlled via `FeatureFlags.swift`. These flags are used to toggle features, enable experimental capabilities, or provide emergency kill switches.

## Configuration

Feature flags are persisted in `UserDefaults` and can be modified via the Settings screen (accessible from the Library tab toolbar).

## Available Flags

### UI/UX
- **`enableTabBarMinimize`** (`Bool`)
  - **Default:** `true`
  - **Description:** Automatically hides the tab bar when scrolling down to maximize content area, and shows it when scrolling up. Disabled for VoiceOver/Reduce Motion.

- **`coverSelectionStrategy`** (`CoverSelectionStrategy`)
  - **Default:** `.auto`
  - **Description:** Controls the strategy for selecting which edition's cover to display.
  - **Values:**
    - `auto`: Best quality (completeness, format, recency).
    - `recent`: Most recently published.
    - `hardcover`: Prioritize hardcover.
    - `manual`: User manually selects.

### API & Networking
- **`enableV2Search`** (`Bool`)
  - **Default:** `true`
  - **Description:** Enables the V2 unified search API (`/api/v2/search`) which supports text, semantic, and hybrid search. V1 search is deprecated.

- **`enableV3Search`** (`Bool`)
  - **Default:** `true`
  - **Description:** Enables the V3 API client for book search operations.

- **`disableCanonicalEnrichment`** (`Bool`)
  - **Default:** `false`
  - **Description:** If `true`, forces the use of the legacy `/api/enrichment/batch` endpoint instead of the V3 `/v3/books/enrich` endpoint. Emergency fallback only.

- **`enablePhotoScanSSE`** (`Bool`)
  - **Default:** `true`
  - **Description:** Uses Server-Sent Events (SSE) for photo scan progress updates instead of WebSockets.

### Experimental / Beta
- **`enableWorkflowImport`** (`Bool`)
  - **Default:** `false`
  - **Description:** Enables Cloudflare Workflows for ISBN import, providing durable execution with retries and state persistence.

## Reset

Flags can be reset to their default values by invoking `FeatureFlags.shared.resetToDefaults()`, typically available in the "Reset Library" debug options.
