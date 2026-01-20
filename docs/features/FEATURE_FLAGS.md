# Feature Flags

This document describes the feature flags used in the BooksTracker iOS application to control feature rollout, experimental capabilities, and legacy fallbacks.

## Overview

Feature flags are managed by the `FeatureFlags` singleton class (`BooksTrackerPackage/Sources/BooksTrackerFeature/FeatureFlags.swift`). They are persisted using `UserDefaults` and can be toggled via the application's debug or settings menu.

## Current Flags

| Flag Name | Description | Default | Key |
| :--- | :--- | :--- | :--- |
| `enableTabBarMinimize` | Hides the tab bar on scroll to maximize content area. Disabled for VoiceOver/Reduce Motion. | `true` | `enableTabBarMinimize` |
| `coverSelectionStrategy` | Controls the logic for selecting which edition's cover to display (Auto, Recent, Hardcover, Manual). | `.auto` | `coverSelectionStrategy` |
| `disableCanonicalEnrichment` | Forces the use of the legacy `/api/enrichment/batch` endpoint instead of the V3 `/v3/books/enrich`. Emergency fallback only. | `false` | `feature.disableCanonicalEnrichment` |
| `enableV2Search` | Enables the V2 Unified Search API (`/api/v2/search`). This is now the primary search API for legacy clients. | `true` | `feature.enableV2Search` |
| `enableV3Search` | Enables the V3 API client for book search operations. This is part of the V3 Migration Plan (Phase 3). | `true` | `feature.enableV3Search` |
| `enableWorkflowImport` | Enables Cloudflare Workflows for ISBN import (durable execution with retries). | `false` | `feature.enableWorkflowImport` |
| `enablePhotoScanSSE` | Uses Server-Sent Events (SSE) for photo scan progress updates instead of WebSockets. | `true` | `feature.enablePhotoScanSSE` |

## Detailed Descriptions

### Cover Selection Strategy (`coverSelectionStrategy`)

*   **Auto (Default):** Uses a quality scoring algorithm considering cover availability, format (Hardcover > Paperback), recency, and data completeness.
*   **Recent:** simply prefers the most recently published edition.
*   **Hardcover:** Prioritizes hardcover editions.
*   **Manual:** Requires user intervention to select an edition.

### V3 Search (`enableV3Search`)

*   **Enabled (Default):** Uses the new V3 API client architecture.
*   **Disabled:** Falls back to the legacy V2 API client.
*   This flag allows for a safe rollout of the V3 client while maintaining a kill-switch if issues arise.

### Workflow Import (`enableWorkflowImport`)

*   **Enabled:** Uses Cloudflare Workflows for ISBN processing, which provides durability and automatic retries on the backend.
*   **Disabled (Default):** Uses the standard immediate processing flow.
*   This is currently an experimental P2 enhancement.

### Photo Scan SSE (`enablePhotoScanSSE`)

*   **Enabled (Default):** Uses HTTP-based Server-Sent Events for real-time progress updates during bookshelf scanning.
*   **Disabled:** Falls back to legacy WebSockets.
*   Migration to SSE is preferred for better compatibility with corporate firewalls and proxies.
