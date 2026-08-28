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
	niobium-client-test niobium-client-clean

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
niobium-client-fhetch-driver: niobium-client-vendor-links
	cmake -S $(NIOBIUM_FHETCH_DIR) -B $(NIOBIUM_FHETCH_DIR)/build \
		-DCMAKE_BUILD_TYPE=Release \
		-DOPENFHE_INSTALL_DIR=$(NIOBIUM_CLIENT_DIR)/vendor/lib/openfhe \
		-DJSON_INCLUDE_DIR=$(JSON_DIR)/single_include \
		-DNIOBIUM_FHETCH_WITH_TESTS=ON
	$(MAKE) -C $(NIOBIUM_FHETCH_DIR)/build fhetch_driver

# -j1: dsl_fhe's `examples` target builds 7 examples, and each one runs its
# own full-core `make -j` internally. Without -j1 here, several examples can
# start at once and multiply into 50-100 parallel compiles, which OOMs the
# machine. -j1 just makes the 7 examples build one at a time; each is still
# fully parallel inside itself, so we don't lose real speed.
niobium-client-dsl-examples: niobium-client-fhetch-driver
	$(MAKE) -j1 -C $(NIOBIUM_CLIENT_DIR)/dsl_fhe examples

niobium-client-test:
	$(MAKE) -j1 -C $(NIOBIUM_CLIENT_DIR) test-simple-ops-release \
		OPENFHE_DIR=$(OPENFHE_DIR) \
		NIOBIUM_CLIENT_FHETCH_DIR=$(NIOBIUM_FHETCH_DIR) \
		JSON_INCLUDE_DIR=$(JSON_DIR)/single_include

# clean also references OPENFHE_DIR to remove OpenFHE's own build/dbuild
niobium-client-clean:
	$(MAKE) -C $(NIOBIUM_CLIENT_DIR) clean OPENFHE_DIR=$(OPENFHE_DIR)
	$(MAKE) -C $(NIOBIUM_CLIENT_DIR)/dsl_fhe clean
