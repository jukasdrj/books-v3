# Claude Code Agent Setup (iOS) - Complete

**Synced from:** bookstrack-backend (automated setup framework)
**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, Xcode 15.2+, iOS 26
**Status:** ✅ Production Ready

---

## 🎯 Quick Start

### Invoke Agents

```bash
# For complex workflows (orchestration)
/skill project-manager

# For iOS build/test/deploy
/skill xcode-agent

# For Swift 6.2 concurrency & iOS 26 compliance
/skill swift62-master

# For code review/debugging/security
/skill zen-mcp-master
```

### Use MCP Commands (Fastest)

```bash
/build          # Quick build validation
/test           # Run Swift Testing suite
/sim            # Launch in simulator with logs
/device-deploy  # Deploy to iPhone/iPad
```

---

## 📚 Complete Documentation

### Essential Reading

| Document | Purpose | When to Read |
|----------|---------|--------------|
| **[ROBIT_GITHUB_ACTIONS_INTEGRATION.md](ROBIT_GITHUB_ACTIONS_INTEGRATION.md)** | **START HERE** - Complete workflow linking agents → hooks → GitHub Actions | Setting up automation |
| **[ROBIT_OPTIMIZATION.md](ROBIT_OPTIMIZATION.md)** | 3-agent architecture design | Understanding the system |
| **[ROBIT_SHARING_FRAMEWORK.md](ROBIT_SHARING_FRAMEWORK.md)** | How robit setup syncs across repos | Customizing for your project |
| **[MCP_SETUP.md](../MCP_SETUP.md)** | XcodeBuildMCP slash command configuration | Using /build, /test, /sim |

### Agent Documentation

| Agent | File | Purpose |
|-------|------|---------|
| **project-manager** | `.claude/skills/project-manager/skill.md` | Orchestrates workflows, delegates to specialists |
| **xcode-agent** | `.claude/skills/xcode-agent/skill.md` | Build, test, deploy, simulator/device operations |
| **swift62-master** | `.claude/skills/swift62-master/skill.md` | Swift 6.2 strict concurrency, @MainActor, iOS 26 HIG validator |
| **zen-mcp-master** | `.claude/skills/zen-mcp-master/skill.md` | Gateway to 14 Zen MCP tools (debug, review, audit) |

---

## 🏗️ Architecture

### 4-Agent Delegation Hierarchy

```
User Request
     ↓
project-manager (Orchestrator)
     ↓
     ├─→ xcode-agent (Build/Test/Deploy)
     │   ├── /build (MCP command)
     │   ├── /test (MCP command)
     │   ├── /sim (MCP command)
     │   └── /device-deploy (MCP command)
     │
     ├─→ swift62-master (Swift 6.2 & iOS 26 Compliance)
     │   ├── @MainActor validation
     │   ├── Sendable conformance checks
     │   ├── SwiftData lifecycle rules
     │   ├── iOS 26 HIG patterns
     │   └── Concurrency violation detection
     │
     └─→ zen-mcp-master (Analysis/Review)
         ├── debug (14 Zen MCP tools)
         ├── codereview
         ├── secaudit
         ├── thinkdeep
         └── ... (10 more)
```

### Integration Flow

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ Claude Code     │    │ Hooks           │    │ GitHub Actions  │
│ Agents          │───▶│ (Bridge)        │───▶│ (CI/CD)         │
└─────────────────┘    └─────────────────┘    └─────────────────┘
      │                       │                       │
      │ Executes              │ Validates             │ Automates
      │ Locally               │ & Suggests            │ Remotely
      │                       │                       │
      ▼                       ▼                       ▼
  • Build/Test          • pre-commit.sh         • PR validation
  • Code review         • post-tool-use.sh      • TestFlight deploy
  • Security audit                              • Doc generation
```

**See:** [ROBIT_GITHUB_ACTIONS_INTEGRATION.md](ROBIT_GITHUB_ACTIONS_INTEGRATION.md) for complete workflow diagrams

---

## 🚀 Common Workflows

### 1. New Feature Development

```bash
# Step 1: Plan and implement
You: "Implement offline sync for reading list"
  ↓
project-manager → delegates to zen-mcp-master (planner)
  ↓
Claude Code implements feature
  ↓
xcode-agent: /build (validate)
  ↓
xcode-agent: /test (quality gate)

# Step 2: Hook triggers review
post-tool-use.sh detects changes → suggests zen-mcp-master

