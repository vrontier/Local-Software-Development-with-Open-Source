# Venus GPT-OSS 120B Setup Summary

## 🎯 Configuration Overview

**Server:** venus.home.arpa (SSH port 26819)  
**GPU:** NVIDIA RTX PRO 6000 Max-Q Blackwell (97.9 GB)  
**Model:** OpenAI GPT-OSS 120B (117B params, MXFP4 quantized)  
**API Port:** **8001** (external) → 8000 (container)  
**Access URL:** `http://venus.home.arpa:8001`

---

## 📊 Memory Requirements

| Component | Size | Status |
|-----------|------|--------|
| Model (MXFP4) | ~54.5 GB | ✅ Fits |
| Overhead (30%) | ~16.3 GB | ✅ Included |
| KV Cache (8K) | ~10 GB | ✅ Included |
| **Total** | **~80.8 GB** | **✅ 17GB headroom** |

---

## 🔌 Network Configuration

### Ports Required

**Venus (GPT-OSS 120B):**
- Port **8001/TCP** - OpenAI API endpoint

**Stella (GLM-4.7-Flash):**
- Port **8000/TCP** - OpenAI API endpoint

### Firewall Status

✅ **No firewall active** - Ports are open by default  
No UFW or iptables rules blocking traffic

---

## 🐳 Docker Configuration

**Image:** `nvcr.io/nvidia/vllm:25.12.post1-py3` (NVIDIA-optimized)  
**Container:** `gpt-oss-120b`  
**Auto-restart:** Yes (unless-stopped)

**Key Parameters:**
- `--gpu-memory-utilization 0.90` (use 90% of 98GB)
- `--max-model-len 8192` (8K context window)
- `--dtype bfloat16` (precision)
- `--enable-prefix-caching` (performance optimization)

---

## 📁 Directory Structure

```
~/gpt-oss-service/
├── docker-compose.yml      # Service configuration
├── .env                    # HuggingFace token (secure)
├── deploy.sh              # Deployment script
├── test.sh                # Inference testing
├── monitor.sh             # Service monitoring
└── firewall-setup.sh      # Port configuration

~/ai-shared/
└── cache/huggingface/     # Model cache (~55GB will download)
```

---

## 🚀 Quick Start Commands

### Deploy Service
```bash
ssh venus-llm
cd ~/gpt-oss-service
./deploy.sh
```

**Note:** First run will download ~55GB model (5-10 minutes on fast connection)

### Test Inference
```bash
ssh venus-llm
~/gpt-oss-service/test.sh
```

### Monitor Service
```bash
ssh venus-llm
~/gpt-oss-service/monitor.sh
```

### View Live Logs
```bash
ssh venus-llm
docker logs -f gpt-oss-120b
```

---

## 🧪 Testing from Mac

### Health Check
```bash
curl http://venus.home.arpa:8001/health
```

### List Models
```bash
curl http://venus.home.arpa:8001/v1/models
```

### Test Completion
```bash
curl http://venus.home.arpa:8001/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-120b",
    "prompt": "Write a hello world in Python",
    "max_tokens": 100,
    "temperature": 0.7
  }' | jq
```

### Test Chat Completion
```bash
curl http://venus.home.arpa:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-120b",
    "messages": [
      {"role": "user", "content": "Explain quantum computing in simple terms"}
    ],
    "max_tokens": 200
  }' | jq
```

---

## 🎮 Configure in OpenCode

**Provider Type:** OpenAI Compatible  
**Base URL:** `http://venus.home.arpa:8001`  
**API Key:** `dummy` (not required, but some clients need it)  
**Model:** `gpt-oss-120b`

---

## 🏗️ Multi-Backend Architecture

You now have two GPU backends:

```
                  Mac Studio (Frontend)
                  - OpenCode
                  - Git repositories
                         |
        ┌────────────────┴────────────────┐
        |                                 |
   Stella (Backend #1)            Venus (Backend #2)
   Port: 8000                     Port: 8001
   GPU: GB10 (128GB)              GPU: RTX PRO 6000 (98GB)
   Model: GLM-4.7-Flash           Model: GPT-OSS 120B
   Status: Building...            Status: Ready to deploy
```

**Load Balancing Options:**
1. **Manual selection** - Choose endpoint per task
2. **HAProxy/Nginx** - Round-robin or weighted routing
3. **Client-side** - Failover logic in OpenCode config

---

## 🔧 Service Management

### Start Service
```bash
ssh venus-llm
cd ~/gpt-oss-service
docker compose up -d
```

### Stop Service
```bash
ssh venus-llm
cd ~/gpt-oss-service
docker compose down
```

### Restart Service
```bash
ssh venus-llm
cd ~/gpt-oss-service
docker compose restart
```

### Update Image
```bash
ssh venus-llm
docker pull nvcr.io/nvidia/vllm:25.12.post1-py3
cd ~/gpt-oss-service
docker compose down
docker compose up -d
```

---

## 📊 Expected Performance

**Model:** GPT-OSS 120B (117B params, 5.1B active)  
**Startup Time:** 3-5 minutes (first run with download)  
**Subsequent Starts:** ~30-60 seconds (cached)  
**Memory Usage:** ~85GB GPU RAM  
**Throughput:** ~15-25 tokens/sec (estimated for 120B on RTX PRO 6000)  
**Context Length:** 8192 tokens

---

## 🐛 Troubleshooting

### Service Won't Start
```bash
ssh venus-llm
docker logs gpt-oss-120b
```

**Common Issues:**
- Out of memory: Check `nvidia-smi`
- Model not found: Verify HF_TOKEN in `.env`
- Port conflict: Check `sudo lsof -i :8001`

### Can't Access from Mac
```bash
# Test connectivity
ping venus.home.arpa

# Test port
nc -zv venus.home.arpa 8001

# Check service
ssh venus-llm 'curl -s http://localhost:8000/health'
```

### Model Download Failed
```bash
# Check HuggingFace token
ssh venus-llm 'cat ~/gpt-oss-service/.env'

# Manually test token
ssh venus-llm 'curl -H "Authorization: Bearer hf_..." \
  https://huggingface.co/api/whoami'

# Clear cache and retry
ssh venus-llm 'rm -rf ~/ai-shared/cache/huggingface/hub/models--openai--gpt-oss-120b'
ssh venus-llm '~/gpt-oss-service/deploy.sh'
```

---

## 🔐 Security Notes

1. **HuggingFace Token:** Stored in `~/gpt-oss-service/.env` (600 permissions)
2. **NVCR Credentials:** Stored in `~/.docker/config.json` (unencrypted warning is normal)
3. **API Access:** No authentication required (internal network only)
4. **Firewall:** Consider enabling UFW for production use

---

## 📈 Next Steps

1. ✅ Deploy service: `./deploy.sh`
2. ✅ Test inference: `./test.sh`
3. ✅ Configure OpenCode to use `http://venus.home.arpa:8001`
4. ⏳ Wait for stella build to complete
5. 🎯 Test both backends
6. 📝 Document performance benchmarks
7. 🔄 Set up load balancing (optional)

---

**Created:** 2026-01-22  
**Status:** Ready for deployment  
**Estimated Setup Time:** 10-15 minutes (plus model download)
