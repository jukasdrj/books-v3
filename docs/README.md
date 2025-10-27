# BooksTrack Documentation Hub

**Last Updated:** October 25, 2025

Welcome to the BooksTrack documentation! This guide helps you find the right documentation for your needs.

---

## 📚 Documentation Structure

```
docs/
├── product/              # Product Requirements (WHY & WHAT)
├── workflows/            # Visual Workflow Diagrams (HOW - Visual)
├── features/             # Technical Implementation (HOW - Code)
├── architecture/         # System Design & Patterns
├── guides/               # How-to Guides & Best Practices
└── plans/                # Implementation Plans & Roadmaps
```

---

## 🎯 Quick Navigation

### **I want to understand... → Go to...**

| What You Need | Documentation Type | Location |
|---------------|-------------------|----------|
| **Why a feature exists** | Product Requirements Doc (PRD) | `docs/product/` |
| **User journey & flows** | Workflow Diagrams | `docs/workflows/` |
| **How code is structured** | Technical Feature Docs | `docs/features/` |
| **API contracts & endpoints** | Feature Docs + Workflow Diagrams | `docs/features/` + `docs/workflows/` |
| **Architecture decisions** | Architecture Docs | `docs/architecture/` |
| **Development setup** | Technical Docs | `docs/technical-docs.md` |
| **Quick reference cheatsheet** | CLAUDE.md | Root: `CLAUDE.md` |

---

## 📖 Documentation Types Explained

### **1. Product Requirements Documents (PRDs)**

**Location:** `docs/product/`

**Purpose:** Connect user problems to solutions. Answer "Why are we building this?" and "What does success look like?"

**Audience:** Product managers, stakeholders, designers, new engineers

**Structure:**
- Problem statement & user pain points
- Target personas & user stories
- Success metrics (KPIs)
- Acceptance criteria
- Functional & non-functional requirements
- Launch checklist & rollout plan

**When to Use:**
- Before building new features
- During stakeholder alignment
- When onboarding new team members
- When planning feature iterations

**Available PRDs:**
- `PRD-Template.md` - Reusable template for new features
- `Bookshelf-Scanner-PRD.md` - Sample PRD (shipped feature)

**To Create a New PRD:**
1. Copy `PRD-Template.md`
2. Rename to `[Feature-Name]-PRD.md`
3. Fill in all sections (delete placeholder text)
4. Reference workflow diagram in "Functional Requirements" section

---

### **2. Workflow Diagrams**

**Location:** `docs/workflows/`

**Purpose:** Visualize complex flows at-a-glance using Mermaid diagrams

**Audience:** Developers, QA engineers, support staff, anyone needing quick comprehension

**Structure:**
- User journey flowcharts
- State machines
- Sequence diagrams (API integration)
- Error handling flows
- Performance metrics tables

**When to Use:**
- Embedded in PRDs for visual storytelling
- Referenced in feature docs for implementation clarity
- Shown in design reviews
- Used for debugging (trace user path through states)

**Available Workflows:**
- `search-workflow.md` - Book search & ISBN scanner
- `bookshelf-scanner-workflow.md` - AI-powered shelf scanning
- `csv-import-workflow.md` - Bulk library import
- `enrichment-workflow.md` - Background metadata enrichment

**To Create a New Workflow:**
1. Identify the feature's key flows (happy path, error cases, edge cases)
2. Choose diagram types:
   - **Flowchart:** Linear user journey (start → actions → end)
   - **State Machine:** System states and transitions
   - **Sequence Diagram:** Multi-component interactions (iOS ↔ Backend ↔ API)
3. Use Mermaid syntax (renders in GitHub, VS Code, many IDEs)
4. Include performance metrics and key components table

---

### **3. Technical Feature Documentation**

**Location:** `docs/features/`

**Purpose:** Deep-dive implementation details, architecture decisions, lessons learned

**Audience:** Engineers actively working on the codebase

**Structure:**
- Code patterns & examples
- API contracts
- Performance benchmarks
- Common issues & solutions
- Testing strategies
- Future enhancements

**When to Use:**
- Implementing new code
- Debugging production issues
- Understanding existing patterns
- Writing tests

**Available Feature Docs:**
- `BOOKSHELF_SCANNER.md` - AI camera scanner (Build 46+)
- `BATCH_BOOKSHELF_SCANNING.md` - Multi-photo scanning
- `GEMINI_CSV_IMPORT.md` - AI-powered CSV import (v3.1.0+)
- ~~`CSV_IMPORT.md`~~ - Legacy manual import (removed v3.3.0, see `archive/features-removed/`)
- `REVIEW_QUEUE.md` - Human-in-the-loop corrections
- `WEBSOCKET_FALLBACK_ARCHITECTURE.md` - Real-time progress tracking
- `DIVERSITY_INSIGHTS.md` - Cultural diversity visualizations and reading statistics

---

### **4. Architecture Documentation**

**Location:** `docs/architecture/`

**Purpose:** System-wide design patterns and architectural decisions

**When to Use:**
- Understanding cross-cutting concerns
- Making architecture decisions
- Refactoring large systems

