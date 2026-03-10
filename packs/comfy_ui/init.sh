#!/bin/bash
set -euo pipefail

# Puget Systems — ComfyUI Creative AI Initialization
# Detects GPUs, recommends a model stack, downloads weights, launches.

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

# --- Source shared smart_build helper (or define inline as fallback) ---
_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
_REPO_ROOT="$(cd "$_SCRIPT_DIR/../.." 2>/dev/null && pwd)" || _REPO_ROOT=""
if [ -f "$_REPO_ROOT/scripts/lib/smart_build.sh" ]; then
    source "$_REPO_ROOT/scripts/lib/smart_build.sh"
else
    # Inline fallback for standalone installs (init.sh copied without repo)
    generate_build_fingerprint() {
        cat Dockerfile docker-compose.yml requirements.txt 2>/dev/null | sha256sum | awk '{print $1}'
    }
    smart_build() {
        local CURRENT_FP
        CURRENT_FP=$(generate_build_fingerprint)
        local SAVED_FP=""
        if [ -f ".build_fingerprint" ]; then
            SAVED_FP=$(cat .build_fingerprint)
        fi
        if [ -z "$SAVED_FP" ]; then
            echo -e "${BLUE}Building container...${NC}"
            docker compose build
        elif [ "$CURRENT_FP" != "$SAVED_FP" ]; then
            echo -e "${YELLOW}⚠ Build configuration has changed since last build.${NC}"
            echo -e "${BLUE}Rebuilding container (--no-cache)...${NC}"
            docker compose build --no-cache
        else
            return 0
        fi
        local BUILD_EXIT=$?
        if [ $BUILD_EXIT -ne 0 ]; then
            echo -e "${RED}✗ Build failed (exit code $BUILD_EXIT).${NC}"
            return $BUILD_EXIT
        fi
        echo "$CURRENT_FP" > .build_fingerprint
        echo -e "${GREEN}✓ Build fingerprint saved.${NC}"
        return 0
    }
fi

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}   Puget Systems — ComfyUI Creative AI Setup${NC}"
echo -e "${BLUE}============================================================${NC}"

# --- ComfyUI Manager (auto-install on first run) ---
if [ ! -d "custom_nodes/ComfyUI-Manager" ]; then
    echo ""
    echo -e "${BLUE}Installing ComfyUI Manager (server-side model & node management)...${NC}"
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git custom_nodes/ComfyUI-Manager
    echo -e "${GREEN}✓ ComfyUI Manager installed.${NC}"
fi

# --- GPU Detection ---
echo ""
echo -e "${YELLOW}[1/3] Detecting GPUs...${NC}"

if ! command -v nvidia-smi &> /dev/null; then
    echo -e "${RED}✗ nvidia-smi not found. NVIDIA drivers required.${NC}"
    exit 1
fi

GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
GPU_NAME=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | head -1)
VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
VRAM_GB=$((VRAM_MB / 1024))
TOTAL_VRAM=$((VRAM_GB * GPU_COUNT))

# Detect compute capability (Blackwell = 12.0+)
COMPUTE_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1)
COMPUTE_MAJOR=$(echo "$COMPUTE_CAP" | cut -d. -f1)
if [ "${COMPUTE_MAJOR:-0}" -ge 12 ] 2>/dev/null; then
    IS_BLACKWELL=true
    echo -e "${GREEN}✓ Found ${GPU_COUNT}x ${GPU_NAME} (${VRAM_GB} GB each, ${TOTAL_VRAM} GB total)${NC}"
    echo -e "${GREEN}  Blackwell GPU detected (compute ${COMPUTE_CAP})${NC}"
else
    IS_BLACKWELL=false
    echo -e "${GREEN}✓ Found ${GPU_COUNT}x ${GPU_NAME} (${VRAM_GB} GB each, ${TOTAL_VRAM} GB total)${NC}"
fi

# --- Model Selection ---
echo ""
echo -e "${YELLOW}[2/3] Select a model${NC}"
echo ""
echo "  ComfyUI supports dozens of generative AI models. Select a starter"
echo "  model to download, or skip and browse the full catalog from within"
echo "  ComfyUI using the Manager extension or built-in templates."
echo ""

