# Publishing Guide for vLLM GB10

## Quick Publish Checklist

- [ ] Build completed successfully
- [ ] Image tested locally
- [ ] README.md updated with your usernames
- [ ] Docker Hub account created
- [ ] GitHub repository created
- [ ] Logged in to registries

## Step 1: Create Accounts

### Docker Hub
1. Go to https://hub.docker.com/signup
2. Create account (free tier is fine)
3. Verify email
4. Note your username

### GitHub Container Registry
1. Already have GitHub account
2. Create Personal Access Token:
   - Go to Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Generate new token
   - Scopes needed: , , 
   - Save token securely

## Step 2: Set Environment Variables

```bash
# On stella
export DOCKERHUB_USERNAME="your-dockerhub-username"
export GITHUB_USERNAME="your-github-username"
export GITHUB_TOKEN="ghp_your_github_token_here"

# Verify
echo $DOCKERHUB_USERNAME
echo $GITHUB_USERNAME
```

## Step 3: Login to Registries

```bash
# Docker Hub
docker login -u $DOCKERHUB_USERNAME

# GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_USERNAME --password-stdin
```

## Step 4: Update README

```bash
cd ~/vllm-gb10

# Replace placeholder with your username
sed -i "s/YOUR_DOCKERHUB_USERNAME/$DOCKERHUB_USERNAME/g" README.md
sed -i "s/YOUR_DOCKERHUB_USERNAME/$DOCKERHUB_USERNAME/g" docker-compose.example.yml

# Review changes
git diff README.md
```

## Step 5: Publish Images

```bash
cd ~/vllm-gb10
./publish.sh
```

This will:
- Tag image with version, date, and latest
- Push to Docker Hub
- Push to GitHub Container Registry
- Show pull commands

## Step 6: Create GitHub Repository

```bash
# Initialize git (if not already done)
cd ~/vllm-gb10
git init
git add .
git commit -m "Initial commit: vLLM with GB10 support"

# Create GitHub repo (using gh CLI)
gh repo create vllm-gb10 --public --source=. --remote=origin

# Or manually:
# 1. Go to https://github.com/new
# 2. Name: vllm-gb10
# 3. Public
# 4. No template
# 5. Create repository
# 6. Follow instructions to push existing repo

# Push to GitHub
git branch -M main
git remote add origin git@github.com:$GITHUB_USERNAME/vllm-gb10.git
git push -u origin main

# Create release tag
git tag -a v1.0.0 -m "Initial release with GB10 support"
git push origin v1.0.0
```

## Step 7: Configure GitHub Repository

### Topics/Tags
Add these topics to your GitHub repo:
- 
- 
- 
- 
- 
- 
- 
- 
- 

### Description
"High-performance vLLM inference server with native NVIDIA GB10 (Grace Blackwell) support"

### Enable Features
- Issues: ✅
- Discussions: ✅
- Wiki: Optional
- Projects: Optional

## Step 8: Create GitHub Release

1. Go to your repo → Releases → Create new release
2. Tag: 
3. Title: "vLLM GB10 v1.0.0 - Initial Release"
4. Description:
   ```markdown
   ## 🚀 Initial Release
   
   First public release of vLLM with native NVIDIA GB10 (Grace Blackwell) support!
   
   ### ✨ Features
   - Native GB10/Blackwell support (compute capability 12.1)
   - Multi-architecture support (sm_80, sm_86, sm_89, sm_90, sm_121)
   - Based on vLLM PR #31740
   - Tested with GLM-4.7-Flash (30B MoE)
   - OpenAI-compatible API
   - Docker-based deployment
   
   ### 📦 Docker Images
   
   **Docker Hub:**
   ```bash
   docker pull YOUR_USERNAME/vllm-gb10:latest
   docker pull YOUR_USERNAME/vllm-gb10:v1.0.0
   ```
   
   **GitHub Container Registry:**
   ```bash
   docker pull ghcr.io/YOUR_USERNAME/vllm-gb10:latest
   docker pull ghcr.io/YOUR_USERNAME/vllm-gb10:v1.0.0
   ```
   
   ### 📚 Documentation
   
   See [README.md](README.md) for full documentation.
   
   ### 🙏 Credits
   
   - vLLM Project: https://github.com/vllm-project/vllm
   - GB10 Support: @seli-equinix (PR #31740)
   
   ### 🐛 Known Issues
   
   - Build time is ~3-4 hours on 20-core system
   - Requires CUDA 12.4+ drivers
   
   Please report any issues!
   ```
5. Publish release

## Step 9: Share with Community

### Reddit
- r/LocalLLaMA - "vLLM with native GB10/Blackwell support"
- r/MachineLearning - "New: vLLM Docker image for NVIDIA GB10"

### Twitter/X
"Just released vLLM with native NVIDIA GB10 (Blackwell) support! 🚀
- Multi-GPU architecture support
- Docker-based deployment
- OpenAI compatible API
- Tested with 30B MoE models

https://github.com/YOUR_USERNAME/vllm-gb10

#AI #NVIDIA #Blackwell #vLLM"

### HuggingFace Forums
Post in Discussions about availability for GB10 users

### NVIDIA Developer Forums
Share in CUDA/GPU Computing section

### Discord Communities
- vLLM Discord
- LocalLLaMA Discord
- AI/ML servers

## Verification

Test that others can use your published image:

```bash
# Remove local image
docker rmi vllm-gb10:latest

# Pull from Docker Hub
docker pull $DOCKERHUB_USERNAME/vllm-gb10:latest

# Test run
docker run --gpus all -p 8000:8000 $DOCKERHUB_USERNAME/vllm-gb10:latest \
  --model zai-org/GLM-4.7-Flash --trust-remote-code

# Test from another machine
curl http://your-server:8000/health
```

## Maintenance

### Future Updates

When you make changes:

```bash
# Update version in publish.sh
VERSION="1.1.0"

# Rebuild
docker build -f Dockerfile.gb10 -t vllm-gb10:latest .

# Publish
./publish.sh

# Tag in git
git tag v1.1.0
git push origin v1.1.0

# Create GitHub release
```

### Monitor Issues

- Respond to GitHub issues promptly
- Label them appropriately (bug, enhancement, question)
- Thank contributors!

## Success Metrics

Track:
- Docker Hub pulls
- GitHub stars
- Issues/PRs
- Community feedback
- Performance reports from different GPUs

## Support

If you need help:
- Check Docker Hub/GHCR documentation
- GitHub docs on Container Registry
- Ask in vLLM community channels

---

**Thank you for contributing to open source!** 🎉
