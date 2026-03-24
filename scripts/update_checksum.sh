#!/bin/bash
# Regenerate install.sh.md5 after editing install.sh
# Run this before committing changes to install.sh

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )"

cd "$REPO_ROOT"

if [ ! -f "install.sh" ]; then
    echo "Error: install.sh not found in $REPO_ROOT"
    exit 1
fi

md5sum install.sh > install.sh.md5
echo "✓ Updated install.sh.md5: $(cat install.sh.md5)"
