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

# prompt_env_proxy [env_file]
#   Interactively prompts for a cache proxy URL, validates format,
#   and writes CACHE_PROXY to .env if provided.
#   Returns 0 = proxy set, 1 = skipped
prompt_env_proxy() {
    local env_file="${1:-.env}"

    echo -e "${YELLOW}Cache Proxy (Optional):${NC}"
    echo "  If this system is on a LAN with a Puget cache proxy (Squid),"
    echo "  model downloads can be cached to avoid re-downloading."
    echo "  Example: http://192.0.2.100:3128"

    while true; do
        read -p "  Enter cache proxy URL (or press Enter to skip): " CACHE_URL
        if [ -z "$CACHE_URL" ]; then
            return 1
        elif echo "$CACHE_URL" | grep -qE '^https?://[a-zA-Z0-9._-]+(:[0-9]+)?/?$'; then
            write_env_var "CACHE_PROXY" "$CACHE_URL" "$env_file"
            echo -e "${GREEN}✓ Cache proxy configured: $CACHE_URL${NC}"
            return 0
        else
            echo -e "${RED}  ✗ Invalid URL format. Must be http://host:port (e.g. http://192.0.2.100:3128)${NC}"
        fi
    done
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
    if [ -n "$image" ] && ! echo "$image" | grep -qE '^(latest|nightly|cu130-nightly)$'; then
        echo -e "${YELLOW}⚠ Non-standard VLLM_IMAGE tag: '${image}'${NC}"
    fi

    if [ "$errors" -gt 0 ]; then
        echo -e "${RED}✗ .env validation failed ($errors error(s)).${NC}"
        echo "  Fix the issues above or regenerate with init.sh"
        return 1
    fi

    return 0
}
