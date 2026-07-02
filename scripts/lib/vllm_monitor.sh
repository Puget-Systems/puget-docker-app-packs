#!/bin/bash
# Puget Systems — vLLM Startup Progress Monitor
# Source this file; do not execute directly.
# Requires ANSI color variables (GREEN, BLUE, YELLOW, RED, NC) to be set.
#
# Usage: wait_for_vllm <container_name> <model_size_gb> [stall_seconds]
#
# Readiness is bounded by STALL, not a flat wall-clock: the load may take as long as
# it needs as long as it keeps making progress (downloading, loading weights, or
# compiling). We fingerprint progress each poll (container net I/O + disk I/O + GPU
# memory + tail-log checksum) and only give up after STALL_SECONDS with NO change —
# which reliably distinguishes a slow-but-progressing load from a true hang (e.g. an
# NCCL deadlock, where all of those freeze). Returns 0 when the API is ready, else 1.

wait_for_vllm() {
    local CONTAINER_NAME="${1:?Usage: wait_for_vllm <container_name> <model_size_gb> [stall_seconds]}"
    local MODEL_SIZE_GB="${2:-0}"
    local STALL_SECONDS="${3:-${VLLM_STALL_SECONDS:-600}}"  # no-progress window before declaring a hang

    # Disable set -e for the monitoring loop — polling commands (grep -q,
    # docker stats, curl) routinely return non-zero and must not kill the script.
    local OLD_OPTS=$(set +o)
    set +e

    local READY=false
    local RESULT=1               # assume failure until the API is confirmed ready
    local LAST_PHASE=""
    local PHASE_LEVEL=0           # Monotonic: phases only advance forward
    local LAST_RESTART_COUNT=0    # Track container restarts to detect crash loops
    local CRASH_DETECTIONS=0      # Number of times we've seen a restart increment
    local START_TIME LAST_PROGRESS_TIME LAST_FP=""
    START_TIME=$(date +%s)
    LAST_PROGRESS_TIME=$START_TIME

    while ! $READY; do
        # Check if container is still running
        if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo -e "\n${RED}✗ vLLM container exited. Check logs:${NC}"
            echo -e "  ${BLUE}docker compose logs inference${NC}"
            break
        fi

        # Detect crash loops (container restarting repeatedly)
        local RESTART_COUNT
        RESTART_COUNT=$(docker inspect --format='{{.RestartCount}}' "$CONTAINER_NAME" 2>/dev/null || echo "0")
        if [ "$RESTART_COUNT" -gt "$LAST_RESTART_COUNT" ] 2>/dev/null; then
            CRASH_DETECTIONS=$((CRASH_DETECTIONS + 1))
            LAST_RESTART_COUNT=$RESTART_COUNT
            # Reset phase tracking since we're on a fresh attempt
            PHASE_LEVEL=0
            LAST_PHASE=""
        fi

        if [ "$CRASH_DETECTIONS" -ge 2 ]; then
            echo ""
            echo -e "${RED}✗ vLLM is crash-looping (restarted ${RESTART_COUNT} times).${NC}"
            echo ""
            # Extract the actual error from the logs
            local ERROR_MSG
            ERROR_MSG=$(docker logs "$CONTAINER_NAME" 2>&1 | grep -E "RuntimeError|OutOfMemoryError|CUDA|Error|error" | tail -5)
            if [ -n "$ERROR_MSG" ]; then
                echo -e "${RED}  Error from logs:${NC}"
                echo "$ERROR_MSG" | while IFS= read -r line; do
                    echo -e "  ${YELLOW}${line}${NC}"
                done
                echo ""
            fi
            echo "  Troubleshooting:"
            echo -e "  ${BLUE}docker compose logs inference${NC}  - View full logs"
            echo -e "  Try reducing GPU memory: edit .env and lower MAX_CONTEXT"
            echo -e "  Or try a smaller model: ${BLUE}./init.sh${NC}"
            break
        fi

        # Check if API is responding (model fully loaded)
        if curl -s --max-time 2 http://localhost:8000/v1/models > /dev/null 2>&1; then
            local ELAPSED=$(( $(date +%s) - START_TIME ))
            local ELAPSED_MIN=$((ELAPSED / 60))
            local ELAPSED_SEC=$((ELAPSED % 60))
            echo -e "\n${GREEN}✓ Model loaded and ready! (${ELAPSED_MIN}m ${ELAPSED_SEC}s)${NC}"
            READY=true
            RESULT=0
            break
        fi

        # Parse vLLM logs to determine startup phase
        local LAST_LOG
        LAST_LOG=$(docker logs "$CONTAINER_NAME" --tail 20 2>&1)
        local CANDIDATE_PHASE=""
        local CANDIDATE_LEVEL=0
        local DETAIL=""

        # Check phases in order of progression (highest priority first)
        if echo "$LAST_LOG" | grep -q "CUDA graphs"; then
            local GRAPH_PCT
            GRAPH_PCT=$(echo "$LAST_LOG" | grep -oE '[0-9]+%\|' | sed 's/|//' | tail -1)
            CANDIDATE_PHASE="Capturing CUDA graphs"
            CANDIDATE_LEVEL=5
            DETAIL="${GRAPH_PCT:-working...}"
        elif echo "$LAST_LOG" | grep -qE "Dynamo bytecode transform|Compiling a graph|Start compiling|torch\.compile takes [0-9]"; then
            # Match real compile activity only. Plain "torch.compile" also appears in
            # the engine config dump and in "disabling torch.compile" (enforce-eager),
            # which previously latched this phase at level 4 and masked the download/
            # load phases for the rest of startup.
            CANDIDATE_PHASE="Compiling model kernels"
            CANDIDATE_LEVEL=4
            DETAIL="(torch.compile)"
        elif echo "$LAST_LOG" | grep -q "Autotuning"; then
            CANDIDATE_PHASE="Autotuning kernels"
            CANDIDATE_LEVEL=3
            DETAIL=""
        elif echo "$LAST_LOG" | grep -q "Loading safetensors\|Loading weights\|Starting to load model"; then
            local SHARD_PCT
            SHARD_PCT=$(echo "$LAST_LOG" | grep -oE '[0-9]+% Completed' | tail -1)
            CANDIDATE_PHASE="Loading model weights"
            CANDIDATE_LEVEL=2
            DETAIL="${SHARD_PCT:-starting...}"
        elif echo "$LAST_LOG" | grep -qiE "Downloading|Fetching"; then
            CANDIDATE_PHASE="Downloading model"
            CANDIDATE_LEVEL=1
            DETAIL=""
        fi

        # For any phase at level <= 1, check NET I/O for live download progress
        if [ "$CANDIDATE_LEVEL" -le 1 ] || [ -z "$CANDIDATE_PHASE" ]; then
            local NET_RX
            NET_RX=$(docker stats "$CONTAINER_NAME" --no-stream --format '{{.NetIO}}' 2>/dev/null | awk -F'/' '{print $1}' | xargs)
            local NET_VAL
            NET_VAL=$(echo "$NET_RX" | grep -oE '[0-9.]+' | head -1)
            local NET_UNIT
            NET_UNIT=$(echo "$NET_RX" | grep -oE '[A-Za-z]+' | head -1)

            local NET_GB=0
            case "$NET_UNIT" in
                GB|GiB) NET_GB=$(echo "$NET_VAL" | cut -d. -f1) ;;
                MB|MiB) NET_GB=0 ;;
                TB|TiB) NET_GB=$(($(echo "$NET_VAL" | cut -d. -f1) * 1024)) ;;
            esac

            if [ "$NET_GB" -gt 0 ] 2>/dev/null && [ "$MODEL_SIZE_GB" -gt 0 ] 2>/dev/null; then
                local DL_PCT=$((NET_GB * 100 / MODEL_SIZE_GB))
                [ "$DL_PCT" -gt 100 ] && DL_PCT=100
                CANDIDATE_PHASE="Downloading model"
                CANDIDATE_LEVEL=1
                DETAIL="${DL_PCT}% (${NET_RX} / ${MODEL_SIZE_GB} GB)"
            elif [ -n "$NET_VAL" ] && echo "$NET_UNIT" | grep -qiE "MB|MiB" 2>/dev/null; then
                local NET_MB
                NET_MB=$(echo "$NET_VAL" | cut -d. -f1)
                if [ "${NET_MB:-0}" -gt 50 ] 2>/dev/null; then
                    CANDIDATE_PHASE="Downloading model"
                    CANDIDATE_LEVEL=1
                    DETAIL="${NET_RX}"
                elif [ -z "$CANDIDATE_PHASE" ]; then
                    if echo "$LAST_LOG" | grep -q "Resolved architecture\|model_tag\|max_model_len"; then
                        CANDIDATE_PHASE="Initializing model"
                        CANDIDATE_LEVEL=0
                        DETAIL=""
                    else
                        CANDIDATE_PHASE="Starting up"
                        CANDIDATE_LEVEL=0
                        DETAIL="waiting..."
                    fi
                fi
            elif [ -z "$CANDIDATE_PHASE" ]; then
                if echo "$LAST_LOG" | grep -q "Resolved architecture\|model_tag\|max_model_len"; then
                    CANDIDATE_PHASE="Initializing model"
                    CANDIDATE_LEVEL=0
                    DETAIL=""
                else
                    CANDIDATE_PHASE="Starting up"
                    CANDIDATE_LEVEL=0
                    DETAIL="waiting..."
                fi
            fi
        fi

        # Only advance phase forward, never regress (prevents oscillation)
        local PHASE
        if [ "$CANDIDATE_LEVEL" -ge "$PHASE_LEVEL" ]; then
            if [ "$CANDIDATE_PHASE" != "$LAST_PHASE" ] && [ -n "$LAST_PHASE" ]; then
                echo ""
            fi
            PHASE="$CANDIDATE_PHASE"
            PHASE_LEVEL=$CANDIDATE_LEVEL
            LAST_PHASE="$PHASE"
        else
            PHASE="$LAST_PHASE"
        fi

        # Calculate elapsed time
        local ELAPSED=$(( $(date +%s) - START_TIME ))
        local ELAPSED_MIN=$((ELAPSED / 60))
        local ELAPSED_SEC=$((ELAPSED % 60))
        local ELAPSED_STR
        ELAPSED_STR=$(printf "%d:%02d" $ELAPSED_MIN $ELAPSED_SEC)

        # Print phase with elapsed time and optional detail (overwrites current line)
        if [ -n "$DETAIL" ]; then
            printf "\r  ⏳ [%s] %s... %s   " "$ELAPSED_STR" "$PHASE" "$DETAIL"
        else
            printf "\r  ⏳ [%s] %s...           " "$ELAPSED_STR" "$PHASE"
        fi

        # ── Stall detection ──────────────────────────────────────────────────
        # Fingerprint forward progress: network I/O + disk I/O (download), GPU memory
        # (weight load), and a checksum of the latest log lines (compile/warmup). Any
        # change means we're making progress, so reset the stall clock. If NOTHING
        # changes for STALL_SECONDS, the load is hung — give up. This lets huge cold
        # downloads take as long as they need while still catching real deadlocks.
        local _io _gpu _logsig _fp
        _io=$(docker stats --no-stream --format '{{.NetIO}}|{{.BlockIO}}' "$CONTAINER_NAME" 2>/dev/null)
        _gpu=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | paste -sd+ - 2>/dev/null)
        [ -z "$_gpu" ] && _gpu=$(rocm-smi --showmeminfo vram 2>/dev/null | grep -iE 'used' | grep -oE '[0-9]+' | paste -sd+ - 2>/dev/null)
        _logsig=$(docker logs --tail 20 "$CONTAINER_NAME" 2>&1 | cksum 2>/dev/null)
        _fp="${_io}|${_gpu}|${_logsig}"
        if [ "$_fp" != "$LAST_FP" ]; then
            LAST_FP="$_fp"
            LAST_PROGRESS_TIME=$(date +%s)
        elif [ $(( $(date +%s) - LAST_PROGRESS_TIME )) -ge "$STALL_SECONDS" ]; then
            echo ""
            echo -e "${RED}✗ vLLM made no progress for ${STALL_SECONDS}s (no I/O, GPU, or log activity) — treating as hung.${NC}"
            local ERR
            ERR=$(docker logs "$CONTAINER_NAME" 2>&1 | grep -iE "error|cuda|nccl|out of memory|timeout|deadlock" | tail -4)
            [ -n "$ERR" ] && { echo -e "${RED}  Recent log signals:${NC}"; echo "$ERR" | while IFS= read -r l; do echo -e "  ${YELLOW}${l}${NC}"; done; }
            break
        fi

        # ── Fatal-error fast path ────────────────────────────────────────────
        # Some failures leave the engine dead while the container stays Up (e.g.
        # Intel Level Zero DEVICE_LOST during memory profiling, or a worker
        # RuntimeError with the parent process still alive) — no restart, so the
        # crash-loop detector never fires, and waiting out the full stall window
        # costs STALL_SECONDS per model. A terminal signature in the log tail
        # combined with ≥30s of zero progress is decisive much sooner. The 30s
        # gate avoids false positives while a restarting engine still shows the
        # previous attempt's trace in its tail (an actively rebooting engine
        # changes the logs, which resets LAST_PROGRESS_TIME above).
        if [ $(( $(date +%s) - LAST_PROGRESS_TIME )) -ge 30 ]; then
            local FATAL
            FATAL=$(docker logs --tail 40 "$CONTAINER_NAME" 2>&1 | grep -m1 -E \
                'UR_RESULT_ERROR_DEVICE_LOST|EngineCore failed to start|Failed to infer device type|RuntimeError: Worker failed|torch\.OutOfMemoryError|CUDA error: no kernel image|driver/library version mismatch')
            if [ -n "$FATAL" ]; then
                echo ""
                echo -e "${RED}✗ Inference engine hit a fatal error (container up, engine dead):${NC}"
                echo -e "  ${YELLOW}${FATAL}${NC}"
                echo "  Troubleshooting:"
                echo -e "  ${BLUE}docker compose logs inference${NC}  - View full logs"
                echo -e "  DEVICE_LOST usually means the GPU/driver crashed — check ${BLUE}sudo dmesg | tail${NC};"
                echo -e "  a reboot may be needed before the GPU responds again."
                break
            fi
        fi

        sleep 3
    done
    echo ""
    # Restore previous shell options
    eval "$OLD_OPTS"
    return $RESULT
}
