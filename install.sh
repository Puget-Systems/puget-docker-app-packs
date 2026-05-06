#!/bin/bash
set -euo pipefail

# Puget Systems Docker App Pack - Universal Installer
# Standards: Ubuntu 24.04 LTS target, /home/puget-app-pack/app pathing

# ANSI Color Codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Source shared helpers ---
INSTALLER_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$INSTALLER_DIR/scripts/lib/gpu_detect.sh"
source "$INSTALLER_DIR/scripts/lib/smart_build.sh"
source "$INSTALLER_DIR/scripts/lib/vllm_monitor.sh"
source "$INSTALLER_DIR/scripts/lib/vllm_model_select.sh"
source "$INSTALLER_DIR/scripts/lib/ollama_model_select.sh"
source "$INSTALLER_DIR/scripts/lib/env_write.sh"

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}   Puget Systems Docker App Pack - Universal Installer${NC}"
echo -e "${BLUE}============================================================${NC}"

# 0. Distribution Compatibility Check
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "ubuntu" ]; then
        echo -e "\n${RED}✗ Unsupported Linux distribution: ${ID:-unknown}${NC}"
        echo -e "  The Puget Docker App Pack currently supports ${GREEN}Ubuntu${NC} only."
        echo -e "  (Detected: $PRETTY_NAME)"
        exit 1
    fi
else
    echo -e "\n${RED}✗ Cannot detect Linux distribution (/etc/os-release not found).${NC}"
    echo -e "  The Puget Docker App Pack requires ${GREEN}Ubuntu${NC}."
    exit 1
fi

# 1. Prerequisite Checks
echo -e "\n${YELLOW}[Preflight] Checking dependencies...${NC}"

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker is not installed.${NC}"
    read -p "  Would you like to install Docker now? (Y/n): " INSTALL_DOCKER
    if [[ "$INSTALL_DOCKER" != "n" && "$INSTALL_DOCKER" != "N" ]]; then
        echo -e "${BLUE}Installing Docker (Official Docker CE)...${NC}"
        
        # 1. Remove any old/conflicting packages
        sudo apt remove -y docker.io docker-doc docker-compose podman-docker containerd runc 2>/dev/null || true
        
        # 2. Install prerequisites
        sudo apt update
        sudo apt install -y ca-certificates curl gnupg
        
        # 3. Add Docker's official GPG key
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        
        # 4. Add the Docker repository
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # 5. Install Docker Engine + Compose Plugin
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        # 6. Add user to docker group
        sudo usermod -aG docker "$USER"
        
        echo -e "${GREEN}✓ Docker installed.${NC}"
        echo -e "${YELLOW}  Note: You may need to log out and back in for docker group changes.${NC}"
    fi
else
    echo -e "${GREEN}✓ Docker found.${NC}"
fi

# Reload with docker group if needed
if command -v docker &> /dev/null; then
    if groups | grep -q "\bdocker\b"; then
        # User is in group active session, good.
        :
    else
        if id -nG "$USER" | grep -qw "docker"; then
            echo -e "${YELLOW}User added to docker group but session not updated.${NC}"
            echo -e "${BLUE}Reloading installer with group permissions...${NC}"
            exec sg docker -c "\"$0\" \"$@\""
        fi
    fi
fi

# Check for Docker Compose (required for all stacks)
if ! docker compose version &> /dev/null; then
    echo -e "${RED}✗ Docker Compose plugin is not installed.${NC}"
    echo "  All stacks require 'docker compose' to run."
    read -p "  Would you like to install Docker Compose plugin now? (Y/n): " INSTALL_COMPOSE
    if [[ "$INSTALL_COMPOSE" != "n" && "$INSTALL_COMPOSE" != "N" ]]; then
        echo -e "${BLUE}Installing Docker Compose plugin...${NC}"
        
        # Ensure Docker repo is configured
        if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt update
        fi
        
        sudo apt install -y docker-compose-plugin
        echo -e "${GREEN}✓ Docker Compose plugin installed.${NC}"
    else
        echo -e "${RED}Cannot continue without Docker Compose.${NC}"
        exit 1
    fi
else
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓ Docker Compose found: ${COMPOSE_VERSION}${NC}"
fi

# Docker Group Warning (critical for Ubuntu)
echo ""
echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}⚠ IMPORTANT (Ubuntu/Debian users):${NC}"
echo -e "  Docker commands require ${RED}sudo${NC} unless your user is in the 'docker' group."
echo -e "  If you haven't already, run: ${GREEN}sudo usermod -aG docker \$USER${NC}"
echo -e "  Then ${RED}LOG OUT${NC} and back in for changes to take effect."
echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
echo ""

# Check for GPU Drivers and Runtimes
detect_gpus || true

if [ "$GPU_VENDOR" == "intel" ]; then
    echo -e "${GREEN}✓ Intel ARC GPU detected: $GPU_NAME ($GPU_COUNTx)${NC}"
    echo -e "${BLUE}Checking Intel Compute Runtime...${NC}"
    
    if ! dpkg -l | grep -q "intel-level-zero-gpu"; then
        echo -e "${RED}✗ Intel Level Zero / Compute Runtime not fully installed.${NC}"
        read -p "  Would you like to install Intel Compute Runtime now? (Y/n): " INSTALL_INTEL
        if [[ "$INSTALL_INTEL" != "n" && "$INSTALL_INTEL" != "N" ]]; then
            sudo apt update
            sudo apt install -y intel-opencl-icd intel-level-zero-gpu level-zero intel-media-va-driver-non-free clinfo
            echo -e "${GREEN}✓ Intel Compute Runtime installed.${NC}"
        else
            echo "  Skipping driver installation. GPU containers may fail to start."
        fi
    else
        echo -e "${GREEN}✓ Intel Compute Runtime found.${NC}"
    fi

    # Check for render nodes
    if ! ls /dev/dri/renderD* 1> /dev/null 2>&1; then
        echo -e "${RED}✗ Cannot access /dev/dri/renderD*. Docker passthrough will fail.${NC}"
    else
        echo -e "${GREEN}✓ GPU Render nodes available.${NC}"
    fi

