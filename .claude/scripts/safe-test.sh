#!/bin/bash
# Safe iOS testing with resource limits and monitoring
# Prevents system crashes from runaway Xcode/Simulator processes

set -euo pipefail

# Configuration
MAX_MEMORY_GB=8
MAX_CPU_PERCENT=400  # 400% = 4 cores at 100%
BUILD_TIMEOUT=300    # 5 minutes
SIM_TIMEOUT=600      # 10 minutes
PARALLEL_JOBS=4
MIN_FREE_MEMORY_GB=4

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up processes...${NC}"

    # Kill simulator if running
    pkill -9 "Simulator" 2>/dev/null || true

    # Kill any xcodebuild processes
    pkill -9 "xcodebuild" 2>/dev/null || true

    # Kill any orphaned processes
    pkill -9 "com.apple.CoreSimulator" 2>/dev/null || true

    echo -e "${GREEN}Cleanup complete${NC}"
}

# Register cleanup on exit
trap cleanup EXIT INT TERM

# Check system resources
check_resources() {
    echo "Checking system resources..."

    # Get free memory in GB
    free_memory=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
    page_size=$(vm_stat | head -1 | awk '{print $8}' | sed 's/\.//')
    free_gb=$((free_memory * page_size / 1024 / 1024 / 1024))

    echo "Free memory: ${free_gb}GB"

    if [ "$free_gb" -lt "$MIN_FREE_MEMORY_GB" ]; then
        echo -e "${RED}ERROR: Insufficient memory. Have ${free_gb}GB, need ${MIN_FREE_MEMORY_GB}GB+${NC}"
        echo "Close other applications and try again."
        exit 1
    fi

    # Check CPU load
    cpu_load=$(uptime | awk '{print $(NF-2)}' | sed 's/,//')
    cpu_cores=$(sysctl -n hw.ncpu)
    cpu_percent=$(echo "$cpu_load * 100 / $cpu_cores" | bc)

    echo "CPU load: ${cpu_load} (${cpu_percent}%)"

    if [ "$cpu_percent" -gt 70 ]; then
        echo -e "${YELLOW}WARNING: High CPU load (${cpu_percent}%). This may cause slowdown.${NC}"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    echo -e "${GREEN}Resource check passed${NC}"
}

# Monitor process resources
monitor_process() {
    local pid=$1
    local max_memory_bytes=$((MAX_MEMORY_GB * 1024 * 1024 * 1024))

    while kill -0 "$pid" 2>/dev/null; do
        # Get memory usage in bytes
        mem_bytes=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print $1*1024}' || echo 0)
        mem_gb=$(echo "scale=2; $mem_bytes / 1024 / 1024 / 1024" | bc)

        # Get CPU percentage
        cpu_percent=$(ps -o %cpu= -p "$pid" 2>/dev/null || echo 0)

        echo "Process $pid: ${mem_gb}GB RAM, ${cpu_percent}% CPU"

        # Check memory limit
        if [ "$mem_bytes" -gt "$max_memory_bytes" ]; then
            echo -e "${RED}KILL: Memory limit exceeded (${mem_gb}GB > ${MAX_MEMORY_GB}GB)${NC}"
            kill -9 "$pid"
            return 1
        fi

        # Check CPU limit (if sustained high usage)
        if [ "$(echo "$cpu_percent > $MAX_CPU_PERCENT" | bc)" -eq 1 ]; then
            echo -e "${YELLOW}WARNING: High CPU usage (${cpu_percent}%)${NC}"
        fi

        sleep 5
    done
}

# Build with resource limits
build_safe() {
    echo "Building with resource limits..."

    # Use -jobs flag to limit parallelism
    timeout "$BUILD_TIMEOUT" xcodebuild \
        -workspace BooksTracker.xcworkspace \
        -scheme BooksTracker \
        -configuration Debug \
        -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
        -jobs "$PARALLEL_JOBS" \
        build 2>&1 | tee build-safe.log &

    BUILD_PID=$!
    echo "Build started (PID: $BUILD_PID)"

    # Monitor build process in background
    monitor_process "$BUILD_PID" &
    MONITOR_PID=$!

    # Wait for build to complete
    if wait "$BUILD_PID"; then
        echo -e "${GREEN}Build succeeded${NC}"
        kill "$MONITOR_PID" 2>/dev/null || true
        return 0
    else
        echo -e "${RED}Build failed or timed out${NC}"
        kill "$MONITOR_PID" 2>/dev/null || true
        return 1
    fi
}

# Launch simulator with monitoring
launch_simulator_safe() {
    echo "Launching simulator with monitoring..."

    # Find iPhone 17 Pro
    DEVICE_ID=$(xcrun simctl list devices | grep "iPhone 17 Pro" | grep -v "unavailable" | head -1 | sed 's/.*(//;s/).*//')

    if [ -z "$DEVICE_ID" ]; then
        echo -e "${RED}ERROR: iPhone 17 Pro simulator not found${NC}"
        return 1
    fi

    echo "Using device: $DEVICE_ID"

    # Boot simulator
    echo "Booting simulator..."
    xcrun simctl boot "$DEVICE_ID" 2>/dev/null || echo "Simulator already booted"

    # Wait for boot
    sleep 5

    # Install app
    echo "Installing BooksTrack..."
    timeout 120 xcrun simctl install "$DEVICE_ID" \
        ~/Library/Developer/Xcode/DerivedData/BooksTracker-*/Build/Products/Debug-iphonesimulator/BooksTracker.app

    # Launch app
    echo "Launching BooksTrack..."
    xcrun simctl launch "$DEVICE_ID" com.oooe.BooksTracker &
    LAUNCH_PID=$!

    # Monitor for timeout
    sleep "$SIM_TIMEOUT" && kill "$LAUNCH_PID" 2>/dev/null &
    TIMEOUT_PID=$!

    # Stream logs (with resource monitoring)
    xcrun simctl spawn "$DEVICE_ID" log stream --level debug | grep -i "bookstrack" &
    LOG_PID=$!

    echo -e "${GREEN}Simulator running (will auto-kill after ${SIM_TIMEOUT}s)${NC}"
    echo "Press Ctrl+C to stop"

    # Monitor log process
    monitor_process "$LOG_PID"

    # Cleanup timeout
    kill "$TIMEOUT_PID" 2>/dev/null || true
}

# Main execution
main() {
    echo -e "${GREEN}=== Safe iOS Testing ===${NC}"

    # Pre-flight checks
    check_resources

    # Initial cleanup
    cleanup

    # Build
    if ! build_safe; then
        echo -e "${RED}Build failed. Exiting.${NC}"
        exit 1
    fi

    # Launch simulator
    launch_simulator_safe
}

# Run main
main
