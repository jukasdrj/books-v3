# BooksTracker v3 - iOS Book Tracking with Cultural Diversity Insights

**Version:** 3.7.5 (Build 189)
**Branch:** `main`
**iOS:** 26.0+ | **Swift:** 6.2+ | **Xcode:** 16.1+

---

## 🎯 Overview

BooksTracker is a native iOS app for managing your personal book library with deep cultural diversity insights. Built with SwiftUI, SwiftData, and CloudKit sync, it helps readers discover patterns in their reading through visual analytics and intelligent recommendations.

**Key Features:**
- 📚 **Smart Library Management** - SwiftData-powered local storage with CloudKit sync
- 🌍 **Diversity Analytics** - 5-dimension representation tracking with radar chart visualization
- ⏱️ **Reading Sessions** - Timer tracking with progressive profiling for enrichment
- 📖 **Multi-Edition Support** - Track different editions of the same work
- 🔍 **Intelligent Search** - Multi-provider API orchestration (Google Books + OpenLibrary)
- 📸 **Bookshelf Scanning** - VisionKit + Gemini Vision for bulk ISBN extraction
- ☁️ **Cloudflare Backend** - Workers + D1 + Durable Objects for real-time sync

---

## 🚀 Current Status

### ✅ Sprint 1: Diversity Stats + Reading Sessions (100% Complete)

**Shipped in PR #1 (Nov 21, 2025)**

**Models & Schema:**
- `EnhancedDiversityStats` - 5-dimension diversity tracking (cultural origin, gender, translation, own voices, accessibility)
- `ReadingSession` - Timer tracking with progressive profiling hooks
- `UserLibraryEntry` updated with reading session relationships
- Schema migration for v2 models

**Services:**
- `DiversityStatsService` - Calculate/update diversity metrics with completion percentages
- `ReadingSessionService` - @MainActor session lifecycle management
- `SessionAnalyticsService` - Cascade metadata aggregation

**UI Components:**
- `RepresentationRadarChart` - Canvas-based 5-axis visualization with ghost state
- Timer UI in `EditionMetadataView` - Live MM:SS counter with session tracking
- `ProgressiveProfilingPrompt` - Post-session questionnaire (3-5 questions)
- `DiversityCompletionWidget` - Progress ring with dimension breakdown

**Testing:**
- 15 unit tests (ReadingSession, EnhancedDiversityStats)
- 11 integration tests (DiversitySessionIntegration)
- Performance tests for radar chart (<200ms P95)

---

## 📋 What's Next

### Sprint 2: Cascade Metadata & Session Analytics (NEXT)

**Focus:** Complete metadata enrichment and session analytics

**Planned Features:**
- Complete diversity completion widget integration
- Session analytics aggregation (weekly/monthly trends)
- Real device testing and keyboard input validation
- Documentation updates

### Future Sprints

- **Sprint 3:** API Orchestration layer (KV→D1 migration)
- **Sprint 4:** Intelligence v2 (Gemini-powered recommendations)
- **Phase 2:** Multi-user support and social features

See `docs/v2-plans/` for detailed sprint planning.

---

## 🏗️ Architecture

**Tech Stack:**
- **Frontend:** SwiftUI, SwiftData, CloudKit
- **Backend:** Cloudflare Workers, D1 (SQLite), Durable Objects, KV
- **APIs:** Google Books, OpenLibrary, Gemini Vision
- **Build:** Swift 6.2, iOS 26 SDK, Xcode 16.1

**Project Structure:**
```
BooksTracker/
├── BooksTrackerPackage/         # Swift Package (154 files)
│   ├── Sources/
│   │   └── BooksTrackerFeature/ # Main feature code
│   │       ├── Models/          # SwiftData models
│   │       ├── Services/        # Business logic actors
│   │       ├── Views/           # SwiftUI views
│   │       └── ...
│   └── Tests/                   # Unit + integration tests
├── BooksTracker/                # App target
├── BooksTrackerWidgets/         # Widget extension
├── Config/                      # Build configuration
└── docs/                        # Documentation
    ├── prd/                     # Product requirements (17 PRDs)
    ├── v2-plans/                # Sprint planning
    └── architecture/            # Technical docs
```

---

## 🛠️ Development Setup

### Prerequisites

- macOS 15.1+
- Xcode 16.1+
- iOS 26.0 SDK
- Swift 6.2+

### Quick Start

1. **Clone repository:**
   ```bash
   git clone <repo-url>
   cd bfrontv3-swift
   ```

2. **Open workspace:**
   ```bash
   open BooksTracker.xcworkspace
   ```

3. **Build and run:**
   - Select scheme: `BooksTracker`
   - Target: iPhone 17 Pro Max Simulator (or real device)
   - Press ⌘R to build and run

### Claude Code Setup

This project uses Claude Code with MCP servers for AI-assisted development.

**Slash Commands:**
```bash
/build         # Quick build validation using xcodebuild
/test          # Run Swift Testing suite
/sim           # Launch app in iOS Simulator with log streaming
/device-deploy # Deploy to connected iPhone/iPad
```

See `CLAUDE.md` for complete Claude Code workflow documentation.

---

## 🧪 Testing

**Run all tests:**
```bash
/test
```

**Manual testing checklist:**
- ✅ Build succeeds with zero warnings (`-Werror` enforced)
- ✅ SwiftData models persist correctly
- ✅ Radar chart renders at 60fps
- ✅ Timer UI updates in real-time
- ✅ Keyboard input works on real device (iOS 26 regression!)
- ✅ CloudKit sync functional

---

## 📖 Documentation

**For AI Agents:**
- `AGENTS.md` - Universal AI agent guide (tech stack, architecture, critical rules)
- `CLAUDE.md` - Claude Code-specific setup (MCP, slash commands, workflows)
- `.github/copilot-instructions.md` - GitHub Copilot configuration

**For Developers:**
- `docs/prd/` - 17 Product Requirement Documents
- `docs/v2-plans/` - Sprint planning and technical design
- `docs/architecture/` - System architecture documentation
- `CHANGELOG.md` - Complete change history

---

## 🎨 Design System

**iOS 26 Liquid Glass:**
- Glass morphism with ultra-thin materials
- Adaptive cards with depth + vibrancy
- Aurora gradients for visual interest
- WCAG AA contrast compliance (4.5:1+ ratio)

**Theme System:**
- Dynamic type support
- Dark mode optimization
- Accessibility-first design
- Haptic feedback integration

---

## 🔒 Zero Warnings Policy

This project enforces **zero warnings** at build time:
- Warnings treated as errors (`-Werror`)
- Swift 6 concurrency compliance
- No deprecated APIs
- No unused variables

**PR Checklist:**
- [ ] Build succeeds with zero warnings
- [ ] Swift 6 concurrency compliance verified
- [ ] @Bindable used for SwiftData models in child views
- [ ] No `Timer.publish` in actors (use `Task.sleep`)
- [ ] WCAG AA contrast validated
- [ ] Real device testing completed

---

## 🤝 Contributing

**Branch Strategy:**
- `main` - Production-ready code
- `feature/v2-*` - v2 sprint branches
- `hotfix/*` - Critical fixes

**Commit Conventions:**
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation
- `test:` - Testing
- `chore:` - Maintenance

---

## 📝 License

Proprietary - © 2025 jukasdrj

---

## 🔗 Links

- **Documentation:** `docs/`
- **PRDs:** `docs/prd/`
- **Sprint Plans:** `docs/v2-plans/sprints/`
- **API Contract:** `docs/architecture/api-contract-v2.4.1.md`

---

**Generated with [Claude Code](https://claude.com/claude-code)**
