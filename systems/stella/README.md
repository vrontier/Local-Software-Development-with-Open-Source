# Stella - Meta Llama 4 Scout Deployment

## Overview

Stella deploys **Meta Llama 4 Scout 17B-16E**, a 109B-parameter mixture-of-experts model with 17B active parameters, running via **llama.cpp** (systemd) on NVIDIA GB10 Grace Blackwell hardware.

**Role**: General-Purpose Inference, Code Generation, Agents
**Status**: ✅ Operational
**API**: http://stella.home.arpa:8000

---

## Hardware

- **System**: Stella (Lenovo ThinkStation PGX)
- **GPU**: NVIDIA GB10 Grace Blackwell (SM 12.1)
- **Architecture**: ARM64 (aarch64)
- **GPU Memory**: 128 GiB unified memory
- **Storage**: Local NVMe (916GB, ~800GB available)
- **Model Storage**: NFS mount at `/mnt/models` (flashstore.home.arpa)

---

## Model Specifications

### Meta Llama 4 Scout 17B-16E (Q6_K GGUF)

- **Architecture**: Transformer MoE
- **Parameters**: 109B total / 17B active per token
- **Experts**: 16 total, 1 active per token
- **Size**: 83 GiB (Q6_K GGUF, 2 shards)
- **Location**: `/mnt/models/Llama-4-Scout-17B-16E-Instruct-GGUF/`
- **Context Length**: 32,768 tokens (model supports up to 10M natively)
- **Quantization**: Q6_K (Unsloth "Excellent" tier)
- **Engine**: llama.cpp (build b8006, systemd service)
- **Performance**: 14.5 tok/s generation, ~62 tok/s prompt processing
- **Features**: Tool calling, code generation, multilingual, OpenAI-compatible API
- **License**: Llama 4 Community License

---

## Deployment

### Service Configuration

**systemd unit** (`/etc/systemd/system/llama-server.service`):
```ini
[Unit]
Description=llama-server Llama-4-Scout-17B-16E inference
After=network-online.target mnt-models.mount
Requires=mnt-models.mount
Wants=network-online.target

[Service]
Type=simple
User=llm-agent
Group=llm-agent
WorkingDirectory=/home/llm-agent/llama.cpp
ExecStart=/home/llm-agent/llama.cpp/build/bin/llama-server \
    -m /mnt/models/Llama-4-Scout-17B-16E-Instruct-GGUF/Llama-4-Scout-17B-16E-Instruct-Q6_K-00001-of-00002.gguf \
    -ngl 999 \
    --no-mmap \
    -fa on \
    -c 32768 \
    --jinja \
    --host 0.0.0.0 \
    --port 8000
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

### Key Flags

| Flag | Purpose |
|------|---------|
| `-ngl 999` | All layers on GPU |
| `--no-mmap` | Critical on GB10 — avoids slow mmap |
| `-fa on` | Flash attention |
| `-c 32768` | 32K context window |
| `--jinja` | Llama 4 chat template |
| `--host 0.0.0.0` | Listen on all interfaces |
| `--port 8000` | API port |

**Note**: llama.cpp auto-discovers shard 2 from the shard 1 path.

### Service Management

```bash
sudo systemctl start llama-server     # Start
sudo systemctl stop llama-server      # Stop
sudo systemctl restart llama-server   # Restart
sudo systemctl status llama-server    # Status
journalctl -u llama-server -f         # Logs
```

### Prerequisites

NFS mount must be configured in `/etc/fstab`:
```
flashstore.home.arpa:/volume1/models /mnt/models nfs4 rw,hard,intr,_netdev,noatime,nofail,rsize=1048576,wsize=1048576 0 0
```

---

## Performance

### Current Stats (32K Context)

| Metric | Value |
|--------|-------|
| **Generation Speed** | 14.5 tok/s |
| **Prompt Processing** | ~62 tok/s |
| **Model Size** | 83 GiB (Q6_K, 2 shards) |
| **Active Parameters** | 17B per token (of 109B total) |
| **Context Window** | 32,768 tokens |
| **GPU Memory** | ~83.5 GB model + ~44 GB available for KV cache |

### Performance Context

Llama 4 Scout uses MoE routing — only 17B of 109B total parameters are active per token:

- **Generation** (14.5 tok/s): Similar to dense 14B models, but drawing from 109B total knowledge
- **Prompt processing** (~62 tok/s): First-request cold cache; should improve on subsequent requests
- **Quality**: Significantly more capable than smaller dense models — 109B total parameters

### Comparison to Other Models Tested on GB10

| Model | Params (active) | Size | Gen Speed |
|-------|-----------------|------|-----------|
| Qwen3-8B (dense) | 8B | 8.1 GB Q8_0 | 27.8 tok/s |
| Qwen2.5-Coder-7B (dense) | 7B | 7.6 GB Q8_0 | 29.4 tok/s |
| **Llama 4 Scout** (MoE) | **17B of 109B** | **83 GB Q6_K** | **14.5 tok/s** |
| Granite 4.0 H-Small (hybrid MoE) | 9B of 32B | 34.3 GB Q8_0 | 20.5 tok/s |
| Qwen3-14B (dense) | 14B | 14.6 GB Q8_0 | 14.7 tok/s |
| Qwen3-32B (dense) | 32B | 32.4 GB Q8_0 | 6.5 tok/s |

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
    "model": "Llama-4-Scout-17B-16E-Instruct-Q6_K-00001-of-00002.gguf",
    "messages": [
      {"role": "user", "content": "Write a Python function that implements binary search."}
    ],
    "max_tokens": 500,
    "temperature": 0.7
  }' | python3 -m json.tool
```