# ═══════════════════════════════════════════════════════════
# Pro Image — Extreme detail, long inference.
# Use for: concept art, start/end frames for video gen, pre-viz VFX.
# ═══════════════════════════════════════════════════════════
echo -e "  ${BLUE}── Pro Image (Extreme detail, production quality) ──${NC}"

# 1) Flux.2 Dev — flagship, gated, ~24 GB (FP8 mixed ~12 GB)
if [ "$TOTAL_VRAM" -ge 16 ]; then
    echo "  1) Flux.2 Dev (FP8)            - Flagship image gen (~53 GB total)"
else
    echo -e "  1) Flux.2 Dev (FP8)            - ${RED}Requires ~16 GB VRAM${NC}"
fi

# 2) Flux.1 Dev — previous gen flagship, ~24 GB full / ~12 GB Schnell
if [ "$TOTAL_VRAM" -ge 16 ]; then
    echo "  2) Flux.1 Dev                  - Previous gen flagship (~12 GB)"
else
    echo -e "  2) Flux.1 Dev                  - ${RED}Requires ~16 GB VRAM${NC}"
fi

# 3) HiDream I1 Dev — 17B param, FP8 ~12 GB
if [ "$TOTAL_VRAM" -ge 16 ]; then
    echo "  3) HiDream I1 Dev (FP8)        - 17B param, high detail (~27 GB)"
else
    echo -e "  3) HiDream I1 Dev (FP8)        - ${RED}Requires ~16 GB VRAM${NC}"
fi

echo ""

# ═══════════════════════════════════════════════════════════
# Standard Image — Fast iterations, good quality.
# Use for: storyboards, moodboards, thumbnails, infographics.
# ═══════════════════════════════════════════════════════════
echo -e "  ${BLUE}── Standard Image (Fast iterations, good quality) ──${NC}"

# 4) Flux.2 Klein 4B — 1-2s on 50-series, ~8 GB
echo "  4) Flux.2 Klein (4B)           - 1-2s on 50-series (~8 GB) [Recommended]"

# 5) Flux.1 Schnell — fast Flux, ~12 GB
echo "  5) Flux.1 Schnell              - Fast Flux generation (~12 GB)"

# 6) SDXL Turbo — fastest SDXL, ~3 GB FP16
echo "  6) SDXL Turbo (FP16)           - Fastest SDXL, real-time (~3 GB)"

# 7) SD 3.5 Medium — latest SD3 arch, ~5 GB
echo "  7) SD 3.5 Medium               - Latest SD3 arch (~5 GB)"

# 8) Z-Image Turbo — fast, high quality, ~10 GB
echo "  8) Z-Image Turbo               - Fast, high quality (~16 GB)"

echo ""

# ═══════════════════════════════════════════════════════════
# Pro Video — keep existing LTX-Video stack
# ═══════════════════════════════════════════════════════════
echo -e "  ${BLUE}── Pro Video ──${NC}"
echo "  9) LTX-Video 2B                - Best open-source video (~4 GB)"
echo ""

# ═══════════════════════════════════════════════════════════
# Utility / Skip
# ═══════════════════════════════════════════════════════════
echo -e "  ${BLUE}── Utility ──${NC}"
echo " 10) Skip                        - Download models from ComfyUI Manager"
echo ""
echo -e "  ${DIM}Tip: Many more models are available inside ComfyUI via the${NC}"
echo -e "  ${DIM}Manager extension and built-in templates, including:${NC}"
echo -e "  ${DIM}Anima Anime, Capybara, Kandinsky, NetaYume Lumina, NewBie Exp,${NC}"
echo -e "  ${DIM}OmniGen2, Ovis, and Qwen Image. You can install${NC}"
echo -e "  ${DIM}these after launching ComfyUI.${NC}"
echo ""
read -p "Select [1-10]: " CHOICE

MODEL_NAME=""
MODEL_URL=""
MODEL_DIR="models/checkpoints"    # Default target subdirectory
MODEL_SIZE_GB=0
TEMPLATE_HINT=""                  # ComfyUI template to search for
EXTRA_DOWNLOADS=()                # Additional files needed (VAE, CLIP, etc.)

