#!/bin/bash

# SubagentStart Hook (v2.0.64)
# Triggered when a subagent (@pm, @pal, @xcode) is invoked
#
# New in v2.0.64:
# - Agents can run asynchronously in background
# - Use TaskOutput tool to retrieve results when ready
# - Async agents can send messages to wake up main agent

set -e

AGENT_ID="${AGENT_ID:-unknown}"
AGENT_TYPE="${AGENT_TYPE:-unknown}"
RUN_IN_BACKGROUND="${RUN_IN_BACKGROUND:-false}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Log subagent invocation
if [ "$RUN_IN_BACKGROUND" = "true" ]; then
    echo "🔄 Background agent started: $AGENT_ID ($AGENT_TYPE) at $TIMESTAMP"
    echo "   Use TaskOutput tool to retrieve results when ready"
else
    echo "🤖 Subagent started: $AGENT_ID ($AGENT_TYPE) at $TIMESTAMP"
fi

# Track agent usage (optional - for analytics)
LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
echo "$TIMESTAMP | START | $AGENT_ID | $AGENT_TYPE | background=$RUN_IN_BACKGROUND" >> "$LOG_DIR/subagent-usage.log"

exit 0
