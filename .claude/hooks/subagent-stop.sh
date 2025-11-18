#!/bin/bash

# SubagentStop Hook (v2.0.43)
# Triggered when a subagent completes its work

set -e

AGENT_ID="${AGENT_ID:-unknown}"
AGENT_TRANSCRIPT_PATH="${AGENT_TRANSCRIPT_PATH:-}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Log subagent completion
echo "✅ Subagent completed: $AGENT_ID at $TIMESTAMP"

# Track completion (optional - for analytics)
LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
echo "$TIMESTAMP | STOP | $AGENT_ID | $AGENT_TRANSCRIPT_PATH" >> "$LOG_DIR/subagent-usage.log"

# Optional: Archive transcripts for review
if [ -n "$AGENT_TRANSCRIPT_PATH" ] && [ -f "$AGENT_TRANSCRIPT_PATH" ]; then
    ARCHIVE_DIR="$HOME/.claude/transcripts"
    mkdir -p "$ARCHIVE_DIR"
    cp "$AGENT_TRANSCRIPT_PATH" "$ARCHIVE_DIR/${AGENT_ID}_${TIMESTAMP// /_}.txt" 2>/dev/null || true
fi

exit 0