**Available Docs:**
- `SyncCoordinator-Architecture.md` - Job orchestration pattern
- `nested-types-pattern.md` - Code organization standard
- `2025-10-22-sendable-audit.md` - Swift 6 concurrency compliance

---

## 🚀 Common Workflows

### **Onboarding a New Developer**

1. Read **CLAUDE.md** (root) - Quick reference & standards
2. Read **docs/technical-docs.md** - Development setup
3. Scan **docs/workflows/** - Visual overview of all features
4. Deep-dive **docs/features/** - Pick a feature area to focus on

---

### **Planning a New Feature**

1. Create PRD from **docs/product/PRD-Template.md**
2. Create workflow diagram in **docs/workflows/**
3. Write technical spec in **docs/features/**
4. Update **CLAUDE.md** with quick reference after shipping

---

### **Debugging a Production Issue**

1. Check **docs/workflows/** to trace user path
2. Consult **docs/features/** for known issues & solutions
3. Review **docs/architecture/** for system-level constraints
4. Check **CLAUDE.md** "Common Issues" section

---

### **Understanding a Feature Before Coding**

1. **Start with workflow diagram** (`docs/workflows/`) - Visual overview
2. **Read PRD** (`docs/product/`) - Understand the "why"
3. **Study feature doc** (`docs/features/`) - Implementation details
4. **Review code** with context from above

---

## 📝 Documentation Best Practices

### **When to Update Each Type**

| Event | Update PRD | Update Workflow | Update Feature Doc | Update CLAUDE.md |
|-------|-----------|----------------|-------------------|------------------|
| **Planning new feature** | ✅ Create new | ✅ Create new | ⏳ After implementation | ⏳ After ship |
| **Feature shipped** | ✅ Mark "Shipped" | ✅ Add performance metrics | ✅ Add lessons learned | ✅ Add quick reference |
| **Bug fixed** | ❌ | ❌ | ✅ Update "Common Issues" | ✅ If critical pattern |
| **Architecture change** | ❌ | ✅ If user-facing flow changes | ✅ Update implementation | ✅ Update standards |
| **Deprecating feature** | ✅ Mark "Deprecated" | ✅ Archive to `docs/archive/` | ✅ Archive | ✅ Remove from quick ref |

---

### **Documentation Checklist for New Features**

Before marking a feature complete:

- [ ] PRD approved by PM and Engineering Lead
- [ ] Workflow diagram created with all states/flows
- [ ] Technical feature doc written with code examples
- [ ] CLAUDE.md updated with quick reference section
- [ ] GitHub Issues created for known P1/P2 enhancements
- [ ] All docs reviewed for broken links

---

## 🔗 External Resources

- **GitHub Issues:** [Project Board](https://github.com/users/jukasdrj/projects/2) - Active tasks
- **CHANGELOG.md:** Victory stories & historical context
- **Cloudflare Workers Docs:** `cloudflare-workers/SERVICE_BINDING_ARCHITECTURE.md`
- **MCP Setup:** `MCP_SETUP.md` - XcodeBuildMCP workflows

---

## 🤝 Contributing to Documentation

### **Writing Guidelines**

1. **PRDs:** Use template, fill in ALL sections (don't delete placeholders without content)
2. **Workflows:** Include flowchart + state machine + sequence diagram (minimum)
3. **Feature Docs:** Show code examples, reference file paths with line numbers
4. **All Docs:** Use tables for quick reference, use Mermaid diagrams liberally

### **Markdown Standards**

- **Headings:** Use `##` for sections, `###` for sub-sections
- **Code Blocks:** Always specify language (```swift, ```typescript)
- **Links:** Relative paths (`docs/features/FEATURE.md`), not absolute
- **Mermaid:** Test rendering in GitHub preview before committing

### **Review Process**

- PRDs require PM + Engineering Lead approval
- Workflow diagrams reviewed during design phase
- Feature docs reviewed with code PRs
- CLAUDE.md updates require zero-warning build verification

---

## 📞 Documentation Owners

| Documentation Type | Owner | Contact |
|-------------------|-------|---------|
| **PRDs** | Product Team | @product |
| **Workflow Diagrams** | Engineering + Product | @engineering |
| **Feature Docs** | Engineering Lead | @engineering |
| **Architecture Docs** | Engineering Lead | @engineering |
| **CLAUDE.md** | Project Maintainer | @jukasdrj |

---

## 🎓 Learning Path

**For Product Managers:**
- Start: PRDs (`docs/product/`)
- Then: Workflow diagrams (`docs/workflows/`)
- Optional: Feature docs (`docs/features/`) for technical depth

**For Designers:**
- Start: Workflow diagrams (`docs/workflows/`)
- Then: PRDs (`docs/product/`) for context
- Reference: CLAUDE.md for iOS 26 HIG standards

**For Engineers:**
- Start: CLAUDE.md (quick reference)
- Then: Workflow diagrams (`docs/workflows/`)
- Deep-dive: Feature docs (`docs/features/`)
- System-level: Architecture docs (`docs/architecture/`)

**For QA/Support:**
- Start: Workflow diagrams (`docs/workflows/`)
- Then: Feature docs (`docs/features/`) "Common Issues" sections
- Reference: PRDs (`docs/product/`) for expected behavior

---

**Happy documenting! 📚**
