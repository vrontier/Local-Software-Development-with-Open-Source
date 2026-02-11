# Taskmeister LLM: Qwen3 Family Analysis for DGX Spark

- **From**: Grace Hopper
- **Date**: 2026-02-11
- **Type**: Analysis
- **References**: `cowork/Mike/2026-02-11_Taskmeister-LLM_Trials.zip`, `cowork/Grace/METRIC_MEETING_MINUTES_QUALITY.md`, `docs/design/TASKMEISTER_LLM.md`

---

## Context

Qwen3-8B scored 80/100 on the meeting minutes quality rubric -- the highest among local models, 5 minutes per request on the Ryzen 9 PRO 3900 (CPU-only). Mike asked whether a "smarter" Qwen3 variant exists that would fit in an NVIDIA DGX Spark.

## DGX Spark Hardware Constraints

| Spec | Value |
|------|-------|
| Superchip | NVIDIA GB10 Grace Blackwell |
| Memory | 128 GB unified (CPU + GPU shared) |
| AI Performance | Up to 1 PFLOP FP4 (sparse) |
| Advertised target | Models up to ~200B parameters |
| Inference stack | NVIDIA AI stack (NIM, TensorRT-LLM, etc.) |

The binding constraint is the **128 GB unified memory**. Model weights, KV cache, and runtime overhead must all fit within this envelope.

---

## Qwen3 Dense Models (Instruct)

These are the standard instruction-tuned dense transformer models in the Qwen3 family. All support think/no-think mode (except 0.6B), Apache 2.0 license, 100+ languages.

| Model | Params | Q8_0 weights | KV cache (32K/1 slot) | Est. total RAM | Fits 128 GB? |
|-------|:------:|:------------:|:--------------------:|:--------------:|:------------:|
| Qwen3-0.6B | 0.6B | ~0.6 GB | ~0.1 GB | ~1 GB | Yes |
| Qwen3-1.7B | 1.7B | ~1.8 GB | ~3.5 GB | ~6 GB | Yes |
| Qwen3-4B | 4B | ~4.2 GB | ~1.5 GB | ~6 GB | Yes |
| **Qwen3-8B** | 8B | ~8.2 GB | ~9.0 GB | ~18 GB | Yes |
| **Qwen3-14B** | 14B | ~15 GB | ~4.5 GB | ~21 GB | Yes |
| **Qwen3-32B** | 32B | ~34 GB | ~10 GB | ~46 GB | **Yes** |

Note: KV cache scales with context length and parallel slots. The estimates above are for 32K context with 1 slot. At 128K/4 slots the KV cache roughly quadruples.

### Memory at production config (128K context, 4 parallel slots)

| Model | Q8_0 weights | KV cache (128K/4 slots) | Est. total RAM | Fits 128 GB? |
|-------|:------------:|:----------------------:|:--------------:|:------------:|
| Qwen3-8B | ~8.2 GB | ~36 GB | ~46 GB | Yes |
| Qwen3-14B | ~15 GB | ~18 GB | ~35 GB | Yes |
| Qwen3-32B | ~34 GB | ~40 GB | ~76 GB | **Yes, ~52 GB headroom** |

Qwen3-32B at Q8_0 with 128K context and 4 parallel slots uses ~76 GB -- well within the 128 GB envelope.

---

## Qwen3 MoE Models (Mixture of Experts)

MoE models have many total parameters but only activate a subset per token. This reduces inference compute but the full weight set must still reside in memory.

| Model | Total params | Active params | Q8_0 weights | KV cache (32K/1) | Est. total RAM | Fits 128 GB? |
|-------|:----------:|:------------:|:------------:|:----------------:|:--------------:|:------------:|
| Qwen3-30B-A3B | 30B | **3B** | ~32 GB | ~7 GB | ~41 GB | Yes, but only 3B active |
| Qwen3-235B-A22B | 235B | **22B** | ~235 GB | ~7 GB | ~245 GB | **No** |

