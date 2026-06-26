#!/bin/bash
# Puget Systems — AMD (RDNA4 / R9700) Personal LLM menu — LLAMA.CPP engine.
#
# Personal LLM runs llama.cpp (llama-server) on AMD instead of Ollama: llama.cpp's HIP
# split (--split-mode row) runs BOTH GPUs per token with no RCCL (~2x Ollama's layer-split
# path), and it's a great fit for a single-user box. Team LLM stays on vLLM (FP8) — its
# dynamic concurrency matters more there than raw speed; llama.cpp's static slots and
# tool-loop fragility are acceptable for Personal.
#
# Models are GGUF (already-quantized, small downloads). The personal_llm AMD compose
# override runs:  llama-server -hf $MODEL_ID -ngl 99 --split-mode row -fa on
#                              --parallel $LLAMA_PARALLEL -c $MAX_CONTEXT ...
# Source only; sets LLAMA_* output vars.

show_llama_model_menu() {
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
        echo "  3) Qwen 3.5 35B-A3B (Q4_K_M)  - MoE, long context (~21 GB)"
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
#   Scale -c to the VRAM left after weights, rather than a flat default. KV cache stays at
#   fp16 (a q8 KV cache degrades long-context attention and makes tool-use loop); flash
#   attention shrinks the compute buffer. fp16 KV for a Qwen3-class GQA model is ~0.25 GB /
#   1k tokens → ~3000 tokens/GB of headroom (conservative, reserving 4 GB for buffers).
#   This sizes the TOTAL pool; with --parallel N each slot gets (-c / N). Cap 131072, floor 8k.
#   In: TOTAL_VRAM   Out: echoes the context length.
recommend_llama_context() {
    local weight="${1:-1}"
    [ "${weight:-0}" -lt 1 ] 2>/dev/null && weight=1
    local headroom=$(( ${TOTAL_VRAM:-0} - weight - 4 ))
    [ "$headroom" -lt 1 ] && headroom=1
    local ctx=$(( headroom * 3000 ))
    [ "$ctx" -gt 131072 ] && ctx=131072
    [ "$ctx" -lt 8192 ]   && ctx=8192
    ctx=$(( (ctx / 1024) * 1024 ))
    echo "$ctx"
}

# select_llama_model <choice>
#   Sets LLAMA_MODEL_ID (HF GGUF repo:quant), LLAMA_IMAGE, LLAMA_GPU_COUNT, LLAMA_MAX_CTX,
#   LLAMA_MODEL_SIZE_GB. Returns 0 = selected, 1 = insufficient VRAM, 2 = skip/custom.
select_llama_model() {
    local choice="$1"
    LLAMA_MODEL_ID=""; LLAMA_MODEL_SIZE_GB=0
    LLAMA_GPU_COUNT=$GPU_COUNT
    LLAMA_IMAGE="${LLAMA_IMAGE_AMD:-ghcr.io/ggml-org/llama.cpp:server-rocm}"
    LLAMA_MAX_CTX="32768"

    case $choice in
        1)
            [ "$TOTAL_VRAM" -lt 22 ] && { echo -e "${RED}✗ Qwen 3.6 35B-A3B Q4 needs ~22 GB (you have ${TOTAL_VRAM} GB).${NC}"; return 1; }
            LLAMA_MODEL_ID="unsloth/Qwen3.6-35B-A3B-GGUF:Q4_K_M"; LLAMA_MODEL_SIZE_GB=21 ;;
        2)
            [ "$TOTAL_VRAM" -lt 18 ] && { echo -e "${RED}✗ Qwen 3.6 27B Q4 needs ~18 GB.${NC}"; return 1; }
            LLAMA_MODEL_ID="unsloth/Qwen3.6-27B-GGUF:Q4_K_M"; LLAMA_MODEL_SIZE_GB=17 ;;
        3)
            [ "$TOTAL_VRAM" -lt 22 ] && { echo -e "${RED}✗ Qwen 3.5 35B-A3B Q4 needs ~22 GB.${NC}"; return 1; }
            LLAMA_MODEL_ID="unsloth/Qwen3.5-35B-A3B-GGUF:Q4_K_M"; LLAMA_MODEL_SIZE_GB=21 ;;
        4)
            [ "$TOTAL_VRAM" -lt 80 ] && { echo -e "${RED}✗ Qwen 3.5 122B Q4 needs ~80 GB (you have ${TOTAL_VRAM} GB).${NC}"; return 1; }
            LLAMA_MODEL_ID="unsloth/Qwen3.5-122B-A10B-GGUF:Q4_K_M"; LLAMA_MODEL_SIZE_GB=73 ;;
        5)
            [ "$TOTAL_VRAM" -lt 22 ] && { echo -e "${RED}✗ DeepSeek-R1 32B Q4 needs ~22 GB.${NC}"; return 1; }
            LLAMA_MODEL_ID="unsloth/DeepSeek-R1-Distill-Qwen-32B-GGUF:Q4_K_M"; LLAMA_MODEL_SIZE_GB=20 ;;
        6)
            [ "$TOTAL_VRAM" -lt 32 ] && { echo -e "${RED}✗ Qwen 3.6 27B Q8 needs ~32 GB.${NC}"; return 1; }
            LLAMA_MODEL_ID="unsloth/Qwen3.6-27B-GGUF:Q8_0"; LLAMA_MODEL_SIZE_GB=29 ;;
        7)
            LLAMA_MODEL_ID="unsloth/Qwen3.5-9B-GGUF:Q4_K_M"; LLAMA_MODEL_SIZE_GB=6 ;;
        8)
            echo -e "${YELLOW}Custom GGUF — format owner/repo-GGUF:QUANT${NC}"
            echo "  e.g. unsloth/Qwen3.6-27B-GGUF:Q4_K_M"
            read -p "  Enter GGUF repo:quant (or Enter to skip): " CUSTOM_GGUF
            [ -z "$CUSTOM_GGUF" ] && return 2
            LLAMA_MODEL_ID="$CUSTOM_GGUF"; LLAMA_MODEL_SIZE_GB=0; return 2 ;;
        *)
            return 2 ;;
    esac

    # Size -c to the VRAM left after weights (fp16 KV; flash-attn enabled in compose).
    LLAMA_MAX_CTX="$(recommend_llama_context "$LLAMA_MODEL_SIZE_GB")"
    return 0
}
