#!/bin/bash
# Puget Systems — Shared GPU Detection
# Source this file; do not execute directly.
# After sourcing, call detect_gpus to populate environment variables.

# --- Pinned vLLM nightly (NVIDIA) ---------------------------------------------
# Every NVIDIA menu entry that needs a nightly vLLM uses VLLM_NIGHTLY_IMAGE, and
# validate_models.sh reads it too, so this is the one place the pin lives.
#
# Why pinned and mirrored: upstream `vllm/vllm-openai:nightly` moves every day, so
# installs were not reproducible and a known-good build could regress overnight.
# vLLM also prunes old `nightly-<sha>` tags from Docker Hub, and a bare Docker Hub
# digest stops being pullable once no tag references it. So tested builds are copied
# (multi-arch index, digest preserved) to our own GHCR package, which we never prune.
# The ref carries the tag (readable: it is the vLLM commit) and the digest (immutable).
#
# .github/workflows/vllm-nightly.yml checks daily that this ref still resolves, and
# keeps one rolling `needs-gpu-validation` PR that bumps these two lines when upstream
# moves. Merge it only after a GPU test pass on the candidate build.
# VLLM_NIGHTLY_CUDA is the image's CUDA_VERSION (from its config env); it sets the
# driver floor for the pin in min_driver_for_image below.
VLLM_NIGHTLY_IMAGE="ghcr.io/puget-systems/vllm-openai:nightly-e68efc685ab1e6f1eda004ced7157e3ca411da2f@sha256:1ff6716fe240a922d0d518b8884261e25b0c02eda8e2ce90888e364978249cad"
VLLM_NIGHTLY_CUDA="13.0.2"

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

        # Detect compute capability. Blackwell spans TWO major versions, and the
        # split is by product line, not by age:
        #   10.x — datacenter Blackwell: sm_100 (B200/GB200), sm_103 (GB300 Ultra)
        #   12.x — consumer/workstation Blackwell: sm_120 (RTX 50 / RTX PRO 6000), sm_121
        # Hopper is 9.x, so ">= 10" is the correct family test. The previous ">= 12"
        # check silently misclassified every datacenter Blackwell box as pre-Blackwell,
        # which failed the NVFP4 menu gates. Found on a GB300 (compute 10.3), Sept 2026.
        #
        # Every family uses the same nightly build (VLLM_NIGHTLY_IMAGE, pinned at the
        # top of this file). vLLM stopped publishing `cu130-nightly` on 2026-04-23
        # (frozen at 0.19.2, no sm_103), and `nightly` itself is now the CUDA 13.0
        # build, so it is the same line, kept current.
        COMPUTE_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1)
        COMPUTE_MAJOR=$(echo "$COMPUTE_CAP" | cut -d. -f1)
        if [ "${COMPUTE_MAJOR:-0}" -ge 10 ] 2>/dev/null; then
            IS_BLACKWELL=true
        else
            IS_BLACKWELL=false
        fi
        return 0
    fi

    return 1
}

# min_driver_for_cuda VERSION — echo the minimum NVIDIA driver major version for a
# CUDA runtime version (e.g. 13.0.2), or nothing when the release is not in the
# table yet. Add a row only once the floor is confirmed in NVIDIA's CUDA release
# notes. validate_models.sh fails when a menu's NVIDIA image maps to nothing, so a
# candidate pin on a new CUDA line cannot pass CI until its row exists here.
min_driver_for_cuda() {
    case "$1" in
        13.0|13.0.*)               echo 580 ;;
        12.8|12.8.*|12.9|12.9.*)   echo 570 ;;
        *) ;;
    esac
}

# min_driver_for_image IMAGE — echo the minimum NVIDIA driver major version the
# container image needs, or nothing when no gate applies (AMD/Intel images ship
# their own userspace; only the NVIDIA driver↔CUDA coupling bites here).
# The mapping is the CUDA release each image line is built against:
#   CUDA 13.0 → driver ≥ 580,  CUDA 12.8/12.9 → driver ≥ 570.
# The pinned nightly follows VLLM_NIGHTLY_CUDA, so a pin bump that moves to a new
# CUDA line (e.g. the cu134 nightlies) moves the floor with it.
# As of 2026-10 every other vllm/vllm-openai tag the menus use (latest, v0.20.2,
# v0.25.0) is a CUDA 13.0.2 build, so all of them need 580.
# This is the single source of truth — the bench sources this file and gates
# model selection with it, so keep it updated when image lines move to a new CUDA.
min_driver_for_image() {
    case "$1" in
        "$VLLM_NIGHTLY_IMAGE")     min_driver_for_cuda "$VLLM_NIGHTLY_CUDA" ;;
        *cu130*)                   echo 580 ;;   # CUDA 13.0
        *cu128*|*cu129*)           echo 570 ;;
        *cu13[1-9]*)               ;;            # newer CUDA line: floor unknown, see above
        # An older mirrored nightly (e.g. an operator override) is the same upstream line.
        vllm/vllm-openai:*|ghcr.io/puget-systems/vllm-openai:*)
                                   echo 580 ;;   # latest/vX.Y.Z are CUDA 13.0 builds
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
