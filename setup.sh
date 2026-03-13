#!/bin/bash

# Puget Systems App Pack - One-Line Bootstrap Installer
# This script downloads the latest installer logic and runs it.
# Dependencies: curl OR wget (no git required)

# ANSI Color Codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Distribution Compatibility Check ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "ubuntu" ]; then
        echo -e "${RED}Error: Unsupported Linux distribution detected: ${ID:-unknown}${NC}"
        echo -e "       The Puget Docker App Pack currently supports ${GREEN}Ubuntu${NC} only."
        echo -e "       (Detected: $PRETTY_NAME)"
        exit 1
    fi
else
    echo -e "${RED}Error: Cannot detect Linux distribution (/etc/os-release not found).${NC}"
    echo -e "       The Puget Docker App Pack requires ${GREEN}Ubuntu${NC}."
    exit 1
fi

# Default to main if not specified
BRANCH=${BRANCH:-main}
REPO_URL="https://github.com/Puget-Systems/puget-docker-app-pack/archive/refs/heads/$BRANCH.tar.gz"
PROJECT_NAME="puget-docker-app-pack"

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}   Puget Systems Docker App Pack - Bootstrap Installer${NC}"
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}   Branch: ${GREEN}$BRANCH${NC}"

# 1. Setup Temporary Environment
TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo ""
echo -e "${BLUE}Fetching latest install scripts...${NC}"

# 2. Download and Extract (curl or wget)
ARCHIVE_PATH="$TEMP_DIR/pack.tar.gz"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$REPO_URL" -o "$ARCHIVE_PATH"
elif command -v wget >/dev/null 2>&1; then
    wget -q "$REPO_URL" -O "$ARCHIVE_PATH"
else
    echo -e "${RED}Error: Neither 'curl' nor 'wget' found. Please install one.${NC}"
    exit 1
fi

if [ ! -f "$ARCHIVE_PATH" ]; then
    echo -e "${RED}Error: Failed to download repository archive.${NC}"
    exit 1
fi

# 3. Extract Archive
tar -xzf "$ARCHIVE_PATH" -C "$TEMP_DIR"
echo -e "${GREEN}Assets acquired.${NC}"

# 4. Handover to Main Installer
# GitHub archives extract to <repo>-<branch>/ directory
# Note: GitHub sanitizes branch names in archives (e.g. feature/foo -> feature-foo)
# For simple branches (main, develop) this is 1:1.
INSTALLER_PATH="$TEMP_DIR/${PROJECT_NAME}-${BRANCH}/install.sh"
chmod +x "$INSTALLER_PATH"

echo -e "${BLUE}Launching Installer...${NC}"
"$INSTALLER_PATH"

exit $?
