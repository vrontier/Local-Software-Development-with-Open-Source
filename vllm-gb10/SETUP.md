# Set-up Guide

This guide walks through the complete setup process for creating a local software development environment using open-source LLMs running on dedicated GPU hardware.

## Table of Contents
1. [SSH Access Setup](#ssh-access-setup)
2. [GPU Backend Configuration](#gpu-backend-configuration)
3. [LLM Deployment](#llm-deployment)
4. [Agent Configuration](#agent-configuration)

---

## SSH Access Setup

### Overview
Set-up a dedicated `llm-agent` user account on the GPU compute backend (stella.home.arpa) with passwordless SSH access from your Frontend machine.

**Server Details:**

- Hostname: `stella.home.arpa`
- SSH Port: `26819`
- Target User: `llm-agent`
- Client Machine: Frontend

### Step 1: Generate SSH Key Pair on Frontend

On your Frontend, generate a dedicated SSH key pair for the llm-agent connection:

```bash
# Generate ED25519 key (more secure and smaller than RSA)
ssh-keygen -t ed25519 -C "llm-agent@stella" -f ~/.ssh/id_ed25519_llm_agent
```

**Options explained:**
- `-t ed25519`: Use ED25519 algorithm (recommended for modern systems)
- `-C "llm-agent@stella"`: Comment to identify the key
- `-f ~/.ssh/id_ed25519_llm_agent`: Custom filename for this specific connection

**During key generation:**
- Press Enter to accept the default location (or specify custom path)
- Enter a passphrase (optional but recommended for additional security)
- If you use a passphrase, you'll need to use ssh-agent to avoid typing it repeatedly

**Expected output:**
```
Generating public/private ed25519 key pair.
Enter passphrase (empty for no passphrase): 
Enter same passphrase again: 
Your identification has been saved in /Users/mike/.ssh/id_ed25519_llm_agent
Your public key has been saved in /Users/mike/.ssh/id_ed25519_llm_agent.pub
The key fingerprint is:
SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx llm-agent@stella
```

### Step 2: Create llm-agent User on Stella

SSH into stella as a user with sudo privileges (replace `your_admin_user` with your actual admin username):

```bash
ssh -p 26819 your_admin_user@stella.home.arpa
```

Once logged in, create the `llm-agent` user:

```bash
# Create the user with a home directory
sudo useradd -m -s /bin/bash llm-agent

# Set a password for the user (you'll use this only for the initial setup)
sudo passwd llm-agent

# Add user to specific groups if needed to allow Docker access:
sudo usermod -aG docker llm-agent

# (Optional) Grant sudo privileges if needed for LLM operations
# sudo usermod -aG sudo llm-agent
# Or on some systems:
# sudo usermod -aG wheel llm-agent
```

### Step 3: Configure SSH Directory for llm-agent

While still logged into stella as admin, set up the SSH directory structure:

```bash
# Switch to the llm-agent user
sudo su - llm-agent

# Create .ssh directory with correct permissions
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Create authorized_keys file
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Exit back to admin user
exit
```

### Step 4: Copy Public Key to Stella

Back on your **Frontend**, copy your public key to the stella server:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_llm_agent.pub -p 26819 llm-agent@stella.home.arpa
```

You'll be prompted for the llm-agent password you set in Step 2.

### Step 5: Configure SSH Client on your Frontend computer

Create or edit your SSH config file for easier connection management:

```bash
# Edit SSH config
nano ~/.ssh/config
```

Add the following configuration:

```
# LLM Agent on Stella (ASUS Ascent GX10 - GB10)
Host stella-llm
    HostName stella.home.arpa
    Port 26819
    User llm-agent
    IdentityFile ~/.ssh/id_ed25519_llm_agent
    IdentitiesOnly yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
    
# Optional: Add compression for faster transfers
    Compression yes
    
# Optional: Enable connection multiplexing for better performance
    ControlMaster auto
    ControlPath ~/.ssh/controlmasters/%r@%h:%p
    ControlPersist 10m
```

Create ControlPath directory: 

```bash
mkdir ~/.ssh/controlmasters
```

Set correct permissions on the config file:

```bash
chmod 600 ~/.ssh/config
```

**Configuration explained:**

- `Host stella-llm`: Alias you'll use to connect (e.g., `ssh stella-llm`)
- `HostName`: The actual server address
- `Port`: Custom SSH port (26819)
- `User`: The llm-agent user we created
- `IdentityFile`: Path to your private key
- `IdentitiesOnly yes`: Only use the specified key (prevents trying other keys)
- `ServerAliveInterval/CountMax`: Keep connection alive and detect disconnections

### Step 6: Test Passwordless SSH Connection

From your Frontend, test the connection:

```bash
# Using the SSH config alias
ssh stella-llm

# Or using the full command
ssh -p 26819 -i ~/.ssh/id_ed25519_llm_agent llm-agent@stella.home.arpa
```

If everything is configured correctly, you should be logged in **without being prompted for a password**.

**First connection note:** On your first connection, you'll see a message about the host's authenticity. Type `yes` to continue and add stella to your known_hosts file.

### Troubleshooting

**Problem: Still being asked for password**

1. Check file permissions on stella:
   ```bash
   # SSH to stella as llm-agent
   ls -la ~/.ssh
   # Should show: drwx------ for .ssh (700)
   # Should show: -rw------- for authorized_keys (600)
   ```

2. Check SSH logs on stella:
   ```bash
   sudo tail -f /var/log/auth.log  # Debian/Ubuntu
   # or
   sudo tail -f /var/log/secure    # RHEL/CentOS
   ```

3. Verify your public key is in authorized_keys:
   ```bash
   cat ~/.ssh/authorized_keys
   ```

4. Test with verbose output:
   ```bash
   ssh -vvv -p 26819 llm-agent@stella.home.arpa
   ```

**Problem: Permission denied (publickey)**

- Ensure the private key has correct permissions: `chmod 600 ~/.ssh/id_ed25519_llm_agent`
- Verify you're using the correct key with `-i` flag or in SSH config
- Check that public key authentication is enabled in `/etc/ssh/sshd_config` on stella:
  ```
  PubkeyAuthentication yes
  ```

**Problem: Connection timeout**

- Verify stella is reachable: `ping stella.home.arpa`
- Check if port 26819 is open: `nc -zv stella.home.arpa 26819`
- Verify SSH service is running on stella: `sudo systemctl status sshd`

### Security Best Practices

1. **Disable password authentication** for the llm-agent user (after confirming key-based auth works):
   ```bash
   # On stella, edit sshd_config
   sudo nano /etc/ssh/sshd_config
   
   # Add or modify:
   Match User llm-agent
       PasswordAuthentication no
       PubkeyAuthentication yes
   
   # Restart SSH service
   sudo systemctl restart sshd
   ```

2. **Use strong SSH keys**: ED25519 is recommended, or RSA with at least 4096 bits

3. **Protect your private key**: Never share it, keep secure backups

4. **Use a passphrase**: Adds an extra layer of security for your private key

5. **Regularly rotate keys**: Consider changing SSH keys periodically

6. **Monitor SSH access**: Review auth logs regularly for suspicious activity

---

## GPU Backend Configuration

### Overview

We'll set up **vLLM** (a high-performance serving framework for LLMs) on the GPU backend using a custom Docker build with **NVIDIA GB10 (Grace Blackwell) support**. vLLM provides an OpenAI-compatible API endpoint, making it easy to integrate with tools like OpenCode.

**Why custom build?** 
1. The NVIDIA GB10 GPU (compute capability 12.1) is cutting-edge hardware that requires special support
2. We use vLLM PR #31740 which adds GB10/Blackwell-class GPU support
3. The GLM-4.7-Flash model uses the `glm4_moe_lite` architecture requiring transformers from main branch
4. This single build supports multiple models: GLM-4.7-Flash, Qwen3-Coder, and other 30B+ models

**Hardware:** ASUS Ascent GX10 with NVIDIA GB10 (Grace Blackwell), 128GB unified memory, 20 CPU cores

### Prerequisites

Before starting, ensure:
- SSH access to your GPU backend is configured (see SSH Access Setup above)
- Docker and Docker Compose are installed on the GPU backend
- The llm-agent user has Docker permissions (`sudo usermod -aG docker llm-agent`)
- Port 8000 is open on your GPU backend for API access
- At least 150GB of free disk space for the Docker build (includes CUDA toolkit, vLLM compilation)
- NVIDIA GPU drivers installed (compatible with CUDA 12.4+)
- Your HuggingFace token ready for model downloads

### Step 1: Verify GPU and Docker Setup

SSH into your GPU backend and verify the setup:

```bash
ssh stella-llm

# Verify NVIDIA GPU is available
nvidia-smi

# Verify Docker is installed and accessible
docker --version
docker compose version
docker ps

# Check available disk space
df -h /
```

Expected output from `nvidia-smi` should show your NVIDIA GPU (e.g., GB10) with driver and CUDA version.

### Step 2: Create Directory Structure

Create a centralized directory structure for models, cache, and services:

```bash
# Create shared directories for models and cache (used across all AI services)
mkdir -p ~/ai-shared/models/huggingface
mkdir -p ~/ai-shared/cache/huggingface

# Create service-specific directories
mkdir -p ~/vllm-gb10         # vLLM source code with GB10 patches
mkdir -p ~/vllm-service      # Service configuration and logs

# Verify structure
ls -la ~/ | grep -E 'ai-shared|vllm'
```

**Directory structure explained:**
- `~/ai-shared/` - Centralized storage for models and cache (shared across all AI services)
  - Models downloaded once, reused across restarts and different inference engines
  - Cache for HuggingFace downloads
- `~/vllm-gb10/` - vLLM source code with GB10/Blackwell support patches
- `~/vllm-service/` - Service configuration, docker-compose, and logs

### Step 3: Clone vLLM with GB10 Support

Clone the vLLM repository with GB10/Blackwell support patches from PR #31740:

```bash
cd ~/vllm-gb10

# Clone the branch with GB10 support from the PR author
git clone --branch feature/sm121-gb10-support https://github.com/seli-equinix/vllm.git .

# Verify the GB10 patches are present
git log --oneline -5

# Check for Blackwell-class detection code
grep -r "is_blackwell_class" vllm/platforms/
```

**What is PR #31740?**
- Adds SM121/GB10 (DGX Spark) Blackwell-class GPU support
- Tested by the author on DGX Spark with GB10 GPU
- Extends vLLM support from SM100/SM103 to SM10x/11x/12x family
- Includes performance optimizations for Grace Blackwell architecture

### Step 4: Create vLLM Dockerfile with GB10 Support

Create a custom Dockerfile that builds vLLM with full GB10 support:

```bash
cd ~/vllm-gb10

cat > Dockerfile.gb10 << 'EOF'
# Start from vLLM's official nightly build which has PyTorch 2.9.1 pre-installed
FROM vllm/vllm-openai:nightly

# Switch to root to install dependencies
USER root

# Install full CUDA toolkit (needed for nvcc and nvrtc during compilation)
RUN apt-get update && apt-get install -y \
    git \
    libnuma-dev \
    cuda-toolkit-12-4 \
    && rm -rf /var/lib/apt/lists/*

# Install transformers from main branch (for GLM-4.7-Flash glm4_moe_lite support)
RUN pip3 install --no-cache-dir git+https://github.com/huggingface/transformers.git@main

# Copy the GB10-patched vLLM source
WORKDIR /workspace/vllm-gb10
COPY . .

# Set environment variables for the entire build process
ENV VLLM_VERSION_OVERRIDE="0.14.0+gb10"
ENV SETUPTOOLS_SCM_PRETEND_VERSION="0.14.0+gb10"
ENV VLLM_INSTALL_PUNICA_KERNELS=1
ENV MAX_JOBS=16
ENV NVCC_THREADS=16
ENV CMAKE_BUILD_PARALLEL_LEVEL=16
ENV VLLM_TARGET_DEVICE=cuda
ENV CUDA_HOME=/usr/local/cuda-12.4
ENV CUDA_PATH=/usr/local/cuda-12.4
ENV PATH=/usr/local/cuda-12.4/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda-12.4/lib64:${LD_LIBRARY_PATH}
ENV LIBRARY_PATH=/usr/local/cuda-12.4/lib64:${LIBRARY_PATH}
ENV TORCH_CUDA_ARCH_LIST="8.0 8.6 8.9 9.0 12.1"

# Install build dependencies manually to avoid isolated build
RUN pip3 install --no-cache-dir ninja cmake wheel setuptools-scm

# Uninstall the existing vLLM and install the GB10-patched version with --no-build-isolation
RUN pip3 uninstall -y vllm && pip3 install --no-cache-dir --no-build-isolation -v .

# Set working directory
WORKDIR /workspace

# Switch back to vllm user for security
USER vllm

# Expose port
EXPOSE 8000

# Default command
CMD ["python3", "-m", "vllm.entrypoints.openai.api_server"]
EOF
```

**Dockerfile explained:**
- **Base image:** vLLM official nightly (includes PyTorch 2.9.1, CUDA runtime)
- **CUDA toolkit:** Full toolkit installation for compiling CUDA kernels
- **Transformers main:** Required for GLM-4.7-Flash's `glm4_moe_lite` architecture
- **Build parallelism:** MAX_JOBS=16 leverages your 20 CPU cores
- **TORCH_CUDA_ARCH_LIST:** Includes 12.1 for GB10 support
- **--no-build-isolation:** Ensures our environment variables are respected

### Step 5: Build Custom Docker Image

Build the vLLM Docker image with GB10 support:

```bash
cd ~/vllm-gb10

docker build -f Dockerfile.gb10 -t vllm-gb10:latest . 2>&1 | tee build.log
```

**Build time:** ~1-2 hours depending on system
- CUDA toolkit download: 15-20 minutes (~4GB)
- Compilation of 419 CUDA kernel files: 45-90 minutes
- Using 16 parallel jobs to maximize your 20-core CPU

**What's being compiled:**
- **Attention kernels:** Paged attention, Flash Attention 2/3
- **Quantization kernels:** FP8, INT8, FP4, GPTQ, Marlin
- **MoE kernels:** Expert routing and computation for GLM-4.7-Flash
- **Cache management:** KV cache operations
- **All quantization formats:** So you can use any model (FP8, FP4, etc.)

**Monitoring the build:**
```bash
# In another terminal, monitor compilation progress
tail -f ~/vllm-gb10/build.log | grep -E '\[[0-9]+/419\]'

# Check CPU usage (should see 12-16 cores active)
btop   # or: htop

# Check if build is still running
ps aux | grep 'docker build'
```

**Build progress indicators:**
```
[50/419]  Building CUDA... (~12% complete)
[100/419] Building CUDA... (~24% complete)
[200/419] Building CUDA... (~48% complete)
[400/419] Building CUDA... (~95% complete)
```

**Why the build takes so long:**
1. **419 CUDA files to compile** - each optimized for multiple GPU architectures
2. **CUDA compilation is complex** - PTX, assembly, optimization passes
3. **GB10 is cutting-edge** - compute capability 12.1 requires latest everything
4. **Multiple architectures** - Compiling for sm_80, 8.6, 8.9, 9.0, AND 12.1

The good news: **This is a one-time cost!** Once built:
- Image is reusable forever
- Works with any transformer model (GLM, Qwen, Llama, etc.)
- No rebuild needed unless vLLM updates

### Step 5: Verify Build Success

After the build completes, verify the image was created:

```bash
# Check if image exists
docker images | grep sglang-custom

# Expected output:
# sglang-custom   glm47-flash   <image-id>   <time>   <size>
```

### Step 6: Set Up HuggingFace Token

Create an environment file with your HuggingFace token:

```bash
cd ~/sglang-service

# Create .env file
echo 'HF_TOKEN=your_huggingface_token_here' > .env

# Secure the file
chmod 600 .env
```

To get a HuggingFace token:
1. Go to https://huggingface.co/settings/tokens
2. Create a new token with read access
3. Copy the token and replace `your_huggingface_token_here` above

### Step 7: Create Docker Compose Configuration

Create a `docker-compose.yml` file that uses your custom image:

```bash
cd ~/sglang-service
nano docker-compose.yml
```

Add the following configuration:

```yaml
services:
  sglang-glm47-flash:
    image: sglang-custom:glm47-flash
    container_name: sglang-agent-code
    restart: unless-stopped
    ports:
      - "8000:8000"
    environment:
      - HF_TOKEN=${HF_TOKEN}
      - HF_HOME=/shared/cache/huggingface
      - CUDA_VISIBLE_DEVICES=0
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=compute,utility
    volumes:
      - ~/ai-shared/cache/huggingface:/shared/cache/huggingface
      - ~/ai-shared/models:/shared/models
      - ./logs:/logs
    command:
      - python3
      - -m
      - sglang.launch_server
      - --model-path
      - zai-org/GLM-4.7-Flash
      - --host
      - 0.0.0.0
      - --port
      - "8000"
      - --tp-size
      - "1"
      - --context-length
      - "8192"
      - --trust-remote-code
      - --mem-fraction-static
      - "0.90"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    shm_size: '32gb'
    ulimits:
      memlock: -1
      stack: 67108864
```

**Configuration explained:**
- `image: sglang-custom:glm47-flash` - Uses your custom-built image
- `ports: "8000:8000"` - Expose API on port 8000 (OpenAI-compatible endpoint)
- `~/ai-shared/cache/huggingface` - Shared model cache (saves re-downloading)
- `--model-path zai-org/GLM-4.7-Flash` - The GLM-4.7-Flash model (30B parameters, ~60GB)
- `--tp-size 1` - Tensor parallelism size (1 = single GPU)
- `--context-length 8192` - Maximum context window
- `--trust-remote-code` - Required for GLM-4.7-Flash model architecture
- `--mem-fraction-static 0.90` - Use 90% of GPU memory
- `shm_size: '32gb'` - Shared memory for efficient inference

### Step 8: Start SGLang Service

Start the SGLang container:

```bash
cd ~/sglang-service
docker compose up -d
```

This will:
1. Start the container using your custom image
2. Download the GLM-4.7-Flash model (~60GB - first run only, saved to shared cache)
3. Load the model into GPU memory
4. Start the inference server

### Step 9: Monitor Startup

Monitor the logs to see the model loading progress:

```bash
# Follow logs in real-time
docker logs -f sglang-agent-code

# Or check last 50 lines
docker logs sglang-agent-code --tail 50
```

**What to look for:**
- Initial startup messages from SGLang
- Model download progress (if first time): `Downloading model from HuggingFace...`
- Model loading: `Loading model weights...`
- Server ready: `Uvicorn running on http://0.0.0.0:8000` or `Server is ready`

**Note:** Initial startup can take 20-40 minutes depending on:
- Network speed (for downloading the ~60GB model - first time only)
- GPU memory initialization
- Model loading and optimization

### Step 10: Verify Service is Running

Check that the container is running and the model is loaded:

```bash
# Check container status
docker ps | grep sglang

# Check GPU utilization - should show model loaded in memory
nvidia-smi

# Test API health endpoint
curl http://localhost:8000/health

# List available models
curl http://localhost:8000/v1/models
```

Expected response from `/v1/models`:
```json
{
  "object": "list",
  "data": [
    {
      "id": "zai-org/GLM-4.7-Flash",
      "object": "model",
      "created": 1234567890,
      "owned_by": "sglang"
    }
  ]
}
```

### Step 11: Test the API

Test a simple completion request:

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "zai-org/GLM-4.7-Flash",
    "messages": [
      {"role": "user", "content": "Hello! Can you write a simple Python function to add two numbers?"}
    ],
    "temperature": 0.7,
    "max_tokens": 500
  }'
```

You should receive a JSON response with the model's completion.

### Managing the Service

**Stop the service:**
```bash
cd ~/sglang
docker compose down
```

**Restart the service:**
```bash
cd ~/sglang
docker compose restart
```

**View logs:**
```bash
docker logs sglang-agent-code --tail 100 -f
```

**Update to latest image:**
```bash
cd ~/sglang
docker compose pull
docker compose up -d
```

### Troubleshooting

**Problem: Out of memory errors**
- Reduce `--mem-fraction-static` to 0.80 or 0.70
- Reduce `--context-length` to 4096 or 2048
- Ensure no other processes are using GPU memory

**Problem: Model download fails**
- Check HuggingFace token is correct in `.env` file
- Verify network connectivity: `curl https://huggingface.co`
- Check available disk space: `df -h`

**Problem: Container keeps restarting**
- Check logs: `docker logs sglang-agent-code`
- Verify GPU is accessible: `docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi`
- Check if port 8000 is already in use: `sudo lsof -i :8000`

**Problem: API returns errors**
- Verify model is fully loaded (check logs)
- Ensure request format matches OpenAI API spec
- Check temperature and max_tokens are within valid ranges

### Performance Tuning

For optimal performance, you can adjust:

1. **Memory allocation** (`--mem-fraction-static`):
   - Higher = more cache, better throughput
   - Lower = more stable, fewer OOM errors

2. **Context length** (`--context-length`):
   - Longer contexts use more memory
   - Adjust based on your use case

3. **Batch size** (automatic in SGLang):
   - SGLang automatically optimizes batching
   - Monitor with `nvidia-smi` for utilization

### OpenAI API Compatibility

SGLang exposes OpenAI-compatible endpoints:

- **Base URL:** `http://your-gpu-backend:8000`
- **Chat Completions:** `POST /v1/chat/completions`
- **Completions:** `POST /v1/completions`
- **Models:** `GET /v1/models`

Use these endpoints in OpenCode or any OpenAI-compatible client by setting:
- Base URL: `http://stella.home.arpa:8000`
- Model: `zai-org/GLM-4.7-Flash`
- API Key: Not required (leave empty or use any value)

---

## Agent Configuration

### Configuring OpenCode to Use SGLang

Once SGLang is running on your GPU backend, configure OpenCode to use it:

1. **Open OpenCode Settings**
   - In OpenCode, go to Settings/Preferences
   - Navigate to AI Provider settings

2. **Add Custom OpenAI Endpoint**
   - Provider: OpenAI Compatible
   - Base URL: `http://stella.home.arpa:8000`
   - Model: `zai-org/GLM-4.7-Flash`
   - API Key: `dummy` (not required but some clients need a value)

3. **Test Connection**
   - Send a test request to verify connectivity
   - Check that responses are being generated

### Example OpenCode Configuration

If OpenCode uses a configuration file:

```json
{
  "ai_providers": [
    {
      "name": "Agent Code (GLM-4.7-Flash)",
      "type": "openai",
      "base_url": "http://stella.home.arpa:8000",
      "model": "zai-org/GLM-4.7-Flash",
      "api_key": "not-needed"
    }
  ]
}
```

### Testing the Setup

Test the complete setup:

1. **From your frontend machine**, test API access:
   ```bash
   curl http://stella.home.arpa:8000/v1/models
   ```

2. **In OpenCode**, create a new chat or coding task

3. **Verify** that responses are coming from your local GLM-4.7-Flash model

---

## Next Steps

- Set up the second GPU backend (Lenovo ThinkStation) for Agent Architect
- Configure additional models as needed
- Implement monitoring and logging
- Optimize performance based on usage patterns
