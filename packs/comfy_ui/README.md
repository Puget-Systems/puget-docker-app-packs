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

3.  (Optional) Run the model selector to download a starter model:
    ```bash
    ./init.sh
    ```

## Model Stacks

During installation (or via `./init.sh`), select from curated model tiers:

### Pro Image — Extreme detail, production quality
Use for: concept art, start/end frames for video gen, pre-viz VFX scenes.
GPU recommendation: Blackwell PRO 5000/6000 series or dual 5090.

| Model | Size | Notes |
|---|---|---|
| **Flux.2 Dev (FP8)** | ~12 GB | Flagship image generation (gated) |
| **Flux.1 Dev** | ~24 GB | Previous gen flagship (gated) |
| **HiDream I1 Dev (FP8)** | ~12 GB | 17B parameter, high detail |

### Standard Image — Fast iterations, good quality
Use for: storyboards, moodboards, thumbnails, infographics, plates for animation.

| Model | Size | Notes |
|---|---|---|
| **Flux.2 Klein (4B)** | ~8 GB | 1-2s generations on 50-series ⭐ |
| **Flux.1 Schnell** | ~12 GB | Fast Flux generation |
| **SDXL Turbo (FP16)** | ~3 GB | Fastest SDXL, real-time |
| **SD 3.5 Medium** | ~5 GB | Latest SD3 architecture |

### Pro Video

| Model | Size | Notes |
|---|---|---|
| **LTX-Video 2B** | ~4 GB | Best open-source video model |

### Additional Models (via ComfyUI Manager/Templates)

Many more models are available inside ComfyUI through the Manager extension and built-in templates:
Anima Anime, Capybara, Kandinsky, NetaYume Lumina, NewBie Exp, OmniGen2, Ovis, Qwen Image, Qwen Image 2512, Z-Image, and more.

## Supported Workflows

ComfyUI templates support a range of generative workflows:

| Workflow | Description |
|---|---|
| **Text to Image** | Generate images from text prompts |
| **Image to Image** | Transform sketches, rough drawings, or photos |
| **Image Editing** | Consistency edits, relighting, depth adjustment |
| **Outpainting** | Extend images (like Photoshop generative extend) |
| **Upscaling** | Enhance resolution (Z-Image Turbo 2K, Image Upscale) |

## Persistence

All data is volume-mounted to your host for easy access:

```text
./models/          → Model checkpoints, VAEs, LoRAs, CLIP, ControlNet
./output/          → Generated images and videos
./input/           → Input images for workflows
./custom_nodes/    → Installed ComfyUI extensions
```

## Adding Models

Drop `.safetensors` or `.ckpt` files into the appropriate subdirectory of `./models/`:

```text
models/
├── checkpoints/       → Base models (SD, SDXL, Flux)
├── diffusion_models/  → Diffusion-only weights (HiDream, etc.)
├── vae/               → VAE models
├── loras/             → LoRA adapters
├── controlnet/        → ControlNet models
├── clip/              → CLIP models
└── text_encoders/     → Text encoder weights
```

Restart the container or refresh the UI to pick up new models.

## GPU Support

| GPU | Architecture | Status |
|---|---|---|
| RTX 4090 / A6000 | Ada (sm_89) | ✅ Full support |
| RTX 5090 / PRO 6000 | Blackwell (sm_120) | ✅ Full support |

The Dockerfile uses CUDA 12.6, which supports both Ada and Blackwell architectures.
Build args `CUDA_VERSION` and `TORCH_INDEX_URL` are available for future CUDA 13.0 needs.
