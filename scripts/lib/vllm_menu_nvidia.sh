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
    echo "  1) Qwen 3.6 (35B MoE AWQ)     - Agentic reasoning, 128K ctx (~22 GB) [New]"

    if [ "$TOTAL_VRAM" -ge 18 ]; then
        echo "  2) Qwen 3.6 (27B Dense AWQ)   - Multimodal agentic, 262K ctx (~18 GB) [New]"
    else
        echo -e "  2) Qwen 3.6 (27B Dense AWQ)   - ${RED}Requires ~18 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 22 ]; then
        echo "  3) Qwen 3.5 (35B MoE AWQ)     - 3B active params, 256K ctx (~22 GB)"
    else
        echo -e "  3) Qwen 3.5 (35B MoE AWQ)     - ${RED}Requires ~22 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 80 ]; then
        echo "  4) Qwen 3.5 (122B MoE AWQ)    - Flagship, 10B active, 128K ctx (~60 GB) [Recommended]"
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

    if [ "$TOTAL_VRAM" -ge 20 ]; then
        echo "  8) Gemma 4 (26B MoE AWQ)       - Google MoE Instruct, 3.8B active (~18 GB)"
    else
        echo -e "  8) Gemma 4 (26B MoE AWQ)       - ${RED}Requires ~20 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    echo "  9) GPT-OSS (20B MoE MXFP4)    - OpenAI open-weight, fast local inference (~16 GB)"

    if [ "$TOTAL_VRAM" -ge 80 ]; then
        echo " 10) GPT-OSS (120B MoE MXFP4)   - OpenAI flagship open-weight, 80 GB+"
    else
        echo -e " 10) GPT-OSS (120B MoE MXFP4)   - ${RED}Requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 20 ]; then
        echo " 11) Qwen 3.6 (27B NVFP4)       - Blackwell FP4 + MTP spec-decode, ~4-5x faster (~14 GB) [New]"
    else
        echo -e " 11) Qwen 3.6 (27B NVFP4)       - ${RED}Requires ~20 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 20 ]; then
        echo " 12) Qwen 3.8 (27B NVFP4)       - Blackwell FP4 + MTP, hybrid attn, 262K ctx (~16 GB) [New]"
    else
        echo -e " 12) Qwen 3.8 (27B NVFP4)       - ${RED}Requires ~20 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    echo " 13) Custom                      - Enter a HuggingFace model ID"
    echo " 14) Skip                        - I'll configure via .env later"
    MENU_MAX=14
}

