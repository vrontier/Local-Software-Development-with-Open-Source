#!/bin/bash
# Check vLLM build status

BUILD_LOG="$HOME/vllm-gb10/build.log"

if [ ! -f "$BUILD_LOG" ]; then
    echo "Build log not found at $BUILD_LOG"
    exit 1
fi

echo "=== vLLM Build Monitor ==="
echo ""

# Check if build is running
if ps aux | grep -q '[d]ocker build.*Dockerfile.gb10'; then
    echo "Status: BUILD IN PROGRESS"
    echo ""
    
    # Get latest progress
    LATEST=$(grep -oE '\[[0-9]+/419\]' "$BUILD_LOG" | tail -1)
    if [ -n "$LATEST" ]; then
        CURRENT=$(echo "$LATEST" | grep -oE '[0-9]+' | head -1)
        PERCENT=$(awk "BEGIN {printf \"%.1f\", ($CURRENT/419)*100}")
        echo "Progress: $LATEST ($PERCENT%)"
        
        # Estimate time remaining (rough approximation)
        ELAPSED=$(grep -oE '#11 [0-9]+\.[0-9]+' "$BUILD_LOG" | tail -1 | awk '{print $2}')
        if [ -n "$ELAPSED" ]; then
            ELAPSED_MIN=$(awk "BEGIN {printf \"%.0f\", $ELAPSED/60}")
            ESTIMATED_TOTAL=$(awk "BEGIN {printf \"%.0f\", ($ELAPSED/$CURRENT)*419/60}")
            REMAINING=$(awk "BEGIN {printf \"%.0f\", $ESTIMATED_TOTAL - $ELAPSED_MIN}")
            echo "Time elapsed: ${ELAPSED_MIN} minutes"
            echo "Estimated remaining: ~${REMAINING} minutes"
        fi
    fi
    
    echo ""
    echo "Recent compilation steps:"
    grep -oE '\[[0-9]+/419\].*' "$BUILD_LOG" | tail -5 | sed 's/^/  /'
    
elif docker images | grep -q 'vllm-gb10.*latest'; then
    echo "Status: BUILD COMPLETE ✓"
    echo ""
    docker images | grep vllm
    echo ""
    echo "Ready to deploy! Run: ~/vllm-service/deploy.sh"
    
else
    # Check for errors
    if grep -qi 'error' "$BUILD_LOG" | tail -20; then
        echo "Status: BUILD FAILED ✗"
        echo ""
        echo "Recent errors:"
        grep -i 'error' "$BUILD_LOG" | tail -10 | sed 's/^/  /'
    else
        echo "Status: UNKNOWN"
        echo "Build process not running and image not found."
        echo ""
        echo "Last 10 lines of build log:"
        tail -10 "$BUILD_LOG" | sed 's/^/  /'
    fi
fi

echo ""
echo "=== Commands ==="
echo "  View full log: tail -f ~/vllm-gb10/build.log"
echo "  Monitor build: watch -n 10 ~/vllm-gb10/check-build.sh"
echo "  After build: ~/vllm-service/deploy.sh"
