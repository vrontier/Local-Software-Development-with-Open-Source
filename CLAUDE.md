# CLAUDE.md

This file provides guidance for AI assistants working with this repository.

## Project Overview

This is a **documentation and configuration repository** for a production dual-GPU AI infrastructure running self-hosted open-source LLMs on NVIDIA Blackwell hardware (GB10/Grace Blackwell). All inference runs locally via **llama.cpp** with no external API dependencies.

## Repository Structure

```
├── README.md                    # Main project overview
├── STATUS.md                    # Current deployment status (check this first)
├── CHANGELOG.md                 # Project timeline and changes
├── systems/                     # Per-system documentation
│   ├── pegasus/                 # GPT-OSS-120B deployment docs
│   └── stella/                  # Qwen3-8B deployment docs
├── docs/                        # Supporting documentation
│   ├── archive/                 # Historical documents and sessions
│   └── research/                # Benchmarks and analysis
├── vllm-gb10/                   # Historical vLLM GB10 project (superseded by llama.cpp)
│   ├── Dockerfile.gb10          # Custom Dockerfile for Blackwell
│   ├── SETUP.md                 # Complete setup guide
│   └── *.sh                     # Build and deployment scripts
└── scripts/                     # Utility scripts
```

## Production Systems

Both systems run **llama.cpp** as **systemd services** (`llama-server.service`), auto-starting on boot after NFS mount is ready.

### Pegasus (Architect & Analyst)
- **Model**: OpenAI GPT-OSS-120B (117B MoE params, MXFP4, 59 GiB GGUF)
- **API**: http://pegasus.home.arpa:8000
- **Hardware**: ASUS Ascent GX10, 128GB GPU, SM 12.1
- **Performance**: 58.8 tok/s generation, 1,809 tok/s prompt, 131K context
- **Engine**: llama.cpp (build b7999+, CUDA 13.0)
- **Model Location**: `/mnt/models/gpt-oss-120b-GGUF/`
- **Service**: `llama-server.service` (systemd)
- **Docs**: `systems/pegasus/`

### Stella (General-Purpose)
- **Model**: Qwen3-8B (8.2B dense, Q8_0, 8.1 GiB GGUF)
- **API**: http://stella.home.arpa:8000
- **Hardware**: Lenovo ThinkStation PGX, 128GB unified ARM, SM 12.1
- **Performance**: 27.8 tok/s generation, 2,236 tok/s prompt, 32K context
- **Engine**: llama.cpp (build b7999+, CUDA 13.0)
- **Model Location**: `/mnt/models/Qwen3-8B-GGUF/Qwen_Qwen3-8B-Q8_0.gguf`
- **Service**: `llama-server.service` (systemd)
- **Docs**: `systems/stella/`

## Infrastructure

- **Model Storage**: NFS at `flashstore.home.arpa:/volume1/models` (mounted at `/mnt/models` on both hosts)
- **DNS**: Local `.home.arpa` domain (resolved by pfSense at 10.0.0.1)
- **Ports**: 8000 for llama-server API on each system
- **NFS fstab**: `flashstore.home.arpa:/volume1/models /mnt/models nfs4 rw,hard,intr,_netdev,noatime,nofail,... 0 0`

## Key Technical Details

### llama.cpp Deployments
- Both systems built from source with CUDA 13.0 for GB10 (SM 12.1)
- Pegasus build flags: `-DGGML_CUDA=ON -DGGML_CUDA_F16=ON -DCMAKE_CUDA_ARCHITECTURES='121a-real'` (MXFP4 support)
- Stella build flags: `-DGGML_CUDA=ON -DGGML_CUDA_F16=ON -DCMAKE_CUDA_ARCHITECTURES=121`
- Source: `~/llama.cpp/` on each host
- Binary: `~/llama.cpp/build/bin/llama-server`

### API Format
Both systems expose an OpenAI-compatible API:
- **Pegasus**: Includes `reasoning_content` field (chain-of-thought), uses `--jinja` for chat template
- **Stella**: Supports thinking mode (Qwen3 think/no-think), OpenAI-compatible responses

### Key Runtime Flags
```bash
# Common flags used on both systems:
-ngl 999          # All layers on GPU
--no-mmap         # Critical on GB10 — avoids slow mmap, 3-5x faster loading
-fa on            # Flash attention
-c 131072         # 128K context
--host 0.0.0.0    # Listen on all interfaces
--port 8000       # API port

# Pegasus-specific:
--jinja           # GPT-OSS embedded chat template

# Model paths:
-m /mnt/models/gpt-oss-120b-GGUF/gpt-oss-120b-mxfp4-00001-of-00003.gguf   # Pegasus
-m /mnt/models/Qwen3-8B-GGUF/Qwen_Qwen3-8B-Q8_0.gguf                       # Stella
```

