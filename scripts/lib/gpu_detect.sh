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
    DRIVER_VERSION=""

    # --- AMD DETECTION ---
    # Check for AMD GPUs via PCI vendor ID 0x1002
    # Must be checked before Intel since both expose /dev/dri render nodes
    local amd_count=0
    local amd_name=""
    local amd_vram_bytes=0
    for card_dir in /sys/class/drm/card[0-9]*/; do
        [ -d "$card_dir" ] || continue
        local vendor_file="$card_dir/device/vendor"
        if [ -f "$vendor_file" ] && [ "$(cat "$vendor_file")" = "0x1002" ]; then
            amd_count=$((amd_count + 1))
            # Read device name from lspci via PCI slot
            if [ -z "$amd_name" ] && command -v lspci &>/dev/null; then
                local pci_slot
                pci_slot=$(basename "$(readlink -f "$card_dir/device")")
                amd_name=$(lspci -s "$pci_slot" 2>/dev/null | awk -F': ' '{print $2}')
            fi
            # Read VRAM from sysfs (per-GPU, take the first)
            local vram_file="$card_dir/device/mem_info_vram_total"
            if [ -f "$vram_file" ] && [ "$amd_vram_bytes" -eq 0 ]; then
                amd_vram_bytes=$(cat "$vram_file")
            fi
        fi
    done

    if [ "$amd_count" -gt 0 ]; then
        GPU_VENDOR="amd"
        GPU_COUNT=$amd_count
        GPU_NAME="${amd_name:-AMD GPU}"
        VRAM_MB=$((amd_vram_bytes / 1024 / 1024))
        VRAM_GB=$((VRAM_MB / 1024))
        TOTAL_VRAM=$((VRAM_GB * GPU_COUNT))
        # amdgpu kernel driver version (informational; ROCm userspace ships in the container)
        DRIVER_VERSION=$(cat /sys/module/amdgpu/version 2>/dev/null || true)
        return 0
    fi

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
        DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
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

# min_driver_for_image IMAGE — echo the minimum NVIDIA driver major version the
# container image needs, or nothing when no gate applies (AMD/Intel images ship
# their own userspace; only the NVIDIA driver↔CUDA coupling bites here).
# The mapping is the CUDA release each image line is built against:
#   CUDA 13.0 → driver ≥ 580,  CUDA 12.8/12.9 → driver ≥ 570.
# This is the single source of truth — the bench sources this file and gates
# model selection with it, so keep it updated when image lines move to a new CUDA.
min_driver_for_image() {
    case "$1" in
        *cu130*)                   echo 580 ;;   # CUDA 13.0 (Blackwell nightly line)
        *cu128*|*cu129*)           echo 570 ;;
        vllm/vllm-openai:*)        echo 570 ;;   # stable/latest/nightly are CUDA 12.8+ builds
        rocm/*|*rocm*|intel/*|puget-vllm-xpu*) ;;  # non-NVIDIA: no NVIDIA driver gate
        *) ;;
    esac
}

# driver_meets_min INSTALLED MIN — return 0 when the installed driver major
# version satisfies the minimum (or when either side is unknown — never block
# on missing data, the container launch will surface a real mismatch).
driver_meets_min() {
    local installed_major="${1%%.*}" min="$2"
    [ -z "$min" ] && return 0
    [[ "$installed_major" =~ ^[0-9]+$ ]] || return 0
    [ "$installed_major" -ge "$min" ]
}
