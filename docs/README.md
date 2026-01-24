# BooksTrack Documentation Hub

**Version 3.7.5 (Build 189+)** | **Last Updated: January 6, 2026**

Welcome to the central documentation for BooksTrack V3. This directory contains all product, technical, and process documentation for the project.

---

## 🚀 Getting Started

- **[README.md](../README.md)** - Project overview, features, requirements
- **[AGENTS.md](../AGENTS.md)** - Universal AI agent guide (code style, architecture, contracts)
- **[CLAUDE.md](../CLAUDE.md)** - Claude Code workflows, MCP setup, testing commands
- **[TODO.md](../TODO.md)** - Current sprint tasks and priorities

---

## 📂 Directory Structure

### `docs/product/`
**Product Requirements (PRDs).** Planned features and backlog items.
- `Reading-Goals-PRD.md` - Set and track reading goals.
- `Series-Tracking-PRD.md` - Manage book series.

### `docs/features/`
**Feature Documentation.** Comprehensive specs for shipped features (What + How).
- **[ISBN_SCANNER.md](./features/ISBN_SCANNER.md)** - Barcode scanning.
- **[BOOKSHELF_SCANNER.md](./features/BOOKSHELF_SCANNER.md)** - Vision-based bulk import.
- **[GEMINI_CSV_IMPORT.md](./features/GEMINI_CSV_IMPORT.md)** - AI-powered CSV import.
- **[LIBRARY_MANAGEMENT.md](./features/LIBRARY_MANAGEMENT.md)** - Core library features.

### `docs/architecture/`
**System Design.** High-level technical decisions and patterns.
- **[dto-mapper.md](./architecture/dto-mapper.md)** - Client-side data mapping.
- **[genre-normalization.md](./architecture/genre-normalization.md)** - Taxonomy rules.
- `VISUAL_DESIGN_SUMMARY.md` - iOS 26 Liquid Glass design system.

### `docs/workflows/`
**Visual Flows.** Mermaid diagrams describing complex user or data flows.

### `docs/archive/`
**Archive.** Deprecated docs, shipped PRDs, and historical references.
- `CSV-Import-PRD.md` (Shipped)
- `Bookshelf-AI-Scanner-PRD.md` (Shipped)
- `openapi-v3.json` (Legacy)

---

## 🔌 Integration & APIs

- **[Cross-Repository Architecture](./CROSS_REPO.md)** - Multi-repo system overview
- **[bendv3 API Documentation](~/dev_repos/bendv3/docs/)** - REST API, WebSocket, contracts (Authoritative Source)
- **[alex Metadata Service](~/dev_repos/alex/)** - Book metadata and cover images

---

## 🔍 How to find what you need

- **"I need to know how the API works."** -> `~/dev_repos/bendv3/docs/`
- **"I'm building a new feature."** -> Check `docs/product/` for requirements, then `docs/architecture/` for constraints.
- **"I'm fixing a bug in the scanner."** -> Read `docs/features/BOOKSHELF_SCANNER.md`.
- **"I'm confused about the project structure."** -> Read `AGENTS.md` in the root.

## 📝 Editing Documentation

1. **Keep it fresh.** If you change code, update the docs immediately.
2. **Standardize.** Use the templates in `docs/product/PRD-Template.md`.
3. **Move, don't delete.** Move outdated docs to `docs/archive/` rather than deleting them.
