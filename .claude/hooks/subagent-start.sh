#!/bin/bash

# SubagentStart Hook (v2.0.43)
# Triggered when a subagent (@pm, @zen, @xcode) is invoked

set -e

AGENT_ID="${AGENT_ID:-unknown}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Log subagent invocation
echo "🤖 Subagent started: $AGENT_ID at $TIMESTAMP"

# Track agent usage (optional - for analytics)
LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
echo "$TIMESTAMP | START | $AGENT_ID" >> "$LOG_DIR/subagent-usage.log"

exit 0
