#!/bin/bash
# Sync OpenAPI spec from live backend with Swift OpenAPI Generator compatibility patches

set -e

SPEC_URL="https://api.oooefam.net/v3/openapi.json"
DOCS_SPEC="docs/openapi-v3.json"
BUILD_SPEC="BooksTrackerPackage/Sources/BooksTrackerFeature/openapi.json"

echo "📥 Fetching OpenAPI spec from $SPEC_URL..."

# Fetch live spec
curl -sf "$SPEC_URL" -o "$BUILD_SPEC.tmp" || {
  echo "❌ Failed to fetch OpenAPI spec from backend"
  exit 1
}

# Validate JSON
jq empty "$BUILD_SPEC.tmp" 2>/dev/null || {
  echo "❌ Invalid JSON in OpenAPI spec"
  rm -f "$BUILD_SPEC.tmp"
  exit 1
}

# Apply compatibility patches for Swift OpenAPI Generator
echo "🔧 Applying Swift OpenAPI Generator compatibility patches..."

# 1. Remove OpenAPI 3.1.0 boolean exclusiveMinimum (not well supported in Swift OpenAPI Generator)
#    Keep minimum constraint only: "minimum": 0, "exclusiveMinimum": true → "minimum": 1
jq 'walk(
  if type == "object" and has("exclusiveMinimum") and .exclusiveMinimum == true and has("minimum") then
    .minimum = (.minimum + 1) | del(.exclusiveMinimum)
  else
    .
  end
)' "$BUILD_SPEC.tmp" > "$BUILD_SPEC.patched"

# 2. Downgrade OpenAPI version to 3.0.3 for Swift OpenAPI Generator compatibility
jq '.openapi = "3.0.3"' "$BUILD_SPEC.patched" > "$BUILD_SPEC.tmp"
rm "$BUILD_SPEC.patched"

# Check if spec changed
if diff -q "$BUILD_SPEC" "$BUILD_SPEC.tmp" >/dev/null 2>&1; then
  echo "✅ OpenAPI spec is up to date"
  rm -f "$BUILD_SPEC.tmp"
  exit 0
fi

# Update both files
mv "$BUILD_SPEC.tmp" "$BUILD_SPEC"
cp "$BUILD_SPEC" "$DOCS_SPEC"

echo "✅ OpenAPI spec updated successfully"
echo "📋 Spec version: $(jq -r '.info.version' "$BUILD_SPEC")"
echo "📊 Endpoints: $(jq -r '.paths | keys | length' "$BUILD_SPEC")"
echo "🔧 Patched: OpenAPI 3.1.0 → 3.0.3 for Swift compatibility"
echo ""
echo "ℹ️  Changes detected - you may need to rebuild to regenerate Swift client code"
