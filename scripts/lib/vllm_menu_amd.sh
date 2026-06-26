#!/bin/bash
# Puget Systems — AMD (RDNA4 / R9700) team_llm menu — LLAMA.CPP engine.
#
# AMD uses llama.cpp (llama-server), NOT vLLM: vLLM's multi-GPU tensor-parallel hits an
# RCCL all-reduce deadlock on RDNA4 over PCIe (all available images ship the regressed
# nccl 2.27.7), capping it at pipeline-parallel ~11 tok/s. llama.cpp's HIP split
# (--split-mode row) runs BOTH GPUs per token with no RCCL — ~2x faster (measured ~22.7
# tok/s on Qwen2.5-32B Q4 across 2x R9700) — and exposes the same OpenAI API.
#
# Models are GGUF (already-quantized; small downloads). The team_llm AMD compose override
# (docker-compose.amd.yml) runs: llama-server -hf $MODEL_ID -ngl 99 --split-mode row ...
# These functions are sourced by vllm_model_select.sh (the vendor dispatcher); the entry
# point names are kept for that dispatch. Source this file; do not execute directly.

show_vllm_model_menu() {
    echo -e "${YELLOW}Available models (llama.cpp / GGUF, multi-GPU via HIP split):${NC}"
    echo ""
    # GGUF Q4_K_M ~= 0.6 GB/B params; Q8_0 ~= 1.0 GB/B. Multi-GPU splits across all GPUs.
    if [ "$TOTAL_VRAM" -ge 22 ]; then
        echo "  1) Qwen2.5 32B (Q4_K_M)       - Flagship dense, ~22 tok/s on 2 GPUs (~20 GB) [Recommended]"
    else
        echo -e "  1) Qwen2.5 32B (Q4_K_M)       - ${RED}Requires ~22 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    if [ "$TOTAL_VRAM" -ge 22 ]; then
        echo "  2) Qwen2.5-Coder 32B (Q4_K_M) - Coding specialist (~20 GB)"
    else
        echo -e "  2) Qwen2.5-Coder 32B (Q4_K_M) - ${RED}Requires ~22 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    if [ "$TOTAL_VRAM" -ge 22 ]; then
        echo "  3) DeepSeek-R1 32B (Q4_K_M)   - Reasoning, Qwen-distilled (~20 GB)"
    else
        echo -e "  3) DeepSeek-R1 32B (Q4_K_M)   - ${RED}Requires ~22 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    if [ "$TOTAL_VRAM" -ge 20 ]; then
        echo "  4) Qwen3 30B-A3B (Q4_K_M)     - MoE, 3B active → very fast (~18 GB)"
    else
        echo -e "  4) Qwen3 30B-A3B (Q4_K_M)     - ${RED}Requires ~20 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    if [ "$TOTAL_VRAM" -ge 36 ]; then
        echo "  5) Qwen2.5 32B (Q8_0)         - Higher quality, needs 2 GPUs (~34 GB)"
    else
        echo -e "  5) Qwen2.5 32B (Q8_0)         - ${RED}Requires ~36 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    echo "  6) Qwen2.5 14B (Q4_K_M)       - Mid-size, lower VRAM (~9 GB)"
    echo "  7) Qwen2.5 7B (Q4_K_M)        - Small & fast (~5 GB)"
    echo "  8) Custom GGUF (advanced)     - Enter any HuggingFace GGUF repo:quant"
    echo "  9) Skip / configure later"
    MENU_MAX=9
}

# select_vllm_model <choice>
#   Sets VLLM_MODEL_ID (HF GGUF repo:quant), VLLM_IMAGE (llama.cpp), VLLM_GPU_COUNT,
#   VLLM_MAX_CTX. Other VLLM_* vars stay empty (unused by llama.cpp). Returns 0 ok, 1 gated,
#   2 skip/custom-handled.
select_vllm_model() {
    local choice="$1"
    VLLM_MODEL_ID=""; VLLM_MODEL_SIZE_GB=0
    VLLM_GPU_COUNT=$GPU_COUNT
    VLLM_EXTRA_ARGS=""; VLLM_DTYPE=""; VLLM_REASONING_ARGS=""; VLLM_THINKING_ARGS=""
    VLLM_TOOL_CALL_ARGS=""; VLLM_GPU_MEM_UTIL=""
    # llama.cpp on RDNA4 — official ggml-org ROCm image (has gfx1201 kernels).
    VLLM_IMAGE="${VLLM_IMAGE_AMD:-ghcr.io/ggml-org/llama.cpp:server-rocm}"
    VLLM_MAX_CTX="16384"

    case $choice in
        1)
            [ "$TOTAL_VRAM" -lt 22 ] && { echo -e "${RED}✗ Qwen2.5 32B Q4 needs ~22 GB (you have ${TOTAL_VRAM} GB).${NC}"; return 1; }
            VLLM_MODEL_ID="bartowski/Qwen2.5-32B-Instruct-GGUF:Q4_K_M"; VLLM_MODEL_SIZE_GB=20 ;;
        2)
            [ "$TOTAL_VRAM" -lt 22 ] && { echo -e "${RED}✗ Qwen2.5-Coder 32B Q4 needs ~22 GB.${NC}"; return 1; }
            VLLM_MODEL_ID="bartowski/Qwen2.5-Coder-32B-Instruct-GGUF:Q4_K_M"; VLLM_MODEL_SIZE_GB=20 ;;
        3)
            [ "$TOTAL_VRAM" -lt 22 ] && { echo -e "${RED}✗ DeepSeek-R1 32B Q4 needs ~22 GB.${NC}"; return 1; }
            VLLM_MODEL_ID="bartowski/DeepSeek-R1-Distill-Qwen-32B-GGUF:Q4_K_M"; VLLM_MODEL_SIZE_GB=20
            VLLM_MAX_CTX="32768" ;;
        4)
            [ "$TOTAL_VRAM" -lt 20 ] && { echo -e "${RED}✗ Qwen3 30B-A3B Q4 needs ~20 GB.${NC}"; return 1; }
            VLLM_MODEL_ID="unsloth/Qwen3-30B-A3B-GGUF:Q4_K_M"; VLLM_MODEL_SIZE_GB=18
            VLLM_MAX_CTX="32768" ;;
        5)
            [ "$TOTAL_VRAM" -lt 36 ] && { echo -e "${RED}✗ Qwen2.5 32B Q8 needs ~36 GB (2 GPUs).${NC}"; return 1; }
            VLLM_MODEL_ID="bartowski/Qwen2.5-32B-Instruct-GGUF:Q8_0"; VLLM_MODEL_SIZE_GB=34 ;;
        6)
            VLLM_MODEL_ID="bartowski/Qwen2.5-14B-Instruct-GGUF:Q4_K_M"; VLLM_MODEL_SIZE_GB=9 ;;
        7)
            VLLM_MODEL_ID="bartowski/Qwen2.5-7B-Instruct-GGUF:Q4_K_M"; VLLM_MODEL_SIZE_GB=5 ;;
        8)
            echo -e "${YELLOW}Custom GGUF — format owner/repo-GGUF:QUANT${NC}"
            echo "  e.g. bartowski/Qwen2.5-32B-Instruct-GGUF:Q4_K_M"
            read -p "  Enter GGUF repo:quant (or Enter to skip): " CUSTOM_GGUF
            [ -z "$CUSTOM_GGUF" ] && return 2
            VLLM_MODEL_ID="$CUSTOM_GGUF"; VLLM_MODEL_SIZE_GB=0; return 2 ;;
        *)
            return 2 ;;
    esac
    return 0
}
