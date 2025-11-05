# AI Context Files - Organization Guide

## Current Setup

You have multiple AI-specific context files:
- `CLAUDE.md` - Claude Code development guide
- `GEMINI.md` - Gemini API configuration
- `copilot.md` (if exists) - GitHub Copilot instructions
- `jules.md` (if exists) - Jules-specific context

## Recommended Structure

Based on community best practices and emerging standards:

### Option 1: Unified `.ai/` Directory (Recommended)
```
.ai/
├── README.md           # This file - explains structure
├── context.md          # Shared context for all AI tools
├── claude.md           # Claude Code specific
├── copilot.md          # GitHub Copilot specific
├── gemini.md           # Gemini API specific
├── jules.md            # Jules specific
└── cursorrules         # Cursor IDE rules (if using Cursor)
```

**Benefits:**
- Clean root directory
- Clear AI-specific namespace
- Easy to .gitignore if needed
- Scales as more AI tools emerge

### Option 2: Root-Level Tool-Specific (Current)
```
/
├── CLAUDE.md           # Keep in root (high visibility)
├── GEMINI.md           # API config (root for quick access)
├── .copilot/           # Copilot-specific directory
│   └── instructions.md
├── .cursor/            # Cursor-specific directory
│   └── cursorrules
└── .jules/             # Jules-specific directory
    └── context.md
```

**Benefits:**
- High visibility for primary tool (CLAUDE.md)
- Tool-specific directories follow their conventions
- No migration needed

### Option 3: Hybrid (Best for Your Project)
```
/
├── CLAUDE.md           # Primary dev guide (keep in root)
├── .ai/                # Shared AI context
│   ├── SHARED_CONTEXT.md  # Common project knowledge
│   ├── gemini-config.md   # Gemini API setup
│   ├── copilot-context.md # Copilot instructions
│   └── jules-context.md   # Jules instructions
└── .github/
    └── copilot-instructions.md  # If using GitHub Copilot
```

**Rationale for Your Project:**
- `CLAUDE.md` stays in root (you use Claude Code as primary)
- Gemini context moves to `.ai/` (it's API config, not dev guide)
- Other AI tool contexts consolidated in `.ai/`
- Clean root, clear hierarchy

## Industry Standards (Emerging)

### 1. **Anthropic (Claude Code)**
- **Convention:** `CLAUDE.md` in root
- **Alternative:** `.claude/` directory
- **Your Setup:** ✅ Correct (`CLAUDE.md` in root)

### 2. **GitHub Copilot**
- **Convention:** `.github/copilot-instructions.md`
- **Alternative:** `copilot.md` in root
- **Docs:** https://docs.github.com/en/copilot/customizing-copilot/adding-custom-instructions-for-github-copilot

### 3. **Cursor IDE**
- **Convention:** `.cursorrules` or `.cursor/rules`
- **Docs:** https://cursor.sh/docs

### 4. **Codeium**
- **Convention:** `.codeium/` directory
- **Alternative:** `codeium.md` in root

### 5. **JetBrains AI**
- **Convention:** `.idea/ai-context.md`

### 6. **Gemini**
- **Your Setup:** `GEMINI.md` (API config, not context)
- **Recommendation:** Move to `.ai/gemini-config.md` or keep as API keys reference

## Shared Context Pattern

Many projects are converging on this pattern:

```markdown
<!-- .ai/SHARED_CONTEXT.md -->
# Project Context (All AI Tools)

## Tech Stack
- Swift 6.2 + SwiftUI
- SwiftData + CloudKit
- Cloudflare Workers (backend)

## Architecture Principles
- @Observable for state (no ViewModels)
- Swift 6 concurrency (@MainActor, actors)
- Insert-before-relate pattern for SwiftData

## Critical Rules
- Zero warnings policy
- @Bindable for SwiftData in child views
- No Timer.publish in actors

<!-- Then tool-specific files reference this -->
```

Then each tool's file includes tool-specific instructions:
- Claude: MCP setup, slash commands, skills
- Copilot: Inline suggestion preferences
- Gemini: API endpoints, rate limits

## Migration Plan for Your Project

### Phase 1: Create `.ai/` Directory
```bash
mkdir -p .ai
```

### Phase 2: Move Tool-Specific Configs
```bash
mv GEMINI.md .ai/gemini-config.md
# Keep CLAUDE.md in root (primary tool)
```

### Phase 3: Extract Shared Context
Create `.ai/SHARED_CONTEXT.md` with:
- Tech stack overview
- Architecture patterns
- Critical rules (from CLAUDE.md sections)

### Phase 4: Update CLAUDE.md
Add reference at top:
```markdown
**See also:** `.ai/SHARED_CONTEXT.md` for project-wide AI context
```

### Phase 5: Add `.gitignore` (Optional)
```
# Exclude personal AI configs
.ai/*-local.md
.ai/api-keys.md
```

## Recommended for BooksTrack

Given your project uses Claude Code as primary:

**Keep:**
- `CLAUDE.md` in root (primary development guide)

**Move:**
- `GEMINI.md` → `.ai/gemini-config.md`
- `copilot.md` → `.github/copilot-instructions.md` (if it exists)
- `jules.md` → `.ai/jules-context.md` (if it exists)

**Create:**
- `.ai/SHARED_CONTEXT.md` (extracted from CLAUDE.md)

**Result:**
```
/
├── CLAUDE.md              ← Primary dev guide (keep here)
├── .ai/
│   ├── README.md          ← This guide
│   ├── SHARED_CONTEXT.md  ← Common AI context
│   ├── gemini-config.md   ← API setup
│   └── jules-context.md   ← Jules instructions
└── .github/
    └── copilot-instructions.md  ← Copilot-specific
```

## Community Resources

- **Anthropic Claude Docs:** https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/use-system-prompt
- **GitHub Copilot Custom Instructions:** https://docs.github.com/en/copilot/customizing-copilot
- **AI Context Best Practices:** https://github.com/ai-context-best-practices (community repo)
- **.cursorrules Examples:** https://github.com/PatrickJS/awesome-cursorrules

## Bottom Line

**No universal standard yet**, but patterns emerging:
1. Primary AI tool context in root (you: `CLAUDE.md` ✅)
2. Tool-specific configs in `.github/`, `.ai/`, or tool directories
3. Shared context extracted to `.ai/SHARED_CONTEXT.md`
4. API keys/configs separate from context (security)

**Your project is well-structured already.** Consider:
- Move `GEMINI.md` to `.ai/` (it's API config, not dev guide)
- Keep `CLAUDE.md` in root (primary tool)
- Create `.ai/SHARED_CONTEXT.md` if you add more AI tools

---

**Last Updated:** November 5, 2025
**References:** Anthropic docs, GitHub Copilot docs, community best practices
