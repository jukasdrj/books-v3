#!/bin/bash

# iOS Pre-Commit Hook
# Based on backend template, customized for iOS

set -e

echo "🤖 Running iOS pre-commit checks..."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

# 1. Check for sensitive files
echo "🔐 Checking for sensitive files..."
SENSITIVE_FILES=(
  "*.mobileprovision"
  "*.p12"
  "*.cer"
  "*credentials*.json"
  "GoogleService-Info.plist"
)

for pattern in "${SENSITIVE_FILES[@]}"; do
  if git diff --cached --name-only | grep -q "$pattern"; then
    echo -e "${RED}✗ Blocked: Attempting to commit sensitive file: $pattern${NC}"
    FAILED=1
  fi
done

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ No sensitive files detected${NC}"
fi

# 2. SwiftLint (if available)
if command -v swiftlint &> /dev/null; then
  echo "🎨 Running SwiftLint..."
  STAGED_SWIFT=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.swift$' || true)

  if [ -n "$STAGED_SWIFT" ]; then
    if ! swiftlint lint --quiet $STAGED_SWIFT; then
      echo -e "${YELLOW}⚠ Warning: SwiftLint found issues${NC}"
      echo "  Run: swiftlint autocorrect"
    else
      echo -e "${GREEN}✓ SwiftLint passed${NC}"
    fi
  fi
fi

# 3. Check for debug print statements
echo "🐛 Checking for debug statements..."
DEBUG_COUNT=$(git diff --cached | grep -c "print(" || true)

if [ $DEBUG_COUNT -gt 0 ]; then
  echo -e "${YELLOW}⚠ Warning: Found $DEBUG_COUNT print() statements${NC}"
  echo "  Consider using proper logging"
fi

# 4. Check Xcode project integrity
if git diff --cached --name-only | grep -q "\.xcodeproj/project.pbxproj"; then
  echo "📦 Checking Xcode project file..."

  # Check for merge conflicts in project file
  if git diff --cached BooksTracker.xcodeproj/project.pbxproj | grep -q "<<<<<<"; then
    echo -e "${RED}✗ Merge conflicts in Xcode project file${NC}"
    FAILED=1
  else
    echo -e "${GREEN}✓ Xcode project file looks clean${NC}"
  fi
fi

# 5. Check if DTOs were updated (if synced from backend)
if git diff --cached --name-only | grep -qE "BooksTrackerFeature/DTOs/.*\.swift"; then
  echo "🔄 Checking DTO changes..."

  echo -e "${YELLOW}⚠ DTO files changed${NC}"
  echo "  Ensure DTOs match backend TypeScript definitions"
  echo "  See backend: src/types/canonical.ts"
fi

# Final result
echo ""
if [ $FAILED -eq 1 ]; then
  echo -e "${RED}❌ Pre-commit checks failed. Commit blocked.${NC}"
  exit 1
else
  echo -e "${GREEN}✅ All pre-commit checks passed!${NC}"
  exit 0
fi
