#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== System Info ==="
hostname
id

echo -e "\n=== NVIDIA Driver Check ==="
if command -v nvidia-smi &> /dev/null; then
  nvidia-smi --query-gpu=gpu_name,driver_version --format=csv
else
  echo -e "${RED}nvidia-smi not found!${NC}"
fi

echo -e "\n=== Docker Installation ==="
if command -v docker &> /dev/null; then
  docker --version
else
  echo -e "${RED}docker not found!${NC}"
fi

echo -e "\n=== Docker Permissions ==="
if docker info &> /dev/null; then
  echo -e "${GREEN}Docker access OK${NC}"
else
  echo -e "${RED}Cannot access Docker socket. User groups:${NC}"
  groups
fi

echo -e "\n=== Docker Runtime Check ==="
if docker info 2>/dev/null | grep -i "runtime"; then
  echo "Runtimes found:"
  docker info 2>/dev/null | grep -i "runtimes" || true
else
  echo -e "${RED}Could not list runtimes.${NC}"
fi

echo -e "\n=== NVIDIA Container Toolkit Check ==="
if command -v nvidia-ctk &> /dev/null; then
  echo -e "${GREEN}nvidia-ctk found${NC}"
else
  echo -e "${RED}nvidia-ctk not found${NC}"
fi

echo -e "\n=== GPU Container Test ==="
echo "Attempting to run small nvidia/cuda container..."
if docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi &> /dev/null; then
   echo -e "${GREEN}SUCCESS: Container can see GPU.${NC}"
else
   echo -e "${RED}FAILURE: Container could not see GPU or failed to run.${NC}"
   echo "Error details:"
   docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi || true
fi