# select_vllm_model <choice>
#   Sets: VLLM_MODEL_ID, VLLM_GPU_COUNT, VLLM_MODEL_SIZE_GB,
#         VLLM_TOOL_CALL_ARGS, VLLM_REASONING_ARGS, VLLM_THINKING_ARGS,
#         VLLM_EXTRA_ARGS, VLLM_DTYPE, VLLM_IMAGE, VLLM_GPU_MEM_UTIL, VLLM_MAX_CTX,
#         VLLM_MIN_DRIVER (min NVIDIA driver major for the chosen image, empty = no gate)
#   Returns: 0 = model selected, 1 = VRAM insufficient, 2 = skipped/custom
select_vllm_model() {
    local choice="$1"
    # Common flags for MoE/nightly models that need eager mode
    local EAGER_ARGS="--enforce-eager --no-enable-prefix-caching"

    # Defaults
    VLLM_MODEL_ID=""
    VLLM_GPU_COUNT=$GPU_COUNT
    VLLM_MODEL_SIZE_GB=0
    VLLM_TOOL_CALL_ARGS=""
    VLLM_REASONING_ARGS=""
    VLLM_THINKING_ARGS=""
    VLLM_EXTRA_ARGS=""
    VLLM_ENABLE_MTP=""
    VLLM_EXTRA_PIP=""
    VLLM_DTYPE="auto"
    VLLM_IMAGE="vllm/vllm-openai:v0.20.2"
    VLLM_MAX_CTX=""

    case $choice in
        1)
            # Qwen 3.6: standard attention (no GDN), so no --language-model-only needed.
            # Context window scales with available VRAM — vLLM distributes KV cache across
            # all GPUs via tensor parallelism, so multi-GPU setups unlock proportionally more context.
            VLLM_MODEL_ID="cyankiwi/Qwen3.6-35B-A3B-AWQ-4bit"; VLLM_MODEL_SIZE_GB=22
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_THINKING_ARGS="--default-chat-template-kwargs '{\"preserve_thinking\": true}'"
            VLLM_EXTRA_ARGS="$EAGER_ARGS"
            VLLM_DTYPE="float16"
            VLLM_IMAGE="vllm/vllm-openai:${NIGHTLY_PREFIX}"
            local total_avail=$((TOTAL_VRAM))
            if [ "$total_avail" -ge 48 ]; then
                VLLM_MAX_CTX="262144"   # Full native 262K — comfortable on 48GB+
            elif [ "$total_avail" -ge 24 ]; then
                VLLM_MAX_CTX="131072"   # 128K — safe on single 24GB GPU
            else
                VLLM_MAX_CTX="65536"    # 64K — for tighter single-GPU setups
            fi
            ;;
        2)
            if [ "$TOTAL_VRAM" -lt 18 ]; then
                echo -e "${RED}✗ Qwen 3.6 27B Dense AWQ requires ~18 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="cyankiwi/Qwen3.6-27B-AWQ-INT4"; VLLM_MODEL_SIZE_GB=18
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="--language-model-only $EAGER_ARGS"
            VLLM_DTYPE="float16"
            VLLM_IMAGE="vllm/vllm-openai:${NIGHTLY_PREFIX}"
            ;;
        3)
            VLLM_MODEL_ID="cyankiwi/Qwen3.5-35B-A3B-AWQ-4bit"; VLLM_MODEL_SIZE_GB=22
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="--language-model-only $EAGER_ARGS"
            VLLM_DTYPE="float16"
            VLLM_IMAGE="vllm/vllm-openai:${NIGHTLY_PREFIX}"
            ;;
        4)
            if [ "$TOTAL_VRAM" -lt 80 ]; then
                echo -e "${RED}✗ Qwen 3.5 122B MoE AWQ requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="cyankiwi/Qwen3.5-122B-A10B-AWQ-4bit"; VLLM_MODEL_SIZE_GB=60
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="--language-model-only $EAGER_ARGS"
            VLLM_DTYPE="float16"
            VLLM_IMAGE="vllm/vllm-openai:${NIGHTLY_PREFIX}"
            VLLM_MAX_CTX="131072"
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
            VLLM_EXTRA_ARGS="$EAGER_ARGS"
            VLLM_IMAGE="vllm/vllm-openai:${NIGHTLY_PREFIX}"
            ;;
        7)
            if [ "$TOTAL_VRAM" -lt 80 ]; then
                echo -e "${RED}✗ Nemotron 3 Super NVFP4 requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-NVFP4"; VLLM_MODEL_SIZE_GB=60
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_EXTRA_ARGS="$EAGER_ARGS"
            VLLM_IMAGE="vllm/vllm-openai:${NIGHTLY_PREFIX}"
            ;;
        8)
            if [ "$TOTAL_VRAM" -lt 20 ]; then
                echo -e "${RED}✗ Gemma 4 26B MoE AWQ requires ~20 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="cyankiwi/gemma-4-26B-A4B-it-AWQ-4bit"; VLLM_MODEL_SIZE_GB=18
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser gemma4"
            VLLM_REASONING_ARGS="--reasoning-parser gemma4"
            VLLM_EXTRA_ARGS="$EAGER_ARGS"
            VLLM_DTYPE="float16"
            VLLM_IMAGE="vllm/vllm-openai:${NIGHTLY_PREFIX}"
            ;;
        9)
            VLLM_MODEL_ID="openai/gpt-oss-20b"; VLLM_GPU_COUNT=1; VLLM_MODEL_SIZE_GB=16
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser openai"
            ;;
        10)
            if [ "$TOTAL_VRAM" -lt 80 ]; then
                echo -e "${RED}✗ GPT-OSS 120B requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="openai/gpt-oss-120b"; VLLM_MODEL_SIZE_GB=80
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser openai"
            ;;
        11)
            # Qwen 3.6 27B NVFP4 (unsloth) — Blackwell FP4 tensor-core quant + MTP
            # speculative decoding. Benchmarked 2026-07-12 on DGX Spark (GB10, sm_121):
            # 22.4 / 78.1 / 133.6 tok/s at conc 1/4/8 = ~4-5x the FP16 27B baseline
            # (4.5 / 17.3 / 32.4), in ~14 GB vs ~54 GB. NVFP4 (compressed-tensors) needs
            # vLLM >=0.25.0 for the FlashInfer-Cutlass FP4 kernel on sm_120/sm_121, so this
            # entry PINS v0.25.0 rather than riding ${NIGHTLY_PREFIX} (which is older and
            # lacks the kernel). VLLM_ENABLE_MTP switches on the MTP draft (the compose
            # injects --speculative-config); speculative decoding is lossless. No eager
            # mode — CUDA graphs are part of the speedup.
            if [ "$TOTAL_VRAM" -lt 20 ]; then
                echo -e "${RED}✗ Qwen 3.6 27B NVFP4 requires ~20 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="unsloth/Qwen3.6-27B-NVFP4"; VLLM_MODEL_SIZE_GB=14
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_ENABLE_MTP="1"
            VLLM_IMAGE="vllm/vllm-openai:v0.25.0"
            ;;
        12)
            # Qwen 3.8 27B NVFP4 (unsloth) — successor to choice 11. Two things differ
            # from the 3.6 NVFP4 entry and both drive the config below:
            #
            # 1. ARCH: hybrid attention (linear attention on 48 of 64 layers, full on 16)
            #    plus a vision tower. That arch landed in vLLM main AFTER the v0.27.1
            #    stable cut (2026-08-11) — the model published 2026-08-14 — so this entry
            #    rides ${NIGHTLY_PREFIX} instead of pinning a release tag. Do NOT "fix"
            #    this to a stable pin until a release ships the arch; a stable image
            #    fails at load with an unrecognized model type.
            # 2. TRANSFORMERS: needs >=5.8.0. VLLM_EXTRA_PIP makes the compose upgrade it
            #    in-container before serving (no-op for every other entry, which leave it
            #    empty). Drop it once the nightly image ships that floor on its own.
            #
            # NVFP4 GEMM kernels are sm_120+ only (FlashInfer-Cutlass), so this gates on
            # compute capability as well as VRAM — on pre-Blackwell the weights load and
            # then fail in the kernel selector, which is a confusing way to find out.
            # MTP draft head is built into the checkpoint (compose injects
            # --speculative-config); speculative decoding is lossless. No eager mode —
            # CUDA graphs are part of the speedup. If a single 24 GB card OOMs during
            # graph capture, add --enforce-eager via EXTRA_VLLM_ARGS in .env, and
            # --kv-cache-dtype fp8 is the lever for pushing past the context set here.
            if [ "${COMPUTE_MAJOR:-0}" -lt 12 ] 2>/dev/null; then
                echo -e "${RED}✗ Qwen 3.8 27B NVFP4 needs a Blackwell GPU (compute 12.0+); this box reports ${COMPUTE_CAP:-unknown}.${NC}"
                echo -e "  ${YELLOW}Use choice 2 (Qwen 3.6 27B AWQ) on this hardware.${NC}"
                return 1
            fi
            if [ "$TOTAL_VRAM" -lt 20 ]; then
                echo -e "${RED}✗ Qwen 3.8 27B NVFP4 requires ~20 GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
                return 1
            fi
            VLLM_MODEL_ID="unsloth/Qwen3.8-27B-NVFP4"; VLLM_MODEL_SIZE_GB=16
            VLLM_TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
            VLLM_REASONING_ARGS="--reasoning-parser qwen3"
            VLLM_ENABLE_MTP="1"
            VLLM_EXTRA_PIP="transformers>=5.8.0"
            VLLM_IMAGE="vllm/vllm-openai:${NIGHTLY_PREFIX}"
            # KV cache is fp16 here, so context is sized to what's left after weights
            # rather than the model's native 262K.
            if [ "$TOTAL_VRAM" -ge 48 ]; then
                VLLM_MAX_CTX="262144"
            elif [ "$TOTAL_VRAM" -ge 32 ]; then
                VLLM_MAX_CTX="131072"
            else
                VLLM_MAX_CTX="65536"
            fi
            ;;
        13)
            read -p "  Enter HuggingFace model ID (owner/model): " VLLM_MODEL_ID
            # Validate format: owner/model-name (letters, digits, dots, hyphens, underscores, colons)
            if [[ ! "$VLLM_MODEL_ID" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._:-]+$ ]]; then
                echo -e "${RED}✗ Invalid model ID format: '${VLLM_MODEL_ID}'${NC}"
                echo "  Expected format: owner/model-name (e.g. cyankiwi/Qwen3.6-35B-A3B-AWQ-4bit)"
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

    # Minimum host driver for the image this entry resolved to (gpu_detect.sh helper)
    VLLM_MIN_DRIVER=$(min_driver_for_image "$VLLM_IMAGE" 2>/dev/null || true)

    return 0
}