### Tool/Function Calling

```bash
curl http://stella.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Llama-4-Scout-17B-16E-Instruct-Q6_K-00001-of-00002.gguf",
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

---

## Comparison to Pegasus

| Feature | Pegasus (GPT-OSS-120B) | Stella (Llama 4 Scout) |
|---------|------------------------|------------------------|
| **Parameters** | 117B MoE | 109B total / 17B active MoE |
| **Architecture** | Transformer MoE | Transformer MoE |
| **Model Size** | 59 GiB (MXFP4) | 83 GiB (Q6_K) |
| **Context** | 131K tokens | 32K tokens |
| **Generation** | 58.8 tok/s | 14.5 tok/s |
| **Quantization** | MXFP4 | Q6_K |
| **Use Case** | Architecture & Analysis | General-purpose, code, agents |
| **Tool Calling** | ✅ OpenAI format | ✅ OpenAI format |
| **Provider** | OpenAI | Meta |

---

## Model History

| Date | Model | Reason |
|------|-------|--------|
| 2026-02-13 | **Llama 4 Scout 17B-16E** (109B MoE) | Most capable model, 109B knowledge base |
| 2026-02-13 | Granite 4.0 H-Small (32B MoE) | Tested — hybrid Mamba prompt processing too slow |
| 2026-02-13 | Qwen2.5-Coder-7B (dense) | Tested — fast but limited capability |
| 2026-02-12 | Qwen3-8B (8.2B dense) | Speed optimization (27.8 tok/s) |
| 2026-02-11 | Qwen3-14B (14.2B dense) | Quality upgrade, llama.cpp migration |
| 2026-01-25 | Qwen3-Coder-30B-A3B (30B MoE) | Code specialization |

---

## Related Documentation

- **[Quickstart Guide](QUICKSTART.md)** - Quick reference commands
- **[Status](../../STATUS.md)** - Current system status
- **[Pegasus](../pegasus/)** - Compare with GPT-OSS-120B

## References

- **Model**: https://huggingface.co/meta-llama/Llama-4-Scout-17B-16E
- **GGUF**: https://huggingface.co/unsloth/Llama-4-Scout-17B-16E-Instruct-GGUF
- **Llama 4 Announcement**: https://ai.meta.com/blog/llama-4-multimodal-intelligence/

---

**Status**: ✅ Operational

For current deployment status, see [../../STATUS.md](../../STATUS.md)
