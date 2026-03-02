# SOP: AI Software Preloads for Outgoing Systems

#### Document Info
*   Authors: Dustin, 🤖
*   Last Updated: Feb 21, 2026
*   Version: 0.5.0
*   Status: PRODUCTION / STAGING

## Overview
This Standard Operating Procedure (SOP) defines the baseline software provisioning for all outgoing Puget Systems workstations configured for AI workflows. This standardizes the deployment of containerized AI environments using the Puget Docker App Pack, ensuring customers receive a "ready-to-compute" system.

**Target OS:** Ubuntu 24.04 LTS
**Core Stack:** Docker + NVIDIA Container Toolkit + OpenVINO (Testing)

---

## Phase 1: OS & Dependency Preparation

1. **Verify OS:** Ensure the system is running a fresh installation of Ubuntu 24.04 LTS.
2. **Execute the Universal Installer:**
   Open a terminal and run the one-line bootstrap script:
   ```bash
   sh -c "$(curl -fsSL https://raw.githubusercontent.com/Puget-Systems/puget-docker-app-pack/main/setup.sh)"
   ```
3. **Follow Installer Prompts:**
   - **Docker:** Allow the script to install Docker CE and the Compose plugin. The script will automatically add the user to the `docker` group.
   - **NVIDIA Drivers:** Allow the script to auto-detect your GPU and install the recommended driver (including open kernel modules for Blackwell/RTX 50 series).
   - *Crucial:* If the NVIDIA drivers are installed during this step, a **system reboot is strictly required** before proceeding.

## Phase 2: GPU Toolkit & Environment Provisioning

1. **Re-run Installer (If Rebooted):** 
   If a reboot was required, run the bootstrap script again to resume setup.
2. **NVIDIA Container Toolkit:**
   Allow the script to install the toolkit and automatically configure the Docker runtime (`nvidia-ctk`) for GPU passthrough.
3. **Select Flavor:** 
   Select the appropriate App Pack based on the customer's sales order:
   - `comfy_ui`: Generative AI / Creative stacks
   - `personal_llm`: Personal LLM (Ollama — single user, easy model swapping)
   - `team_llm`: Team LLM (vLLM — multi-user, multi-GPU tensor parallelism)
   - `docker-base`: General data science

## Phase 3: Validation & Quality Control (QC)

Before the system is cleared for shipping, execute the following validations:

### 1. GPU Passthrough Verification
Ensure the Docker daemon can successfully allocate GPUs to containers.
```bash
docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi
```
*Expected Result:* Displays the NVIDIA SMI table recognizing all installed GPUs inside the isolated container environment.

### 2. OpenVINO Validation (CPU PCIe / Memory Bandwidth)
*Context: We utilize OpenVINO for CPU PCIe Lanes & Memory Bandwidth benchmarking for Foundation-tier multi-inference.*
- Deploy the designated OpenVINO benchmark container/script.
- Verify that memory bandwidth and PCIe lane throughput meet the Puget Systems baseline standards for the specific CPU/Motherboard SKU.

### 3. Auto-Start Check
If the customer requested an "always-on" stack (like Team LLM or Personal LLM), verify the user opted-in to the installer's auto-start prompt, ensuring containers use the `restart: unless-stopped` Docker policy.