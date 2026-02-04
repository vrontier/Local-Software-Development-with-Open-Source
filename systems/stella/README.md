# Stella - Qwen3-Coder-30B-A3B-Instruct Deployment

## Overview

Stella deploys **Qwen/Qwen3-Coder-30B-A3B-Instruct**, a coding-optimized MoE model designed for fast inference and code generation on NVIDIA GB10 Grace Blackwell hardware.

**Role**: Fast Code Generation & Interactive Development  
**Status**: ✅ Operational  
**API**: http://stella.home.arpa:8000

---

## Hardware

- **System**: Stella (Lenovo ThinkStation PGX)
- **GPU**: NVIDIA GB10 Grace Blackwell (SM 12.0)
- **Architecture**: ARM64 (aarch64)
- **GPU Memory**: 128 GiB unified memory
- **Storage**: Local NVMe (916GB, ~800GB available)
- **Model Storage**: NFS mount at `/mnt/models` (flashstore.home.arpa)

---

## Model Specifications

### Qwen/Qwen3-Coder-30B-A3B-Instruct

- **Architecture**: Qwen3MoeForCausalLM
- **Parameters**: 30B total, 3B active per token (MoE)
- **Size**: 57 GB on disk, 56.9GB loaded in GPU
- **Location**: `/mnt/models/models--Qwen--Qwen3-Coder-30B-A3B-Instruct/snapshots/b2cff646eb4bb1d68355c01b18ae02e7cf42d120`
- **Context Length**: 204,800 tokens (configured)
- **Precision**: BF16 (unquantized)
- **Languages**: Multilingual (60+ languages)
- **Specialization**: Code generation, software development
- **Release**: Alibaba Cloud, 2025

### MoE Architecture

- **Total Experts**: Multiple routing experts
- **Active Experts**: ~3B parameters per token
- **Efficiency**: 10x faster than dense 30B models
- **Quality**: Comparable to much larger models

---

## vLLM Configuration

### Docker Image

- **Image**: `nvcr.io/nvidia/vllm:25.12-py3`
- **Source**: NVIDIA Container Registry (requires authentication)
- **vLLM Version**: 0.11.1+9114fd76.nv25.12
- **CUDA**: 13.1 (forward compatible with driver 580.95.05)
- **Release**: December 2025

**Why This Image?**
- ✅ Official NVIDIA build optimized for GB10
- ✅ Better MoE support than 25.11 version
- ✅ Stable safetensors loading for large models
- ✅ Full tool calling support

---

## Deployment

### Location
- **Host**: stella.home.arpa (10.0.0.81)
- **Directory**: `~/vllm-service/`
- **Container Name**: `qwen-coder`
- **Port**: 8000

### Current Configuration (204K Context, NFS Storage)

**Updated (2026-02-04): Model now served from NFS with 204K context**

**docker-compose.yml** (`~/vllm-service/docker-compose.yml`):
```yaml
services:
  vllm:
    image: nvcr.io/nvidia/vllm:25.12-py3
    container_name: qwen-coder
    privileged: true
    ipc: host
    network_mode: host
    volumes:
      - /mnt/models:/models:ro
      - /home/llm-agent/vllm-service/logs:/workspace/logs:rw
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - CUDA_VISIBLE_DEVICES=0
    command: >
      vllm serve /models/models--Qwen--Qwen3-Coder-30B-A3B-Instruct/snapshots/b2cff646eb4bb1d68355c01b18ae02e7cf42d120
      --trust-remote-code
      --gpu-memory-utilization 0.93
      --max-model-len 204800
      --dtype auto
      --port 8000
      --host 0.0.0.0
      --tool-call-parser hermes
      --enable-auto-tool-choice
      --disable-sliding-window
    restart: unless-stopped
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

**Key Features**:
- `restart: unless-stopped`: Auto-restarts on boot and after crashes
- Model served directly from NFS (`/mnt/models`)
- 204,800 token context window
- `--tool-call-parser hermes`: Hermes-format function calling
- `--enable-auto-tool-choice`: Automatic tool selection

### Service Management

```bash
# Start service
cd ~/vllm-service && docker compose up -d

