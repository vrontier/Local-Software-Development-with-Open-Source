# System Status

**Last Updated**: 2026-02-04

---

## 🎯 Production Systems

Both systems run vLLM as a **docker-compose service** with `restart: unless-stopped`, automatically starting on boot and restarting after crashes. Models are stored centrally on NFS.

### Pegasus - GPT-OSS-120B
- **Status**: ✅ Operational
- **API**: http://pegasus.home.arpa:8000
- **Model**: OpenAI GPT-OSS-120B (MXFP4, 117B params, 130GB)
- **Model Location**: NFS (`/mnt/models/models--openai--gpt-oss-120b`)
- **vLLM**: Community build (`vllm-gb10:latest`, v0.14.0rc2.dev259)
- **Service**: docker-compose (`~/vllm-service/docker-compose.yml`)
- **Performance**: 34 tokens/sec sustained
- **Context**: 131,072 tokens
- **Features**: Tool calling enabled (OpenAI-compatible)
- **Role**: Architect & Analyst - Long-context analysis, architecture design
- **Documentation**: [systems/pegasus/](systems/pegasus/)

### Stella - Qwen3-Coder-30B-A3B
- **Status**: ✅ Operational
- **API**: http://stella.home.arpa:8000
- **Model**: Qwen/Qwen3-Coder-30B-A3B-Instruct (30B MoE, 3B active, 57GB)
- **Model Location**: NFS (`/mnt/models/models--Qwen--Qwen3-Coder-30B-A3B-Instruct`)
- **vLLM**: NVIDIA Container (`nvcr.io/nvidia/vllm:25.12-py3`, v0.11.1)
- **Service**: docker-compose (`~/vllm-service/docker-compose.yml`)
- **Performance**: MoE optimized for fast inference
- **Context**: 204,800 tokens
- **Features**: Tool calling enabled (Hermes parser), coding-optimized
- **Role**: Fast Inference - Code generation, interactive development
- **Documentation**: [systems/stella/](systems/stella/)

---

## 📊 System Comparison

| Feature | Pegasus | Stella |
|---------|---------|--------|
| **Hardware** | ASUS Ascent GX10 | Lenovo ThinkStation PGX |
| **GPU Memory** | 128GB | 128GB (unified ARM) |
| **Model** | GPT-OSS-120B | Qwen3-Coder-30B-A3B |
| **Size** | 117B params, 130GB | 30B params (3B active), 57GB |
| **Context** | 131K tokens | 204K tokens |
| **Speed** | 34 tok/s | TBD (MoE optimized) |
| **Quantization** | MXFP4 | BF16 (unquantized) |
| **Model Storage** | NFS (flashstore) | NFS (flashstore) |
| **Service** | docker-compose | docker-compose |
| **Use Case** | Deep analysis | Code generation |
| **Tool Calling** | ✅ Enabled (OpenAI) | ✅ Enabled (Hermes) |

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
  - `models--Qwen--Qwen3-Coder-30B-A3B-Instruct`: 57 GB (Stella)

### Service Management
- **Deployment**: docker-compose with `restart: unless-stopped`
- **Config Location**: `~/vllm-service/docker-compose.yml` on each host
- **Start**: `cd ~/vllm-service && docker compose up -d`
- **Stop**: `cd ~/vllm-service && docker compose down`
- **Logs**: `docker logs -f <container-name>`

### Network Configuration
- **DNS**: Local `.home.arpa` domain (resolved by pfSense at 10.0.0.1)
- **Firewall**: UFW on all systems
- **Ports**:
  - Pegasus: 8000 (GPT-OSS-120B API)
  - Stella: 8000 (Qwen3-Coder API)
  - Venus: 8001 (reserved, inactive)

---

## 📈 Recent Activity

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
  - [Stella (Qwen3-Coder-30B-A3B)](systems/stella/)
- **Deployment Guides**: [docs/deployment/](docs/deployment/)
- **Network Setup**: [docs/network/](docs/network/)
- **Archives**: [docs/archive/](docs/archive/)
- **Research**: [docs/research/](docs/research/)
- **vLLM GB10 Project**: [vllm-gb10/](vllm-gb10/)

---

## 🎯 Current Focus

**Completed**: Production service deployment
- ✅ Both systems running as docker-compose services
- ✅ Models centralized on NFS storage
- ✅ Auto-restart on boot/crash configured
- ✅ Extended context (204K) working on Stella

**Next Steps**:
1. Benchmark Stella performance (tokens/sec)
2. Document tool calling examples for both formats
3. Add monitoring (Prometheus/Grafana)
4. Create health check automation scripts

---

**For detailed system information, see respective documentation in [systems/](systems/)**
