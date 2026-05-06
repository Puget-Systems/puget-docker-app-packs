#!/bin/bash
# Puget Systems — Shared GPU Detection
# Source this file; do not execute directly.
# After sourcing, call detect_gpus to populate environment variables.

detect_gpus() {
    # Initialize defaults
    GPU_VENDOR="unknown"
    GPU_COUNT=0
    GPU_NAME="unknown"
    VRAM_MB=0
    VRAM_GB=0
    TOTAL_VRAM=0
    COMPUTE_CAP="0.0"
    COMPUTE_MAJOR=0
    IS_BLACKWELL=false
    NIGHTLY_PREFIX="nightly"

    # --- INTEL DETECTION ---
    if ls /dev/dri/renderD* 1> /dev/null 2>&1 && lspci 2>/dev/null | grep -iE 'vga|display|3d' | grep -i 'intel' 1> /dev/null 2>&1; then
        GPU_VENDOR="intel"
        # Count number of render nodes
        GPU_COUNT=$(ls -1q /dev/dri/renderD* | wc -l | tr -d ' ')
        
        # Determine GPU Name (fallback)
        GPU_NAME=$(lspci -v 2>/dev/null | grep -iE 'vga|display|3d' | grep -i 'intel' | head -1 | awk -F': ' '{print $2}')
        if [[ "$GPU_NAME" == "" ]]; then
            GPU_NAME="Intel ARC GPU"
        fi

        # Determine VRAM: fallback to 32GB (32768 MB) since lmem_total_bytes is missing for B70
        # If clinfo is available, we try to parse it, but it's slow. We'll use 32GB as standard for B70.
        # Alternatively, check clinfo if it exists.
        if command -v clinfo &> /dev/null; then
            VRAM_MB=$(clinfo 2>/dev/null | grep -i 'Global memory size' | head -1 | awk '{print $4}' | awk '{printf "%d", $1/1024/1024}')
        fi
        
        if [ -z "$VRAM_MB" ] || [ "$VRAM_MB" -eq 0 ]; then
            VRAM_MB=32768 # Default 32GB for B70
        fi

        VRAM_GB=$((VRAM_MB / 1024))
        TOTAL_VRAM=$((VRAM_GB * GPU_COUNT))
        return 0
    fi

    # --- NVIDIA DETECTION ---
    if command -v nvidia-smi &> /dev/null; then
        GPU_VENDOR="nvidia"
        GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
        GPU_NAME=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | head -1)
        VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)

        # Unified memory GPUs (e.g., NVIDIA GB10 / DGX Spark) report [N/A] for VRAM.
        if [[ "$VRAM_MB" == *"N/A"* ]] || [[ -z "$VRAM_MB" ]] || ! [[ "$VRAM_MB" =~ ^[0-9]+$ ]]; then
            VRAM_MB=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
            IS_UNIFIED_MEMORY=true
        else
            IS_UNIFIED_MEMORY=false
        fi
        VRAM_GB=$((VRAM_MB / 1024))
        TOTAL_VRAM=$((VRAM_GB * GPU_COUNT))

        # Detect compute capability (Blackwell = 12.0+)
        COMPUTE_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1)
        COMPUTE_MAJOR=$(echo "$COMPUTE_CAP" | cut -d. -f1)
        if [ "${COMPUTE_MAJOR:-0}" -ge 12 ] 2>/dev/null; then
            IS_BLACKWELL=true
            NIGHTLY_PREFIX="cu130-nightly"
        else
            IS_BLACKWELL=false
            NIGHTLY_PREFIX="nightly"
        fi
        return 0
    fi

    return 1
}
