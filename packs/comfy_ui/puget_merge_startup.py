"""
Puget Systems — Merge template models into Manager's cached model list.

This startup script runs inside ComfyUI on boot (via Manager's startup-scripts).
It injects Puget's template model entries so users can find and install
template-required models (Z-Image, Flux.2, HiDream, etc.) through Manager.

Runs after Manager initializes, avoiding the remote cache overwrite problem.
"""
import json
import os
import time
import threading

def find_puget_models():
    """Find puget-models.json relative to the ComfyUI root."""
    candidates = [
        os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))), "puget-models.json"),
        "/home/puget-app-pack/app/puget-models.json",
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
    return None


def find_manager_model_list():
    """Find Manager's model-list.json."""
    candidates = [
        os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "model-list.json"),
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
    return None


def do_merge():
    """Delayed merge — waits for Manager to finish its cache update."""
    time.sleep(15)  # Wait for Manager to finish downloading its cache

    puget_path = find_puget_models()
    manager_path = find_manager_model_list()

    if not puget_path:
        return
    if not manager_path:
        return

    try:
        with open(puget_path, 'r') as f:
            puget_data = json.load(f)
        with open(manager_path, 'r') as f:
            manager_data = json.load(f)

        puget_models = puget_data.get('models', [])
        if not puget_models:
            return

        # Remove existing Puget entries, add fresh ones
        existing = manager_data.get('models', [])
        cleaned = [m for m in existing if not m.get('puget')]
        cleaned.extend(puget_models)
        manager_data['models'] = cleaned

        with open(manager_path, 'w') as f:
            json.dump(manager_data, f, indent=2)

        print(f"[Puget] Merged {len(puget_models)} template models into Manager.")
    except Exception as e:
        print(f"[Puget] Model merge failed: {e}")


# Run in background thread so we don't block ComfyUI startup
thread = threading.Thread(target=do_merge, daemon=True)
thread.start()
