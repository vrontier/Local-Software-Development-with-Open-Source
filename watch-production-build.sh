#!/bin/bash

echo "════════════════════════════════════════════════════════"
echo "  vLLM Production Build Monitor - Live Progress"  
echo "════════════════════════════════════════════════════════"
echo ""

# Check if build is running
if ! ps aux | grep -q "[d]ocker build.*production"; then
    echo "⚠️  Build process NOT RUNNING"
    echo ""
    if docker images | grep -q "vllm-gb10.*production"; then
        echo "✅ BUILD COMPLETE!"
        docker images | grep "vllm-gb10.*production"
    else
        echo "Build may have failed. Last 20 log lines:"
        tail -20 /tmp/vllm-production.log
    fi
    exit 0
fi

# Extract progress - look for [XX/435] pattern
CURRENT=$(tail -50 /tmp/vllm-production.log | grep -oE "\[[0-9]+/435\]" | tail -1 | grep -oE "[0-9]+" | head -1)

if [ -z "$CURRENT" ]; then
    echo "📦 Status: Installing dependencies..."
    echo ""
    tail -10 /tmp/vllm-production.log
    exit 0
fi

# Calculate statistics  
TOTAL=435
PERCENT=$(awk "BEGIN {printf \"%.1f\", ($CURRENT/$TOTAL)*100}")
REMAINING=$((TOTAL - CURRENT))

# Get elapsed time from log timestamp
FIRST_BUILD_LINE=$(grep -m1 "Building" /tmp/vllm-production.log)
LOG_START_SEC=$(echo "$FIRST_BUILD_LINE" | grep -oE "^#[0-9]+ [0-9.]+" | awk '{print $2}' | cut -d. -f1)
CURRENT_BUILD_LINE=$(tail -5 /tmp/vllm-production.log | grep "Building" | tail -1)
CURRENT_SEC=$(echo "$CURRENT_BUILD_LINE" | grep -oE "^#[0-9]+ [0-9.]+" | awk '{print $2}' | cut -d. -f1)

if [ -n "$LOG_START_SEC" ] && [ -n "$CURRENT_SEC" ]; then
    ELAPSED=$((CURRENT_SEC - LOG_START_SEC))
    ELAPSED_MIN=$((ELAPSED / 60))
    ELAPSED_HOURS=$((ELAPSED_MIN / 60))
    ELAPSED_MIN_LEFT=$((ELAPSED_MIN % 60))
    
    if [ $CURRENT -gt 5 ]; then
        AVG_SEC_PER_FILE=$((ELAPSED / CURRENT))
        ESTIMATED_REMAINING=$((REMAINING * AVG_SEC_PER_FILE))
        ESTIMATED_MIN=$((ESTIMATED_REMAINING / 60))
        ESTIMATED_HOURS=$((ESTIMATED_MIN / 60))
        ESTIMATED_MIN_LEFT=$((ESTIMATED_MIN % 60))
    else
        ESTIMATED_HOURS="?"
        ESTIMATED_MIN_LEFT="?"
    fi
    
    echo "📊 Progress: $CURRENT / $TOTAL files ($PERCENT%)"
    echo "⏱️  Elapsed: ${ELAPSED_HOURS}h ${ELAPSED_MIN_LEFT}m"
    echo "⏳ Estimated remaining: ${ESTIMATED_HOURS}h ${ESTIMATED_MIN_LEFT}m"
    echo "⚡ Average: ${AVG_SEC_PER_FILE}s per file"
else
    echo "📊 Progress: $CURRENT / $TOTAL files ($PERCENT%)"
    echo "⏱️  Elapsed: calculating..."
fi

echo "📈 Files remaining: $REMAINING"
echo ""
echo "🔨 Current file:"
tail -30 /tmp/vllm-production.log | grep "Building" | tail -1
echo ""

# Show what phase we are in
if [ $CURRENT -lt 50 ]; then
    echo "📍 Phase: Quantization & Core Kernels (fast)"
    echo "   Expected phase time: ~30-45 minutes"
elif [ $CURRENT -lt 150 ]; then
    echo "📍 Phase: Flash Attention Kernels (SLOWEST)"
    echo "   Expected phase time: ~2-3 hours"
elif [ $CURRENT -lt 250 ]; then
    echo "📍 Phase: MoE & Advanced Kernels"
    echo "   Expected phase time: ~1-2 hours"
elif [ $CURRENT -lt 400 ]; then
    echo "📍 Phase: Remaining Kernels"
    echo "   Expected phase time: ~1-2 hours"
else
    echo "📍 Phase: Final Kernels & Linking"
    echo "   Expected phase time: ~30 minutes"
fi

echo ""
echo "💡 Tip: watch -n 30 ~/watch-production-build.sh"
