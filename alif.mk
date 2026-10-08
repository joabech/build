################################################################################
# Alif Zephyr SDK (west-managed workspace)
#
# $(WORKSPACE) is the cim workspace root; also the west topdir (west.yml's
# self: path: alif means sdk-alif itself lives at $(WORKSPACE)/alif, and
# "west update" fetches zephyr/matter/mcuboot_alif/etc as siblings of it,
# directly under $(WORKSPACE)).
################################################################################

ALIF_BOARD      ?= alif_e7_dk/ae722f80f55d5xx/rtss_he
ALIF_SAMPLE     ?= zephyr/samples/hello_world
ALIF_BUILD_DIR  ?= build/alif

ZEPHYR_SDK_INSTALL_DIR := $(WORKSPACE)/toolchains/zephyr-sdk
ALIF_SE_TOOLS_DIR       := $(WORKSPACE)/toolchains/alif-se-tools

export ZEPHYR_TOOLCHAIN_VARIANT := zephyr

.PHONY: alif-build alif-test alif-clean alif-flash

alif-build:
	@[ -d $(WORKSPACE)/.west ] || { echo "ERROR: west workspace not initialized. Run 'make install-all' first."; exit 1; }
	. $(WORKSPACE)/.venv/bin/activate && \
	  cd $(WORKSPACE) && \
	  ZEPHYR_SDK_INSTALL_DIR=$(ZEPHYR_SDK_INSTALL_DIR) \
	  west build -p always -b $(ALIF_BOARD) -d $(ALIF_BUILD_DIR) $(ALIF_SAMPLE)

alif-test:
	@[ -f $(WORKSPACE)/$(ALIF_BUILD_DIR)/zephyr/zephyr.elf ] || { echo "ERROR: $(ALIF_BUILD_DIR)/zephyr/zephyr.elf not found. Run 'make sdk-build' first."; exit 1; }
	@echo "Alif build artifact exists:"
	@ls -lh $(WORKSPACE)/$(ALIF_BUILD_DIR)/zephyr/zephyr.elf

alif-clean:
	rm -rf $(WORKSPACE)/$(ALIF_BUILD_DIR)

alif-flash:
	@[ -d $(ALIF_SE_TOOLS_DIR) ] || { echo "ERROR: Alif Security Toolkit not found at $(ALIF_SE_TOOLS_DIR). Run 'make install-alif-se-tools-extract' first."; exit 1; }
	. $(WORKSPACE)/.venv/bin/activate && \
	  cd $(WORKSPACE) && \
	  ALIF_SE_TOOLS_DIR=$(ALIF_SE_TOOLS_DIR) \
	  west flash -d $(ALIF_BUILD_DIR)
