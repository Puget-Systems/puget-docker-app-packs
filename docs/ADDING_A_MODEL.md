# Adding a New Model to the App Packs

When adding a new model to the Puget Docker App Packs, follow this checklist.
Models must be added to **both** the shared library and all callers.

---

## vLLM (Team LLM)

### 1. Model Menu Entry
**File:** `scripts/lib/vllm_model_select.sh` → `show_vllm_model_menu()`

- [ ] Add numbered menu entry with model name, size, and VRAM requirement
- [ ] Add VRAM-gated display (green if fits, red if too large)
- [ ] Increment `MENU_MAX` at the end of the function
- [ ] Move "Custom" and "Skip" entries down to maintain numbering

### 2. Model Configuration
**File:** `scripts/lib/vllm_model_select.sh` → `select_vllm_model()`

- [ ] Add `case` entry with:
  - [ ] `VLLM_MODEL_ID` — Full HuggingFace model ID
  - [ ] `VLLM_MODEL_SIZE_GB` — Approximate weight size in GB
  - [ ] `VLLM_TOOL_CALL_ARGS` — Tool call parser (`hermes`, `gemma4`, `qwen3_coder`)
  - [ ] `VLLM_REASONING_ARGS` — If model supports thinking mode (`--reasoning-parser qwen3`, `--reasoning-parser gemma4`)
  - [ ] `VLLM_EXTRA_ARGS` — Special flags (`--language-model-only`, `--enforce-eager`, etc.)
  - [ ] `VLLM_DTYPE` — Data type (`auto` default, `float16` for AWQ models)
  - [ ] `VLLM_IMAGE` — Set to `"${NIGHTLY_PREFIX}"` if model needs nightly vLLM
- [ ] Add VRAM gate: `if [ "$TOTAL_VRAM" -lt <min_gb> ]; then ... return 1; fi`

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

- [ ] Run `bash -n scripts/lib/vllm_model_select.sh` (syntax check)
- [ ] Run `bash scripts/update_checksum.sh` (update integrity manifest)
- [ ] Test on target hardware or document VRAM requirement
- [ ] Commit with descriptive message

---

## Ollama (Personal LLM)

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

### 3. Callers
- [ ] `install.sh` — personal_llm section (dynamic `MENU_MAX`, no update needed)
- [ ] `packs/personal_llm/init.sh` (dynamic `MENU_MAX`, no update needed)

### 4. Finalize
- [ ] Run `bash -n scripts/lib/ollama_model_select.sh`
- [ ] Run `bash scripts/update_checksum.sh`
- [ ] Commit

---

## Common Gotchas

| Issue | Symptom | Prevention |
|-------|---------|------------|
| Forgot `VLLM_IMAGE="${NIGHTLY_PREFIX}"` | `model type not recognized` at container startup | Check if model arch is in vLLM stable |
| Forgot to update `MENU_MAX` | Prompt says `[1-N]` but there are N+1 options | `MENU_MAX` is set inside the menu function |
| Wrong tool call parser | Tool calls silently fail | Check model's HF README for supported parsers |
| VRAM gate too tight/loose | Model OOMs or unnecessarily blocked | Test: model_size * 1.1 is a safe gate threshold |
| Stale `checksums.md5` | Integrity check fails on customer machines | Pre-commit hook auto-updates (see `.githooks/`) |