elif [ "$GPU_VENDOR" == "nvidia" ] || command -v nvidia-smi &> /dev/null; then
    # We check if nvidia-smi exists AND returns success (0)
    if ! command -v nvidia-smi &> /dev/null || ! nvidia-smi &> /dev/null; then
        echo -e "${RED}✗ NVIDIA drivers not detected (or not active).${NC}"
        echo "  GPU-accelerated stacks (ComfyUI, Office Inference) require NVIDIA drivers."
        
        # Offer automated installation
        read -p "  Would you like to install the recommended NVIDIA drivers now? (Y/n): " INSTALL_DRIVERS
        if [[ "$INSTALL_DRIVERS" != "n" && "$INSTALL_DRIVERS" != "N" ]]; then
            # Ensure ubuntu-drivers-common is available (pre-installed on Ubuntu, but verify)
            if ! command -v ubuntu-drivers &> /dev/null; then
                echo -e "${BLUE}Installing driver detection tools...${NC}"
                sudo apt update && sudo apt install -y ubuntu-drivers-common
            fi
            
            # Show detected GPU and recommended driver
            echo -e "${BLUE}Detecting GPU hardware...${NC}"
            ubuntu-drivers devices 2>/dev/null || true
            echo ""
            
            echo -e "${BLUE}Installing recommended NVIDIA drivers for your GPU...${NC}"
            DRIVER_OUTPUT=$(sudo ubuntu-drivers install 2>&1)
            DRIVER_EXIT=$?
            echo "$DRIVER_OUTPUT"
            
            if [ $DRIVER_EXIT -ne 0 ]; then
                echo -e "${RED}✗ Driver installation failed.${NC}"
                echo "  You may need to install drivers manually."
                echo "  Try: sudo apt update && sudo ubuntu-drivers install"
                exit 1
            fi
            
            # Check if anything was actually installed (vs already at newest version)
            if echo "$DRIVER_OUTPUT" | grep -qE "(0 newly installed|already the newest version|No drivers found)"; then
                # Drivers are already installed but nvidia-smi still fails.
                # This is NOT a "just reboot" situation — something deeper is wrong.
                echo ""
                echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
                echo -e "${RED}⚠ NVIDIA drivers are installed but the GPU is not responding.${NC}"
                echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
                echo ""
                echo "  The driver package is already installed, but nvidia-smi cannot"
                echo "  communicate with the GPU. Common causes:"
                echo ""
                echo -e "  1. ${YELLOW}Secure Boot${NC} is blocking the unsigned NVIDIA kernel module."
                echo "     Check:  mokutil --sb-state"
                echo "     Fix:    sudo mokutil --disable-validation  (then reboot)"
                echo ""
                echo -e "  2. ${YELLOW}Kernel module not loaded${NC} after a kernel update."
                echo "     Check:  lsmod | grep nvidia"
                echo "     Fix:    sudo modprobe nvidia"
                echo ""
                echo -e "  3. ${YELLOW}Kernel/driver version mismatch${NC} (new kernel, old DKMS build)."
                echo "     Fix:    sudo ubuntu-drivers install"
                echo "             sudo dkms autoinstall"
                echo "             Then reboot."
                echo ""
                echo -e "  4. ${YELLOW}Wrong driver variant${NC} for your GPU generation."
                echo "     Check:  ubuntu-drivers devices"
                echo "     (Blackwell/RTX 50 series requires the '-open' kernel module variant)"
                echo ""
                echo "  Resolve the issue above and re-run this installer."
                exit 1
            else
                # Drivers were freshly installed — reboot is genuinely needed
                echo -e "${YELLOW}⚠ IMPORTANT: Drivers installed.${NC}"
                echo -e "${YELLOW}  You MUST REBOOT your system before the GPU will be available.${NC}"
                echo "  Please reboot and run this installer again."
                exit 0
            fi
        else
            echo "  Skipping driver installation. GPU containers may fail to start."
        fi
    else
        DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
        GPU_NAME=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | head -1)
        echo -e "${GREEN}✓ NVIDIA Driver found: $DRIVER_VERSION ($GPU_NAME)${NC}"
    fi

    # Check for NVIDIA Container Toolkit (required for GPU access)
    # Use `command -v nvidia-ctk` — dpkg -l can falsely report packages as present
    # when they are in a "desired but not installed" (un) state.
    if ! command -v nvidia-ctk &> /dev/null; then
        echo -e "${RED}✗ NVIDIA Container Toolkit is not installed.${NC}"
        echo "  This is required for Docker to access NVIDIA GPUs."
        read -p "  Would you like to install NVIDIA Container Toolkit now? (Y/n): " INSTALL_NVIDIA
        if [[ "$INSTALL_NVIDIA" != "n" && "$INSTALL_NVIDIA" != "N" ]]; then
            echo -e "${BLUE}Installing NVIDIA Container Toolkit...${NC}"
            # Add NVIDIA repo (--yes allows re-runs without "file already exists" error)
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
                sudo gpg --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
                sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
            sudo apt update && sudo apt install -y nvidia-container-toolkit
            echo -e "${GREEN}✓ NVIDIA Container Toolkit installed.${NC}"
        fi
    else
        echo -e "${GREEN}✓ NVIDIA Container Toolkit found.${NC}"
    fi

    # Hard gate: GPU stacks CANNOT work without the Container Toolkit.
    # Fail early with a clear message instead of a cryptic Docker error at launch.
    if ! command -v nvidia-ctk &> /dev/null; then
        echo ""
        echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}✗ NVIDIA Container Toolkit is required but not installed.${NC}"
        echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "  Without it, Docker cannot access NVIDIA GPUs and GPU-accelerated"
        echo "  containers (Ollama, vLLM, ComfyUI) will fail to start with:"
        echo ""
        echo -e "  ${YELLOW}could not select device driver \"nvidia\" with capabilities: [[gpu]]${NC}"
        echo ""
        echo "  Install manually with:"
        echo -e "  ${BLUE}curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \\"
        echo -e "    sudo gpg --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
        echo -e "  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \\"
        echo -e "    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \\"
        echo -e "    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list"
        echo -e "  sudo apt update && sudo apt install -y nvidia-container-toolkit${NC}"
        echo ""
        echo "  Then re-run this installer."
        exit 1
    fi

    # ALWAYS configure Docker for NVIDIA GPU access.
    # nvidia-ctk runtime configure is idempotent — safe to run every time.
    # We run it unconditionally because `docker info | grep nvidia` can false-positive
    # on the GPU device name (e.g. "NVIDIA GeForce RTX 5090") even when the runtime
    # is NOT actually registered.
    if command -v nvidia-ctk &> /dev/null && command -v docker &> /dev/null; then
        echo -e "${BLUE}Configuring Docker for NVIDIA GPU access...${NC}"
        sudo nvidia-ctk runtime configure --runtime=docker
        sudo systemctl restart docker

        # Wait for Docker to restart
        echo "Waiting for Docker to restart..."
        for i in {1..15}; do
            if docker info &> /dev/null 2>&1; then
                break
            fi
            sleep 1
        done

        echo -e "${GREEN}✓ Docker GPU runtime configured.${NC}"

        # Verify GPU access with a real container — this is the definitive test.
        echo "Verifying GPU access in Docker (this may pull an image on first run)..."
        if docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi &> /dev/null; then
            echo -e "${GREEN}✓ GPU accessible from Docker.${NC}"
        else
            echo ""
            echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
            echo -e "${RED}✗ Docker cannot access the NVIDIA GPU.${NC}"
            echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
            echo ""
            echo "  The NVIDIA driver works (nvidia-smi passed), and the Container"
            echo "  Toolkit is installed, but Docker still cannot access the GPU."
            echo ""
            echo "  Common causes:"
            echo -e "  1. ${YELLOW}Reboot required${NC} — the toolkit was just installed and the"
            echo "     kernel modules need to be reloaded."
            echo -e "     Fix: ${BLUE}sudo reboot${NC}, then re-run this installer."
            echo ""
            echo -e "  2. ${YELLOW}Toolkit/driver version mismatch${NC} — the container toolkit"
            echo "     version may not support this driver."
            echo -e "     Check: ${BLUE}nvidia-ctk --version${NC}"
            echo -e "     Fix:   ${BLUE}sudo apt update && sudo apt install --reinstall nvidia-container-toolkit${NC}"
            echo ""
            echo -e "  3. ${YELLOW}Docker daemon config conflict${NC} — /etc/docker/daemon.json"
            echo "     may have a conflicting configuration."
            echo -e "     Check: ${BLUE}cat /etc/docker/daemon.json${NC}"
            echo ""
            echo "  After fixing, re-run this installer."
            exit 1
        fi
    fi