# Step 3: Code review
You: /skill zen-mcp-master
  ↓
Uses codereview tool → validates Swift patterns

# Step 4: Commit and PR
pre-commit.sh validates (SwiftLint, secrets check)
  ↓
Create PR → GitHub Actions runs pr-validation.yml
  ↓
Build + Test + Coverage report
```

### 2. Bug Fix

```bash
# Step 1: Debug
You: "App crashes when adding book"
  ↓
zen-mcp-master: debug tool → identifies root cause

# Step 2: Fix and test
Claude Code fixes bug
  ↓
xcode-agent: /test → regression test passes

# Step 3: Quick deploy
Create hotfix tag (v3.1.1)
  ↓
GitHub Actions: testflight-deploy.yml
  ↓
Auto-deploys to TestFlight
```

### 3. TestFlight Deployment

```bash
# Step 1: Validate
zen-mcp-master: precommit (validate changes)
  ↓
xcode-agent: /build && /test (quality gates)

# Step 2: Tag release
git tag -a v3.2.0 -m "Release v3.2.0"
git push origin v3.2.0

# Step 3: Automated deployment
GitHub Actions: testflight-deploy.yml
  ↓
Archive → Export IPA → Upload to TestFlight
  ↓
Create GitHub release
  ↓
Slack notification (optional)
```

---

## 🛠️ Setup Instructions

### 1. Verify Agents Installed

```bash
ls -la .claude/skills/
# Should show:
# - project-manager/
# - xcode-agent/
# - zen-mcp-master/
```

### 2. Configure Hooks

```bash
# Make hooks executable
chmod +x .claude/hooks/pre-commit.sh
chmod +x .claude/hooks/post-tool-use.sh

# Test hooks
bash .claude/hooks/post-tool-use.sh
bash .claude/hooks/pre-commit.sh
```

### 3. Set Up GitHub Actions

**Required secrets** (Settings → Secrets and variables → Actions):

```
CERTIFICATE_BASE64              # iOS signing certificate (base64)
CERTIFICATE_PASSWORD            # Certificate password
KEYCHAIN_PASSWORD              # Keychain password
PROVISIONING_PROFILE_BASE64    # Provisioning profile (base64)
TEAM_ID                        # Apple Developer Team ID
APPLE_ID                       # Apple ID for TestFlight
APP_SPECIFIC_PASSWORD          # App-specific password
```

**To encode certificate:**
```bash
base64 -i Certificates.p12 | pbcopy
```

**See:** [ROBIT_GITHUB_ACTIONS_INTEGRATION.md](ROBIT_GITHUB_ACTIONS_INTEGRATION.md) for detailed setup

### 4. Test the System

```bash
# Test agent invocation
/skill xcode-agent

# Test MCP commands
/build
/test

# Make a code change and watch hook trigger
# Edit any Swift file → post-tool-use.sh suggests review

