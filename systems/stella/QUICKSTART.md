# Stella Quick Reference

**Model**: Meta Llama 4 Scout 17B-16E (109B/17B active MoE, Q6_K GGUF)
**API**: http://stella.home.arpa:8000
**Engine**: llama.cpp (build b8006, systemd service)
**Performance**: 14.5 tok/s generation, ~62 tok/s prompt
**Context**: 32K tokens
**Status**: ✅ Operational

---

## Quick Access

```bash
# SSH to Stella
ssh stella-llm

# Check service status
ssh stella-llm "systemctl status llama-server"

# Watch logs
ssh stella-llm "journalctl -u llama-server -f"
```

---

## Service Management

```bash
# Start
ssh stella-llm "sudo systemctl start llama-server"

# Stop
ssh stella-llm "sudo systemctl stop llama-server"

# Restart
ssh stella-llm "sudo systemctl restart llama-server"

# Status
ssh stella-llm "sudo systemctl status llama-server"

# Logs
ssh stella-llm "journalctl -u llama-server -f"
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
    "model": "Llama-4-Scout-17B-16E-Instruct-Q6_K-00001-of-00002.gguf",
    "messages": [{"role":"user", "content":"Hello! Who are you?"}],
    "max_tokens": 100
  }' | python3 -m json.tool
```

### Tool Calling
```bash
curl http://stella.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Llama-4-Scout-17B-16E-Instruct-Q6_K-00001-of-00002.gguf",
    "messages": [{"role":"user", "content":"What is the weather in Tokyo?"}],
    "tools": [{"type":"function","function":{"name":"get_weather","description":"Get weather","parameters":{"type":"object","properties":{"location":{"type":"string"}},"required":["location"]}}}],
    "tool_choice": "auto"
  }' | python3 -m json.tool
```

### Streaming Response
```bash
curl http://stella.home.arpa:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Llama-4-Scout-17B-16E-Instruct-Q6_K-00001-of-00002.gguf",
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
ssh stella-llm "df -h /mnt/models"
```

### llama.cpp Version
```bash
ssh stella-llm "/home/llm-agent/llama.cpp/build/bin/llama-server --version"
```

---

## Configuration

### Service File Location
```bash
ssh stella-llm "cat /etc/systemd/system/llama-server.service"
```

### Edit Configuration
```bash
ssh stella-llm "sudo nano /etc/systemd/system/llama-server.service"
# After editing:
ssh stella-llm "sudo systemctl daemon-reload && sudo systemctl restart llama-server"
```

---

## Quick Commands Summary

| Task | Command |
|------|---------|
| SSH to Stella | `ssh stella-llm` |
| Service status | `ssh stella-llm "systemctl status llama-server"` |
| Start service | `ssh stella-llm "sudo systemctl start llama-server"` |
| Stop service | `ssh stella-llm "sudo systemctl stop llama-server"` |
| View logs | `ssh stella-llm "journalctl -u llama-server -f"` |
| Health check | `curl http://stella.home.arpa:8000/health` |
| List models | `curl http://stella.home.arpa:8000/v1/models` |
| GPU status | `ssh stella-llm nvidia-smi` |

---

## Documentation

- **[Full Documentation](README.md)** - Complete Stella deployment guide
- **[Status Page](../../STATUS.md)** - Current system status
- **[Pegasus](../pegasus/)** - Compare with GPT-OSS-120B

---

**Status**: ✅ Operational — Meta Llama 4 Scout 17B-16E (109B/17B MoE)
