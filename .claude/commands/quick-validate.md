---
description: Quick build validation without Simulator (safe)
---

🔍 **Quick Build Validation** 🔍

Validate code changes without launching Simulator - prevents system crashes.

**Tasks:**

1. **Execute Safe Build Script**
   - Run `.claude/scripts/quick-validate.sh`
   - Build with 2 parallel jobs (low resource usage)
   - 5-minute timeout
   - Output to `build-quick.log`

2. **Report Results**
   - If success: Confirm build passed
   - If failure: Show relevant errors from log
   - Suggest next steps (real device testing, fixes needed)

**Target:** iOS Simulator (build only, no launch)
**Configuration:** Debug
**Resource Usage:** ~4GB RAM, ~200% CPU

**Use this instead of /build when:**
- Testing code changes during development
- Validating Swift 6 concurrency fixes
- Checking for zero warnings compliance
- System resources are limited
