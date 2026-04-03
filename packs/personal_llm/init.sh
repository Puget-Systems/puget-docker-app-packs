#!/bin/bash
echo "Initializing Office Inference..."

# --- Cache Proxy Status ---
if [ -f .env ]; then
    source .env 2>/dev/null
fi

if [ -n "$CACHE_PROXY" ]; then
    echo -e "\033[0;32m✓ Cache Proxy: $CACHE_PROXY\033[0m"
else
    echo -e "\033[1;33m⚠ No cache proxy configured (downloads go direct).\033[0m"
    echo "  To enable, add CACHE_PROXY=http://<ip>:3128 to .env"
fi
echo ""

echo "Select a model to download:"
echo "  1) Qwen 3 (8B)           - Fast, Low VRAM (~5 GB)"
echo "  2) Qwen 3 (32B)          - Best Quality, Single GPU (~20 GB) [Recommended]"
echo "  3) DeepSeek R1 (70B)     - Flagship Reasoning, Dual GPU (~42 GB)"
echo "  4) Llama 4 Scout         - Multimodal (text+image), Dual GPU (~63 GB)"
echo "  5) Nemotron 3 Nano (30B) - NVIDIA MoE Reasoning, Single GPU (~24 GB)"
echo "  6) Nemotron 3 Super      - NVIDIA Flagship MoE, Multi-GPU (~96 GB)"
echo "  7) Exit"
echo ""
read -p "Select [1-7]: " CHOICE

TAG=""
case $CHOICE in
    1) TAG="qwen3:8b" ;;
    2) TAG="qwen3:32b" ;;
    3) TAG="deepseek-r1:70b" ;;
    4) TAG="llama4:scout" ;;
    5) TAG="nemotron-3-nano:30b" ;;
    6) TAG="nemotron-3-super" ;;
    *) echo "Exiting."; exit 0 ;;
esac

echo "Pulling $TAG... (this may take a while for larger models)"

# Wait for Ollama server to be ready
echo "Waiting for Ollama server to be ready..."
for i in $(seq 1 30); do
    if docker compose exec inference ollama list &>/dev/null; then
        echo "✓ Ollama server is ready."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "✗ Ollama server did not become ready in time."
        echo "  Check: docker compose logs inference"
        exit 1
    fi
    sleep 1
done

docker compose exec inference ollama pull "$TAG"

echo ""
echo "Model ready!"
echo "Access the Chat UI at: http://localhost:3000"
echo "Select '$TAG' from the dropdown at the top."
