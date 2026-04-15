#!/bin/bash
set -euo pipefail

# Puget Systems — Personal LLM Initialization
# Detects GPUs, recommends a model, pulls via Ollama, launches the stack.

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}   Puget Systems — Personal LLM Setup (Ollama)${NC}"
echo -e "${BLUE}============================================================${NC}"

# --- Source shared libraries ---
INIT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
if [ -f "$INIT_DIR/scripts/lib/gpu_detect.sh" ]; then
    source "$INIT_DIR/scripts/lib/gpu_detect.sh"
    source "$INIT_DIR/scripts/lib/ollama_model_select.sh"
else
    # Fallback: try repo root (when run from pack dir during dev)
    _REPO_ROOT="$(cd "$INIT_DIR/../.." 2>/dev/null && pwd)" || _REPO_ROOT=""
    if [ -f "$_REPO_ROOT/scripts/lib/gpu_detect.sh" ]; then
        source "$_REPO_ROOT/scripts/lib/gpu_detect.sh"
        source "$_REPO_ROOT/scripts/lib/ollama_model_select.sh"
    else
        echo -e "${RED}✗ Cannot find shared libraries (gpu_detect.sh).${NC}"
        echo "  Run the installer first, or ensure scripts/lib/ exists."
        exit 1
    fi
fi

# --- GPU Detection ---
echo ""
echo -e "${YELLOW}[1/3] Detecting GPUs...${NC}"

if detect_gpus; then
    echo -e "${GREEN}✓ Found ${GPU_COUNT}x ${GPU_NAME} (${VRAM_GB} GB each, ${TOTAL_VRAM} GB total)${NC}"
    if [ "$IS_BLACKWELL" = true ]; then
        echo -e "${GREEN}  Blackwell GPU detected (compute ${COMPUTE_CAP})${NC}"
    fi
else
    GPU_COUNT=1
    TOTAL_VRAM=0
    VRAM_GB=0
    echo -e "${YELLOW}⚠ nvidia-smi not found, cannot detect VRAM.${NC}"
    echo "  All models will be shown without VRAM gating."
fi

# --- Cache Proxy Status ---
if [ -f .env ]; then
    source .env 2>/dev/null || true
fi

if [ -n "${CACHE_PROXY:-}" ]; then
    echo -e "${GREEN}✓ Cache Proxy: $CACHE_PROXY${NC}"
else
    echo -e "${YELLOW}⚠ No cache proxy configured (downloads go direct).${NC}"
    echo "  To enable, add CACHE_PROXY=http://<ip>:3128 to .env"
fi

# --- Model Selection ---
echo ""
echo -e "${YELLOW}[2/3] Select a model${NC}"
echo ""
echo "  Available models (based on ${TOTAL_VRAM} GB total VRAM):"
echo ""
show_ollama_model_menu
echo ""
read -p "Select [1-${MENU_MAX}]: " CHOICE

SELECT_RC=0
select_ollama_model "$CHOICE" || SELECT_RC=$?

if [ $SELECT_RC -eq 2 ]; then
    echo "Exiting."
    exit 0
elif [ $SELECT_RC -eq 1 ]; then
    # VRAM insufficient — message already printed by select_ollama_model
    exit 1
fi

# --- Pull Model ---
echo ""
echo -e "${YELLOW}[3/3] Downloading ${OLLAMA_MODEL_TAG}...${NC}"

if ! wait_for_ollama; then
    exit 1
fi

echo -e "${BLUE}Pulling ${OLLAMA_MODEL_TAG}... (This may take a while for larger models)${NC}"
docker compose exec -T inference ollama pull "$OLLAMA_MODEL_TAG"

echo ""
echo -e "${GREEN}✓ Model ready!${NC}"
echo -e "  Access the Chat UI at: ${BLUE}http://localhost:3000${NC}"
echo -e "  Select '${OLLAMA_MODEL_TAG}' from the dropdown at the top."
