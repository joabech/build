# Fine-tune a chat model and export a quantized GGUF. One pipeline for
# macOS and Linux: build/finetune.py does the work, running in the build
# git's own venv ($(BUILD_VENV), from build/requirements.txt via
# 'cim install pip'). Pulled in by sdk.yml's makefile_include: (no git is
# named "finetune", so it isn't auto-discovered).

FINETUNE = WORKSPACE="$(WORKSPACE)" LLAMA_CPP_DIR="$(LLAMA_CPP_DIR)" \
	LLAMA_QUANTIZE_BIN="$(LLAMA_QUANTIZE_BIN)" QUANT="$(QUANT)" \
	VAL_SPLIT="$(VAL_SPLIT)" SEED="$(SEED)" \
	$(BUILD_VENV)/bin/python3 $(WORKSPACE)/build/finetune.py

COMMON_ARGS = $(if $(DRY_RUN),--dry-run) $(if $(KEEP),--keep-intermediates)

FINETUNE_PROFILES := test low medium high
FINETUNE_TARGETS  := $(addprefix finetune-,$(FINETUNE_PROFILES))

.PHONY: $(FINETUNE_TARGETS) finetune-gguf finetune-list finetune-models \
        finetune-help finetune-clean finetune-check-venv

finetune-check-venv:
	@test -x "$(BUILD_VENV)/bin/python3" || \
	  { echo "error: $(BUILD_VENV) missing -- run 'cim install pip' first" >&2; exit 1; }

$(FINETUNE_TARGETS): finetune-%: finetune-check-venv
	@test -n "$(MODEL)" || { echo "error: MODEL=<local-path-or-hf-repo> is required (see 'make finetune-models')" >&2; exit 1; }
	@test -n "$(DATASET)$(DATA)" || { echo "error: set DATASET=<raw.jsonl> or DATA=<split-dir>" >&2; exit 1; }
	$(FINETUNE) train $* --model "$(MODEL)" \
	  $(if $(DATASET),--dataset "$(DATASET)",--data "$(DATA)") \
	  $(if $(ADAPTER_PATH),--adapter-path "$(ADAPTER_PATH)") \
	  $(if $(ITERS),--iters $(ITERS)) \
	  $(if $(GGUF),--gguf) $(if $(NO_GGUF),--no-gguf) \
	  $(COMMON_ARGS) $(FINETUNE_ARGS)

# Re-export a GGUF from a finished session without retraining.
# ADAPTER=<N> picks from 'make finetune-list'; ADAPTER_PATH=<dir> skips the
# list; with neither, it asks.
finetune-gguf: finetune-check-venv
	$(FINETUNE) export \
	  $(if $(ADAPTER_PATH),--adapter-path "$(ADAPTER_PATH)") \
	  $(if $(ADAPTER),--pick $(ADAPTER)) \
	  $(if $(MODEL),--model "$(MODEL)") \
	  $(COMMON_ARGS)

finetune-list: finetune-check-venv
	@$(FINETUNE) list

# Never downloads anything: a curated list plus what's already cached.
finetune-models:
	@echo "Models are never auto-downloaded by this target. Pick one and pass it as MODEL=."
	@echo ""
	@echo "Curated candidates (smaller trains faster, especially without a GPU):"
	@echo "  HuggingFaceTB/SmolLM2-135M-Instruct"
	@echo "  HuggingFaceTB/SmolLM2-360M-Instruct"
	@echo "  Qwen/Qwen2.5-0.5B-Instruct"
	@echo "  Qwen/Qwen2.5-1.5B-Instruct"
	@echo "  unsloth/Qwen3.5-4B                 (~25 GB RAM to train on CPU)"
	@echo "  meta-llama/Llama-3.2-3B-Instruct   (gated -- 'hf auth login' first)"
	@echo ""
	@echo "Already cached in ~/.cache/huggingface/hub:"
	@ls -1 "$$HOME/.cache/huggingface/hub" 2>/dev/null | grep '^models--' \
	  | sed 's/^models--//; s/--/\//g; s/^/  /' | grep . || echo "  (none found)"

finetune-clean:
	rm -rf $(WORKSPACE)/data $(WORKSPACE)/adapters $(WORKSPACE)/fused $(WORKSPACE)/gguf

finetune-help:
	@echo "================================================================================"
	@echo "finetune: LoRA/DoRA fine-tune a chat model and export a quantized GGUF"
	@echo "Same pipeline on macOS and Linux; trains on CUDA, Apple GPU (MPS) or CPU."
	@echo ""
	@echo "  make finetune-<profile> MODEL=<path-or-hf-repo> DATASET=<chatml.jsonl>"
	@echo ""
	@echo "Profiles (build/profiles/<profile>.yaml):"
	@echo "  test     10 steps, sanity check only, no GGUF by default"
	@echo "  low      LoRA r8,  1 epoch   -- fast"
	@echo "  medium   LoRA r16, 3 epochs  -- balanced"
	@echo "  high     DoRA r32 on all linear layers, 3 epochs -- best, slowest"
	@echo ""
	@echo "Other targets:"
	@echo "  finetune-gguf     GGUF from a finished session (ADAPTER=<N> or ADAPTER_PATH=<dir>)"
	@echo "  finetune-list     list finished sessions under adapters/"
	@echo "  finetune-models   model candidates + what's cached locally"
	@echo "  finetune-clean    remove data/ adapters/ fused/ gguf/"
	@echo ""
	@echo "Optional: DATA=<split-dir> (instead of DATASET)  ITERS=<steps>  ADAPTER_PATH=<dir>"
	@echo "          GGUF=1 / NO_GGUF=1  KEEP=1 (keep f16/merged)  DRY_RUN=1"
	@echo "          FINETUNE_ARGS='--override sft.learning_rate=3e-5'"
	@echo "Variables: QUANT=$(QUANT)  VAL_SPLIT=$(VAL_SPLIT)  SEED=$(SEED)"
	@echo ""
	@$(MAKE) --no-print-directory finetune-models
