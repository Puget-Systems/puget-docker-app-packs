# Puget Custom Workflows

This directory contains custom ComfyUI workflow templates shipped with the Puget App Pack.

## Available Workflows

### Puget Branded Product Shot (Coming Soon)
- **Models**: Z-Image Turbo + Flux.2 Dev FP8 + ControlNet Canny
- **Use case**: Generate hero product images, then inpaint your brand logo using ControlNet edge guidance
- **GPU**: Dual GPU recommended (simultaneous), single GPU supported (sequential)
- **VRAM**: ~14 GB (GPU 0) + ~33 GB (GPU 1) on dual setup

## Adding Workflows

Place `.json` workflow files in this directory. They will appear in ComfyUI's workflow browser automatically.
