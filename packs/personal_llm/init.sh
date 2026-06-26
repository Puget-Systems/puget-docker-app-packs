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
echo -e "${BLUE}   Puget Systems — Personal LLM Setup${NC}"
echo -e "${BLUE}============================================================${NC}"

# --- Source shared libraries ---
INIT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
_LIBDIR=""
if [ -f "$INIT_DIR/scripts/lib/gpu_detect.sh" ]; then
    _LIBDIR="$INIT_DIR/scripts/lib"
else
    # Fallback: try repo root (when run from pack dir during dev)
    _REPO_ROOT="$(cd "$INIT_DIR/../.." 2>/dev/null && pwd)" || _REPO_ROOT=""
    [ -f "$_REPO_ROOT/scripts/lib/gpu_detect.sh" ] && _LIBDIR="$_REPO_ROOT/scripts/lib"
fi
if [ -z "$_LIBDIR" ]; then
    echo -e "${RED}✗ Cannot find shared libraries (gpu_detect.sh).${NC}"
    echo "  Run the installer first, or ensure scripts/lib/ exists."
    exit 1
fi
source "$_LIBDIR/gpu_detect.sh"
source "$_LIBDIR/ollama_model_select.sh"
source "$_LIBDIR/llama_menu_amd.sh"   # AMD Personal runs llama.cpp, not Ollama
source "$_LIBDIR/vllm_monitor.sh"     # wait_for_vllm (llama-server health poll)
source "$_LIBDIR/env_write.sh"

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
    # Safe key extraction — only read known keys, never execute .env as code
    CACHE_PROXY=$(grep '^CACHE_PROXY=' .env 2>/dev/null | tail -1 | cut -d= -f2- || true)
fi

if [ -z "${CACHE_PROXY:-}" ]; then
    echo -e "${YELLOW}⚠ No cache proxy configured (downloads go direct).${NC}"
    echo "  To enable, add CACHE_PROXY=http://<ip>:3128 to .env"
fi

# --- Model Selection ---
echo ""
echo -e "${YELLOW}[2/3] Select a model${NC}"
echo ""
echo "  Available models (based on ${TOTAL_VRAM} GB total VRAM):"
echo ""

# AMD Personal runs llama.cpp (OpenAI API, downloads via -hf at container start). Every
# other vendor runs Ollama (pull into the running container).
if [ "${GPU_VENDOR:-}" = "amd" ]; then
    show_llama_model_menu
    echo ""
    read -p "Select [1-${MENU_MAX}]: " CHOICE
    LL_RC=0
    select_llama_model "$CHOICE" || LL_RC=$?
    [ $LL_RC -eq 2 ] && { echo "Exiting."; exit 0; }
    [ $LL_RC -eq 1 ] && exit 1

    echo ""
    echo -e "${YELLOW}[3/3] Writing config and (re)launching llama.cpp...${NC}"
    write_env_var "MODEL_ID" "$LLAMA_MODEL_ID" ".env"
    write_env_var "MAX_CONTEXT" "$LLAMA_MAX_CTX" ".env"
    write_env_var "LLAMA_PARALLEL" "${LLAMA_PARALLEL:-2}" ".env"
    write_env_var "LLAMA_SPLIT_MODE" "${LLAMA_SPLIT_MODE:-layer}" ".env"
    write_env_var "LLAMA_IMAGE" "$LLAMA_IMAGE" ".env"
    echo -e "  Model:   ${LLAMA_MODEL_ID}"
    echo -e "  Context: ${LLAMA_MAX_CTX} (${LLAMA_PARALLEL:-2} slots → $((LLAMA_MAX_CTX / ${LLAMA_PARALLEL:-2})) per request)"
    echo -e "  GPUs:    split=${LLAMA_SPLIT_MODE:-layer} ($([ "${LLAMA_SPLIT_MODE:-layer}" = none ] && echo "single GPU, fastest" || echo "both GPUs"))"

    # Recreate the inference container so llama-server restarts with the new model/context.
    docker compose up -d

    echo -e "${BLUE}llama.cpp is downloading the model and starting (5–30 min)...${NC}"
    wait_for_vllm "puget_ollama" "${LLAMA_MODEL_SIZE_GB:-0}" || true
    echo ""
    echo -e "${GREEN}✓ Ready.${NC}  Chat UI: ${BLUE}http://localhost:3000${NC}"
    echo -e "  Pick the model from the dropdown at the top."
    exit 0
fi

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
