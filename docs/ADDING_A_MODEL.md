# Adding a New Model to the App Packs

When adding a new model to the Puget Docker App Packs, follow this checklist.
Models must be added to **both** the shared library and all callers.

> **Vendor menu layout:** `scripts/lib/vllm_model_select.sh` is only a
> **dispatcher** — it lazily sources the real per-vendor menu based on
> `$GPU_VENDOR`. Add vLLM models to the vendor menu file(s) the model applies to:
>
> | Vendor | File | Notes |
> |---|---|---|
> | NVIDIA | `scripts/lib/vllm_menu_nvidia.sh` | Pre-quantized AWQ/NVFP4/MXFP4 repos |
> | AMD (RDNA4) | `scripts/lib/vllm_menu_amd.sh` | Online FP8 (`--quantization fp8`) on FP16 repos — no int4 kernels on ROCm |
> | Intel (XPU) | `scripts/lib/vllm_menu_intel.sh` | FP16 only — no AWQ/GPTQ/bf16 on XPU |
> | AMD Personal (llama.cpp) | `scripts/lib/llama_menu_amd.sh` | GGUF `repo:quant` IDs |
>
> The benchmark suite enumerates all of these through `scripts/list_models.sh`
> (a versioned TSV manifest) — as long as you follow the checklist below, new
> models flow into the bench automatically with no bench-side change.

---

## vLLM (Team LLM)

### 1. Model Menu Entry
**File:** `scripts/lib/vllm_menu_<vendor>.sh` → `show_vllm_model_menu()`

- [ ] Add numbered menu entry with model name, size, and VRAM requirement
- [ ] Add VRAM-gated display (green if fits, red if too large)
- [ ] Increment `MENU_MAX` at the end of the function
- [ ] Move "Custom" and "Skip" entries down to maintain numbering

### 2. Model Configuration
**File:** `scripts/lib/vllm_menu_<vendor>.sh` → `select_vllm_model()`

- [ ] Add `case` entry with:
  - [ ] `VLLM_MODEL_ID` — Full HuggingFace model ID
  - [ ] `VLLM_MODEL_SIZE_GB` — Approximate weight size in GB
  - [ ] `VLLM_TOOL_CALL_ARGS` — Tool call parser (`hermes`, `gemma4`, `qwen3_coder`)
  - [ ] `VLLM_REASONING_ARGS` — If model supports thinking mode (`--reasoning-parser qwen3`, `--reasoning-parser gemma4`)
  - [ ] `VLLM_EXTRA_ARGS` — Special flags (`--language-model-only`, `--enforce-eager`, etc.)
  - [ ] `VLLM_DTYPE` — Data type (`auto` default, `float16` for AWQ models)
  - [ ] `VLLM_IMAGE` — Set to `"vllm/vllm-openai:${NIGHTLY_PREFIX}"` if model needs nightly vLLM
- [ ] Add VRAM gate: `if [ "$TOTAL_VRAM" -lt <min_gb> ]; then ... return 1; fi`
- [ ] **Driver requirement:** `VLLM_MIN_DRIVER` is derived automatically from
      `VLLM_IMAGE` by `min_driver_for_image()` in `scripts/lib/gpu_detect.sh`
      (cu130 → driver ≥580, cu128/cu129 and stable → ≥570). If the image line
      moves to a new CUDA release, update that one mapping — every menu and the
      bench inherit it.

### 3. Container Runtime Check
**File:** `packs/team_llm/docker-compose.yml`

- [ ] Does the model need a newer `transformers` version than what ships in the vLLM image?
  - If yes: add conditional pip upgrade in the `command:` block
- [ ] Does the model need `trust-remote-code`? (Already enabled globally)
- [ ] Does the model need special quantization support? (e.g., NVFP4 → nightly only)

### 4. Caller Updates
These files read `MENU_MAX` dynamically, so **no range update needed** — but verify:

