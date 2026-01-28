# vLLM for NVIDIA GB10 (Grace Blackwell)

High-performance vLLM inference server with native support for NVIDIA GB10 (Grace Blackwell) GPUs.

> 📚 **Complete Setup Guide**: For detailed setup instructions including SSH configuration, directory structure, and deployment, see [SETUP.md](SETUP.md).

## Features

- ✅ **NVIDIA GB10 Support** - Native support for Grace Blackwell architecture (compute capability 12.1)
- ✅ **Multi-Architecture** - Also supports A100 (8.0), RTX 3090 (8.6), RTX 4090 (8.9), H100 (9.0)
- ✅ **Large MoE Models** - Optimized for Mixture of Experts models like GLM-4.7-Flash
- ✅ **OpenAI Compatible** - Drop-in replacement for OpenAI API
- ✅ **Production Ready** - Docker-based deployment with health checks and monitoring

## Quick Start

> 💡 **New to this setup?** Start with the [Complete Setup Guide](SETUP.md) which covers SSH configuration, directory structure, and detailed deployment steps.

### Prerequisites

- NVIDIA GPU with compute capability 8.0+ (GB10/Blackwell recommended)
- Docker with NVIDIA Container Runtime
- 64GB+ system RAM (128GB recommended for 30B+ models)
- CUDA 12.4+ compatible drivers
- HuggingFace account and token (for model downloads)

**See**: [SETUP.md - Prerequisites](SETUP.md#prerequisites) for verification steps

### Pull and Run

```bash
# Pull the image
docker pull YOUR_DOCKERHUB_USERNAME/vllm-gb10:latest

# Run with GLM-4.7-Flash
docker run -d \
  --name vllm-server \
  --gpus all \
  -p 8000:8000 \
  -e HF_TOKEN=your_huggingface_token \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  YOUR_DOCKERHUB_USERNAME/vllm-gb10:latest \
  --model zai-org/GLM-4.7-Flash \
  --trust-remote-code \
  --gpu-memory-utilization 0.85
```

### Test Inference

```bash
# Health check
curl http://localhost:8000/health

# List models
curl http://localhost:8000/v1/models

# Generate completion
curl http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "zai-org/GLM-4.7-Flash",
    "prompt": "Write a Python function to calculate fibonacci",
    "max_tokens": 256
  }'
```

## Supported Models

This build has been tested with:

- **GLM-4.7-Flash** (30B MoE) - Recommended for GB10
- **Qwen3-Coder-30B-A3B-Instruct-FP8** (30B)
- **Llama 3.x** series (8B, 70B)
- **Mistral** series
- Any vLLM-compatible model

## Docker Compose Deployment

See [docker-compose.example.yml](docker-compose.example.yml) for production deployment.

```bash
# Copy example config
cp docker-compose.example.yml docker-compose.yml

# Edit configuration (add your HuggingFace token, adjust model settings)
vim docker-compose.yml

# Start service
docker compose up -d

# View logs
docker compose logs -f
```

**Complete deployment guide**: See [SETUP.md - Step 7: Create Docker Compose Configuration](SETUP.md#step-7-create-docker-compose-configuration) for:
- Full configuration options explained
- Environment variable setup
- Model cache configuration
- Performance tuning parameters

## Building from Source

If you need to customize the build:

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/vllm-gb10
cd vllm-gb10

# Build image
docker build -f Dockerfile.gb10 -t vllm-gb10:latest .

# This takes 3-4 hours on a 20-core system
```

**Detailed build instructions**: See [SETUP.md - GPU Backend Configuration](SETUP.md#gpu-backend-configuration) for:
- Complete directory structure setup
- Step-by-step build process with monitoring
- Build progress indicators and troubleshooting
- Performance tuning recommendations

## Architecture Support

This image includes CUDA kernels compiled for:

| Architecture | Compute Capability | Examples |
|--------------|-------------------|----------|
| Ampere (datacenter) | 8.0 | A100, A30 |
| Ampere (consumer) | 8.6 | RTX 3090, A40 |
| Ada Lovelace | 8.9 | RTX 4090, L40 |
| Hopper | 9.0 | H100, H200 |
| **Blackwell** | **12.1** | **GB10, GB200** |

## Performance

**GLM-4.7-Flash on GB10 (128GB unified memory):**
- Loading time: ~2 minutes (cached)
- Memory usage: ~57GB model + ~40GB KV cache
- Throughput: ~TBD tokens/sec (will update after benchmarking)
- Max context: 4096 tokens (configurable)

## Technical Details

### Base Image
- Built on: 
- PyTorch: 2.9.1
- CUDA: 12.4
- Python: 3.12

### Key Build Parameters
- 
-  (parallel compilation)
- Transformers: main branch (for latest model support)

### What Makes This Special

1. **GB10 Support from PR #31740**
   - Adds Blackwell-class GPU detection
   - Tested on DGX Spark
   - Enables sm_12.1 architecture

2. **Built from Source**
   - No precompiled binaries for GB10 exist yet
   - All CUDA kernels compiled with GB10 support
   - Full CUDA 12.4 toolkit included

3. **Latest Model Support**
   - Transformers from main branch
   - Includes GLM-4.7-Flash architecture support
   - Compatible with newest MoE models

## Contributing

Contributions welcome! Please:

1. Test on your GPU architecture
2. Report performance benchmarks
3. Submit issues for bugs
4. Share model compatibility results

## License

- vLLM: Apache 2.0
- This Dockerfile and scripts: MIT (or your choice)

## Credits

- **vLLM Project**: https://github.com/vllm-project/vllm
- **GB10 Support PR**: https://github.com/vllm-project/vllm/pull/31740
- **Author**: @seli-equinix (GB10 patches)

## Documentation

- **[SETUP.md](SETUP.md)** - Complete setup guide:
  - [SSH Access Setup](SETUP.md#ssh-access-setup)
  - [GPU Backend Configuration](SETUP.md#gpu-backend-configuration)
  - [Agent Configuration](SETUP.md#agent-configuration)
- **[QUICKREF.md](QUICKREF.md)** - Quick reference for common commands
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Architecture and deployment scenarios
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Contribution guidelines
- **[PUBLISHING.md](PUBLISHING.md)** - How to publish to registries

## Support

- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions
- **vLLM Documentation**: https://docs.vllm.ai/

## Changelog

### v1.0.0 (2026-01-21)
- Initial release with GB10 support
- Multi-architecture build (sm_80, sm_86, sm_89, sm_90, sm_121)
- Based on vLLM PR #31740
- Tested with GLM-4.7-Flash on NVIDIA GB10

---

**Built for the community by GB10 early adopters** 🚀
