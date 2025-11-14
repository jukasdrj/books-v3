# Robit Setup Sharing Framework

**Purpose:** Share the optimized Claude Code agent setup across all BooksTrack repositories
**Target Repos:** iOS (books-tracker-v1), Flutter (future), Web (future)
**Last Updated:** November 13, 2025

---

## Overview

The backend's robit setup (3-agent delegation hierarchy) can be adapted for other repositories while respecting their unique tech stacks and workflows.

**Core Agents (Universal):**
1. **project-manager** - Orchestration (same across all repos)
2. **tech-specific-agent** - Platform-specific operations (varies by repo)
3. **zen-mcp-master** - Deep analysis (same across all repos)

---

## Automation Strategy

### Option A: Template Repository (Recommended)

Create `.claude-template/` with reusable agent configurations:

```
.claude-template/
├── README.md                      # How to use this template
├── skills/
│   ├── project-manager/           # Universal orchestrator
│   │   └── skill.md
│   ├── zen-mcp-master/            # Universal analyst
│   │   └── skill.md
│   └── PLATFORM_TEMPLATE.md       # Template for platform agents
├── hooks/
│   ├── pre-commit.sh.template     # Customizable pre-commit
│   └── post-tool-use.sh.template  # Customizable hook
└── docs/
    ├── SETUP_GUIDE.md             # Installation instructions
    └── CUSTOMIZATION.md           # How to adapt for your repo
```

**Sync Strategy:**
- Backend maintains `.claude-template/` as source of truth
- GitHub workflow syncs template to other repos
- Each repo customizes from template

---

### Option B: Shared Submodule (Advanced)

Create separate `bookstrack-claude-agents` repo:

```
bookstrack-claude-agents/
├── README.md
├── core/                          # Shared agents
│   ├── project-manager/
│   ├── zen-mcp-master/
│   └── README.md
├── platforms/                     # Platform-specific examples
│   ├── cloudflare-workers/       # Backend example
│   ├── swift-ios/                # iOS example
│   ├── flutter/                  # Flutter example
│   └── README.md
└── docs/
    └── INTEGRATION.md
```

**Usage in each repo:**
```bash
# In books-tracker-v1 (iOS)
git submodule add https://github.com/jukasdrj/bookstrack-claude-agents.git .claude/shared
ln -s .claude/shared/core/project-manager .claude/skills/project-manager
ln -s .claude/shared/core/zen-mcp-master .claude/skills/zen-mcp-master
```

---

## Universal Agents

### 1. project-manager (Same Everywhere)

**Why universal:** Orchestration logic is platform-agnostic

**Customization needed:**
- Update delegation targets (platform-specific agent names)
- Adjust workflow patterns for platform

**Template location:** `.claude-template/skills/project-manager/skill.md`

**Per-repo changes:**
```markdown
# In backend (Cloudflare):
**Delegates to:**
- `cloudflare-agent` for deployment/monitoring
- `zen-mcp-master` for analysis

# In iOS (Swift):
**Delegates to:**
- `xcode-agent` for build/test/deploy
- `zen-mcp-master` for analysis

# In Flutter:
**Delegates to:**
- `flutter-agent` for build/deploy
- `zen-mcp-master` for analysis
```

---

### 2. zen-mcp-master (Same Everywhere)

**Why universal:** Zen MCP tools work across all codebases

**Customization needed:**
- None! Same file across all repos

**Template location:** `.claude-template/skills/zen-mcp-master/skill.md`

**Copy as-is to all repos.**

---

## Platform-Specific Agents

### Backend: cloudflare-agent

**File:** `.claude/skills/cloudflare-agent/skill.md`

**Focus:**
- `npx wrangler` commands
- Deployment to Cloudflare Workers
- KV cache management
- Log analysis

---

### iOS: xcode-agent (Proposed)

**File:** `.claude/skills/xcode-agent/skill.md`

**Focus:**
- Xcode build/test commands
- TestFlight deployment
- Swift package management
- iOS-specific debugging

**Example structure:**
```markdown
# Xcode Build & Deploy Agent

**Purpose:** iOS app build, test, and deployment automation

**When to use:**
- Building iOS app
- Running tests
- Deploying to TestFlight
- Managing Swift packages

**Key capabilities:**
- Execute `xcodebuild` with proper schemes
- Run Swift tests with `swift test`
- Upload to TestFlight via `xcrun altool`
- Manage Swift Package dependencies
- Analyze crash logs

**CRITICAL:** Always use `xcodebuild` with project/workspace specification

## Core Responsibilities

### 1. Build Operations
- Build app with `xcodebuild -scheme BooksTracker build`
- Archive for distribution
- Manage build configurations (Debug/Release)

### 2. Testing
- Run unit tests: `swift test`
- Run UI tests: `xcodebuild test -scheme BooksTracker`
- Generate code coverage reports

### 3. Deployment
- Upload to TestFlight
- Manage certificates and provisioning profiles
- Increment build numbers

### 4. Swift Package Management
- Resolve dependencies: `swift package resolve`
- Update packages: `swift package update`
```

