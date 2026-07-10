#!/bin/bash
# Puget Systems — machine-readable model manifest.
#
# Enumerates every model the App Pack menus would offer ON THIS HARDWARE
# (VRAM-gated by the same select_* functions the installer uses — the menus
# stay the single source of truth) and prints one TSV row per model. The
# benchmark suite consumes this instead of screen-scraping menu functions.
#
# Output format (fields are TAB-separated; empty fields allowed):
#   line 1:  #PUGET_MODEL_MANIFEST <contract_version>
#   line 2:  #hw <vendor> <gpu_count> <total_vram_gb> <driver_version>
#   rows:    pack  engine  choice  model_id  size_gb  min_driver  image  gpu_count  dtype  max_ctx
#
# Contract v1: consumers must tolerate ADDED trailing fields; field meaning /
# order of the first 10 never changes within v1. Bump the version if it must.
#
# Usage: scripts/list_models.sh [--pack team_llm|personal_llm|all]

set -euo pipefail

CONTRACT_VERSION=1
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"

# Menu libs expect these color vars; output here must stay clean, so blank them.
GREEN="" BLUE="" YELLOW="" RED="" NC=""
export PUGET_NONINTERACTIVE=1

PACK_FILTER="all"
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --pack) PACK_FILTER="$2"; shift ;;
        *) echo "Unknown option: $1 (usage: list_models.sh [--pack team_llm|personal_llm|all])" >&2; exit 1 ;;
    esac
    shift
done

# shellcheck source=lib/gpu_detect.sh
source "$LIB_DIR/gpu_detect.sh"
detect_gpus || { echo "No supported GPU detected" >&2; exit 1; }

printf '#PUGET_MODEL_MANIFEST\t%s\n' "$CONTRACT_VERSION"
printf '#hw\t%s\t%s\t%s\t%s\n' "$GPU_VENDOR" "$GPU_COUNT" "$TOTAL_VRAM" "${DRIVER_VERSION:-unknown}"

emit_row() { # pack engine choice model_id size_gb min_driver image gpu_count dtype max_ctx
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}

# ── team_llm (vLLM on NVIDIA/Intel; llama.cpp default + vLLM opt-in on AMD) ─
if [ "$PACK_FILTER" = "all" ] || [ "$PACK_FILTER" = "team_llm" ]; then
    # AMD default engine is llama.cpp (TEAM_AMD_ENGINE=llama). Emit its rows first;
    # the vLLM rows below stay too (opt-in engine) — contract v1 consumers key on
    # the engine column, and extra rows are tolerated.
    if [ "$GPU_VENDOR" = "amd" ] && [ -f "$LIB_DIR/llama_menu_amd.sh" ]; then
        # shellcheck source=lib/llama_menu_amd.sh
        source "$LIB_DIR/llama_menu_amd.sh"
        LLAMA_MIN_CTX_PER_SLOT=16384   # team profile (matches install.sh/init.sh)
        show_llama_model_menu >/dev/null 2>&1
        _max="${MENU_MAX:-11}"
        for _c in $(seq 1 "$_max"); do
            _row=$(
                if select_llama_model "$_c" >/dev/null 2>&1 </dev/null; then
                    emit_row "team_llm" "llamacpp" "$_c" "$LLAMA_MODEL_ID" \
                        "${LLAMA_MODEL_SIZE_GB:-0}" "" "$LLAMA_IMAGE" \
                        "${LLAMA_GPU_COUNT:-1}" "" "${LLAMA_MAX_CTX:-}"
                fi
            ) || true
            [ -n "$_row" ] && echo "$_row"
        done
        unset LLAMA_MIN_CTX_PER_SLOT
    fi
    # shellcheck source=lib/vllm_model_select.sh
    source "$LIB_DIR/vllm_model_select.sh"
    show_vllm_model_menu >/dev/null 2>&1   # loads the vendor impl + sets MENU_MAX
    _max="${MENU_MAX:-12}"
    for _c in $(seq 1 "$_max"); do
        # Subshell so one entry's vars never leak into the next; stdin from
        # /dev/null so Custom entries (read -p) fall through to "skipped".
        _row=$(
            if select_vllm_model "$_c" >/dev/null 2>&1 </dev/null; then
                emit_row "team_llm" "vllm" "$_c" "$VLLM_MODEL_ID" "${VLLM_MODEL_SIZE_GB:-0}" \
                    "${VLLM_MIN_DRIVER:-}" "$VLLM_IMAGE" "${VLLM_GPU_COUNT:-1}" \
                    "${VLLM_DTYPE:-auto}" "${VLLM_MAX_CTX:-}"
            fi
        ) || true
        [ -n "$_row" ] && echo "$_row"
    done
fi

# ── personal_llm (engine differs by vendor: AMD = llama.cpp, else Ollama) ───
if [ "$PACK_FILTER" = "all" ] || [ "$PACK_FILTER" = "personal_llm" ]; then
    if [ "$GPU_VENDOR" = "amd" ] && [ -f "$LIB_DIR/llama_menu_amd.sh" ]; then
        # shellcheck source=lib/llama_menu_amd.sh
        source "$LIB_DIR/llama_menu_amd.sh"
        show_llama_model_menu >/dev/null 2>&1
        _max="${MENU_MAX:-11}"
        for _c in $(seq 1 "$_max"); do
            _row=$(
                if select_llama_model "$_c" >/dev/null 2>&1 </dev/null; then
                    emit_row "personal_llm" "llamacpp" "$_c" "$LLAMA_MODEL_ID" \
                        "${LLAMA_MODEL_SIZE_GB:-0}" "" "$LLAMA_IMAGE" \
                        "${LLAMA_GPU_COUNT:-1}" "" "${LLAMA_MAX_CTX:-}"
                fi
            ) || true
            [ -n "$_row" ] && echo "$_row"
        done
    else
        # shellcheck source=lib/ollama_model_select.sh
        source "$LIB_DIR/ollama_model_select.sh"
        show_ollama_model_menu >/dev/null 2>&1
        _max="${MENU_MAX:-8}"
        for _c in $(seq 1 "$_max"); do
            _row=$(
                if select_ollama_model "$_c" >/dev/null 2>&1 </dev/null; then
                    emit_row "personal_llm" "ollama" "$_c" "$OLLAMA_MODEL_TAG" \
                        "${OLLAMA_MODEL_VRAM_GB:-0}" "" "" "1" "" ""
                fi
            ) || true
            [ -n "$_row" ] && echo "$_row"
        done
    fi
fi
