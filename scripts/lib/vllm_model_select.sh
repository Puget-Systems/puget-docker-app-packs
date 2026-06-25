#!/bin/bash
# Puget Systems — vLLM Model Selection (vendor dispatcher)
#
# The same entry points — show_vllm_model_menu / select_vllm_model — serve every GPU
# vendor. The real per-vendor menus live in vllm_menu_<vendor>.sh; this file LAZILY
# sources the right one the first time an entry point is called, by which point
# detect_gpus has set $GPU_VENDOR. (install.sh sources this file at startup, before the
# GPU is detected, so the vendor cannot be chosen at source time.)
#
# Source this file; do not execute directly.

_VMS_LIBDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source the per-vendor menu for the current $GPU_VENDOR (default nvidia). The vendor
# file redefines show_vllm_model_menu / select_vllm_model with its real implementation,
# replacing these dispatch stubs — so subsequent calls go straight to the vendor code.
_vms_load_vendor() {
    case "${GPU_VENDOR:-nvidia}" in
        amd)   source "$_VMS_LIBDIR/vllm_menu_amd.sh" ;;
        intel) source "$_VMS_LIBDIR/vllm_menu_intel.sh" ;;
        *)     source "$_VMS_LIBDIR/vllm_menu_nvidia.sh" ;;
    esac
}

show_vllm_model_menu() { _vms_load_vendor; show_vllm_model_menu "$@"; }
select_vllm_model()    { _vms_load_vendor; select_vllm_model "$@"; }