---

### Flutter: flutter-agent (Proposed)

**File:** `.claude/skills/flutter-agent/skill.md`

**Focus:**
- `flutter build` commands
- Pub package management
- Android/iOS builds
- Firebase deployment

---

## Automated Sync Workflow

### Create: `.github/workflows/sync-claude-setup.yml`

```yaml
name: 🤖 Sync Claude Agent Setup

on:
  push:
    branches: [main]
    paths:
      - '.claude-template/**'
      - '.github/workflows/sync-claude-setup.yml'

jobs:
  sync-to-ios:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Sync Claude template to iOS repo
        env:
          GH_TOKEN: ${{ secrets.GH_TOKEN }}
        run: |
          git clone --depth 1 https://github.com/jukasdrj/books-tracker-v1.git /tmp/ios

          # Copy universal agents (no changes needed)
          cp -r .claude-template/skills/project-manager /tmp/ios/.claude/skills/
          cp -r .claude-template/skills/zen-mcp-master /tmp/ios/.claude/skills/

          # Copy hook templates (iOS will customize)
          cp .claude-template/hooks/pre-commit.sh.template /tmp/ios/.claude/hooks/pre-commit.sh
          cp .claude-template/hooks/post-tool-use.sh.template /tmp/ios/.claude/hooks/post-tool-use.sh

          # Copy documentation
          cp .claude-template/docs/SETUP_GUIDE.md /tmp/ios/.claude/
          cp .claude-template/docs/CUSTOMIZATION.md /tmp/ios/.claude/

          cd /tmp/ios
          if ! git diff --quiet; then
            git add .claude/
            git commit -m "chore: sync Claude agent setup from backend template

Synced universal agents and templates.
iOS-specific customization required for:
- xcode-agent implementation
- Hook customization
- project-manager delegation targets

See .claude/CUSTOMIZATION.md for instructions"
            git push origin main
          else
            echo "No changes to sync"
          fi

  sync-to-flutter:
    runs-on: ubuntu-latest
    if: vars.FLUTTER_REPO_ENABLED == 'true'
    steps:
      # Similar to iOS sync
      - uses: actions/checkout@v4
      # ... same pattern
```

---

## Template Structure

### Project Manager Template

**File:** `.claude-template/skills/project-manager/skill.md`

**Variables to customize (marked with `{{PLATFORM}}`)**:

```markdown
# BooksTrack Project Manager

**Purpose:** Top-level orchestration agent

**Delegates to:**
- `{{PLATFORM_AGENT}}` for platform operations
- `zen-mcp-master` for deep analysis

## Delegation Patterns

### When to Delegate to {{PLATFORM_AGENT}}
```
User request contains:
- {{PLATFORM_KEYWORDS}}

Example:
User: "{{PLATFORM_EXAMPLE}}"
Manager: Delegates to {{PLATFORM_AGENT}} with context
```

### Platform-Specific Configuration

**For Backend (Cloudflare Workers):**
- `{{PLATFORM_AGENT}}` = `cloudflare-agent`
- `{{PLATFORM_KEYWORDS}}` = "deploy", "wrangler", "production"
- `{{PLATFORM_EXAMPLE}}` = "Deploy to production and monitor"

**For iOS:**
- `{{PLATFORM_AGENT}}` = `xcode-agent`
- `{{PLATFORM_KEYWORDS}}` = "build", "test", "TestFlight"
- `{{PLATFORM_EXAMPLE}}` = "Build app and upload to TestFlight"

**For Flutter:**
- `{{PLATFORM_AGENT}}` = `flutter-agent`
- `{{PLATFORM_KEYWORDS}}` = "flutter build", "pub get", "deploy"
- `{{PLATFORM_EXAMPLE}}` = "Build APK and deploy to Firebase"
```

---

## Customization Guide for Each Repo

### iOS Repository Setup

**1. Copy universal agents (automatic via workflow):**
```bash
# Synced automatically from backend
.claude/skills/project-manager/    # Universal
.claude/skills/zen-mcp-master/     # Universal
```

**2. Create iOS-specific agent:**
```bash
# Create manually in iOS repo
.claude/skills/xcode-agent/skill.md
```

**3. Customize project-manager:**
```bash
# Edit .claude/skills/project-manager/skill.md
# Replace {{PLATFORM_AGENT}} with xcode-agent
# Update delegation keywords for iOS
```

**4. Customize hooks:**
```bash
# Edit .claude/hooks/pre-commit.sh
# Add iOS-specific checks:
# - SwiftLint validation
# - Xcode project integrity
# - Storyboard validation
# - Asset catalog checks

# Edit .claude/hooks/post-tool-use.sh
# Add iOS-specific triggers:
# - xcodebuild commands → xcode-agent
# - Swift file edits → zen-mcp-master
# - Xcode project changes → xcode-agent
```

