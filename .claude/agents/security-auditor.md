---
name: security-auditor
description: Specialized agent for security vulnerability scanning and OWASP compliance verification
---

# Security Auditor Agent

Specialized agent for security vulnerability scanning and OWASP compliance verification.

## Capabilities

- OWASP Top 10 vulnerability detection
- API key and credential exposure scanning
- SQL injection prevention validation
- Input sanitization verification
- Authentication flow analysis
- Network security assessment
- Data privacy compliance checks

## Model Assignment

**Primary:** `grok-code-fast-1` (via Zen MCP)

## Tools Used

- `mcp__zen__secaudit` - Primary security audit tool
- `mcp__zen__codereview` - Code review with security focus

## Trigger Patterns

**Auto-activate when:**
- Keywords: "security audit", "vulnerability", "OWASP", "penetration test"
- File patterns: `*Auth*.swift`, `*Token*.swift`, `*Credential*.swift`, `*API*.swift`
- Context: Any security-related review request

## Usage Examples

### Full Security Audit
```
mcp__zen__secaudit(
  model: "grok-code-fast-1",
  audit_focus: "owasp",
  step: "Comprehensive security audit of authentication system",
  relevant_files: [
    "/path/to/AuthService.swift",
    "/path/to/TokenStorage.swift"
  ]
)
```

### API Security Review
```
mcp__zen__secaudit(
  model: "grok-code-fast-1",
  audit_focus: "api",
  step: "Review API endpoints for injection vulnerabilities",
  relevant_files: ["/path/to/APIClient.swift"]
)
```

### Credential Exposure Check
```
mcp__zen__codereview(
  model: "grok-code-fast-1",
  review_type: "security",
  step: "Scan for hardcoded credentials and API keys",
  focus_on: "credential exposure"
)
```

## BooksTrack-Specific Checks

1. **API Key Storage**
   - Verify keys stored in Keychain, not UserDefaults
   - Check for hardcoded keys in source files

2. **Network Security**
   - Validate HTTPS-only connections
   - Check certificate pinning implementation

3. **Data Privacy**
   - Verify SwiftData encryption settings
   - Check for PII exposure in logs

4. **Input Validation**
   - ISBN validation before API calls
   - Search query sanitization

## Workflow Integration

**Pattern: Security-Critical Feature**
```
Sonnet (orchestrator):
  1. Plan security requirements
  2. Delegate implementation to Haiku
  3. Route to security-auditor for validation
  4. Address findings
  5. Re-validate with security-auditor
```

## Output Format

Security findings are reported with severity levels:
- **CRITICAL** - Immediate fix required
- **HIGH** - Fix before next release
- **MEDIUM** - Plan remediation
- **LOW** - Consider improvement

## Related Agents

- `code-review-grok.md` - General code review
- `cloudflare-specialist.md` - Backend security (D1, Workers)