case $CHOICE in
    1)
        MODEL_NAME="Flux.2 Dev (FP8 Mixed)"
        MODEL_URL="https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/diffusion_models/flux2_dev_fp8mixed.safetensors"
        MODEL_DIR="models/diffusion_models"
        MODEL_SIZE_GB=33
        TEMPLATE_HINT="Flux.2 Dev"
        # Text encoder: BF16 (33 GB) needs 48+ GB GPU; FP8 (17 GB) fits on 24-40 GB GPUs
        if [ "$VRAM_GB" -ge 48 ]; then
            TEXT_ENC="mistral_3_small_flux2_bf16.safetensors"
        else
            TEXT_ENC="mistral_3_small_flux2_fp8.safetensors"
            echo -e "${YELLOW}  Note: Using FP8 text encoder (fits ${VRAM_GB} GB GPU).${NC}"
        fi
        EXTRA_DOWNLOADS=(
            "models/vae|https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors"
            "models/text_encoders|https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/text_encoders/${TEXT_ENC}"
            "models/loras|https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/loras/Flux_2-Turbo-LoRA_comfyui.safetensors"
        )
        ;;
    2)
        MODEL_NAME="Flux.1 Dev"
        MODEL_URL="https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors"
        MODEL_SIZE_GB=24
        # Flux.1 Dev is also gated
        echo ""
        echo -e "${YELLOW}⚠ Flux.1 Dev is a gated model on HuggingFace.${NC}"
        echo "  You must accept the license at:"
        echo -e "  ${BLUE}https://huggingface.co/black-forest-labs/FLUX.1-dev${NC}"
        echo ""
        read -p "  Enter your HuggingFace token (or press Enter to skip): " HF_TOKEN
        if [ -z "$HF_TOKEN" ]; then
            echo -e "${RED}✗ Download skipped (no token provided).${NC}"
            echo "  Download manually or use ComfyUI Manager after launching."
            MODEL_URL=""
        fi
        TEMPLATE_HINT="Flux.1 Dev"
        ;;
    3)
        MODEL_NAME="HiDream I1 Dev (FP8)"
        MODEL_URL="https://huggingface.co/Comfy-Org/HiDream-I1_ComfyUI/resolve/main/split_files/diffusion_models/hidream_i1_dev_fp8.safetensors"
        MODEL_DIR="models/diffusion_models"
        MODEL_SIZE_GB=12
        TEMPLATE_HINT="HiDream"
        EXTRA_DOWNLOADS=(
            "models/vae|https://huggingface.co/Comfy-Org/HiDream-I1_ComfyUI/resolve/main/split_files/vae/ae.safetensors"
            "models/text_encoders|https://huggingface.co/Comfy-Org/HiDream-I1_ComfyUI/resolve/main/split_files/text_encoders/clip_g_hidream.safetensors"
            "models/text_encoders|https://huggingface.co/Comfy-Org/HiDream-I1_ComfyUI/resolve/main/split_files/text_encoders/clip_l_hidream.safetensors"
            "models/text_encoders|https://huggingface.co/Comfy-Org/HiDream-I1_ComfyUI/resolve/main/split_files/text_encoders/llama_3.1_8b_instruct_fp8_scaled.safetensors"
            "models/text_encoders|https://huggingface.co/Comfy-Org/HiDream-I1_ComfyUI/resolve/main/split_files/text_encoders/t5xxl_fp8_e4m3fn_scaled.safetensors"
        )
        ;;
    4)
        MODEL_NAME="Flux.2 Klein (4B)"
        MODEL_URL="https://huggingface.co/black-forest-labs/FLUX.2-klein-4B/resolve/main/flux-2-klein-4b.safetensors"
        MODEL_SIZE_GB=8
        TEMPLATE_HINT="Flux.2 Klein"
        ;;
    5)
        MODEL_NAME="Flux.1 Schnell"
        MODEL_URL="https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors"
        MODEL_SIZE_GB=12
        echo ""
        echo -e "${YELLOW}⚠ Flux.1 Schnell is gated on HuggingFace.${NC}"
        echo "  Accept the license at:"
        echo -e "  ${BLUE}https://huggingface.co/black-forest-labs/FLUX.1-schnell${NC}"
        read -p "  Enter your HuggingFace token (or press Enter to skip): " HF_TOKEN
        if [ -z "$HF_TOKEN" ]; then
            echo -e "${RED}✗ Download skipped (no token provided).${NC}"
            MODEL_URL=""
        fi
        TEMPLATE_HINT="Flux.1 Schnell"
        ;;
    6)
        MODEL_NAME="SDXL Turbo (FP16)"
        MODEL_URL="https://huggingface.co/stabilityai/sdxl-turbo/resolve/main/sd_xl_turbo_1.0_fp16.safetensors"
        MODEL_SIZE_GB=3
        TEMPLATE_HINT="SDXL Turbo"
        ;;
    7)
        MODEL_NAME="SD 3.5 Medium"
        MODEL_URL="https://huggingface.co/stabilityai/stable-diffusion-3.5-medium/resolve/main/sd3.5_medium.safetensors"
        MODEL_SIZE_GB=5
        echo ""
        echo -e "${YELLOW}⚠ SD 3.5 Medium is gated on HuggingFace.${NC}"
        echo "  Accept the license at:"
        echo -e "  ${BLUE}https://huggingface.co/stabilityai/stable-diffusion-3.5-medium${NC}"
        read -p "  Enter your HuggingFace token (or press Enter to skip): " HF_TOKEN
        if [ -z "$HF_TOKEN" ]; then
            echo -e "${RED}✗ Download skipped (no token provided).${NC}"
            MODEL_URL=""
        fi
        TEMPLATE_HINT="SD3.5 Simple"
        ;;
    8)
        MODEL_NAME="Z-Image Turbo (BF16)"
        MODEL_URL="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
        MODEL_DIR="models/diffusion_models"
        MODEL_SIZE_GB=10
        TEMPLATE_HINT="Z-Image"
        EXTRA_DOWNLOADS=(
            "models/vae|https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors"
            "models/text_encoders|https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors"
        )
        ;;
    9)
        MODEL_NAME="LTX-Video 2B"
        MODEL_URL="https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltx-video-2b-v0.9.5.safetensors"
        MODEL_SIZE_GB=4
        TEMPLATE_HINT="LTX-Video"
        ;;
    *)
        echo ""
        echo "Skipping model download."
        echo -e "You can download models later from within ComfyUI using the ${BLUE}Manager${NC} extension,"
        echo -e "or browse ${BLUE}ComfyUI templates${NC} which auto-download required models."
        echo ""
        echo "Supported workflows include:"
        echo "  • Text to Image    — Generate from a text prompt"
        echo "  • Image to Image   — Transform sketches or photos"
        echo "  • Image Editing    — Relighting, depth, consistency"
        echo "  • Outpainting      — Extend images (like Photoshop generative extend)"
        echo "  • Upscaling        — Enhance resolution (Z-Image Turbo 2K, etc.)"
        ;;
