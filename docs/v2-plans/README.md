# BooksTracker v2 - Consolidated Plans

**Created:** November 20, 2025
**Status:** Ready for Implementation
**Sprint 1 Start:** December 2, 2025

---

## Overview

This directory contains the most mature and validated planning documents for BooksTracker v2. These documents have been refined through user research, technical feasibility analysis, and data model reviews.

---

## 📁 Directory Structure

```
docs/v2-plans/
├── README.md                           # This file
├── SPRINT_1_READY.md                   # Sprint 1 implementation readiness checklist
├── QUICK_START.md                      # Quick reference for developers
├── DATA_MODEL_SOUNDNESS.md             # Comprehensive data model review
├── VISUAL_DESIGN_SUMMARY.md            # UI/UX design principles
│
├── sprints/
│   ├── SPRINT_OVERVIEW.md              # All sprints timeline (Sprints 1-16)
│   └── sprint-01-REVISED.md            # Sprint 1 detailed plan (79 hours)
│
├── features/
│   └── book-details-redesign.md        # Bento Box UI redesign spec
│
├── technical-design/
│   ├── reading-sessions.md             # ReadingSession technical spec
│   ├── cascade-metadata.md             # Book enrichment system (47 pages)
│   └── ratings-system.md               # Enhanced ratings (45 pages)
│
└── user-research/
    └── USER_INTERVIEW_INSIGHTS.md      # User interview findings & validation
```

---

## 🚀 Quick Start

### For Developers Starting Sprint 1

1. **Read:** [`SPRINT_1_READY.md`](SPRINT_1_READY.md) - Implementation readiness checklist
2. **Review:** [`sprints/sprint-01-REVISED.md`](sprints/sprint-01-REVISED.md) - Detailed Sprint 1 plan
3. **Context:** [`DATA_MODEL_SOUNDNESS.md`](DATA_MODEL_SOUNDNESS.md) - Data model soundness review
4. **Design:** [`VISUAL_DESIGN_SUMMARY.md`](VISUAL_DESIGN_SUMMARY.md) - UI/UX patterns

### For Product Planning

