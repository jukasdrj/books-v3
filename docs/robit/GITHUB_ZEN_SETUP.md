# GitHub + Zen MCP Setup Guide
**BooksTrack Flutter Project**

This project is optimized for collaborative development with GitHub Issues and Zen MCP AI-powered code assistance.

---

## 🚀 Quick Start

### 1. Set Up API Keys (Required for Zen MCP)

```bash
# Copy the environment template
cp .env.example .env

# Edit .env and add your API keys:
# - ANTHROPIC_API_KEY (Claude Max Plan)
# - GOOGLE_AI_API_KEY (Gemini Pro)
# - XAI_API_KEY (Grok)
# - OPENROUTER_API_KEY (Multiple models)
# - CLOUDFLARE_API_TOKEN (Workers)
```

**Security Note:** `.env` is gitignored. NEVER commit API keys to git.

### 2. Create GitHub Labels

```bash
# Apply all project labels
bash .github/create_issues.sh
```

This creates:
- **Priority labels:** P0 (Critical) → P3 (Low)
- **Type labels:** bug, feature, enhancement, perf, security, docs
- **Phase labels:** 1-Foundation → 6-Launch
- **Platform labels:** android, ios, macos, web, all
- **Component labels:** database, ui, api, scanner, auth, firebase
- **Status labels:** blocked, in-progress, ready, needs-review
- **Effort labels:** XS (<2h) → XL (3-5d)

### 3. Enable Zen MCP in Claude Code

Zen MCP is already configured in `.claude/mcp_config.json`. Restart Claude Code to activate.

**Available Tools:**
- `codereview` - Expert AI code review (Gemini 2.5 Pro, Claude Opus 4)
- `debug` - Systematic debugging with hypothesis testing
- `planner` - Interactive feature planning
- `thinkdeep` - Complex problem analysis
- `consensus` - Multi-model decision making
- `refactor` - Refactoring recommendations
- `secaudit` - Security audits
- `testgen` - Test generation
- `analyze` - Code architecture analysis
- `chat` - General AI assistance

### 4. Install Pre-commit Hook (Recommended)

```bash
# Link Claude Code pre-commit hook to git
ln -sf ../../.claude/hooks/pre-commit.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

**What it does:**
- Runs `flutter analyze`
- Checks code formatting
- Runs tests
- Prevents committing sensitive files
- Warns about debug statements

---

## 📋 GitHub Issues Workflow

### Creating Issues

Use GitHub issue templates:

1. **Feature Request** - Proposes new functionality
2. **Bug Report** - Reports bugs with reproduction steps

### Issue Labels Guide

#### Priority (Required)
- **P0: Critical** - Blocks progress, fix immediately (red)
- **P1: High** - Important, fix soon (orange)
- **P2: Medium** - Standard priority (yellow)
- **P3: Low** - Nice to have (light yellow)

#### Type (Required)
- `type: bug` - Something broken
- `type: feature` - New functionality
- `type: enhancement` - Improvement to existing feature
- `type: refactor` - Code quality improvement
- `type: perf` - Performance optimization
- `type: security` - Security fix
- `type: docs` - Documentation
- `type: test` - Testing

#### Phase
- `phase: 1-foundation` - Weeks 1-3 (Critical foundation)
- `phase: 2-search` - Weeks 4-5 (Search feature)
- `phase: 3-scanner` - Weeks 6-8 (AI Scanner)
- `phase: 4-insights` - Weeks 9-10 (Analytics)
- `phase: 5-polish` - Weeks 11-12 (Testing & polish)
- `phase: 6-launch` - Weeks 13-14 (Production launch)

#### Platform
- `platform: android` - Android-specific
- `platform: ios` - iOS-specific
- `platform: macos` - macOS-specific
- `platform: web` - Web-specific
- `platform: all` - Cross-platform

#### Component
- `component: database` - Drift database layer
- `component: ui` - UI/widgets
- `component: api` - API integration
- `component: scanner` - AI Scanner
- `component: auth` - Authentication
- `component: firebase` - Firebase services
- `component: routing` - Navigation/go_router
- `component: state` - State management/Riverpod

#### Status
- `status: ready` - Can be worked on
- `status: in-progress` - Currently being worked on
- `status: blocked` - Blocked by dependencies
- `status: needs-review` - Needs code review
- `status: needs-testing` - Needs testing

#### Effort
- `effort: XS (< 2h)` - Extra small
- `effort: S (2-4h)` - Small
- `effort: M (4-8h)` - Medium
- `effort: L (1-2d)` - Large
- `effort: XL (3-5d)` - Extra large

#### Special
- `good first issue` - Good for newcomers
- `help wanted` - Extra attention needed
- `expert-validated` - Validated by Zen MCP AI review
- `ai-review-required` - Needs Zen MCP code review

### Example Issue Creation

```bash
gh issue create \
  --title "[P0] Fix DTOMapper Author Mapping Bug" \
  --body "Description..." \
  --label "P0: Critical,type: bug,phase: 1-foundation,component: database,platform: all,effort: M (4-8h)"
```

---

## 🤖 Zen MCP AI Tools Usage

### Code Review with Expert AI

```bash
# In Claude Code, use custom prompt:
/code-review files=lib/core/database/database.dart review_type=full
```

This triggers Zen MCP `codereview` tool with:
- Gemini 2.5 Pro or Claude Opus 4
- Security analysis (OWASP Top 10)
- Performance bottlenecks
- Architecture violations
- Best practices validation

### Debugging with AI

```bash
/debug-issue \
  issue_description="DTOMapper returns wrong authors" \
  files=lib/core/services/dto_mapper.dart \
  platform=all
