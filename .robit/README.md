# 📚 BooksTrack AI Development Configuration

**Version:** 3.0.0 (Build 47+)
**iOS:** 26.0+ | **Swift:** 6.2+ | **Updated:** November 13, 2025

This directory contains AI-optimized context and configuration for development tools (Claude Code, GitHub Copilot, Zen MCP, Jules). Designed for BooksTrack but 95% reusable across Swift/iOS projects.

---

## 🎯 Purpose

The `.robit/` directory provides:
- **Structured context** for AI assistants to understand your codebase
- **Reusable patterns** for Swift 6 concurrency, SwiftData, and iOS 26 HIG
- **Consistent workflows** across different AI tools
- **Project-specific rules** that override default AI behaviors

---

## 📁 Directory Structure

```
.robit/
├── README.md                    # This file - overview and usage
├── context.md                   # Codebase structure and key concepts
├── patterns.md                  # Swift 6 best practices and code patterns
├── architecture.md              # System design and architectural decisions
├── prompts/                     # Reusable prompt templates
│   ├── code-review.md          # Code review checklist
│   ├── debug-guide.md          # Systematic debugging approach
│   └── feature-planning.md     # Feature implementation template
├── workflows/                   # AI-assisted development workflows
│   ├── adding-features.md      # How to add new features
│   ├── refactoring.md          # Safe refactoring patterns
│   └── testing.md              # Test generation guidelines
└── reference/                   # Quick reference materials
    ├── swiftdata-patterns.md   # SwiftData best practices
    ├── concurrency-rules.md    # Swift 6 concurrency checklist
    └── ios26-hig.md            # iOS 26 HIG compliance

```

---

## 🚀 Quick Start

### For AI Assistants (Auto-Loaded)

When you open this project in Claude Code, GitHub Copilot, or other AI tools, they should automatically:
1. Read `context.md` to understand the codebase
2. Reference `patterns.md` for code standards
3. Consult `architecture.md` for design decisions

### For Developers

**Use prompts for common tasks:**
```bash
# Code review with AI
# Reference: .robit/prompts/code-review.md

# Plan new feature
# Reference: .robit/prompts/feature-planning.md

# Debug systematic issue
# Reference: .robit/prompts/debug-guide.md
```

**Check patterns before coding:**
- Swift 6 concurrency: `.robit/reference/concurrency-rules.md`
- SwiftData models: `.robit/reference/swiftdata-patterns.md`
- iOS 26 HIG: `.robit/reference/ios26-hig.md`

---

## 🤖 AI Tool Integration

### Claude Code
- Reads all `.robit/*.md` files automatically
- Uses `context.md` for codebase understanding
- References `patterns.md` for code generation
- Consults `CLAUDE.md` (root) for project-specific overrides

### GitHub Copilot
- Uses `.robit/patterns.md` for inline suggestions
- References `.github/copilot-instructions.md` (if exists)
- Respects Swift 6 concurrency patterns

### Zen MCP
- Multi-model AI with specialized tools
- Uses `.robit/architecture.md` for system-level analysis
- Consults `.zen/conf/providers.yml` for model selection

### Jules (GitHub)
- PR reviews reference `.robit/prompts/code-review.md`
- Uses context for architectural feedback
- Integrates with GitHub Issues/Projects

---

## 📚 Key Files Explained

### `context.md` - Codebase Overview
**Purpose:** Help AI understand your project structure, dependencies, and domain logic.

**Contains:**
- Project architecture (SwiftUI + SwiftData + Cloudflare Workers)
- Core entities (Work, Edition, Author, UserLibraryEntry)
- Key services (EnrichmentQueue, LibraryRepository, etc.)
- Navigation structure (4-tab layout)
- Backend integration (Cloudflare Workers API)

**When to update:**
- New major feature added
- Architecture changes
- New dependencies added
- Navigation structure modified

---

### `patterns.md` - Code Standards
**Purpose:** Enforce Swift 6 best practices and project-specific patterns.

**Contains:**
- Swift 6 concurrency rules (`@MainActor`, actors, `nonisolated`)
- SwiftData patterns (relationships, CloudKit sync)
- State management (`@Observable`, `@State`, `@Bindable`)
- iOS 26 HIG compliance (navigation, accessibility)
- Zero-warning policy enforcement

**When to update:**
- New coding standard adopted
- Common bug pattern discovered
- iOS/Swift version upgrade
- Team consensus on best practice

---

### `architecture.md` - System Design
**Purpose:** Document high-level decisions and trade-offs.

**Contains:**
- Data flow diagrams
- Service layer architecture
- Backend API contracts
- Performance optimizations
- Security patterns

**When to update:**
- Major refactoring completed
- New backend endpoint added
- Architectural decision made
- Performance bottleneck solved

---

## 🔄 Exporting to Other Projects

This `.robit/` configuration is designed for **95% reusability** across Swift/iOS projects.

### Universal Files (100% reusable)
- `README.md` (this file) - Minimal changes needed
- `prompts/` - Language-agnostic templates
- `workflows/` - General development workflows

