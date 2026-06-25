#!/bin/bash
# Validate every model the menus reference WITHOUT running it (most are too big to run
# in CI). It catches the failure modes we've actually hit: a repo deleted/renamed (401),
# gated so general users can't pull it (401/403), or a typo/phantom model (404).
#
# Checks are anonymous on purpose — a model that needs a token or accepted terms is
# "broken" for a general app-pack user, so it should fail here.
#
# This is branch-aware: it sources THIS branch's model-select libs, so each branch
# (main / amd-rocm / intel-b70) validates its own menu. Run locally or in CI.
#
#   scripts/validate_models.sh           # vLLM + Ollama menus
#   exit 0 = all reachable, 1 = something is missing/gated
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RED=''; GREEN=''; YELLOW=''; NC=''   # color vars the libs expect (no-op in CI)
NIGHTLY_PREFIX="nightly"

# Fake a huge multi-vendor box so VRAM gates never hide a menu item from validation.
GPU_VENDOR="${GPU_VENDOR:-nvidia}"; TOTAL_VRAM=1000000; VRAM_GB=1000000; GPU_COUNT=8

source "$REPO_ROOT/scripts/lib/gpu_detect.sh" 2>/dev/null || true
source "$REPO_ROOT/scripts/lib/vllm_model_select.sh"
source "$REPO_ROOT/scripts/lib/ollama_model_select.sh" 2>/dev/null || true

fail=0

# --- HuggingFace repo (vLLM + ComfyUI) -----------------------------------------------
hf_status() {  # repo-id -> prints HTTP code
    curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
        "https://huggingface.co/$1/resolve/main/config.json"
}
check_hf() {  # label repo-id
    local code; code=$(hf_status "$2")
    case "$code" in
        200|307) printf '  ok   %-12s %s\n' "$1" "$2" ;;
        401|403) printf '  GATE %-12s %s  (HTTP %s — gated/needs token)\n' "$1" "$2" "$code"; fail=1 ;;
        *)       printf '  MISS %-12s %s  (HTTP %s)\n' "$1" "$2" "$code"; fail=1 ;;
    esac
}

# --- Ollama registry (personal_llm) --------------------------------------------------
check_ollama() {  # tag like qwen3:8b  (best-effort: warns, doesn't fail the build)
    local tag="$1" name ver
    name="${tag%%:*}"; ver="${tag#*:}"; [ "$ver" = "$tag" ] && ver="latest"
    local code; code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
        -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
        "https://registry.ollama.ai/v2/library/${name}/manifests/${ver}")
    case "$code" in
        200) printf '  ok   %-12s %s\n' "ollama" "$tag" ;;
        *)   printf '  WARN %-12s %s  (HTTP %s — verify on ollama.com)\n' "ollama" "$tag" "$code" ;;
    esac
}

echo "== vLLM menu (branch: $(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')) =="
if declare -f show_vllm_model_menu >/dev/null; then
    show_vllm_model_menu >/dev/null 2>&1   # sets MENU_MAX
    for c in $(seq 1 "${MENU_MAX:-14}"); do
        VLLM_MODEL_ID=""
        # </dev/null so the interactive "Custom" item reads EOF and skips instead of hanging.
        select_vllm_model "$c" </dev/null >/dev/null 2>&1 || true
        [ -z "$VLLM_MODEL_ID" ] && continue            # Custom / Skip / unset
        check_hf "vllm[$c]" "$VLLM_MODEL_ID"
    done
fi

echo "== Ollama menu =="
if declare -f select_ollama_model >/dev/null; then
    om_max="${MENU_MAX:-8}"
    show_ollama_model_menu >/dev/null 2>&1 && om_max="${MENU_MAX:-8}"
    for c in $(seq 1 "$om_max"); do
        OLLAMA_MODEL_TAG=""
        select_ollama_model "$c" </dev/null >/dev/null 2>&1 || true
        [ -z "$OLLAMA_MODEL_TAG" ] && continue
        check_ollama "$OLLAMA_MODEL_TAG"
    done
fi

echo ""
if [ "$fail" -eq 0 ]; then
    echo "✓ All vLLM model repos reachable."
else
    echo "✗ One or more model repos are missing/gated (see above)."
fi
exit "$fail"
