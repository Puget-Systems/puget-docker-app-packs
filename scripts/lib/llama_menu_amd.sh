#!/bin/bash
# Puget Systems — AMD (RDNA4 / R9700) LLM menu — LLAMA.CPP engine (Personal AND Team).
#
# llama.cpp (llama-server) is the default AMD engine for BOTH packs. Multi-GPU work goes
# over direct HIP transfers (no RCCL, which deadlocks/fails on RDNA4), and --split-mode
# LAYER is the default: benchmarked 2026-07-09 on dual R9700 it matches row-split at
# concurrency 1 (23.4 tok/s, Qwen3.6-27B Q4_K_M), beats it at concurrency 4 (55.7 tok/s),
# and is crash-safe under concurrent decode — vs vLLM FP16 PP=2 at 10.9 tok/s on the same
# model. Team's vLLM FP8 path survives as an opt-in override (TEAM_AMD_ENGINE=vllm).
#
# Models are GGUF (already-quantized, small downloads). The AMD compose overrides run:
#   llama-server -hf $MODEL_ID -ngl 99 --split-mode $LLAMA_SPLIT_MODE -fa on
#                --parallel $LLAMA_PARALLEL -c $MAX_CONTEXT ...
#
# CONCURRENCY MODEL: unlike vLLM (PagedAttention auto-scales many requests over one shared
# KV pool), llama.cpp STATICALLY pre-segments: -c is a fixed pool split EVENLY across
# --parallel N slots, so per-request context = MAX_CONTEXT / N and more slots = less context
# each. Default is 2 slots (one active chat + one background task) for both packs — enough
# for a workstation without gutting context; raise LLAMA_PARALLEL in .env to trade context
# for concurrency.
# Pack profile knobs (set before calling select_llama_model):
#   LLAMA_DEFAULT_PARALLEL — slot count (default 2 for both packs).
#   LLAMA_MIN_CTX_PER_SLOT — per-request context floor (Personal 8192 default; Team 16384).
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
    if [ "$TOTAL_VRAM" -ge 18 ]; then
        echo "  8) Gemma 3 27B (Q4_K_M)       - Google, multimodal (~17 GB)"
    else
        echo -e "  8) Gemma 3 27B (Q4_K_M)       - ${RED}Requires ~18 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    if [ "$TOTAL_VRAM" -ge 46 ]; then
        echo "  9) DeepSeek-R1 70B (Q4_K_M)   - Reasoning, Llama-distilled (~43 GB)"
    else
        echo -e "  9) DeepSeek-R1 70B (Q4_K_M)   - ${RED}Requires ~46 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    if [ "$TOTAL_VRAM" -ge 18 ]; then
        echo "  10) Qwen 3.8 27B (Q4_K_M)     - Dense, hybrid-attention, vision (~17 GB) [New]"
    else
        echo -e "  10) Qwen 3.8 27B (Q4_K_M)     - ${RED}Requires ~18 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    if [ "$TOTAL_VRAM" -ge 32 ]; then
        echo "  11) Qwen 3.8 27B (Q8_0)       - Dense, higher quality (~30 GB)"
    else
        echo -e "  11) Qwen 3.8 27B (Q8_0)       - ${RED}Requires ~32 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi
    echo "  12) Custom GGUF (advanced)    - Enter any HuggingFace GGUF repo:quant"
    echo "  13) Skip / configure later"
    MENU_MAX=13
}

