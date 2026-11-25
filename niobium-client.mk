################################################################################
# niobium-client
#
# niobium-fhetch, openfhe, and json are checked out standalone here (not as
# git submodules) so cim can cache/update them independently. Wired into
# niobium-client via its own OPENFHE_DIR / NIOBIUM_CLIENT_FHETCH_DIR /
# JSON_INCLUDE_DIR overrides.
################################################################################

export PATH := $(FETCH_BY_SIMILARITY_SUBMISSION_VENV)/bin:$(PATH)

# niobium-fhetch is checked out standalone (NIOBIUM_FHETCH_DIR), not under
# niobium-client/vendor/, so point dsl_fhe at the real fhetch_driver path.
export NBCC_FHETCH_DRIVER := $(NIOBIUM_FHETCH_DIR)/build/tests/fhetch_driver/fhetch_driver

.PHONY: niobium-client-build niobium-client-release niobium-client-vendor-links \
	niobium-client-fhetch-driver niobium-client-dsl-examples \
	niobium-client-test niobium-client-clean niobium-client-help

# Split into stages so any one of them can be re-run on its own (e.g.
# `make niobium-client-fhetch-driver`) instead of always redoing everything.
niobium-client-build: niobium-client-dsl-examples

# -j1: niobium-client's own `release` target only works if its steps run in
# the order written (build client before OpenFHE is ready otherwise). Under
# -j, make is free to interleave them. -j1 here just forces that ordering;
# the actual compiling still runs at full parallelism via its own
# `cmake --build -j`.
niobium-client-release:
	$(MAKE) -j1 -C $(NIOBIUM_CLIENT_DIR) release \
		OPENFHE_DIR=$(OPENFHE_DIR) \
		NIOBIUM_CLIENT_FHETCH_DIR=$(NIOBIUM_FHETCH_DIR) \
		JSON_INCLUDE_DIR=$(JSON_DIR)/single_include

# dsl_fhe expects niobium-fhetch under niobium-client/vendor/, but we build
# it standalone instead - symlink it into the paths dsl_fhe expects.
niobium-client-vendor-links: niobium-client-release
	mkdir -p $(NIOBIUM_CLIENT_DIR)/build/vendor
	ln -sfn $(NIOBIUM_FHETCH_DIR)/include $(NIOBIUM_CLIENT_DIR)/vendor/niobium-fhetch/include
	ln -sfn $(NIOBIUM_CLIENT_DIR)/build/_deps/niobium-fhetch-build $(NIOBIUM_CLIENT_DIR)/build/vendor/niobium-fhetch

# fhetch_driver needs NIOBIUM_FHETCH_WITH_TESTS=ON, which niobium-client's
# build never sets (and turning it on there collides with its own examples).
# So build it from the standalone niobium-fhetch checkout instead.
# WITH_EXAMPLES=ON also builds simple_fhetch for niobium-client-test-simple-fhetch.
niobium-client-fhetch-driver: niobium-client-vendor-links
	cmake -S $(NIOBIUM_FHETCH_DIR) -B $(NIOBIUM_FHETCH_DIR)/build \
		-DCMAKE_BUILD_TYPE=Release \
		-DOPENFHE_INSTALL_DIR=$(NIOBIUM_CLIENT_DIR)/vendor/lib/openfhe \
		-DJSON_INCLUDE_DIR=$(JSON_DIR)/single_include \
		-DNIOBIUM_FHETCH_WITH_TESTS=ON \
		-DNIOBIUM_FHETCH_WITH_EXAMPLES=ON
	$(MAKE) -C $(NIOBIUM_FHETCH_DIR)/build fhetch_driver simple_fhetch

# -j1: dsl_fhe's `examples` target builds 7 examples, and each one runs its
# own full-core `make -j` internally. Without -j1 here, several examples can
# start at once and multiply into 50-100 parallel compiles, which OOMs the
# machine. -j1 just makes the 7 examples build one at a time; each is still
# fully parallel inside itself, so we don't lose real speed.
niobium-client-dsl-examples: niobium-client-fhetch-driver
	$(MAKE) -j1 -C $(NIOBIUM_CLIENT_DIR)/dsl_fhe examples

# Runs only the simple_ops example (all 13 ops). Use this to test that one
# example without the rest of sdk-test: `make niobium-client-test-simple-ops`.
.PHONY: niobium-client-test-simple-ops
niobium-client-test-simple-ops:
	$(MAKE) -j1 -C $(NIOBIUM_CLIENT_DIR) test-simple-ops-release \
		OPENFHE_DIR=$(OPENFHE_DIR) \
		NIOBIUM_CLIENT_FHETCH_DIR=$(NIOBIUM_FHETCH_DIR) \
		JSON_INCLUDE_DIR=$(JSON_DIR)/single_include