esac

# --- Download ---
if [ -n "$MODEL_URL" ]; then
    MODEL_FILE=$(basename "$MODEL_URL")
    echo ""
    mkdir -p "$MODEL_DIR"

    if [ -f "$MODEL_DIR/$MODEL_FILE" ]; then
        echo -e "${GREEN}[3/3] ✓ ${MODEL_NAME} already downloaded, skipping.${NC}"
    else
        echo -e "${YELLOW}[3/3] Downloading ${MODEL_NAME}...${NC}"
        # Download with proper auth header for gated models
        if [ -n "${HF_TOKEN:-}" ]; then
            wget -nc -q --show-progress --header="Authorization: Bearer ${HF_TOKEN}" -P "$MODEL_DIR/" "$MODEL_URL"
        else
            wget -nc -q --show-progress -P "$MODEL_DIR/" "$MODEL_URL"
        fi
        DL_EXIT=$?

    if [ $DL_EXIT -eq 0 ]; then
        echo -e "${GREEN}✓ ${MODEL_NAME} downloaded to ${MODEL_DIR}/${NC}"
        if [ -n "$TEMPLATE_HINT" ]; then
            echo ""
            echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
            echo -e "${BLUE}│${NC}  ${GREEN}Next Step:${NC} Open ComfyUI and search templates for:       ${BLUE}│${NC}"
            echo -e "${BLUE}│${NC}  ${YELLOW}\"${TEMPLATE_HINT}\"${NC}                                          ${BLUE}│${NC}"
            echo -e "${BLUE}│${NC}                                                         ${BLUE}│${NC}"
            echo -e "${BLUE}│${NC}  The template will set up the correct workflow.          ${BLUE}│${NC}"
            if [ "${TEXT_ENC:-}" = "mistral_3_small_flux2_fp8.safetensors" ]; then
                echo -e "${BLUE}│${NC}                                                         ${BLUE}│${NC}"
                echo -e "${BLUE}│${NC}  ${YELLOW}⚠ Template may show 'Missing Models' for BF16${NC}          ${BLUE}│${NC}"
                echo -e "${BLUE}│${NC}  ${YELLOW}  text encoder (too large for ${VRAM_GB} GB GPU).${NC}            ${BLUE}│${NC}"
                echo -e "${BLUE}│${NC}  Close the dialog, then in the text encoder node,       ${BLUE}│${NC}"
                echo -e "${BLUE}│${NC}  select: ${GREEN}mistral_3_small_flux2_fp8.safetensors${NC}          ${BLUE}│${NC}"
            else
                echo -e "${BLUE}│${NC}  All required files have been pre-downloaded.            ${BLUE}│${NC}"
            fi
            echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"

        fi
    else
        echo -e "${RED}✗ Download failed (exit code ${DL_EXIT}).${NC}"
        echo "  Check your network connection and try again."
        echo "  For gated models, ensure your HuggingFace token has access."
        echo -e "  You can also download from within ComfyUI using the ${BLUE}Manager${NC} extension."
    fi
    fi  # end file-exists check

    # Download any extra files (VAE, CLIP, etc.)
    for extra in "${EXTRA_DOWNLOADS[@]}"; do
        EXTRA_DIR=$(echo "$extra" | cut -d'|' -f1)
        EXTRA_URL=$(echo "$extra" | cut -d'|' -f2)
        EXTRA_NAME=$(basename "$EXTRA_URL")
        mkdir -p "$EXTRA_DIR"
        if [ -f "$EXTRA_DIR/$EXTRA_NAME" ]; then
            echo -e "${GREEN}  ✓ ${EXTRA_NAME} (already exists)${NC}"
        else
            echo -e "${BLUE}  Downloading ${EXTRA_NAME}...${NC}"
            if [ -n "${HF_TOKEN:-}" ]; then
                wget -nc -q --show-progress --header="Authorization: Bearer ${HF_TOKEN}" -P "$EXTRA_DIR/" "$EXTRA_URL"
            else
                wget -nc -q --show-progress -P "$EXTRA_DIR/" "$EXTRA_URL"
            fi
        fi
    done
