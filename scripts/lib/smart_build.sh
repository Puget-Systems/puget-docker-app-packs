#!/bin/bash
# Puget Systems — Smart Build (fingerprint-based rebuild detection)
# Source this file; do not execute directly.
# Requires ANSI color variables (GREEN, BLUE, YELLOW, RED, NC) to be set.

generate_build_fingerprint() {
    cat Dockerfile docker-compose.yml requirements.txt 2>/dev/null | sha256sum | awk '{print $1}'
}

smart_build() {
    local CURRENT_FP
    CURRENT_FP=$(generate_build_fingerprint)
    local SAVED_FP=""
    if [ -f ".build_fingerprint" ]; then
        SAVED_FP=$(cat .build_fingerprint)
    fi

    local BUILD_EXIT=0
    if [ -z "$SAVED_FP" ]; then
        # First build — use normal layer-cached build
        echo -e "${BLUE}Building container...${NC}"
        docker compose build || BUILD_EXIT=$?
    elif [ "$CURRENT_FP" != "$SAVED_FP" ]; then
        echo -e "${YELLOW}⚠ Build configuration has changed since last build.${NC}"
        echo -e "${BLUE}Rebuilding container (--no-cache)...${NC}"
        docker compose build --no-cache || BUILD_EXIT=$?
    else
        # No changes — skip build entirely
        return 0
    fi

    if [ $BUILD_EXIT -ne 0 ]; then
        echo -e "${RED}✗ Build failed (exit code $BUILD_EXIT).${NC}"
        return $BUILD_EXIT
    fi
    echo "$CURRENT_FP" > .build_fingerprint
    echo -e "${GREEN}✓ Build fingerprint saved.${NC}"
    return 0
}
