# Stella Quick Reference

> **Note**: This document still references the old vLLM/Docker deployment and needs a full rewrite. Current deployment uses llama.cpp via systemd.

**Model**: Qwen3-8B (8.2B dense, Q8_0 GGUF)
**API**: http://stella.home.arpa:8000
**Engine**: llama.cpp (systemd service)
**Performance**: 27.8 tok/s generation
**Status**: ✅ Operational

---

## Quick Access

```bash
# Check build progress
./scripts/check-stella-build.sh

# SSH to Stella
ssh stella-llm

# Check build log
ssh stella-llm "tail -f ~/vllm-gadflyii/build.log"

# Attach to build session
ssh stella-llm "screen -r gadflyii-build"  # Ctrl-A D to detach
```

---

## Container Management

### Check Status
```bash
ssh stella-llm "docker ps | grep glm"
ssh stella-llm "docker logs glm-nvfp4"
ssh stella-llm "docker logs -f glm-nvfp4"  # Follow logs
```

### Start/Stop/Restart
```bash
# Start
ssh stella-llm "cd ~/vllm-service && docker compose up -d"

# Stop
ssh stella-llm "cd ~/vllm-service && docker compose down"

# Restart
ssh stella-llm "cd ~/vllm-service && docker compose restart"

# View logs
ssh stella-llm "cd ~/vllm-service && docker compose logs -f"
```

---

## API Testing

### Health Check
```bash
curl http://stella.home.arpa:8000/health
```

### List Models
```bash
curl http://stella.home.arpa:8000/v1/models | python3 -m json.tool
```

### Simple Chat
```bash
curl http://stella.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "GadflyII/GLM-4.7-Flash-NVFP4",
    "messages": [{"role":"user", "content":"Hello! Who are you?"}],
    "max_tokens": 100
  }' | python3 -m json.tool
```

### Longer Generation
```bash
curl http://stella.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "GadflyII/GLM-4.7-Flash-NVFP4",
    "messages": [
      {"role":"system", "content":"You are a helpful AI assistant."},
      {"role":"user", "content":"Explain how mixture-of-experts models work."}
    ],
    "max_tokens": 500,
    "temperature": 0.7
  }' | python3 -m json.tool
```

### Streaming Response
```bash
curl http://stella.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "GadflyII/GLM-4.7-Flash-NVFP4",
    "messages": [{"role":"user", "content":"Write a short poem about AI."}],
    "max_tokens": 200,
    "stream": true
  }'
```

---

## System Info

### GPU Status
```bash
ssh stella-llm "nvidia-smi"
ssh stella-llm "nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv"
```

### Disk Space
```bash
ssh stella-llm "df -h /"
ssh stella-llm "du -sh ~/vllm-gadflyii ~/ai-shared/cache/huggingface"
```

### Docker Images
```bash
ssh stella-llm "docker images | grep -E 'REPOSITORY|vllm'"
```

### vLLM Version
```bash
ssh stella-llm "docker run --rm vllm-gadflyii:nvfp4 python3 -c 'import vllm; print(vllm.__version__)'"
```

---

## Build Status Check

### Check Build Progress
```bash
# Quick status
./scripts/check-stella-build.sh

# Detailed log (last 50 lines)
ssh stella-llm "tail -50 ~/vllm-gadflyii/build.log"

# Search for errors
ssh stella-llm "grep -i error ~/vllm-gadflyii/build.log | tail -20"

# Check if build completed
ssh stella-llm "docker images | grep vllm-gadflyii"
```

### Monitor Build Live
```bash
# Watch log file
ssh stella-llm "tail -f ~/vllm-gadflyii/build.log"

# Or attach to screen session
ssh stella-llm "screen -r gadflyii-build"
# Press Ctrl-A D to detach without stopping
```

---

## Troubleshooting

### Build Taking Too Long
```bash
# Check system load
ssh stella-llm "top -bn1 | head -20"

# Check if docker is running
ssh stella-llm "ps aux | grep docker"

# Check build progress
ssh stella-llm "tail -100 ~/vllm-gadflyii/build.log | grep -E 'Step|Running|Building'"
```

### Container Won't Start
```bash
# Check container status
ssh stella-llm "docker ps -a | grep glm"

# View full logs
ssh stella-llm "docker logs glm-nvfp4 2>&1 | tail -100"

# Check for port conflicts
ssh stella-llm "sudo netstat -tlnp | grep 8000"

# Verify GPU
ssh stella-llm "nvidia-smi"
```

