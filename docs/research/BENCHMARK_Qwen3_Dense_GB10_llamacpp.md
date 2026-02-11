# Benchmark: Qwen3 Dense Family on GB10 — llama.cpp

- **Date**: 2026-02-11
- **Hardware**: Stella (Lenovo ThinkStation PGX), NVIDIA GB10 Grace Blackwell, 128 GB unified memory
- **Engine**: llama.cpp build 4d3daf80f (b7999+), CUDA 13.0, SM 12.1
- **Build flags**: `-DGGML_CUDA=ON -DGGML_CUDA_F16=ON -DCMAKE_CUDA_ARCHITECTURES=121`
- **Runtime flags**: `-ngl 999 -mmp 0 -fa 1` (all layers GPU, no mmap, flash attention)
- **Quantization**: Q8_0 (8-bit) for all models
- **Source**: [bartowski GGUF repos on HuggingFace](https://huggingface.co/bartowski)
- **Tool**: `llama-bench` (5 runs per test, mean ± stddev)

---

## Results

### Prompt Processing (tokens/sec, higher is better)

| Test | Qwen3-8B (8.1 GiB) | Qwen3-14B (14.6 GiB) | Qwen3-32B (32.4 GiB) |
|------|--------------------:|----------------------:|----------------------:|
| pp512 | 2,225.39 ± 12.05 | 1,196.87 ± 1.61 | 504.71 ± 0.21 |
| pp1024 | 2,246.39 ± 2.97 | 1,203.57 ± 1.83 | 508.33 ± 0.85 |
| pp2048 | 2,236.04 ± 4.12 | 1,199.89 ± 1.40 | 503.37 ± 0.71 |

### Text Generation (tokens/sec, higher is better)

| Test | Qwen3-8B (8.1 GiB) | Qwen3-14B (14.6 GiB) | Qwen3-32B (32.4 GiB) |
|------|--------------------:|----------------------:|----------------------:|
| tg128 | 27.75 ± 0.00 | 14.73 ± 0.00 | 6.55 ± 0.00 |
| tg256 | 27.79 ± 0.01 | 14.73 ± 0.00 | 6.53 ± 0.00 |
| tg512 | 27.70 ± 0.00 | 14.70 ± 0.00 | 6.52 ± 0.00 |

### Practical Response Times

| Response length | Qwen3-8B | Qwen3-14B | Qwen3-32B |
|-----------------|----------|-----------|-----------|
| 256 tokens | ~9 sec | ~17 sec | ~39 sec |
| 512 tokens | ~18 sec | ~35 sec | ~78 sec |
| 1,000 tokens | ~36 sec | ~68 sec | ~153 sec |

---

## Analysis

### Memory Bandwidth Bound

Generation speed scales almost perfectly inversely with model size, confirming pure memory-bandwidth saturation:

| Model | Size (GiB) | tg (tok/s) | Bandwidth utilization |
|-------|--------:|--------:|------|
| Qwen3-8B | 8.11 | 27.75 | 225 GB/s (82% of ~273 GB/s) |
| Qwen3-14B | 14.61 | 14.73 | 215 GB/s (79%) |
| Qwen3-32B | 32.42 | 6.55 | 212 GB/s (78%) |

The GB10's ~273 GB/s memory bandwidth is the hard ceiling. Each generated token requires reading the full model weights, so generation speed is `bandwidth / model_size`.

### Memory Headroom (128 GB unified)

| Model | Weights | Remaining for KV cache + OS |
|-------|--------:|----------------------------:|
| Qwen3-8B | 8.1 GB | ~120 GB |
| Qwen3-14B | 14.6 GB | ~113 GB |
| Qwen3-32B | 32.4 GB | ~96 GB |

All three fit comfortably. Even the 32B leaves substantial room for large context windows.

### Comparison with MoE on Same Hardware

For reference, MoE models on GB10 only read active parameters per token:

| Model | Total / Active | tg (tok/s) | Source |
|-------|---------------|--------:|--------|
| Qwen3-Coder-30B-A3B | 30B / 3B active | ~45 | Community benchmarks |
| Qwen3-8B (dense) | 8B / 8B | 27.75 | This benchmark |
| Qwen3-14B (dense) | 14B / 14B | 14.73 | This benchmark |
| Qwen3-32B (dense) | 32B / 32B | 6.55 | This benchmark |

MoE models with small active parameter counts are dramatically faster on bandwidth-constrained hardware like GB10.

---

## Context: Taskmeister LLM Use Case

These benchmarks support the model selection for the Taskmeister meeting-minutes task (see `TASKMEISTER_LLM_Qwen3_family.md`):

- **Qwen3-8B** scored 80/100 on the quality rubric (CPU-only, 300 sec/request)
- **Qwen3-14B** at 14.7 tok/s on GB10 delivers a 1,000-token response in ~68 sec — a 4.4x speedup over CPU, with expected quality improvement over 8B
- **Qwen3-32B** at 6.5 tok/s delivers in ~153 sec — better quality but the speed penalty may not justify the gain for interactive use

**Recommendation**: Qwen3-14B Q8_0 offers the best quality/speed balance on GB10 for this task.

---

## Bonus: GPT-OSS-120B (MXFP4 MoE) on GB10

Benchmarked on Pegasus (ASUS Ascent GX10) for comparison. This is a MoE model — only a fraction of the 117B parameters are active per token, making it dramatically faster than dense models of similar total size.

| Test | GPT-OSS-120B (59 GiB, MXFP4) | vs vLLM |
|------|------------------------------:|--------:|
| pp512 | 1,747.82 ± 11.33 tok/s | — |
| pp2048 | 1,808.99 ± 7.82 tok/s | — |
| tg128 | 58.81 ± 0.06 tok/s | **+73%** (was 34 tok/s) |
| tg512 | 58.60 ± 0.03 tok/s | **+72%** (was 34 tok/s) |

Build flags for MXFP4 support: `-DCMAKE_CUDA_ARCHITECTURES='121a-real'`

Source: [ggml-org/gpt-oss-120b-GGUF](https://huggingface.co/ggml-org/gpt-oss-120b-GGUF)

---

## Reproduction

```bash
# Build llama.cpp on GB10
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON -DGGML_CUDA_F16=ON -DCMAKE_CUDA_ARCHITECTURES=121 -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc
cmake --build build --config Release -j 20

# Run benchmark
./build/bin/llama-bench -m /path/to/model.gguf -ngl 999 -mmp 0 -fa 1 -p 512,1024,2048 -n 128,256,512 --progress
```
