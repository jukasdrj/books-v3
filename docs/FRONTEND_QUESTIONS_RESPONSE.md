# Frontend Questions Response - November 20, 2025

**Status:** All questions addressed with comprehensive implementation details
**Issues Resolved:** #489 (ping/pong), #497 (token refresh implementation)
**Documentation Updated:** `docs/API_CONTRACT.md`

---

## Issue #489: WebSocket ping/pong Messages

### Question
The API contract mentions `ping` and `pong` message types in two locations (lines 1246-1247 and 1314-1316), but the OpenAPI spec doesn't document them. Are these implemented?

### Answer: ❌ NOT IMPLEMENTED

**Status:** These message types are **planned but not yet implemented**.

**What We Changed:**
1. ✅ Removed `ping` and `pong` from MessageType enum (lines 1314-1316)
2. ✅ Updated Heartbeat section (lines 1246-1247) to clarify they're not needed

**Updated Documentation (API_CONTRACT.md:1246-1247):**
```markdown
**Heartbeat:**
- Not required - Cloudflare Workers automatically handles connection health
- Connections remain active for duration of job (up to 2 hours with auto token refresh)
```

**Client Implementation:**
```swift
// ❌ DON'T implement ping/pong handling
// ✅ Cloudflare Workers keeps connections alive automatically

let webSocket = URLSession.shared.webSocketTask(with: request)
webSocket.resume()

// No need to send periodic pings - server handles this
```

**Why They're Not Needed:**
- Cloudflare Workers platform maintains WebSocket connections automatically
- No manual heartbeat required for connections under 2 hours
- Token auto-refresh system (every 15 minutes) acts as implicit keep-alive

**If You See Disconnections:**
- Check for iOS app backgrounding (iOS suspends WebSocket connections when app goes to background)
- Verify token hasn't expired (2-hour lifetime with 30-minute auto-refresh window)
- Use reconnection logic (see Section 7.5 in API_CONTRACT.md)

---

## Issue #497: Token Refresh Implementation Details

### Question
The API contract says token refresh is "automatic" and "production ready," but doesn't explain the backend implementation. How does it actually work?

### Answer: ✅ FULLY IMPLEMENTED (Backend Details Added)

**Status:** Automatic token refresh is **fully implemented** using Durable Object alarms. No client code changes required.

### Backend Implementation (New Documentation)

**Updated Section (API_CONTRACT.md:367-381):**

#### Architecture Overview

**Alarm System:**
- Durable Object schedules alarms every **15 minutes** to check token expiration
- Alarm fires automatically even if client is idle
- Checks if token expiration is < 30 minutes away

**Implementation Files:**
- `src/durable-objects/progress-socket.js:698` - `scheduleTokenRefreshCheck()`
- `src/durable-objects/progress-socket.js:770` - `autoRefreshToken()`
- `src/durable-objects/progress-socket.js:1545` - Alarm handler

**Refresh Flow:**

1. **Initial Connection:**
   - Client connects with token (2-hour expiration)
   - Durable Object stores `authToken` and `authTokenExpiration` in KV
   - Schedules first alarm for 15 minutes

2. **Alarm Fires (Every 15 Minutes):**
   ```javascript
   // Check if token expires in < 30 minutes
   const timeUntilExpiration = expiration - Date.now();
   const REFRESH_WINDOW_MS = 30 * 60 * 1000; // 30 minutes

   if (timeUntilExpiration < REFRESH_WINDOW_MS && timeUntilExpiration > 0) {
     // Auto-refresh token
     await this.autoRefreshToken();
   }
   ```

3. **Auto-Refresh Process:**
   - Generates new token (crypto.randomUUID())
   - Extends expiration by **2 hours** from refresh time
   - Updates KV storage: `authToken` and `authTokenExpiration`
   - **Blacklists old token** with 2.5-hour TTL (prevents replay attacks)
   - **5-minute grace period:** Old token still works for reconnections during this window

4. **Conflict Prevention:**
   - Durable Objects support **only ONE alarm** per instance
   - If job processing alarm is active (CSV import, batch scan), token refresh alarm is **delayed by 5 seconds**
   - This ensures job alarms fire first, then token refresh resumes

#### Token Blacklist Security

**Why Blacklist Old Tokens?**
- Prevents replay attacks if old token is intercepted
- Old tokens become invalid after new token is issued
- Exception: 5-minute grace period for reconnections

