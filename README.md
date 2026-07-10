# Puget Systems Docker App Packs

A standardized, high-performance starter template system for AI and engineering workflows on Puget Systems workstations.

## Overview

This repository uses an **App Pack** architecture. It provides specialized "Flavors" (Stacks) that serve as reliable foundations for your containerized applications, from basic Python scripts to multi-GPU inference servers.

**Supported Hardware** (the installer auto-detects your vendor — no branch or flag to pick):
*   **Standard**: Any x86_64 system with Docker
*   **NVIDIA**: CUDA 12.6+ (Ada / RTX 4090, etc.)
*   **NVIDIA Blackwell**: RTX 5090 / RTX PRO 6000 / GB10 (CUDA 13.0, auto-detected)
*   **AMD**: ROCm on RDNA4 (Radeon AI PRO R9700 / RX 9070)
*   **Intel**: Arc Pro B70 (Battlemage) via the XPU backend

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
*   **Engine**: Ollama on NVIDIA/Intel; **llama.cpp** on AMD (both GPU-accelerated, easy model swapping)
*   **Interface**: Open WebUI (ChatGPT-like)
*   **Best For**: Personal workstations, one-command model management

### 4. Team LLM
*   **Target**: Production Multi-User Inference
*   **Engine**: vLLM on NVIDIA/Intel; **llama.cpp** (layer-split GGUF) on AMD — vLLM FP8 available via `TEAM_AMD_ENGINE=vllm` (all OpenAI-compatible API)
*   **Interface**: Open WebUI
*   **Models**: Qwen 3.6 (35B MoE, 27B Dense), Qwen 3.5 MoE (35B, 122B), DeepSeek R1 70B, Nemotron 3 (Nano/Super NVFP4), GPT-OSS (20B/120B), Gemma 4 26B. The exact menu is vendor-specific (NVIDIA pre-quantized AWQ/NVFP4, AMD online FP8, Intel FP16) and VRAM-gated on your hardware.
*   **Best For**: Shared workstations, teams needing a single high-throughput endpoint

---

## Quick Start

### One-Line Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/Puget-Systems/puget-docker-app-packs/main/setup.sh -o setup.sh && bash setup.sh
```

**One install path for every GPU.** The installer auto-detects your vendor
(NVIDIA / AMD / Intel) and architecture (including Blackwell → CUDA 13) and
selects the right container images and model menu — there is no per-vendor
branch or flag to choose. The interactive wizard will:
1.  Install Docker, GPU drivers, and (NVIDIA) the Container Toolkit if needed
2.  Prompt you to select a Flavor
3.  Configure GPU settings and model selection (for LLM packs)
4.  Build and launch the stack

### Manual Install

```bash
git clone https://github.com/Puget-Systems/puget-docker-app-packs.git
cd puget-docker-app-packs
./install.sh
```

> **Testing the develop branch (pre-release):** the unified installer currently
> lives on `develop` while it's validated across NVIDIA/AMD/Intel hardware. Until
> it merges to `main`, test it with:
> ```bash
> curl -fsSL https://raw.githubusercontent.com/Puget-Systems/puget-docker-app-packs/develop/setup.sh -o setup.sh && BRANCH=develop bash setup.sh
> ```

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
- **Blackwell (RTX 5090 / PRO 6000 / GB10)**: `sudo apt install nvidia-driver-580-open` (open kernel modules required)
- Driver ≥580 is required for the CUDA 13 (`cu130`) model images used on Blackwell; ≥570 for the CUDA 12.8 stable images. Verify: `nvidia-smi`

### NVIDIA Container Toolkit (GPU Stacks)
- The installer will offer to install this automatically
- Manual: [NVIDIA Container Toolkit Install Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

### Intel Arc Drivers (B70 / Battlemage)
- **Required for**: Intel Arc GPUs (auto-detected — no separate branch)
- The installer **auto-detects** the Intel GPU and offers to install the Intel Compute Runtime (`intel-opencl-icd`, `libze-intel-gpu1`, `clinfo`, …) — no manual step needed in most cases.
- For the newest Battlemage drivers (26.09.x+), add the `kobuk-team/intel-graphics` PPA *before* running the installer:
  ```bash
  sudo add-apt-repository -y ppa:kobuk-team/intel-graphics && sudo apt update
  ```
- Verify: `clinfo | grep "Device Name"`

---

## Integrity Verification

The bootstrap installer (`setup.sh`) automatically verifies the integrity of `install.sh` using an MD5 checksum before launching it. If the checksum doesn't match, the installer will exit with an error.

### For Developers

After editing `install.sh`, the checksum must be updated. This happens **automatically** via a git pre-commit hook. To activate the hook on a fresh clone:

```bash
git config core.hooksPath .githooks
```

Or update manually:

```bash
scripts/update_checksum.sh
```

---

## Repository Structure

```text
.
├── setup.sh                   # Bootstrap script (curl-friendly)
├── install.sh                 # Universal Interactive Installer
├── install.sh.md5             # MD5 checksum for integrity verification
├── packs/                     # Flavor Templates
│   ├── docker-base/           # Ubuntu 24.04 LTS Foundation
│   ├── comfy_ui/              # Creative Stack (CUDA + ComfyUI)
│   ├── personal_llm/          # Personal LLM (Ollama + Open WebUI)
│   └── team_llm/              # Team LLM (vLLM / llama.cpp on AMD + Open WebUI)
├── scripts/
│   ├── update_checksum.sh     # Regenerate install.sh.md5
│   └── lib/                   # Shared installer helpers
├── .githooks/
│   └── pre-commit             # Auto-updates checksum on commit
└── README.md
```