```

This triggers Zen MCP `debug` tool for:
- Root cause analysis
- Hypothesis testing
- Fix recommendations
- Test case suggestions

### Feature Planning

```bash
/plan-feature \
  feature_name="AI Bookshelf Scanner" \
  phase="Phase 3" \
  effort="3 weeks"
```

This triggers Zen MCP `planner` tool for:
- Implementation plan
- Component breakdown
- Database schema changes
- Testing strategy
- Risk assessment

---

## 🔧 Zen MCP Configuration

### Provider Configuration

See `.zen/conf/providers.yml` for AI provider setup.

**Configured Providers:**
1. **Anthropic Claude** (Max Plan)
   - Claude Sonnet 4 (200K context, thinking mode)
   - Claude Opus 4 (200K context, complex reasoning)

2. **Google Gemini** (Paid Pro)
   - Gemini 2.5 Pro Experimental (1M context)
   - Gemini 2.0 Flash Thinking (fast, free)

3. **xAI Grok**
   - Grok Beta (131K context)

4. **OpenRouter**
   - GPT-5 Pro (400K context)
   - DeepSeek V3 (excellent for code)
   - Qwen 2.5 Coder 32B (specialized coding)
   - Llama 3.3 70B (good balance)

### Model Selection Strategy

Zen MCP auto-selects the best model for each task:

| Task | Preferred Models |
|------|-----------------|
| Code Review | Gemini 2.5 Pro, Claude Sonnet 4, GPT-5 |
| Debugging | Gemini 2.5 Pro, DeepSeek, Claude Sonnet 4 |
| Refactoring | Qwen Coder, DeepSeek, Claude Sonnet 4 |
| Architecture | Claude Opus 4, GPT-5, Gemini 2.5 Pro |
| Documentation | Claude Sonnet 4, Gemini 2.5 Pro |
| Planning | Claude Opus 4, GPT-5 |
| Quick Tasks | Flash Thinking, DeepSeek, Llama |

### Cost Optimization

- Simple tasks use cheaper models (DeepSeek, Llama)
- Complex tasks use premium models (Claude Opus 4, GPT-5)
- Max cost per request: $1.00

---

## 📚 Claude Code Prompts

Custom prompts are in `.claude/prompts/`:

1. **code-review.md** - Comprehensive code review
2. **debug-issue.md** - Systematic debugging
3. **plan-feature.md** - Feature planning

### Using Prompts

```bash
# In Claude Code chat:
/code-review files=lib/core/database/database.dart review_type=security

# Or use slash commands if configured:
/review lib/core/database/database.dart
```

---

## 🔐 Security Best Practices

1. **API Keys**
   - Store in `.env` (gitignored)
   - Use `.env.example` as template
   - Never commit keys to git
   - Rotate keys if exposed

2. **Firebase Config**
   - `google-services.json` is gitignored
   - `GoogleService-Info.plist` is gitignored
   - Download fresh from Firebase Console
   - Add SHA-1 fingerprints for production

3. **Pre-commit Hook**
   - Prevents committing sensitive files
   - Enforces code quality
   - Runs tests before commit

---

## 🎯 Project Phases & Milestones

### Phase 1: Foundation (Weeks 1-3) ✅ 95% Complete
- [x] DTOMapper bug fix
- [x] N+1 query elimination
- [x] Keyset pagination
- [x] Image caching
- [x] Tab navigation (StatefulShellRoute)
- [x] Review Queue data model normalization
- [ ] CI/CD pipeline
- [ ] Analytics & Crashlytics

### Phase 2: Search (Weeks 4-5)
- [ ] Multi-mode search UI
- [ ] Barcode scanner integration
- [ ] Search result caching
- [ ] Result badges

### Phase 3: AI Scanner (Weeks 6-8)
- [ ] Camera capture
- [ ] Cloudflare Workers integration
- [ ] Gemini 2.0 Flash Vision API
- [ ] Review Queue UI

### Phase 4: Insights (Weeks 9-10)
- [ ] Reading statistics
- [ ] Diversity analysis charts
- [ ] Genre normalization
- [ ] Export functionality

### Phase 5: Polish (Weeks 11-12)
- [ ] Accessibility (TalkBack, VoiceOver)
- [ ] Performance optimization
- [ ] User testing feedback
- [ ] App Store assets

### Phase 6: Launch (Weeks 13-14)
- [ ] Production deployment
- [ ] App Store submission
- [ ] Marketing materials
- [ ] Public launch

---

## 📞 Support & Resources

### Documentation
- [TODO_REFINED.md](./TODO_REFINED.md) - Full development plan
- [CLAUDE.md](./CLAUDE.md) - Claude Code project guidelines
- [IMPLEMENTATION_LOG.md](./IMPLEMENTATION_LOG.md) - Session logs

### Security
- [SECURITY_INCIDENT.md](./SECURITY_INCIDENT.md) - Firebase security incident
- [FIREBASE_SETUP.md](./FIREBASE_SETUP.md) - Firebase configuration guide
- [FIREBASE_CLEANUP_PLAN.md](./FIREBASE_CLEANUP_PLAN.md) - Firebase cleanup steps

### External Resources
- [Zen MCP Documentation](https://github.com/BeehiveInnovations/zen-mcp-server)
- [Claude Code Docs](https://docs.claude.com/claude-code)
- [Flutter Docs](https://docs.flutter.dev/)
- [Riverpod Docs](https://riverpod.dev/)
- [Drift Docs](https://drift.simonbinder.eu/)

---

**Last Updated:** November 12, 2025
**Status:** Ready for collaborative development with GitHub + Zen MCP
