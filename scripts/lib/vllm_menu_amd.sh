#!/bin/bash
# Puget Systems — AMD (RDNA4 / R9700) team_llm menu — LLAMA.CPP engine.
#
# AMD uses llama.cpp (llama-server), NOT vLLM: vLLM's multi-GPU tensor-parallel hits an
# RCCL all-reduce deadlock on RDNA4 over PCIe (all available images ship the regressed
# nccl 2.27.7), capping it at pipeline-parallel ~11 tok/s. llama.cpp's HIP split
# (--split-mode row) runs BOTH GPUs per token with no RCCL — ~2x faster — same OpenAI API.
#
# Models mirror the Qwen3.6/3.5 lineup used by the NVIDIA/Intel menus, but as GGUF
# (already-quantized; small downloads). The team_llm AMD compose override runs:
#   llama-server -hf $MODEL_ID -ngl 99 --split-mode row -c $MAX_CONTEXT ...
# These functions are sourced by vllm_model_select.sh (the vendor dispatcher). Source only.

show_vllm_model_menu() {
    echo -e "${YELLOW}Available models (llama.cpp / GGUF, multi-GPU via HIP split):${NC}"
    echo ""
    # GGUF Q4_K_M ~= 0.6 GB/B params, Q8_0 ~= 1.06 GB/B. Sizes below are the GGUF footprint.
    if [ "$TOTAL_VRAM" -ge 22 ]; then
        echo "  1) Qwen 3.6 35B-A3B (Q4_K_M)  - MoE flagship, 3B active → fast (~21 GB) [Recommended]"
    else
        echo -e "  1) Qwen 3.6 35B-A3B (Q4_K_M)  - ${RED}Requires ~22 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    if [ "$TOTAL_VRAM" -ge 18 ]; then
        echo "  2) Qwen 3.6 27B (Q4_K_M)      - Dense, multimodal-agentic (~17 GB)"
    else
        echo -e "  2) Qwen 3.6 27B (Q4_K_M)      - ${RED}Requires ~18 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    if [ "$TOTAL_VRAM" -ge 22 ]; then
        echo "  3) Qwen 3.5 35B-A3B (Q4_K_M)  - MoE, 256K ctx (~21 GB)"
    else
        echo -e "  3) Qwen 3.5 35B-A3B (Q4_K_M)  - ${RED}Requires ~22 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    if [ "$TOTAL_VRAM" -ge 80 ]; then
        echo "  4) Qwen 3.5 122B-A10B (Q4_K_M)- Flagship MoE, 10B active (~73 GB, split GGUF)"
    else
        echo -e "  4) Qwen 3.5 122B-A10B (Q4_K_M)- ${RED}Requires ~80 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    if [ "$TOTAL_VRAM" -ge 22 ]; then
        echo "  5) DeepSeek-R1 32B (Q4_K_M)   - Reasoning, Qwen-distilled (~20 GB)"
    else
        echo -e "  5) DeepSeek-R1 32B (Q4_K_M)   - ${RED}Requires ~22 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    if [ "$TOTAL_VRAM" -ge 32 ]; then
        echo "  6) Qwen 3.6 27B (Q8_0)        - Dense, higher quality (~29 GB)"
    else
        echo -e "  6) Qwen 3.6 27B (Q8_0)        - ${RED}Requires ~32 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    echo "  7) Qwen 3.5 9B (Q4_K_M)       - Small & fast (~6 GB)"
    echo "  8) Custom GGUF (advanced)     - Enter any HuggingFace GGUF repo:quant"
    echo "  9) Skip / configure later"
    MENU_MAX=9
}

# recommend_llama_context <weights_gb>
#   Same idea as recommend_ollama_context (ollama_model_select.sh): rather than pin a flat
#   16K/32K, scale -c to the VRAM left after weights and lean on flash-attention + a q8 KV
#   cache (set in docker-compose.amd.yml) to ~halve KV memory. With q8 KV a Qwen3-class GQA
#   model costs ~0.12 GB / 1k tokens, so ~5000 tokens/GB of headroom (conservative, leaving
#   4 GB for compute/graph buffers). Cap at 131072 (Qwen3 native-with-rope ceiling), floor 8k.
#   A 64 GB box on a 17 GB Q4 27B → 131072 instead of 16384.
#   In: TOTAL_VRAM   Out: echoes the context length.
recommend_llama_context() {
    local weight="${1:-1}"
    [ "${weight:-0}" -lt 1 ] 2>/dev/null && weight=1
    local headroom=$(( ${TOTAL_VRAM:-0} - weight - 4 ))   # reserve ~4 GB for compute buffers
    [ "$headroom" -lt 1 ] && headroom=1

    local ctx=$(( headroom * 5000 ))        # ~5000 tokens / GB with q8 KV cache
    [ "$ctx" -gt 131072 ] && ctx=131072     # Qwen3 native-with-rope ceiling
    [ "$ctx" -lt 8192 ]   && ctx=8192       # floor so the model is still usable
    ctx=$(( (ctx / 1024) * 1024 ))          # round down to a clean 1K boundary
    echo "$ctx"
}

