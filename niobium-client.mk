################################################################################
# niobium-client
#
# niobium-fhetch, openfhe, and json are checked out standalone (not under
# niobium-client/vendor/ as git submodules) and wired in via the path
# overrides niobium-client's own Makefile/CMake already expose for exactly
# this purpose: OPENFHE_DIR, NIOBIUM_CLIENT_FHETCH_DIR, JSON_INCLUDE_DIR.
################################################################################

# Route python3 through fetch-by-similarity-submission's venv (already has
# numpy per its requirements.txt) so dsl_fhe's fetch-by-similarity example
# harness, which also needs numpy, picks it up without a second venv.
export PATH := $(FETCH_BY_SIMILARITY_SUBMISSION_VENV)/bin:$(PATH)

# dsl_fhe's Makefile defaults NBCC_FHETCH_DRIVER to a path under
# niobium-client/vendor/niobium-fhetch/build/ - but niobium-fhetch is
# checked out standalone here (NIOBIUM_FHETCH_DIR), so point it there
# instead.
export NBCC_FHETCH_DRIVER := $(NIOBIUM_FHETCH_DIR)/build/tests/fhetch_driver/fhetch_driver

.PHONY: niobium-client-build niobium-client-test niobium-client-clean

# niobium-client's own `release` target (config-release + build-release,
# each in turn fanning out to config-openfhe-release/config-client-release
# and build-openfhe-release) only expresses its internal ordering via
# left-to-right prerequisite lists, not real dependency edges - e.g.
# config-client-release isn't declared to depend on build-openfhe-release
# having installed OpenFHE yet. GNU Make honors that ordering only when run
# serially; under `-j` (which $(MAKE) auto-forwards into this recursive call
# via the jobserver) Make is free to interleave those siblings, so
# config-client-release or build-release can start before OpenFHE is
# actually built and installed. Passing -j1 here disconnects this
# invocation from the inherited jobserver and forces its own orchestration
# back to serial, without losing real build parallelism - the actual
# compiles still run at -j $(NUM_CPUS) via the explicit
# `cmake --build ... -j $(NUM_CPUS)` in build-openfhe(-release)/build(-release).
niobium-client-build:
	$(MAKE) -j1 -C $(NIOBIUM_CLIENT_DIR) release \
		OPENFHE_DIR=$(OPENFHE_DIR) \
		NIOBIUM_CLIENT_FHETCH_DIR=$(NIOBIUM_FHETCH_DIR) \
		JSON_INCLUDE_DIR=$(JSON_DIR)/single_include
	# dsl_fhe's generated CMakeLists.txt (xcomp/codegen.py) hardcodes
	# vendor/-relative paths for niobium-fhetch's headers and built
	# libnbfhetch - it has no NIOBIUM_CLIENT_FHETCH_DIR override of its
	# own. Since that override (above) means niobium-client/vendor/
	# niobium-fhetch stays an empty placeholder and libnbfhetch actually
	# lands under build/_deps/niobium-fhetch-build/, bridge both expected
	# locations to the real ones. dsl_fhe's own Makefile already expects
	# build/vendor/niobium-fhetch to exist this way (see its LD_LIB_PATH).
	mkdir -p $(NIOBIUM_CLIENT_DIR)/build/vendor
	ln -sfn $(NIOBIUM_FHETCH_DIR)/include $(NIOBIUM_CLIENT_DIR)/vendor/niobium-fhetch/include
	ln -sfn $(NIOBIUM_CLIENT_DIR)/build/_deps/niobium-fhetch-build $(NIOBIUM_CLIENT_DIR)/build/vendor/niobium-fhetch
	# fhetch_driver (spawned by libnbfhetch for cooperative/record-once
	# replay - e.g. dsl_fhe's test-simple "replay with NEW inputs" step)
	# is gated behind NIOBIUM_FHETCH_WITH_TESTS, which niobium-client's
	# own build never turns on. Turning it on inside niobium-client's own
	# CMake tree collides with niobium-client's own examples (duplicate
	# target names, e.g. plaintext_add_client) since both get configured
	# together there. Build it from the standalone niobium-fhetch
	# checkout in its own tree instead, reusing the OpenFHE/json already
	# built above.
	cmake -S $(NIOBIUM_FHETCH_DIR) -B $(NIOBIUM_FHETCH_DIR)/build \
		-DCMAKE_BUILD_TYPE=Release \
		-DOPENFHE_INSTALL_DIR=$(NIOBIUM_CLIENT_DIR)/vendor/lib/openfhe \
		-DJSON_INCLUDE_DIR=$(JSON_DIR)/single_include \
		-DNIOBIUM_FHETCH_WITH_TESTS=ON
	$(MAKE) -C $(NIOBIUM_FHETCH_DIR)/build fhetch_driver
	$(MAKE) -C $(NIOBIUM_CLIENT_DIR)/dsl_fhe examples

niobium-client-test:
	$(MAKE) -j1 -C $(NIOBIUM_CLIENT_DIR) test-simple-ops-release \
		OPENFHE_DIR=$(OPENFHE_DIR) \
		NIOBIUM_CLIENT_FHETCH_DIR=$(NIOBIUM_FHETCH_DIR) \
		JSON_INCLUDE_DIR=$(JSON_DIR)/single_include

# clean also references OPENFHE_DIR to remove OpenFHE's own build/dbuild
niobium-client-clean:
	$(MAKE) -C $(NIOBIUM_CLIENT_DIR) clean OPENFHE_DIR=$(OPENFHE_DIR)
	$(MAKE) -C $(NIOBIUM_CLIENT_DIR)/dsl_fhe clean