# recommend_llama_context <weights_gb> [avail_vram_gb] [n_slots] [min_ctx_per_slot]
#   Scale -c to the VRAM left after weights. KV stays fp16 (q8 KV degrades long-context
#   attention → tool-loops); flash attention shrinks the compute buffer. fp16 KV for a
#   Qwen3-class GQA model is ~0.25 GB / 1k tokens → ~3000 tokens/GB of headroom (reserving
#   4 GB for buffers). avail_vram defaults to TOTAL_VRAM (layer = both GPUs); pass a
#   single GPU's VRAM for --split-mode none. llama.cpp divides -c evenly across --parallel
#   N slots (per-request ctx = -c / N), so the result is per-slot ctx × N: total capped at
#   131072, per-slot floored at min_ctx_per_slot (default 8192) and rounded down to a
#   1024-token boundary.
recommend_llama_context() {
    local weight="${1:-1}"
    [ "${weight:-0}" -lt 1 ] 2>/dev/null && weight=1
    local avail="${2:-${TOTAL_VRAM:-0}}"
    local slots="${3:-1}"
    [ "${slots:-0}" -lt 1 ] 2>/dev/null && slots=1
    local min_slot="${4:-8192}"
    local headroom=$(( avail - weight - 4 ))
    [ "$headroom" -lt 1 ] && headroom=1
    local ctx=$(( headroom * 3000 ))
    [ "$ctx" -gt 131072 ] && ctx=131072
    local per_slot=$(( ctx / slots ))
    [ "$per_slot" -lt "$min_slot" ] && per_slot="$min_slot"
    per_slot=$(( (per_slot / 1024) * 1024 ))
    [ "$per_slot" -lt 4096 ] && per_slot=4096
    echo $(( per_slot * slots ))
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
            [ "$TOTAL_VRAM" -lt 18 ] && { echo -e "${RED}✗ Gemma 3 27B Q4 needs ~18 GB.${NC}"; return 1; }
            LLAMA_MODEL_ID="unsloth/gemma-3-27b-it-GGUF:Q4_K_M"; LLAMA_MODEL_SIZE_GB=17 ;;
        9)
            [ "$TOTAL_VRAM" -lt 46 ] && { echo -e "${RED}✗ DeepSeek-R1 70B Q4 needs ~46 GB (you have ${TOTAL_VRAM} GB).${NC}"; return 1; }
            LLAMA_MODEL_ID="unsloth/DeepSeek-R1-Distill-Llama-70B-GGUF:Q4_K_M"; LLAMA_MODEL_SIZE_GB=43 ;;
        10)
            # Qwen3.8 is hybrid-attention (48/64 linear layers) — needs a llama-server
            # image from 2026-08-14 or later; `docker compose pull` if the rolling
            # server-rocm tag was cached before then.
            [ "$TOTAL_VRAM" -lt 18 ] && { echo -e "${RED}✗ Qwen 3.8 27B Q4 needs ~18 GB.${NC}"; return 1; }
            LLAMA_MODEL_ID="unsloth/Qwen3.8-27B-GGUF:Q4_K_M"; LLAMA_MODEL_SIZE_GB=17 ;;
        11)
            [ "$TOTAL_VRAM" -lt 32 ] && { echo -e "${RED}✗ Qwen 3.8 27B Q8 needs ~32 GB.${NC}"; return 1; }
            LLAMA_MODEL_ID="unsloth/Qwen3.8-27B-GGUF:Q8_0"; LLAMA_MODEL_SIZE_GB=30 ;;
        12)
            echo -e "${YELLOW}Custom GGUF — format owner/repo-GGUF:QUANT${NC}"
            echo "  e.g. unsloth/Qwen3.6-27B-GGUF:Q4_K_M"
            read -p "  Enter GGUF repo:quant (or Enter to skip): " CUSTOM_GGUF
            [ -z "$CUSTOM_GGUF" ] && return 2
            LLAMA_MODEL_ID="$CUSTOM_GGUF"; LLAMA_MODEL_SIZE_GB=0; return 2 ;;
        *)
            return 2 ;;
    esac

    # GPU split (benchmarked 2026-07-09, dual R9700, Qwen3.6-27B Q4_K_M): LAYER split
    # matches row-split at concurrency 1 (23.4 tok/s), beats it at concurrency 4
    # (55.7 tok/s aggregate), and is crash-safe under concurrent decode. ROW split aborts
    # on Qwen3.6-family models under concurrent decode (GGML_ASSERT(!(split && ne02 <
    # ne12)) — its matmul path lacks those broadcast shapes) and segfaulted under
    # concurrency on non-P2P platforms, so it is no longer a default. Power users can set
    # LLAMA_SPLIT_MODE=row in .env for single-stream use — verify per model architecture
    # first. Single GPU → "none" (nothing to split).
    if [ "${GPU_COUNT:-1}" -le 1 ]; then
        LLAMA_SPLIT_MODE="none"
    else
        LLAMA_SPLIT_MODE="layer"
    fi

    # Concurrency slots. llama.cpp does NOT auto-scale like vLLM: -c is a fixed KV pool
    # split EVENLY across --parallel N slots (per-request ctx = -c / N) and traffic is
    # statically pre-segmented, so more slots = proportionally less context per request.
    # Default 2 (one active chat + one background task, e.g. a summarizer) — enough for a
    # workstation without gutting context. On tight-VRAM boxes we shed to 1 slot so the
    # single request keeps a usable window.
    LLAMA_PARALLEL="${LLAMA_DEFAULT_PARALLEL:-2}"
    local min_slot="${LLAMA_MIN_CTX_PER_SLOT:-8192}"
    local headroom_ctx=$(( (TOTAL_VRAM - LLAMA_MODEL_SIZE_GB - 4) * 3000 ))
    while [ "$LLAMA_PARALLEL" -gt 1 ] && [ $(( headroom_ctx / LLAMA_PARALLEL )) -lt "$min_slot" ]; do
        LLAMA_PARALLEL=$(( LLAMA_PARALLEL - 1 ))
    done
    LLAMA_MAX_CTX="$(recommend_llama_context "$LLAMA_MODEL_SIZE_GB" "$TOTAL_VRAM" "$LLAMA_PARALLEL" "$min_slot")"
    return 0
}
