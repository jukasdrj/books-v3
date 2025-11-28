---
description: Emergency cleanup - kill all Xcode/Simulator processes
---

🚨 **Emergency Xcode Cleanup** 🚨

Kill all Xcode, Simulator, and xcodebuild processes to recover from system overload.

**Tasks:**

1. **Execute Emergency Cleanup**
   - Run `.claude/scripts/kill-all-xcode.sh`
   - Kill Xcode, Simulator, xcodebuild, CoreSimulator
   - Kill indexing services (SourceKit, XCBuild)

2. **Verify Cleanup**
   - Check no processes remain: `ps aux | grep -E "(Xcode|Simulator|xcodebuild)"`
   - Report what was killed

3. **Recommend Next Steps**
   - Wait 10 seconds for processes to fully terminate
   - Suggest using `/quick-validate` for safe testing
   - Suggest real device testing (`/device-deploy`) if UI validation needed

**Use when:**
- System becomes unresponsive
- High CPU/memory usage from Xcode processes
- Simulator won't quit normally
- Before starting fresh development session
