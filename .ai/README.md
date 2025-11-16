# AI Context Files - Organization Guide

**Last Updated:** November 16, 2025

## ✅ Current Structure (AGENTS.md Standard Adopted)

BooksTrack follows the **AGENTS.md open standard** for unified AI agent instructions:

```
/
├── AGENTS.md                    # ⭐ PRIMARY: Universal AI agent guide
├── CLAUDE.md                    # Claude Code-specific (MCP, slash commands)
├── .ai/
│   ├── README.md                # This file - explains structure
│   ├── SHARED_CONTEXT.md        # Reference: Tech stack, architecture
│   └── gemini-config.md         # Gemini API configuration
└── .github/
    └── copilot-instructions.md  # GitHub Copilot setup
```

---

## 📋 What Each File Does

### AGENTS.md (Root) - Universal AI Agent Guide

**Purpose:** Single source of truth for ALL AI coding agents

**Supported Tools:**
- OpenAI Codex/Copilot
- Google Gemini/Jules
- GitHub Copilot
- Cursor
- Claude Code
- Aider, RooCode, Factory Droid, etc.

**Contains:**
- Project overview and tech stack
- Build and test commands
- Critical rules (SwiftData lifecycle, concurrency)
- Code style and conventions
- Backend API contract
- Testing patterns
- Common development tasks
- Security best practices
- Documentation structure

**When to update:**
- Add new features/patterns
- Change tech stack
- Update build/test procedures
- Add critical rules from debugging

---

### CLAUDE.md (Root) - Claude Code-Specific

**Purpose:** Claude Code-specific features and workflows

**Unique to Claude Code:**
- MCP setup and slash commands
- Task tool with specialized agents
- TodoWrite patterns
- Git commit workflow
- PR creation workflow
- Skills and Zen MCP tool usage
- Token budget optimization

**When to update:**
- Add new MCP servers
- Create new slash commands
- Add new specialized agents
- Update Claude Code workflows

---

### .ai/SHARED_CONTEXT.md - Reference Material

**Purpose:** Detailed technical context for AI tools (reference only)

**Contains:**
- Detailed SwiftData model relationships
- Architecture principles
- Critical patterns with examples
- Backend structure details

**Used by:** AGENTS.md extracts content from here

**When to update:**
- Major architecture changes
- New critical patterns discovered
- Backend contract changes

---

### .ai/gemini-config.md - Gemini API Setup

**Purpose:** Gemini API-specific configuration

**Contains:**
- Gemini model selection
- API endpoint configuration
- Rate limiting info
- Feature-specific Gemini usage

**When to update:**
- Gemini model versions change
- API configuration changes
- New Gemini-powered features

---

### .github/copilot-instructions.md - GitHub Copilot

**Purpose:** GitHub Copilot inline suggestion preferences

**Contains:**
- Concise quick reference
- Common crash patterns
- Build/test commands
- Backend repository link

**When to update:**
- Add new common crash patterns
- Update build commands
- Change backend repository

---

## 🎯 Industry Standard: AGENTS.md

**What is AGENTS.md?**
- Open standard from OpenAI (launched 2025)
- "README for agents" - dedicated AI context file
- 20,000+ GitHub repositories adopted it
- Supported by major AI coding tools

**Why AGENTS.md?**
- **Universal compatibility:** Works with ALL AI tools
- **Single source of truth:** No duplication across tool-specific files
- **Clean separation:** Keeps README.md focused on humans
- **Flexible format:** Standard Markdown, no required sections

**Official Spec:** https://agents.md
**GitHub Repo:** https://github.com/openai/agents.md

---

## 📊 Content Distribution

### Universal Content (AGENTS.md)
- ✅ Tech stack overview
- ✅ Build and test commands
- ✅ Critical rules (SwiftData, concurrency, iOS 26 HIG)
- ✅ Code style conventions
- ✅ SwiftData architecture
- ✅ Backend API contract
- ✅ Testing patterns
- ✅ Common development tasks
- ✅ Security checklist
- ✅ Documentation structure

### Tool-Specific Content (CLAUDE.md, copilot-instructions.md)
- ✅ MCP server setup (Claude Code)
- ✅ Slash commands (Claude Code)
- ✅ Task tool agents (Claude Code)
- ✅ Git/PR workflows (Claude Code)
- ✅ Inline suggestion preferences (Copilot)

### Reference Content (.ai/SHARED_CONTEXT.md)
- ✅ Detailed architecture diagrams
- ✅ Extended pattern examples
- ✅ Backend implementation details

---

## 🔄 Workflow: When to Update Which File

### Scenario 1: Adding a New Critical Rule

**Example:** Discovered new SwiftData crash pattern

