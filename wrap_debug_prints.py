#!/usr/bin/env python3
"""
Automated script to wrap all print() statements in #if DEBUG blocks.
Preserves existing formatting and handles multi-line print statements.
"""

import re
import os
import sys
from pathlib import Path

def is_already_wrapped(lines, line_idx):
    """Check if print statement is already wrapped in #if DEBUG"""
    # Look backwards for #if DEBUG
    for i in range(line_idx - 1, max(0, line_idx - 10), -1):
        line = lines[i].strip()
        if line.startswith('#if DEBUG'):
            # Found #if DEBUG, now check if there's a matching #endif after our print
            for j in range(line_idx + 1, min(len(lines), line_idx + 10)):
                if lines[j].strip().startswith('#endif'):
                    return True
        # Stop if we hit another control structure
        if line.startswith('func ') or line.startswith('var ') or line.startswith('let ') or line.startswith('class ') or line.startswith('struct '):
            break
    return False

def find_print_end(lines, start_idx):
    """Find the end of a print statement (handles multi-line)"""
    paren_count = 0
    in_string = False
    escape_next = False

    for idx in range(start_idx, len(lines)):
        line = lines[idx]
        for char in line:
            if escape_next:
                escape_next = False
                continue
            if char == '\\':
                escape_next = True
                continue
            if char == '"' and not in_string:
                in_string = True
            elif char == '"' and in_string:
                in_string = False
            elif not in_string:
                if char == '(':
                    paren_count += 1
                elif char == ')':
                    paren_count -= 1
                    if paren_count == 0:
                        return idx
    return start_idx

def get_indentation(line):
    """Get the indentation of a line"""
    return len(line) - len(line.lstrip())

def wrap_prints_in_file(filepath):
    """Wrap all unwrapped print statements in a file"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return 0

    changes_made = 0
    new_lines = []
    i = 0

    while i < len(lines):
        line = lines[i]

        # Check if this line contains a print statement
        if re.search(r'\bprint\s*\(', line) and not line.strip().startswith('//'):
            # Check if already wrapped
            if not is_already_wrapped(lines, i):
                # Find the end of the print statement
                end_idx = find_print_end(lines, i)

                # Get indentation
                indent = ' ' * get_indentation(line)

                # Add #if DEBUG before
                new_lines.append(f"{indent}#if DEBUG\n")

                # Add the print statement(s)
                for j in range(i, end_idx + 1):
                    new_lines.append(lines[j])

                # Add #endif after
                new_lines.append(f"{indent}#endif\n")

                changes_made += 1
                i = end_idx + 1
                continue

        new_lines.append(line)
        i += 1

    if changes_made > 0:
        try:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.writelines(new_lines)
            print(f"✅ {filepath.name}: Wrapped {changes_made} print statement(s)")
        except Exception as e:
            print(f"Error writing {filepath}: {e}")
            return 0

    return changes_made

def main():
    # Find all Swift files in BooksTrackerFeature
    base_dir = Path("BooksTrackerPackage/Sources/BooksTrackerFeature")

    if not base_dir.exists():
        print(f"Error: Directory {base_dir} not found")
        sys.exit(1)

    swift_files = list(base_dir.rglob("*.swift"))
    print(f"Found {len(swift_files)} Swift files")
    print()

    total_changes = 0
    files_modified = 0

    for swift_file in sorted(swift_files):
        changes = wrap_prints_in_file(swift_file)
        if changes > 0:
            total_changes += changes
            files_modified += 1

    print()
    print(f"{'='*60}")
    print(f"✅ Complete! Wrapped {total_changes} print statements across {files_modified} files")
    print(f"{'='*60}")

    # Verify no unwrapped prints remain
    print("\nVerifying...")
    os.system("grep -r 'print(' BooksTrackerPackage/Sources/BooksTrackerFeature/ --include='*.swift' | grep -v '#if DEBUG' | grep -v '//.*print(' | wc -l")

if __name__ == "__main__":
    main()