# Stop service
cd ~/vllm-service && docker compose down

# View logs
docker logs -f qwen-coder

# Restart service
cd ~/vllm-service && docker compose restart
```

### Prerequisites

NFS mount must be configured in `/etc/fstab`:
```
flashstore.home.arpa:/volume1/models /mnt/models nfs4 rw,hard,intr,_netdev,noatime,nofail,rsize=1048576,wsize=1048576 0 0
```

---

## Performance

### Current Stats (32K Context)

- **GPU Memory**: 56.9 GiB model + 42.46 GiB KV cache = ~100GB total
- **KV Cache Capacity**: 463,744 tokens
- **Max Concurrency**: 14.15x at full context
- **Loading Time**: ~5.4 minutes (first time)
- **Attention Backend**: FlashAttention (FLASH_ATTN)
- **Compilation**: torch.compile enabled (56s compile time)

### Memory Breakdown

| Component | Size |
|-----------|------|
| Model Weights | 56.9 GB |
| KV Cache (32K context) | 42.46 GB |
| Available for batching | ~28 GB |
| **Total Used** | ~100 GB / 128 GB |

### Expected Performance (200K Context)

- **GPU Memory**: Model (57GB) + KV cache (~65-70GB) = ~125GB total
- **Available Memory**: Very limited for batching
- **Concurrency**: Likely 1-2 requests max
- **Use Case**: Single-user, long-context analysis

---

## API Usage

### Health Check

```bash
curl http://stella.home.arpa:8000/health
```

### List Models

```bash
curl http://stella.home.arpa:8000/v1/models | python3 -m json.tool
```

### Chat Completion

```bash
curl http://stella.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-Coder-30B-A3B-Instruct",
    "messages": [
      {"role": "user", "content": "Write a Python function to calculate fibonacci numbers"}
    ],
    "max_tokens": 500,
    "temperature": 0.7
  }' | python3 -m json.tool
```

### Code Completion

```bash
curl http://stella.home.arpa:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-Coder-30B-A3B-Instruct",
    "prompt": "def fibonacci(n):",
    "max_tokens": 200,
    "temperature": 0.2
  }' | python3 -m json.tool
```

### Tool/Function Calling

**Research in Progress** - Format being tested:

```bash
curl http://stella.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-Coder-30B-A3B-Instruct",
    "messages": [
      {"role": "user", "content": "What is the weather in San Francisco?"}
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get current weather for a location",
          "parameters": {
            "type": "object",
            "properties": {
              "location": {"type": "string", "description": "City name"}
            },
            "required": ["location"]
          }
        }
      }
    ],
    "tool_choice": "auto"
  }' | python3 -m json.tool
```

**Note**: Qwen models use Hermes function calling format. Testing optimal `tool_choice` values.

---

## Deployment Commands

### Start Service

```bash
# On Stella
cd ~/vllm-service
docker compose up -d

# Monitor startup
docker logs -f qwen-coder
```

### Stop Service

```bash
cd ~/vllm-service
docker compose down
```

### Restart Service

```bash
cd ~/vllm-service
docker compose restart
```

### Check Status

```bash
# Container status
docker ps | grep qwen

# GPU utilization
nvidia-smi

# API health
curl http://localhost:8000/health
```

---

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker logs qwen-coder

# Common issues:
# - Model downloading: Wait 5-10 minutes
# - Out of memory: Reduce --gpu-memory-utilization to 0.85
# - CUDA not found: Check nvidia-smi
```

### API Not Responding

```bash
# Check if server finished loading
docker logs qwen-coder | grep "Application startup complete"

# For 200K context, loading takes longer
# Watch for "Model loading took" message
```

### Out of Memory (OOM)

If running 200K context causes OOM:

1. Reduce context: Try 131072 (128K) instead
2. Lower GPU utilization: --gpu-memory-utilization 0.90
3. Enable sliding window: Remove --disable-sliding-window

---

## Comparison to Pegasus

