#!/bin/bash
set -euo pipefail
# Puget Systems — Team LLM Initialization
# Detects GPUs, recommends a model, writes .env, launches the stack.

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}   Puget Systems — Team LLM Setup (vLLM)${NC}"
echo -e "${BLUE}============================================================${NC}"

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

# Detect compute capability for CUDA version selection
# Blackwell (RTX 50xx) = compute_cap 12.0+ → requires cu130 Docker images
COMPUTE_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1)
COMPUTE_MAJOR=$(echo "$COMPUTE_CAP" | cut -d. -f1)
if [ "${COMPUTE_MAJOR:-0}" -ge 12 ] 2>/dev/null; then
    NIGHTLY_PREFIX="cu130-nightly"
    IS_BLACKWELL=true
    echo -e "${GREEN}✓ Found ${GPU_COUNT}x ${GPU_NAME} (${VRAM_GB} GB each, ${TOTAL_VRAM} GB total)${NC}"
    echo -e "${GREEN}  Blackwell GPU detected (compute ${COMPUTE_CAP}) → using CUDA 13.0 images${NC}"
else
    NIGHTLY_PREFIX="nightly"
    IS_BLACKWELL=false
    echo -e "${GREEN}✓ Found ${GPU_COUNT}x ${GPU_NAME} (${VRAM_GB} GB each, ${TOTAL_VRAM} GB total)${NC}"
fi

# --- Cache Proxy Status ---
if [ -f .env ]; then
    source .env 2>/dev/null
fi

if [ -n "$CACHE_PROXY" ]; then
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

# 1) Qwen 3 8B — always fits
echo "  1) Qwen 3 (8B)                - Fast, single GPU (~16 GB BF16)"

# 2) Qwen 3 32B FP8 — near-lossless, needs ~32 GB
if [ "$TOTAL_VRAM" -ge 40 ]; then
    echo "  2) Qwen 3 (32B FP8)           - Near-lossless quality (~32 GB)"
else
    echo -e "  2) Qwen 3 (32B FP8)           - ${RED}Requires ~40 GB VRAM${NC}"
fi

# 3) Qwen 3.5 35B MoE AWQ — tiny active params, fits almost anywhere
# 4) Qwen 3.5 122B MoE AWQ — flagship MoE, needs ~60 GB
echo "  3) Qwen 3.5 (35B MoE AWQ)     - 3B active params, fast (~18 GB)"
if [ "$TOTAL_VRAM" -ge 80 ]; then
    echo "  4) Qwen 3.5 (122B MoE AWQ)    - Flagship, 10B active (~60 GB) [Recommended]"
else
    echo -e "  4) Qwen 3.5 (122B MoE AWQ)    - ${RED}Requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
fi

# 5) DeepSeek R1 70B AWQ — reasoning specialist
if [ "$TOTAL_VRAM" -ge 40 ]; then
    echo "  5) DeepSeek R1 (70B AWQ)      - Reasoning specialist (~38 GB)"
else
    echo -e "  5) DeepSeek R1 (70B AWQ)      - ${RED}Requires ~40 GB VRAM${NC}"
fi

echo "  6) Custom                      - Enter a HuggingFace model ID"
echo "  7) Skip                        - I'll configure via .env later"
echo ""
read -p "Select [1-7]: " CHOICE

MODEL_ID=""
PARALLEL=$GPU_COUNT
MODEL_SIZE_GB=0      # Approximate weight size in GB for memory planning
TOOL_CALL_ARGS=""    # vLLM tool call parser args (auto-set per model)
REASONING_ARGS=""    # vLLM reasoning parser (e.g. --reasoning-parser qwen3)
EXTRA_VLLM_ARGS=""   # Additional vLLM args (e.g. --language-model-only)
DTYPE="auto"         # Data type (auto, float16, bfloat16) — AWQ requires float16
VLLM_IMAGE="latest"  # Docker image tag (nightly for new architectures)
case $CHOICE in
    1) MODEL_ID="Qwen/Qwen3-8B"; PARALLEL=1; MODEL_SIZE_GB=16
       TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes" ;;
    2)
        if [ "$TOTAL_VRAM" -lt 40 ]; then
            echo -e "${RED}✗ Qwen 3 32B FP8 requires ~40 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
            exit 1
        fi
        MODEL_ID="Qwen/Qwen3-32B-FP8"; MODEL_SIZE_GB=32
        TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
        ;;
    3)
        MODEL_ID="cyankiwi/Qwen3.5-35B-A3B-AWQ-4bit"; MODEL_SIZE_GB=22; PARALLEL=$GPU_COUNT
        TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
        REASONING_ARGS="--reasoning-parser qwen3"
        EXTRA_VLLM_ARGS="--language-model-only --enforce-eager --no-enable-prefix-caching"
        DTYPE="float16"
        VLLM_IMAGE="${NIGHTLY_PREFIX}"
        ;;
    4)
        if [ "$TOTAL_VRAM" -lt 80 ]; then
            echo -e "${RED}✗ Qwen 3.5 122B MoE AWQ requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
            exit 1
        fi
        MODEL_ID="cyankiwi/Qwen3.5-122B-A10B-AWQ-4bit"; MODEL_SIZE_GB=60
        TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
        REASONING_ARGS="--reasoning-parser qwen3"
        EXTRA_VLLM_ARGS="--language-model-only --enforce-eager --no-enable-prefix-caching"
        DTYPE="float16"
        VLLM_IMAGE="${NIGHTLY_PREFIX}"
        ;;
    5)
        if [ "$TOTAL_VRAM" -lt 40 ]; then
            echo -e "${RED}✗ DeepSeek R1 70B AWQ requires ~40 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
            exit 1
        fi
        MODEL_ID="Valdemardi/DeepSeek-R1-Distill-Llama-70B-AWQ"; MODEL_SIZE_GB=38
        TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
        ;;
    6) read -p "  Enter HuggingFace model ID: " MODEL_ID ;;
    *) echo "Exiting."; exit 0 ;;
