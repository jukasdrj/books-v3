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

exit 0