---

### Flutter Repository Setup (Future)

**Same pattern as iOS:**
1. Universal agents (synced automatically)
2. Create `flutter-agent` manually
3. Customize `project-manager`
4. Customize hooks

---

## Hook Templates

### Pre-Commit Hook Template

**File:** `.claude-template/hooks/pre-commit.sh.template`

```bash
#!/bin/bash
# Platform: {{PLATFORM}}
# Customize for your codebase

# Universal checks (same for all repos)
# 1. Check for sensitive files
# 2. Check for hardcoded secrets
# 3. Check for debug statements

# {{PLATFORM}}-specific checks
# Add your platform checks here:

# For Backend (Cloudflare):
# - wrangler.toml validation
# - JavaScript syntax check

# For iOS:
# - SwiftLint validation
# - Xcode project integrity

# For Flutter:
# - flutter analyze
# - Dart formatting check
```

---

### Post-Tool-Use Hook Template

**File:** `.claude-template/hooks/post-tool-use.sh.template`

```bash
#!/bin/bash
# Platform: {{PLATFORM}}

TOOL_NAME="${CLAUDE_TOOL_NAME:-}"

# Universal triggers
if [[ "$TOOL_NAME" == "MultiEdit" ]]; then
  INVOKE_AGENT="project-manager"
  AGENT_CONTEXT="Multiple files changed"
fi

# {{PLATFORM}}-specific triggers

# For Backend:
# npx wrangler → cloudflare-agent

# For iOS:
# xcodebuild → xcode-agent
# swift test → xcode-agent

# For Flutter:
# flutter build → flutter-agent
# pub get → flutter-agent
```

---

## Installation Instructions for Other Repos

### Step 1: Enable Template Sync (Backend)

```bash
cd bookstrack-backend

# Create template directory
mkdir -p .claude-template/skills
mkdir -p .claude-template/hooks
mkdir -p .claude-template/docs

# Copy current agents as templates
cp -r .claude/skills/project-manager .claude-template/skills/
cp -r .claude/skills/zen-mcp-master .claude-template/skills/

# Create hook templates
cp .claude/hooks/pre-commit.sh .claude-template/hooks/pre-commit.sh.template
cp .claude/hooks/post-tool-use.sh .claude-template/hooks/post-tool-use.sh.template

# Create sync workflow
# (Use workflow example above)

git add .claude-template/
git commit -m "feat: create Claude agent setup template for sharing"
git push
```

### Step 2: First Sync to iOS (Manual)

```bash
cd books-tracker-v1

# Create Claude directory structure
mkdir -p .claude/skills
mkdir -p .claude/hooks

# Copy universal agents from backend
cp -r ../bookstrack-backend/.claude-template/skills/project-manager .claude/skills/
cp -r ../bookstrack-backend/.claude-template/skills/zen-mcp-master .claude/skills/

# Copy hook templates
cp ../bookstrack-backend/.claude-template/hooks/pre-commit.sh.template .claude/hooks/pre-commit.sh
cp ../bookstrack-backend/.claude-template/hooks/post-tool-use.sh.template .claude/hooks/post-tool-use.sh

# Make hooks executable
chmod +x .claude/hooks/*.sh

# Customize for iOS
# Edit .claude/skills/project-manager/skill.md (replace {{PLATFORM_AGENT}} with xcode-agent)
# Edit .claude/hooks/* (add iOS-specific checks)

# Create iOS-specific agent
nano .claude/skills/xcode-agent/skill.md
# (Use xcode-agent template from above)

git add .claude/
git commit -m "feat: setup Claude agents (synced from backend template)"
git push
```

### Step 3: Future Updates (Automatic)

After first manual setup, backend workflow automatically syncs updates to iOS repo.

---

## Benefits of Sharing

**Consistency:**
- Same orchestration logic (project-manager)
- Same analysis tools (zen-mcp-master)
- Similar hook patterns

**Reduced Duplication:**
- Write once (backend), use everywhere
- Update once, sync automatically

**Platform Flexibility:**
- Each repo customizes for its tech stack
- Universal parts stay universal

**Easy Onboarding:**
- New repos get instant robit setup
- Just customize platform-specific agent

---

## Summary

**Universal (shared across all repos):**
- project-manager agent ✅
- zen-mcp-master agent ✅
- Hook templates ✅

**Platform-specific (per repo):**
- cloudflare-agent (backend only)
- xcode-agent (iOS only)
- flutter-agent (Flutter only)

**Automation:**
- `.github/workflows/sync-claude-setup.yml` syncs templates
- Each repo customizes from template
- Updates propagate automatically

---

**Next Steps:**
1. Create `.claude-template/` in backend
2. Create sync workflow
3. First manual sync to iOS
4. Enable automatic sync
5. iOS customizes xcode-agent
6. Test and iterate

**Questions?**
See `.claude/ROBIT_OPTIMIZATION.md` for original setup details.
