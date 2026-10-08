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

ALIF_SE_TOOLS_TAR := $(WORKSPACE)/downloads/app-release-exec-linux-SE_FW_1.112.00_DEV.tar

.PHONY: alif-build alif-test alif-clean alif-flash alif-west-config alif-west-sync alif-zephyr-pip-deps alif-se-tools-extract

# Install-time helpers (invoked from sdk.yml's install: section via
# $(MAKE) <target> - keeping the actual multi-line shell logic here avoids
# the per-line-subshell behaviour of sdk.yml's "commands:" blocks).

# Hand-write .west/config instead of calling "west init -l": this needs no
# python/west binary at all, so it works even before the pip install step
# has run, and lets west commands be used manually from $(WORKSPACE) right
# away.
alif-west-config:
	mkdir -p $(WORKSPACE)/.west
	printf '[manifest]\npath = alif\nfile = west.yml\n' > $(WORKSPACE)/.west/config

alif-west-sync:
	$(WORKSPACE)/.venv/bin/west update

alif-zephyr-pip-deps:
	$(WORKSPACE)/.venv/bin/pip install -r $(WORKSPACE)/zephyr/scripts/requirements.txt

alif-se-tools-extract:
	mkdir -p $(ALIF_SE_TOOLS_DIR)
	tar -xf $(ALIF_SE_TOOLS_TAR) -C $(ALIF_SE_TOOLS_DIR) --strip-components=1

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
