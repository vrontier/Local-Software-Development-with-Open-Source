# vLLM GB10 Project Files

This document lists all the custom files created for the open-source release.

## Core Files

### Docker & Build
-  - Custom Dockerfile with GB10 support and multi-architecture compilation
-  - Production-ready docker-compose configuration template
-  - Environment variable template

### Documentation
-  - Main project documentation
-  - Contribution guidelines
-  - Step-by-step publishing guide
-  - This file

### Scripts
-  - Automated publishing to Docker Hub and GHCR
-  - Build progress monitor

### Configuration
-  - Git ignore patterns
-  - MIT license with vLLM attribution
-  - GitHub Actions workflow (optional)

## Supporting Files (In ~/vllm-service/)

These files are for deployment, not for the public repository:

-  - Service deployment script
-  - Service monitoring script  
-  - Inference testing script
-  - Production configuration (with actual tokens)
-  - Production environment variables (with actual tokens)

## Files NOT to Publish

**Do not publish:**
-  - Contains local paths and build details
-  (without .example) - Contains actual tokens
-  (without .example) - May contain production secrets
- Any files in  or  - These are large model files

## Publishing Checklist

Before pushing to GitHub:

1. ✅ Reviewed README.md
2. ✅ Updated all YOUR_USERNAME placeholders
3. ✅ Removed any secrets/tokens
4. ✅ Tested docker-compose.example.yml
5. ✅ Added .gitignore to prevent accidental commits
6. ✅ Chose appropriate LICENSE
7. ✅ Created meaningful commit messages

## Repository Structure



## File Sizes (Approximate)

- Dockerfile.gb10: ~2 KB
- README.md: ~6 KB  
- CONTRIBUTING.md: ~3 KB
- PUBLISHING.md: ~6 KB
- docker-compose.example.yml: ~2 KB
- publish.sh: ~3 KB
- Total documentation: ~25 KB

## vLLM Source Code

The bulk of the repository is the vLLM source code from the GB10 support PR:
- Branch: 
- Origin: https://github.com/seli-equinix/vllm.git
- Upstream PR: https://github.com/vllm-project/vllm/pull/31740

**Credit:** @seli-equinix for GB10 patches
