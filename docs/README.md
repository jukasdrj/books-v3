# BooksTrack Documentation Hub

**Version 3.7.5 (Build 189+)** | **Last Updated: January 2026**

Welcome to the central documentation for BooksTrack V3. This directory contains all product, technical, and process documentation for the project.

## 🚀 Getting Started

- **[AGENTS.md](../AGENTS.md)** - Universal AI agent guide (code style, architecture, contracts)
- **[CLAUDE.md](../CLAUDE.md)** - Claude Code workflows, MCP setup, testing commands
- **[TODO.md](../TODO.md)** - Current sprint tasks and priorities

---

## 📂 Directory Structure

### `docs/product/`
**Product Requirements (PRDs).** The "Why" and "What" of features.
- `Library-Management-PRD.md` - Core library functionality.
- `Diversity-Insights-PRD.md` - Analytics & representation logic.
- `Bookshelf-AI-Scanner-PRD.md` - Vision-based bulk import.
- `CSV-Import-PRD.md` - Data migration capabilities.
- ...and more.

### `docs/features/`
**Implementation Details.** The "How" of specific features, bridging PRDs and code.
- `FEATURE_FLAGS.md` - Active feature flags and configuration.
- `book-details-redesign.md` - V3 detail view architecture.

### `docs/architecture/`
**System Design.** High-level technical decisions and patterns.
- `cascade-metadata.md` - How we merge data from multiple providers.
- `ratings-system.md` - Logic behind user ratings.
- `reading-sessions.md` - Timer & session state management.
- `VISUAL_DESIGN_SUMMARY.md` - iOS 26 Liquid Glass design system.

### `docs/api/`
**API Specifications.**
- `openapi-v3.json` - Current V3 API contract.
- *For authoritative backend docs, see `~/dev_repos/bendv3/docs/`.*

### `docs/workflows/`
**Visual Flows.** Mermaid diagrams describing complex user or data flows.
- See `docs/workflows/README.md` for available workflows and templates.

---

## 🔍 How to Find What You Need

- **"I need to know how the API works."** -> `~/dev_repos/bendv3/docs/` (authoritative source) or `docs/api/openapi-v3.json` (client contract).
- **"I'm building a new feature."** -> Check `docs/product/` for requirements, then `docs/architecture/` for constraints.
- **"I'm fixing a bug in the scanner."** -> Read `docs/product/Bookshelf-AI-Scanner-PRD.md`.
- **"I'm confused about the project structure."** -> Read `AGENTS.md` in the root or `docs/CROSS_REPO.md`.

---

## 🧪 Testing & Development

- **[Safe Testing Guide](./.claude/rules/safe-testing.md)** - Resource management, testing commands
- **[Git Workflows](./.claude/rules/git-workflows.md)** - Commit and PR guidelines
- **[Swift Concurrency Rules](./.claude/rules/swift-concurrency.md)** - Swift 6 patterns

---

## 📝 Editing Documentation

1. **Keep it fresh.** If you change code, update the docs.
2. **Standardize.** Use the templates in `docs/product/PRD-Template.md`.
3. **Move, don't delete.** Move outdated docs to `docs/archive/` rather than deleting them, unless they are dangerously misleading.

---

## 📊 Documentation Health

**Last audit:** January 2026
**Status:** Active development (Q1 2026)

For documentation issues or improvements, update this file and notify the team.
