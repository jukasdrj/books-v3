# 🚀 BooksTrack Flutter - Complete Workflow Setup

**Date:** November 12, 2025
**Status:** ✅ Production-Ready for Team Collaboration

---

## ✅ What's Been Configured

### 1. GitHub Issues System
- ✅ 47 comprehensive labels created
- ✅ Feature request template
- ✅ Bug report template
- ✅ Label creation automation script
- ✅ Issue generation script template

### 2. Zen MCP AI Integration
- ✅ Multi-provider AI configuration
- ✅ 10+ AI tools enabled
- ✅ Auto model selection
- ✅ Cost optimization

### 3. Claude Code Integration
- ✅ Pre-commit hook
- ✅ Custom prompts (code-review, debug, plan)
- ✅ MCP server configuration

### 4. Security
- ✅ .env template for API keys
- ✅ Updated .gitignore
- ✅ Pre-commit hook prevents sensitive file commits
- ✅ Firebase config protection

---

## 🎯 Quick Start for Your Friends/Reviewers

### Step 1: Clone & Setup

```bash
git clone https://github.com/jukasdrj/books-flutter.git
cd books-flutter

# Install dependencies
flutter pub get

# Generate code
dart run build_runner build --delete-conflicting-outputs

# Set up API keys (optional for reviewers)
cp .env.example .env
# Edit .env with your keys if you want to use Zen MCP
```

### Step 2: Run the App

```bash
# iOS
flutter run -d ios

# Android
flutter run -d android

# macOS (may have gRPC issue)
flutter run -d macos

# Web
flutter run -d chrome
```

### Step 3: Review the Code

**Use GitHub Issues:**
- Browse issues by label: https://github.com/jukasdrj/books-flutter/labels
- Filter by priority: P0 (Critical) → P3 (Low)
- Filter by phase: 1-Foundation → 6-Launch
- Create new issues using templates

**Use Zen MCP (if you have API keys):**
```bash
# In Claude Code:
/code-review files=lib/core/database/database.dart review_type=security
/debug-issue issue_description="..." files=...
/plan-feature feature_name="..." phase="..."
```

---

## 📊 Project Status

### Phase 1: Foundation - 95% Complete ✅

**Completed:**
- ✅ DTOMapper bug fix (author mapping)
- ✅ N+1 query elimination (batch fetching)
- ✅ Keyset pagination implementation
- ✅ Image caching (CachedNetworkImage)
- ✅ Tab navigation (StatefulShellRoute)
- ✅ Review Queue data model normalization
- ✅ Firebase cleanup & re-registration
- ✅ Package ID standardization (com.oooefam.bookstrack)

**Remaining (P2):**
- [ ] CI/CD pipeline setup
- [ ] Analytics & Crashlytics integration
- [ ] AsyncValueView widget
- [ ] Skeleton shimmer loaders

### Next Phase: Search (Weeks 4-5)
See [TODO_REFINED.md](./TODO_REFINED.md) for complete 14-week plan.

---

## 🏷️ GitHub Label System

### Priority (Filter by Urgency)
- 🔴 **P0: Critical** - Blocks progress (4 issues in backlog)
- 🟠 **P1: High** - Important, fix soon
- 🟡 **P2: Medium** - Standard priority
- 🟢 **P3: Low** - Nice to have

### Phase (Filter by Timeline)
- **Phase 1:** Foundation (Weeks 1-3) - 95% complete
- **Phase 2:** Search (Weeks 4-5)
- **Phase 3:** AI Scanner (Weeks 6-8)
- **Phase 4:** Insights (Weeks 9-10)
- **Phase 5:** Polish (Weeks 11-12)
- **Phase 6:** Launch (Weeks 13-14)

### Component (Filter by Area)
- `component: database` - Drift SQL queries
- `component: ui` - Widgets & Material Design 3
- `component: api` - Cloudflare Workers integration
- `component: scanner` - AI vision & camera
- `component: firebase` - Auth, Firestore, Storage
- `component: routing` - go_router navigation
- `component: state` - Riverpod state management

### Effort (Filter by Time)
- `effort: XS (< 2h)` - Quick fixes
- `effort: S (2-4h)` - Small tasks
- `effort: M (4-8h)` - Half day
- `effort: L (1-2d)` - 1-2 days
- `effort: XL (3-5d)` - 3-5 days

---

## 🤖 Zen MCP AI Tools

### Available Tools (with your API keys)

1. **codereview** - Expert code review
   - Uses: Gemini 2.5 Pro, Claude Opus 4, GPT-5
   - Checks: Security, performance, architecture, best practices

2. **debug** - Systematic debugging
   - Uses: Gemini 2.5 Pro, DeepSeek V3
   - Provides: Root cause analysis, fixes, test cases

3. **planner** - Feature planning
   - Uses: Claude Opus 4, GPT-5
   - Provides: Implementation plans, component breakdown, timelines

4. **thinkdeep** - Complex problem analysis
   - Uses: Multiple models for hypothesis testing
   - Provides: Deep investigation, evidence-based findings

