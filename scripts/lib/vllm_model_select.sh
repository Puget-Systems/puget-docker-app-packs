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
    echo "  1) Qwen 3.6 (35B MoE GPTQ)    - Agentic reasoning, 128K ctx (~22 GB) [New]"

    if [ "$TOTAL_VRAM" -ge 18 ]; then
        echo "  2) Qwen 3.6 (27B Dense GPTQ)  - Multimodal agentic, 262K ctx (~18 GB) [New]"
    else
        echo -e "  2) Qwen 3.6 (27B Dense GPTQ)  - ${RED}Requires ~18 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 22 ]; then
        echo "  3) Qwen 3.5 (35B MoE GPTQ)    - 3B active params, 256K ctx (~22 GB)"
    else
        echo -e "  3) Qwen 3.5 (35B MoE GPTQ)    - ${RED}Requires ~22 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 80 ]; then
        echo "  4) Qwen 3.5 (122B MoE GPTQ)   - Flagship, 10B active, 128K ctx (~60 GB) [Recommended]"
    else
        echo -e "  4) Qwen 3.5 (122B MoE GPTQ)   - ${RED}Requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 40 ]; then
        echo "  5) DeepSeek R1 (70B GPTQ)     - Reasoning specialist (~38 GB)"
    else
        echo -e "  5) DeepSeek R1 (70B GPTQ)     - ${RED}Requires ~40 GB VRAM${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 20 ]; then
        echo "  6) Gemma 4 (26B MoE GPTQ)     - Google MoE Instruct, 3.8B active (~18 GB)"
    else
        echo -e "  6) Gemma 4 (26B MoE GPTQ)     - ${RED}Requires ~20 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    echo "  7) Llama 4 (8B FP16)          - Standard FP16, Intel optimized (~16 GB)"

    echo "  8) Custom                     - Enter a HuggingFace model ID"
    echo "  9) Skip                       - I'll configure via .env later"
    MENU_MAX=9
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
    VLLM_EXTRA_ARGS=""
    VLLM_DTYPE="float16"
    VLLM_IMAGE="intel/vllm:xpu"
    VLLM_MAX_CTX=""

    case $choice in
        1)
            VLLM_MODEL_ID="cyankiwi/Qwen3.6-35B-A3B-GPTQ-Int4"; VLLM_MODEL_SIZE_GB=22
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_THINKING_ARGS="--default-chat-template-kwargs '{\"preserve_thinking\": true}'"
            VLLM_EXTRA_ARGS="$XPU_ARGS"
            local total_avail=$((TOTAL_VRAM))
            if [ "$total_avail" -ge 48 ]; then
                VLLM_MAX_CTX="131072"
            else
                VLLM_MAX_CTX="65536"
            fi
            ;;
        2)
            if [ "$TOTAL_VRAM" -lt 18 ]; then
                echo -e "${RED}✗ Qwen 3.6 27B Dense GPTQ requires ~18 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="cyankiwi/Qwen3.6-27B-GPTQ-Int4"; VLLM_MODEL_SIZE_GB=18
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="--language-model-only $XPU_ARGS"
            ;;
        3)
            VLLM_MODEL_ID="cyankiwi/Qwen3.5-35B-A3B-GPTQ-Int4"; VLLM_MODEL_SIZE_GB=22
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="--language-model-only $XPU_ARGS"
            ;;
        4)
            if [ "$TOTAL_VRAM" -lt 80 ]; then
                echo -e "${RED}✗ Qwen 3.5 122B MoE GPTQ requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="cyankiwi/Qwen3.5-122B-A10B-GPTQ-Int4"; VLLM_MODEL_SIZE_GB=60
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="--language-model-only $XPU_ARGS"
            VLLM_MAX_CTX="65536"
            ;;
        5)
            if [ "$TOTAL_VRAM" -lt 40 ]; then
                echo -e "${RED}✗ DeepSeek R1 70B GPTQ requires ~40 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="Valdemardi/DeepSeek-R1-Distill-Llama-70B-GPTQ"; VLLM_MODEL_SIZE_GB=38
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
            ;;
        6)
            if [ "$TOTAL_VRAM" -lt 20 ]; then
                echo -e "${RED}✗ Gemma 4 26B MoE GPTQ requires ~20 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="cyankiwi/gemma-4-26B-A4B-it-GPTQ-Int4"; VLLM_MODEL_SIZE_GB=18
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser gemma4"
            VLLM_REASONING_ARGS="--reasoning-parser gemma4"
            VLLM_EXTRA_ARGS="$XPU_ARGS"
            ;;
        7)
            VLLM_MODEL_ID="meta-llama/Meta-Llama-4-8B-Instruct"; VLLM_MODEL_SIZE_GB=16
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser llama4"
            VLLM_EXTRA_ARGS="$XPU_ARGS"
            ;;
        8)
            read -p "  Enter HuggingFace model ID (owner/model): " VLLM_MODEL_ID
            # Validate format: owner/model-name (letters, digits, dots, hyphens, underscores, colons)
            if [[ ! "$VLLM_MODEL_ID" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._:-]+$ ]]; then
                echo -e "${RED}✗ Invalid model ID format: '${VLLM_MODEL_ID}'${NC}"
                echo "  Expected format: owner/model-name (e.g. cyankiwi/Qwen3.6-35B-A3B-GPTQ-Int4)"
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
