#!/bin/bash
# Regenerate checksums.md5 for all tracked script files.
# Run this before committing changes to any .sh file.

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )"
cd "$REPO_ROOT"

# All shell scripts that ship in the distribution (excluding this script itself)
SCRIPT_FILES=$(find . -name '*.sh' \
    -not -path './.git/*' \
    -not -path './context_portal/*' \
    -not -path './scripts/update_checksum.sh' \
    | sort)

if [ -z "$SCRIPT_FILES" ]; then
    echo "Error: No .sh files found in $REPO_ROOT"
    exit 1
fi

# Generate manifest: one "hash  filename" per line
md5sum $SCRIPT_FILES > checksums.md5

echo "✓ Updated checksums.md5 ($(wc -l < checksums.md5) files):"
cat checksums.md5
