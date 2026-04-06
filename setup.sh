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

# 3.5. Integrity Check (MD5)
# Verify all shipped scripts against the checksums manifest.
# Supports both the new multi-file checksums.md5 and legacy install.sh.md5.

# GitHub archives extract to <repo>-<branch>/ — auto-detect the directory
EXTRACT_DIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
if [ -z "$EXTRACT_DIR" ]; then
    echo -e "${RED}Error: Archive extraction failed — no directory found.${NC}"
    exit 1
fi

CHECKSUM_FILE="$EXTRACT_DIR/checksums.md5"
LEGACY_CHECKSUM="$EXTRACT_DIR/install.sh.md5"

if [ -f "$CHECKSUM_FILE" ]; then
    echo -e "${BLUE}Verifying script integrity...${NC}"
    FAILED=false
    while IFS= read -r line; do
        EXPECTED_HASH=$(echo "$line" | awk '{print $1}')
        FILE_REL=$(echo "$line" | awk '{print $2}')
        FILE_ABS="$EXTRACT_DIR/$FILE_REL"

        if [ ! -f "$FILE_ABS" ]; then
            echo -e "  ${RED}✗ Missing: ${FILE_REL}${NC}"
            FAILED=true
            continue
        fi

        ACTUAL_HASH=$(md5sum "$FILE_ABS" | awk '{print $1}')
        if [ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
            echo -e "  ${RED}✗ MISMATCH: ${FILE_REL}${NC}"
            echo -e "    Expected: ${EXPECTED_HASH}"
            echo -e "    Got:      ${ACTUAL_HASH}"
            FAILED=true
        fi
    done < "$CHECKSUM_FILE"

    if [ "$FAILED" = true ]; then
        echo -e "${RED}✗ Integrity check FAILED.${NC}"
        echo -e "  One or more scripts may be corrupted or tampered with."
        echo -e "  If you just updated scripts, run: ${BLUE}scripts/update_checksum.sh${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ All scripts verified ($(wc -l < "$CHECKSUM_FILE") files).${NC}"
elif [ -f "$LEGACY_CHECKSUM" ]; then
    # Backwards compatibility: single-file install.sh.md5
    echo -e "${BLUE}Verifying installer integrity...${NC}"
    EXPECTED_HASH=$(awk '{print $1}' "$LEGACY_CHECKSUM")
    ACTUAL_HASH=$(md5sum "$EXTRACT_DIR/install.sh" | awk '{print $1}')
    if [ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
        echo -e "${RED}✗ Integrity check FAILED.${NC}"
        echo -e "  Expected MD5: ${EXPECTED_HASH}"
        echo -e "  Got MD5:      ${ACTUAL_HASH}"
        exit 1
    fi
    echo -e "${GREEN}✓ Installer integrity verified (MD5).${NC}"
else
    echo -e "${YELLOW}⚠ No checksum file found — skipping integrity check.${NC}"
fi

# 4. Handover to Main Installer
INSTALLER_PATH="$EXTRACT_DIR/install.sh"
chmod +x "$INSTALLER_PATH"

echo -e "${BLUE}Launching Installer...${NC}"
"$INSTALLER_PATH"

exit $?
