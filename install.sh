#!/bin/bash

# Puget Systems Docker App Pack - Universal Installer
# Standards: Ubuntu 24.04 LTS target, /home/puget-app-pack/app pathing

# ANSI Color Codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
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
        sudo usermod -aG docker $USER
        
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
            exec sg docker -c "$0 $@"
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

# Check for NVIDIA Drivers (required for GPU stacks)
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
if ! dpkg -l nvidia-container-toolkit &> /dev/null 2>&1; then
    echo -e "${RED}✗ NVIDIA Container Toolkit is not installed.${NC}"
    echo "  This is required for GPU passthrough to containers."
    read -p "  Would you like to install NVIDIA Container Toolkit now? (Y/n): " INSTALL_NVIDIA
    if [[ "$INSTALL_NVIDIA" != "n" && "$INSTALL_NVIDIA" != "N" ]]; then
        echo -e "${BLUE}Installing NVIDIA Container Toolkit...${NC}"
        # Add NVIDIA repo
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
        sudo apt update && sudo apt install -y nvidia-container-toolkit
        echo -e "${GREEN}✓ NVIDIA Container Toolkit installed.${NC}"
    fi
else
    echo -e "${GREEN}✓ NVIDIA Container Toolkit found.${NC}"
fi

# ALWAYS ensure Docker runtime is configured for NVIDIA (even if toolkit was pre-installed)
if command -v nvidia-ctk &> /dev/null && command -v docker &> /dev/null; then
    # Check if nvidia runtime is configured in Docker
    if ! docker info 2>/dev/null | grep -q "nvidia"; then
        echo -e "${BLUE}Configuring Docker for NVIDIA GPU access...${NC}"
        sudo nvidia-ctk runtime configure --runtime=docker
        sudo systemctl restart docker
        
        # Wait for Docker to restart
        echo "Waiting for Docker to restart..."
        for i in {1..10}; do
            if docker info &> /dev/null; then
                break
            fi
            sleep 1
        done
        
        echo -e "${GREEN}✓ Docker GPU runtime configured.${NC}"
    fi

    # Verify generic GPU access
    echo "Verifying GPU access in Docker (this may pull an image)..."
    if docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi &> /dev/null; then
        echo -e "${GREEN}✓ GPU accessible from Docker.${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: GPU verification check did not pass.${NC}"
        echo -e "${YELLOW}  This is common immediately after driver/toolkit installation.${NC}"
        echo -e "${YELLOW}  If containers fail to detect the GPU, try: sudo reboot${NC}"
    fi
fi

# Re-check after potential installs
if ! command -v docker &> /dev/null; then
    echo -e "\n${RED}Docker is still not available. Cannot continue.${NC}"
    echo "Please install Docker manually and run this installer again."
    exit 1
fi

# --- Configuration ---

# Resolve the directory where this script resides to find the packs
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PACKS_DIR="$SCRIPT_DIR/packs"

if [ ! -d "$PACKS_DIR" ]; then
   echo -e "${RED}Error: 'packs' directory not found at $PACKS_DIR!${NC}"
   exit 1
fi

OPTIONS=($(ls "$PACKS_DIR"))

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

# Create standard .env if it doesn't exist
if [ ! -f "$INSTALL_DIR/.env" ]; then
    echo "Creating default .env..."
    echo "PUGET_APP_NAME=$INSTALL_DIR" > "$INSTALL_DIR/.env"
fi

echo -e "${GREEN}Success! Application installed to '$INSTALL_DIR'.${NC}"

