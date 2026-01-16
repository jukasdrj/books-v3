#!/bin/bash

# SubagentStop Hook (v2.0.64)
# Triggered when a subagent completes its work
#
# New in v2.0.64:
# - Handles async agent completion notifications
# - Background agents can now wake up main agent with messages
# - TaskOutput tool replaced AgentOutputTool and BashOutputTool

set -e

AGENT_ID="${AGENT_ID:-unknown}"
AGENT_TYPE="${AGENT_TYPE:-unknown}"
AGENT_TRANSCRIPT_PATH="${AGENT_TRANSCRIPT_PATH:-}"
WAS_BACKGROUND="${WAS_BACKGROUND:-false}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Log subagent completion
if [ "$WAS_BACKGROUND" = "true" ]; then
    echo "✅ Background agent completed: $AGENT_ID ($AGENT_TYPE) at $TIMESTAMP"
    echo "   Results available via TaskOutput tool"
else
    echo "✅ Subagent completed: $AGENT_ID ($AGENT_TYPE) at $TIMESTAMP"
fi

# Track completion (optional - for analytics)
LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
echo "$TIMESTAMP | STOP | $AGENT_ID | $AGENT_TYPE | background=$WAS_BACKGROUND | $AGENT_TRANSCRIPT_PATH" >> "$LOG_DIR/subagent-usage.log"

# Optional: Archive transcripts for review
if [ -n "$AGENT_TRANSCRIPT_PATH" ] && [ -f "$AGENT_TRANSCRIPT_PATH" ]; then
    ARCHIVE_DIR="$HOME/.claude/transcripts"
    mkdir -p "$ARCHIVE_DIR"
    SAFE_TIMESTAMP="${TIMESTAMP// /_}"
    SAFE_TIMESTAMP="${SAFE_TIMESTAMP//:/-}"
    cp "$AGENT_TRANSCRIPT_PATH" "$ARCHIVE_DIR/${AGENT_ID}_${SAFE_TIMESTAMP}.txt" 2>/dev/null || true
fi

# PAL MCP Review Gate (PM Orchestration Mode)
# Require review of subagent outputs before integration
# Context: BooksTrack = Solo-dev family app (pragmatic quality bar)

IMPLEMENTATION_AGENTS=("Explore" "general-purpose" "feature-dev" "Bash")
SECURITY_AGENTS=("cloudflare-specialist" "security-auditor")

# Only review non-background agents (background already reviewed in parallel)
if [ "$WAS_BACKGROUND" = "false" ]; then
    # Check if implementation work requires code review
    if [[ " ${IMPLEMENTATION_AGENTS[@]} " =~ " ${AGENT_TYPE} " ]]; then
        echo ""
        echo "⚠️  REVIEW GATE: Implementation work detected"
        echo "   Before integrating subagent output, run PAL MCP review:"
        echo "   → mcp__pal__codereview (model: grok-code-fast-1)"
        echo "   → Focus: correctness, architecture, performance, obvious bugs"
        echo "   → Bar: 'Good enough for family app' (not enterprise-grade)"
        echo ""
    fi

    # Check if security work requires audit
    if [[ " ${SECURITY_AGENTS[@]} " =~ " ${AGENT_TYPE} " ]]; then
        echo ""
        echo "⚠️  SECURITY GATE: Security-critical work detected"
        echo "   Before integrating subagent output, run PAL MCP audit:"
        echo "   → mcp__pal__secaudit (model: grok-code-fast-1)"
        echo "   → Focus: API keys exposure, obvious vulns, broken auth"
        echo "   → Context: Family app (low attack surface, pragmatic security)"
        echo ""
    fi
fi

exit 0
