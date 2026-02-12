# System Status

**Last Updated**: 2026-02-12

---

## 🎯 Production Systems

Models are stored centrally on NFS. Both systems run llama.cpp via systemd.

### Pegasus - GPT-OSS-120B
- **Status**: ✅ Operational
- **API**: http://pegasus.home.arpa:8000
- **Model**: OpenAI GPT-OSS-120B (MXFP4 MoE, 117B params, 59 GiB GGUF)
- **Model Location**: NFS (`/mnt/models/gpt-oss-120b-GGUF/`)
- **Engine**: llama.cpp (build b7999+, CUDA 13.0, SM 12.1)
- **Service**: systemd (`llama-server.service`)
- **Performance**: 58.8 tok/s generation, 1,809 tok/s prompt processing (was 34 tok/s with vLLM)
- **Context**: 131,072 tokens
- **Features**: OpenAI-compatible API, reasoning traces, Jinja chat template
- **Role**: Architect & Analyst - Long-context analysis, architecture design
- **Documentation**: [systems/pegasus/](systems/pegasus/)

### Stella - Qwen3-8B
- **Status**: ✅ Operational
- **API**: http://stella.home.arpa:8000
- **Model**: Qwen3-8B (8.2B dense, Q8_0, 8.1 GiB)
- **Model Location**: NFS (`/mnt/models/Qwen3-8B-GGUF/Qwen_Qwen3-8B-Q8_0.gguf`)
- **Engine**: llama.cpp (build b7999+, CUDA 13.0, SM 12.1)
- **Service**: systemd (`llama-server.service`)
- **Performance**: 27.8 tok/s generation, 2,236 tok/s prompt processing
- **Context**: 32,768 tokens
- **Features**: OpenAI-compatible API, thinking mode
- **Role**: General-purpose inference, fast responses
- **Documentation**: [systems/stella/](systems/stella/)

---

## 📊 System Comparison

| Feature | Pegasus | Stella |
|---------|---------|--------|
| **Hardware** | ASUS Ascent GX10 | Lenovo ThinkStation PGX |
| **GPU Memory** | 128GB | 128GB (unified ARM) |
| **Model** | GPT-OSS-120B | Qwen3-8B |
| **Size** | 117B params, 59 GiB (GGUF) | 8.2B params, 8.1 GiB (Q8_0) |
| **Context** | 131K tokens | 32K tokens |
| **Speed** | 58.8 tok/s | 27.8 tok/s |
| **Quantization** | MXFP4 (GGUF) | Q8_0 (GGUF) |
| **Engine** | llama.cpp (systemd) | llama.cpp (systemd) |
| **Model Storage** | NFS (flashstore) | NFS (flashstore) |
| **Use Case** | Deep analysis | General-purpose, fast responses |
| **Tool Calling** | ✅ Enabled (OpenAI) | OpenAI-compatible API |

---

## ⚠️ Inactive Systems

### Venus - RTX PRO 6000 Blackwell
- **Status**: ❌ Inactive
- **Last Activity**: 2026-01-22 (NVIDIA NIM download incomplete)
- **Hardware**: 98GB GPU memory
- **Current State**: System offline, no active deployment
- **Future**: To be determined
- **Documentation**: [docs/archive/venus/](docs/archive/venus/)

---

## 🗄️ Infrastructure

### Model Storage (NFS)
- **NFS Server**: flashstore.home.arpa:/volume1/models
- **Capacity**: 9.1 TB (RAID5, ASUSTOR FS6712X)
- **Network**: 10 GbE
- **Mount Point**: `/mnt/models` (on both Pegasus and Stella)
- **fstab entry**: `flashstore.home.arpa:/volume1/models /mnt/models nfs4 rw,hard,intr,_netdev,noatime,nofail,... 0 0`
- **Contents**:
  - `models--openai--gpt-oss-120b`: 130 GB (Pegasus)
  - `Qwen3-8B-GGUF/`: 8.5 GB (Stella)
  - `models--Qwen--Qwen3-Coder-30B-A3B-Instruct`: 57 GB (available)
  - `models--Qwen--Qwen3-32B-AWQ`: 19 GB (available)
  - `Qwen3-32B-GGUF/`: 33 GB (available)
  - `Qwen3-8B-GGUF/`: 8.5 GB (available)

### Service Management

