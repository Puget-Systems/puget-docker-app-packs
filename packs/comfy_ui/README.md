# ComfyUI Pack

GPU-accelerated generative AI workstation for image and video synthesis.

## Components

1.  **ComfyUI**: Node-based workflow editor for Stable Diffusion, Flux, and other diffusion models.
2.  **ComfyUI Manager**: Install custom nodes and models directly from the UI.

## Quick Start

1.  Start the stack:
    ```bash
    docker compose up -d
    ```

2.  Access the UI: [http://localhost:8188](http://localhost:8188)

## Included Model Stacks

During installation, you can select a pre-configured model stack:

| Stack | Model | Size | Best For |
|---|---|---|---|
| Pro Image | **Flux.1 Schnell** | ~12 GB | State-of-the-art image generation |
| Pro Video | **LTX-Video 2B** (v0.9.5) | ~4 GB | Open-source video generation |
| Standard | **SDXL Base 1.0** | ~6 GB | Reliable, broad compatibility |
| Skip | None | — | Download your own models |

## Persistence

All data is volume-mounted to your host for easy access:

```text
./models/          → Model checkpoints, VAEs, LoRAs
./output/          → Generated images and videos
./input/           → Input images for workflows
./custom_nodes/    → Installed ComfyUI extensions
```

## Adding Models

Drop `.safetensors` or `.ckpt` files into the appropriate subdirectory of `./models/`:

```text
models/
├── checkpoints/   → Base models (SD, SDXL, Flux)
├── vae/           → VAE models
├── loras/         → LoRA adapters
├── controlnet/    → ControlNet models
└── clip/          → CLIP models
```

Restart the container or refresh the UI to pick up new models.

## GPU Support

| GPU | Architecture | Status |
|---|---|---|
| RTX 4090 / A6000 | Ada (sm_89) | ✅ Full support |
| RTX 5090 / PRO 6000 | Blackwell (sm_120) | ✅ Full support |

The Dockerfile uses CUDA 12.6, which supports both Ada and Blackwell architectures.
