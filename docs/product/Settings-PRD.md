# Settings - Product Requirements Document

**Status:** Shipped
**Owner:** iOS Engineering Team
**Target Release:** v3.0.0 (Build 47+)
**Last Updated:** October 31, 2025

---

## Executive Summary

Settings provides app customization (themes, AI provider, experimental features, Library Reset) via a gear icon in the Library tab toolbar. Following iOS 26 HIG (4-tab maximum), Settings uses sheet presentation rather than a dedicated tab.

---

## Problem Statement

**User Need:** Customize themes, enable beta features, reset library data.  
**Solution:** Accessible Settings sheet with 5 themes, Gemini AI selection, feature flags, and comprehensive Library Reset.

---

## Success Metrics

- ✅ Settings accessible in <2 taps (Library → Gear icon)
- ✅ Theme changes apply immediately (no restart)
- ✅ Feature flags respected throughout app

---

## User Stories

**As a** user, **I want to** change app theme **so that** it matches my aesthetic.  
**As a** developer, **I want to** reset library **so that** I can test imports with fresh data.

---

## Key Features

### 5 Built-In Themes
- Liquid Blue, Cosmic Purple, Forest Green, Sunset Orange, Moonlight Silver
- Instant switching (no restart)
- WCAG AA contrast compliance

### Library Reset
- Deletes all Works, Editions, Authors, UserLibraryEntries
- Cancels in-flight backend enrichment jobs
- Clears search history, enrichment queue, feature flags

### AI Provider Selection
- Gemini 2.0 Flash (default)
- Settings → AI & Scanning

---

## Success Criteria (Shipped)

- ✅ Settings in Library toolbar (not tab bar)
- ✅ 5 themes with immediate switching
- ✅ Library Reset with backend job cancellation
- ✅ Sheet presentation (iOS 26 HIG compliant)

---

**Status:** ✅ Shipped in v3.0.0 (Build 47+)
