#!/bin/bash
# Puget Systems — Shared vLLM Model Selection
# Source this file; do not execute directly.
#
# Prerequisites: source gpu_detect.sh and call detect_gpus first.
#   Required globals: GPU_VENDOR, GPU_COUNT, TOTAL_VRAM, VRAM_GB, NIGHTLY_PREFIX
#   Required colors:  GREEN, BLUE, YELLOW, RED, NC
#
# Usage:
#   show_vllm_model_menu          # prints the numbered model list
#   select_vllm_model <choice>    # sets VLLM_* output vars, returns 0/1/2

show_vllm_model_menu() {
    # Quantized models use online FP8 (--quantization fp8) on the FP16 weights — int4
    # (AWQ/GPTQ) has no WNA16 kernel on ROCm/RDNA4, but FP8 does. FP8 ~= half the FP16
    # footprint, so sizes below are the FP8 runtime size; the download is the FP16 repo.
    if [ "$TOTAL_VRAM" -ge 40 ]; then
        echo "  1) Qwen 3.6 (35B MoE FP8)     - Agentic reasoning, 128K ctx (~35 GB) [New]"
    else
        echo -e "  1) Qwen 3.6 (35B MoE FP8)     - ${RED}Requires ~40 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 30 ]; then
        echo "  2) Qwen 3.6 (27B Dense FP8)   - Multimodal agentic, 262K ctx (~27 GB) [New]"
    else
        echo -e "  2) Qwen 3.6 (27B Dense FP8)   - ${RED}Requires ~30 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 40 ]; then
        echo "  3) Qwen 3.5 (35B MoE FP8)     - 3B active params, 256K ctx (~35 GB)"
    else
        echo -e "  3) Qwen 3.5 (35B MoE FP8)     - ${RED}Requires ~40 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 128 ]; then
        echo "  4) Qwen 3.5 (122B MoE FP8)    - Flagship, 10B active, 128K ctx (~120 GB)"
    else
        echo -e "  4) Qwen 3.5 (122B MoE FP8)    - ${RED}Requires ~128 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 80 ]; then
        echo "  5) DeepSeek R1 (70B FP8)      - Reasoning specialist (~70 GB)"
    else
        echo -e "  5) DeepSeek R1 (70B FP8)      - ${RED}Requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 30 ]; then
        echo "  6) Gemma 3 (27B FP8)          - Google dense instruct (~27 GB)"
    else
        echo -e "  6) Gemma 3 (27B FP8)          - ${RED}Requires ~30 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    echo "  7) Llama 3.1 (8B Instruct)    - Standard FP16 dense, ungated (~16 GB)"

    echo "  8) Custom                     - Enter a HuggingFace model ID"
    echo "  9) Skip                       - I'll configure via .env later"
    echo ""
    echo "  Benchmark-only:"
    echo " 10) Qwen 3 (8B Dense FP16) TP=1 - Single GPU baseline (~16 GB)"

    if [ "$TOTAL_VRAM" -ge 56 ]; then
        echo " 11) Qwen 3.6 (27B Dense FP16)  - Unquantized dense, 262K ctx (~54 GB)"
    else
        echo -e " 11) Qwen 3.6 (27B Dense FP16)  - ${RED}Requires ~56 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    echo " 12) Qwen 2.5 (3B FP16) TP=1     - Single GPU baseline (~6 GB)"
    echo " 13) Llama 3.1 (8B FP16) TP=1    - Single GPU baseline (~16 GB)"
    echo " 14) DeepSeek R1 8B (FP16) TP=1  - Single GPU baseline (~16 GB)"

    MENU_MAX=14
}

