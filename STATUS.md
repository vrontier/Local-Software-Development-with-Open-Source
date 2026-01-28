# System Status

**Last Updated**: 2026-01-25

---

## 🎯 Production Systems

### Pegasus - GPT-OSS-120B
- **Status**: ✅ Operational
- **API**: http://pegasus.home.arpa:8000
- **Model**: OpenAI GPT-OSS-120B (MXFP4, 117B params, 130GB)
- **vLLM**: Community build (eugr/spark-vllm-docker)
- **Performance**: 34 tokens/sec sustained
- **Context**: 131,072 tokens
- **Features**: Tool calling enabled (OpenAI-compatible)
- **Role**: Architect & Analyst - Long-context analysis, architecture design
- **Documentation**: [systems/pegasus/](systems/pegasus/)

### Stella - Qwen3-Coder-30B-A3B
- **Status**: ✅ Operational
- **API**: http://stella.home.arpa:8000
- **Model**: Qwen/Qwen3-Coder-30B-A3B-Instruct (30B MoE, 3B active, 18GB)
- **vLLM**: NVIDIA Container v0.11.1 (nvcr.io/nvidia/vllm:25.12-py3)
- **Performance**: TBD (MoE optimized for fast inference)
- **Context**: 32,768 tokens (testing 200K+ extended context)
- **Features**: Tool calling enabled (Hermes parser), coding-optimized
- **Role**: Fast Inference - Code generation, interactive development
- **Documentation**: [systems/stella/](systems/stella/)

---

## 📊 System Comparison

| Feature | Pegasus | Stella |
|---------|---------|--------|
| **Hardware** | ASUS Ascend GB10 | ASUS Ascent GX10 (Grace Blackwell) |
| **GPU Memory** | 128GB | 128GB (unified ARM) |
| **Model** | GPT-OSS-120B | Qwen3-Coder-30B-A3B |
| **Size** | 117B params, 130GB | 30B params (3B active), 18GB |
| **Context** | 131K tokens | 32K tokens (testing 200K+) |
| **Speed** | 34 tok/s | TBD (MoE optimized) |
| **Quantization** | MXFP4 | BF16 (unquantized) |
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

### Model Storage
- **NFS Server**: flashstore.home.arpa:/volume1/models
- **Capacity**: 9.1 TB (RAID5, ASUSTOR FS6712X)
- **Network**: 10 GbE
- **Mount Point**: /mnt/models (on Pegasus)
- **Contents**:
  - GPT-OSS-120B: 130.53 GB
  - GLM-4.7-Flash-NVFP4: 20.4 GB (downloading)

### Network Configuration
- **DNS**: Local `.home.arpa` domain
- **Firewall**: UFW on all systems
- **Ports**:
  - Pegasus: 8000 (GPT-OSS-120B API)
  - Stella: 8000 (GLM-4.7-Flash API)
  - Venus: 8001 (reserved, inactive)

---

## 📈 Recent Activity

### 2026-01-25
- ✅ Pegasus: Added OpenAI-compatible tool calling
- ✅ Documentation: Reorganized structure (systems/, docs/, archive/)
- ✅ Stella: Successfully deployed Qwen/Qwen3-Coder-30B-A3B-Instruct with vLLM 0.11.1
- 🔄 Stella: Testing extended 200K+ context configuration

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

**Active Work**: Optimizing Stella for extended context (200K+ tokens)
- Test 204,800 token context configuration
- Benchmark performance vs Pegasus
- Document tool calling format/usage
- Performance testing and optimization

**Next Steps**:
1. Finalize extended context settings
2. Create performance comparison benchmarks
3. Document tool calling examples
4. Move cached models to flashstore NFS

---

**For detailed system information, see respective documentation in [systems/](systems/)**