esac

if [ -z "$MODEL_ID" ]; then
    echo -e "${RED}No model selected.${NC}"
    exit 1
fi

# --- Auto-tune GPU memory settings based on model size vs available VRAM ---
AVAILABLE_VRAM=$((VRAM_GB * PARALLEL))

# Calculate optimal GPU memory utilization and context length
GPU_MEM_UTIL="0.90"    # Default: 90%
MAX_CTX=32768          # Default context length

if [ "$MODEL_SIZE_GB" -gt 0 ] 2>/dev/null; then
    # How much of VRAM do weights need? (as percentage)
    WEIGHT_PCT=$((MODEL_SIZE_GB * 100 / AVAILABLE_VRAM))
    
    if [ "$WEIGHT_PCT" -ge 85 ]; then
        # Tight — high utilization, reduced context
        GPU_MEM_UTIL="0.95"
        MAX_CTX=8192
    elif [ "$WEIGHT_PCT" -ge 70 ]; then
        # Tight — high utilization, reduced context
        GPU_MEM_UTIL="0.92"
        MAX_CTX=16384
    else
        # Comfortable fit
        GPU_MEM_UTIL="0.90"
        MAX_CTX=32768
    fi
fi

# Qwen 3.5 MoE note: hybrid GDN+attention uses more memory per token than pure
# attention models, and Triton autotuner needs scratch space. Keep moderate context.
case "$MODEL_ID" in
    cyankiwi/Qwen3.5-*)
        if [ "$MAX_CTX" -gt 16384 ]; then
            MAX_CTX=16384
            echo -e "${YELLOW}  Note: Qwen 3.5 MoE context capped to ${MAX_CTX} tokens (hybrid GDN+attention memory)${NC}"
        fi
        ;;
esac

# --- Write Config ---
echo ""
echo -e "${YELLOW}[3/3] Writing configuration...${NC}"

# Write or update .env
cat > .env <<EOF
# Puget Systems — Team LLM Configuration
# Generated by init.sh on $(date)

# Model to serve (HuggingFace model ID)
MODEL_ID=${MODEL_ID}

# vLLM Docker image tag (latest or nightly for bleeding-edge models)
VLLM_IMAGE=${VLLM_IMAGE}

# Number of GPUs for tensor parallelism
GPU_COUNT=${PARALLEL}

# Maximum context length (tokens)
MAX_CONTEXT=${MAX_CTX}

# GPU memory utilization (0.0-1.0, auto-tuned for ${MODEL_SIZE_GB}GB model on ${AVAILABLE_VRAM}GB VRAM)
GPU_MEMORY_UTILIZATION=${GPU_MEM_UTIL}

# Reasoning parser (e.g. Qwen3.5 thinking mode)
REASONING_ARGS=${REASONING_ARGS}

# Tool call parser and auto-tool-choice (auto-set per model)
TOOL_CALL_ARGS=${TOOL_CALL_ARGS}

# Extra vLLM args (e.g. --language-model-only for text-only Qwen3.5)
EXTRA_VLLM_ARGS=${EXTRA_VLLM_ARGS}

# Data type (auto, float16, bfloat16) — AWQ models require float16
DTYPE=${DTYPE}

# Cache proxy (optional, for faster model downloads)
# CACHE_PROXY=http://<ip>:3128
EOF

