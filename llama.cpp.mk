# Build fragment for the llama.cpp git (cmake). Produces a local
# llama-quantize + llama-cli, used by finetune.mk's GGUF export step so
# the target never depends on a Homebrew install or an external
# checkout outside the workspace.

LLAMA_CPP_BUILD_TYPE ?= Release
LLAMA_CPP_BUILD_DIR   ?= $(LLAMA_CPP_DIR)/build

# Metal on macOS (the point of building this on Apple Silicon); plain CPU
# backend everywhere else -- on Linux there's no Foundation framework for
# ggml-metal's CMakeLists to link against, so GGML_METAL must stay off
# there. curl/examples/tests are disabled on both to keep the build fast
# since we only need two binaries.
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
LLAMA_CPP_CMAKE_FLAGS ?= -DGGML_METAL=ON -DLLAMA_CURL=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TESTS=OFF
else
LLAMA_CPP_CMAKE_FLAGS ?= -DGGML_METAL=OFF -DLLAMA_CURL=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TESTS=OFF
endif

LLAMA_QUANTIZE_BIN ?= $(LLAMA_CPP_BUILD_DIR)/bin/llama-quantize
LLAMA_CLI_BIN      ?= $(LLAMA_CPP_BUILD_DIR)/bin/llama-cli

.PHONY: llama.cpp-envsetup llama.cpp-build llama.cpp-clean llama.cpp-help

llama.cpp-envsetup:
	@echo "Running $@ ..."
	@echo "llama.cpp build options (override with make VAR=value):"
	@echo "  LLAMA_CPP_BUILD_TYPE=$(LLAMA_CPP_BUILD_TYPE)"
	@echo "  LLAMA_CPP_BUILD_DIR=$(LLAMA_CPP_BUILD_DIR)"
	@echo "  LLAMA_CPP_CMAKE_FLAGS=$(LLAMA_CPP_CMAKE_FLAGS)"

llama.cpp-build:
	@echo "Running $@ ..."
	cmake -B $(LLAMA_CPP_BUILD_DIR) -S $(LLAMA_CPP_DIR) \
		-DCMAKE_BUILD_TYPE=$(LLAMA_CPP_BUILD_TYPE) \
		$(LLAMA_CPP_CMAKE_FLAGS)
	cmake --build $(LLAMA_CPP_BUILD_DIR) --target llama-quantize llama-cli -j
	@echo "Built: $(LLAMA_QUANTIZE_BIN)"
	@echo "Built: $(LLAMA_CLI_BIN)"

llama.cpp-clean:
	@echo "Running $@ ..."
	@if [ -z "$(LLAMA_CPP_BUILD_DIR)" ]; then \
	  echo "Error: LLAMA_CPP_BUILD_DIR is not set, refusing to rm -rf"; \
	  exit 1; \
	fi
	rm -rf $(LLAMA_CPP_BUILD_DIR)

# GGUF_MODEL points at the quantized GGUF this pipeline produced (see
# finetune.mk / finetune.py: $(WORKSPACE)/gguf/<model>-<adapter>-<quant>.gguf).
# NOT the same thing as MODEL -- MODEL is the HF repo id/path used for
# training and transformers resolves it itself; llama-cli has no such resolution
# and can only load an actual local GGUF file. Defaults to the most
# recently modified *.gguf under $(WORKSPACE)/gguf, override with
# GGUF_MODEL=/path/to/some.gguf to test a specific export.
GGUF_MODEL ?= $(shell ls -t $(WORKSPACE)/gguf/*.gguf 2>/dev/null | head -n1)

llama.cpp-run:
	@echo "Running $@ ..."
	@if [ -z "$(GGUF_MODEL)" ]; then \
	  echo "error: no GGUF_MODEL set and no *.gguf found under $(WORKSPACE)/gguf -- run a finetune-<profile> first, or pass GGUF_MODEL=/path/to/model.gguf" >&2; \
	  exit 1; \
	fi
	@echo "Using GGUF_MODEL=$(GGUF_MODEL)"
	$(LLAMA_CLI_BIN) --model $(GGUF_MODEL) --prompt "What is cim? How do I install it? How do I find targets?" --n_predict 32


################################################################################
# Help target
################################################################################

llama.cpp-help:
	@echo "================================================================================"
	@echo "llama.cpp build (CMake, host tool only -- llama-quantize + llama-cli)"
	@echo ""
	@echo "Targets:"
	@echo "  llama.cpp-envsetup   print the resolved build options (no build)"
	@echo "  llama.cpp-build      configure + build llama-quantize and llama-cli"
	@echo "  llama.cpp-run        smoke-test llama-cli against a GGUF this pipeline exported"
	@echo "  llama.cpp-clean      remove LLAMA_CPP_BUILD_DIR"
	@echo "  llama.cpp-help"
	@echo ""
	@echo "Variables (defaults):"
	@echo "  LLAMA_CPP_BUILD_TYPE=$(LLAMA_CPP_BUILD_TYPE)"
	@echo "  LLAMA_CPP_BUILD_DIR=$(LLAMA_CPP_BUILD_DIR)"
	@echo "  GGUF_MODEL=<path>    (llama.cpp-run only; default: newest \$$(WORKSPACE)/gguf/*.gguf)"
	@echo ""
	@echo "Used by the GGUF export step (see 'make finetune-help')."
