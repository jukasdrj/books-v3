#!/bin/bash
# Quick build validation without launching simulator
# Use this to validate changes without overwhelming system resources

set -euo pipefail

PARALLEL_JOBS=2
TIMEOUT=300

echo "🔍 Quick Build Validation (No Simulator)"
echo "========================================="

# Cleanup any previous processes
pkill -9 "xcodebuild" 2>/dev/null || true

# Build for simulator (but don't launch)
echo "Building for iOS Simulator..."

# Use Perl as timeout (macOS compatible)
perl -e 'alarm shift @ARGV; exec @ARGV' "$TIMEOUT" xcodebuild \
    -workspace BooksTracker.xcworkspace \
    -scheme BooksTracker \
    -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -jobs "$PARALLEL_JOBS" \
    clean build \
    COMPILER_INDEX_STORE_ENABLE=NO \
    2>&1 | tee build-quick.log

if [ "${PIPESTATUS[0]}" -eq 0 ]; then
    echo "✅ Build succeeded"
    exit 0
else
    echo "❌ Build failed"
    echo "Check build-quick.log for details"
    exit 1
fi
