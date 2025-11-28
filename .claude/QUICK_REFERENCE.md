# Quick Reference: Safe Testing Commands

## 🚀 What to Use When

| Situation | Command | Why |
|-----------|---------|-----|
| Changed code, need to validate | `/quick-validate` | Fast, safe, no Simulator |
| Need to test UI | `/device-deploy` | Real device = best performance |
| Must use Simulator | `/sim-safe` | Resource-limited, monitored |
| System frozen/slow | `/kill-xcode` | Emergency cleanup |
| Running tests | `/test` | Swift Testing suite |

## 📊 Resource Comparison

| Command | CPU | RAM | Crash Risk | Speed |
|---------|-----|-----|------------|-------|
| `/quick-validate` | 200% | 4GB | ✅ None | ⚡ Fast |
| `/device-deploy` | 100% | 2GB | ✅ None | ⚡ Fast |
| `/sim-safe` | 300% | 6GB | ⚠️ Low | 🐢 Slow |
| `/build` | 400% | 8GB | ⚠️ Medium | 🐢 Slow |
| `/sim` | 600% | 12GB | ❌ High | 🐌 Very Slow |

## 💬 What to Say to Claude

**Instead of:** "Build and test"
**Say:** "Validate my changes"
→ Claude uses `/quick-validate`

**Instead of:** "Run in Simulator"
**Say:** "Test this safely"
→ Claude offers real device or `/sim-safe`

**Instead of:** "Xcode is frozen"
**Say:** "Cleanup"
→ Claude uses `/kill-xcode`

## 🆘 Emergency Shortcuts

**System Unresponsive:**
```bash
./.claude/scripts/kill-all-xcode.sh
```

**Quick Build Check:**
```bash
./.claude/scripts/quick-validate.sh
```

**Safe Simulator Test:**
```bash
./.claude/scripts/safe-test.sh
```

## 📝 Remember

1. **Always start with `/quick-validate`**
2. **Real device > Simulator** (when possible)
3. **Use `/sim-safe`, not `/sim`**
4. **Keep `/kill-xcode` ready** for emergencies

---

**Full docs:** `.claude/SAFE_TESTING.md`
