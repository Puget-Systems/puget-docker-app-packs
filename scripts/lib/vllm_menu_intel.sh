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
#
# Models: unquantized FP16 only. The Intel XPU backend cannot run AWQ/GPTQ
# (CUDA-only dequant kernels) or bfloat16, so every entry here is an FP16 model
# that has been validated end-to-end on Intel Arc Pro B70 hardware. VRAM-gated
# so larger models only appear when enough aggregate GPU memory is present.

show_vllm_model_menu() {
    echo "  1) Qwen2.5 3B Instruct        - Fast general chat, FP16 (~6 GB)"
    echo "  2) Qwen3 8B                   - Thinking/reasoning model, FP16 (~16 GB) [Recommended]"
    echo "  3) Llama 3.1 8B Instruct      - General purpose, FP16 (~16 GB)"
    echo "  4) DeepSeek R1 Distill 8B     - Reasoning specialist, FP16 (~16 GB)"

    if [ "$TOTAL_VRAM" -ge 60 ]; then
        echo "  5) Qwen3.6 27B Dense          - Capable dense model, FP16 (~54 GB, multi-GPU)"
    else
        echo -e "  5) Qwen3.6 27B Dense          - ${RED}Requires ~60 GB total VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 80 ]; then
        echo "  6) Qwen3.6 35B-A3B MoE        - 3B active params, FP16 (~70 GB, multi-GPU)"
    else
        echo -e "  6) Qwen3.6 35B-A3B MoE        - ${RED}Requires ~80 GB total VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    echo "  7) Custom                     - Enter a HuggingFace model ID"
    echo "  8) Skip                       - I'll configure via .env later"
    MENU_MAX=8
}

# select_vllm_model <choice>
#   Sets: VLLM_MODEL_ID, VLLM_GPU_COUNT, VLLM_MODEL_SIZE_GB,
#         VLLM_TOOL_CALL_ARGS, VLLM_REASONING_ARGS, VLLM_THINKING_ARGS,
#         VLLM_EXTRA_ARGS, VLLM_DTYPE, VLLM_IMAGE, VLLM_GPU_MEM_UTIL, VLLM_MAX_CTX
#   Returns: 0 = model selected, 1 = VRAM insufficient, 2 = skipped/custom
select_vllm_model() {
    local choice="$1"
    # Common flags for Intel XPU vLLM
    local XPU_ARGS="--enforce-eager"

    # Defaults
    VLLM_MODEL_ID=""
    VLLM_GPU_COUNT=$GPU_COUNT
    VLLM_MODEL_SIZE_GB=0
    VLLM_TOOL_CALL_ARGS=""
    VLLM_REASONING_ARGS=""
    VLLM_THINKING_ARGS=""
    VLLM_EXTRA_ARGS="$XPU_ARGS"
    VLLM_DTYPE="float16"     # XPU cannot serve bfloat16
    if [ "$GPU_VENDOR" == "intel" ]; then
        VLLM_IMAGE="puget-vllm-xpu:b70"   # built from Dockerfile.xpu (LLM Scaler + patch)
    else
        VLLM_IMAGE="vllm/vllm-openai:latest"
    fi
    VLLM_MAX_CTX="32768"

    case $choice in
        1)
            VLLM_MODEL_ID="Qwen/Qwen2.5-3B-Instruct"; VLLM_MODEL_SIZE_GB=6
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
            ;;
        2)
            VLLM_MODEL_ID="Qwen/Qwen3-8B"; VLLM_MODEL_SIZE_GB=16
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            ;;
        3)
            VLLM_MODEL_ID="unsloth/meta-llama-3.1-8b-instruct"; VLLM_MODEL_SIZE_GB=16
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser llama3_json"
            ;;
        4)
            VLLM_MODEL_ID="deepseek-ai/DeepSeek-R1-Distill-Llama-8B"; VLLM_MODEL_SIZE_GB=16
            VLLM_REASONING_ARGS="--reasoning-parser deepseek_r1"
            ;;
        5)
            if [ "$TOTAL_VRAM" -lt 60 ]; then
                echo -e "${RED}✗ Qwen3.6 27B Dense (FP16) requires ~60 GB total VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="Qwen/Qwen3.6-27B"; VLLM_MODEL_SIZE_GB=54
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            ;;
        6)
            if [ "$TOTAL_VRAM" -lt 80 ]; then
                echo -e "${RED}✗ Qwen3.6 35B-A3B MoE (FP16) requires ~80 GB total VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="Qwen/Qwen3.6-35B-A3B"; VLLM_MODEL_SIZE_GB=70
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            ;;
        7)
            read -p "  Enter HuggingFace model ID (owner/model): " VLLM_MODEL_ID
            # Validate format: owner/model-name (letters, digits, dots, hyphens, underscores, colons)
            if [[ ! "$VLLM_MODEL_ID" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._:-]+$ ]]; then
                echo -e "${RED}✗ Invalid model ID format: '${VLLM_MODEL_ID}'${NC}"
                echo "  Expected format: owner/model-name (e.g. Qwen/Qwen3-8B)"
                VLLM_MODEL_ID=""
                return 2
            fi
            return 2
            ;;
        *)
            return 2
            ;;
    esac

    # --- Auto-tune GPU memory utilization based on model size vs available VRAM ---
    local available_vram=$((VRAM_GB * VLLM_GPU_COUNT))
    VLLM_GPU_MEM_UTIL="0.90"

    if [ "$VLLM_MODEL_SIZE_GB" -gt 0 ] 2>/dev/null && [ "$available_vram" -gt 0 ] 2>/dev/null; then
        local weight_pct=$((VLLM_MODEL_SIZE_GB * 100 / available_vram))

        if [ "$weight_pct" -ge 85 ]; then
            VLLM_GPU_MEM_UTIL="0.95"
        elif [ "$weight_pct" -ge 70 ]; then
            VLLM_GPU_MEM_UTIL="0.92"
        fi
    fi

    # Minimum host driver for the image this entry resolved to (gpu_detect.sh helper)
    VLLM_MIN_DRIVER=$(min_driver_for_image "$VLLM_IMAGE" 2>/dev/null || true)

    return 0
}
