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
# Pipe through xcsift for structured error/warning parsing
# Note: xcsift --Werror will exit with error code if warnings exist
perl -e 'alarm shift @ARGV; exec @ARGV' "$TIMEOUT" xcodebuild \
    -workspace BooksTracker.xcworkspace \
    -scheme BooksTracker \
    -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
    -jobs "$PARALLEL_JOBS" \
    clean build \
    COMPILER_INDEX_STORE_ENABLE=NO \
    2>&1 | tee build-quick.log | xcsift --warnings --Werror

# Capture all exit codes immediately before PIPESTATUS is cleared
PIPE_STATUS=("${PIPESTATUS[@]}")
BUILD_EXIT_CODE="${PIPE_STATUS[0]}"
XCSIFT_EXIT_CODE="${PIPE_STATUS[2]:-0}"  # Default to 0 if not set

echo ""
if [ "$BUILD_EXIT_CODE" -ne 0 ]; then
    echo "❌ Build failed - compilation errors detected"
    echo "Check build-quick.log for details or review xcsift output above"
    exit 1
elif [ "$XCSIFT_EXIT_CODE" -ne 0 ]; then
    echo "⚠️  Build succeeded but warnings detected (zero warnings policy violated)"
    echo "Review xcsift output above for warning details"
    exit 1
else
    echo "✅ Build succeeded with zero warnings"
    exit 0
fi