### API Not Responding
```bash
# Check if API is listening
ssh stella-llm "curl -s http://localhost:8000/health || echo 'API not responding'"

# Check container logs for errors
ssh stella-llm "docker logs glm-nvfp4 2>&1 | grep -i error"

# Restart container
ssh stella-llm "cd ~/vllm-service && docker compose restart && docker compose logs -f"
```

### Out of Memory
```bash
# Check GPU memory
ssh stella-llm "nvidia-smi"

# Reduce GPU memory utilization
ssh stella-llm "cd ~/vllm-service"
# Edit docker-compose.yml: --gpu-memory-utilization 0.75
ssh stella-llm "cd ~/vllm-service && docker compose down && docker compose up -d"
```

---

## Configuration Files

### docker-compose.yml Location
```bash
ssh stella-llm "cat ~/vllm-service/docker-compose.yml"
```

### Edit Configuration
```bash
ssh stella-llm "nano ~/vllm-service/docker-compose.yml"
# After editing:
ssh stella-llm "cd ~/vllm-service && docker compose down && docker compose up -d"
```

### Build Configuration
```bash
ssh stella-llm "cat ~/vllm-gadflyii/Dockerfile.gadflyii"
```

---

## Performance Testing

### Simple Throughput Test
```bash
time curl http://stella.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "GadflyII/GLM-4.7-Flash-NVFP4",
    "messages": [{"role":"user", "content":"Count from 1 to 100."}],
    "max_tokens": 500
  }' | python3 -c "import sys, json; d=json.load(sys.stdin); print(f\"Tokens: {d['usage']['completion_tokens']}, Time: see above\")"
```

### Monitor During Generation
```bash
# In one terminal:
curl http://stella.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"GadflyII/GLM-4.7-Flash-NVFP4","messages":[{"role":"user","content":"Write a long essay about AI."}],"max_tokens":2000}'

# In another terminal:
watch -n 1 "ssh stella-llm nvidia-smi"
```

---

## Quick Commands Summary

| Task | Command |
|------|---------|
| Check build | `./scripts/check-stella-build.sh` |
| SSH to Stella | `ssh stella-llm` |
| Watch build | `ssh stella-llm "tail -f ~/vllm-gadflyii/build.log"` |
| Start service | `ssh stella-llm "cd ~/vllm-service && docker compose up -d"` |
| Stop service | `ssh stella-llm "cd ~/vllm-service && docker compose down"` |
| View logs | `ssh stella-llm "docker logs -f glm-nvfp4"` |
| Health check | `curl http://stella.home.arpa:8000/health` |
| Test API | `curl http://stella.home.arpa:8000/v1/models` |
| GPU status | `ssh stella-llm nvidia-smi` |
| Disk space | `ssh stella-llm "df -h /"` |

---

## Expected Timeline

| Stage | Duration | Status |
|-------|----------|--------|
| Base image download | 15-20 min | ✅ |
| System dependencies | 5-10 min | 🔄 |
| PyTorch installation | 10-15 min | ⏳ |
| Transformers build | 15-20 min | ⏳ |
| vLLM compilation | 2-3 hours | ⏳ |
| Image finalization | 5-10 min | ⏳ |
| **Total** | **3-4 hours** | 🔄 |

**Started**: 2026-01-25 21:18 PM  
**Expected Completion**: 01:00-02:00 AM

---

## After Build Completes

### 1. Verify Image
```bash
ssh stella-llm "docker images | grep vllm-gadflyii"
# Should show: vllm-gadflyii:nvfp4
```

### 2. Deploy Service
```bash
ssh stella-llm "cd ~/vllm-service && docker compose up -d"
```

### 3. Monitor Startup (2-5 minutes)
```bash
ssh stella-llm "docker logs -f glm-nvfp4"
# Wait for: "Application startup complete"
```

### 4. Test API
```bash
curl http://stella.home.arpa:8000/health
curl http://stella.home.arpa:8000/v1/models
```

### 5. Benchmark Performance
```bash
# Run throughput test
# Measure tokens/sec
# Compare to Pegasus (34 tok/s)
```

---

## Documentation

- **[Full Documentation](README.md)** - Complete Stella deployment guide
- **[Migration Guide](MIGRATION.md)** - Migrating from old model
- **[Deployment Options](../../STELLA_DEPLOYMENT_OPTIONS.md)** - vLLM fork comparison
- **[Status Page](../../STATUS.md)** - Current system status

---

**Build Status**: 🔄 In Progress - Check back in 3-4 hours!
