# Pegasus GPT-OSS-120B Quick Reference

## Quick Access
- **API Endpoint**: `http://pegasus.home.arpa:8000`
- **Model**: OpenAI GPT-OSS-120B (MXFP4, 130GB)
- **Context**: 131,072 tokens
- **Performance**: ~34 tokens/sec

## Container Management

### Check Status
```bash
ssh pegasus-llm "docker ps | grep gpt-oss"
```

### View Logs
```bash
ssh pegasus-llm "docker logs gpt-oss-120b"
ssh pegasus-llm "docker logs -f gpt-oss-120b"  # Follow logs
ssh pegasus-llm "docker logs --tail 50 gpt-oss-120b"  # Last 50 lines
```

### Restart Container
```bash
# Stop and remove
ssh pegasus-llm "docker stop gpt-oss-120b && docker rm gpt-oss-120b"

# Start with current configuration (tool calling enabled)
ssh pegasus-llm "docker run -d --name gpt-oss-120b \
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
    --enable-auto-tool-choice"
```

## API Testing

### Health Check
```bash
curl http://pegasus.home.arpa:8000/health
```

### List Models
```bash
curl http://pegasus.home.arpa:8000/v1/models | python3 -m json.tool
```

### Simple Chat
```bash
curl http://pegasus.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/models/models--openai--gpt-oss-120b/snapshots/b5c939de8f754692c1647ca79fbf85e8c1e70f8a",
    "messages": [{"role":"user", "content":"Hello!"}],
    "max_tokens": 100
  }' | python3 -m json.tool
```

### Tool Calling Test
```bash
curl http://pegasus.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/models/models--openai--gpt-oss-120b/snapshots/b5c939de8f754692c1647ca79fbf85e8c1e70f8a",
    "messages": [{"role":"user", "content":"Calculate 15 * 7"}],
    "max_tokens": 50,
    "tools": [{
      "type": "function",
      "function": {
        "name": "calculate",
        "description": "Perform a mathematical calculation",
        "parameters": {
          "type": "object",
          "properties": {
            "expression": {"type": "string", "description": "Math expression"}
          },
          "required": ["expression"]
        }
      }
    }]
  }' | python3 -m json.tool
```

## System Info

### GPU Status
```bash
ssh pegasus-llm "nvidia-smi"
ssh pegasus-llm "nvidia-smi --query-gpu=memory.used,memory.total --format=csv"
```

### Model Storage
```bash
ssh pegasus-llm "df -h /mnt/models"
ssh pegasus-llm "ls -lh /mnt/models/models--openai--gpt-oss-120b/snapshots/"
```

### vLLM Version
```bash
ssh pegasus-llm "docker exec gpt-oss-120b vllm --version"
```

## Troubleshooting

### Container Won't Start
1. Check if port 8000 is already in use:
   ```bash
   ssh pegasus-llm "sudo netstat -tlnp | grep 8000"
   ```

2. Verify NFS mount:
   ```bash
   ssh pegasus-llm "mount | grep /mnt/models"
   ssh pegasus-llm "ls /mnt/models/models--openai--gpt-oss-120b"
   ```

3. Check GPU availability:
   ```bash
   ssh pegasus-llm "nvidia-smi"
   ```

### API Not Responding
1. Check container status:
   ```bash
   ssh pegasus-llm "docker ps -a | grep gpt-oss"
   ```

2. Check logs for errors:
   ```bash
   ssh pegasus-llm "docker logs --tail 100 gpt-oss-120b | grep -i error"
   ```

3. Verify API is listening:
   ```bash
   ssh pegasus-llm "curl localhost:8000/health"
   ```

### Slow Performance
1. Check GPU utilization:
   ```bash
   ssh pegasus-llm "nvidia-smi dmon -s um"
   ```

2. Check NFS performance:
   ```bash
   ssh pegasus-llm "dd if=/mnt/models/test of=/dev/null bs=1M count=1024"
   ```

## Configuration Summary

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `--trust-remote-code` | Enabled | Allow model-specific code |
| `--gpu-memory-utilization` | 0.90 | Use 90% of GPU memory |
| `--max-model-len` | 131072 | 128K token context window |
| `--load-format` | fastsafetensors | Fast model loading |
| `--tool-call-parser` | openai | OpenAI function calling format |
| `--enable-auto-tool-choice` | Enabled | Auto tool selection |

## References
- Full documentation: `PEGASUS_GPT-OSS-120B.md`
- vLLM GPT-OSS Guide: https://docs.vllm.ai/projects/recipes/en/latest/OpenAI/GPT-OSS.html
- OpenAI Cookbook: https://cookbook.openai.com/articles/gpt-oss/run-vllm
