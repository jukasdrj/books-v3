# Safe Testing Guide - Preventing System Crashes

**Problem:** Xcode builds and iOS Simulator can overwhelm CPU/memory, causing system lockups.

**Solution:** Resource-limited testing scripts with monitoring and auto-cleanup.

---

## Quick Reference

### **Option 1: Quick Build Validation (Recommended)**
```bash
./.claude/scripts/quick-validate.sh
```
- **What:** Builds project without launching Simulator
- **Resources:** 2 parallel jobs, 5-minute timeout
- **Best for:** Validating code changes, checking for compile errors
- **Safe:** Yes - no Simulator overhead

### **Option 2: Monitored Simulator Testing**
```bash
./.claude/scripts/safe-test.sh
```
- **What:** Full build + Simulator launch with resource monitoring
- **Resources:** 4 parallel jobs, 8GB RAM limit, 10-minute auto-kill
- **Best for:** Integration testing, UI validation
- **Safe:** Yes - auto-kills on resource limits

### **Option 3: Emergency Cleanup**
```bash
./.claude/scripts/kill-all-xcode.sh
```
- **What:** Kills all Xcode/Simulator processes immediately
- **Best for:** When system becomes unresponsive
- **Use:** Press Ctrl+Alt+Esc → Terminal → run script

---

## Detailed Usage

### Quick Build Validation

**Use this for:**
- Code syntax validation
- Swift 6 concurrency checks
- Zero warnings policy verification
- Fast iteration cycles

**Example workflow:**
```bash
# Make changes to LibraryView.swift
vim BooksTrackerPackage/Sources/Features/LibraryView.swift

# Validate changes (no Simulator)
./.claude/scripts/quick-validate.sh

# If build succeeds, commit
git add .
git commit -m "Update LibraryView filters"
```

**Output:**
- Build logs saved to `build-quick.log`
- Exit code 0 = success, 1 = failure

---

### Monitored Simulator Testing

**Use this for:**
- UI/UX validation
- Integration testing
- Real-time log analysis
- Performance testing (with limits)

**Example workflow:**
```bash
# Run safe simulator test
./.claude/scripts/safe-test.sh

# Script will:
# 1. Check you have 4GB+ RAM free
# 2. Warn if CPU load >70%
# 3. Build with 4 parallel jobs max
# 4. Monitor memory every 5s (kill if >8GB)
# 5. Auto-kill after 10 minutes
# 6. Stream logs to terminal
```

**Monitoring output:**
```
Process 12345: 2.34GB RAM, 120% CPU
Process 12345: 3.12GB RAM, 145% CPU
...
KILL: Memory limit exceeded (8.2GB > 8GB)
```

**Resource limits:**
- **Memory:** 8GB max (auto-kill)
- **CPU:** 400% warning (4 cores × 100%)
- **Runtime:** 10 minutes max (auto-kill)
- **Build timeout:** 5 minutes

---

### Emergency Cleanup

**Use when:**
- System becomes unresponsive
- Fans running at max speed
- Activity Monitor shows runaway processes
- Xcode frozen/beachballing

**Steps:**
1. Press `Cmd+Space` → type "Terminal" → Enter
2. Run: `cd ~/dev_repos/books-v3`
3. Run: `./.claude/scripts/kill-all-xcode.sh`
4. Wait 10 seconds
5. Close Xcode if still open
6. Reopen Xcode

**Alternative (if Terminal frozen):**
1. Press `Cmd+Option+Esc` (Force Quit)
2. Select "Xcode" → Force Quit
3. Select "Simulator" → Force Quit
4. Wait 30 seconds
5. Open Terminal and run cleanup script

---

## Prevention Strategies

### **Before Starting Development Session:**

1. **Close unnecessary apps:**
   - Chrome (notorious memory hog)
   - Slack, Discord
   - Other IDEs (VS Code, etc.)

2. **Check available resources:**
   ```bash
   # Check free memory
   vm_stat | grep "Pages free"

   # Check CPU load
   uptime

   # If load >70%, wait or restart
   ```

3. **Clean Xcode derived data:**
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/BooksTracker-*
   ```

### **During Development:**

1. **Use quick validation first:**
   - Always try `quick-validate.sh` before `safe-test.sh`
   - Only use Simulator when UI testing needed

2. **Monitor Activity Monitor:**
   - Keep Activity Monitor open (Cmd+Space → "Activity Monitor")
   - Watch for xcodebuild processes >4GB RAM
   - Watch for Simulator processes >2GB RAM

3. **Set up keyboard shortcuts:**
   - Add `kill-all-xcode.sh` to your shell aliases:
     ```bash
     # In ~/.zshrc or ~/.bashrc
     alias killxcode='~/dev_repos/books-v3/.claude/scripts/kill-all-xcode.sh'
     ```

### **Alternative Testing Strategies:**

#### **Strategy A: Build-Only Development**
```bash
# 1. Make changes
vim BooksTrackerPackage/Sources/Features/LibraryView.swift

