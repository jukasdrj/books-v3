# Claude Code Agent Setup (iOS)

**Synced from:** bookstrack-backend (manual setup)
**Tech Stack:** Swift, SwiftUI, Xcode

## Available Agents

### ✅ Universal Agents (Synced from Backend)
- **project-manager** - Orchestration and delegation
- **zen-mcp-master** - Deep analysis (14 Zen MCP tools)

### 🚧 iOS-Specific Agent (TODO)
- **xcode-agent** - Xcode build, test, TestFlight deployment

## Quick Start

```bash
# For complex workflows
/skill project-manager

# For analysis/review/debugging
/skill zen-mcp-master

# For iOS build/test (after creating xcode-agent)
/skill xcode-agent
```

## Next Steps

### 1. Create xcode-agent (Required)

Create `.claude/skills/xcode-agent/skill.md` with iOS-specific capabilities:

- Xcode build commands (`xcodebuild`)
- Swift testing (`swift test`)
- TestFlight deployment
- Swift package management
- Crash log analysis

See `.claude/ROBIT_SHARING_FRAMEWORK.md` for xcode-agent template.

### 2. Customize project-manager

Edit `.claude/skills/project-manager/skill.md`:
- Replace `cloudflare-agent` references with `xcode-agent`
- Update delegation patterns for iOS workflows

### 3. Add Hooks (Optional)

**Pre-commit hook** (`.claude/hooks/pre-commit.sh`):
- SwiftLint validation
- Xcode project integrity checks
- Asset catalog validation

**Post-tool-use hook** (`.claude/hooks/post-tool-use.sh`):
- Suggest `xcode-agent` when xcodebuild is used
- Suggest `zen-mcp-master` for Swift file changes

## Documentation

- `ROBIT_OPTIMIZATION.md` - Complete agent architecture
- `ROBIT_SHARING_FRAMEWORK.md` - How sharing works
- Backend repo: https://github.com/jukasdrj/bookstrack-backend/.claude/

## Future Updates

Run `../bookstrack-backend/scripts/sync-robit-to-repos.sh` to sync updates from backend.