- [ ] `install.sh` — team_llm section still works with the new option number
- [ ] `packs/team_llm/init.sh` — still works with new option number

### 5. Finalize

- [ ] Run `bash -n scripts/lib/vllm_menu_<vendor>.sh` (syntax check)
- [ ] Run `bash scripts/list_models.sh` on a GPU box (or with a stubbed
      `nvidia-smi`) and confirm the new row appears with the expected
      `min_driver` and `image` fields
- [ ] Run `bash scripts/update_checksum.sh` (update integrity manifest)
- [ ] Test on target hardware or document VRAM requirement
- [ ] Commit with descriptive message

---

## Ollama (Personal LLM — NVIDIA/Intel)

### 1. Model Menu Entry
**File:** `scripts/lib/ollama_model_select.sh` → `show_ollama_model_menu()`

- [ ] Add numbered menu entry
- [ ] Add VRAM-gated display
- [ ] Increment `MENU_MAX`
- [ ] Move "Skip" entry down

### 2. Model Configuration
**File:** `scripts/lib/ollama_model_select.sh` → `select_ollama_model()`

- [ ] Add `case` entry: `OLLAMA_MODEL_TAG` and `OLLAMA_MODEL_VRAM_GB`
- [ ] Verify multi-GPU performance warning triggers correctly:
  - Warning fires when `OLLAMA_MODEL_VRAM_GB > VRAM_GB` and `GPU_COUNT > 1`
  - This is the "pipeline parallelism is slow" warning
  - (It is suppressed when `PUGET_NONINTERACTIVE=1` — that's how
    `list_models.sh` and the bench enumerate without blocking on a prompt)

### 3. Callers
- [ ] `install.sh` — personal_llm section (dynamic `MENU_MAX`, no update needed)
- [ ] `packs/personal_llm/init.sh` (dynamic `MENU_MAX`, no update needed)

### 4. Finalize
- [ ] Run `bash -n scripts/lib/ollama_model_select.sh`
- [ ] Run `bash scripts/update_checksum.sh`
- [ ] Commit

---

## llama.cpp (Personal LLM — AMD)

**File:** `scripts/lib/llama_menu_amd.sh` → `show_llama_model_menu()` / `select_llama_model()`

- [ ] Same menu/`MENU_MAX` pattern as above
- [ ] `LLAMA_MODEL_ID` is a HuggingFace GGUF `repo:quant` (e.g. `unsloth/Qwen3.6-27B-GGUF:Q4_K_M`)
- [ ] `LLAMA_MODEL_SIZE_GB` — GGUF footprint (Q4_K_M ≈ 0.6 GB/B params, Q8_0 ≈ 1.06)
- [ ] Context is auto-sized by `recommend_llama_context()` — no per-model value needed

---

## Common Gotchas

| Issue | Symptom | Prevention |
|-------|---------|------------|
| Forgot `VLLM_IMAGE="vllm/vllm-openai:${NIGHTLY_PREFIX}"` | `model type not recognized` at container startup | Check if model arch is in vLLM stable |
| Host driver older than the image's CUDA | `no kernel image is available` / `driver/library version mismatch` in container logs | `min_driver_for_image()` mapping current? The bench gates on it pre-launch |
| Forgot to update `MENU_MAX` | Prompt says `[1-N]` but there are N+1 options | `MENU_MAX` is set inside the menu function |
| Edited the dispatcher instead of the vendor menu | Model never appears on the target vendor | `vllm_model_select.sh` is dispatch-only; menus live in `vllm_menu_<vendor>.sh` |
| Wrong tool call parser | Tool calls silently fail | Check model's HF README for supported parsers |
| VRAM gate too tight/loose | Model OOMs or unnecessarily blocked | Test: model_size * 1.1 is a safe gate threshold |
| Stale `checksums.md5` | Integrity check fails on customer machines | Pre-commit hook auto-updates (see `.githooks/`) |