**Implementation:**
```javascript
// Old token storage key format
const oldTokenKey = `oldToken_${oldToken}_${Date.now()}`;

// Blacklist with TTL (2.5 hours = 2hr expiration + 30min buffer)
await this.storage.put({
  [`blacklist_${oldToken}`]: {
    blacklistedAt: Date.now(),
    reason: "Token refreshed",
    jobId: this.jobId
  }
}, { expirationTtl: 2.5 * 60 * 60 }); // 9000 seconds
```

#### Client Perspective

**What Clients Need to Know:**

1. **No Action Required:**
   - Tokens are refreshed automatically while WebSocket is connected
   - Client doesn't receive notification of refresh (transparent)
   - Connection stays alive for full job duration (even if > 2 hours)

2. **Token Lifespan:**
   - Initial token: 2 hours
   - After auto-refresh: 2 hours from refresh time
   - Maximum job duration: **Unlimited** (token keeps refreshing every 15 min)

3. **Disconnection Handling:**
   - If client disconnects and reconnects **within 5 minutes** of auto-refresh: Old token still works
   - If client disconnects for > 5 minutes: Old token is blacklisted, reconnection fails
   - **Best practice:** Always use the **latest token** from initial job creation response

4. **Token Expiration Scenarios:**
   ```swift
   // Scenario 1: Active WebSocket (token refreshed automatically)
   // Client starts job at 10:00 AM with token expiring at 12:00 PM
   // At 11:30 AM: Alarm triggers, new token issued (expires at 1:30 PM)
   // At 1:00 PM: Alarm triggers again, new token issued (expires at 3:00 PM)
   // Job completes at 2:45 PM - no issues

   // Scenario 2: Disconnected client (token NOT refreshed)
   // Client starts job at 10:00 AM, disconnects at 10:15 AM
   // At 11:30 AM: Alarm tries to refresh, but no active WebSocket
   // At 12:00 PM: Token expires
   // Client tries to reconnect at 12:30 PM: ❌ Token expired, must start new job

   // Scenario 3: Reconnection during grace period
   // Client starts job at 10:00 AM with token A
   // At 11:30 AM: Token A refreshed to token B (token A has 5-min grace period)
   // Client disconnects at 11:32 AM
   // Client reconnects at 11:34 AM with token A: ✅ Succeeds (grace period)
   // Client reconnects at 11:36 AM with token A: ❌ Fails (grace period expired)
   ```

#### Testing Token Refresh

**Local Testing (wrangler dev):**
```bash
# Start dev server
npx wrangler dev --remote

# Connect with wscat
wscat -c "ws://localhost:8787/ws/progress?jobId=test-123&token=test-token" \
  --subprotocol "bookstrack-auth.test-token"

# Monitor logs for token refresh messages
# Look for: "[test-123] Token expires in 29min - refreshing automatically"
```

**Production Testing:**
```bash
# 1. Start long-running job (CSV import with 1000+ rows)
curl -X POST https://api.oooefam.net/api/csv/import \
  -H "Content-Type: application/json" \
  -d '{"csv": "...large CSV data..."}'

# Response: { "jobId": "abc123", "token": "xyz789" }

# 2. Connect WebSocket
wscat -c "wss://api.oooefam.net/ws/progress?jobId=abc123" \
  --subprotocol "bookstrack-auth.xyz789"

# 3. Wait 30+ minutes (or modify token expiration for testing)
# 4. Check Cloudflare Workers logs for token refresh events

# Expected logs:
# [abc123] Token refresh check scheduled for 2025-11-20T10:15:00.000Z
# [abc123] Token expires in 29min - refreshing automatically
# [abc123] ✅ Token refreshed successfully, new expiration: 2025-11-20T12:45:00.000Z
# [abc123] ✅ Auth token invalidated and blacklisted (TTL: 2.5 hours)
```

#### Edge Cases & Error Handling

**1. Token Expiration During Job:**
- **Scenario:** Job runs > 2 hours, but client misses auto-refresh
- **Behavior:** Next message send fails with `1008 POLICY_VIOLATION`
- **Solution:** Client should reconnect (if within grace period) or restart job

**2. Multiple Clients with Same Token:**
- **Scenario:** Client A and Client B both use token X
- **Behavior:** Token refresh invalidates token X for BOTH clients
- **Solution:** Each client should request separate job (unique tokens per job)

**3. Alarm Conflicts (Job Processing vs Token Refresh):**
- **Scenario:** CSV import alarm scheduled for 10:00 AM, token refresh alarm also tries to schedule for 10:00 AM
- **Behavior:** Token refresh alarm is **delayed by 5 seconds** (10:00:05 AM)
- **Solution:** Automatic - no client action required

