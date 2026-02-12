# Local Agentic Software Development Platform 

This repository contains documentation and configuration for deploying a **production dual-GPU AI infrastructure** with self-hosted Open Source LLMs on NVIDIA Blackwell hardware (GB10/Grace Blackwell).

All AI inference runs locally on your own GPU hardware, giving you full control, privacy, and no API costs.

## 🎯 Current Deployment

**Two production systems serving complementary roles:**

- **Pegasus** - [GPT-OSS-120B](systems/pegasus/) (117B params) - Architect & Analyst
- **Stella** - [Qwen3-8B](systems/stella/) (8.2B dense) - General-Purpose

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

### Stella - Qwen3-8B
**Status**: ✅ Operational | **API**: http://stella.home.arpa:8000

- **Model**: Qwen3-8B (8.2B dense, Q8_0 GGUF)
- **Performance**: 27.8 tok/s generation, 2,236 tok/s prompt
- **Context**: 32,768 tokens
- **Role**: General-purpose inference, fast responses
- **Features**: OpenAI-compatible API, thinking mode

📖 **[Documentation →](systems/stella/)** | 🚀 **[Quick Start →](systems/stella/QUICKSTART.md)**

## 📊 System Comparison

| Feature | Pegasus | Stella |
|---------|---------|--------|
| **Hardware** | ASUS Ascent GX10 | Lenovo ThinkStation PGX |
| **GPU Memory** | 128 GB | 128 GB (unified ARM) |
| **API Endpoint** | http://pegasus.home.arpa:8000 | http://stella.home.arpa:8000 |
| **Model** | OpenAI GPT-OSS-120B | Qwen3-8B |
| **Parameters** | 117B MoE | 8.2B dense |
| **Model Size** | 59 GiB (MXFP4 GGUF) | 8.1 GiB (Q8_0 GGUF) |
| **Model Storage** | NFS (flashstore) | NFS (flashstore) |
| **Quantization** | MXFP4 | Q8_0 |
| **Max Context** | 131,072 tokens | 32,768 tokens |
| **Speed** | 58.8 tok/s | 27.8 tok/s |
| **Engine** | llama.cpp (systemd) | llama.cpp (systemd) |
| **Reasoning Traces** | Yes (`reasoning_content`) | Thinking mode (Qwen3) |
| **OpenAI SDK Compatible** | Full | Full |
| **Specialization** | Architecture, analysis, code review | General-purpose, fast inference |

## 🔧 Tool Calling

Both systems support tool/function calling with different formats:

### Pegasus (OpenAI Format)
Returns structured JSON in the `tool_calls` array - fully compatible with OpenAI SDKs:
```json
{
  "tool_calls": [{
    "function": {
      "name": "get_weather",
      "arguments": "{\"location\": \"Tokyo\"}"
    }
  }],
  "reasoning_content": "User asks about weather, using get_weather tool."
}
```

### Stella (Hermes Format)
Returns XML-formatted tool calls in the `content` field - requires custom parsing:
```xml
<tool_call>
<function=get_weather>
<parameter=location>Tokyo</parameter>
</function>
</tool_call>
```

### Hermes Format Documentation
For implementing a Hermes parser, see the official NousResearch documentation:
- [Hermes Function Calling (GitHub)](https://github.com/NousResearch/Hermes-Function-Calling) - Reference implementation
- [Hermes Dataset & Format Spec](https://huggingface.co/datasets/NousResearch/hermes-function-calling-v1) - Format specification
- [Hermes 3 Technical Report](https://arxiv.org/pdf/2408.11857) - Detailed documentation
- [Parser Implementation (functioncall.py)](https://github.com/NousResearch/Hermes-Function-Calling/blob/main/functioncall.py) - Python parser example

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
       │  ASUS Ascent     │           │  Lenovo PGX      │
       │  GX10 (128GB)    │           │  GB10 (128GB)    │
       │                  │           │  Grace Blackwell │
       │  GPT-OSS-120B    │           │  Qwen3-8B        │
       │  117B params     │           │  8.2B dense      │
       │  58.8 tok/s      │           │  27.8 tok/s      │
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
│   └── stella/                 # Qwen3-8B deployment
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
- [Stella (Qwen3-8B)](systems/stella/) - General-purpose fast inference

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
- **Stella**: [systems/stella/QUICKSTART.md](systems/stella/QUICKSTART.md)

## Contributing

Contributions welcome! See [vllm-gb10/CONTRIBUTING.md](vllm-gb10/CONTRIBUTING.md).

## License

MIT License - see [LICENSE](LICENSE) for details.

Individual components may have their own licenses:
- vLLM: Apache 2.0
- Docker images: Based on official vLLM images
