# Changelog

All notable changes to this project will be documented in this file.

---

## [2026-02-11] - Migration to llama.cpp & Qwen3 Benchmarking

### Infrastructure
- **Engine Migration**: Both systems migrated from vLLM (Docker) to llama.cpp (native, systemd)
  - Built llama.cpp from source on both systems (b7999+, CUDA 13.0, SM 12.1)
  - Configured as systemd services (`llama-server.service`) with `Requires=mnt-models.mount`
  - Auto-restart on failure, starts after NFS mount is ready
  - Docker completely removed from both systems — no container overhead

- **Pegasus Performance Boost**: GPT-OSS-120B generation speed **34 → 58.8 tok/s (+73%)**
  - Same model, same MXFP4 quantization — llama.cpp is simply faster on GB10
  - Model re-downloaded as GGUF format (59 GiB vs 130 GB safetensors)
  - Prompt processing: 1,809 tok/s
  - Reasoning traces preserved via `--jinja` flag

- **Stella Model Change**: Switched from Qwen3-Coder-30B-A3B (MoE) to Qwen3-14B (dense)
  - Motivated by Taskmeister meeting-minutes quality requirements
  - Dense 14B provides better quality per active parameter than 3B-active MoE
  - Performance: 14.7 tok/s generation, 1,200 tok/s prompt processing
  - Q8_0 quantization (14.6 GiB) — best quality-to-size ratio

### Benchmarking
- **Qwen3 Dense Family on GB10** (llama.cpp, Q8_0, flash attention):

  | Model | Size | Prompt (pp2048) | Generation (tg512) |
  |-------|------|-----------------|-------------------|
  | Qwen3-8B | 8.1 GiB | 2,236 tok/s | 27.7 tok/s |
  | Qwen3-14B | 14.6 GiB | 1,200 tok/s | 14.7 tok/s |
  | Qwen3-32B | 32.4 GiB | 503 tok/s | 6.5 tok/s |

- Generation speed scales linearly with model size (memory-bandwidth bound at ~78% of theoretical 273 GB/s)
- Full results: [docs/research/BENCHMARK_Qwen3_Dense_GB10_llamacpp.md](docs/research/BENCHMARK_Qwen3_Dense_GB10_llamacpp.md)

### Research & Evaluation
- **NVFP4 on GB10**: Investigated and ruled out — CUTLASS FP4 kernels not compiled for SM 12.1 in vLLM 0.11.1
- **AWQ on GB10**: Downloaded Qwen3-32B-AWQ (19 GB) — available on NFS but not deployed (native context only 40K)
- **Taskmeister Qwen3 Analysis**: Evaluated Qwen3 family for meeting-minutes task (see `TASKMEISTER_LLM_Qwen3_family.md`)

### Models on NFS
New models added to flashstore:
- `gpt-oss-120b-GGUF/`: 60 GB (Pegasus, active)
- `Qwen3-14B-GGUF/`: 15 GB (Stella, active)
- `Qwen3-32B-GGUF/`: 33 GB (benchmark, available)
- `Qwen3-8B-GGUF/`: 8.5 GB (benchmark, available)
- `models--Qwen--Qwen3-32B-AWQ/`: 19 GB (vLLM format, available)

### Removed
- vLLM Docker containers and images on both systems
- Docker-compose service configuration (replaced by systemd)

---

## [2026-02-04] - Production Service Deployment & Storage Migration

### Infrastructure
- **Service Deployment**: Both Pegasus and Stella now run vLLM as docker-compose services
  - Auto-restart on boot (`restart: unless-stopped`)
  - Consistent service management via `docker compose up/down/restart`
  - Config stored at `~/vllm-service/docker-compose.yml` on each host

- **NFS Model Storage**: All models migrated to central NFS storage
  - Mount point: `/mnt/models` on both systems
  - NFS server: `flashstore.home.arpa:/volume1/models`
  - Added to `/etc/fstab` for persistence on both hosts

- **Disk Cleanup**: Freed significant disk space on both systems
  - Stella: ~467GB freed (61% → 7% usage)
  - Pegasus: ~86GB freed (20% → 10% usage)
  - Removed local model caches, unused Docker images, build caches