## Working with This Repository

### Before Making Changes
1. Check `STATUS.md` for current system state
2. Review relevant system docs in `systems/[name]/`
3. Check `CHANGELOG.md` for recent changes

### Documentation Conventions
- System-specific docs go in `systems/[system-name]/`
- Each system has a `README.md` and `QUICKSTART.md`
- Benchmarks and analysis go in `docs/research/`
- Archive historical content in `docs/archive/`
- Use `CHANGELOG.md` for significant changes

### Common Tasks

**Check system health:**
```bash
curl http://pegasus.home.arpa:8000/health
curl http://stella.home.arpa:8000/health
```

**Service management (on respective hosts):**
```bash
sudo systemctl start llama-server     # Start
sudo systemctl stop llama-server      # Stop
sudo systemctl restart llama-server   # Restart
sudo systemctl status llama-server    # Status
journalctl -u llama-server -f         # Logs
```

**SSH access (from Mac):**
```bash
ssh pegasus-llm    # Pegasus (as llm-agent)
ssh stella-llm     # Stella (as llm-agent)
```

## Model IDs (for API calls)

llama.cpp uses GGUF filenames as model IDs:
- **Pegasus**: `gpt-oss-120b-mxfp4-00001-of-00003.gguf`
- **Stella**: `Qwen_Qwen3-8B-Q8_0.gguf`

Query available models: `curl http://<host>:8000/v1/models`

## OpenCode Integration

Models configured in `~/.config/opencode/opencode.json` using `@ai-sdk/openai-compatible` provider.

## Maintenance Commands

**Rebuild llama.cpp (on either host):**
```bash
cd ~/llama.cpp && git pull
cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON -DGGML_CUDA_F16=ON -DCMAKE_CUDA_ARCHITECTURES=121 -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc
cmake --build build --config Release -j 20
sudo systemctl restart llama-server
```

**NFS mount (if not in fstab):**
```bash
sudo mount -t nfs4 flashstore.home.arpa:/volume1/models /mnt/models \
  -o rw,hard,intr,_netdev,noatime,nofail,rsize=1048576,wsize=1048576
```

## Models on NFS

| Path | Size | Status |
|------|------|--------|
| `gpt-oss-120b-GGUF/` | 60 GB | Active (Pegasus) |
| `Qwen3-8B-GGUF/` | 8.5 GB | Active (Stella) |
| `models--openai--gpt-oss-120b/` | 130 GB | Legacy (safetensors, can be removed) |
| `models--Qwen--Qwen3-Coder-30B-A3B-Instruct/` | 57 GB | Available |
| `models--Qwen--Qwen3-32B-AWQ/` | 19 GB | Available (vLLM format) |
| `Qwen3-32B-GGUF/` | 33 GB | Available (benchmarked at 6.5 tok/s) |
| `Qwen3-14B-GGUF/` | 15 GB | Available |

## Known Issues

- GB10 requires `--no-mmap` flag — mmap is extremely slow on this platform
- GDS (GPU Direct Storage) not supported on these platforms
- Dense models are memory-bandwidth bound on GB10: ~6.5 tok/s (32B), ~14.7 tok/s (14B), ~27.8 tok/s (8B)
- NVFP4 quantization not supported on GB10 SM 12.1 in current vLLM/llama.cpp releases
- Model loading from NFS takes ~1-2 min (use `--no-mmap` to avoid 3-5x penalty)
- Pegasus MXFP4 build requires `-DCMAKE_CUDA_ARCHITECTURES='121a-real'`

## External References

- llama.cpp: https://github.com/ggml-org/llama.cpp
- llama.cpp GB10 Guide: https://learn.arm.com/learning-paths/laptops-and-desktops/dgx_spark_llamacpp/
- llama.cpp GB10 Benchmarks: https://github.com/ggml-org/llama.cpp/discussions/16578
- GPT-OSS GGUF: https://huggingface.co/ggml-org/gpt-oss-120b-GGUF
- GPT-OSS llama.cpp Guide: https://github.com/ggml-org/llama.cpp/discussions/15396
- vLLM Docs (historical): https://docs.vllm.ai/