# select_vllm_model <choice>
#   Sets VLLM_MODEL_ID (HF GGUF repo:quant), VLLM_IMAGE (llama.cpp), VLLM_GPU_COUNT,
#   VLLM_MAX_CTX. Other VLLM_* vars stay empty (unused by llama.cpp). Returns 0/1/2.
select_vllm_model() {
    local choice="$1"
    VLLM_MODEL_ID=""; VLLM_MODEL_SIZE_GB=0
    VLLM_GPU_COUNT=$GPU_COUNT
    VLLM_EXTRA_ARGS=""; VLLM_DTYPE=""; VLLM_REASONING_ARGS=""; VLLM_THINKING_ARGS=""
    VLLM_TOOL_CALL_ARGS=""; VLLM_GPU_MEM_UTIL=""
    VLLM_IMAGE="${VLLM_IMAGE_AMD:-ghcr.io/ggml-org/llama.cpp:server-rocm}"
    VLLM_MAX_CTX="32768"

    case $choice in
        1)
            [ "$TOTAL_VRAM" -lt 22 ] && { echo -e "${RED}✗ Qwen 3.6 35B-A3B Q4 needs ~22 GB (you have ${TOTAL_VRAM} GB).${NC}"; return 1; }
            VLLM_MODEL_ID="unsloth/Qwen3.6-35B-A3B-GGUF:Q4_K_M"; VLLM_MODEL_SIZE_GB=21 ;;
        2)
            [ "$TOTAL_VRAM" -lt 18 ] && { echo -e "${RED}✗ Qwen 3.6 27B Q4 needs ~18 GB.${NC}"; return 1; }
            VLLM_MODEL_ID="unsloth/Qwen3.6-27B-GGUF:Q4_K_M"; VLLM_MODEL_SIZE_GB=17 ;;
        3)
            [ "$TOTAL_VRAM" -lt 22 ] && { echo -e "${RED}✗ Qwen 3.5 35B-A3B Q4 needs ~22 GB.${NC}"; return 1; }
            VLLM_MODEL_ID="unsloth/Qwen3.5-35B-A3B-GGUF:Q4_K_M"; VLLM_MODEL_SIZE_GB=21 ;;
        4)
            [ "$TOTAL_VRAM" -lt 80 ] && { echo -e "${RED}✗ Qwen 3.5 122B Q4 needs ~80 GB (you have ${TOTAL_VRAM} GB).${NC}"; return 1; }
            VLLM_MODEL_ID="unsloth/Qwen3.5-122B-A10B-GGUF:Q4_K_M"; VLLM_MODEL_SIZE_GB=73 ;;
        5)
            [ "$TOTAL_VRAM" -lt 22 ] && { echo -e "${RED}✗ DeepSeek-R1 32B Q4 needs ~22 GB.${NC}"; return 1; }
            VLLM_MODEL_ID="unsloth/DeepSeek-R1-Distill-Qwen-32B-GGUF:Q4_K_M"; VLLM_MODEL_SIZE_GB=20 ;;
        6)
            [ "$TOTAL_VRAM" -lt 32 ] && { echo -e "${RED}✗ Qwen 3.6 27B Q8 needs ~32 GB.${NC}"; return 1; }
            VLLM_MODEL_ID="unsloth/Qwen3.6-27B-GGUF:Q8_0"; VLLM_MODEL_SIZE_GB=29 ;;
        7)
            VLLM_MODEL_ID="unsloth/Qwen3.5-9B-GGUF:Q4_K_M"; VLLM_MODEL_SIZE_GB=6 ;;
        8)
            echo -e "${YELLOW}Custom GGUF — format owner/repo-GGUF:QUANT${NC}"
            echo "  e.g. unsloth/Qwen3.6-27B-GGUF:Q4_K_M"
            read -p "  Enter GGUF repo:quant (or Enter to skip): " CUSTOM_GGUF
            [ -z "$CUSTOM_GGUF" ] && return 2
            VLLM_MODEL_ID="$CUSTOM_GGUF"; VLLM_MODEL_SIZE_GB=0; return 2 ;;
        *)
            return 2 ;;
    esac

    # Size -c to the VRAM left after weights (flash-attn + q8 KV cache enabled in compose).
    VLLM_MAX_CTX="$(recommend_llama_context "$VLLM_MODEL_SIZE_GB")"
    return 0
}
