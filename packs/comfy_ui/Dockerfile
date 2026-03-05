# Base Image: NVIDIA CUDA Runtime (Ubuntu 24.04 base)
# CUDA 12.8 is the first version with native Blackwell (sm_120 / RTX 5090) support
# Also supports Ada (RTX 4090) and older architectures
ARG CUDA_VERSION=12.8.0
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu24.04

# PyTorch index URL (cu128 supports both Ada and Blackwell natively)
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu128

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
# - python3.11: ComfyUI recommended
# - git, wget: For cloning managers/models
# - libgl1, libglib2.0-0: OpenCV requirements
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Create standard user
RUN groupadd -r puget-app-pack && useradd -r -g puget-app-pack -m -d /home/puget-app-pack -s /bin/bash puget-app-pack

# Set up Workspace
WORKDIR /home/puget-app-pack/app

# Clone ComfyUI (Release branch/standard)
RUN git clone https://github.com/comfyanonymous/ComfyUI.git .

# Create and activate virtual environment (required for Ubuntu 24.04 / PEP 668)
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python Requirements
RUN pip install --no-cache-dir torch torchvision torchaudio --index-url ${TORCH_INDEX_URL}
RUN pip install --no-cache-dir -r requirements.txt

# Install 3D node dependencies (fixes nodes_load_3d.py import errors)
RUN pip install --no-cache-dir trimesh pygltflib numpy-stl

# Ensure standard data directories exist for volume mounting
# Using -p for idempotent creation (some may exist from git clone)
RUN mkdir -p models output input temp custom_nodes

# Fix permissions
RUN chown -R puget-app-pack:puget-app-pack /home/puget-app-pack

USER puget-app-pack

# Expose standard port
EXPOSE 8188

# Launch
CMD ["python3", "main.py", "--listen", "0.0.0.0"]
