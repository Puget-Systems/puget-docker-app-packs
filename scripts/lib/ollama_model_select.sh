#!/bin/bash
# Puget Systems — Shared Ollama Model Selection
# Source this file; do not execute directly.
#
# Prerequisites: source gpu_detect.sh and call detect_gpus first.
#   Required globals: GPU_COUNT, TOTAL_VRAM, VRAM_GB
#   Required colors:  GREEN, BLUE, YELLOW, RED, NC
#
# Usage:
#   show_ollama_model_menu          # prints the numbered model list
#   select_ollama_model <choice>    # sets OLLAMA_* output vars, returns 0/1/2

show_ollama_model_menu() {
    if [ "$TOTAL_VRAM" -ge 24 ]; then
        echo "  1) Qwen 3.6 (35B MoE)    - Agentic coding, 256K ctx, thinking preservation (~24 GB) [New]"
    else
        echo -e "  1) Qwen 3.6 (35B MoE)    - ${RED}Requires ~24 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 18 ]; then
        echo "  2) Qwen 3.6 (27B Dense)  - Multimodal agentic, 262K ctx (~18 GB) [New]"
    else
        echo -e "  2) Qwen 3.6 (27B Dense)  - ${RED}Requires ~18 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 42 ]; then
        echo "  3) DeepSeek R1 (70B)     - Flagship Reasoning, Dual GPU (~42 GB)"
    else
        echo -e "  3) DeepSeek R1 (70B)     - ${RED}Requires ~42 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 63 ]; then
        echo "  4) Llama 4 Scout         - Multimodal (text+image), Dual GPU (~63 GB)"
    else
        echo -e "  4) Llama 4 Scout         - ${RED}Requires ~63 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 24 ]; then
        echo "  5) Nemotron 3 Nano (30B) - NVIDIA MoE Reasoning, Single GPU (~24 GB)"
    else
        echo -e "  5) Nemotron 3 Nano (30B) - ${RED}Requires ~24 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 96 ]; then
        echo "  6) Nemotron 3 Super      - NVIDIA Flagship MoE, Multi-GPU (~96 GB)"
    else
        echo -e "  6) Nemotron 3 Super      - ${RED}Requires ~96 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 20 ]; then
        echo "  7) Gemma 4 (31B)         - Google, Dense Instruct, Single GPU (~20 GB)"
    else
        echo -e "  7) Gemma 4 (31B)         - ${RED}Requires ~20 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    if [ "$TOTAL_VRAM" -ge 18 ]; then
        echo "  8) Qwen 3.8 (27B Dense)  - Hybrid attention, vision, 262K ctx (~17 GB) [New]"
    else
        echo -e "  8) Qwen 3.8 (27B Dense)  - ${RED}Requires ~18 GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    fi

    local fn_vram; fn_vram=$(_flash_next_ollama_vram_gb)
    if [ "$TOTAL_VRAM" -ge "$fn_vram" ] && [ "$(host_ram_gb)" -ge 48 ]; then
        echo "  9) Qwen 3.8 Flash-Next   - 125B MoE, 6B active, vision (~120 GB download; ~${fn_vram} GB VRAM + 34 GB RAM) [New]"
    elif [ "$TOTAL_VRAM" -lt "$fn_vram" ]; then
        echo -e "  9) Qwen 3.8 Flash-Next   - ${RED}Requires ~${fn_vram} GB VRAM (you have ${TOTAL_VRAM} GB)${NC}"
    else
        echo -e "  9) Qwen 3.8 Flash-Next   - ${RED}Requires 48 GB system RAM (you have $(host_ram_gb) GB)${NC}"
    fi

    echo "  10) Skip                 - I'll download models later"
    MENU_MAX=10
}

