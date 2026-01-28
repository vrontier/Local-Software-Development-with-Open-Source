# Deployment Architecture

This document explains what runs where in the vLLM GB10 setup.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Mac Studio (Development Machine)                           │
│  - GitHub repository (vllm-gb10/)                           │
│  - Documentation and Dockerfiles                            │
│  - Publishing scripts                                       │
│  - SSH access to AI backends                                │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ SSH (stella-llm)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Stella (AI Compute Backend #1)                             │
│  Hostname: stella.home.arpa                                 │
│  GPU: NVIDIA GB10 (Grace Blackwell), 128GB                  │
│                                                              │
│  ~/vllm-gb10/ (Build directory)                             │
│  ├── Dockerfile.gb10                 ← Build source         │
│  ├── check-build.sh                  ← Monitor builds       │
│  ├── vLLM source code                ← From PR #31740       │
│  └── build.log                       ← Build output         │
│                                                              │
│  ~/vllm-service/ (Runtime directory)                        │
│  ├── docker-compose.yml              ← Service config       │
│  ├── .env                            ← Secrets (HF token)   │
│  ├── deploy.sh                       ← Deploy service       │
│  ├── monitor.sh                      ← Monitor service      │
│  ├── test.sh                         ← Test inference       │
│  └── logs/                           ← Runtime logs         │
│                                                              │
│  ~/ai-shared/ (Shared storage)                              │
│  ├── cache/huggingface/              ← Model cache (59GB)   │
│  └── models/huggingface/             ← Model storage        │
│                                                              │
│  Docker Images:                                             │
│  └── vllm-gb10:latest                ← Built image (~20GB)  │
│                                                              │
│  Running Services:                                          │
│  └── vllm-glm47 (port 8000)          ← Inference server    │
└─────────────────────────────────────────────────────────────┘
```

## What Runs Where

### Mac Studio (Development Machine)

**Purpose:** Development, documentation, version control

**Required:**
- GitHub repository with documentation
- SSH access to AI backends
- (Optional) Docker Hub / GHCR credentials for publishing

**Does NOT need:**
- NVIDIA GPU
- vLLM installation
- Model files
- Docker images

**Storage:** ~100 MB for repository

---

### Stella (AI Compute Backend #1)

**Purpose:** Build container, run inference server

**Required:**
1. **Build-time dependencies:**
   - Docker with NVIDIA Container Runtime
   - CUDA 12.4+ drivers
   - `~/vllm-gb10/` with source code and Dockerfile
   
2. **Runtime dependencies:**
   - Built Docker image: `vllm-gb10:latest`
   - Service configuration: `~/vllm-service/`
   - Model cache: `~/ai-shared/cache/` (59GB for GLM-4.7-Flash)
   - Environment file with HuggingFace token

**Storage:**
- Docker image: ~20GB
- Model cache: ~59GB per model
- Logs: ~100MB per day
- **Total:** ~80GB minimum

**Services running:**
- `vllm-glm47` container (inference API on port 8000)

---

### Other GB10 Box (AI Compute Backend #2)

**Purpose:** Secondary inference server or failover

**Required:**
- Same as Stella runtime dependencies
- Can pull pre-built image from Docker Hub/GHCR
- Can share model cache via NFS or copy locally

**Does NOT need:**
- Build dependencies
- Full source code

**Storage:**
- Docker image: ~20GB
- Model cache: 0GB (if using NFS) or ~59GB (if local copy)
- **Total:** ~20-80GB

---

## File Organization

### On Mac (GitHub Repository)

```
vllm-gb10/
├── README.md                    # Public documentation
├── CONTRIBUTING.md              # Contribution guide
├── PUBLISHING.md                # Publishing workflow
├── DEPLOYMENT.md                # This file
├── LICENSE                      # MIT license
├── Dockerfile.gb10              # Build instructions
├── docker-compose.example.yml   # Deployment template
├── .env.example                 # Environment template
├── .gitignore                   # Prevent secrets
├── publish.sh                   # Publishing script
├── check-build.sh               # Build monitor
└── .github/
    └── workflows/
        └── build-and-publish.yml
```

**What's NOT in GitHub:**
- ❌ HuggingFace tokens
- ❌ Model files
- ❌ Build logs
- ❌ Production configs with secrets
- ❌ vLLM source code (linked as submodule or reference)

---

### On Stella (AI Backend)

```
~/vllm-gb10/                     # BUILD directory
├── [All files from GitHub]      # Synced from Mac
├── [vLLM source code]           # Cloned from PR #31740
├── build.log                    # Local build output
└── build/                       # Build artifacts

~/vllm-service/                  # RUNTIME directory
├── docker-compose.yml           # Production config (not in GitHub)
├── .env                         # Secrets (not in GitHub)
├── deploy.sh                    # Deployment script
├── monitor.sh                   # Monitoring script
├── test.sh                      # Testing script
└── logs/                        # Runtime logs

~/ai-shared/                     # SHARED STORAGE
├── cache/huggingface/           # Model downloads
└── models/huggingface/          # Model storage
```

---

## Syncing Workflow

### Mac → Stella (Update build configuration)

```bash
# On Mac: Edit files, commit to git
cd ~/Development/vrontier/Local-Software-Development-with-Open-Source/vllm-gb10
vim Dockerfile.gb10
git commit -am "Update build config"

# Sync to Stella
rsync -av --exclude='.git' ./ stella-llm:~/vllm-gb10/

# On Stella: Rebuild
ssh stella-llm
cd ~/vllm-gb10
docker build -f Dockerfile.gb10 -t vllm-gb10:latest .
```

### Stella → Mac (Get monitoring scripts)

```bash
# On Mac: Sync deployment scripts for documentation
rsync -av stella-llm:~/vllm-service/*.sh ./vllm-gb10/examples/
```

---

## Deployment Scenarios

### Scenario 1: Single Backend (Current)

```
Mac → SSH → Stella (build + run)
```

**Workflow:**
1. Develop on Mac
2. Build on Stella
3. Run on Stella
4. Access API: `http://stella.home.arpa:8000`

---

### Scenario 2: Dual Backend (Planned)

```
Mac → SSH → Stella (build + run)
    ↓
    ↘ SSH → Other Box (pull + run)
```

**Workflow:**
1. Build on Stella
2. Push to Docker Hub
3. Pull on Other Box
4. Load balance between both

---

### Scenario 3: Public Distribution

```
Mac → GitHub → Community
                  ↓
              Docker Hub → Anyone with GB10
```

**Workflow:**
1. Push code to GitHub
2. Publish image to Docker Hub/GHCR
3. Others pull and run
4. Community contributes back

---

## Port Mapping

| Service | Port | Access |
|---------|------|--------|
| vLLM API | 8000 | `http://stella.home.arpa:8000` |
| Health Check | 8000 | `http://stella.home.arpa:8000/health` |
| OpenAI API | 8000 | `http://stella.home.arpa:8000/v1/*` |

---

## Security Considerations

### On Mac
- ✅ No secrets in Git repository
- ✅ `.gitignore` prevents accidental commits
- ✅ Example files show structure without real values

### On Stella
- ✅ `.env` file not synced to Mac
- ✅ HuggingFace token in environment variable
- ✅ No external access (internal network only)
- ⚠️ Consider firewall if exposing to internet

---

## Backup Strategy

### What to Backup

**On Mac:**
- ✅ Git repository (already version controlled)

**On Stella:**
- ✅ `~/vllm-service/.env` (HuggingFace token)
- ✅ `~/vllm-service/docker-compose.yml` (production config)
- ⚠️ Model cache can be re-downloaded if needed
- ⚠️ Docker image can be rebuilt or pulled

### Backup Commands

```bash
# Backup production configs
rsync -av stella-llm:~/vllm-service/ ~/Backups/stella-vllm-service/

# Restore if needed
rsync -av ~/Backups/stella-vllm-service/ stella-llm:~/vllm-service/
```

---

## Minimal Runtime Requirements

### To run inference (no building):

**On AI Backend:**
1. Docker with NVIDIA runtime
2. Pre-built image: `vllm-gb10:latest`
3. `~/vllm-service/docker-compose.yml`
4. `~/vllm-service/.env` (with HF_TOKEN)
5. Model cache: `~/ai-shared/cache/`

**Storage:** ~80GB (20GB image + 59GB model)

**Commands:**
```bash
cd ~/vllm-service
docker compose up -d
```

That's it! No build tools, no source code needed.

---

## Summary

| Component | Mac | Stella | Other Box |
|-----------|-----|--------|-----------|
| GitHub repo | ✅ | ❌ | ❌ |
| Build tools | ❌ | ✅ | ❌ |
| vLLM source | ❌ | ✅ | ❌ |
| Docker image | ❌ | ✅ | ✅ |
| Model cache | ❌ | ✅ | ✅ or NFS |
| Service config | ❌ | ✅ | ✅ |
| Runs inference | ❌ | ✅ | ✅ |

**Mac:** Development & documentation only  
**Stella:** Build & runtime  
**Other Box:** Runtime only (pulls pre-built image)