else
    echo ""
    echo -e "${YELLOW}[3/3] Skipping download.${NC}"
fi

# --- Write .env ---
cat > .env <<EOF
# Puget Systems — ComfyUI Configuration
# Generated by init.sh on $(date)

# Selected model (for reference only — ComfyUI loads from models/ directory)
SELECTED_MODEL=${MODEL_NAME:-none}

# GPU Info
GPU_NAME=${GPU_NAME}
GPU_COUNT=${GPU_COUNT}
VRAM_GB=${VRAM_GB}
TOTAL_VRAM=${TOTAL_VRAM}
IS_BLACKWELL=${IS_BLACKWELL}
EOF

echo ""
echo -e "${GREEN}✓ Configuration saved to .env${NC}"
echo ""
echo -e "  GPU:     ${GPU_COUNT}x ${GPU_NAME} (${TOTAL_VRAM} GB total)"
echo -e "  Model:   ${MODEL_NAME:-none}"
echo ""

# --- Launch ---
read -p "Start ComfyUI now? (Y/n): " START
if [[ "$START" != "n" && "$START" != "N" ]]; then
    echo -e "${BLUE}Starting ComfyUI...${NC}"
    smart_build
    if [ $? -ne 0 ]; then
        echo -e "${RED}Build failed. Cannot start container.${NC}"
        exit 1
    fi
    docker compose up -d

    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$LOCAL_IP" ]; then
        LOCAL_IP="<your-ip>"
    fi

    echo ""
    echo -e "${GREEN}✓ ComfyUI is starting.${NC}"
    echo -e "  Local:   ${BLUE}http://localhost:8188${NC}"
    echo -e "  Network: ${BLUE}http://${LOCAL_IP}:8188${NC}"
    echo ""
    echo -e "  ${DIM}Tip: Use the ${NC}Manager${DIM} button in the ComfyUI sidebar to browse${NC}"
    echo -e "  ${DIM}and install additional models and custom nodes (server-side).${NC}"
    echo ""
else
    echo "Run 'docker compose up -d' when ready."
fi
