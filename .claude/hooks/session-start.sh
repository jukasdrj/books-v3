#!/bin/bash

# SessionStart Hook (v2.0.64)
# Triggered when a new Claude Code session begins
# Use for initialization, environment checks, or welcome messages
#
# New in v2.0.64:
# - Named sessions: use /rename to name, /resume <name> to restore
# - /stats command provides usage statistics and streak info
# - Auto-compacting is now instant
# - .claude/rules/ directory support for memory rules
#
# New in v2.0.65:
# - Switch models during prompt with alt+p (linux/win) or option+p (mac)
# - Context window info in status line
# - CLAUDE_CODE_SHELL env var for shell override

set -e

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Log session start
echo "🚀 Session started at $TIMESTAMP"
echo "📁 Project: $PROJECT_DIR"

# Track session starts (optional - for analytics)
LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
echo "$TIMESTAMP | SESSION_START | $PROJECT_DIR" >> "$LOG_DIR/session-history.log"

# Check for common iOS development issues
if [ -d "BooksTracker.xcodeproj" ]; then
    # Check for orphaned Xcode processes
    XCODE_PROCESSES=$(ps aux | grep -E "(Xcode|Simulator)" | grep -v grep | wc -l | xargs)

    if [ "$XCODE_PROCESSES" -gt 0 ]; then
        echo "⚠️ Warning: Found $XCODE_PROCESSES running Xcode/Simulator processes"
        echo "   Consider running /kill-xcode if you experience issues"
    fi

    # Check available system memory (macOS)
    if command -v vm_stat &> /dev/null; then
        FREE_MEM=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        FREE_GB=$((FREE_MEM * 4096 / 1024 / 1024 / 1024))

        if [ "$FREE_GB" -lt 4 ]; then
            echo "⚠️ Warning: Low system memory (${FREE_GB}GB free)"
            echo "   Use /quick-validate instead of /build to prevent crashes"
        fi
    fi
fi

# Check if OpenAPI spec is outdated (7+ days old)
SPEC_FILE="BooksTrackerPackage/Sources/BooksTrackerFeature/openapi.json"
if [ -f "$SPEC_FILE" ]; then
    SPEC_AGE=$(( $(date +%s) - $(stat -f %m "$SPEC_FILE" 2>/dev/null || stat -c %Y "$SPEC_FILE" 2>/dev/null || echo "0") ))
    DAYS_OLD=$(( SPEC_AGE / 86400 ))

    if [ "$SPEC_AGE" -gt 604800 ]; then
        echo "📋 Info: OpenAPI spec is $DAYS_OLD days old"
        echo "   Consider syncing: ./.claude/scripts/sync-openapi.sh"
    fi
fi

exit 0
