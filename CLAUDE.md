# CLAUDE.md

This file provides guidance for AI assistants working with this repository.

## Project Overview

This is a **documentation and configuration repository** for a production dual-GPU AI infrastructure running self-hosted open-source LLMs on NVIDIA Blackwell hardware (GB10/Grace Blackwell). All inference runs locally with no external API dependencies.

## Repository Structure

```
├── README.md                    # Main project overview
├── STATUS.md                    # Current deployment status (check this first)
├── CHANGELOG.md                 # Project timeline and changes
├── systems/                     # Per-system documentation
│   ├── pegasus/                 # GPT-OSS-120B deployment docs
│   └── stella/                  # Qwen3-Coder-30B-A3B deployment docs
├── docs/                        # Supporting documentation
│   ├── archive/                 # Historical documents and sessions
│   └── research/                # Future project proposals
├── vllm-gb10/                   # Self-contained vLLM GB10 project
│   ├── Dockerfile.gb10          # Custom Dockerfile for Blackwell
│   ├── SETUP.md                 # Complete setup guide
│   └── *.sh                     # Build and deployment scripts
└── scripts/                     # Utility scripts
```

## Production Systems

Both systems run as **docker-compose services** with `restart: unless-stopped` (auto-start on boot).

### Pegasus (Architect & Analyst)
- **Model**: OpenAI GPT-OSS-120B (117B params, MXFP4)
- **API**: http://pegasus.home.arpa:8000
- **Hardware**: ASUS Ascent GX10, 128GB GPU
- **Performance**: 34 tokens/sec, 131K context
- **Tool Calling**: OpenAI format (`--tool-call-parser openai`)
- **Service**: `~/vllm-service/docker-compose.yml`
- **Container**: `gpt-oss-120b`
- **Docs**: `systems/pegasus/`

### Stella (Fast Coder)
- **Model**: Qwen/Qwen3-Coder-30B-A3B-Instruct (30B MoE, 3B active)
- **API**: http://stella.home.arpa:8000
- **Hardware**: Lenovo ThinkStation PGX, 128GB unified ARM
- **Performance**: MoE-optimized, 204K context
- **Tool Calling**: Hermes format (`--tool-call-parser hermes`)
- **Service**: `~/vllm-service/docker-compose.yml`
- **Container**: `qwen-coder`
- **Docs**: `systems/stella/`

## Infrastructure

- **Model Storage**: NFS at `flashstore.home.arpa:/volume1/models` (mounted at `/mnt/models` on both hosts)
- **DNS**: Local `.home.arpa` domain (resolved by pfSense at 10.0.0.1)
- **Ports**: 8000 for vLLM API on each system
- **NFS fstab**: `flashstore.home.arpa:/volume1/models /mnt/models nfs4 rw,hard,intr,_netdev,noatime,nofail,... 0 0`

## Key Technical Details

### vLLM Deployments
- Pegasus uses community vLLM build (`eugr/spark-vllm-docker`) for GPT-OSS-120B MXFP4 support
- Stella uses NVIDIA official container (`nvcr.io/nvidia/vllm:25.12-py3`)
- Both require `--trust-remote-code` flag

### Tool Calling Formats
- **Pegasus (OpenAI)**: Returns `tool_calls` array with JSON, includes `reasoning_content`
- **Stella (Hermes)**: Returns XML-formatted tool calls in `content` field, requires custom parsing

### Common Docker Run Patterns
```bash
# Key flags used across deployments:
--privileged --gpus all
--ipc=host --network host
--gpu-memory-utilization 0.85-0.95
--trust-remote-code
--tool-call-parser [openai|hermes]
--enable-auto-tool-choice
```

## Working with This Repository

### Before Making Changes
1. Check `STATUS.md` for current system state
2. Review relevant system docs in `systems/[name]/`
3. Note which vLLM version/container each system uses

### Documentation Conventions
- System-specific docs go in `systems/[system-name]/`
- Each system has a `README.md` and `QUICKSTART.md`
- Archive historical content in `docs/archive/`
- Use `CHANGELOG.md` for significant changes

### Common Tasks

**Check system health:**
```bash
curl http://pegasus.home.arpa:8000/health
curl http://stella.home.arpa:8000/health
```

**View container logs (on respective hosts):**
```bash
docker logs -f gpt-oss-120b    # Pegasus
docker logs -f qwen-coder      # Stella
```

**Service management (on respective hosts):**
```bash
# Start/stop/restart (same on both systems)
cd ~/vllm-service && docker compose up -d      # Start
cd ~/vllm-service && docker compose down       # Stop
cd ~/vllm-service && docker compose restart    # Restart
```

**SSH access (from Mac):**
```bash
ssh pegasus-llm    # Pegasus (as llm-agent)
ssh stella-llm     # Stella (as llm-agent)
```

## Model IDs (for API calls)

vLLM uses full paths as model IDs:
- **Pegasus**: `/models/models--openai--gpt-oss-120b/snapshots/b5c939de8f754692c1647ca79fbf85e8c1e70f8a`
- **Stella**: `/models/models--Qwen--Qwen3-Coder-30B-A3B-Instruct/snapshots/b2cff646eb4bb1d68355c01b18ae02e7cf42d120`

Query available models: `curl http://<host>:8000/v1/models`

## OpenCode Integration

Models configured in `~/.config/opencode/opencode.json` using `@ai-sdk/openai-compatible` provider.

## Maintenance Commands

**Docker cleanup (free disk space):**
```bash
docker image prune -a -f       # Remove unused images
docker builder prune -a -f     # Clear build cache
docker container prune -f      # Remove stopped containers
docker system df               # Check disk usage
```

**NFS mount (if not in fstab):**
```bash
sudo mount -t nfs4 flashstore.home.arpa:/volume1/models /mnt/models \
  -o rw,hard,intr,_netdev,noatime,nofail,rsize=1048576,wsize=1048576
```

## Known Issues

- GB10 requires specific vLLM builds (standard NVIDIA containers may hang at "Using Marlin backend")
- GDS (GPU Direct Storage) not supported on these platforms
- Stella's Hermes tool calling format requires custom parsing (not direct OpenAI SDK compatible)
- Model loading from NFS takes longer than local disk (~5-6 min for Stella)

## External References

- vLLM Docs: https://docs.vllm.ai/
- Community GB10 vLLM: https://github.com/eugr/spark-vllm-docker
- Hermes Function Calling: https://github.com/NousResearch/Hermes-Function-Calling
- GPT-OSS vLLM Guide: https://docs.vllm.ai/projects/recipes/en/latest/OpenAI/GPT-OSS.html
