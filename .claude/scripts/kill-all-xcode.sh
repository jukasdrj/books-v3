#!/bin/bash
# Emergency script to kill all Xcode/Simulator processes
# Use this if system becomes unresponsive

echo "🚨 Emergency Cleanup - Killing all Xcode processes"
echo "=================================================="

# Kill Xcode
echo "Killing Xcode..."
pkill -9 "Xcode" 2>/dev/null || echo "Xcode not running"

# Kill Simulator
echo "Killing Simulator..."
pkill -9 "Simulator" 2>/dev/null || echo "Simulator not running"

# Kill xcodebuild
echo "Killing xcodebuild..."
pkill -9 "xcodebuild" 2>/dev/null || echo "xcodebuild not running"

# Kill CoreSimulator services
echo "Killing CoreSimulator services..."
pkill -9 "com.apple.CoreSimulator" 2>/dev/null || echo "CoreSimulator not running"

# Kill SourceKit
echo "Killing SourceKit..."
pkill -9 "SourceKitService" 2>/dev/null || echo "SourceKit not running"

# Kill indexing
echo "Killing indexing services..."
pkill -9 "com.apple.dt.XCBuild" 2>/dev/null || echo "XCBuild not running"

echo ""
echo "✅ All processes terminated"
echo ""
echo "You can now:"
echo "  1. Close and reopen Xcode"
echo "  2. Run ./quick-validate.sh for safe build validation"
echo "  3. Run ./safe-test.sh for monitored simulator testing"
