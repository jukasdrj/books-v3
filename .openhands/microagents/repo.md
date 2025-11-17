---
name: BooksTracker Repository Agent
type: knowledge
version: 1.0.0
agent: CodeActAgent
---

# Repository Purpose

BooksTracker is a modern iOS book tracking application with cultural diversity insights, powered by SwiftUI and SwiftData. The app allows users to track their reading journey, discover diverse voices, and gain insights into their literary preferences. It features AI-powered bookshelf scanning, ISBN barcode scanning, CSV import capabilities, and comprehensive reading analytics.

**Key Features:**
- Smart library management with Work/Edition architecture
- AI-powered bookshelf scanner using Gemini 2.5 Flash
- ISBN barcode scanning with VisionKit
- Cultural diversity analytics and reading statistics
- CloudKit sync across Apple devices
- Modern iOS 26 design with accessibility compliance

# Setup Instructions

**Prerequisites:**
- Xcode 16.0+
- iOS 26.0+ SDK
- Swift 6.2+
- Apple Developer Account (for device testing)

**To set up the project:**
1. Clone the repository: `git clone https://github.com/jukasdrj/books_tracker_v1.git`
2. Open the Xcode workspace: `open BooksTracker.xcworkspace`
3. Configure signing in Xcode (update Team and Bundle Identifier)
4. Build and run with `Cmd + R`

**MCP Commands (if using Claude Code):**
- `/build` - Quick build validation using XcodeBuildMCP
- `/test` - Run Swift Testing suite
- `/sim` - Launch BooksTracker in iOS Simulator with log streaming
- `/device-deploy` - Deploy to connected iPhone/iPad

# Repository Structure

- `/BooksTracker/` - iOS app shell with entry point and assets
- `/BooksTrackerPackage/` - Swift Package containing the main feature module
  - `/Sources/BooksTrackerFeature/` - Core application code
    - `/Models/` - SwiftData models (Work, Edition, Author)
    - `/Views/` - SwiftUI views (Library, Search, Shelf, Insights)
    - `/Services/` - Business logic (API clients, enrichment)
    - `/Utilities/` - Helpers & extensions
  - `/Tests/BooksTrackerFeatureTests/` - Swift Testing suite
- `/BooksTrackerUITests/` - UI test suite
- `/BooksTrackerWidgets/` - iOS widgets extension
- `/docs/` - Comprehensive documentation hub
  - `/product/` - Product requirements and user stories
  - `/workflows/` - Mermaid flow diagrams
  - `/features/` - Technical implementation deep-dives
  - `/architecture/` - System design decisions
  - `/guides/` - How-to guides
- `/Config/` - Configuration files
- `/.github/` - GitHub configuration and templates
  - `/workflows/build.yml.disabled` - CI/CD workflow (currently disabled)
  - `/agents/` - GitHub agent configurations
  - `ISSUE_TEMPLATE.md` - Issue template
  - `copilot-instructions.md` - GitHub Copilot setup
- `/.claude/` - Claude Code-specific configurations and commands
- `/.ai/` - Shared AI context files

**Key Files:**
- `CLAUDE.md` - Claude Code-specific developer quick reference
- `AGENTS.md` - Universal AI agent instructions
- `MCP_SETUP.md` - XcodeBuildMCP workflows and slash commands
- `CHANGELOG.md` - Version history and debugging lessons
- `README.md` - Main project documentation

# CI/CD and Development Practices

**Testing Framework:** Swift Testing with `@Test` and `#expect` syntax
**Code Standards:** 
- Zero warnings policy (Swift 6 strict concurrency)
- WCAG AA compliance (4.5:1+ contrast ratios)
- Use `@MainActor` for UI, `nonisolated` for pure functions
- Insert SwiftData models before setting relationships

**Backend:** Maintained in separate repository (bookstrack-backend) using Cloudflare Workers, Durable Objects, KV Storage, R2 Object Storage, and Gemini 2.5 Flash AI.

**Build Workflow:** The repository has a disabled GitHub Actions workflow (`build.yml.disabled`) that includes build validation, Swift testing, and zero-warnings enforcement for iOS development.

**Development Tools:**
- XcodeBuildMCP for iOS development workflows
- AST-grep for Swift code searches (not ripgrep)
- Swift 6.2+ with strict concurrency
- VisionKit for barcode scanning
- AVFoundation for camera integration