1. **Roadmap:** [`sprints/SPRINT_OVERVIEW.md`](sprints/SPRINT_OVERVIEW.md) - Full 16-sprint timeline
2. **User Research:** [`user-research/USER_INTERVIEW_INSIGHTS.md`](user-research/USER_INTERVIEW_INSIGHTS.md)
3. **Priorities:** [`DATA_MODEL_SOUNDNESS.md`](DATA_MODEL_SOUNDNESS.md#top-5-priorities)

### For AI Agents

1. **Context:** [`QUICK_START.md`](QUICK_START.md) - Quick reference
2. **Sprint 1 Tasks:** [`sprints/sprint-01-REVISED.md`](sprints/sprint-01-REVISED.md#task-breakdown)
3. **Technical Specs:** [`technical-design/`](technical-design/)

---

## 🎯 Sprint 1 Priorities (Dec 2-13, 2025)

### **1. EnhancedDiversityStats** (User's #1 Priority)
- Representation Radar chart (5-7 diversity dimensions)
- "Ghost state" UI for missing data (dashed lines + "+" icons)
- Progressive profiling integration
- Diversity completion gamification

**User Quote:**
> "Diversity stats are #1 - they feed my recommendations greatly. Radar chart is very clear, love the '+' callout."

---

### **2. ReadingSession Tracking** (Original Sprint 1)
- Timer UI in WorkDetailView
- Session lifecycle management (start/stop/persist)
- Reading pace analytics
- Post-session progressive prompts

**User Quote:**
> "Very important - I'd use this daily. Happy to help with progressive profiling prompts."

---

## 📊 Key Metrics

- **Sprint 1 Duration:** 2 weeks (Dec 2-13)
- **Estimated Effort:** 79 hours
- **New SwiftData Models:** 2 (EnhancedDiversityStats, ReadingSession)
- **New Services:** 2 (DiversityStatsService, ReadingSessionService)
- **New UI Components:** 4 (RadarChart, ProgressivePrompt, CompletionWidget, SessionTimer)
- **User Stories:** 10 (6 diversity stats + 4 reading sessions)

---

## 🔗 Related Documentation

- **Main Project Guide:** [`AGENTS.md`](../../AGENTS.md)
- **Claude Code Setup:** [`CLAUDE.md`](../../CLAUDE.md)
- **API Contract:** [`docs/API_CONTRACT.md`](../API_CONTRACT.md)
- **Full v2 Ideation:** [`.ai/v2-ideation/`](../../.ai/v2-ideation/)

---

## 📝 Document Status

| Document | Status | Completeness | Validated |
|----------|--------|--------------|-----------|
| SPRINT_1_READY.md | ✅ Ready | 100% | Yes (User research) |
| sprint-01-REVISED.md | ✅ Ready | 100% | Yes (User interview) |
| DATA_MODEL_SOUNDNESS.md | ✅ Complete | 100% | Yes (Technical review) |
| USER_INTERVIEW_INSIGHTS.md | ✅ Complete | 100% | Yes (Nov 20, 2025) |
| VISUAL_DESIGN_SUMMARY.md | ✅ Complete | 100% | Yes (User validated) |
| cascade-metadata.md | ✅ Complete | 100% | No (Sprint 2) |
| ratings-system.md | ✅ Complete | 100% | No (Sprint 3) |
| reading-sessions.md | ✅ Complete | 100% | Yes (Sprint 1) |

---

## 🎨 Design Philosophy (v2)

### Core Principles

1. **Visual Hierarchy:** Most important information surfaced first
2. **Modularity:** Different data types in dedicated, scannable modules
3. **Progressive Disclosure:** Hide complexity, reveal on demand
4. **Data Visualization:** Charts and badges over text lists
5. **Contextual Actions:** Actions appear when relevant

### Key Visual Patterns

- **Bento Box Layout:** Modular 2x2 grid for book details
- **Representation Radar:** 5-7 axis spider/radar chart for diversity
- **Progressive Profiling:** Contextual prompts (not upfront forms)
- **Gamification:** Progress rings, curator badges, completion percentage

---

## ✅ Validation Summary

### User Research (Nov 20, 2025)

**Interviewee:** Target user (product owner persona)

**Key Findings:**
- ✅ Diversity stats are #1 priority ("feed my recommendations greatly")
- ✅ Representation Radar chart design validated ("very clear")
- ✅ "Ghost state" UI approved ("love the '+' callout")
- ✅ Reading session tracking validated ("I'd use this daily")
- ✅ Progressive profiling acceptance confirmed ("happy to help")
- ✅ Gamification motivating ("yes, very motivating")

**Deprioritized:**
- ❌ Annotations → Renamed to "Book Enrichment System" (Sprint 2)
- ❌ Social features → Moved to Phase 3
- ❌ AI recommendations → Moved to Phase 4

---

## 🏗️ Implementation Workflow

### Sprint 1 Workflow

1. **Week 1:** Implementation & unit tests (40 hours)
   - Diversity stats (24h)
   - Reading sessions (16h)

2. **Week 2:** Integration, polish & validation (39 hours)
   - Integration testing (16h)
   - UI polish & accessibility (12h)
   - User acceptance testing (8h)
   - Documentation (3h)

3. **Deliverables:**
   - ✅ Working Representation Radar chart
   - ✅ Progressive profiling prompts
   - ✅ Reading session timer
   - ✅ Diversity completion gamification
   - ✅ 161+ tests passing (including new tests)
   - ✅ Zero warnings (Swift 6 concurrency)

---

## 📚 Additional Resources

### iOS 26 API Opportunities

**High Value:**
- **Chart3DView:** 3D diversity radar evolution (temporal insights)
- **RichTextEditor:** Formatted book annotations
- **SFSymbolsView:** Animated progress icons

**Future Consideration:**
- **NewTabView:** Bottom accessories for quick actions
- **ListSectionIndexLabel:** Enhanced library navigation

See: [iOS 26 Analysis](../../.ai/ios26-analysis.md) (if created)

---

**Last Updated:** November 20, 2025
**Maintained by:** oooe (jukasdrj)
**Branch:** `feature/v2-diversity-reading-sessions`
**Next Milestone:** Sprint 1 Kickoff (Dec 2, 2025)
