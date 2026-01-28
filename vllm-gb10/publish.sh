#!/bin/bash
# Publish vllm-gb10 to Docker Hub and GitHub Container Registry

set -e

# Configuration
IMAGE_NAME="vllm-gb10"
VERSION="1.0.0"
DOCKERHUB_USER="${DOCKERHUB_USERNAME}"  # Set via environment or replace
GITHUB_USER="${GITHUB_USERNAME}"        # Set via environment or replace

echo "=== vLLM GB10 Image Publisher ==="
echo ""

# Check if image exists
if ! docker images | grep -q "vllm-gb10.*latest"; then
    echo "ERROR: vllm-gb10:latest image not found!"
    echo "Please build the image first."
    exit 1
fi

echo "✓ Found vllm-gb10:latest image"
echo ""

# Verify logins
echo "=== Login Verification ==="

# Docker Hub
if [ -n "$DOCKERHUB_USER" ]; then
    echo "Docker Hub user: $DOCKERHUB_USER"
    if ! docker login --username "$DOCKERHUB_USER" --password-stdin < /dev/null 2>/dev/null; then
        echo "Please log in to Docker Hub:"
        docker login
    fi
    echo "✓ Docker Hub authenticated"
else
    echo "⚠ DOCKERHUB_USERNAME not set, skipping Docker Hub publish"
fi

echo ""

# GitHub Container Registry
if [ -n "$GITHUB_USER" ]; then
    echo "GitHub user: $GITHUB_USER"
    if ! echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USER" --password-stdin 2>/dev/null; then
        echo "Please log in to GitHub Container Registry:"
        echo "(Use a Personal Access Token with write:packages scope)"
        docker login ghcr.io -u "$GITHUB_USER"
    fi
    echo "✓ GitHub Container Registry authenticated"
else
    echo "⚠ GITHUB_USERNAME not set, skipping GitHub CR publish"
fi

echo ""
echo "=== Tagging Images ==="

# Tag with version and latest
TAGS=("latest" "v$VERSION" "$(date +%Y%m%d)")

for TAG in "${TAGS[@]}"; do
    if [ -n "$DOCKERHUB_USER" ]; then
        docker tag vllm-gb10:latest "$DOCKERHUB_USER/$IMAGE_NAME:$TAG"
        echo "Tagged: $DOCKERHUB_USER/$IMAGE_NAME:$TAG"
    fi
    
    if [ -n "$GITHUB_USER" ]; then
        docker tag vllm-gb10:latest "ghcr.io/$GITHUB_USER/$IMAGE_NAME:$TAG"
        echo "Tagged: ghcr.io/$GITHUB_USER/$IMAGE_NAME:$TAG"
    fi
done

echo ""
echo "=== Publishing to Docker Hub ==="

if [ -n "$DOCKERHUB_USER" ]; then
    for TAG in "${TAGS[@]}"; do
        echo "Pushing $DOCKERHUB_USER/$IMAGE_NAME:$TAG..."
        docker push "$DOCKERHUB_USER/$IMAGE_NAME:$TAG"
    done
    echo "✓ Published to Docker Hub"
else
    echo "⚠ Skipped (no DOCKERHUB_USERNAME)"
fi

echo ""
echo "=== Publishing to GitHub Container Registry ==="

if [ -n "$GITHUB_USER" ]; then
    for TAG in "${TAGS[@]}"; do
        echo "Pushing ghcr.io/$GITHUB_USER/$IMAGE_NAME:$TAG..."
        docker push "ghcr.io/$GITHUB_USER/$IMAGE_NAME:$TAG"
    done
    echo "✓ Published to GitHub Container Registry"
else
    echo "⚠ Skipped (no GITHUB_USERNAME)"
fi

echo ""
echo "=== Publication Complete! ==="
echo ""
echo "Docker Hub images:"
if [ -n "$DOCKERHUB_USER" ]; then
    for TAG in "${TAGS[@]}"; do
        echo "  docker pull $DOCKERHUB_USER/$IMAGE_NAME:$TAG"
    done
fi

echo ""
echo "GitHub Container Registry images:"
if [ -n "$GITHUB_USER" ]; then
    for TAG in "${TAGS[@]}"; do
        echo "  docker pull ghcr.io/$GITHUB_USER/$IMAGE_NAME:$TAG"
    done
fi

echo ""
echo "Next steps:"
echo "1. Update README.md with your registry URLs"
echo "2. Create GitHub release with tag v$VERSION"
echo "3. Share on social media / forums!"
