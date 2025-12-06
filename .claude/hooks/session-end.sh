#!/bin/bash

# SessionEnd Hook (v1.0.85+)
# Triggered when a Claude Code session ends
# Use for cleanup, final checks, or session summaries

set -e

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Log session end
echo "👋 Session ended at $TIMESTAMP"

# Track session ends (optional - for analytics)
LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
echo "$TIMESTAMP | SESSION_END | $PROJECT_DIR" >> "$LOG_DIR/session-history.log"

# Check for uncommitted changes
if [ -d ".git" ]; then
    UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | xargs)

    if [ "$UNCOMMITTED" -gt 0 ]; then
        echo "📝 Info: You have $UNCOMMITTED uncommitted changes"
        echo "   Run: git status"
    fi
fi

# Clean up temporary files (optional)
# Uncomment if you want automatic cleanup:
# rm -f build-quick.log build-safe.log 2>/dev/null || true

# Archive session transcript (optional)
# Uncomment to save session transcripts automatically:
# TRANSCRIPT_DIR="$HOME/.claude/transcripts/sessions"
# mkdir -p "$TRANSCRIPT_DIR"
# TRANSCRIPT_FILE="${TRANSCRIPT_DIR}/session_${TIMESTAMP// /_}.txt"
# echo "Session ended at $TIMESTAMP" > "$TRANSCRIPT_FILE"

echo "✅ Session cleanup complete"

exit 0
