#!/usr/bin/env python3
"""Merge Puget model entries into ComfyUI Manager's model-list.json.

Adds any models tagged with "puget": true from puget-models.json into
Manager's model-list.json, replacing any existing Puget entries (allows
updates). Safe to run repeatedly — idempotent.

Usage: python3 merge_puget_models.py <puget-models.json> <model-list.json>
"""
import json
import sys
import os

def merge(puget_path, manager_path):
    if not os.path.exists(puget_path):
        print(f"  ⚠ {puget_path} not found, skipping model merge.")
        return False
    if not os.path.exists(manager_path):
        print(f"  ⚠ {manager_path} not found, skipping model merge.")
        return False

    with open(puget_path, 'r') as f:
        puget_data = json.load(f)
    with open(manager_path, 'r') as f:
        manager_data = json.load(f)

    puget_models = puget_data.get('models', [])
    if not puget_models:
        return False

    # Remove any existing Puget-tagged entries (allows clean updates)
    existing = manager_data.get('models', [])
    cleaned = [m for m in existing if not m.get('puget')]

    # Append our models
    cleaned.extend(puget_models)
    manager_data['models'] = cleaned

    with open(manager_path, 'w') as f:
        json.dump(manager_data, f, indent=2)

    print(f"  ✓ Added {len(puget_models)} Puget template models to Manager.")
    return True

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <puget-models.json> <model-list.json>")
        sys.exit(1)
    merge(sys.argv[1], sys.argv[2])
