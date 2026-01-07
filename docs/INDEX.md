# BooksTrack Documentation Index

**Version 3.7.5 (Build 189+)** | **Last Updated: January 6, 2026**

Quick navigation hub for all BooksTrack documentation.

---

## 🚀 Getting Started

- **[README.md](../README.md)** - Project overview, features, requirements
- **[AGENTS.md](../AGENTS.md)** - Universal AI agent guide (code style, architecture, contracts)
- **[CLAUDE.md](../CLAUDE.md)** - Claude Code workflows, MCP setup, testing commands
- **[TODO.md](../TODO.md)** - Current sprint tasks and priorities

---

## 📋 Product Documentation

- **[Product Docs](./product/)** - Product requirements, roadmaps, feature specs
- **[Flutter Parity Matrix](./product/FLUTTER_PARITY.md)** - iOS vs Flutter feature map
- **[Feature Flags](./features/FEATURE_FLAGS.md)** - Feature flag documentation
- **[Project Status](./project/STATUS.md)** - Active sprint progress and blockers

---

## 🏗️ Architecture & Design

- **[Architecture Docs](./architecture/)** - System design, technical decisions
- **[API Specs](./api/)** - Local OpenAPI specifications
- **[Workflows](./workflows/)** - Mermaid diagrams for complex flows
- **[Visual Design](./architecture/VISUAL_DESIGN_SUMMARY.md)** - iOS 26 Liquid Glass design system

---

## 🔌 Integration & APIs

- **[Cross-Repository Architecture](./CROSS_REPO.md)** - Multi-repo system overview
- **[bendv3 API Documentation](~/dev_repos/bendv3/docs/)** - REST API, WebSocket, contracts
- **[alex Metadata Service](~/dev_repos/alex/)** - Book metadata and cover images

---

## 🧪 Testing & Development

- **[Safe Testing Guide](../.claude/rules/safe-testing.md)** - Resource management, testing commands
- **[Git Workflows](../.claude/rules/git-workflows.md)** - Commit and PR guidelines
- **[Swift Concurrency Rules](../.claude/rules/swift-concurrency.md)** - Swift 6 patterns

---

## 📚 Reference

- **[CHANGELOG.md](../CHANGELOG.md)** - Version history and release notes
- **[Archive](../archive/)** - Deprecated docs, completed PRs, old planning files

---

## 🔍 Quick Search Tips

**Find by topic:**
- **Testing:** `grep -r "test" docs/ .claude/rules/`
- **API contracts:** Check `docs/api/` (local) or `~/dev_repos/bendv3/docs/` (backend)
- **Feature specs:** `docs/product/*.md`
- **Architecture decisions:** `docs/architecture/*.md`

**Cross-repo documentation:**
- **bendv3:** `~/dev_repos/bendv3/CLAUDE.md` and `~/dev_repos/bendv3/docs/`
- **alex:** `~/dev_repos/alex/CLAUDE.md`
- **Shared knowledge:** `~/.claude/knowledge-base/`

---

## 📊 Documentation Health

Last audit: **January 6, 2026**
Status: **Active development** (Q1 2026)

For documentation issues or improvements, update this index and notify the team.