**4. Token Refresh During Reconnection:**
- **Scenario:** Client disconnects at 11:29 AM, token refreshes at 11:30 AM, client reconnects at 11:31 AM
- **Behavior:** Old token works if within 5-minute grace period
- **Solution:** Client should track latest token from initial job response

---

## Summary of Changes

### Documentation Updates (API_CONTRACT.md)

**Section 7.1 (WebSocket Connection):**
- ✅ Removed `ping` and `pong` from connection flow
- ✅ Updated Heartbeat section to clarify no manual heartbeat needed

**Section 7.2 (Message Format):**
- ✅ Removed `ping` and `pong` from MessageType enum

**Section 3.1 (Token Management):**
- ✅ Added "Backend Implementation" subsection with 7 implementation details
- ✅ Added alarm scheduling explanation (15-minute intervals)
- ✅ Added token blacklist security details (2.5-hour TTL)
- ✅ Added conflict prevention logic (job alarms vs token refresh alarms)
- ✅ Updated "Refresh Window" to clarify 5-minute grace period for old tokens

### Client Impact

**Breaking Changes:** ❌ None

**Required Client Changes:** ❌ None
- Token refresh is fully automatic and transparent
- Clients continue using tokens exactly as before
- No new message types to handle

**Optional Improvements:**
```swift
// iOS: Monitor WebSocket disconnections and reconnect logic
func handleDisconnection(error: Error?) {
    if error?.localizedDescription.contains("1008") == true {
        // Token expired - must start new job
        print("Token expired, restarting job")
        startNewJob()
    } else {
        // Network issue - retry with same token (within 5-min grace period)
        print("Network issue, retrying connection")
        reconnectWebSocket(with: currentToken)
    }
}
```

---

## Testing Recommendations

### Frontend Integration Tests

**Test 1: Long-Running Job (> 2 Hours)**
```swift
// Start job at 10:00 AM
let response = await startBatchEnrichment(books: largeBatchOf500Books)
let jobId = response.jobId
let token = response.token

// Connect WebSocket
let ws = connectWebSocket(jobId: jobId, token: token)

// Wait for job completion (should take 2+ hours)
// Expected: Connection stays alive entire duration
// Expected: No token expiration errors
```

**Test 2: Reconnection After Token Refresh**
```swift
// Start job, disconnect after 90 minutes
let response = await startCSVImport(csv: largeCSV)
let ws = connectWebSocket(jobId: response.jobId, token: response.token)

// Disconnect at T+90 minutes (after auto-refresh at T+90)
ws.cancel(with: .normalClosure, reason: nil)

// Reconnect at T+92 minutes (within 5-min grace period)
let wsReconnected = connectWebSocket(jobId: response.jobId, token: response.token)

// Expected: Reconnection succeeds
// Expected: Receive reconnected message with current progress
```

**Test 3: Token Expiration (Idle Connection)**
```swift
// Start job, disconnect immediately
let response = await startJob()
let ws = connectWebSocket(jobId: response.jobId, token: response.token)
ws.cancel(with: .normalClosure, reason: nil)

// Wait 2+ hours (token expires)
sleep(2 * 60 * 60)

// Try to reconnect with expired token
let wsExpired = connectWebSocket(jobId: response.jobId, token: response.token)

// Expected: Connection fails with 1008 POLICY_VIOLATION
// Expected: Error message contains "Token expired"
```

---

## Additional Resources

**Related Documentation:**
- `docs/API_CONTRACT.md` - Full API contract (updated with token refresh details)
- `docs/deployment/TROUBLESHOOTING_RUNBOOK.md:484` - Token refresh troubleshooting
- `src/durable-objects/progress-socket.js` - Token refresh implementation
- `tests/integration/websocket-token.test.js` - Token refresh integration tests

**Related Issues:**
- #163 - Token authentication security fix (Sec-WebSocket-Protocol)
- #164 - Token blacklist cleanup (TTL expiration)
- #407 - WebSocket upgrade performance optimization
- #127 - Reconnection support

**Production Monitoring:**
```bash
# Stream logs to monitor token refresh events
npx wrangler tail --format pretty | grep "Token"

# Example output:
# [abc123] Token refresh check scheduled for 2025-11-20T10:15:00.000Z
# [abc123] Token expires in 29min - refreshing automatically
# [abc123] ✅ Token refreshed successfully
# [abc123] ✅ Auth token invalidated and blacklisted (TTL: 2.5 hours)
```

---

**Last Updated:** November 20, 2025
**Prepared By:** Backend Team (Claude Code)
**For:** Frontend Team
**Status:** Ready for iOS/Web Integration