# select_vllm_model <choice>
#   Sets: VLLM_MODEL_ID, VLLM_GPU_COUNT, VLLM_MODEL_SIZE_GB,
#         VLLM_TOOL_CALL_ARGS, VLLM_REASONING_ARGS, VLLM_THINKING_ARGS,
#         VLLM_EXTRA_ARGS, VLLM_DTYPE, VLLM_IMAGE, VLLM_GPU_MEM_UTIL, VLLM_MAX_CTX
#   Returns: 0 = model selected, 1 = VRAM insufficient, 2 = skipped/custom
select_vllm_model() {
    local choice="$1"
    # Common flags for eager mode (needed on Intel XPU and some MoE models)
    local EAGER_ARGS="--enforce-eager"

    # Defaults
    VLLM_MODEL_ID=""
    VLLM_GPU_COUNT=$GPU_COUNT
    VLLM_MODEL_SIZE_GB=0
    VLLM_TOOL_CALL_ARGS=""
    VLLM_REASONING_ARGS=""
    VLLM_THINKING_ARGS=""
    VLLM_EXTRA_ARGS=""
    VLLM_DTYPE="float16"

    # Vendor-specific default image
    if [ "${GPU_VENDOR:-nvidia}" = "amd" ]; then
        # Official AMD ROCm vLLM image, arch-pinned. vllm/vllm-openai-rocm:latest rotted
        # to a CUDA build (torch +cuXXX, hip=None) and can't see the GPU. The rocm/vllm
        # tags are per-GPU-arch; gfx120X covers RDNA4 (Radeon AI PRO R9700 / RX 9070, the
        # Puget AMD test cards). For other arches use the matching rocm/vllm tag
        # (gfx110X = RDNA3, gfx94X/gfx95X = Instinct) or override VLLM_IMAGE in .env.
        VLLM_IMAGE="${VLLM_IMAGE_AMD:-rocm/vllm:rocm7.13.0_gfx120X-all_ubuntu24.04_py3.13_pytorch_2.10.0_vllm_0.19.1}"
    elif [ "${GPU_VENDOR:-nvidia}" = "intel" ]; then
        VLLM_IMAGE="intel/llm-scaler-vllm:0.14.0-b8.2.1"
    else
        VLLM_IMAGE="vllm/vllm-openai:latest"
    fi
    VLLM_MAX_CTX=""

    case $choice in
        1)
            # Qwen 3.6 35B MoE — online FP8 quant of the FP16 weights (~35 GB runtime).
            if [ "$TOTAL_VRAM" -lt 40 ]; then
                echo -e "${RED}✗ Qwen 3.6 35B MoE FP8 requires ~40 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="Qwen/Qwen3.6-35B-A3B"; VLLM_MODEL_SIZE_GB=35
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_THINKING_ARGS="--default-chat-template-kwargs '{\"preserve_thinking\": true}'"
            VLLM_EXTRA_ARGS="--language-model-only --quantization fp8 $EAGER_ARGS"
            VLLM_MAX_CTX="65536"
            ;;
        2)
            if [ "$TOTAL_VRAM" -lt 30 ]; then
                echo -e "${RED}✗ Qwen 3.6 27B Dense FP8 requires ~30 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="Qwen/Qwen3.6-27B"; VLLM_MODEL_SIZE_GB=27
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="--language-model-only --quantization fp8 $EAGER_ARGS"
            ;;
        3)
            if [ "$TOTAL_VRAM" -lt 40 ]; then
                echo -e "${RED}✗ Qwen 3.5 35B MoE FP8 requires ~40 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="Qwen/Qwen3.5-35B-A3B"; VLLM_MODEL_SIZE_GB=35
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="--language-model-only --quantization fp8 $EAGER_ARGS"
            ;;
        4)
            if [ "$TOTAL_VRAM" -lt 128 ]; then
                echo -e "${RED}✗ Qwen 3.5 122B MoE FP8 requires ~128 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="Qwen/Qwen3.5-122B-A10B"; VLLM_MODEL_SIZE_GB=120
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="--quantization fp8 $EAGER_ARGS"
            VLLM_MAX_CTX="65536"
            ;;
        5)
            if [ "$TOTAL_VRAM" -lt 80 ]; then
                echo -e "${RED}✗ DeepSeek R1 70B FP8 requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="deepseek-ai/DeepSeek-R1-Distill-Llama-70B"; VLLM_MODEL_SIZE_GB=70
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
            VLLM_EXTRA_ARGS="--quantization fp8 $EAGER_ARGS"
            ;;
        6)
            # Gemma 4 has no public FP16 repo (gated/absent); use Gemma 3 27B instead.
            if [ "$TOTAL_VRAM" -lt 30 ]; then
                echo -e "${RED}✗ Gemma 3 27B FP8 requires ~30 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="unsloth/gemma-3-27b-it"; VLLM_MODEL_SIZE_GB=27
            VLLM_EXTRA_ARGS="--quantization fp8 $EAGER_ARGS"
            ;;
        7)
            # Ungated unsloth mirror — meta-llama/* is gated (403) and Llama-4 has no 8B.
            VLLM_MODEL_ID="unsloth/Meta-Llama-3.1-8B-Instruct"; VLLM_MODEL_SIZE_GB=16
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser llama3_json"
            VLLM_EXTRA_ARGS="$EAGER_ARGS"
            ;;
        8)
            read -r -p "  Enter HuggingFace model ID (owner/model): " VLLM_MODEL_ID
            # Validate format: owner/model-name (letters, digits, dots, hyphens, underscores, colons)
            if [[ ! "$VLLM_MODEL_ID" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._:-]+$ ]]; then
                echo -e "${RED}✗ Invalid model ID format: '${VLLM_MODEL_ID}'${NC}"
                echo "  Expected format: owner/model-name (e.g. cyankiwi/Qwen3.6-35B-A3B-AWQ-4bit)"
                VLLM_MODEL_ID=""
                return 2
            fi
            return 2
            ;;
        10)
            # Benchmark-only: Qwen3-8B FP16 forced to single GPU (TP=1)
            VLLM_MODEL_ID="Qwen/Qwen3-8B"; VLLM_MODEL_SIZE_GB=16
            VLLM_GPU_COUNT=1
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="$EAGER_ARGS"
            VLLM_MAX_CTX="32768"
            ;;
        11)
            # Benchmark-only: Qwen3.6-27B Dense unquantized FP16 (requires TP=4)
            if [ "$TOTAL_VRAM" -lt 56 ]; then
                echo -e "${RED}✗ Qwen 3.6 27B Dense FP16 requires ~56 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="Qwen/Qwen3.6-27B"; VLLM_MODEL_SIZE_GB=54
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="--language-model-only $EAGER_ARGS"
            VLLM_MAX_CTX="32768"
            ;;
        12)
            # Benchmark-only: Qwen2.5-3B FP16 forced to single GPU (TP=1)
            VLLM_MODEL_ID="Qwen/Qwen2.5-3B-Instruct"; VLLM_MODEL_SIZE_GB=6
            VLLM_GPU_COUNT=1
            VLLM_EXTRA_ARGS="$EAGER_ARGS"
            VLLM_MAX_CTX="32768"
            ;;
        13)
            # Benchmark-only: Llama 3.1 8B FP16 forced to single GPU (TP=1)
            # Ungated unsloth mirror (meta-llama/* is gated → 403 without a grant).
            VLLM_MODEL_ID="unsloth/Meta-Llama-3.1-8B-Instruct"; VLLM_MODEL_SIZE_GB=16
            VLLM_GPU_COUNT=1
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser llama3"
            VLLM_EXTRA_ARGS="$EAGER_ARGS"
            VLLM_MAX_CTX="32768"
            ;;
        14)
            # Benchmark-only: DeepSeek R1 8B FP16 forced to single GPU (TP=1)
            VLLM_MODEL_ID="deepseek-ai/DeepSeek-R1-Distill-Llama-8B"; VLLM_MODEL_SIZE_GB=16
            VLLM_GPU_COUNT=1
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
            VLLM_EXTRA_ARGS="$EAGER_ARGS"
            VLLM_MAX_CTX="32768"
            ;;
        *)
            return 2
            ;;
    esac

    # --- Auto-tune GPU memory utilization based on model size vs available VRAM ---
    local available_vram=$((VRAM_GB * VLLM_GPU_COUNT))

    if [ "${GPU_VENDOR:-nvidia}" = "amd" ]; then
        # AMD ROCm requires more VRAM headroom (RCCL, driver memory translation/GTT/ring buffers)
        if [ "$VLLM_GPU_COUNT" -gt 1 ]; then
            VLLM_GPU_MEM_UTIL="0.75" # Default to 0.75 for multi-GPU to give 25% headroom
        else
            VLLM_GPU_MEM_UTIL="0.80" # Default to 0.80 for single-GPU to give 20% headroom
        fi

        if [ "$VLLM_MODEL_SIZE_GB" -gt 0 ] 2>/dev/null; then
            local weight_pct=$((VLLM_MODEL_SIZE_GB * 100 / available_vram))
            if [ "$weight_pct" -ge 85 ]; then
                VLLM_GPU_MEM_UTIL="0.88" # Keep 12% headroom for weights
            elif [ "$weight_pct" -ge 70 ]; then
                VLLM_GPU_MEM_UTIL="0.82" # Keep 18% headroom
            elif [ "$weight_pct" -ge 50 ]; then
                VLLM_GPU_MEM_UTIL="0.78" # Keep 22% headroom
            fi
        fi

        # AMD/PCIe multi-GPU: vLLM's tensor-parallel all-reduce (RCCL) deadlocks on
        # PCIe-connected Radeon GPUs with no XGMI/Infinity-Fabric link. Use pipeline
        # parallelism (sequential layer split) instead. The compose emits
        # --tensor-parallel-size=$GPU_COUNT first, then EXTRA_VLLM_ARGS, so the later
        # --tensor-parallel-size 1 wins (argparse last-value), giving TP=1 + PP=N.
        if [ "$VLLM_GPU_COUNT" -gt 1 ]; then
            VLLM_EXTRA_ARGS="$VLLM_EXTRA_ARGS --tensor-parallel-size 1 --pipeline-parallel-size $VLLM_GPU_COUNT"
        fi
    else
        # NVIDIA / Intel defaults
        VLLM_GPU_MEM_UTIL="0.90"
        if [ "$VLLM_MODEL_SIZE_GB" -gt 0 ] 2>/dev/null; then
            local weight_pct=$((VLLM_MODEL_SIZE_GB * 100 / available_vram))
            if [ "$weight_pct" -ge 85 ]; then
                VLLM_GPU_MEM_UTIL="0.95"
            elif [ "$weight_pct" -ge 70 ]; then
                VLLM_GPU_MEM_UTIL="0.92"
            fi
        fi
    fi

    return 0
}
