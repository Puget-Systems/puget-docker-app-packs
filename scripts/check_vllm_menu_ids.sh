#!/bin/bash
# Puget Systems — vLLM menu model-ID accessibility check (CI guard)
#
# Every model offered by the vLLM selection menu must resolve on Hugging Face.
# A shipping menu full of 404/401 model IDs (as happened with the old GPTQ list)
# is the exact failure this catches. Run in CI and before releasing the pack.
#
# Exit code 0 = all IDs reachable; non-zero = at least one is not.
# Honors $HF_TOKEN for gated repos (a 401 without a token is reported as GATED,
# which is a soft warning, not a hard failure).

set -uo pipefail

SELECT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/vllm_model_select.sh"

# Stub the globals/colors the menu file expects, then harvest every literal
# VLLM_MODEL_ID="owner/model" assignment from the menu source. We read the IDs
# statically (no shell eval of the menu) so this is safe to run anywhere.
ids=$(grep -oE 'VLLM_MODEL_ID="[^"]+"' "$SELECT_LIB" \
        | sed -E 's/VLLM_MODEL_ID="([^"]+)"/\1/' \
        | grep -vE '^\s*$' | sort -u)

if [ -z "$ids" ]; then
    echo "✗ No model IDs found in $SELECT_LIB"
    exit 2
fi

token="${HF_TOKEN:-${HUGGINGFACE_HUB_TOKEN:-}}"
auth=(); [ -n "$token" ] && auth=(-H "Authorization: Bearer $token")

fail=0
echo "Checking vLLM menu model IDs ($(echo "$ids" | wc -l | tr -d ' ') unique)..."
while IFS= read -r id; do
    code=$(curl -s ${auth[@]+"${auth[@]}"} -o /dev/null -w "%{http_code}" \
        --max-time 15 "https://huggingface.co/api/models/$id")
    case "$code" in
        200|307) echo "  ✓ $code  $id" ;;
        401|403) echo "  ⚠ $code  $id  (GATED — needs HF_TOKEN/accept terms)" ;;
        *)       echo "  ✗ $code  $id"; fail=1 ;;
    esac
done <<< "$ids"

if [ "$fail" -ne 0 ]; then
    echo "FAIL: one or more menu model IDs are unreachable."
    exit 1
fi
echo "OK: all menu model IDs resolve."
