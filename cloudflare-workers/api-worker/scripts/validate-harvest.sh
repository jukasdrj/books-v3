#!/bin/bash
set -e

echo "🔍 Validating ISBNdb Cover Harvest Results"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check R2 storage
echo ""
echo "📦 R2 Storage Check:"
COVER_COUNT=$(npx wrangler r2 object list LIBRARY_DATA --prefix covers/isbn/ | grep -c ".jpg" || echo "0")
echo "   Found $COVER_COUNT covers in R2"

# Check KV metadata (sample)
echo ""
echo "💾 KV Metadata Check:"
SAMPLE_ISBN="9780451524935"
METADATA=$(npx wrangler kv:key get --binding=KV_CACHE "cover:$SAMPLE_ISBN" || echo "")
if [ -n "$METADATA" ]; then
  echo "   ✓ Sample metadata exists for ISBN: $SAMPLE_ISBN"
  echo "   $METADATA" | jq .
else
  echo "   ✗ No metadata found for sample ISBN"
fi

# Check failed ISBNs
echo ""
echo "❌ Failed ISBNs:"
if [ -f "failed_isbns.json" ]; then
  FAILED_COUNT=$(cat failed_isbns.json | jq '.totalFailed')
  echo "   Total failed: $FAILED_COUNT"
  echo "   Top 5 failures:"
  cat failed_isbns.json | jq '.failures[:5] | .[] | {isbn, title, error: .error}'
else
  echo "   No failures logged (or file not found)"
fi

echo ""
echo "✅ Validation complete"