# 2. Quick validate (no Simulator)
./.claude/scripts/quick-validate.sh

# 3. Test on real device (less resource-intensive)
/device-deploy  # Uses slash command
```

#### **Strategy B: Real Device Testing**
- Use `/device-deploy` slash command
- Connects to iPhone/iPad via USB
- Much lighter on system resources than Simulator
- Shows real-world performance

**Setup:**
1. Connect iPhone/iPad via USB
2. Trust computer on device
3. Run: `/device-deploy`

#### **Strategy C: Cloud CI/CD**
- Push to GitHub
- Let GitHub Actions run tests
- Review results remotely
- Zero local resource usage

**Setup:** Already configured in `.github/workflows/`

---

## Claude Code Integration

### **Slash Commands (Updated)**

**Use these instead of direct `/sim` or `/build`:**

```bash
# Safe build validation (no Simulator)
/quick-validate

# Monitored Simulator test
/sim-safe

# Emergency cleanup
/kill-xcode
```

**How to add slash commands:**

1. Create `.claude/commands/quick-validate.md`:
   ```markdown
   ---
   description: Quick build validation without Simulator
   ---
   Run the quick validation script to build without launching Simulator.
   Use bash tool to execute: `./.claude/scripts/quick-validate.sh`
   ```

2. Create `.claude/commands/sim-safe.md` (already exists)

3. Create `.claude/commands/kill-xcode.md`:
   ```markdown
   ---
   description: Emergency cleanup - kill all Xcode processes
   ---
   Run emergency cleanup script to kill all Xcode/Simulator processes.
   Use bash tool to execute: `./.claude/scripts/kill-all-xcode.sh`
   ```

### **MCP Workflow (Recommended)**

When asking Claude to test changes:

**Instead of:**
> "Build and test in Simulator"

**Say:**
> "Use quick-validate to check for errors, then we'll test on real device"

**Claude will:**
1. Run `quick-validate.sh`
2. Check build logs
3. Suggest `/device-deploy` if UI testing needed

---

## Troubleshooting

### **"Insufficient memory" error**
```bash
# Check what's using memory
top -o MEM

# Close memory hogs:
killall "Google Chrome"
killall "Slack"

# Try again
./.claude/scripts/safe-test.sh
```

### **Build times out after 5 minutes**
```bash
# Reduce parallel jobs (edit safe-test.sh)
PARALLEL_JOBS=2  # Down from 4

# Or increase timeout
BUILD_TIMEOUT=600  # 10 minutes
```

### **Script says "Resource check passed" but system still slow**
- Reduce `MAX_MEMORY_GB=6` (down from 8)
- Reduce `PARALLEL_JOBS=2` (down from 4)
- Close more background apps

### **Simulator still crashes**
- Use real device testing instead (`/device-deploy`)
- Run tests on GitHub Actions (cloud CI/CD)
- Test one feature at a time (don't stress test)

---

## Performance Benchmarks

**Typical resource usage:**

| Task | CPU | Memory | Safe? |
|------|-----|--------|-------|
| Quick validate | 200% | 4GB | ✅ Yes |
| Safe Simulator | 300% | 6GB | ✅ Yes (monitored) |
| Regular /sim | 600% | 12GB | ❌ Can crash |
| Real device | 100% | 2GB | ✅ Very safe |

**Recommendations by system specs:**

| RAM | Best approach |
|-----|---------------|
| 8GB | Real device only |
| 16GB | Quick validate + real device |
| 32GB+ | Safe Simulator OK |

---

## Summary

**Golden Rule:** Always start with `quick-validate.sh`, only use Simulator when necessary.

**Three-tier approach:**
1. **Quick validate** - Fast syntax/compile checks (0 crashes)
2. **Safe Simulator** - Monitored testing (rare crashes)
3. **Real device** - Production-like testing (0 crashes)

**Emergency:** Keep `kill-all-xcode.sh` aliased for instant access.

**Integration:** Use `/quick-validate` slash command in Claude Code workflows.

---

**Last Updated:** November 28, 2025
**Maintained by:** oooe (jukasdrj)