# Per-Flavor Post-Install Guidance
echo -e "\n${YELLOW}[Post-Install: $FLAVOR]${NC}"
case $FLAVOR in
    comfy_ui)
        echo "ComfyUI requires AI models to generate images."
        
        # Create required directories with write permissions
        # This prevents Docker from creating them as root and ensures the container user can write
        echo -e "${BLUE}Ensuring data directories exist and are writable...${NC}"
        COMFY_DIRS=("models" "models/checkpoints" "output" "input" "temp" "custom_nodes")
        for dir in "${COMFY_DIRS[@]}"; do
            target="$INSTALL_DIR/$dir"
            if [ ! -d "$target" ]; then
                mkdir -p "$target"
            fi
            # Allow container user to write (since UID might not match host)
            chmod 777 "$target"
        done

        echo ""
        echo "Select a Creative Stack for your workflow:"
        echo "  1) Pro Image  (Flux.1 Schnell ~12GB) - SOTA Image Generation"
        echo "  2) Pro Video  (LTX-Video 2B   ~4GB)  - Best Open Source Video Model"
        echo "  3) Standard   (SDXL Base 1.0  ~6GB)  - Reliable, Broad Compatibility"
        echo "  4) Skip       - I'll download models myself"
        echo ""
        read -p "Select a stack [1-4]: " STACK_CHOICE
        
        case $STACK_CHOICE in
            1)
                echo -e "${BLUE}Downloading Flux.1 Schnell (Pro Image Stack)...${NC}"
                mkdir -p "$INSTALL_DIR/models/checkpoints"
                wget -q --show-progress -P "$INSTALL_DIR/models/checkpoints/" \
                    "https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors"
                echo -e "${GREEN}✓ Flux.1 Schnell downloaded.${NC}"
                ;;
            2)
                echo -e "${BLUE}Downloading LTX-Video 2B (Pro Video Stack)...${NC}"
                mkdir -p "$INSTALL_DIR/models/checkpoints"
                wget -q --show-progress -P "$INSTALL_DIR/models/checkpoints/" \
                    "https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltx-video-2b-v0.9.5.safetensors"
                echo -e "${GREEN}✓ LTX-Video downloaded.${NC}"
                echo -e "${YELLOW}Note: You will need to install 'ComfyUI-LTXVideo' custom nodes via ComfyUI Manager.${NC}"
                ;;
            3)
                echo -e "${BLUE}Downloading SDXL Base 1.0 (Standard Stack)...${NC}"
                mkdir -p "$INSTALL_DIR/models/checkpoints"
                wget -q --show-progress -P "$INSTALL_DIR/models/checkpoints/" \
                    "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors"
                echo -e "${GREEN}✓ SDXL Base 1.0 downloaded.${NC}"
                ;;
            *)
                echo "Skipping model download."
                echo -e "You can download models later to: ${BLUE}$INSTALL_DIR/models/checkpoints/${NC}"
                ;;
        esac
        echo ""
        echo -e "After starting, access ComfyUI at: ${BLUE}http://localhost:8188${NC}"
        ;;
    personal_llm)
        echo -e "${GREEN}Personal LLM (Ollama + Open WebUI)${NC}"
        echo "Note: You will be prompted to download models after the container launches."
        echo "      (Or use ./init.sh at any time)"
        echo ""
        # Cache Proxy Configuration (optional)
        echo -e "${YELLOW}Cache Proxy (Optional):${NC}"
        echo "  If this system is on a LAN with a Puget cache proxy (Squid),"
        echo "  model downloads can be cached to avoid re-downloading."
        read -p "  Enter cache proxy URL (or press Enter to skip): " CACHE_URL
        if [ -n "$CACHE_URL" ]; then
            echo "CACHE_PROXY=$CACHE_URL" >> "$INSTALL_DIR/.env"
            echo -e "${GREEN}✓ Cache proxy configured: $CACHE_URL${NC}"
        fi
        ;;
    team_llm)
        echo -e "${GREEN}Team LLM (vLLM + Open WebUI)${NC}"
        echo "Production inference with multi-GPU tensor parallelism."
        echo ""
        # Cache Proxy Configuration (optional)
        echo -e "${YELLOW}Cache Proxy (Optional):${NC}"
        echo "  If this system is on a LAN with a Puget cache proxy (Squid),"
        echo "  model downloads can be cached to avoid re-downloading."
        read -p "  Enter cache proxy URL (or press Enter to skip): " CACHE_URL
        if [ -n "$CACHE_URL" ]; then
            echo "CACHE_PROXY=$CACHE_URL" >> "$INSTALL_DIR/.env"
            echo -e "${GREEN}✓ Cache proxy configured: $CACHE_URL${NC}"
        fi
        echo ""
        # GPU Detection
        echo -e "${YELLOW}GPU Configuration:${NC}"
        if command -v nvidia-smi &> /dev/null; then
            GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
            GPU_NAME=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | head -1)
            VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
            VRAM_GB=$((VRAM_MB / 1024))
            TOTAL_VRAM=$((VRAM_GB * GPU_COUNT))
            echo -e "${GREEN}  ✓ Found ${GPU_COUNT}x ${GPU_NAME} (${VRAM_GB} GB each, ${TOTAL_VRAM} GB total)${NC}"
        else
            GPU_COUNT=1
            TOTAL_VRAM=32
            echo -e "${YELLOW}  ⚠ nvidia-smi not found, defaulting to 1 GPU.${NC}"
        fi
        echo ""
        # Model Selection
        echo -e "${YELLOW}Select a model to serve:${NC}"
        echo ""
        echo "  1) Qwen 3 (8B)                - Fast, single GPU (~16 GB BF16)"

        if [ "$TOTAL_VRAM" -ge 40 ]; then
            echo "  2) Qwen 3 (32B FP8)           - Near-lossless quality (~32 GB)"
        else
            echo -e "  2) Qwen 3 (32B FP8)           - ${RED}Requires ~40 GB VRAM${NC}"
        fi

        echo "  3) Qwen 3.5 (35B MoE AWQ)     - 3B active params, fast (~18 GB)"

        if [ "$TOTAL_VRAM" -ge 80 ]; then
            echo "  4) Qwen 3.5 (122B MoE AWQ)    - Flagship, 10B active (~60 GB) [Recommended]"
        else
            echo -e "  4) Qwen 3.5 (122B MoE AWQ)    - ${RED}Requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
        fi

        if [ "$TOTAL_VRAM" -ge 40 ]; then
            echo "  5) DeepSeek R1 (70B AWQ)      - Reasoning specialist (~38 GB)"
        else
            echo -e "  5) DeepSeek R1 (70B AWQ)      - ${RED}Requires ~40 GB VRAM${NC}"
        fi

        echo "  6) Custom                      - Enter a HuggingFace model ID"
        echo "  7) Skip                        - I'll configure via .env later"
        echo ""
        read -p "Select [1-7]: " VLLM_MODEL_SELECT
        
        VLLM_MODEL_ID=""
        VLLM_GPU_COUNT=1
        VLLM_MODEL_SIZE_GB=0
        VLLM_TOOL_CALL_ARGS=""
        VLLM_EXTRA_ARGS=""
        VLLM_IMAGE="latest"
        case $VLLM_MODEL_SELECT in
            1) VLLM_MODEL_ID="Qwen/Qwen3-8B"; VLLM_GPU_COUNT=1; VLLM_MODEL_SIZE_GB=16
               VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes" ;;
            2)
                if [ "$TOTAL_VRAM" -lt 40 ]; then
                    echo -e "${RED}✗ Qwen 3 32B FP8 requires ~40 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                else
                    VLLM_MODEL_ID="Qwen/Qwen3-32B-FP8"; VLLM_GPU_COUNT=$GPU_COUNT; VLLM_MODEL_SIZE_GB=32
                    VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
                fi
                ;;
            3)
                VLLM_MODEL_ID="cyankiwi/Qwen3.5-35B-A3B-AWQ-4bit"; VLLM_GPU_COUNT=1; VLLM_MODEL_SIZE_GB=18
                VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
                VLLM_IMAGE="nightly"
                ;;
            4)
                if [ "$TOTAL_VRAM" -lt 80 ]; then
                    echo -e "${RED}✗ Qwen 3.5 122B MoE AWQ requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                else
                    VLLM_MODEL_ID="cyankiwi/Qwen3.5-122B-A10B-AWQ-4bit"; VLLM_GPU_COUNT=$GPU_COUNT; VLLM_MODEL_SIZE_GB=60
                    VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
                    VLLM_IMAGE="nightly"
                fi
                ;;
            5)
                if [ "$TOTAL_VRAM" -lt 40 ]; then
                    echo -e "${RED}✗ DeepSeek R1 70B AWQ requires ~40 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                else
                    VLLM_MODEL_ID="Valdemardi/DeepSeek-R1-Distill-Llama-70B-AWQ"; VLLM_GPU_COUNT=$GPU_COUNT; VLLM_MODEL_SIZE_GB=38
                    VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
                fi
                ;;
            6) read -p "  Enter HuggingFace model ID: " VLLM_MODEL_ID ;;
            *) echo "Skipping model configuration. Edit .env before starting." ;;
        esac
        
        if [ -n "$VLLM_MODEL_ID" ]; then
            # Auto-tune GPU memory settings based on model size vs available VRAM
            AVAILABLE_VRAM=$((VRAM_GB * VLLM_GPU_COUNT))
            GPU_MEM_UTIL="0.90"
            MAX_CTX=32768
            
            if [ "$VLLM_MODEL_SIZE_GB" -gt 0 ] 2>/dev/null; then
                WEIGHT_PCT=$((VLLM_MODEL_SIZE_GB * 100 / AVAILABLE_VRAM))
                
                if [ "$WEIGHT_PCT" -ge 85 ]; then
                    GPU_MEM_UTIL="0.95"
                    MAX_CTX=8192
                elif [ "$WEIGHT_PCT" -ge 70 ]; then
                    GPU_MEM_UTIL="0.92"
                    MAX_CTX=16384
                else
                    GPU_MEM_UTIL="0.90"
                    MAX_CTX=32768
                fi
            fi
            
            echo "MODEL_ID=$VLLM_MODEL_ID" >> "$INSTALL_DIR/.env"
            echo "VLLM_IMAGE=$VLLM_IMAGE" >> "$INSTALL_DIR/.env"
            echo "GPU_COUNT=$VLLM_GPU_COUNT" >> "$INSTALL_DIR/.env"
            echo "MAX_CONTEXT=$MAX_CTX" >> "$INSTALL_DIR/.env"
            echo "GPU_MEMORY_UTILIZATION=$GPU_MEM_UTIL" >> "$INSTALL_DIR/.env"
            echo "TOOL_CALL_ARGS=$VLLM_TOOL_CALL_ARGS" >> "$INSTALL_DIR/.env"
            echo -e "${GREEN}✓ Model: $VLLM_MODEL_ID (${VLLM_GPU_COUNT} GPU(s))${NC}"
            echo -e "  Memory: ${GPU_MEM_UTIL} utilization, ${MAX_CTX} context tokens"
            echo -e "  Tool calls: enabled (hermes parser)"
            echo -e "  The model will download on first launch."
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

    docker compose up --build -d
    
    if [ $? -eq 0 ]; then
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
                echo "  1) Qwen 3 (8B)         - Fast, Low VRAM (~5 GB)"
                echo "  2) Qwen 3 (32B)        - Best Quality, Single GPU (~20 GB) [Recommended]"
                echo "  3) DeepSeek R1 (70B)   - Flagship Reasoning, Dual GPU (~42 GB)"
                echo "  4) Llama 4 Scout       - Multimodal (text+image), Dual GPU (~63 GB)"
                echo "  5) Skip                - I'll download models later"
                echo ""
                read -p "Select a model [1-5]: " MODEL_SELECT
                
                MODEL_TAG=""
                case $MODEL_SELECT in
                    1) MODEL_TAG="qwen3:8b" ;;
                    2) MODEL_TAG="qwen3:32b" ;;
                    3) MODEL_TAG="deepseek-r1:70b" ;;
                    4) MODEL_TAG="llama4:scout" ;;
                    *) echo "Skipping model download." ;;
                esac

                if [[ -n "$MODEL_TAG" ]]; then
                     echo -e "${BLUE}Downloading $MODEL_TAG... (This may take a while for larger models)${NC}"
                     docker compose exec inference ollama pull "$MODEL_TAG"
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
                    
                    CONTAINER_NAME="puget_vllm"
                    READY=false
                    LAST_PHASE=""
                    PHASE_LEVEL=0           # Monotonic: phases only advance forward
                    LAST_RESTART_COUNT=0    # Track container restarts to detect crash loops
                    CRASH_DETECTIONS=0      # Number of times we've seen a restart increment
                    START_TIME=$(date +%s)  # Track elapsed time
                    
                    while ! $READY; do
                        # Check if container is still running
                        if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
                            echo -e "\n${RED}✗ vLLM container exited. Check logs:${NC}"
                            echo -e "  ${BLUE}docker compose logs inference${NC}"
                            break
                        fi
                        
                        # Detect crash loops (container restarting repeatedly)
                        RESTART_COUNT=$(docker inspect --format='{{.RestartCount}}' "$CONTAINER_NAME" 2>/dev/null || echo "0")
                        if [ "$RESTART_COUNT" -gt "$LAST_RESTART_COUNT" ] 2>/dev/null; then
                            CRASH_DETECTIONS=$((CRASH_DETECTIONS + 1))
                            LAST_RESTART_COUNT=$RESTART_COUNT
                            # Reset phase tracking since we're on a fresh attempt
                            PHASE_LEVEL=0
                            LAST_PHASE=""
                        fi
                        
                        if [ "$CRASH_DETECTIONS" -ge 2 ]; then
                            echo ""
                            echo -e "${RED}✗ vLLM is crash-looping (restarted ${RESTART_COUNT} times).${NC}"
                            echo ""
                            # Extract the actual error from the logs
                            ERROR_MSG=$(docker logs "$CONTAINER_NAME" 2>&1 | grep -E "RuntimeError|OutOfMemoryError|CUDA|Error|error" | tail -5)
                            if [ -n "$ERROR_MSG" ]; then
                                echo -e "${RED}  Error from logs:${NC}"
                                echo "$ERROR_MSG" | while IFS= read -r line; do
                                    echo -e "  ${YELLOW}${line}${NC}"
                                done
                                echo ""
                            fi
                            echo "  Troubleshooting:"
                            echo -e "  ${BLUE}docker compose logs inference${NC}  - View full logs"
                            echo -e "  Try reducing GPU memory: edit .env and lower MAX_CONTEXT"
                            echo -e "  Or try a smaller model: ${BLUE}./init.sh${NC}"
                            break
                        fi
                        
                        # Check if API is responding (model fully loaded)
                        if curl -s --max-time 2 http://localhost:8000/v1/models > /dev/null 2>&1; then
                            ELAPSED=$(( $(date +%s) - START_TIME ))
                            ELAPSED_MIN=$((ELAPSED / 60))
                            ELAPSED_SEC=$((ELAPSED % 60))
                            echo -e "\n${GREEN}✓ Model loaded and ready! (${ELAPSED_MIN}m ${ELAPSED_SEC}s)${NC}"
                            READY=true
                            break
                        fi
                        
                        # Parse vLLM logs to determine startup phase
                        # Use --tail 20 for download progress (tqdm bars can be verbose)
                        LAST_LOG=$(docker logs "$CONTAINER_NAME" --tail 20 2>&1)
                        CANDIDATE_PHASE=""
                        CANDIDATE_LEVEL=0
                        DETAIL=""
                        
                        # Check phases in order of progression (highest priority first)
                        if echo "$LAST_LOG" | grep -q "CUDA graphs"; then
                            GRAPH_PCT=$(echo "$LAST_LOG" | grep -oE '[0-9]+%\|' | sed 's/|//' | tail -1)
                            CANDIDATE_PHASE="Capturing CUDA graphs"
                            CANDIDATE_LEVEL=5
                            DETAIL="${GRAPH_PCT:-working...}"
                        elif echo "$LAST_LOG" | grep -q "torch.compile\|Dynamo bytecode\|compile range"; then
                            CANDIDATE_PHASE="Compiling model kernels"
                            CANDIDATE_LEVEL=4
                            DETAIL="(torch.compile)"
                        elif echo "$LAST_LOG" | grep -q "Autotuning"; then
                            CANDIDATE_PHASE="Autotuning kernels"
                            CANDIDATE_LEVEL=3
                            DETAIL=""
                        elif echo "$LAST_LOG" | grep -q "Loading safetensors\|Loading weights\|Starting to load model"; then
                            SHARD_PCT=$(echo "$LAST_LOG" | grep -oE '[0-9]+% Completed' | tail -1)
                            CANDIDATE_PHASE="Loading model weights"
                            CANDIDATE_LEVEL=2
                            DETAIL="${SHARD_PCT:-starting...}"
                        elif echo "$LAST_LOG" | grep -qiE "Downloading|Fetching"; then
                            DL_PCT=$(echo "$LAST_LOG" | grep -iE "Downloading|Fetching" | grep -oE '[0-9]+%' | tail -1)
                            DL_SIZE=$(echo "$LAST_LOG" | grep -iE "Downloading" | grep -oE '[0-9.]+[GMK]/[0-9.]+[GMK]' | tail -1)
                            CANDIDATE_PHASE="Downloading model"
                            CANDIDATE_LEVEL=1
                            if [ -n "$DL_SIZE" ]; then
                                DETAIL="${DL_PCT:-} ${DL_SIZE}"
                            elif [ -n "$DL_PCT" ]; then
                                DETAIL="${DL_PCT}"
                            else
                                DETAIL="in progress..."
                            fi
                        else
                            # No recognizable phase in logs — check network I/O for silent downloads
                            NET_RX=$(docker stats "$CONTAINER_NAME" --no-stream --format '{{.NetIO}}' 2>/dev/null | awk -F'/' '{print $1}' | xargs)
                            NET_VAL=$(echo "$NET_RX" | grep -oE '[0-9.]+' | head -1)
                            NET_UNIT=$(echo "$NET_RX" | grep -oE '[A-Za-z]+' | head -1)
                            
                            NET_GB=0
                            case "$NET_UNIT" in
                                GB|GiB) NET_GB=$(echo "$NET_VAL" | cut -d. -f1) ;;
                                MB|MiB) NET_GB=0 ;;
                                TB|TiB) NET_GB=$(($(echo "$NET_VAL" | cut -d. -f1) * 1024)) ;;
                            esac
                            
                            if [ "$NET_GB" -gt 0 ] 2>/dev/null && [ "$VLLM_MODEL_SIZE_GB" -gt 0 ] 2>/dev/null; then
                                DL_PCT=$((NET_GB * 100 / VLLM_MODEL_SIZE_GB))
                                [ "$DL_PCT" -gt 100 ] && DL_PCT=100
                                CANDIDATE_PHASE="Downloading model"
                                CANDIDATE_LEVEL=1
                                DETAIL="${DL_PCT}% (${NET_RX} / ${VLLM_MODEL_SIZE_GB} GB)"
                            elif [ -n "$NET_VAL" ] && echo "$NET_UNIT" | grep -qiE "MB|MiB" 2>/dev/null; then
                                CANDIDATE_PHASE="Downloading model"
                                CANDIDATE_LEVEL=1
                                DETAIL="${NET_RX}"
                            elif echo "$LAST_LOG" | grep -q "Resolved architecture\|model_tag\|max_model_len"; then
                                CANDIDATE_PHASE="Initializing model"
                                CANDIDATE_LEVEL=0
                                DETAIL=""
                            else
                                CANDIDATE_PHASE="Starting up"
                                CANDIDATE_LEVEL=0
                                DETAIL="waiting..."
                            fi
                        fi
                        
                        # Only advance phase forward, never regress (prevents oscillation)
                        if [ "$CANDIDATE_LEVEL" -ge "$PHASE_LEVEL" ]; then
                            # Print newline to preserve the old status line before showing new phase
                            if [ "$CANDIDATE_PHASE" != "$LAST_PHASE" ] && [ -n "$LAST_PHASE" ]; then
                                echo ""
                            fi
                            PHASE="$CANDIDATE_PHASE"
                            PHASE_LEVEL=$CANDIDATE_LEVEL
                            LAST_PHASE="$PHASE"
                        else
                            PHASE="$LAST_PHASE"
                        fi
                        
                        # Calculate elapsed time
                        ELAPSED=$(( $(date +%s) - START_TIME ))
                        ELAPSED_MIN=$((ELAPSED / 60))
                        ELAPSED_SEC=$((ELAPSED % 60))
                        ELAPSED_STR=$(printf "%d:%02d" $ELAPSED_MIN $ELAPSED_SEC)
                        
                        # Print phase with elapsed time and optional detail (overwrites current line)
                        if [ -n "$DETAIL" ]; then
                            printf "\r  ⏳ [%s] %s... %s   " "$ELAPSED_STR" "$PHASE" "$DETAIL"
                        else
                            printf "\r  ⏳ [%s] %s...           " "$ELAPSED_STR" "$PHASE"
                        fi
                        
                        sleep 3
                    done
                    echo ""
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