# _flash_next_ollama_vram_gb — VRAM gate (GiB) for Qwen 3.8 Flash-Next Q4_K_M (120 GB download).
#   Ollama keeps the model's ~34 GB n-gram embedding table in host RAM (CPU_Mapped), so the GPUs
#   hold far less than the download: measured 2026-11-04 at 85 GB on 4x RTX 5090 (TOTAL_VRAM 124)
#   and 93 GB on 8x RTX 5090 (more per-GPU overhead), both 100% GPU at 32K context. 90 admits a
#   single 96 GB card (reports 95). On unified memory (DGX Spark) the table shares the same pool,
#   so the whole download must fit: 124 turns away a 128 GB Spark (reports ~119) instead of OOMing.
_flash_next_ollama_vram_gb() {
    if [ "${IS_UNIFIED_MEMORY:-false}" = "true" ]; then echo 124; else echo 90; fi
}

# select_ollama_model <choice>
#   Sets: OLLAMA_MODEL_TAG, OLLAMA_MODEL_VRAM_GB
#   Returns: 0 = model selected, 1 = VRAM insufficient, 2 = skipped
select_ollama_model() {
    local choice="$1"

    OLLAMA_MODEL_TAG=""
    OLLAMA_MODEL_VRAM_GB=0

    case $choice in
        1) OLLAMA_MODEL_TAG="qwen3.6:35b";        OLLAMA_MODEL_VRAM_GB=24 ;;
        2) OLLAMA_MODEL_TAG="qwen3.6:27b";        OLLAMA_MODEL_VRAM_GB=18 ;;
        3) OLLAMA_MODEL_TAG="deepseek-r1:70b";    OLLAMA_MODEL_VRAM_GB=42 ;;
        4) OLLAMA_MODEL_TAG="llama4:scout";        OLLAMA_MODEL_VRAM_GB=63 ;;
        5) OLLAMA_MODEL_TAG="nemotron-3-nano:30b"; OLLAMA_MODEL_VRAM_GB=24 ;;
        6) OLLAMA_MODEL_TAG="nemotron-3-super";    OLLAMA_MODEL_VRAM_GB=96 ;;
        7) OLLAMA_MODEL_TAG="gemma4:31b";          OLLAMA_MODEL_VRAM_GB=20 ;;
        # Needs Ollama >= 0.34 (older servers answer the pull with 412); compose pins it.
        8) OLLAMA_MODEL_TAG="qwen3.8:27b";         OLLAMA_MODEL_VRAM_GB=18 ;;
        # Ollama added the arch in 0.33.1; compose pins 0.34.4. See _flash_next_ollama_vram_gb.
        9)
            OLLAMA_MODEL_TAG="qwen3.8-flash-next:125b-a6b-q4_K_M"
            OLLAMA_MODEL_VRAM_GB=$(_flash_next_ollama_vram_gb)
            if [ "$(host_ram_gb)" -lt 48 ]; then
                echo -e "${RED}✗ ${OLLAMA_MODEL_TAG} keeps a ~34 GB embedding table in system RAM; it needs 48 GB RAM (you have $(host_ram_gb) GB).${NC}"
                return 1
            fi ;;
        *) return 2 ;;
    esac

    # VRAM gate: warn and block if insufficient
    if [ "$TOTAL_VRAM" -lt "$OLLAMA_MODEL_VRAM_GB" ]; then
        echo -e "${RED}✗ ${OLLAMA_MODEL_TAG} requires ~${OLLAMA_MODEL_VRAM_GB} GB VRAM (you have ${TOTAL_VRAM} GB).${NC}"
        echo "  Select a smaller model or add more GPUs."
        return 1
    fi

    # Multi-GPU warning: Ollama uses pipeline parallelism (layer splitting)
    # which is significantly slower than tensor parallelism (vLLM).
    # PUGET_NONINTERACTIVE=1 (set by scripts/list_models.sh and the bench) accepts
    # the layer-split trade-off without prompting so enumeration doesn't block.
    if [ "$GPU_COUNT" -gt 1 ] && [ "$OLLAMA_MODEL_VRAM_GB" -gt "$VRAM_GB" ] && [ "${PUGET_NONINTERACTIVE:-0}" != "1" ]; then
        echo ""
        echo -e "${YELLOW}⚠ WARNING: ${OLLAMA_MODEL_TAG} (~${OLLAMA_MODEL_VRAM_GB} GB) exceeds single GPU capacity (${VRAM_GB} GB).${NC}"
        echo -e "  Ollama will split layers across GPUs, which is ${RED}significantly slower${NC}"
        echo -e "  than single-GPU inference. For multi-GPU workloads, the ${BLUE}Team LLM${NC}"
        echo -e "  pack (vLLM) provides tensor parallelism with much better performance."
        echo ""
        read -p "  Continue anyway? (y/N): " CONTINUE
        if [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
            return 2
        fi
    fi

    return 0
}