# Stand-alone targets for the other examples. Not part of niobium-client-test.
.PHONY: niobium-client-test-mult niobium-client-test-bootstrap \
	niobium-client-test-plaintext-add niobium-client-test-auto

niobium-client-test-mult:
	$(MAKE) -j1 -C $(NIOBIUM_CLIENT_DIR) test-mult-release \
		OPENFHE_DIR=$(OPENFHE_DIR) \
		NIOBIUM_CLIENT_FHETCH_DIR=$(NIOBIUM_FHETCH_DIR) \
		JSON_INCLUDE_DIR=$(JSON_DIR)/single_include

niobium-client-test-bootstrap:
	$(MAKE) -j1 -C $(NIOBIUM_CLIENT_DIR) test-bootstrap-release \
		OPENFHE_DIR=$(OPENFHE_DIR) \
		NIOBIUM_CLIENT_FHETCH_DIR=$(NIOBIUM_FHETCH_DIR) \
		JSON_INCLUDE_DIR=$(JSON_DIR)/single_include

niobium-client-test-plaintext-add:
	$(MAKE) -j1 -C $(NIOBIUM_CLIENT_DIR) test-plaintext-add-release \
		OPENFHE_DIR=$(OPENFHE_DIR) \
		NIOBIUM_CLIENT_FHETCH_DIR=$(NIOBIUM_FHETCH_DIR) \
		JSON_INCLUDE_DIR=$(JSON_DIR)/single_include

# auto has two test targets: ciphers and trace-format. Run both.
niobium-client-test-auto:
	$(MAKE) -j1 -C $(NIOBIUM_CLIENT_DIR) test-auto-ciphers-release \
		OPENFHE_DIR=$(OPENFHE_DIR) \
		NIOBIUM_CLIENT_FHETCH_DIR=$(NIOBIUM_FHETCH_DIR) \
		JSON_INCLUDE_DIR=$(JSON_DIR)/single_include
	$(MAKE) -j1 -C $(NIOBIUM_CLIENT_DIR) test-auto-trace-format-release \
		OPENFHE_DIR=$(OPENFHE_DIR) \
		NIOBIUM_CLIENT_FHETCH_DIR=$(NIOBIUM_FHETCH_DIR) \
		JSON_INCLUDE_DIR=$(JSON_DIR)/single_include

# FHETCH-only example from niobium-fhetch (not niobium-client). Writes its trace
# into the current directory, so run it from the niobium-fhetch checkout.
.PHONY: niobium-client-test-simple-fhetch
niobium-client-test-simple-fhetch: niobium-client-fhetch-driver
	cd $(NIOBIUM_FHETCH_DIR) && \
		rm -rf simple_fhetch_example_simple && \
		build/examples/simple_fhetch --no-ring-dim-check

niobium-client-test: niobium-client-test-simple-ops

# clean also references OPENFHE_DIR to remove OpenFHE's own build/dbuild
niobium-client-clean:
	$(MAKE) -C $(NIOBIUM_CLIENT_DIR) clean OPENFHE_DIR=$(OPENFHE_DIR)
	$(MAKE) -C $(NIOBIUM_CLIENT_DIR)/dsl_fhe clean

niobium-client-help:
	@echo "================================================================================"
	@echo "niobium-client (FHE client, examples, and example tests)"
	@echo ""
	@echo "Targets:"
	@echo "  niobium-client-build                build the client, fhetch_driver, and dsl_fhe examples"
	@echo "  niobium-client-release              build niobium-client itself (Release)"
	@echo "  niobium-client-fhetch-driver        build fhetch_driver and simple_fhetch from niobium-fhetch"
	@echo "  niobium-client-test                 run the default test set (simple_ops)"
	@echo "  niobium-client-test-simple-ops      simple_ops example, all 13 ops"
	@echo "  niobium-client-test-mult            mult example: client -> server -> decrypt"
	@echo "  niobium-client-test-bootstrap       bootstrap example: client -> server -> decrypt"
	@echo "  niobium-client-test-plaintext-add   plaintext_add example: client -> server -> decrypt"
	@echo "  niobium-client-test-auto            auto example: ciphers_ops and trace-format"
	@echo "  niobium-client-test-simple-fhetch   simple_fhetch record and replay (niobium-fhetch)"
	@echo "  niobium-client-clean                remove niobium-client and dsl_fhe build output"
	@echo "  niobium-client-help"
	@echo ""
	@echo "Variables (defaults):"
	@echo "  NIOBIUM_CLIENT_DIR=$(NIOBIUM_CLIENT_DIR)"
	@echo "  NIOBIUM_FHETCH_DIR=$(NIOBIUM_FHETCH_DIR)"
	@echo "  OPENFHE_DIR=$(OPENFHE_DIR)"
	@echo "  JSON_DIR=$(JSON_DIR)"
	@echo ""
	@echo "Each niobium-client-test-<example> target runs on its own, without the rest of sdk-test."
	@echo "Example: make niobium-client-test-mult"
