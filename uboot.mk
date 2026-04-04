################################################################################
# Variables
################################################################################
WORKSPACE             ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)
TOOLCHAIN_AARCH64_BM  ?= $(WORKSPACE)/toolchains/aarch64-bm/bin

UBOOT_DIR             ?= $(WORKSPACE)/u-boot
UBOOT_BIN             ?= $(UBOOT_DIR)/u-boot.bin
UBOOT_ELF             ?= $(UBOOT_DIR)/u-boot
UBOOT_DEFCONFIG       ?= qemu_arm64_defconfig

################################################################################
# macOS shell configuration - brew is typically used to dev tools
################################################################################
ifeq ($(shell uname -s),Darwin)
export PATH := /opt/homebrew/bin:$(PATH)
endif

################################################################################
# Toolchain and ccache
################################################################################
export PATH := $(TOOLCHAIN_AARCH64_BM):$(PATH)

CCACHE := $(shell command -v ccache 2>/dev/null)
ifneq ($(CCACHE),)
UBOOT_CC := ccache $(CROSS_COMPILE)gcc
else
UBOOT_CC := $(CROSS_COMPILE)gcc
endif

OPENSSL_FLAGS :=
ifeq ($(shell uname -s),Darwin)
OPENSSL_PREFIX := $(shell brew --prefix openssl@3 2>/dev/null || brew --prefix openssl 2>/dev/null)
ifneq ($(OPENSSL_PREFIX),)
OPENSSL_FLAGS := HOSTCFLAGS="-I$(OPENSSL_PREFIX)/include" HOSTLDFLAGS="-L$(OPENSSL_PREFIX)/lib"
endif
endif

################################################################################
# Build / test / clean / flash
################################################################################
.PHONY: uboot-build uboot-check uboot-clean uboot-flash

uboot-build:
	@[ -d u-boot ] || { echo "ERROR: u-boot directory not found. Run 'cim update' first."; exit 1; }
	$(MAKE) -C u-boot $(UBOOT_DEFCONFIG) CROSS_COMPILE=$(CROSS_COMPILE) $(OPENSSL_FLAGS)
	$(MAKE) -C u-boot olddefconfig CROSS_COMPILE=$(CROSS_COMPILE) $(OPENSSL_FLAGS)
	$(MAKE) -C u-boot CROSS_COMPILE=$(CROSS_COMPILE) CC="$(UBOOT_CC)" $(OPENSSL_FLAGS)

uboot-check:
	@[ -f u-boot/u-boot.bin ] || { echo "ERROR: u-boot.bin not found. Run 'make sdk-build' first."; exit 1; }
	@echo "U-Boot binary exists - basic build verification passed"
	@ls -lh u-boot/u-boot.bin

uboot-clean:
	[ -d u-boot ] && $(MAKE) -C u-boot distclean CROSS_COMPILE=$(CROSS_COMPILE) 2>/dev/null || true

uboot-flash:
	@echo "U-Boot is a bootloader - no flashing needed from here."
	@echo "Output files:"
	@echo "  u-boot/u-boot.bin  - Raw binary"
	@echo "  u-boot/u-boot      - ELF binary"
	@echo "  u-boot/u-boot.dtb  - Device tree blob"

################################################################################
# U-Boot tools (mkimage)
################################################################################

.PHONY: uboot-tools
uboot-tools:
	@$(MAKE) -C $(UBOOT_DIR) tools CROSS_COMPILE=$(CROSS_COMPILE) $(OPENSSL_FLAGS)
