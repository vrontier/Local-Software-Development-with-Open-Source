# Pegasus GPT-OSS-120B Deployment

## Overview
Successfully deployed OpenAI's GPT-OSS-120B model on Pegasus (ASUS Ascend GB10) using community-optimized vLLM for Blackwell architecture. This model serves as the **Architect & Analyst** role in our local software development workflow.

## Hardware
- **System**: Pegasus (ASUS Ascend)
- **GPU**: NVIDIA GB10 (Blackwell architecture, SM12.1)
- **GPU Memory**: 128 GiB
- **Model Storage**: NFS share at `flashstore.home.arpa:/volume1/models`

## Deployment Details

### Model Specifications
- **Model**: OpenAI GPT-OSS-120B MXFP4 quantized
- **Size**: 130.53 GiB (17 safetensor files)
- **Context Window**: 131,072 tokens (16x default)
- **Quantization**: MXFP4 (4-bit mixed-precision floating point)
- **Location**: `/mnt/models/models--openai--gpt-oss-120b/snapshots/b5c939de8f754692c1647ca79fbf85e8c1e70f8a`

### Docker Container
- **Image**: `vllm-gb10:latest` (community-built from https://github.com/eugr/spark-vllm-docker)
- **Container Name**: `gpt-oss-120b`
- **Port**: 8000
- **Base Image**: CUDA 13.1.0 on Ubuntu 24.04
- **vLLM Version**: 0.14.0rc2.dev259

### Build Command
```bash
cd ~/spark-vllm-docker
./build-and-copy.sh --use-wheels nightly -t vllm-gb10
```

### Run Command

**Updated (2026-01-25): Added OpenAI-compatible tool calling support**

```bash
docker run -d --name gpt-oss-120b \
  --privileged --gpus all \
  --ipc=host --network host \
  -v /mnt/models:/models:ro \
  vllm-gb10 \
  vllm serve /models/models--openai--gpt-oss-120b/snapshots/b5c939de8f754692c1647ca79fbf85e8c1e70f8a \
    --trust-remote-code \
    --gpu-memory-utilization 0.90 \
    --max-model-len 131072 \
    --port 8000 \
    --host 0.0.0.0 \
    --load-format fastsafetensors \
    --tool-call-parser openai \
    --enable-auto-tool-choice
```

**New Parameters:**
- `--tool-call-parser openai`: Enables OpenAI-compatible function calling format
- `--enable-auto-tool-choice`: Automatically selects tools when appropriate

**Requirements:**
- vLLM >= 0.10.2 (required for `--tool-call-parser openai`)
- Current vLLM version: 0.14.0rc2.dev259 ✅

**Sources:**
- https://docs.vllm.ai/projects/recipes/en/latest/OpenAI/GPT-OSS.html
- https://cookbook.openai.com/articles/gpt-oss/run-vllm

## Performance Benchmarks

### Throughput Tests
| Test Scenario | Tokens Generated | Time (seconds) | Tokens/sec |
|--------------|------------------|----------------|------------|
| 200-word story | 300 | 9.287 | 32.3 |
| 400-word story | 600 | 17.495 | 34.3 |
| 2000-word story | 3000 | 87.77 | **34.2** |

### Key Performance Characteristics
- **Consistent Throughput**: ~34 tokens/second maintained across all test sizes
- **Linear Scaling**: 2x tokens = ~2x time (excellent efficiency)
- **Model Loading**: 85 seconds using fastsafetensors (70.31s for weights)
- **Initialization**: ~2 minutes total from container start to API ready

### Memory Usage
- **Model Size**: 65.97 GiB GPU memory
- **KV Cache**: 37.3 GiB available
- **Total Capacity**: 543,248 tokens in KV cache
- **Concurrency**: 8.15x for 131K token requests
- **GPU Utilization**: 90% configured, ~109 GiB used in production

## Technical Resolution: The Marlin Backend Hang

### Problem
Standard NVIDIA vLLM containers hang at "Using Marlin backend" on GB10 (Blackwell) systems when loading MXFP4 quantized models.

### Root Cause
- FlashInfer MXFP4 optimized path was disabled in vLLM ~1 month ago due to bugs
- Fallback to Marlin kernel lacks proper SM12X (GB10) architecture support
- NVIDIA's official vLLM containers don't detect/handle GB10 correctly

### Solution
Used community-maintained container from https://github.com/eugr/spark-vllm-docker:
- Builds vLLM from nightly wheels with GB10-specific patches
- Includes fastsafetensors patch for faster model loading
- Proper CUDA 13.0/13.1 support for Blackwell
- Triton 3.5.1 with GB10 compatibility

### References
- NVIDIA Forum Discussion: https://forums.developer.nvidia.com/t/run-vllm-in-spark/348862?page=6
- Key insight from forum user `eugr` and `christopher_owen` regarding SM12X detection
- Community repo has 135+ stars, actively maintained for DGX Spark/GB10 systems

## API Access

### Endpoint
```
http://pegasus.home.arpa:8000
```

### Firewall Rule
```bash
sudo ufw allow 8000/tcp comment "vLLM inference server"
```

### Example Usage

#### Basic Chat Completion
```bash
# List models
curl http://pegasus.home.arpa:8000/v1/models

# Chat completion
curl http://pegasus.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/models/models--openai--gpt-oss-120b/snapshots/b5c939de8f754692c1647ca79fbf85e8c1e70f8a",
    "messages": [{"role":"user", "content":"Your prompt here"}],
    "max_tokens": 1000
  }'
```

#### Tool Calling Example
```bash
curl http://pegasus.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/models/models--openai--gpt-oss-120b/snapshots/b5c939de8f754692c1647ca79fbf85e8c1e70f8a",
    "messages": [{"role":"user", "content":"What is 2+2?"}],
    "max_tokens": 50,
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "calculate",
          "description": "Perform a mathematical calculation",
          "parameters": {
            "type": "object",
            "properties": {
              "expression": {
                "type": "string",
                "description": "The mathematical expression to evaluate"
              }
            },
            "required": ["expression"]
          }
        }
      }
    ]
  }'
```

**Expected Response:**
```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [{
        "type": "function",
        "function": {
          "name": "calculate",
          "arguments": "{\"expression\": \"2+2\"}"
        }
      }],
      "reasoning_content": "User asks a simple math question. Use calculation tool."
    },
    "finish_reason": "tool_calls"
  }]
}
```

## Features

### Reasoning Traces
GPT-OSS-120B includes chain-of-thought reasoning in the `reasoning_content` field, showing the model's internal problem-solving process.

### Special Capabilities
- **Tool calling support**: OpenAI-compatible function calling with `--tool-call-parser openai` and `--enable-auto-tool-choice`
- **Extended context**: 131K tokens (configurable up to 1M)
- **Prefix caching**: Enabled for faster repeated prompt processing
- **Chunked prefill**: Max 2048 tokens per batch for optimal memory usage

## Role: Architect & Analyst

This model is designated for:
- **Software Architecture Design**: System design, component interaction, scalability planning
- **Code Analysis**: Deep code review, pattern detection, refactoring suggestions
- **Technical Documentation**: Generating comprehensive technical specs and documentation
- **Problem Decomposition**: Breaking down complex requirements into actionable tasks
- **Long-Context Analysis**: Processing large codebases, documentation sets, or multi-file changes

The extended 131K context window makes it ideal for analyzing entire codebases or long technical documents in a single request.

## Infrastructure

### NFS Share Configuration
Models are stored on a centralized NFS share for access across all systems:
```
flashstore.home.arpa:/volume1/models
  - 9.1 TB capacity
  - 10 GbE network connection
  - RAID5 configuration (ASUSTOR FS6712X)
  - Mounted at: /mnt/models
```

Mount command:
```bash
sudo mount -t nfs4 flashstore.home.arpa:/volume1/models /mnt/models \
  -o rw,hard,intr,_netdev,noatime,nofail,rsize=1048576,wsize=1048576
```

### Model Transfer
Model was transferred from Venus to NFS at 368 MB/s:
```bash
rsync -avh --progress \
  ~/ai-shared/cache/huggingface/hub/models--openai--gpt-oss-120b \
  /mnt/models/
```

## Startup Time Breakdown
1. Container initialization: ~5 seconds
2. Model architecture resolution: ~3 seconds
3. Model loading (fastsafetensors): ~70 seconds
4. torch.compile optimization: ~18 seconds
5. KV cache allocation: ~2 seconds
6. FlashInfer autotuning: ~1 second
7. API server startup: ~1 second

**Total**: ~2 minutes from `docker run` to ready

## Limitations & Notes

### Known Issues
- "Not enough SMs to use max_autotune_gemm mode" warning (expected on GB10)
- GDS (GPU Direct Storage) not supported on this platform (uses CPU path instead)
- CUDA compatibility mode: Using CUDA 13.1 with driver 580.95.05

### Performance Notes
- Model is MXFP4 quantized (uses Marlin backend on GB10)
- Performance is 2-3x faster than standard vLLM on Blackwell without optimizations
- SGLang may offer better performance for this specific model (per forum discussions)
- Consider exploring SGLang if maximum throughput is critical

### Context Limits
- Configured: 131,072 tokens
- KV cache supports: 543,248 tokens total
- Maximum concurrent 131K requests: ~8x

## Future Improvements

1. **Multi-node deployment**: Use Ray distributed backend to span multiple GB10 systems
2. **SGLang comparison**: Test SGLang for potentially better MXFP4 performance
3. **Larger context**: Test with full model capacity (model supports up to 1M tokens)
4. **Performance tuning**: Experiment with different batch sizes and chunked prefill settings
5. **Monitoring**: Add Prometheus/Grafana for throughput and latency monitoring

## Related Systems

- **Venus**: RTX PRO 6000 Blackwell (cleaned up, no active deployment)
- **Stella**: GB10 Grace Blackwell (vLLM build in progress for GLM-4.7-Flash)

## Deployment History

### 2026-01-25: Tool Calling Support Added
- **Updated by**: Mike & Claude
- **Container**: `gpt-oss-120b` (d6ea729bc554)
- **Changes**:
  - Added `--tool-call-parser openai` for OpenAI-compatible function calling
  - Added `--enable-auto-tool-choice` for automatic tool selection
- **Verification**: Successfully tested with calculator tool example
- **Status**: ✅ Running with tool calling enabled

### 2026-01-22: Initial Deployment
- **Deployed by**: Mike & Claude
- **Container**: `gpt-oss-120b` (f1e1140474be)
- **Performance**: 34 tokens/sec sustained throughput
- **Status**: Successfully deployed and benchmarked

## Contributors
- Setup: Mike (user) and Claude (AI assistant)
- Community Docker: eugr (https://github.com/eugr/spark-vllm-docker)
- GB10 patches: christopher_owen, eugr, and NVIDIA DGX Spark community