# Create a commit → pre-commit.sh validates
git add .
git commit -m "Test commit"
```

---

## 🎯 Available Tools

### Claude Code Agents (4)

| Agent | Purpose | Key Capabilities |
|-------|---------|------------------|
| **project-manager** | Orchestration | Delegates to specialists, coordinates multi-phase workflows |
| **xcode-agent** | iOS Operations | Build, test, deploy, simulator/device management |
| **swift62-master** | Swift/iOS Compliance | Swift 6.2 concurrency, @MainActor, iOS 26 HIG, SwiftData lifecycle |
| **zen-mcp-master** | Deep Analysis | 14 Zen MCP tools (debug, codereview, secaudit, etc.) |

### Zen MCP Tools (14)

Available via `zen-mcp-master`:

- **debug** - Systematic bug investigation
- **codereview** - Comprehensive code review
- **secaudit** - Security audit (OWASP Top 10)
- **thinkdeep** - Complex problem analysis
- **planner** - Task planning and breakdown
- **consensus** - Multi-model decision making
- **analyze** - Codebase analysis
- **refactor** - Refactoring opportunities
- **tracer** - Execution flow tracing
- **testgen** - Test generation
- **precommit** - Git change validation
- **docgen** - Documentation generation
- Plus 2 more...

**See:** `.claude/skills/zen-mcp-master/skill.md` for complete tool documentation

### MCP Slash Commands (4)

Via XcodeBuildMCP:

```bash
/build          # Quick build validation (12-30s)
/test           # Run Swift Testing suite (1-2min)
/sim            # Launch simulator with live logs
/device-deploy  # Deploy to connected device
```

**See:** [MCP_SETUP.md](../MCP_SETUP.md) for XcodeBuildMCP configuration

### GitHub Actions Workflows (3+)

- **pr-validation.yml** - Build, test, lint on PR creation
- **testflight-deploy.yml** - Auto-deploy on version tags
- **docs-validation.yml** - Validate markdown and Mermaid diagrams

**See:** [ROBIT_GITHUB_ACTIONS_INTEGRATION.md](ROBIT_GITHUB_ACTIONS_INTEGRATION.md) for workflow examples

---

## 🧠 Zen MCP Models

**Available via zen-mcp-master:**

### Google Gemini
- `gemini-2.5-pro` - Deep reasoning, complex problems (1M context)
- `gemini-2.5-flash-preview` - Fast, efficient analysis (1M context)
- `gemini-2.5-pro-computer-use` - UI interaction, automation (1M context)

### X.AI Grok
- `grok-4` - Most intelligent (256K context)
- `grok-4-heavy` - Most powerful (256K context)
- `grok-4-fast-reasoning` - Ultra-fast (2M context)
- `grok-code-fast-1` - Coding specialist (2M context)

**Model selection is automatic** - agents choose based on task complexity

---

## 📖 Learning Path

### For New Users

1. **Read:** [ROBIT_GITHUB_ACTIONS_INTEGRATION.md](ROBIT_GITHUB_ACTIONS_INTEGRATION.md) - Understand complete workflow
2. **Try:** `/build` → See MCP commands in action
3. **Invoke:** `/skill project-manager` → Experience agent orchestration
4. **Test:** Make a code change → Watch hooks trigger
5. **Deploy:** Create PR → See GitHub Actions run

### For Customization

1. **Study:** `.claude/skills/project-manager/skill.md` - Learn delegation patterns
2. **Explore:** `.claude/skills/xcode-agent/skill.md` - Understand iOS operations
3. **Review:** `.claude/hooks/post-tool-use.sh` - See hook logic
4. **Modify:** GitHub Actions workflows for your needs
5. **Extend:** Add new agents or hooks as needed

---

## 🔧 Troubleshooting

### Agents not working?

```bash
# Verify skill files exist
ls -la .claude/skills/*/skill.md

# Check mcp-zen-usage skill is loaded
# It should be in ~/.claude/skills/mcp-zen-usage/
```

### Hooks not triggering?

```bash
# Make hooks executable
chmod +x .claude/hooks/*.sh

# Test manually
bash .claude/hooks/post-tool-use.sh
```

### GitHub Actions failing?

```bash
# Validate YAML syntax
yamllint .github/workflows/pr-validation.yml

# Check secrets are set
# GitHub → Settings → Secrets and variables → Actions

# View logs
gh run list
gh run view <run-id> --log
```

---

## 🎉 What's Next?

### Immediate Actions

1. ✅ **Test your setup** - Run `/build` and `/test`
2. ✅ **Make a code change** - See hooks suggest agents
3. ✅ **Create a PR** - Watch GitHub Actions validate
4. ✅ **Deploy to TestFlight** - Tag a release version

### Advanced Customization

1. **Add custom workflows** - Create new GitHub Actions
2. **Extend hooks** - Add project-specific validations
3. **Create new agents** - For specialized tasks
4. **Optimize CI/CD** - Fine-tune workflow performance

---

## 📚 External Resources

- **Claude Code Docs:** https://docs.claude.com/en/docs/claude-code
- **Zen MCP GitHub:** https://github.com/zenith-ai/zen-mcp
- **XcodeBuildMCP:** https://github.com/anthropics/xcode-build-mcp
- **GitHub Actions:** https://docs.github.com/en/actions
- **SwiftLint:** https://github.com/realm/SwiftLint

---

## 🏆 Success Metrics

Your robit setup is working when:

- ✅ Agents invoke successfully (`/skill project-manager`)
- ✅ MCP commands execute (`/build`, `/test`)
- ✅ Hooks suggest appropriate next steps
- ✅ Pre-commit validation catches issues
- ✅ GitHub Actions build and test PRs
- ✅ TestFlight deployment is automated

---

**Last Updated:** November 13, 2025
**Maintained By:** BooksTrack iOS Team
**Architecture:** 3-agent delegation hierarchy
**Integration:** Claude Code + Hooks + GitHub Actions
**Status:** ✅ Production Ready