**Both systems** (llama.cpp, systemd):
- **Service**: `llama-server.service`
- **Start**: `sudo systemctl start llama-server`
- **Stop**: `sudo systemctl stop llama-server`
- **Restart**: `sudo systemctl restart llama-server`
- **Status**: `sudo systemctl status llama-server`
- **Logs**: `journalctl -u llama-server -f`

### Network Configuration
- **DNS**: Local `.home.arpa` domain (resolved by pfSense at 10.0.0.1)
- **Firewall**: UFW on all systems
- **Ports**:
  - Pegasus: 8000 (GPT-OSS-120B API, vLLM)
  - Stella: 8000 (Qwen3-8B API, llama-server)
  - Venus: 8001 (reserved, inactive)

---

## 📈 Recent Activity

### 2026-02-12
- ✅ Stella: Switched model from Qwen3-14B to Qwen3-8B (Q8_0, 27.8 tok/s — nearly 2x faster)

### 2026-02-11
- ✅ Both systems: Switched from vLLM to llama.cpp (native CUDA build, SM 12.1)
- ✅ Both systems: Configured as systemd services (`llama-server.service`) with NFS dependency
- ✅ Both systems: Docker images removed, no more container overhead
- ✅ Pegasus: GPT-OSS-120B now at 58.8 tok/s (was 34 tok/s with vLLM — **73% faster**)
- ✅ Stella: Switched model from Qwen3-Coder-30B-A3B (MoE) to Qwen3-14B (dense, Q8_0, 14.7 tok/s)
- ✅ Benchmarked Qwen3 dense family on GB10: 8B (27.8 tok/s), 14B (14.7 tok/s), 32B (6.5 tok/s)
- ✅ Research: [Qwen3 Dense Benchmark Results](docs/research/BENCHMARK_Qwen3_Dense_GB10_llamacpp.md)

### 2026-02-04
- ✅ Both systems: Configured vLLM as docker-compose service with auto-restart
- ✅ Both systems: Models migrated to NFS storage (flashstore)
- ✅ Both systems: Local model caches cleaned up (~470GB freed on Stella, ~60GB on Pegasus)
- ✅ Stella: Extended context confirmed at 204,800 tokens
- ✅ Documentation: Updated for service-based deployment

### 2026-01-25
- ✅ Pegasus: Added OpenAI-compatible tool calling
- ✅ Documentation: Reorganized structure (systems/, docs/, archive/)
- ✅ Stella: Successfully deployed Qwen/Qwen3-Coder-30B-A3B-Instruct with vLLM 0.11.1

### 2026-01-22
- ✅ Pegasus: GPT-OSS-120B deployed successfully
- ⚠️ Venus: Switched from vLLM to NVIDIA NIM (incomplete)
- ✅ Stella: vLLM custom build completed (67GB image)

---

## 🔍 Quick Health Checks

```bash
# Check Pegasus
curl http://pegasus.home.arpa:8000/health

# Check Stella (when deployed)
curl http://stella.home.arpa:8000/health

# Check all systems from Mac
./scripts/check-all-systems.sh
```

---

## 📚 Documentation

- **System Documentation**: [systems/](systems/)
  - [Pegasus (GPT-OSS-120B)](systems/pegasus/)
  - [Stella (Qwen3-8B)](systems/stella/)
- **Deployment Guides**: [docs/deployment/](docs/deployment/)
- **Network Setup**: [docs/network/](docs/network/)
- **Archives**: [docs/archive/](docs/archive/)
- **Research**: [docs/research/](docs/research/)
- **vLLM GB10 Project**: [vllm-gb10/](vllm-gb10/)

---

## 🎯 Current Focus

**Completed**: Full llama.cpp migration
- ✅ Both systems: llama.cpp systemd services with NFS dependency
- ✅ Pegasus: GPT-OSS-120B at 58.8 tok/s (73% faster than vLLM)
- ✅ Stella: Qwen3-8B Q8_0 at 27.8 tok/s
- ✅ Docker removed from both systems — no container overhead
- ✅ Qwen3 dense family benchmarked on GB10 (8B/14B/32B)

**Next Steps**:
1. Document tool calling examples for both systems
2. Add monitoring (Prometheus/Grafana)
3. Create health check automation scripts

---

**For detailed system information, see respective documentation in [systems/](systems/)**
