# Personal LLM Pack

Local AI assistant for individual use. Easy model management — pull, swap, and chat with any open-source model.

## Components

1.  **The Engine (Ollama)**: Local inference server with GPU acceleration and one-command model management.
2.  **The Interface (Open WebUI)**: ChatGPT-like interface for chatting and RAG (document upload).
3.  **The Brain (AutoGen)**: *Advanced Users*. An agent workflow engine for creating "Swarms of Experts".

## When to Use This Pack

- **Single user** workstation or personal machine
- You want to **browse and swap models** easily (`ollama pull qwen3:32b`)
- Your model fits on a **single GPU** (up to ~90 GB for RTX PRO 6000)

> For multi-user serving or multi-GPU tensor parallelism, see the **Team LLM** pack.

## Quick Start

1.  Start the stack:
    ```bash
    docker compose up -d
    ```

2.  (First Run Only) Initialize a model:
    ```bash
    ./init.sh
    ```
    Or manually: `docker compose exec inference ollama pull qwen3:32b`

3.  Access the Chat UI: [http://localhost:3000](http://localhost:3000)

## Available Models

The `init.sh` wizard offers these pre-configured options:

| # | Model | Ollama Tag | VRAM | Notes |
|---|---|---|---|---|
| 1 | Qwen 3 (8B) | `qwen3:8b` | ~5 GB | Fast, low VRAM |
| 2 | Qwen 3 (32B) | `qwen3:32b` | ~20 GB | Best quality, single GPU |
| 3 | DeepSeek R1 (70B) | `deepseek-r1:70b` | ~42 GB | Flagship reasoning, dual GPU |
| 4 | Llama 4 Scout | `llama4:scout` | ~63 GB | Multimodal (text+image) |
| 5 | Nemotron 3 Nano (30B) | `nemotron-3-nano:30b` | ~24 GB | NVIDIA MoE reasoning |
| 6 | Nemotron 3 Super | `nemotron-3-super` | ~96 GB | NVIDIA flagship MoE |
| 7 | Gemma 4 (31B) | `gemma4:31b` | ~20 GB | Google dense instruct |

All models are quantized (GGUF) for efficient single-GPU inference.

## GPU & Architecture Support

| GPU Family | Architecture | Status |
|---|---|---|
| RTX 4090 / A6000 | Ada (sm_89) | ✅ Full support |
| RTX 5090 / PRO 6000 | Blackwell (sm_120) | ✅ Full support |

Ollama automatically selects the correct CUDA runtime for your GPU.

## Context Window

The default context window is capped at **32K tokens** via `OLLAMA_NUM_CTX` to prevent models with large native context windows (e.g., Gemma 4's 256K) from exhausting system RAM during KV cache allocation.

To override, add to `.env`:

```bash
OLLAMA_NUM_CTX=65536
```

## Changing Models

Pull any model from the [Ollama Library](https://ollama.com/library):

```bash
docker compose exec inference ollama pull gemma4:31b
```

Or run the wizard again:

```bash
./init.sh
```

## Advanced: The "Brain" (AutoGen)

The `brain` container is a headless Python environment pre-loaded with `pyautogen`. It connects to the local Ollama instance via the internal network.

To run the example swarm:

```bash
# Enter the brain container
docker compose exec brain bash

# Run the example
python examples/group_chat.py
```
