# 🚀 BooksTrack Claude Code Quick Start

**Updated for Claude Code v2.0.43** | **November 18, 2025**

---

## 🤖 Custom Agents (The Power Trio)

### **@pm** - Your Autonomous Product Manager
**Call with:** `@pm` or just say "PM" in your message

**What it does:**
- Clarifies requirements (asks 1-2 questions max)
- Makes architecture decisions
- Delegates to Haiku (fast coding) + Grok-4 (expert review)
- Runs `/build` and `/test` automatically
- Delivers production-ready code

**Example:**
```
You: "@pm add pagination to library view"
PM: "Infinite scroll or page numbers?"
You: "Infinite scroll"
PM: [Delegates to Haiku → Reviews with Grok-4 → Validates → Delivers]
```

**Autonomy:** HIGH - Operates independently

---

### **@zen** - Deep Analysis Expert
**Call with:** `@zen` or ask for debugging/review

**What it does:**
- Complex debugging (crashes, race conditions)
- Comprehensive code review (Swift 6.2 compliance)
- Security audits (CloudKit, auth, data)
- Architectural analysis

**Example:**
```
You: "@zen debug this SwiftData crash"
Zen: [Uses mcp__zen__debug → Finds root cause → Reports findings]
```

**Autonomy:** MEDIUM - Works with PM

---

### **@xcode** - Build & Test Specialist
**Call with:** `@xcode` or use slash commands directly

**What it does:**
- Build validation (`/build`)
- Test execution (`/test`)
- Simulator launches (`/sim`)
- Device deployment (`/device-deploy`)

**Example:**
```
You: "@xcode run tests"
Xcode: [Executes /test → Reports results]

Or directly:
You: "/test"
```

**Autonomy:** MEDIUM - Executes commands

---

## ⚡ Slash Commands (XcodeBuildMCP)

```bash
/build          # Quick build validation (<30s)
/test           # Run full test suite (<2min)
/sim            # Launch in iOS Simulator (with live logs!)
/device-deploy  # Deploy to connected iPhone/iPad
```

**These work standalone OR through @xcode agent**

---

## 📋 Common Workflows

### **Quick Feature Request**
```
You: "@pm implement dark mode toggle"
→ PM handles everything (clarify, code, review, test)
```

### **Bug Fix**
```
You: "@zen debug the search crash"
→ Zen investigates
You: "@pm implement the fix"
→ PM codes + tests
```

### **Code Review**
```
You: "@zen review SearchView for Swift 6 compliance"
→ Zen analyzes with mcp__zen__codereview
```

### **Build & Test**
```
You: "/build"
→ Quick validation

You: "/test"
→ Run full suite

Or:
You: "@xcode validate everything"
→ Runs both + reports
```

---

## 🎯 When to Use What

### Use `@pm` when:
✅ Implementing features
✅ Refactoring code
✅ Want autonomous end-to-end workflow
✅ Need Haiku (fast) + Grok-4 (review)

### Use `@zen` when:
✅ Debugging complex issues
✅ Need code review
✅ Security audits required
✅ Architectural decisions

### Use `@xcode` when:
✅ Just need build/test
✅ Simulator/device testing
✅ Direct slash command execution

### Use built-in Claude when:
✅ Simple questions
✅ Quick edits
✅ File reading
✅ Documentation

---

## 💡 Pro Tips

**1. PM is autonomous - let it work!**
```
Good: "@pm add offline sync"
PM: [Handles everything]

Avoid: "@pm can you...?"
Just: "@pm [what you want]"
```

**2. Chain agents for complex tasks**
```
You: "@zen analyze this code"
→ Zen provides analysis
You: "@pm implement the recommendations"
→ PM executes
```

**3. Slash commands are fastest for simple tasks**
```
Quick: "/build"
Detailed: "@xcode validate and report issues"
```

**4. Hooks are logging for you**
```
Subagent usage logged to ~/.claude/logs/subagent-usage.log
Transcripts archived to ~/.claude/transcripts/
```

---

## 🔧 Your Setup

**MCPs Enabled:**
- ✅ Zen MCP (debug, codereview, secaudit, etc.)
- ✅ XcodeBuildMCP (slash commands)
- ✅ Filesystem MCP (file editing)

**Custom Agents:**
- ✅ @pm (autonomous orchestrator)
- ✅ @zen (deep analysis)
- ✅ @xcode (build/test)

**Hooks:**
- ✅ SubagentStart (logs agent invocations)
- ✅ SubagentStop (archives transcripts)
- ✅ pre-commit (iOS validation)

**Settings:**
- ✅ Permissions configured (.claude/settings.json)
- ✅ Ignore patterns set (DerivedData, etc.)
- ✅ Auto-compact enabled

---

## 🎬 Try It Now!

**Test PM agent:**
```
@pm create a simple test feature
```

**Test Zen agent:**
```
@zen review the Work.swift model for Swift 6 compliance
```

**Test Xcode agent:**
```
/build
```

---

## 📚 More Info

- **Full guide:** `CLAUDE.md`
- **Agent details:** `.claude/agents/*/agent.md`
- **Slash commands:** `.claude/commands/*.md`
- **Settings:** `.claude/settings.json`

---

**Questions?** Just ask! Claude Code and your custom agents are here to help.
