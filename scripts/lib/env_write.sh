#!/bin/bash
# Puget Systems — Shared .env Management
# Source this file; do not execute directly.
#
# Provides a single source of truth for .env file format,
# preventing duplicate keys, validating proxy URLs, and
# ensuring consistent behavior between install.sh and init.sh.
#
# Required colors: GREEN, BLUE, YELLOW, RED, NC

# write_env_header <pack_name> [env_file]
#   Truncates (or creates) the .env and writes the header.
#   Must be called BEFORE any write_env_var calls.
write_env_header() {
    local pack_name="${1:?Usage: write_env_header <pack_name> [env_file]}"
    local env_file="${2:-.env}"
    echo "PUGET_APP_NAME=${pack_name}" > "$env_file"
}

# write_env_var <key> <value> [env_file]
#   Appends KEY=VALUE to .env.
#   Skips if value is empty (avoids writing KEY= with no value).
write_env_var() {
    local key="${1:?Usage: write_env_var <key> <value> [env_file]}"
    local value="${2:-}"
    local env_file="${3:-.env}"

    # Skip empty values to keep .env clean
    if [ -z "$value" ]; then
        return 0
    fi

    echo "${key}=${value}" >> "$env_file"
}

# write_env_comment <text> [env_file]
#   Appends a comment line to .env.
write_env_comment() {
    local text="${1:-}"
    local env_file="${2:-.env}"
    echo "# ${text}" >> "$env_file"
}

# write_env_blank [env_file]
#   Appends a blank line to .env for readability.
write_env_blank() {
    local env_file="${1:-.env}"
    echo "" >> "$env_file"
}

# _cache_port_open host port  → 0 if a TCP connection succeeds within ~2s
_cache_port_open() { timeout 2 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }

# prompt_env_proxy [env_file]
#   Configure the LAN download cache for this install — NO interactive prompt.
#   Precedence:
#     1. Explicit env vars always win: HF_ENDPOINT (HF mirror) and/or CACHE_PROXY (proxy).
#     2. Otherwise AUTO-DETECT the Puget lab cache on PUGET_CACHE_HOST (default
#        172.19.168.179): Olah HF mirror on :8090, Squid proxy on :3128. Each is used
#        only if it actually answers within ~2s — automatic on the Puget LAN, and
#        silently skipped (direct downloads) everywhere else.
#   When a proxy is set, the HF mirror's host is added to NO_PROXY so multi-GB model
#   weights stream straight from the mirror instead of round-tripping through the proxy.
#   Returns 0 if any cache was configured, 1 if none.
prompt_env_proxy() {
    local env_file="${1:-.env}"
    local host="${PUGET_CACHE_HOST:-172.19.168.179}"
    local re='^https?://[a-zA-Z0-9._-]+(:[0-9]+)?/?$'
    local hf="" proxy=""

    # --- HF mirror endpoint: explicit env, else auto-detect the Olah mirror (:8090) ---
    if [ -n "${HF_ENDPOINT:-}" ]; then
        if echo "$HF_ENDPOINT" | grep -qE "$re"; then
            hf="$HF_ENDPOINT"; echo -e "${GREEN}✓ HF mirror (from env): $hf${NC}"
        else
            echo -e "${YELLOW}⚠ Ignoring malformed HF_ENDPOINT env var: '$HF_ENDPOINT'${NC}"
        fi
    elif _cache_port_open "$host" 8090; then
        hf="http://$host:8090"; echo -e "${GREEN}✓ Detected Puget HF mirror: $hf${NC}"
    fi

    # --- HF token: honor a preset HF_TOKEN from the environment (never prompted, never in
    # git). It authenticates the mirror's per-request repo-visibility HEAD to HF so anonymous
    # rate-limiting can't 401 cache lookups. Re-written to .env on every install so the
    # per-install .env reset can't drop it. Use a READ-ONLY token — it crosses the LAN to the
    # mirror in plaintext. The value is masked in output. ---
    if [ -n "${HF_TOKEN:-}" ]; then
        write_env_var "HF_TOKEN" "$HF_TOKEN" "$env_file"
        echo -e "${GREEN}✓ HF token configured from environment (read-only recommended)${NC}"
    fi

    # --- Squid forward proxy: explicit env, else auto-detect (:3128) ---
    if [ -n "${CACHE_PROXY:-}" ]; then
        if echo "$CACHE_PROXY" | grep -qE "$re"; then
            proxy="$CACHE_PROXY"; echo -e "${GREEN}✓ Cache proxy (from env): $proxy${NC}"
        else
            echo -e "${YELLOW}⚠ Ignoring malformed CACHE_PROXY env var: '$CACHE_PROXY'${NC}"
        fi
    elif _cache_port_open "$host" 3128; then
        proxy="http://$host:3128"; echo -e "${GREEN}✓ Detected Puget cache proxy: $proxy${NC}"
    fi

    [ -n "$hf" ] && write_env_var "HF_ENDPOINT" "$hf" "$env_file"
    if [ -n "$proxy" ]; then
        write_env_var "CACHE_PROXY" "$proxy" "$env_file"
        local noproxy="localhost,127.0.0.1,0.0.0.0"
        if [ -n "$hf" ]; then
            local hfhost; hfhost=$(echo "$hf" | sed -E 's#^https?://##; s#[:/].*$##')
            noproxy="${noproxy},${hfhost}"
        fi
        write_env_var "NO_PROXY" "$noproxy" "$env_file"
    fi

    if [ -z "$hf" ] && [ -z "$proxy" ]; then
        echo "  No LAN download cache detected — using direct downloads."
        return 1
    fi
    return 0
}

