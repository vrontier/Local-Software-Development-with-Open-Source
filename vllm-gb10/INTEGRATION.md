# Integration with Parent Repository

This document explains how the vllm-gb10 project fits within the parent Local-Software-Development-with-Open-Source repository.

## Repository Structure

```
Local-Software-Development-with-Open-Source/
├── README.md                    # Repository overview with links to vllm-gb10/
├── LICENSE                      # MIT License
├── .gitignore                   # Git exclusions
└── vllm-gb10/                   # vLLM GB10 project (complete, self-contained)
    ├── README.md                # vLLM GB10 overview and quick start
    ├── SETUP.md                 # Complete setup guide (SSH, GPU, deployment)
    ├── DEPLOYMENT.md            # Architecture and deployment scenarios
    ├── QUICKREF.md              # Quick command reference
    ├── INTEGRATION.md           # This file
    ├── CONTRIBUTING.md          # Contribution guide
    ├── PUBLISHING.md            # Publishing workflow
    ├── FILES.md                 # File listing
    ├── Dockerfile.gb10          # Build configuration
    ├── docker-compose.example.yml
    ├── .env.example
    ├── sync.sh                  # Mac ↔ Stella synchronization
    ├── publish.sh               # Publish to Docker Hub/GHCR
    ├── check-build.sh           # Build monitor
    └── .github/workflows/       # GitHub Actions (optional)
```

## Documentation Organization

All vLLM GB10 documentation is self-contained within the `vllm-gb10/` directory:

| File | Purpose | Audience |
|------|---------|----------|
| **README.md** | Overview, quick start, features | New users, quick reference |
| **SETUP.md** | Complete end-to-end setup guide | First-time setup |
| **QUICKREF.md** | Common commands reference | Daily operations |
| **DEPLOYMENT.md** | Architecture diagrams, scenarios | DevOps, multi-box setups |
| **CONTRIBUTING.md** | Contribution guidelines | Contributors |
| **PUBLISHING.md** | Publishing to registries | Maintainers |
| **INTEGRATION.md** | Repository structure (this file) | Developers |

## User Journey

### For New Users

1. Start with parent [README.md](../README.md) for overview
2. Navigate to [vllm-gb10/README.md](README.md) for quick start
3. Follow [SETUP.md](SETUP.md) for complete setup:
   - [SSH Access Setup](SETUP.md#ssh-access-setup)
   - [GPU Backend Configuration](SETUP.md#gpu-backend-configuration)
   - [Agent Configuration](SETUP.md#agent-configuration)
4. Use [QUICKREF.md](QUICKREF.md) for daily operations

### For Advanced Users

1. Jump to [vllm-gb10/README.md](README.md)
2. Pull pre-built image from Docker Hub
3. Reference [SETUP.md](SETUP.md) for config details as needed

### For Contributors

1. Read [CONTRIBUTING.md](CONTRIBUTING.md)
2. Review [DEPLOYMENT.md](DEPLOYMENT.md) for architecture
3. Use [sync.sh](sync.sh) for Mac ↔ Stella workflow

## Syncing Between Mac and Stella

### File Locations

**Mac (Development):**
```
~/Development/vrontier/Local-Software-Development-with-Open-Source/
└── vllm-gb10/                   ← Git repository
    ├── README.md, SETUP.md, etc.
    ├── Dockerfile.gb10
    └── sync.sh
```

**Stella (GPU Backend):**
```
~/vllm-gb10/                     ← Synced from Mac
├── [All files from Mac]         ← Synced via sync.sh
├── [vLLM source code]           ← Additional files (not on Mac)
└── build.log                    ← Build artifacts (not on Mac)

~/vllm-service/                  ← Runtime configs (NOT synced)
├── docker-compose.yml           ← Production config (has secrets)
├── .env                         ← HuggingFace token (not on Mac)
└── logs/                        ← Runtime logs
```

### Sync Commands

```bash
# From Mac
cd ~/Development/vrontier/Local-Software-Development-with-Open-Source/vllm-gb10

# Push changes to Stella
./sync.sh push

# Pull updates from Stella
./sync.sh pull

# Check sync status
./sync.sh status
```

## Publishing Strategy

The `vllm-gb10/` directory is designed to be publishable as either:

**Option A: Standalone Repository**
- Extract `vllm-gb10/` as its own GitHub repo
- All documentation is self-contained
- No external dependencies

**Option B: Monorepo Subdirectory (Current)**
- Keep as part of Local-Software-Development-with-Open-Source
- Parent README.md links to vllm-gb10/
- Good for integrated local development setup

**Current approach:** Option B

## Benefits of This Structure

✅ **Self-Contained**
- All vLLM GB10 docs in one directory
- Can be extracted as standalone project
- No dependencies on parent repository

✅ **Clear Hierarchy**
- Parent README → Overview
- vllm-gb10/README → Quick start
- vllm-gb10/SETUP.md → Complete guide

✅ **Easy Publishing**
- `vllm-gb10/` can be published to GitHub as-is
- Docker images published to Docker Hub/GHCR
- Community can use either source

✅ **Security**
- Secrets stay on Stella (~/vllm-service/)
- Only documentation and configs on Mac
- sync.sh excludes sensitive files

## Future Projects

The parent repository structure allows for additional projects:

```
Local-Software-Development-with-Open-Source/
├── README.md
├── vllm-gb10/          # NVIDIA GB10 inference
├── sglang-h100/        # Future: H100 backend (placeholder)
├── ollama-mac/         # Future: Mac Studio local LLM (placeholder)
└── agents/             # Future: Agent configurations (placeholder)
```

Each project directory would be self-contained with its own SETUP.md.

## Summary

**Repository Structure:**
- **Parent**: Overview and links to projects
- **vllm-gb10/**: Complete, self-contained vLLM GB10 project
- **Flexibility**: Can extract vllm-gb10/ as standalone repo

**Documentation Flow:**
- Parent README → vllm-gb10/README → vllm-gb10/SETUP.md
- All vLLM docs within vllm-gb10/ directory
- No redundancy, clear navigation

**Syncing:**
- Mac: Git repository with documentation
- Stella: Full deployment with vLLM source
- sync.sh: Keep them in sync (excludes secrets)

**Result:** Clean separation between overview (parent) and implementation (vllm-gb10), with ability to publish either way.
