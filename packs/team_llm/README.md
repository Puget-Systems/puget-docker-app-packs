# Team LLM Pack

Production-grade local LLM server for teams. Multi-GPU tensor parallelism with vLLM, serving an OpenAI-compatible API.

## Components

1.  **The Engine (vLLM)**: High-throughput inference with tensor parallelism across multiple GPUs.
2.  **The Interface (Open WebUI)**: ChatGPT-like interface connected via OpenAI API.
3.  **The Brain (AutoGen)**: *Advanced Users*. Agent workflow engine for "Swarms of Experts".

## When to Use This Pack

- **Multiple users** sharing one workstation or server
- You need **multi-GPU tensor parallelism** (vLLM splits computation, not just memory)
- You're serving a **single model in production** (less model swapping, more throughput)

> For personal use with easy model swapping, see the **Personal LLM** pack.

## Quick Start

1.  Run the setup wizard (detects GPUs, picks a model):
    ```bash
    ./init.sh
    ```

2.  Or configure manually via `.env`:
    ```bash
    MODEL_ID=Qwen/Qwen3-32B-FP8
    GPU_COUNT=2
    MAX_CONTEXT=32768
    ```

3.  Start the stack:
    ```bash
    docker compose up -d
    ```

4.  Access the Chat UI: [http://localhost:3000](http://localhost:3000)
5.  API endpoint: [http://localhost:8000/v1](http://localhost:8000/v1)

## Available Models

The `init.sh` wizard offers these pre-configured options:

| # | Model | HuggingFace ID | VRAM | Notes |
|---|---|---|---|---|
| 1 | Qwen 3 (8B) | `Qwen/Qwen3-8B` | ~16 GB | Fast, single GPU |
| 2 | Qwen 3 (32B FP8) | `Qwen/Qwen3-32B-FP8` | ~32 GB | Near-lossless quality |
| 3 | Qwen 3.5 (35B MoE AWQ) | `cyankiwi/Qwen3.5-35B-A3B-AWQ-4bit` | ~22 GB | ⚠️ Coming Soon on Blackwell |
| 4 | Qwen 3.5 (122B MoE AWQ) | `cyankiwi/Qwen3.5-122B-A10B-AWQ-4bit` | ~60 GB | ⚠️ Coming Soon on Blackwell |
| 5 | DeepSeek R1 (70B AWQ) | `Valdemardi/DeepSeek-R1-Distill-Llama-70B-AWQ` | ~38 GB | Reasoning specialist |
| 6 | Nemotron 3 Nano (30B MoE) | `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-NVFP4` | ~20 GB | 3B active, long context (NVFP4) |
| 7 | Nemotron 3 Super (120B MoE) | `nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-NVFP4` | ~60 GB | 12B active, flagship (NVFP4) |
| 8 | Gemma 4 (26B MoE AWQ) | `cyankiwi/gemma-4-26B-A4B-it-AWQ-4bit` | ~18 GB | 3.8B active, 256K context capable |
| 9 | Custom | User-specified | Varies | Any HuggingFace model ID |

> **Blackwell Note**: Qwen 3.5 MoE models use Gated DeltaNet (GDN) attention kernels that are not yet supported on RTX 5090 / Blackwell GPUs (`sm_120`). These options appear as "Coming Soon" on Blackwell hardware. Use Qwen 3 32B FP8 instead — it works flawlessly.

## GPU & Architecture Support

| GPU Family | Architecture | CUDA | Docker Image | Status |
|---|---|---|---|---|
| RTX 4090 / A6000 | Ada (sm_89) | 12.6 | `vllm/vllm-openai:latest` | ✅ Full support |
| RTX 5090 / PRO 6000 | Blackwell (sm_120) | 13.0 | `vllm/vllm-openai:cu130-nightly` | ✅ (except Qwen 3.5 MoE) |

The wizard automatically detects your GPU architecture and selects the correct Docker image.

## Changing Models

Run the wizard again:

```bash
./init.sh
```

Or edit `.env` manually and restart:

```bash
# Edit .env
MODEL_ID=Qwen/Qwen3-32B-FP8
GPU_COUNT=2

# Restart
docker compose down && docker compose up -d
```

## Advanced: The "Brain" (AutoGen)

The brain container connects via OpenAI API to vLLM:

```bash
docker compose exec brain bash
python examples/group_chat.py
```
