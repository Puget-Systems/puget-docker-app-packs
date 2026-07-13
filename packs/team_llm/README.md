# Team LLM Pack

Production-grade local LLM server for teams, serving an OpenAI-compatible API. NVIDIA/Intel run vLLM (multi-GPU tensor parallelism); AMD runs llama.cpp by default (layer-split GGUF — 2×+ faster than vLLM on RDNA4, where RCCL tensor parallelism is broken) with vLLM FP8 available via `TEAM_AMD_ENGINE=vllm`.

## Components

1.  **The Engine**: vLLM (NVIDIA/Intel) or llama.cpp (AMD default) — high-throughput multi-GPU inference.
2.  **The Interface (Open WebUI)**: ChatGPT-like interface connected via OpenAI API.
3.  **The Brain (AutoGen)**: *Advanced Users*. Agent workflow engine for "Swarms of Experts".

## When to Use This Pack

- **Multiple users** sharing one workstation or server
- You need **multi-GPU inference** (vLLM tensor parallelism; llama.cpp layer split on AMD)
- You're serving a **single model in production** (less model swapping, more throughput)

> For personal use with easy model swapping, see the **Personal LLM** pack.

## Concurrency: vLLM vs llama.cpp (AMD)

The two engines handle multi-user load very differently — this matters when sizing an AMD box:

- **vLLM (NVIDIA/Intel)** auto-scales. PagedAttention serves many simultaneous requests out of one shared KV-cache pool, allocating context on demand — you don't pre-declare how many users to expect.
- **llama.cpp (AMD default)** uses **static slots**. `MAX_CONTEXT` (`-c`) is a fixed KV pool split **evenly** across `--parallel N` slots, so **per-request context = `MAX_CONTEXT` ÷ `LLAMA_PARALLEL`**, and traffic is pre-segmented into those N slots. More slots = more concurrent requests but proportionally **less context each**.

The AMD default is **2 slots** (one active chat + one background task), sized so each request keeps a large context window. To trade context for more concurrency, raise `LLAMA_PARALLEL` in `.env` (e.g. `4` on a dual-GPU box quarters per-request context but serves 4 at once). If your team genuinely needs many-user dynamic concurrency on AMD, the opt-in vLLM FP8 engine (`TEAM_AMD_ENGINE=vllm`) is the auto-scaling path — at lower single-stream throughput.

## Quick Start

1.  Run the setup wizard (detects GPUs, picks a model):
    ```bash
    ./init.sh
    ```

2.  Or configure manually via `.env`:
    ```bash
    MODEL_ID=cyankiwi/Qwen3.6-35B-A3B-AWQ-4bit
    GPU_COUNT=1
    MAX_CONTEXT=131072
    ```

3.  Start the stack:
    ```bash
    docker compose up -d
    ```