### Changed
- **Stella Context**: Confirmed at 204,800 tokens (extended context working)
- **Stella DNS**: Fixed DNS resolution (added pfSense 10.0.0.1 to resolvers)
- **Documentation**: Updated all docs to reflect service-based deployment

### Configuration Files Added
- `systems/pegasus/docker-compose.yml`
- `systems/stella/docker-compose.yml`

---

## [2026-01-25] - Documentation Reorganization & Stella Update

### Added
- **New Documentation Structure**: Organized into `systems/`, `docs/`, `scripts/`
- **STATUS.md**: Single source of truth for current deployment status
- **CHANGELOG.md**: Consolidated timeline replacing session documents
- **Stella Documentation**: Comprehensive guide for GLM-4.7-Flash-NVFP4 deployment
- **Deployment Options Guide**: Comparison of vLLM approaches for Stella

### Changed
- **Pegasus Documentation**: Moved to `systems/pegasus/`
  - README.md (formerly PEGASUS_GPT-OSS-120B.md)
  - QUICKSTART.md
- **Pegasus Model**: Added OpenAI-compatible tool calling support
  - Added `--tool-call-parser openai`
  - Added `--enable-auto-tool-choice`
  - Verified with function calling test
- **Stella Model**: Switching to GadflyII/GLM-4.7-Flash-NVFP4
  - From: zai-org/GLM-4.7-Flash (59GB, broken)
  - To: GadflyII/GLM-4.7-Flash-NVFP4 (20.4GB, NVFP4 optimized)
  - 3x compression with only 1.3% accuracy loss

### Archived
- **Session Documents**: Moved to `docs/archive/sessions/`
  - 2026-01-22.md (formerly READ_FIRST.md)
  - 2026-01-21.md (formerly SESSION_2026-01-21.md)
- **Venus Documentation**: Moved to `docs/archive/venus/`
  - VLLM_ATTEMPT.md (abandoned vLLM setup)
  - FIREWALL.md (firewall configuration)
- **Research**: Moved to `docs/research/`
  - KERNEL_DESIGN.md (future project proposal)

### Infrastructure
- Created organized directory structure for scalability
- Separated active systems from archived experiments
- Improved documentation discoverability

---

## [2026-01-22] - Initial Production Deployments

### Pegasus - GPT-OSS-120B
- **Status**: ✅ Successfully deployed and operational
- **Model**: OpenAI GPT-OSS-120B (MXFP4, 117B params, 130GB)
- **vLLM**: Community build from eugr/spark-vllm-docker
- **Performance**: 34 tokens/sec sustained throughput
- **Context**: 131,072 tokens
- **Resolution**: Fixed Marlin backend hang using community container
- **Hardware**: ASUS Ascent GX10, 128GB GPU
- **Storage**: NFS mount from flashstore.home.arpa
- **API**: http://pegasus.home.arpa:8000

### Venus - NVIDIA NIM (Incomplete)
- **Attempted**: vLLM deployment (failed at Marlin backend)
- **Switched**: To NVIDIA NIM container
- **Status**: ⚠️ Download incomplete (~25GB/60-70GB)
- **Current**: System inactive, deployment abandoned
- **Hardware**: RTX PRO 6000 Blackwell, 98GB GPU

### Stella - vLLM Build
- **Status**: ✅ Build completed successfully
- **Build**: Custom vLLM Docker image with GB10 support
- **Image**: 67GB, vLLM v0.14.0rc2.dev259
- **Duration**: ~8 hours (435 CUDA kernel files)
- **Model**: zai-org/GLM-4.7-Flash (30B MoE)
- **Issue**: Model problematic, needs replacement
- **Hardware**: Lenovo ThinkStation PGX, GB10 Grace Blackwell, 128GB ARM

---

## [2026-01-21] - Repository Reorganization (vllm-gb10)

