# Quick Reference Guide

## File Locations

### On Mac (`~/Development/vrontier/Local-Software-Development-with-Open-Source/vllm-gb10/`)
**Purpose:** GitHub repository - documentation and build configs only

- ✅ Documentation (README, CONTRIBUTING, etc.)
- ✅ Dockerfile.gb10
- ✅ Example configs
- ✅ Scripts (publish.sh, sync.sh, etc.)
- ❌ NO secrets, NO build artifacts, NO models

### On Stella (`~/vllm-gb10/`)
**Purpose:** Build directory with full vLLM source

- ✅ Everything from Mac (synced)
- ✅ vLLM source code (from PR #31740)
- ✅ Build logs and artifacts
- ❌ NO runtime secrets

### On Stella (`~/vllm-service/`)
**Purpose:** Runtime directory with production configs

- ✅ docker-compose.yml (production)
- ✅ .env (with HF_TOKEN)
- ✅ Deployment scripts (deploy.sh, monitor.sh, test.sh)
- ✅ Runtime logs
- ❌ NOT synced to Mac (contains secrets)

### On Stella (`~/ai-shared/`)
**Purpose:** Shared model storage

- ✅ Model cache (59GB for GLM-4.7-Flash)
- ❌ NOT synced (too large)

---

## Common Commands

### On Mac

```bash
# Navigate to project
cd ~/Development/vrontier/Local-Software-Development-with-Open-Source/vllm-gb10

# Edit documentation
vim README.md

# Commit changes
git add .
git commit -m "Update documentation"

# Push changes to Stella
./sync.sh push

# Pull updates from Stella
./sync.sh pull

# Check what would be synced
./sync.sh status

# Push to GitHub
git push origin main
```

### On Stella (via SSH from Mac)

```bash
# Connect
ssh stella-llm

# Check build status
~/vllm-gb10/check-build.sh

# Monitor build (auto-refresh every 10 seconds)
watch -n 10 ~/vllm-gb10/check-build.sh

# Deploy service (after build completes)
~/vllm-service/deploy.sh

# Monitor running service
~/vllm-service/monitor.sh

# Test inference
~/vllm-service/test.sh

# View logs
docker logs -f vllm-glm47

# Restart service
cd ~/vllm-service && docker compose restart

# Stop service
cd ~/vllm-service && docker compose down
```

### Publishing (from Stella)

```bash
ssh stella-llm

# Set credentials
export DOCKERHUB_USERNAME="your-username"
export GITHUB_USERNAME="your-username"
export GITHUB_TOKEN="ghp_your_token"

# Login
docker login
echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_USERNAME --password-stdin

# Publish
cd ~/vllm-gb10
./publish.sh
```

---

## What Needs to Run on Stella

### Build Phase (one-time, ~4 hours)
```bash
ssh stella-llm
cd ~/vllm-gb10
docker build -f Dockerfile.gb10 -t vllm-gb10:latest .
```

**Requirements:**
- Docker with NVIDIA runtime
- CUDA 12.4+ drivers
- 20GB disk space for image
- Internet connection (for downloads)

### Runtime Phase (always)
```bash
ssh stella-llm
cd ~/vllm-service
docker compose up -d
```

**Requirements:**
- Built Docker image: `vllm-gb10:latest`
- Model cache: `~/ai-shared/cache/huggingface/`
- Environment: `.env` with HF_TOKEN
- 80GB disk space (20GB image + 59GB model + overhead)
- GPU: NVIDIA GB10

---

## What Does NOT Need to Run on Stella

❌ **Git repository** - That's on Mac only  
❌ **GitHub workflows** - Runs on GitHub servers  
❌ **Development tools** - Edit on Mac, sync to Stella  
❌ **vLLM source code** - Only needed during build, not runtime

---

## Syncing Workflow

### Making Changes

```bash
# On Mac
cd ~/Development/vrontier/Local-Software-Development-with-Open-Source/vllm-gb10
vim Dockerfile.gb10          # Make changes
git commit -am "Update"      # Commit locally
./sync.sh push               # Sync to Stella

# On Stella (rebuild if needed)
ssh stella-llm
cd ~/vllm-gb10
docker build -f Dockerfile.gb10 -t vllm-gb10:latest .
cd ~/vllm-service
docker compose up -d         # Redeploy with new image
```

### Getting Updates

```bash
# On Mac
./sync.sh pull               # Get any changes from Stella
git diff                     # Review changes
git add .                    # Stage if good
git commit -m "Update"       # Commit
```

---

## Directory Sizes

| Location | Purpose | Size |
|----------|---------|------|
| Mac: `vllm-gb10/` | Git repo | ~100 MB |
| Stella: `vllm-gb10/` | Build dir | ~500 MB |
| Stella: `vllm-service/` | Runtime | ~10 MB |
| Stella: `ai-shared/` | Models | ~59 GB |
| Stella: Docker image | Container | ~20 GB |
| **Total on Mac** | | **~100 MB** |
| **Total on Stella** | | **~80 GB** |

---

## Backup Checklist

✅ **Mac:** Git repository (auto-backed up via Git)  
✅ **Stella:** `~/vllm-service/.env` (HuggingFace token)  
✅ **Stella:** `~/vllm-service/docker-compose.yml` (production config)  
⚠️ **Stella:** Docker image (can rebuild or pull from registry)  
⚠️ **Stella:** Model cache (can re-download)

---

## Troubleshooting

### Build not completing
```bash
ssh stella-llm
~/vllm-gb10/check-build.sh
tail -100 ~/vllm-gb10/build.log
```

### Service won't start
```bash
ssh stella-llm
~/vllm-service/monitor.sh
docker logs vllm-glm47
```

### Can't access API
```bash
ssh stella-llm
curl http://localhost:8000/health
docker ps | grep vllm
```

### Sync issues
```bash
# On Mac
./sync.sh status            # See what's different
./sync.sh pull              # Get remote changes
./sync.sh push              # Push local changes
```

---

## Quick Links

- **GitHub:** (create after publishing)
- **Docker Hub:** https://hub.docker.com/r/YOUR_USERNAME/vllm-gb10
- **GHCR:** https://github.com/YOUR_USERNAME/vllm-gb10/pkgs/container/vllm-gb10
- **Upstream PR:** https://github.com/vllm-project/vllm/pull/31740
- **vLLM Docs:** https://docs.vllm.ai/

---

## One-Line Commands

```bash
# Check build progress
ssh stella-llm '~/vllm-gb10/check-build.sh'

# Deploy service
ssh stella-llm '~/vllm-service/deploy.sh'

# Test inference
ssh stella-llm '~/vllm-service/test.sh'

# Check service health
curl http://stella.home.arpa:8000/health

# Sync from Mac to Stella
cd ~/Development/vrontier/Local-Software-Development-with-Open-Source/vllm-gb10 && ./sync.sh push
```
