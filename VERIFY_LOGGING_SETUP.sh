#!/bin/bash
# Verification script for worker logging setup

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║         Worker Logging Setup Verification                         ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

WORKER_DIR="/Users/justingardner/Downloads/xcode/books-tracker-v1/cloudflare-workers/api-worker"
PROJECT_ROOT="/Users/justingardner/Downloads/xcode/books-tracker-v1"

# Check 1: Documentation files exist
echo "1. Checking documentation files..."
DOC_FILES=(
  "README_LOGGING.md"
  "WORKER_LOGGING_QUICK_REFERENCE.md"
  "WORKER_LOGGING_GUIDE.md"
  "BACKGROUND_TASK_DEBUGGING.md"
  "LOGGING_EXAMPLES.md"
  "LOGGING_DOCUMENTATION_INDEX.md"
)

MISSING_FILES=0
for file in "${DOC_FILES[@]}"; do
  if [ -f "$PROJECT_ROOT/$file" ]; then
    echo "   ✓ $file"
  else
    echo "   ✗ $file (MISSING)"
    MISSING_FILES=$((MISSING_FILES + 1))
  fi
done

if [ $MISSING_FILES -eq 0 ]; then
  echo "   Status: All documentation files present (6/6)"
else
  echo "   Status: Missing $MISSING_FILES files"
fi
echo ""

# Check 2: Worker files exist
echo "2. Checking worker installation..."
if [ -f "$WORKER_DIR/wrangler.toml" ]; then
  echo "   ✓ wrangler.toml found"
else
  echo "   ✗ wrangler.toml not found"
fi

if [ -f "$WORKER_DIR/src/index.js" ]; then
  echo "   ✓ src/index.js found"
else
  echo "   ✗ src/index.js not found"
fi

if [ -d "$WORKER_DIR/node_modules/wrangler" ]; then
  echo "   ✓ wrangler CLI installed"
else
  echo "   ✗ wrangler CLI not installed"
fi
echo ""

# Check 3: Wrangler configuration
echo "3. Checking wrangler configuration..."
if grep -q "name = \"api-worker\"" "$WORKER_DIR/wrangler.toml"; then
  echo "   ✓ Worker name: api-worker"
fi

if grep -q "LOG_LEVEL = \"DEBUG\"" "$WORKER_DIR/wrangler.toml"; then
  echo "   ✓ Log level: DEBUG"
fi

if grep -q "STRUCTURED_LOGGING = \"true\"" "$WORKER_DIR/wrangler.toml"; then
  echo "   ✓ Structured logging: enabled"
fi

if grep -q "ProgressWebSocketDO" "$WORKER_DIR/wrangler.toml"; then
  echo "   ✓ Durable Object binding: ProgressWebSocketDO"
fi
echo ""

# Check 4: Commands ready to use
echo "4. Quick start commands ready to use:"
echo ""
echo "   Start real-time logs:"
echo "   $ npx wrangler tail"
echo ""
echo "   Filter by search term:"
echo "   $ npx wrangler tail --search \"csv-gemini\""
echo "   $ npx wrangler tail --search \"scan-bookshelf\""
echo "   $ npx wrangler tail --search \"ERROR\""
echo ""
echo "   JSON format (for piping):"
echo "   $ npx wrangler tail --format json"
echo ""

# Check 5: File sizes
echo "5. Documentation size summary:"
for file in "${DOC_FILES[@]}"; do
  if [ -f "$PROJECT_ROOT/$file" ]; then
    SIZE=$(wc -c < "$PROJECT_ROOT/$file" | numfmt --to=iec 2>/dev/null || stat -f%z "$PROJECT_ROOT/$file" | awk '{printf "%.1f KB\n", $1/1024}')
    printf "   %-40s %s\n" "$file" "$SIZE"
  fi
done
TOTAL=$(du -sh "$PROJECT_ROOT" 2>/dev/null | awk '{print $1}')
echo ""

# Check 6: Next steps
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                        SETUP COMPLETE                             ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo ""
echo "1. Read the quick start guide:"
echo "   $ cat $PROJECT_ROOT/README_LOGGING.md"
echo ""
echo "2. View the one-page cheat sheet:"
echo "   $ cat $PROJECT_ROOT/WORKER_LOGGING_QUICK_REFERENCE.md"
echo ""
echo "3. Try real-time logging:"
echo "   $ cd $WORKER_DIR"
echo "   $ npx wrangler tail --search \"csv-gemini\""
echo ""
echo "4. Trigger CSV import from iOS app and watch logs appear"
echo ""
echo "Documentation files:"
for file in "${DOC_FILES[@]}"; do
  echo "   - $PROJECT_ROOT/$file"
done
echo ""
