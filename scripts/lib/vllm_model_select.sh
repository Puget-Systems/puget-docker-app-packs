#!/bin/bash
# Puget Systems — Shared vLLM Model Selection
# Source this file; do not execute directly.
#
# Prerequisites: source gpu_detect.sh and call detect_gpus first.
#   Required globals: GPU_COUNT, TOTAL_VRAM, VRAM_GB, NIGHTLY_PREFIX
#   Required colors:  GREEN, BLUE, YELLOW, RED, NC
#
# Usage:
#   show_vllm_model_menu          # prints the numbered model list
#   select_vllm_model <choice>    # sets VLLM_* output vars, returns 0/1/2

show_vllm_model_menu() {
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

    echo "  6) Nemotron 3 Nano (30B MoE)   - 3B active, long context (~20 GB NVFP4)"
    if [ "$TOTAL_VRAM" -ge 80 ]; then
        echo "  7) Nemotron 3 Super (120B MoE) - 12B active, flagship (~60 GB NVFP4)"
    else
        echo -e "  7) Nemotron 3 Super (120B MoE) - ${RED}Requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 56 ]; then
        echo "  8) Gemma 4 (26B MoE BF16)      - Google MoE Instruct, 3.8B active (~52 GB)"
    else
        echo -e "  8) Gemma 4 (26B MoE BF16)      - ${RED}Requires ~56 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    echo "  9) Custom                      - Enter a HuggingFace model ID"
    echo " 10) Skip                        - I'll configure via .env later"
    MENU_MAX=10
}

# select_vllm_model <choice>
#   Sets: VLLM_MODEL_ID, VLLM_GPU_COUNT, VLLM_MODEL_SIZE_GB,
#         VLLM_TOOL_CALL_ARGS, VLLM_REASONING_ARGS, VLLM_EXTRA_ARGS,
#         VLLM_DTYPE, VLLM_IMAGE, VLLM_GPU_MEM_UTIL, VLLM_MAX_CTX
#   Returns: 0 = model selected, 1 = VRAM insufficient, 2 = skipped/custom
select_vllm_model() {
    local choice="$1"

    # Defaults
    VLLM_MODEL_ID=""
    VLLM_GPU_COUNT=$GPU_COUNT
    VLLM_MODEL_SIZE_GB=0
    VLLM_TOOL_CALL_ARGS=""
    VLLM_REASONING_ARGS=""
    VLLM_EXTRA_ARGS=""
    VLLM_DTYPE="auto"
    VLLM_IMAGE="latest"
    VLLM_MAX_CTX=""

    case $choice in
        1)
            VLLM_MODEL_ID="Qwen/Qwen3-8B"; VLLM_GPU_COUNT=1; VLLM_MODEL_SIZE_GB=16
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
            ;;
        2)
            if [ "$TOTAL_VRAM" -lt 40 ]; then
                echo -e "${RED}✗ Qwen 3 32B FP8 requires ~40 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="Qwen/Qwen3-32B-FP8"; VLLM_MODEL_SIZE_GB=32
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
            ;;
        3)
            VLLM_MODEL_ID="cyankiwi/Qwen3.5-35B-A3B-AWQ-4bit"; VLLM_MODEL_SIZE_GB=22
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="--language-model-only --enforce-eager --no-enable-prefix-caching"
            VLLM_DTYPE="float16"
            VLLM_IMAGE="${NIGHTLY_PREFIX}"
            ;;
        4)
            if [ "$TOTAL_VRAM" -lt 80 ]; then
                echo -e "${RED}✗ Qwen 3.5 122B MoE AWQ requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="cyankiwi/Qwen3.5-122B-A10B-AWQ-4bit"; VLLM_MODEL_SIZE_GB=60
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="--language-model-only --enforce-eager --no-enable-prefix-caching"
            VLLM_DTYPE="float16"
            VLLM_IMAGE="${NIGHTLY_PREFIX}"
            ;;
        5)
            if [ "$TOTAL_VRAM" -lt 40 ]; then
                echo -e "${RED}✗ DeepSeek R1 70B AWQ requires ~40 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="Valdemardi/DeepSeek-R1-Distill-Llama-70B-AWQ"; VLLM_MODEL_SIZE_GB=38
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
            ;;
        6)
            VLLM_MODEL_ID="nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-NVFP4"; VLLM_MODEL_SIZE_GB=25
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="--enforce-eager --no-enable-prefix-caching"
            VLLM_IMAGE="${NIGHTLY_PREFIX}"
            ;;
        7)
            if [ "$TOTAL_VRAM" -lt 80 ]; then
                echo -e "${RED}✗ Nemotron 3 Super NVFP4 requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-NVFP4"; VLLM_MODEL_SIZE_GB=60
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="--enforce-eager --no-enable-prefix-caching"
            VLLM_IMAGE="${NIGHTLY_PREFIX}"
            ;;
        8)
            if [ "$TOTAL_VRAM" -lt 56 ]; then
                echo -e "${RED}✗ Gemma 4 26B MoE requires ~56 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="google/gemma-4-26B-A4B-it"; VLLM_MODEL_SIZE_GB=52
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser gemma4"
            VLLM_REASONING_ARGS="--reasoning-parser gemma4"
            VLLM_EXTRA_ARGS="--enforce-eager --no-enable-prefix-caching"
            VLLM_MAX_CTX=16384
            VLLM_IMAGE="${NIGHTLY_PREFIX}"
            ;;
        9)
            read -p "  Enter HuggingFace model ID: " VLLM_MODEL_ID
            return 2
            ;;
        *)
            return 2
            ;;
    esac

    # --- Auto-tune GPU memory utilization based on model size vs available VRAM ---
    local available_vram=$((VRAM_GB * VLLM_GPU_COUNT))
    VLLM_GPU_MEM_UTIL="0.90"
    # If the model case-block didn't set a specific MAX_CONTEXT cap,
    # leave it empty to let vLLM auto-detect based on available VRAM.
    VLLM_MAX_CTX="${VLLM_MAX_CTX:-}"

    if [ "$VLLM_MODEL_SIZE_GB" -gt 0 ] 2>/dev/null; then
        local weight_pct=$((VLLM_MODEL_SIZE_GB * 100 / available_vram))

        if [ "$weight_pct" -ge 85 ]; then
            VLLM_GPU_MEM_UTIL="0.95"
        elif [ "$weight_pct" -ge 70 ]; then
            VLLM_GPU_MEM_UTIL="0.92"
        fi
    fi

    return 0
}
