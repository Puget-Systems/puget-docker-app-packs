#!/bin/bash
# Puget Systems — Shared GPU Detection
# Source this file; do not execute directly.
# After sourcing, call detect_gpus to populate environment variables.

detect_gpus() {
    if ! command -v nvidia-smi &> /dev/null; then
        GPU_COUNT=0
        GPU_NAME="unknown"
        VRAM_MB=0
        VRAM_GB=0
        TOTAL_VRAM=0
        COMPUTE_CAP="0.0"
        COMPUTE_MAJOR=0
        IS_BLACKWELL=false
        NIGHTLY_PREFIX="nightly"
        return 1
    fi

    GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
    GPU_NAME=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | head -1)
    VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)

    # Unified memory GPUs (e.g., NVIDIA GB10 / DGX Spark) report [N/A] for VRAM.
    # Fall back to total system RAM since unified memory = all RAM is GPU-accessible.
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
}
