#!/bin/bash
# Experiment: compare AMD (RDNA4 / R9700) vLLM image × quant × parallelism on decode tok/s.
#
# Spins up a vLLM OpenAI server for the given (image, model, extra-args), waits for it to
# serve, times a fixed single-stream 256-token generation, prints decode tok/s + load time,
# then tears the container down. Single-stream is the latency metric that tracks the
# "feels slower than my 5090+AWQ" complaint; tweak CONC for throughput runs.
#
# Why this branch exists: stock rocm/vllm has no int4 kernel (FP8 is the floor) and we run
# pipeline-parallel to dodge an RCCL all-reduce error. Community RDNA4 builds add 4-bit
# (AWQ via kyuz0, MXFP4 via tcclaviger) and the community runs tensor-parallel — this script
# measures whether 4-bit + TP actually beats our FP8 + PP baseline on the same box.
#
# Usage:
#   HF_TOKEN=hf_... scripts/experiments/bench_amd_quant_parallel.sh "<label>" "<image>" "<model>" "<extra vllm args>"
#
# Examples (run both, compare the tok/s):
#   bench... fp8-pp2 rocm/vllm:rocm7.13.0_gfx120X-all_ubuntu24.04_py3.13_pytorch_2.10.0_vllm_0.19.1 \
#            Qwen/Qwen3.6-27B "--quantization fp8 --tensor-parallel-size 1 --pipeline-parallel-size 2"
#   bench... awq-tp2 kyuz0/vllm-therock-gfx1201:latest \
#            cyankiwi/Qwen3.6-27B-AWQ-INT4 "--tensor-parallel-size 2"
set -uo pipefail

LABEL="${1:?Usage: bench <label> <image> <model> <extra-args>}"
IMAGE="${2:?image required}"
MODEL="${3:?model required}"
EXTRA="${4:-}"
PORT="${PORT:-8001}"; MAXCTX="${MAXCTX:-65536}"; UTIL="${UTIL:-0.85}"
NAME="bench_${LABEL}"
# Default to the real hub (public models download anonymously). The Olah mirror rate-limits
# anonymous repo-visibility HEADs → 401s; set HF_ENDPOINT explicitly only if you have a valid
# token. For already-cached models, pass HF_HUB_OFFLINE=1 to skip the network check entirely.
HF_ENDPOINT="${HF_ENDPOINT:-https://huggingface.co}"
HF_HUB_OFFLINE="${HF_HUB_OFFLINE:-0}"

docker rm -f "$NAME" >/dev/null 2>&1
echo "[$LABEL] starting"
echo "  image: $IMAGE"
echo "  model: $MODEL"
echo "  args : $EXTRA"
t0=$(date +%s)
docker run -d --name "$NAME" \
  --device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --ipc=host \
  --group-add video --group-add render \
  -p "$PORT:8000" -v team_llm_vllm_cache:/root/.cache/huggingface \
  -e HF_ENDPOINT="$HF_ENDPOINT" -e HF_TOKEN="${HF_TOKEN:-}" -e HF_HUB_OFFLINE="$HF_HUB_OFFLINE" -e NCCL_P2P_DISABLE=1 \
  --entrypoint bash "$IMAGE" -c \
  "python3 -m vllm.entrypoints.openai.api_server --model $MODEL --max-model-len $MAXCTX \
   --gpu-memory-utilization $UTIL --enforce-eager --trust-remote-code --disable-custom-all-reduce $EXTRA" \
  >/dev/null 2>&1

# Wait for the server (first run also downloads weights; int4+TP loads can take 15+ min on
# the newer community vLLM). Bail early if the container dies.
c=000
for _ in $(seq 1 150); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://localhost:$PORT/v1/models" 2>/dev/null || echo 000)
  [ "$c" = 200 ] && break
  if ! docker ps -q --filter "name=^${NAME}$" | grep -q .; then
    echo "[$LABEL] ✗ container exited before serving. Last errors:"
    docker logs "$NAME" 2>&1 | grep -iE 'error|runtime|failed|shape|kernel|divisible|out of memory|ncclComm' | tail -6
    docker rm -f "$NAME" >/dev/null 2>&1
    exit 1
  fi
  sleep 10
done
load=$(( $(date +%s) - t0 ))
if [ "$c" != 200 ]; then
  echo "[$LABEL] ✗ never served (HTTP $c after ${load}s)"
  docker logs "$NAME" 2>&1 | tail -8
  docker rm -f "$NAME" >/dev/null 2>&1
  exit 1
fi
echo "[$LABEL] served in ${load}s — timing a 256-token single-stream generation..."

RESP=$(curl -s "http://localhost:$PORT/v1/chat/completions" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Write a detailed 300-word explanation of how transformer attention works.\"}],\"max_tokens\":256,\"temperature\":0,\"ignore_eos\":true}" \
  -w '\n%{time_total}' --max-time 180)
echo "$RESP" | python3 -c "
import sys,json
data=sys.stdin.read().rsplit(chr(10),1)
body,t=''.join(data[:-1]),float(data[-1])
d=json.loads(body); n=d['usage']['completion_tokens']
print(f'[$LABEL] RESULT: {n} tokens in {t:.2f}s = {n/t:.1f} tok/s   (load ${load}s)')
" || { echo "[$LABEL] could not parse response:"; echo "$RESP" | head -c 400; }

# KEEP=1 leaves the server running for manual testing instead of tearing it down.
if [ "${KEEP:-0}" = 1 ]; then
    echo "[$LABEL] LEFT RUNNING as container '$NAME' → http://localhost:$PORT/v1 (model: $MODEL)"
else
    docker rm -f "$NAME" >/dev/null 2>&1
fi
