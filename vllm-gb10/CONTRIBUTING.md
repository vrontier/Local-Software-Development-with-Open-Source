# Contributing to vLLM GB10

Thank you for your interest in contributing! We welcome contributions from the community.

## How to Contribute

### Reporting Issues

- Check if the issue already exists
- Provide detailed information:
  - GPU model and compute capability
  - CUDA version
  - Docker version
  - Model being used
  - Error messages and logs
  - Steps to reproduce

### Testing on Different GPUs

We especially need testing on:
- ✅ GB10/Blackwell (tested)
- ⏳ H100/H200 (Hopper)
- ⏳ RTX 4090 (Ada Lovelace)
- ⏳ RTX 3090 (Ampere consumer)
- ⏳ A100 (Ampere datacenter)

**To contribute test results:**
1. Run the image on your GPU
2. Report in Issues with tag "gpu-compatibility"
3. Include:
   - GPU model and compute capability
   - Model tested
   - Memory usage
   - Tokens/second performance
   - Any errors or warnings

### Performance Benchmarks

Help us build a benchmark database:

```bash
# Run benchmark
docker run --gpus all YOUR_USERNAME/vllm-gb10:latest \
  --model <model_name> \
  --benchmark \
  --input-len 512 \
  --output-len 256

# Share results in Discussions
```

### Code Contributions

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Documentation

- Fix typos or unclear sections
- Add examples for different use cases
- Translate to other languages
- Add troubleshooting tips

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/vllm-gb10
cd vllm-gb10

# Build locally
docker build -f Dockerfile.gb10 -t vllm-gb10:dev .

# Test
docker run --gpus all -p 8000:8000 vllm-gb10:dev \
  --model zai-org/GLM-4.7-Flash
```

## Code of Conduct

- Be respectful and inclusive
- Provide constructive feedback
- Help others learn and grow
- Give credit where due

## Questions?

- Open a Discussion for questions
- Join our community chat (if available)
- Check the documentation first

Thank you for contributing! 🚀
