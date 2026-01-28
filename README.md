# Local Agentic Software Development Platform 

This repository contains documentation and configuration for deploying a **production dual-GPU AI infrastructure** with self-hosted Open Source LLMs on NVIDIA Blackwell hardware (GB10/Grace Blackwell).

All AI inference runs locally on your own GPU hardware, giving you full control, privacy, and no API costs.

## 🎯 Current Deployment

**Two production systems serving complementary roles:**

- **Pegasus** - [GPT-OSS-120B](systems/pegasus/) (117B params) - Architect & Analyst
- **Stella** - [GLM-4.7-Flash-NVFP4](systems/stella/) (30B MoE) - Fast Inference

📊 **[View Current Status →](STATUS.md)** | 📖 **[View Changelog →](CHANGELOG.md)**

## 🚀 Production Systems

### Pegasus - GPT-OSS-120B
**Status**: ✅ Operational | **API**: http://pegasus.home.arpa:8000

- **Model**: OpenAI GPT-OSS-120B (117B params, MXFP4 quantized)
- **Performance**: 34 tokens/sec sustained
- **Context**: 131,072 tokens
- **Role**: Long-context analysis, architecture design, code review
- **Features**: OpenAI-compatible tool calling

📖 **[Documentation →](systems/pegasus/)** | 🚀 **[Quick Start →](systems/pegasus/QUICKSTART.md)**

### Stella - GLM-4.7-Flash-NVFP4
**Status**: 🔄 Deploying | **API**: http://stella.home.arpa:8000

- **Model**: GadflyII/GLM-4.7-Flash-NVFP4 (30B MoE, NVFP4 quantized)
- **Target**: 50+ tokens/sec
- **Context**: Up to 202,752 tokens
- **Role**: Fast interactive chat, quick queries
- **Special**: Blackwell-optimized mixed precision quantization

📖 **[Documentation →](systems/stella/)**

## 📦 Projects

### [vLLM for NVIDIA GB10](vllm-gb10/)

Self-contained vLLM project with native GB10/Blackwell support. This is the foundation for both Pegasus and Stella deployments.

**Features:**
- Native GB10/Blackwell support (SM 12.1)
- Multi-architecture CUDA kernels
- OpenAI-compatible API
- Docker-based deployment
- Comprehensive documentation

📖 **[vLLM GB10 Project →](vllm-gb10/)**

## 🏗️ Architecture

```
                 ┌─────────────────────────────┐
                 │   Frontend / Clients        │
                 │   - OpenCode / Cursor       │
                 │   - API clients             │
                 │   - SSH access              │
                 └──────────────┬──────────────┘
                                │
                ┌───────────────┴───────────────┐
                │       OpenAI API & SSH        │
                │                               │
       ┌────────▼─────────┐           ┌─────────▼────────┐
       │     Pegasus      │           │      Stella      │
       │  ASUS Ascend     │           │  ASUS Ascent     │
       │  GB10 (128GB)    │           │  GX10 GB (128GB) │
       │                  │           │  Grace Blackwell │
       │  GPT-OSS-120B    │           │  GLM-4.7-NVFP4   │
       │  117B params     │           │  30B MoE         │
       │  34 tok/s        │           │  50+ tok/s       │
       │  :8000           │           │  :8000           │
       └────────┬─────────┘           └─────────┬────────┘
                │                               │
                └───────────────┬───────────────┘
                                │
                    ┌───────────▼──────────┐
                    │   NFS Model Storage  │
                    │  flashstore.arpa     │
                    │  9.1TB RAID5         │
                    └──────────────────────┘
```

## 📚 Documentation Structure

```
├── STATUS.md                    # Current deployment status
├── CHANGELOG.md                 # Project timeline and changes
├── systems/                     # Per-system documentation
│   ├── pegasus/                # GPT-OSS-120B deployment
│   └── stella/                 # GLM-4.7-Flash-NVFP4 deployment
├── docs/                       # Supporting documentation
│   ├── deployment/             # Deployment guides
│   ├── network/                # Network configuration
│   ├── archive/                # Historical documents
│   └── research/               # Future projects
├── vllm-gb10/                  # vLLM GB10 project (self-contained)
└── scripts/                    # Utility scripts
```

### 📖 Key Documents

**System Documentation**:
- [Pegasus (GPT-OSS-120B)](systems/pegasus/) - Production Architect & Analyst system
- [Stella (GLM-4.7-Flash-NVFP4)](systems/stella/) - Fast inference system

**Status & History**:
- [STATUS.md](STATUS.md) - Current deployment status
- [CHANGELOG.md](CHANGELOG.md) - Project timeline

**Deployment**:
- [vLLM GB10 Setup Guide](vllm-gb10/SETUP.md) - Complete GB10 build guide

## 🚀 Quick Start

### Check System Status
```bash
# View current deployment status
cat STATUS.md

# Check Pegasus
curl http://pegasus.home.arpa:8000/health

# Check Stella (when deployed)
curl http://stella.home.arpa:8000/health
```

### Using the APIs

See individual system documentation:
- **Pegasus**: [systems/pegasus/QUICKSTART.md](systems/pegasus/QUICKSTART.md)
- **Stella**: [systems/stella/QUICKSTART.md](systems/stella/QUICKSTART.md) (coming soon)

## Contributing

Contributions welcome! See [vllm-gb10/CONTRIBUTING.md](vllm-gb10/CONTRIBUTING.md).

## License

MIT License - see [LICENSE](LICENSE) for details.

Individual components may have their own licenses:
- vLLM: Apache 2.0
- Docker images: Based on official vLLM images
