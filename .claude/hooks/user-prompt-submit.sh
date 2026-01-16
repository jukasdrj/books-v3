#!/bin/bash

# UserPromptSubmit Hook (v2.0.65+)
# Detects complex multi-step tasks and reminds to use planning-with-files
# Triggered before Claude processes user input
#
# BooksTrack Context: Solo-dev family app
# - Focus on code quality and maintainability
# - Pragmatic security (not paranoid)
# - Encourage planning for complex work

set -e

USER_INPUT="${USER_INPUT:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Multi-step task indicators (case-insensitive regex patterns)
COMPLEX_PATTERNS=(
    "implement.*feature"
    "add.*feature"
    "build.*new"
    "migration"
    "refactor.*entire"
    "redesign"
    "phase [0-9]"
    "step [0-9]"
    "first.*then.*finally"
    "first.*second.*third"
)

# Check if planning files exist in project root
has_planning_files() {
    [ -f "$PROJECT_DIR/task_plan.md" ] && \
    [ -f "$PROJECT_DIR/findings.md" ] && \
    [ -f "$PROJECT_DIR/progress.md" ]
}

# Check if user input matches complex task patterns
is_complex_task() {
    local input="$1"
    for pattern in "${COMPLEX_PATTERNS[@]}"; do
        if echo "$input" | grep -qiE "$pattern"; then
            return 0
        fi
    done
    return 1
}

# Main logic
if ! has_planning_files && is_complex_task "$USER_INPUT"; then
    echo ""
    echo "🎯 Multi-step task detected. Use planning-with-files for best results:"
    echo "   Run: /planning-with-files"
    echo "   Creates: task_plan.md, findings.md, progress.md in project root"
    echo ""
    echo "   Benefits:"
    echo "   - Persistent task memory (survives context resets)"
    echo "   - Phase tracking with decisions/errors logged"
    echo "   - PM orchestration with subagent delegation"
    echo ""
fi

exit 0
