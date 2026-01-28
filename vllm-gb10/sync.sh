#!/bin/bash
# Sync script between Mac and Stella

set -e

REMOTE="stella-llm"
LOCAL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REMOTE_BUILD_DIR="~/vllm-gb10"
REMOTE_SERVICE_DIR="~/vllm-service"

echo "=== vLLM GB10 Sync Script ==="
echo ""

# Function to show usage
usage() {
    echo "Usage: $0 [push|pull|status]"
    echo ""
    echo "Commands:"
    echo "  push    - Push local changes to Stella build directory"
    echo "  pull    - Pull updates from Stella (scripts only, not secrets)"
    echo "  status  - Show what would be synced"
    echo ""
    exit 1
}

# Files to sync (documentation and build configs)
SYNC_FILES=(
    "README.md"
    "SETUP.md"
    "QUICKREF.md"
    "CONTRIBUTING.md"
    "PUBLISHING.md"
    "DEPLOYMENT.md"
    "INTEGRATION.md"
    "FILES.md"
    "LICENSE"
    "Dockerfile.gb10"
    "docker-compose.example.yml"
    ".env.example"
    ".gitignore"
    "publish.sh"
    "check-build.sh"
    ".github/"
)

case "${1:-}" in
    push)
        echo "Pushing changes from Mac to Stella..."
        echo ""
        
        # Sync to build directory
        rsync -av --progress \
            --files-from=<(printf '%s\n' "${SYNC_FILES[@]}") \
            "$LOCAL_DIR/" "$REMOTE:$REMOTE_BUILD_DIR/"
        
        echo ""
        echo "✓ Pushed to $REMOTE:$REMOTE_BUILD_DIR/"
        echo ""
        echo "Next steps on Stella:"
        echo "  ssh $REMOTE"
        echo "  cd ~/vllm-gb10"
        echo "  docker build -f Dockerfile.gb10 -t vllm-gb10:latest ."
        ;;
    
    pull)
        echo "Pulling updates from Stella to Mac..."
        echo ""
        
        # Pull from build directory (no secrets)
        rsync -av --progress \
            --files-from=<(printf '%s\n' "${SYNC_FILES[@]}") \
            "$REMOTE:$REMOTE_BUILD_DIR/" "$LOCAL_DIR/"
        
        echo ""
        echo "✓ Pulled from $REMOTE:$REMOTE_BUILD_DIR/"
        echo ""
        echo "Review changes:"
        echo "  git status"
        echo "  git diff"
        ;;
    
    status)
        echo "Checking sync status..."
        echo ""
        
        rsync -avn --delete \
            --files-from=<(printf '%s\n' "${SYNC_FILES[@]}") \
            "$LOCAL_DIR/" "$REMOTE:$REMOTE_BUILD_DIR/"
        
        echo ""
        echo "Run './sync.sh push' to sync these changes"
        ;;
    
    *)
        usage
        ;;
esac