4.  Access the Chat UI: [http://localhost:3000](http://localhost:3000)
5.  API endpoint: [http://localhost:8000/v1](http://localhost:8000/v1)

## Available Models

The `init.sh` wizard offers these pre-configured options:

| # | Model | HuggingFace ID | VRAM | Context | Notes |
|---|---|---|---|---|---|
| 1 | **Qwen 3.6 (35B MoE AWQ)** | `cyankiwi/Qwen3.6-35B-A3B-AWQ-4bit` | ~22 GB | 128K | Agentic, thinking preservation 🆕 |
| 2 | Qwen 3.5 (35B MoE AWQ) | `cyankiwi/Qwen3.5-35B-A3B-AWQ-4bit` | ~22 GB | 256K | 3B active params, fast |
| 3 | Qwen 3.5 (122B MoE AWQ) | `cyankiwi/Qwen3.5-122B-A10B-AWQ-4bit` | ~60 GB | 128K | Flagship, 10B active |
| 4 | DeepSeek R1 (70B AWQ) | `Valdemardi/DeepSeek-R1-Distill-Llama-70B-AWQ` | ~38 GB | auto | Reasoning specialist |
| 5 | Nemotron 3 Nano (30B MoE) | `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-NVFP4` | ~20 GB | auto | 3B active, long context (NVFP4) |
| 6 | Nemotron 3 Super (120B MoE) | `nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-NVFP4` | ~60 GB | auto | 12B active, flagship (NVFP4) |
| 7 | Gemma 4 (26B MoE AWQ) | `cyankiwi/gemma-4-26B-A4B-it-AWQ-4bit` | ~18 GB | auto | 3.8B active, 256K context capable |
| 8 | GPT-OSS (20B MoE MXFP4) | `openai/gpt-oss-20b` | ~16 GB | auto | OpenAI open-weight, Apache 2.0 |
| 9 | GPT-OSS (120B MoE MXFP4) | `openai/gpt-oss-120b` | ~80 GB | auto | OpenAI flagship open-weight, Apache 2.0 |
| 10 | Qwen 3.6 (27B NVFP4) | `unsloth/Qwen3.6-27B-NVFP4` | ~14 GB | auto | **Blackwell only.** FP4 tensor cores + MTP speculative decode; ~4–5× the FP16 27B on DGX Spark (22/78/134 tok/s @ conc 1/4/8). Pins vLLM `v0.25.0`. |
| 11 | Custom | User-specified | Varies | — | Any HuggingFace model ID |

> **NVFP4 (entry 11) is Blackwell-specific.** It needs vLLM ≥ 0.25.0 for the FlashInfer-Cutlass FP4 kernel on `sm_120`/`sm_121` (RTX 50-series, DGX Spark/GB10, B200), so the menu pins `vllm/vllm-openai:v0.25.0` instead of the rolling nightly. MTP speculative decoding (lossless) is switched on via `VLLM_ENABLE_MTP=1`, which makes the compose inject `--speculative-config`. On pre-Blackwell GPUs vLLM falls back to a slower Marlin path — use an AWQ entry there instead.

## Thinking Preservation (Qwen 3.6)

Qwen 3.6 introduces **Thinking Preservation**: the model retains its `<think>...</think>` reasoning traces across conversation turns. This means it can reference its own prior reasoning rather than re-deriving conclusions from scratch each turn.

Enabled automatically when you select Qwen 3.6 via `init.sh`. It writes to `.env` as:
```
THINKING_ARGS=--default-chat-template-kwargs '{"preserve_thinking": true}'
```

Benefits:
- **KV cache efficiency** — previously computed reasoning blocks are reused
- **Decision consistency** — model remembers how it reached conclusions across turns
- **Better agentic workflows** — especially useful in multi-step tool-calling sessions

## Context Window Notes

| Model | Native Context | vLLM `MAX_CONTEXT` Set To | Why |
|---|---|---|---|
| Qwen 3.6 35B AWQ | 262K | `262144` on 48GB+ / `131072` on 24GB / `65536` on <24GB | KV cache distributes across GPUs — more GPUs = more context |
| Qwen 3.5 35B AWQ | 256K | auto | Let vLLM size from available VRAM |
| Qwen 3.5 122B AWQ | 256K | `131072` (128K) | Multi-GPU headroom management |

## GPU & Architecture Support

| GPU Family | Architecture | CUDA | Docker Image | Status |
|---|---|---|---|---|
| RTX 4090 / A6000 | Ada (sm_89) | 12.6 | `vllm/vllm-openai:latest` | ✅ Full support |
| RTX 5090 / PRO 6000 | Blackwell (sm_120) | 13.0 | `vllm/vllm-openai:cu130-nightly` | ✅ Full support |

The wizard automatically detects your GPU architecture and selects the correct Docker image.

## Changing Models

Run the wizard again:

```bash
./init.sh
```

Or edit `.env` manually and restart:

```bash
# Edit .env
MODEL_ID=cyankiwi/Qwen3.6-35B-A3B-AWQ-4bit
GPU_COUNT=1
MAX_CONTEXT=131072

# Restart
docker compose down && docker compose up -d
```

## Security Notes

- **`--trust-remote-code`**: The vLLM server runs with `--trust-remote-code`, which allows model
  repositories to include custom Python code that runs during model loading. Only use models from
  trusted sources (official HuggingFace repos, verified publishers).

- **Gemma 4 Custom Build**: Gemma 4 requires a newer version of `transformers` than the stock vLLM
  image ships. You **must** build the custom image before first use:
  ```bash
  docker compose build inference
  ```
  This bakes the correct `transformers` version into the image at build time using `Dockerfile.gemma4`.

## Advanced: The "Brain" (AutoGen)

The brain container connects via OpenAI API to vLLM:

```bash
docker compose exec brain bash
python examples/group_chat.py
```