# validate_env [env_file]
#   Validates .env for common issues. Returns 0 if valid, 1 if errors found.
#   Prints warnings/errors with color output.
validate_env() {
    local env_file="${1:-.env}"
    local errors=0

    if [ ! -f "$env_file" ]; then
        echo -e "${RED}✗ .env file not found: $env_file${NC}"
        return 1
    fi

    # Check for duplicate keys (ignoring comments and blanks)
    local dupes
    dupes=$(grep -v '^#' "$env_file" | grep -v '^$' | cut -d= -f1 | sort | uniq -d)
    if [ -n "$dupes" ]; then
        echo -e "${RED}✗ Duplicate keys in .env:${NC}"
        echo "$dupes" | while IFS= read -r key; do
            echo -e "  ${RED}${key}${NC} (appears $(grep -c "^${key}=" "$env_file") times)"
        done
        errors=$((errors + 1))
    fi

    # Validate CACHE_PROXY format if set
    local proxy
    proxy=$(grep '^CACHE_PROXY=' "$env_file" 2>/dev/null | tail -1 | cut -d= -f2-)
    if [ -n "$proxy" ] && ! echo "$proxy" | grep -qE '^https?://[a-zA-Z0-9._-]+(:[0-9]+)?/?$'; then
        echo -e "${RED}✗ Invalid CACHE_PROXY format: '${proxy}'${NC}"
        echo "  Must be http://host:port (e.g. http://192.0.2.100:3128)"
        errors=$((errors + 1))
    fi

    # Validate VLLM_IMAGE is a known tag (warning, not error)
    local image
    image=$(grep '^VLLM_IMAGE=' "$env_file" 2>/dev/null | tail -1 | cut -d= -f2-)
    # Accept the known per-vendor inference images: NVIDIA (vllm/vllm-openai), AMD ROCm
    # (rocm/vllm — AMD's official arch-pinned builds; ggml-org/llama.cpp — AMD team_llm runs
    # llama.cpp, not vLLM), Intel (intel/llm-scaler-vllm), and locally-built puget-vllm-*
    # images. Anything else gets a (non-fatal) heads-up.
    if [ -n "$image" ] && ! echo "$image" | grep -qE '^(vllm/vllm-openai:(latest|nightly|cu130-nightly|v[0-9]+\.[0-9]+\.[0-9]+)|rocm/vllm:.+|ghcr\.io/ggml-org/llama\.cpp:.+|intel/llm-scaler-vllm:.+|puget-vllm-.+)$'; then
        echo -e "${YELLOW}⚠ Non-standard inference image: '${image}'${NC}"
    fi

    if [ "$errors" -gt 0 ]; then
        echo -e "${RED}✗ .env validation failed ($errors error(s)).${NC}"
        echo "  Fix the issues above or regenerate with init.sh"
        return 1
    fi

    return 0
}