# Preserve cache proxy if it was set
if [ -n "$CACHE_PROXY" ]; then
    sed -i "s|# CACHE_PROXY=.*|CACHE_PROXY=${CACHE_PROXY}|" .env
fi

echo -e "${GREEN}✓ Configuration written to .env${NC}"
echo ""
echo "  Model:    $MODEL_ID"
echo "  GPUs:     $PARALLEL"
echo "  Context:  $MAX_CTX tokens"
echo "  Memory:   $GPU_MEM_UTIL utilization"
echo ""

read -p "Start the stack now? (Y/n): " START
if [[ "$START" != "n" && "$START" != "N" ]]; then
    echo -e "${BLUE}Starting vLLM server...${NC}"
    docker compose up -d
    echo ""
    
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}✓ Stack starting.${NC}"
    echo -e "  Chat UI:  ${BLUE}http://localhost:3000${NC}"
    echo -e "  API:      ${BLUE}http://localhost:8000/v1${NC}"
    echo -e "  Network:  ${BLUE}http://${LOCAL_IP}:3000${NC}"
    echo ""
    
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
            # Download phase detected from log output.
            # Don't trust tqdm values from logs (they go stale quickly).
            # Always use docker stats NET I/O for live progress.
            CANDIDATE_PHASE="Downloading model"
            CANDIDATE_LEVEL=1
            DETAIL=""  # Will be filled by NET I/O below
        fi
        
        # For any phase at level <= 1 (Starting up, Initializing, Downloading),
        # check NET I/O to detect silent downloads or show live progress.
        # This catches the case where tqdm never flushes OR has gone stale.
        if [ "$CANDIDATE_LEVEL" -le 1 ] || [ -z "$CANDIDATE_PHASE" ]; then
            NET_RX=$(docker stats "$CONTAINER_NAME" --no-stream --format '{{.NetIO}}' 2>/dev/null | awk -F'/' '{print $1}' | xargs)
            NET_VAL=$(echo "$NET_RX" | grep -oE '[0-9.]+' | head -1)
            NET_UNIT=$(echo "$NET_RX" | grep -oE '[A-Za-z]+' | head -1)
            
            # Convert to GB for percentage calculation
            NET_GB=0
            case "$NET_UNIT" in
                GB|GiB) NET_GB=$(echo "$NET_VAL" | cut -d. -f1) ;;
                MB|MiB) NET_GB=0 ;;
                TB|TiB) NET_GB=$(($(echo "$NET_VAL" | cut -d. -f1) * 1024)) ;;
            esac
            
            # If significant network activity, show download progress
            if [ "$NET_GB" -gt 0 ] 2>/dev/null && [ "$MODEL_SIZE_GB" -gt 0 ] 2>/dev/null; then
                DL_PCT=$((NET_GB * 100 / MODEL_SIZE_GB))
                [ "$DL_PCT" -gt 100 ] && DL_PCT=100
                CANDIDATE_PHASE="Downloading model"
                CANDIDATE_LEVEL=1
                DETAIL="${DL_PCT}% (${NET_RX} / ${MODEL_SIZE_GB} GB)"
            elif [ -n "$NET_VAL" ] && echo "$NET_UNIT" | grep -qiE "MB|MiB" 2>/dev/null; then
                # Sub-GB download — show raw value
                NET_MB=$(echo "$NET_VAL" | cut -d. -f1)
                if [ "${NET_MB:-0}" -gt 50 ] 2>/dev/null; then
                    # More than 50 MB downloaded — probably model data
                    CANDIDATE_PHASE="Downloading model"
                    CANDIDATE_LEVEL=1
                    DETAIL="${NET_RX}"
                elif [ -z "$CANDIDATE_PHASE" ]; then
                    # Small amount — could be metadata
                    if echo "$LAST_LOG" | grep -q "Resolved architecture\|model_tag\|max_model_len"; then
                        CANDIDATE_PHASE="Initializing model"
                        CANDIDATE_LEVEL=0
                        DETAIL=""
                    else
                        CANDIDATE_PHASE="Starting up"
                        CANDIDATE_LEVEL=0
                        DETAIL="waiting..."
                    fi
                fi
            elif [ -z "$CANDIDATE_PHASE" ]; then
                # No network activity and no log match
                if echo "$LAST_LOG" | grep -q "Resolved architecture\|model_tag\|max_model_len"; then
                    CANDIDATE_PHASE="Initializing model"
                    CANDIDATE_LEVEL=0
                    DETAIL=""
                else
                    CANDIDATE_PHASE="Starting up"
                    CANDIDATE_LEVEL=0
                    DETAIL="waiting..."
                fi
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
else
    echo "Run 'docker compose up -d' when ready."
fi