### Swift-Specific Files (95% reusable)
- `patterns.md` - Update for project-specific conventions
- `reference/swiftdata-patterns.md` - Reuse if using SwiftData
- `reference/concurrency-rules.md` - Universal Swift 6 rules

### Project-Specific Files (80% reusable)
- `context.md` - Replace with your project structure
- `architecture.md` - Document your system design

### Export Steps
1. Copy entire `.robit/` directory to new project
2. Update `context.md` with new project structure
3. Review `patterns.md` for project-specific conventions
4. Update `architecture.md` with new system design
5. Keep `prompts/` and `workflows/` as-is (universal)

**Estimated export time:** 30-60 minutes

---

## 📖 Documentation Hierarchy

This project uses a **layered documentation strategy**:

```
📄 CLAUDE.md (root)              ← Active development quick reference (<500 lines)
📄 .robit/context.md             ← AI context (codebase structure)
📄 .robit/patterns.md            ← Code standards (Swift 6, iOS 26)
📄 .robit/architecture.md        ← System design (high-level decisions)
📁 docs/                         ← Human-readable documentation
   ├── product/                  ← PRDs (why features exist)
   ├── workflows/                ← Mermaid diagrams (visual flows)
   ├── features/                 ← Implementation details
   └── architecture/             ← Architectural decision records
```

**Rule of thumb:**
- **AI reads:** `.robit/*` + `CLAUDE.md`
- **Humans read:** `docs/*` + `CLAUDE.md`
- **Both read:** `CLAUDE.md` (single source of truth for active standards)

---

## 🛠️ Maintenance

### Weekly
- [ ] Review AI-generated code for pattern compliance
- [ ] Update `patterns.md` if new standards emerge

### Monthly
- [ ] Sync `context.md` with major feature changes
- [ ] Archive outdated patterns to `docs/archive/`

### Per Release
- [ ] Update version numbers in this README
- [ ] Document new architectural decisions in `architecture.md`
- [ ] Verify all `.robit/reference/*` files are current

---

## 🆘 Troubleshooting

### AI not following project patterns?
1. Check if `CLAUDE.md` (root) has conflicting instructions
2. Verify `.robit/patterns.md` is clear and specific
3. Add examples to patterns if AI misunderstands

### AI generating incorrect architecture?
1. Update `.robit/architecture.md` with constraints
2. Add "CRITICAL" or "NEVER" markers for hard rules
3. Document trade-offs and rationale

### Export to new project not working?
1. Verify target project has similar structure (Swift/iOS)
2. Update `context.md` first (highest impact)
3. Adapt `patterns.md` to target language conventions

---

## 🎯 Best Practices

### For AI Assistants
- **Always read** `context.md` before suggesting code
- **Reference** `patterns.md` for Swift 6 compliance
- **Consult** `architecture.md` for system constraints
- **Defer to** `CLAUDE.md` (root) for overrides

### For Developers
- **Update** `.robit/*` when project evolves
- **Review** AI suggestions against patterns
- **Document** new patterns as they emerge
- **Export** configuration to new projects for consistency

### For Teams
- **Sync** `.robit/patterns.md` across projects
- **Share** prompts in `.robit/prompts/`
- **Version** configuration changes with git
- **Review** AI-generated code for compliance

---

## 📦 Related Files

- **Root:** `CLAUDE.md` - Project-specific overrides and active standards
- **Root:** `MCP_SETUP.md` - XcodeBuildMCP workflows
- **Docs:** `docs/README.md` - Human-readable documentation hub
- **GitHub:** `.github/copilot-instructions.md` - Copilot configuration
- **AI:** `.ai/SHARED_CONTEXT.md` - Alternative AI context format

---

## 🌟 What Makes This Setup Special

### 1. **Multi-AI Compatibility**
- Works with Claude Code, Copilot, Zen MCP, Jules
- No vendor lock-in
- Consistent behavior across tools

### 2. **95% Reusable**
- Export to any Swift/iOS project in 30-60 minutes
- Language-agnostic prompts and workflows
- Project-specific files clearly marked

### 3. **Living Documentation**
- Git-versioned configuration
- Evolves with project
- Team consensus enforced

### 4. **Zero Boilerplate**
- No repeated context in every prompt
- AI reads once, remembers project structure
- Faster, more accurate code generation

---

## 🚀 Next Steps

### For This Project
1. ✅ `.robit/` configuration complete
2. ⏳ Train team on AI workflows
3. ⏳ Monitor AI adherence to patterns
4. ⏳ Refine patterns based on feedback

### For Other Projects
1. Copy `.robit/` directory
2. Update `context.md` (30 min)
3. Review `patterns.md` (15 min)
4. Test with AI assistant (15 min)
5. Enjoy consistent AI assistance!

---

**Last Updated:** November 13, 2025
**Maintainer:** BooksTrack Team
**License:** MIT (configuration only, not app code)
**Status:** ✅ Production-Ready