### Added
- **vllm-gb10/** as self-contained publishable project
- Comprehensive documentation for GB10/Blackwell support
- Build scripts and automation

### Changed
- Moved SETUP.md into vllm-gb10/ directory
- Made vllm-gb10/ ready for standalone distribution
- Updated cross-references

### Documentation Created
- vllm-gb10/README.md - Project overview
- vllm-gb10/SETUP.md - Complete setup guide (22k+ lines)
- vllm-gb10/QUICKREF.md - Command reference
- vllm-gb10/DEPLOYMENT.md - Architecture diagrams
- vllm-gb10/INTEGRATION.md - Repo integration guide
- vllm-gb10/CONTRIBUTING.md - Contribution guidelines
- vllm-gb10/PUBLISHING.md - Publishing workflow
- vllm-gb10/FILES.md - File inventory

---

## [Earlier] - Project Inception

### Infrastructure Setup
- **Network**: Configured local .home.arpa DNS
- **Storage**: Set up NFS share on flashstore (9.1TB, RAID5)
- **Systems**: 
  - Pegasus: ASUS Ascent GX10
  - Venus: RTX PRO 6000 Blackwell
  - Stella: Lenovo ThinkStation PGX (Grace Blackwell)

### vLLM GB10 Development
- Created Dockerfile.gb10 for Blackwell support
- Integrated PR #31740 patches
- Multi-architecture CUDA kernel compilation
- Added GLM-4.7-Flash support via transformers main branch

---

## Performance Benchmarks

### Pegasus (GPT-OSS-120B)
| Test | Tokens | Time (s) | Tokens/sec |
|------|--------|----------|------------|
| 200-word story | 300 | 9.29 | 32.3 |
| 400-word story | 600 | 17.50 | 34.3 |
| 2000-word story | 3000 | 87.77 | 34.2 |

**Consistent**: ~34 tokens/second across all test sizes  
**Memory**: 66GB model + 37GB KV cache = 103GB total

### Stella (GLM-4.7-Flash-NVFP4)
- **Target**: 50+ tokens/sec
- **Memory**: ~20GB model + ~100GB KV cache expected
- **Status**: Benchmarks pending deployment

---

## Technical Achievements

### Pegasus
- ✅ Resolved Marlin backend hang on GB10 hardware
- ✅ Achieved consistent 34 tok/s throughput
- ✅ Enabled 131K token context window
- ✅ Implemented OpenAI-compatible tool calling
- ✅ Fast model loading with fastsafetensors (70s)

### Stella (Build)
- ✅ Successful GB10 Grace Blackwell vLLM compilation
- ✅ ARM architecture support
- ✅ Multi-architecture CUDA kernels (8.0, 8.6, 8.9, 9.0, 12.1)
- 🔄 Model deployment in progress

### vllm-gb10 Project
- ✅ Self-contained publishable project
- ✅ Complete documentation suite
- ✅ Build automation scripts
- ✅ Integration with parent repository

---

## Known Issues & Limitations

### Pegasus
- GDS (GPU Direct Storage) not supported on platform
- "Not enough SMs" warning for max_autotune_gemm (expected)
- CUDA compatibility mode (13.1 with driver 580.95.05)

### Stella
- Previous model (zai-org/GLM-4.7-Flash) problematic
- Migration to NVFP4 variant in progress

### Venus
- vLLM Marlin backend hang (unresolved with standard containers)
- NVIDIA NIM deployment incomplete
- System currently inactive

---

## Future Plans

### Immediate (In Progress)
- [ ] Complete Stella GLM-4.7-Flash-NVFP4 deployment
- [ ] Performance benchmark Stella vs Pegasus
- [ ] Create unified deployment guide
- [ ] Document network topology

### Short Term
- [ ] Evaluate GadflyII's vLLM fork for Stella
- [ ] Add monitoring (Prometheus/Grafana)
- [ ] Create system health check scripts
- [ ] Multi-system testing framework

### Long Term
- [ ] Consider Venus reactivation with different model
- [ ] Explore multi-node Ray deployment
- [ ] Test SGLang for performance comparison
- [ ] Expand context limits (up to 1M tokens)

---

## Contributors

- **Mike** - Infrastructure setup, system administration
- **Claude** - AI assistant for configuration, documentation, troubleshooting

## Community Contributions

- **eugr** - Community vLLM build for DGX Spark/GB10 systems
- **GadflyII** - GLM-4.7-Flash-NVFP4 quantization and vLLM fork
- **NVIDIA DGX Spark Community** - GB10 patches and support

---

**For current status, see [STATUS.md](STATUS.md)**  
**For system documentation, see [systems/](systems/)**