The 235B MoE does not fit at Q8_0. At Q4_K_M (~120 GB weights) it's borderline but leaves no headroom for KV cache. At FP8 (NVIDIA's native format via TensorRT-LLM) the weights are also ~235 GB -- still too large.

The 30B-A3B fits in memory but only activates 3B parameters per token. For a quality-sensitive task like meeting minutes, a 3B-active MoE is unlikely to outperform a dense 8B or 14B model.

---

## Newer "2507" Variants

Qwen released updated instruct and thinking variants in July 2025:

| Model | Type | Parameters | Notes |
|-------|:----:|:---------:|-------|
| Qwen3-4B-Instruct-2507 | Dense | 4B | Updated training; smaller than 8B |
| Qwen3-30B-A3B-Instruct-2507 | MoE | 30B (3B active) | Better training but still only 3B active |
| Qwen3-235B-A22B-Instruct-2507 | MoE | 235B (22B active) | Does not fit DGX Spark |
| Qwen3-4B-Thinking-2507 | Dense | 4B | Thinking-optimized variant |
| Qwen3-30B-A3B-Thinking-2507 | MoE | 30B (3B active) | Thinking-optimized; still 3B active |
| Qwen3-235B-A22B-Thinking-2507 | MoE | 235B (22B active) | Does not fit DGX Spark |

No 2507 variant exists for the 8B, 14B, or 32B dense models yet. The standard Qwen3 instruct models remain the best options at those sizes.

---

## Recommendation

### Primary: Qwen3-32B (Q8_0)

The largest dense Qwen3 model that comfortably fits in a DGX Spark.

| Aspect | Detail |
|--------|--------|
| Parameters | 32B dense |
| Q8_0 weight size | ~34 GB |
| Production config (128K/4 slots) | ~76 GB -- fits with ~52 GB headroom |
| Think mode | Yes |
| Languages | 100+ |
| License | Apache 2.0 |
| Context | 40K native, YaRN to 128K |
| Expected quality | Significantly better than 8B on factual accuracy, quote extraction, hallucination avoidance |

At 4x the parameters of the 8B, Qwen3-32B should improve on the dimensions where the 8B already excels (topic coverage, quote fidelity) and reduce errors in the dimensions where smaller models struggle (action item fabrication, factual accuracy). The 8B scored 80/100 with only a -1 accuracy penalty -- the 32B should approach or exceed that with even fewer hallucinations.

On the DGX Spark's GB10 GPU, inference should be dramatically faster than the 300s the 8B took on CPU. Rough estimate: 20-40 tok/s generation, making a full meeting minutes response (1,000 tokens) achievable in 25-50 seconds.

### Alternative: Qwen3-14B (Q8_0)

If Qwen3-32B proves too slow or memory-constrained with larger contexts:

| Aspect | Detail |
|--------|--------|
| Parameters | 14B dense |
| Q8_0 weight size | ~15 GB |
| Production config (128K/4 slots) | ~35 GB -- fits with ~93 GB headroom |
| Think mode | Yes |
| Expected quality | Better than 8B, likely not as strong as 32B |

The 14B leaves substantial headroom for very large contexts or many parallel slots. It's a good fallback if the 32B encounters memory pressure.

### Not recommended

- **Qwen3-30B-A3B**: Fits in memory but only 3B active. Quality ceiling too low for governance use.
- **Qwen3-235B-A22B**: Does not fit at any practical quantization. Would need multi-node or a DGX Station.
- **Qwen3-4B / Qwen3-1.7B**: Already benchmarked. Too small for the quality target.

---

## Next Steps

1. **Benchmark Qwen3-32B on the DGX Spark** with the same meeting minutes transcript and prompt. Measure quality (rubric score), inference speed (tok/s), and memory usage.
2. **Compare with Qwen3-14B** on the same benchmark to establish the quality/speed tradeoff.
3. **Test with a real project meeting transcript** (decisions, disagreements, action items) -- the current podcast benchmark doesn't stress the action-item and factual-accuracy dimensions enough.