| Feature | Pegasus (GPT-OSS-120B) | Stella (Qwen3-Coder-30B) |
|---------|------------------------|--------------------------|
| **Parameters** | 117B | 30B (3B active MoE) |
| **Model Size** | 130GB | 57GB |
| **Context** | 131K tokens | 32K (testing 200K+) |
| **Speed** | 34 tok/s | TBD |
| **Memory Usage** | 66GB model + 37GB cache | 57GB model + 43GB cache |
| **Quantization** | MXFP4 | BF16 (unquantized) |
| **Use Case** | Architecture & Analysis | Code Generation |
| **Tool Calling** | OpenAI format | Hermes format |
| **Specialization** | General reasoning | Software development |

---

## Technical Notes

### Why vLLM 0.11.1 Works (vs 0.11.0)

**Issue with 0.11.0**:
- MoE models would load but API server never started
- Hung during torch.compile phase
- Even with `--enforce-eager`, initialization failed

**Fixed in 0.11.1**:
- Better MoE model support
- Improved safetensors loading (16 shards loaded successfully)
- Stable torch.compile for Qwen3MoeForCausalLM
- Application startup completes properly

### Tool Calling Parser

- **Parser**: `hermes` (specified with `--tool-call-parser hermes`)
- **Format**: Hermes function calling format (not OpenAI)
- **Auto-choice**: Enabled with `--enable-auto-tool-choice`
- **Research needed**: Optimal tool_choice values and response format

### Loading Performance

**First Load** (model download + load):
```
- Safetensors shards: 16 total
- Download time: ~3-5 minutes (18GB)
- Load time: 5:14 (314 seconds)
- torch.compile: 56 seconds
- Total: ~6.5 minutes
```

**Subsequent Loads** (cached):
```
- Download: 0 seconds (cached)
- Load time: ~5 minutes
- torch.compile: ~1 minute (cached)
- Total: ~6 minutes
```

---

## Future Improvements

### Planned

1. **Extended Context Testing**: Validate 200K token configuration
2. **Performance Benchmarking**: Compare speed vs Pegasus
3. **Tool Calling Documentation**: Document Hermes format examples
4. **Model Migration**: Move cache to flashstore NFS

### Potential Optimizations

1. **Quantization**: Consider FP8 or AWQ for 2x memory savings
2. **Multi-GPU**: Test tensor parallelism (if needed)
3. **Batch Optimization**: Tune for concurrent requests
4. **Continuous Batching**: Enable for better throughput

---

## Session History

### 2026-01-25: Successful Deployment

**Timeline**:
- 22:45 - Started with IBM Granite 4.0 H Small (failed - compatibility)
- 23:01 - Switched to Qwen3-Coder-30B-A3B-Instruct
- 23:08 - Upgraded to vLLM 25.12 (0.11.1) after 25.11 (0.11.0) failed
- 23:25 - Model started loading (16 safetensors shards)
- 23:31 - Model fully loaded, torch.compile completed
- 23:32 - API server started successfully
- 23:33 - First successful generation

**Key Learnings**:
1. NVIDIA official images work perfectly (vs community builds)
2. vLLM 0.11.1 required for MoE stability on ARM GB10
3. Hermes parser needed for Qwen tool calling
4. Safetensors loading works reliably with progress display

### Previous Attempts (Failed)

- **Granite 4.0 H Small**: Loaded but API never started (hybrid MoE issue)
- **GLM-4.7-Flash-NVFP4**: Library path issues, transformers version conflicts
- **Custom vLLM builds**: Complex, slow, unreliable

---

## Related Documentation

- **[Quickstart Guide](QUICKSTART.md)** - Quick reference commands
- **[Status](../../STATUS.md)** - Current system status
- **[Pegasus Comparison](../pegasus/)** - Compare with GPT-OSS-120B

---

## References

- **Model**: https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct
- **vLLM**: https://github.com/vllm-project/vllm
- **NVIDIA Container**: nvcr.io/nvidia/vllm:25.12-py3
- **Hermes Format**: https://github.com/NousResearch/Hermes-Function-Calling

---

**Status**: ✅ Operational - Ready for testing and optimization

For current deployment status, see [../../STATUS.md](../../STATUS.md)
