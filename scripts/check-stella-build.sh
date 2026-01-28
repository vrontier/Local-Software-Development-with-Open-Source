#!/bin/bash
# Check GadflyII vLLM build progress on Stella

echo "=== Stella Build Status ==="
echo ""

# Check if screen session is running
echo "Screen session:"
ssh stella-llm "screen -ls | grep gadflyii-build || echo 'No build session running'"
echo ""

# Check last 30 lines of build log
echo "Recent build log:"
ssh stella-llm "tail -30 ~/vllm-gadflyii/build.log 2>/dev/null || echo 'Build log not found yet'"
echo ""

# Check if image exists
echo "Docker images:"
ssh stella-llm "docker images | grep -E 'REPOSITORY|vllm'"
