---
description: Safe iOS Simulator launch with resource limits and monitoring
---

📲 **Safe Simulator Launch** 📲

Launch iOS Simulator with resource limits to prevent system crashes.

**Safety Features:**
- CPU and memory monitoring
- Automatic process cleanup on limits exceeded
- Graceful shutdown on resource pressure
- Background process prevention

**Tasks:**

1. **Pre-flight Check**
   - Check available system memory (require 4GB+ free)
   - Check CPU load (warn if >70%)
   - Kill any orphaned simulators or build processes

2. **Resource-Limited Build**
   - Build with limited parallel tasks (max 4)
   - Stream build output to file (prevent console overflow)
   - Timeout after 5 minutes

3. **Monitored Simulator Launch**
   - Boot simulator with resource monitoring
   - Install app with timeout (2 minutes max)
   - Launch app with watchdog timer

4. **Active Monitoring**
   - Monitor process memory every 5 seconds
   - Kill if memory exceeds 8GB
   - Kill if CPU time exceeds 10 minutes
   - Auto-cleanup on exit

**Target Simulator:** iPhone 17 Pro (iOS 26.0)
**Configuration:** Debug
**Resource Limits:** 8GB RAM, 4 parallel jobs, 10min max runtime

Use this instead of `/sim` when system stability is a concern.
