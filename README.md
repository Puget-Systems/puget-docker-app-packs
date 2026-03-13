# Puget Systems Docker App Packs

A standardized, high-performance starter template system for AI and engineering workflows on Puget Systems workstations.

## Overview

This repository uses an **App Pack** architecture. It provides specialized "Flavors" (Stacks) that serve as reliable foundations for your containerized applications, from basic Python scripts to multi-GPU inference servers.

**Supported Hardware**:
*   **Standard**: Any x86_64 system with Docker
*   **Accelerated**: NVIDIA GPUs with CUDA 12.6+ (Ada / RTX 4090, etc.)
*   **Blackwell**: RTX 5090 / RTX PRO 6000 (CUDA 13.0, auto-detected)

## Available Flavors

### 1. Base (LTS)
*   **Target**: General Purpose Development
*   **OS**: Ubuntu 24.04 LTS
*   **Components**: `git`, `python3`, `pip`
*   **Best For**: Scripts, Data Processing, Cleaning

### 2. ComfyUI (Creative)
*   **Target**: Generative AI & Image/Video Synthesis
*   **Base**: NVIDIA CUDA 12.6 Runtime (Ubuntu 24.04)
*   **Stack**: ComfyUI (Latest), Manager-Ready
*   **Models**: Pro Image (Flux.2 Dev, Flux.1 Dev, HiDream), Standard Image (Flux.2 Klein, Flux.1 Schnell, SDXL Turbo, SD 3.5 Medium), Pro Video (LTX-Video 2B)
*   **Persistence**: Auto-maps `./models`, `./output`, `./input`, `./custom_nodes` to host

### 3. Personal LLM
*   **Target**: Single-User AI Assistant
*   **Engine**: Ollama (GPU-accelerated, easy model swapping)
*   **Interface**: Open WebUI (ChatGPT-like)
*   **Best For**: Personal workstations, one-command model management

### 4. Team LLM
*   **Target**: Production Multi-User Inference
*   **Engine**: vLLM (multi-GPU tensor parallelism, OpenAI-compatible API)
*   **Interface**: Open WebUI
*   **Models**: Qwen 3 (8B, 32B FP8), Qwen 3.5 MoE (35B, 122B — Coming Soon on Blackwell), DeepSeek R1 70B AWQ
*   **Best For**: Shared workstations, teams needing a single high-throughput endpoint

---

## Quick Start

### One-Line Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/Puget-Systems/puget-docker-app-pack/main/setup.sh -o setup.sh && bash setup.sh
```

The interactive wizard will:
1.  Install Docker, NVIDIA drivers, and Container Toolkit (if needed)
2.  Prompt you to select a Flavor
3.  Configure GPU settings and model selection (for LLM packs)
4.  Build and launch the stack

### Manual Install

```bash
git clone https://github.com/Puget-Systems/puget-docker-app-pack.git
cd puget-docker-app-pack
./install.sh
```

### Develop Branch

For the latest features (not yet released):

```bash
curl -fsSL https://raw.githubusercontent.com/Puget-Systems/puget-docker-app-pack/develop/setup.sh -o setup.sh && BRANCH=develop bash setup.sh
```

---

## Prerequisites

### Docker
- **Required for all stacks**
- Ubuntu: `sudo apt install docker.io docker-compose-v2`
- **⚠️ Important**: Docker requires `sudo` unless your user is in the `docker` group:
  ```bash
  sudo usermod -aG docker $USER
  # Then LOG OUT and back in!
  ```

### NVIDIA Drivers (GPU Stacks)
- **Required for**: ComfyUI, Personal LLM, Team LLM
- **Ada (RTX 4090)**: `sudo apt install nvidia-driver-550` (driver 550+)
- **Blackwell (RTX 5090)**: `sudo apt install nvidia-driver-580-open` (open kernel modules required)
- Verify: `nvidia-smi`

### NVIDIA Container Toolkit (GPU Stacks)
- The installer will offer to install this automatically
- Manual: [NVIDIA Container Toolkit Install Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

---

## Repository Structure

```text
.
├── setup.sh               # Bootstrap script (curl-friendly)
├── install.sh             # Universal Interactive Installer
├── packs/                 # Flavor Templates
│   ├── docker-base/       # Ubuntu 24.04 LTS Foundation
│   ├── comfy_ui/          # Creative Stack (CUDA + ComfyUI)
│   ├── personal_llm/      # Personal LLM (Ollama + Open WebUI)
│   └── team_llm/          # Team LLM (vLLM + Open WebUI)
├── SOP_AI_PRELOAD_v0.5.0.md  # Puget Systems internal SOP
└── README.md
```
