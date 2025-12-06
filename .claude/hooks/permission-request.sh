#!/bin/bash

# PermissionRequest Hook (v2.0.45+)
# Triggered when Claude requests permission to use a tool
# Can auto-approve or deny based on custom logic

set -e

# Hook input available via stdin (JSON format)
# Fields: tool_name, tool_input, permission_decision, etc.

TOOL_NAME="${TOOL_NAME:-unknown}"
PERMISSION_DECISION="${PERMISSION_DECISION:-ask}"

# Example: Auto-approve safe read operations
if [[ "$TOOL_NAME" == "Read" ]] || [[ "$TOOL_NAME" == "Grep" ]] || [[ "$TOOL_NAME" == "Glob" ]]; then
    # These are safe read-only operations - auto-approve
    echo "✅ Auto-approved: $TOOL_NAME (read-only operation)"
    exit 0
fi

# Example: Auto-deny dangerous operations
if [[ "$TOOL_NAME" == "Bash" ]] && echo "$TOOL_INPUT" | grep -qE "(rm -rf /|sudo rm|format|mkfs)"; then
    echo "🚫 Auto-denied: $TOOL_NAME (dangerous operation blocked)"
    exit 1
fi

# Example: Require approval for git write operations
if [[ "$TOOL_NAME" == "Bash" ]] && echo "$TOOL_INPUT" | grep -qE "(git push|git commit|git add)"; then
    echo "⚠️ Approval required: $TOOL_NAME (git write operation)"
    # Return 0 to let user decide (shows permission prompt)
    exit 0
fi

# Default: Let Claude Code handle permission check
echo "🤔 Permission check: $TOOL_NAME"
exit 0
