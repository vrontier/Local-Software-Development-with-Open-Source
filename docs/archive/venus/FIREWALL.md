# Venus Firewall Configuration

## Current UFW Status

```
Status: active

To                         Action      From
--                         ------      ----
26819                      ALLOW       Anywhere                   # SSH
50201                      ALLOW       Anywhere
8000/tcp                   ALLOW       10.0.0.0/24               # Existing service
8080/tcp                   ALLOW       10.0.0.0/24               # Go4CUDA API
26819 (v6)                 ALLOW       Anywhere (v6)
50201 (v6)                 ALLOW       Anywhere (v6)
```

## 🔥 Action Required: Add Port 8001

Port 8001 needs to be opened for the GPT-OSS 120B API to be accessible from your Mac (10.0.0.0/24 network).

### Quick Command

SSH to venus and run:

```bash
ssh venus-llm
cd ~/gpt-oss-service
./add-firewall-rule.sh
```

### Or Run Manually

```bash
ssh venus-llm
sudo ufw allow from 10.0.0.0/24 to any port 8001 proto tcp comment 'vLLM GPT-OSS 120B API'
sudo ufw status numbered
```

### Expected Result

After adding the rule, UFW status should show:

```
To                         Action      From
--                         ------      ----
26819                      ALLOW       Anywhere
50201                      ALLOW       Anywhere
8000/tcp                   ALLOW       10.0.0.0/24
8001/tcp                   ALLOW       10.0.0.0/24               # vLLM GPT-OSS 120B API ← NEW
8080/tcp                   ALLOW       10.0.0.0/24               # Go4CUDA API
26819 (v6)                 ALLOW       Anywhere (v6)
50201 (v6)                 ALLOW       Anywhere (v6)
```

## Port Allocation Summary

| Port | Service | Network | Description |
|------|---------|---------|-------------|
| 26819 | SSH | Anywhere | Remote access |
| 50201 | Unknown | Anywhere | Existing service |
| 8000 | Unknown | 10.0.0.0/24 | Existing local service |
| **8001** | **vLLM** | **10.0.0.0/24** | **GPT-OSS 120B API (NEW)** |
| 8080 | Go4CUDA | 10.0.0.0/24 | Go4CUDA API |

## Testing After Firewall Configuration

### 1. Verify UFW Rule
```bash
ssh venus-llm 'sudo ufw status | grep 8001'
```

Expected output:
```
8001/tcp                   ALLOW       10.0.0.0/24               # vLLM GPT-OSS 120B API
```

### 2. Deploy Service
```bash
ssh venus-llm '~/gpt-oss-service/deploy.sh'
```

### 3. Test from Venus Locally
```bash
ssh venus-llm 'curl -s http://localhost:8000/health'
```

### 4. Test from Mac (through firewall)
```bash
curl http://venus.home.arpa:8001/health
```

Expected response:
```json
{"status": "ok"}
```

### 5. Test Inference
```bash
curl http://venus.home.arpa:8001/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-120b",
    "prompt": "Hello, world!",
    "max_tokens": 50
  }' | jq
```

## Troubleshooting

### Port Still Blocked?

Check if the rule was added correctly:
```bash
ssh venus-llm 'sudo ufw status numbered | grep -A 1 8001'
```

### Check What's Listening on Port 8001
```bash
ssh venus-llm 'sudo lsof -i :8001'
```

### View UFW Logs
```bash
ssh venus-llm 'sudo tail -f /var/log/ufw.log | grep 8001'
```

### Temporarily Allow All Traffic (for testing only)
```bash
# DO NOT USE IN PRODUCTION
ssh venus-llm 'sudo ufw allow 8001/tcp'
```

### Remove Rule if Needed
```bash
# List rules with numbers
ssh venus-llm 'sudo ufw status numbered'

# Delete by number (e.g., if rule is #7)
ssh venus-llm 'sudo ufw delete 7'
```

## Security Notes

✅ **Best Practice:** Port 8001 is restricted to local network (10.0.0.0/24)
- Your Mac at 10.0.0.x can access it
- External internet cannot access it
- Matches the pattern of existing port 8000 rule

⚠️ **Important:** This API has no authentication by default. Keep it on the local network only.

## Next Steps After Firewall Configuration

1. ✅ Add firewall rule (this document)
2. 🚀 Deploy service: `ssh venus-llm '~/gpt-oss-service/deploy.sh'`
3. 🧪 Test inference: `ssh venus-llm '~/gpt-oss-service/test.sh'`
4. 🎮 Configure OpenCode to use `http://venus.home.arpa:8001`

---

**Status:** Firewall configuration required before deployment
**Script Location:** `~/gpt-oss-service/add-firewall-rule.sh` on venus
**Manual Command:** `sudo ufw allow from 10.0.0.0/24 to any port 8001 proto tcp`
