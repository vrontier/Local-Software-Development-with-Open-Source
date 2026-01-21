# Local Software Development with Open Source
This guide describes how-to setup Open Source tooling and intelligence for local Software Development. The guide focusses on using NVIDIA's Blackwell GPU architecture as compute platform. The general approach however can be applied to other GPU architectures from NVIDIA, AMD, Apple Silicon or INTEL as well.

# Prerequisites

## My hardware set-up 
* Apple Mac Studio as front-end (can be an desktop or laptop computer with any OS that 
* ASUS Ascent GX10 as AI backend for "Agent Code" and "Agent Test" (Nvidia GB10 Grace Blackwell 128GB VRAM)
* Lenovo ThinkStation PGX GB10 as AI backend for "Agent Architect" (Nvidia GB10 Grace Blackwell 128GB VRAM)

## Software used
* Opencode
* vLLM

## LLMs used
* Agent Code: Z.ai's GLM-4.7-Flash 30b (https://z.ai/blog/glm-4.7)
* Agent Architect: OpenAI's GPT-OSS 120b (https://platform.openai.com/docs/models/gpt-oss-120b)
* Agent Test: tbd

# Approach

* Setup and configuration of tooling and intelligence
* Design and implementation of an example project