else
    echo -e "${YELLOW}⚠ No NVIDIA or Intel GPUs detected. Only CPU workloads will be supported.${NC}"
fi

# Re-check after potential installs
if ! command -v docker &> /dev/null; then
    echo -e "\n${RED}Docker is still not available. Cannot continue.${NC}"
    echo "Please install Docker manually and run this installer again."
    exit 1
fi

# --- Configuration ---

# Resolve the directory where this script resides to find the packs
PACKS_DIR="$INSTALLER_DIR/packs"

if [ ! -d "$PACKS_DIR" ]; then
   echo -e "${RED}Error: 'packs' directory not found at $PACKS_DIR!${NC}"
   exit 1
fi

OPTIONS=()
for _d in "$PACKS_DIR"/*/; do
    OPTIONS+=("$(basename "$_d")")
done

if [ ${#OPTIONS[@]} -eq 0 ]; then
    echo -e "${RED}Error: No packs found in $PACKS_DIR.${NC}"
    exit 1
fi

# 1. Flavor Selection
echo -e "\n${YELLOW}[Step 1] Select Application Flavor${NC}"
echo "Different flavors are optimized for different use cases:"
echo "--------------------------------------------------------"

PS3="Select a flavor (enter number): "
select FLAVOR in "${OPTIONS[@]}"; do
    if [ -n "$FLAVOR" ]; then
        echo -e "Selected Flavor: ${GREEN}$FLAVOR${NC}"
        break
    else
        echo "Invalid selection. Please try again."
    fi
done

# 2. Directory Setup
DEFAULT_DIR="${FLAVOR:-my-puget-app}"
echo -e "\n${YELLOW}[Step 2] Configuration${NC}"
read -p "Enter installation directory name [${DEFAULT_DIR}]: " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_DIR}

if [ -d "$INSTALL_DIR" ]; then
    echo -e "${RED}Warning: Directory '$INSTALL_DIR' already exists.${NC}"
    read -p "Continue and potentially overwrite files? (y/N): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo "Installation aborted."
        exit 1
    fi
else
    mkdir -p "$INSTALL_DIR"
fi

# 3. Feature Selection (Placeholder for Phase 2)
# Future: Read 'features.json' from pack and prompt for mixins
echo -e "\n${YELLOW}[Step 3] Customization${NC}"
echo "Standard configuration selected."

# 4. Installation
echo -e "\n${YELLOW}[Step 4] Installing...${NC}"

# Copy Core Pack Files
cp -r "$PACKS_DIR/$FLAVOR/." "$INSTALL_DIR/"

# Copy shared libraries so pack scripts (init.sh) can source them at runtime
mkdir -p "$INSTALL_DIR/scripts/lib"
cp "$INSTALLER_DIR/scripts/lib/"*.sh "$INSTALL_DIR/scripts/lib/"

# Reset .env to a clean state on each install/re-install
# This prevents duplicate entries from stacking on re-runs
write_env_header "$INSTALL_DIR" "$INSTALL_DIR/.env"

echo -e "${GREEN}Success! Application installed to '$INSTALL_DIR'.${NC}"

# Per-Flavor Post-Install Guidance
echo -e "\n${YELLOW}[Post-Install: $FLAVOR]${NC}"
case $FLAVOR in
    comfy_ui)
        echo "ComfyUI requires AI models to generate images."
        
        # Create required directories with write permissions
        # Uses 777 because the container UID may not match the host UID.
        # These are single-user AI workstations, so broad permissions are acceptable.
        echo -e "${BLUE}Ensuring data directories exist and are writable...${NC}"
        COMFY_DIRS=("models" "models/checkpoints" "models/diffusion_models" "models/vae" "models/clip" "models/loras" "models/controlnet" "models/text_encoders" "models/xlabs" "models/xlabs/controlnets" "output" "input" "temp" "custom_nodes" "workflows" "user" "user/default")
        for dir in "${COMFY_DIRS[@]}"; do
            target="$INSTALL_DIR/$dir"
            if [ ! -d "$target" ]; then
                mkdir -p "$target"
            fi
            chmod 777 "$target"
        done

        # --- ComfyUI Manager (auto-install on first run) ---
        if [ ! -d "$INSTALL_DIR/custom_nodes/ComfyUI-Manager" ]; then
            echo ""
            echo -e "${BLUE}Installing ComfyUI Manager (server-side model & node management)...${NC}"
            git clone https://github.com/ltdrdata/ComfyUI-Manager.git "$INSTALL_DIR/custom_nodes/ComfyUI-Manager"
            echo -e "${GREEN}✓ ComfyUI Manager installed.${NC}"
        fi
        # Ensure Manager directory is writable by container (UID mismatch)
        chmod -R 777 "$INSTALL_DIR/custom_nodes/ComfyUI-Manager" 2>/dev/null || true

        # Install Puget model merge as a Manager startup script
        MANAGER_STARTUP="$INSTALL_DIR/custom_nodes/ComfyUI-Manager/__manager/startup-scripts"
        mkdir -p "$MANAGER_STARTUP"
        if [ -f "$INSTALL_DIR/puget_merge_startup.py" ]; then
            cp "$INSTALL_DIR/puget_merge_startup.py" "$MANAGER_STARTUP/puget_merge_startup.py"
            chmod 777 "$MANAGER_STARTUP/puget_merge_startup.py"
        fi
        chmod -R 777 "$INSTALL_DIR/custom_nodes/ComfyUI-Manager/__manager" 2>/dev/null || true

        # GPU Detection for VRAM gating
        echo ""
        echo -e "${YELLOW}GPU Configuration:${NC}"
        if detect_gpus; then
            # Map shared vars to comfy-prefixed names for the model menu
            COMFY_GPU_COUNT=$GPU_COUNT
            COMFY_VRAM=$VRAM_GB
            COMFY_TOTAL_VRAM=$TOTAL_VRAM
            echo -e "${GREEN}  ✓ Found ${GPU_COUNT}x ${GPU_NAME} (${VRAM_GB} GB each, ${TOTAL_VRAM} GB total)${NC}"
        else
            COMFY_GPU_COUNT=0
            COMFY_VRAM=0
            COMFY_TOTAL_VRAM=0
            echo -e "${YELLOW}  ⚠ nvidia-smi not found, cannot detect VRAM.${NC}"
        fi

        echo ""
        echo "Select a model for your workflow. More models are available inside"
        echo "ComfyUI via the Manager extension and built-in templates."
        echo ""

        DIM='\033[2m'

        echo -e "  ${BLUE}── Pro Image (Extreme detail, production quality) ──${NC}"
        if [ "$COMFY_VRAM" -ge 16 ]; then
            echo "  1) Flux.2 Dev (FP8)            - Flagship image gen (~53 GB total)"
        else
            echo -e "  1) Flux.2 Dev (FP8)            - ${RED}Requires ~16 GB VRAM${NC}"
        fi
        if [ "$COMFY_VRAM" -ge 16 ]; then
            echo "  2) Flux.1 Dev                  - Previous gen flagship (~12 GB)"
        else
            echo -e "  2) Flux.1 Dev                  - ${RED}Requires ~16 GB VRAM${NC}"
        fi
        if [ "$COMFY_VRAM" -ge 16 ]; then
            echo "  3) HiDream I1 Dev (FP8)        - 17B param, high detail (~27 GB)"
        else
            echo -e "  3) HiDream I1 Dev (FP8)        - ${RED}Requires ~16 GB VRAM${NC}"
        fi
        echo ""

        echo -e "  ${BLUE}── Standard Image (Fast iterations, good quality) ──${NC}"
        echo "  4) Flux.2 Klein (4B)           - 1-2s on 50-series (~8 GB) [Recommended]"
        echo "  5) Flux.1 Schnell              - Fast Flux generation (~12 GB)"
        echo "  6) SDXL Turbo (FP16)           - Fastest SDXL, real-time (~3 GB)"
        echo "  7) SD 3.5 Medium               - Latest SD3 arch (~5 GB)"
        echo "  8) Z-Image Turbo               - Fast, high quality (~16 GB)"
        echo ""

        echo -e "  ${BLUE}── Pro Video ──${NC}"
        echo "  9) LTX-Video 2B                - Best open-source video (~4 GB)"
        echo ""

        echo " 10) Skip                        - Download models from ComfyUI Manager"
        echo ""
        echo -e "  ${DIM}Tip: Additional models (Anima Anime, Capybara, Kandinsky, OmniGen2,${NC}"
        echo -e "  ${DIM}Ovis, Qwen Image, etc.) available via ComfyUI Manager and templates.${NC}"
        echo ""
        read -p "Select [1-10]: " COMFY_MODEL_CHOICE

        COMFY_MODEL_NAME=""
        COMFY_MODEL_URL=""
        COMFY_MODEL_DIR="$INSTALL_DIR/models/checkpoints"
        COMFY_HF_TOKEN=""
        COMFY_TEMPLATE_HINT=""
        COMFY_EXTRA_DOWNLOADS=()

        case $COMFY_MODEL_CHOICE in
            1)
                COMFY_MODEL_NAME="Flux.2 Dev (FP8)"
                COMFY_MODEL_URL="https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/diffusion_models/flux2_dev_fp8mixed.safetensors"
                COMFY_MODEL_DIR="$INSTALL_DIR/models/diffusion_models"
                COMFY_TEMPLATE_HINT="Flux.2 Dev"
                # Text encoder: BF16 (33 GB) needs 48+ GB GPU; FP8 (17 GB) fits on 24-40 GB GPUs
                if [ "$COMFY_VRAM" -ge 48 ]; then
                    COMFY_TEXT_ENC="mistral_3_small_flux2_bf16.safetensors"
                else
                    COMFY_TEXT_ENC="mistral_3_small_flux2_fp8.safetensors"
                    echo -e "${YELLOW}  Note: Using FP8 text encoder (fits ${COMFY_VRAM} GB GPU).${NC}"
                fi
                COMFY_EXTRA_DOWNLOADS=(
                    "$INSTALL_DIR/models/vae|https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors"
                    "$INSTALL_DIR/models/text_encoders|https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/text_encoders/${COMFY_TEXT_ENC}"
                    "$INSTALL_DIR/models/loras|https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/loras/Flux_2-Turbo-LoRA_comfyui.safetensors"
                )
                ;;
            2)
                COMFY_MODEL_NAME="Flux.1 Dev"
                COMFY_MODEL_URL="https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors"
                echo ""
                echo -e "${YELLOW}⚠ Flux.1 Dev is a gated model on HuggingFace.${NC}"
                echo "  Accept the license at: https://huggingface.co/black-forest-labs/FLUX.1-dev"
                read -p "  Enter your HuggingFace token (or press Enter to skip): " COMFY_HF_TOKEN
                if [ -z "$COMFY_HF_TOKEN" ]; then
                    echo -e "${YELLOW}  Download skipped. Use ComfyUI Manager after launch.${NC}"
                    COMFY_MODEL_URL=""
                fi
                COMFY_TEMPLATE_HINT="Flux.1 Dev"
                ;;
            3)
                COMFY_MODEL_NAME="HiDream I1 Dev (FP8)"
                COMFY_MODEL_URL="https://huggingface.co/Comfy-Org/HiDream-I1_ComfyUI/resolve/main/split_files/diffusion_models/hidream_i1_dev_fp8.safetensors"
                COMFY_MODEL_DIR="$INSTALL_DIR/models/diffusion_models"
                COMFY_TEMPLATE_HINT="HiDream"
                COMFY_EXTRA_DOWNLOADS=(
                    "$INSTALL_DIR/models/vae|https://huggingface.co/Comfy-Org/HiDream-I1_ComfyUI/resolve/main/split_files/vae/ae.safetensors"
                    "$INSTALL_DIR/models/text_encoders|https://huggingface.co/Comfy-Org/HiDream-I1_ComfyUI/resolve/main/split_files/text_encoders/clip_g_hidream.safetensors"
                    "$INSTALL_DIR/models/text_encoders|https://huggingface.co/Comfy-Org/HiDream-I1_ComfyUI/resolve/main/split_files/text_encoders/clip_l_hidream.safetensors"
                    "$INSTALL_DIR/models/text_encoders|https://huggingface.co/Comfy-Org/HiDream-I1_ComfyUI/resolve/main/split_files/text_encoders/llama_3.1_8b_instruct_fp8_scaled.safetensors"
                    "$INSTALL_DIR/models/text_encoders|https://huggingface.co/Comfy-Org/HiDream-I1_ComfyUI/resolve/main/split_files/text_encoders/t5xxl_fp8_e4m3fn_scaled.safetensors"
                )
                ;;
            4)
                COMFY_MODEL_NAME="Flux.2 Klein (4B)"
                COMFY_MODEL_URL="https://huggingface.co/black-forest-labs/FLUX.2-klein-4B/resolve/main/flux-2-klein-4b.safetensors"
                COMFY_TEMPLATE_HINT="Flux.2 Klein"
                ;;
            5)
                COMFY_MODEL_NAME="Flux.1 Schnell"
                COMFY_MODEL_URL="https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors"
                echo ""
                echo -e "${YELLOW}⚠ Flux.1 Schnell is gated on HuggingFace.${NC}"
                echo "  Accept the license at: https://huggingface.co/black-forest-labs/FLUX.1-schnell"
                read -p "  Enter your HuggingFace token (or press Enter to skip): " COMFY_HF_TOKEN
                if [ -z "$COMFY_HF_TOKEN" ]; then
                    echo -e "${YELLOW}  Download skipped. Use ComfyUI Manager after launch.${NC}"
                    COMFY_MODEL_URL=""
                fi
                COMFY_TEMPLATE_HINT="Flux.1 Schnell"
                ;;
            6)
                COMFY_MODEL_NAME="SDXL Turbo (FP16)"
                COMFY_MODEL_URL="https://huggingface.co/stabilityai/sdxl-turbo/resolve/main/sd_xl_turbo_1.0_fp16.safetensors"
                COMFY_TEMPLATE_HINT="SDXL Turbo"
                ;;
            7)
                COMFY_MODEL_NAME="SD 3.5 Medium"
                COMFY_MODEL_URL="https://huggingface.co/stabilityai/stable-diffusion-3.5-medium/resolve/main/sd3.5_medium.safetensors"
                echo ""
                echo -e "${YELLOW}⚠ SD 3.5 Medium is gated on HuggingFace.${NC}"
                echo "  Accept the license at: https://huggingface.co/stabilityai/stable-diffusion-3.5-medium"
                read -p "  Enter your HuggingFace token (or press Enter to skip): " COMFY_HF_TOKEN
                if [ -z "$COMFY_HF_TOKEN" ]; then
                    echo -e "${YELLOW}  Download skipped. Use ComfyUI Manager after launch.${NC}"
                    COMFY_MODEL_URL=""
                fi
                COMFY_TEMPLATE_HINT="SD3.5 Simple"
                ;;
            8)
                COMFY_MODEL_NAME="Z-Image Turbo (BF16)"
                COMFY_MODEL_URL="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
                COMFY_MODEL_DIR="$INSTALL_DIR/models/diffusion_models"
                COMFY_TEMPLATE_HINT="Z-Image"
                COMFY_EXTRA_DOWNLOADS=(
                    "$INSTALL_DIR/models/vae|https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors"
                    "$INSTALL_DIR/models/text_encoders|https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors"
                )
                ;;
            9)
                COMFY_MODEL_NAME="LTX-Video 2B"
                COMFY_MODEL_URL="https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltx-video-2b-v0.9.5.safetensors"
                COMFY_TEMPLATE_HINT="LTX-Video"
                ;;

            *)
                echo "Skipping model download."
                echo -e "You can download models from within ComfyUI using the ${BLUE}Manager${NC} extension."
                ;;
        esac

        if [ -n "$COMFY_MODEL_URL" ]; then
            COMFY_MODEL_FILE=$(basename "$COMFY_MODEL_URL")
            mkdir -p "$COMFY_MODEL_DIR"
            if [ -f "$COMFY_MODEL_DIR/$COMFY_MODEL_FILE" ]; then
                echo -e "${GREEN}✓ ${COMFY_MODEL_NAME} already downloaded, skipping.${NC}"
            else
                echo -e "${BLUE}Downloading ${COMFY_MODEL_NAME}...${NC}"
                if [ -n "$COMFY_HF_TOKEN" ]; then
                    wget -nc -q --show-progress --header="Authorization: Bearer ${COMFY_HF_TOKEN}" -P "$COMFY_MODEL_DIR/" "$COMFY_MODEL_URL"
                else
                    wget -nc -q --show-progress -P "$COMFY_MODEL_DIR/" "$COMFY_MODEL_URL"
                fi
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓ ${COMFY_MODEL_NAME} downloaded.${NC}"
                else
                    echo -e "${RED}✗ Download failed. You can retry from within ComfyUI Manager.${NC}"
                fi
            fi

            # Download companion files (VAE, text encoders, LoRAs)
            for extra in "${COMFY_EXTRA_DOWNLOADS[@]}"; do
                EXTRA_DIR=$(echo "$extra" | cut -d'|' -f1)
                EXTRA_URL=$(echo "$extra" | cut -d'|' -f2)
                EXTRA_NAME=$(basename "$EXTRA_URL")
                mkdir -p "$EXTRA_DIR"
                EXTRA_EXIT=0
                if [ -f "$EXTRA_DIR/$EXTRA_NAME" ]; then
                    echo -e "${GREEN}  ✓ ${EXTRA_NAME} (already exists)${NC}"
                else
                    echo -e "${BLUE}  Downloading ${EXTRA_NAME}...${NC}"
                    if [ -n "$COMFY_HF_TOKEN" ]; then
                        wget -nc -q --show-progress --header="Authorization: Bearer ${COMFY_HF_TOKEN}" -P "$EXTRA_DIR/" "$EXTRA_URL" || EXTRA_EXIT=$?
                    else
                        wget -nc -q --show-progress -P "$EXTRA_DIR/" "$EXTRA_URL" || EXTRA_EXIT=$?
                    fi
                fi
                if [ $EXTRA_EXIT -eq 0 ]; then
                    echo -e "${GREEN}  ✓ ${EXTRA_NAME}${NC}"
                else
                    echo -e "${RED}  ✗ ${EXTRA_NAME} failed — will auto-download when template is opened${NC}"
                fi
            done

            if [ -n "$COMFY_TEMPLATE_HINT" ]; then
                echo ""
                echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
                echo -e "${BLUE}│${NC}  ${GREEN}Next Step:${NC} Open ComfyUI and search templates for:       ${BLUE}│${NC}"
                echo -e "${BLUE}│${NC}  ${YELLOW}\"${COMFY_TEMPLATE_HINT}\"${NC}                                          ${BLUE}│${NC}"
                echo -e "${BLUE}│${NC}                                                         ${BLUE}│${NC}"
                echo -e "${BLUE}│${NC}  The template will set up the correct workflow.          ${BLUE}│${NC}"
                if [ "${COMFY_TEXT_ENC:-}" = "mistral_3_small_flux2_fp8.safetensors" ]; then
                    echo -e "${BLUE}│${NC}                                                         ${BLUE}│${NC}"
                    echo -e "${BLUE}│${NC}  ${YELLOW}⚠ Template may show 'Missing Models' for BF16${NC}          ${BLUE}│${NC}"
                    echo -e "${BLUE}│${NC}  ${YELLOW}  text encoder (too large for ${COMFY_VRAM} GB GPU).${NC}            ${BLUE}│${NC}"
                    echo -e "${BLUE}│${NC}  Close the dialog, then in the text encoder node,       ${BLUE}│${NC}"
                    echo -e "${BLUE}│${NC}  select: ${GREEN}mistral_3_small_flux2_fp8.safetensors${NC}          ${BLUE}│${NC}"
                else
                    echo -e "${BLUE}│${NC}  All required files have been pre-downloaded.            ${BLUE}│${NC}"
                fi
                echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
            fi
        fi

        echo ""
        echo -e "After starting, access ComfyUI at: ${BLUE}http://localhost:8188${NC}"
        echo -e "Use the ${BLUE}Manager${NC} button in the sidebar to install additional models and nodes."
        echo -e "Run ${BLUE}./${INSTALL_DIR}/init.sh${NC} at any time to reconfigure."
        ;;
    personal_llm)
        echo -e "${GREEN}Personal LLM (Ollama + Open WebUI)${NC}"
        echo ""
        # Cache Proxy Configuration (optional)
        prompt_env_proxy "$INSTALL_DIR/.env" || true
        echo ""
        # GPU Detection
        echo -e "${YELLOW}GPU Configuration:${NC}"
        if detect_gpus; then
            echo -e "${GREEN}  ✓ Found ${GPU_COUNT}x ${GPU_NAME} (${VRAM_GB} GB each, ${TOTAL_VRAM} GB total)${NC}"
            if [ "$IS_BLACKWELL" = true ]; then
                echo -e "${GREEN}    Blackwell GPU detected (compute ${COMPUTE_CAP})${NC}"
            fi
        else
            GPU_COUNT=1
            TOTAL_VRAM=0
            VRAM_GB=0
            echo -e "${YELLOW}  ⚠ nvidia-smi not found, cannot detect VRAM.${NC}"
        fi
        ;;
    team_llm)
        echo -e "${GREEN}Team LLM (vLLM + Open WebUI)${NC}"
        echo "Production inference with multi-GPU tensor parallelism."
        echo ""
        # Cache Proxy Configuration (optional)
        prompt_env_proxy "$INSTALL_DIR/.env" || true
        echo ""
        # GPU Detection
        echo -e "${YELLOW}GPU Configuration:${NC}"
        if detect_gpus; then
            echo -e "${GREEN}  ✓ Found ${GPU_COUNT}x ${GPU_NAME} (${VRAM_GB} GB each, ${TOTAL_VRAM} GB total)${NC}"
            if [ "$IS_BLACKWELL" = true ]; then
                echo -e "${GREEN}    Blackwell GPU detected (compute ${COMPUTE_CAP}) → using CUDA 13.0 images${NC}"
            fi
        else
            GPU_COUNT=1
            TOTAL_VRAM=32
            VRAM_GB=32
            echo -e "${YELLOW}  ⚠ nvidia-smi not found, defaulting to 1 GPU.${NC}"
        fi
        echo ""
        # Model Selection (uses shared library)
        echo -e "${YELLOW}Select a model to serve:${NC}"
        echo ""
        show_vllm_model_menu
        echo ""
        read -p "Select [1-${MENU_MAX}]: " VLLM_MODEL_SELECT

        if select_vllm_model "$VLLM_MODEL_SELECT"; then
            write_env_var "MODEL_ID" "$VLLM_MODEL_ID" "$INSTALL_DIR/.env"
            write_env_var "VLLM_IMAGE" "$VLLM_IMAGE" "$INSTALL_DIR/.env"
            write_env_var "GPU_COUNT" "$VLLM_GPU_COUNT" "$INSTALL_DIR/.env"
            write_env_var "MAX_CONTEXT" "$VLLM_MAX_CTX" "$INSTALL_DIR/.env"
            write_env_var "GPU_MEMORY_UTILIZATION" "$VLLM_GPU_MEM_UTIL" "$INSTALL_DIR/.env"
            write_env_var "REASONING_ARGS" "$VLLM_REASONING_ARGS" "$INSTALL_DIR/.env"
            write_env_var "TOOL_CALL_ARGS" "$VLLM_TOOL_CALL_ARGS" "$INSTALL_DIR/.env"
            write_env_var "EXTRA_VLLM_ARGS" "$VLLM_EXTRA_ARGS" "$INSTALL_DIR/.env"
            write_env_var "DTYPE" "$VLLM_DTYPE" "$INSTALL_DIR/.env"
            echo -e "${GREEN}✓ Model: $VLLM_MODEL_ID (${VLLM_GPU_COUNT} GPU(s))${NC}"
            ctx_display=${VLLM_MAX_CTX:-auto (vLLM will size based on available VRAM)}
            echo -e "  Memory: ${VLLM_GPU_MEM_UTIL} utilization, ${ctx_display} context"
            PARSER_NAME=$(echo "$VLLM_TOOL_CALL_ARGS" | grep -oE 'tool-call-parser [^ ]+' | awk '{print $2}' || echo "hermes")
            echo -e "  Tool calls: enabled ($PARSER_NAME parser)"
            echo -e "  The model will download on first launch."
        elif [ -n "$VLLM_MODEL_ID" ]; then
            # Custom model (return code 2) — write what we have
            write_env_var "MODEL_ID" "$VLLM_MODEL_ID" "$INSTALL_DIR/.env"
            echo -e "${GREEN}✓ Custom model: $VLLM_MODEL_ID${NC}"
            echo -e "  Edit .env to configure GPU count, context, and memory settings."
        else
            echo "Skipping model configuration. Edit .env before starting."
        fi
        ;;
    docker-base)
        echo "Base environment ready for Python development."
        echo "Edit files in '$INSTALL_DIR/src/' and rebuild."
        ;;
    *)
        echo "Stack ready. Edit files in '$INSTALL_DIR/src/' and rebuild."
        ;;
esac

echo -e "\n${YELLOW}[Step 5] Launch${NC}"
read -p "Would you like to build and start the container now? (Y/n): " START_NOW
if [[ "$START_NOW" != "n" && "$START_NOW" != "N" ]]; then
    echo -e "${BLUE}Building and starting container in background...${NC}"
    cd "$INSTALL_DIR"

    # Validate .env before launch — catch stacking/corruption early
    if ! validate_env ".env"; then
        echo -e "${RED}Fix .env issues before launching.${NC}"
        cd - > /dev/null
        exit 1
    fi
    
    # Check for container name conflicts (since we use static names in some packs)
    # We try to get the container name from docker-compose.yml if possible, or just handle the error
    # Here we'll just attempt to stop and remove any existing container using the project's names
    # or conflicting names we know about (like puget_comfy_ui)
    docker compose down 2>/dev/null || true
    
    # Specifically check for the comfy_ui conflict the user saw
    if [ "$FLAVOR" == "comfy_ui" ]; then
        if docker ps -a --format '{{.Names}}' | grep -q "^puget_comfy_ui$"; then
            echo -e "${YELLOW}⚠ Conflict: A container named 'puget_comfy_ui' already exists.${NC}"
            read -p "  Would you like to remove the existing container to continue? (y/N): " REMOVE_CONFLICT
            if [[ "$REMOVE_CONFLICT" == "y" || "$REMOVE_CONFLICT" == "Y" ]]; then
                echo -e "${BLUE}Removing existing container 'puget_comfy_ui'...${NC}"
                docker rm -f puget_comfy_ui 2>/dev/null || true
            else
                echo -e "${RED}Error: Cannot launch because of name conflict.${NC}"
                echo "Please stop/remove the existing container or choose a different installation name."
                cd - > /dev/null
                exit 1
            fi
        fi
    fi

    # Smart rebuild: detect if build files changed → --no-cache rebuild
    BUILD_OK=true
    if ! smart_build; then
        echo -e "${RED}Build failed. Attempting to start with existing images...${NC}"
        BUILD_OK=false
    fi
    COMPOSE_EXIT=0
    docker compose up -d || COMPOSE_EXIT=$?
    
    if [ $COMPOSE_EXIT -eq 0 ]; then
        echo -e "${GREEN}✓ Container started successfully!${NC}"
        
        # Show access URL based on flavor
        case $FLAVOR in
            comfy_ui)
                LOCAL_IP=$(hostname -I | awk '{print $1}')
                echo -e "\n${GREEN}Access ComfyUI at:${NC}"
                echo -e "  Local:   ${BLUE}http://localhost:8188${NC}"
                echo -e "  Network: ${BLUE}http://${LOCAL_IP}:8188${NC}"
                ;;
            personal_llm)
                LOCAL_IP=$(hostname -I | awk '{print $1}')
                echo -e "\n${GREEN}Access Open WebUI at:${NC}"
                echo -e "  Local:   ${BLUE}http://localhost:3000${NC}"
                echo -e "  Network: ${BLUE}http://${LOCAL_IP}:3000${NC}"
                echo ""
                echo "Select a starter model to download:"
                echo ""
                show_ollama_model_menu
                echo ""
                read -p "Select a model [1-${MENU_MAX}]: " MODEL_SELECT

                MODEL_TAG=""
                OLLAMA_SELECT_RC=0
                select_ollama_model "$MODEL_SELECT" || OLLAMA_SELECT_RC=$?

                if [ $OLLAMA_SELECT_RC -eq 0 ]; then
                    MODEL_TAG="$OLLAMA_MODEL_TAG"
                elif [ $OLLAMA_SELECT_RC -eq 1 ]; then
                    # VRAM insufficient — message already printed
                    MODEL_TAG=""
                else
                    echo "Skipping model download."
                    MODEL_TAG=""
                fi

                if [[ -n "$MODEL_TAG" ]]; then
                     if ! wait_for_ollama; then
                         MODEL_TAG=""
                     fi
                fi

                if [[ -n "$MODEL_TAG" ]]; then
                     echo -e "${BLUE}Downloading $MODEL_TAG... (This may take a while for larger models)${NC}"
                     docker compose exec -T inference ollama pull "$MODEL_TAG"
                     echo -e "${GREEN}✓ Model ready.${NC}"
                else
                     echo -e "Run ${BLUE}./init.sh${NC} later to download models."
                fi
                ;;
            team_llm)
                LOCAL_IP=$(hostname -I | awk '{print $1}')
                echo -e "\n${GREEN}vLLM server is starting...${NC}"
                echo -e "  Chat UI:  ${BLUE}http://localhost:3000${NC}"
                echo -e "  API:      ${BLUE}http://localhost:8000/v1${NC}"
                echo -e "  Network:  ${BLUE}http://${LOCAL_IP}:3000${NC}"
                echo ""
                
                # Wait for model download and loading with progress
                if [ -n "$VLLM_MODEL_ID" ]; then
                    echo -e "${YELLOW}Waiting for model to download and load...${NC}"
                    echo "  (This may take 5-30 minutes depending on model size and bandwidth)"
                    echo ""
                    wait_for_vllm "puget_vllm" "$VLLM_MODEL_SIZE_GB"
                fi
                
                echo -e "  Re-configure model: ${BLUE}./init.sh${NC}"
                ;;
        esac
    else
        echo -e "${RED}Container failed to start. Check logs with: docker compose logs${NC}"
    fi
    cd - > /dev/null
fi

# Offer auto-start on boot
echo ""
read -p "Would you like this container to start automatically on system boot? (Y/n): " AUTO_START
if [[ "$AUTO_START" != "n" && "$AUTO_START" != "N" ]]; then
    # Ensure Docker service starts on boot
    sudo systemctl enable docker 2>/dev/null || true
    
    # The docker-compose.yml already has restart: unless-stopped
    # But we need the container to exist, so start it if not running
    cd "$INSTALL_DIR"
    if ! docker compose ps --quiet 2>/dev/null | grep -q .; then
        docker compose up -d
    fi
    cd - > /dev/null
    
    echo -e "${GREEN}✓ Auto-start configured.${NC}"
    echo "  Container will restart automatically after reboot."
    echo "  (Uses Docker's 'restart: unless-stopped' policy)"
fi

echo -e "\n${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   Installation Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Useful commands:"
echo -e "  ${BLUE}cd $INSTALL_DIR${NC}              - Go to installation"
echo -e "  ${BLUE}docker compose logs -f${NC}      - View logs"
echo -e "  ${BLUE}docker compose restart${NC}      - Restart container"
echo -e "  ${BLUE}docker compose down${NC}         - Stop container"