# wait_for_ollama [timeout_secs]
#   Polls `docker compose exec -T inference ollama list` until it succeeds.
#   Returns: 0 = ready, 1 = timed out
wait_for_ollama() {
    local timeout="${1:-120}"

    echo -n "Waiting for Ollama server to be ready"
    local i=0
    while [ "$i" -lt "$timeout" ]; do
        i=$((i + 1))
        if docker compose exec -T inference ollama list &>/dev/null; then
            echo ""
            echo -e "${GREEN}✓ Ollama server is ready.${NC}"
            return 0
        fi
        echo -n "."
        sleep 1
    done

    echo ""
    echo -e "${RED}✗ Ollama server did not become ready after ${timeout} seconds.${NC}"
    echo "  Check: docker compose logs inference"
    return 1
}

# _ollama_discovered_libraries — compute libraries Ollama found at its CURRENT start
#   (one per line, e.g. CUDA / cpu). Reads only the logs since the container last started, so
#   lines from an earlier, failed start don't count. Prints nothing if discovery hasn't logged yet.
_ollama_discovered_libraries() {
    local started
    started=$(docker inspect -f '{{.State.StartedAt}}' puget_ollama 2>/dev/null) || return 0
    docker logs --since "$started" puget_ollama 2>&1 \
        | grep 'msg="inference compute"' | grep -o 'library=[A-Za-z]*' | cut -d= -f2 | sort -u
}

# ensure_ollama_gpu — confirm Ollama is using the NVIDIA GPUs, not silently running on the CPU.
#   Ollama gives up on a GPU library after a 30 s discovery watchdog and falls back to CPU
#   without failing; a 120 GB model then "works" at 0.2 tok/s. If that happened, turn on
#   persistence mode, restart the engine once and check again; if it's still on CPU, say so
#   loudly. NVIDIA only (AMD/Intel run llama.cpp, not Ollama). Returns 0 = GPU, 1 = CPU only.
ensure_ollama_gpu() {
    [ "${GPU_VENDOR:-nvidia}" = "nvidia" ] || return 0
    local attempt libs i
    for attempt in 1 2; do
        libs=""
        for i in $(seq 1 90); do
            libs=$(_ollama_discovered_libraries)
            [ -n "$libs" ] && break
            sleep 1
        done
        if echo "$libs" | grep -qx "CUDA"; then
            echo -e "${GREEN}✓ Ollama is using the NVIDIA GPU(s).${NC}"
            return 0
        fi
        [ -z "$libs" ] && return 0   # older/newer Ollama without this log line: don't guess
        [ "$attempt" = 2 ] && break
        echo -e "${YELLOW}⚠ Ollama started without finding the GPU(s) — retrying after enabling persistence mode...${NC}"
        enable_nvidia_persistence || true
        docker compose restart inference >/dev/null 2>&1
        wait_for_ollama >/dev/null || break
    done
    echo ""
    echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}✗ Ollama is running on the CPU only — models will be extremely slow.${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
    echo "  Ollama could not initialise the NVIDIA GPU(s) in time and fell back to the CPU."
    echo -e "  Fix: ${BLUE}sudo nvidia-smi -pm 1 && docker compose restart inference${NC}"
    echo -e "  Check: ${BLUE}docker compose logs inference | grep 'inference compute'${NC} should list CUDA devices."
    echo ""
    return 1
}