**Update:**
1. ✅ `AGENTS.md` - Add to "Critical Rules" section
2. ✅ `.ai/SHARED_CONTEXT.md` - Add detailed example
3. ⚠️ `CLAUDE.md` - Only if Claude Code-specific workflow needed
4. ✅ `.github/copilot-instructions.md` - Add to quick reference

---

### Scenario 2: Adding New MCP Server

**Example:** Installed new XcodeBuildMCP command

**Update:**
1. ✅ `CLAUDE.md` - Add to "MCP Commands" section
2. ❌ `AGENTS.md` - No update (Claude Code-specific)
3. ❌ Other files - No update

---

### Scenario 3: Backend API Contract Change

**Example:** New v3 endpoint added

**Update:**
1. ✅ `AGENTS.md` - Update "Backend API Contract" section
2. ✅ `.ai/SHARED_CONTEXT.md` - Update detailed contract
3. ✅ `.ai/gemini-config.md` - Update if Gemini endpoint changed
4. ⚠️ `.github/copilot-instructions.md` - Update if quick reference impacted

---

### Scenario 4: New Feature Implemented

**Example:** Added dark mode toggle

**Update:**
1. ✅ `AGENTS.md` - Add to "Features" section (if major)
2. ⚠️ `.ai/SHARED_CONTEXT.md` - Add pattern if reusable
3. ❌ Tool-specific files - No update (unless MCP/workflow changed)

---

## ✨ Best Practices

### Keep AGENTS.md Lean
- Focus on "what" and "how"
- Link to detailed docs for "why" (use `docs/` for deep-dives)
- ~500-800 lines max (current: ~700)

### Avoid Duplication
- Extract common patterns to `.ai/SHARED_CONTEXT.md`
- Reference SHARED_CONTEXT from AGENTS.md
- Tool-specific files should ONLY contain tool-specific content

### Living Documentation
- Update AGENTS.md when patterns change
- Review after major debugging sessions
- Capture lessons learned immediately

### Versioning
- Track major changes in git history
- Update "Last Updated" date
- Reference version in header

---

## 🔗 Migration from Old Structure (COMPLETED)

**Before (October 2025):**
```
/
├── CLAUDE.md (500+ lines, mixed content)
├── GEMINI.md (Gemini config)
├── .ai/
│   ├── README.md (migration guide)
│   └── SHARED_CONTEXT.md
```

**After (November 2025):**
```
/
├── AGENTS.md (700 lines, universal)        # ⭐ NEW
├── CLAUDE.md (200 lines, Claude-specific)  # ✅ Streamlined
├── .ai/
│   ├── README.md (this guide)              # ✅ Updated
│   ├── SHARED_CONTEXT.md (reference)       # ✅ Kept
│   └── gemini-config.md (API config)       # ✅ Renamed
└── .github/
    └── copilot-instructions.md             # ✅ Kept
```

**Changes Made:**
1. ✅ Created `AGENTS.md` (universal standard)
2. ✅ Streamlined `CLAUDE.md` (Claude Code-specific only)
3. ✅ Renamed `GEMINI.md` → `.ai/gemini-config.md`
4. ✅ Updated `.ai/README.md` (this file)
5. ✅ Extracted universal content to `AGENTS.md`

---

## 📚 Community Resources

- **AGENTS.md Spec:** https://agents.md
- **GitHub Repo:** https://github.com/openai/agents.md
- **Anthropic Claude Docs:** https://docs.anthropic.com
- **GitHub Copilot Docs:** https://docs.github.com/en/copilot/customizing-copilot
- **Cursor Rules Examples:** https://github.com/PatrickJS/awesome-cursorrules

---

## ❓ FAQ

**Q: Should I use AGENTS.md or CLAUDE.md for new instructions?**

A:
- **Universal patterns** (tech stack, architecture, critical rules) → `AGENTS.md`
- **Claude Code workflows** (MCP, Task tool, git/PR) → `CLAUDE.md`

**Q: Do all AI tools support AGENTS.md?**

A: Yes! Major tools (OpenAI, GitHub Copilot, Cursor, Claude Code, Gemini) all read AGENTS.md.

**Q: Can I have multiple AGENTS.md files?**

A: Yes! For monorepos, place AGENTS.md in subdirectories. The closest file to edited code wins.

**Q: Should I delete tool-specific files?**

A: No! Keep `CLAUDE.md`, `copilot-instructions.md`, etc. for tool-specific features that don't belong in universal AGENTS.md.

**Q: How do I keep AGENTS.md from getting too long?**

A:
- Extract detailed examples to `.ai/SHARED_CONTEXT.md`
- Link to `docs/` for deep-dives
- Focus on quick reference, not documentation

---

**Last Updated:** November 16, 2025
**Standard Adopted:** AGENTS.md (https://agents.md)
**Maintained by:** oooe (jukasdrj)