5. **consensus** - Multi-model decision making
   - Uses: 2+ models with different perspectives
   - Provides: Comprehensive recommendations

6. **refactor** - Refactoring recommendations
   - Uses: Qwen Coder, DeepSeek, Claude
   - Provides: Code smell detection, modernization suggestions

7. **secaudit** - Security audits
   - Uses: Claude Opus 4, Gemini 2.5 Pro
   - Provides: OWASP Top 10 analysis, vulnerability detection

8. **testgen** - Test generation
   - Uses: Claude Sonnet 4, DeepSeek
   - Provides: Test cases, edge case coverage

9. **analyze** - Architecture analysis
   - Uses: Claude Opus 4, Gemini 2.5 Pro
   - Provides: Codebase structure, patterns, improvements

10. **chat** - General AI assistance
    - Uses: Auto-selected model
    - Provides: Q&A, explanations, brainstorming

### Model Selection Strategy

Zen MCP automatically chooses the best model for each task:

| Task Type | Preferred Models |
|-----------|-----------------|
| Code Review | Gemini 2.5 Pro, Claude Sonnet 4, GPT-5 |
| Debugging | Gemini 2.5 Pro, DeepSeek, Claude Sonnet 4 |
| Refactoring | Qwen Coder, DeepSeek, Claude Sonnet 4 |
| Architecture | Claude Opus 4, GPT-5, Gemini 2.5 Pro |
| Documentation | Claude Sonnet 4, Gemini 2.5 Pro |
| Planning | Claude Opus 4, GPT-5 |
| Quick Tasks | Flash Thinking, DeepSeek, Llama |

---

## 💡 Tips for Reviewers

### Code Review Focus Areas

1. **Flutter Best Practices**
   - Material Design 3 compliance
   - Proper Riverpod usage
   - Widget composition patterns

2. **Performance**
   - Database query optimization (check for N+1)
   - Image loading (memory optimization)
   - Lazy loading & pagination

3. **Security**
   - No hardcoded credentials
   - Proper API key handling
   - Firebase security rules

4. **Architecture**
   - Feature-first structure
   - Clear separation of concerns
   - DTOMapper correctness

### How to Provide Feedback

**Option 1: GitHub Issues**
```bash
# Create an issue using the template
gh issue create

# Or browse/comment on existing issues
gh issue list --label "needs-review"
```

**Option 2: Pull Request Comments**
- Comment on specific lines
- Suggest improvements
- Reference related issues

**Option 3: GitHub Discussions**
- Ask questions
- Propose alternatives
- Share ideas

---

## 📁 Key Files to Review

### Critical Performance & Data (P0)
- `lib/core/services/dto_mapper.dart` - Author mapping bug fix
- `lib/core/database/database.dart` - N+1 fix, keyset pagination
- `lib/shared/widgets/book_card.dart` - Image caching

### Navigation & UI
- `lib/core/router/app_router.dart` - StatefulShellRoute navigation
- `lib/shared/widgets/main_scaffold.dart` - Bottom navigation
- `lib/features/library/screens/library_screen.dart` - Main screen

### Data Models
- `lib/core/database/database.dart` - Tables: Works, Authors, Editions, ScanSessions, DetectedItems
- `lib/core/models/dtos/work_dto.dart` - API DTOs

### Configuration
- `pubspec.yaml` - Dependencies
- `.github/` - Issue templates, labels, automation
- `.zen/conf/providers.yml` - AI provider setup
- `.claude/` - Hooks, prompts, MCP config

---

## 🔐 Security Notes

**For Reviewers:**
- You don't need API keys to review code
- Don't commit your .env file
- Firebase config files are gitignored (security protection)

**For Contributors:**
- Set up .env from .env.example
- Pre-commit hook prevents sensitive file commits
- All API keys stored securely in .env (gitignored)

---

## 📞 Getting Help

### Documentation
- [GITHUB_ZEN_SETUP.md](./GITHUB_ZEN_SETUP.md) - Complete setup guide
- [TODO_REFINED.md](./TODO_REFINED.md) - 14-week development plan
- [CLAUDE.md](./CLAUDE.md) - Claude Code guidelines
- [IMPLEMENTATION_LOG.md](./IMPLEMENTATION_LOG.md) - Session logs

### External Resources
- [Zen MCP Server](https://github.com/BeehiveInnovations/zen-mcp-server)
- [Claude Code Docs](https://docs.claude.com/claude-code)
- [Flutter Docs](https://docs.flutter.dev/)

---

## 🎉 What You Can Do Now

### As a Reviewer:
1. Clone the repo
2. Run the app
3. Browse GitHub issues
4. Leave feedback via issues/PRs
5. Ask questions in discussions

### As a Contributor (with API keys):
1. Set up .env with your keys
2. Use Zen MCP tools for AI assistance
3. Run pre-commit hook
4. Create issues with templates
5. Submit PRs with proper labels

---

**Last Updated:** November 12, 2025
**Status:** ✅ Ready for Team Collaboration
**Contributors:** Justin Gardner + Claude Code
