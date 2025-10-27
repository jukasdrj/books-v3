#!/bin/bash
set -euo pipefail

# Script to audit Swift tests for missing assertions
# Finds @Test functions that don't contain #expect() calls

TESTS_DIR="BooksTrackerPackage/Tests"
TEMP_DIR=$(mktemp -d)
REPORT_FILE="$TEMP_DIR/audit_report.txt"

echo "🔍 Auditing Swift tests for missing assertions..."
echo ""

# Find all test files
find "$TESTS_DIR" -name "*Tests.swift" -type f | sort | while read -r file; do
    # Extract each @Test function with its body
    python3 - "$file" <<'PYTHON_SCRIPT'
import sys
import re

def extract_test_functions(filepath):
    """Extract @Test functions and check for #expect assertions."""
    with open(filepath, 'r') as f:
        content = f.read()

    # Pattern to match @Test decorated functions with their bodies
    # This handles multi-line @Test attributes
    pattern = r'(@Test[^\n]*\n\s*(?:@Test[^\n]*\n\s*)*func\s+(\w+)\s*\([^)]*\)(?:\s+(?:async\s+)?(?:throws\s+)?)?(?:->[^{]*)?\s*\{)'

    matches = re.finditer(pattern, content)

    for match in matches:
        test_start = match.start()
        func_name = match.group(2)

        # Find the matching closing brace
        brace_count = 0
        func_end = test_start
        in_func = False

        for i in range(test_start, len(content)):
            if content[i] == '{':
                brace_count += 1
                in_func = True
            elif content[i] == '}':
                brace_count -= 1
                if in_func and brace_count == 0:
                    func_end = i + 1
                    break

        func_body = content[test_start:func_end]

        # Check if function body contains #expect
        if '#expect' not in func_body:
            # Count line number
            line_num = content[:test_start].count('\n') + 1
            print(f"{filepath}:{line_num}: func {func_name}() - missing #expect")

extract_test_functions(sys.argv[1])
PYTHON_SCRIPT
done | tee "$REPORT_FILE"

ISSUE_COUNT=$(wc -l < "$REPORT_FILE" | tr -d ' ')

echo ""
if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo "✅ All tests contain assertions!"
else
    echo "⚠️  Found $ISSUE_COUNT test(s) without #expect() assertions"
    echo ""
    echo "Review these tests to ensure they properly verify behavior."
    echo "Note: Some tests may be intentionally assertion-free (e.g., compilation tests)."
fi

rm -rf "$TEMP_DIR"
