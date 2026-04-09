################################################################################
# macOS shell configuration
# Ensure Homebrew's bash (5.3.x) is found before system bash (3.x)
# This is required for U-Boot's scripts/check-local-export which uses 'shopt
# lastpipe'
################################################################################
ifeq ($(shell uname -s),Darwin)
export PATH := /opt/homebrew/bin:$(PATH)
endif

################################################################################
# Toolchain and ccache
################################################################################

# Prepend toolchain to PATH so the cross compiler and aarch64-none-elf-gdb
# are found both during the build and when running QEMU/debug targets.
export PATH := $(WORKSPACE)/$(TOOLCHAIN_AARCH64_BM):$(PATH)

# Use ccache automatically when available.  U-Boot sets CC = $(CROSS_COMPILE)gcc
# internally; overriding CC on the command line is the correct way to inject it.
CCACHE := $(shell command -v ccache 2>/dev/null)
ifneq ($(CCACHE),)
UBOOT_CC := ccache $(CROSS_COMPILE)gcc
else
UBOOT_CC := $(CROSS_COMPILE)gcc
endif

# macOS OpenSSL support
# Homebrew installs OpenSSL to non-standard locations; U-Boot build needs to
# find headers/libs
OPENSSL_FLAGS :=
ifeq ($(shell uname -s),Darwin)
OPENSSL_PREFIX := $(shell brew --prefix openssl@3 2>/dev/null || brew --prefix openssl 2>/dev/null)
ifneq ($(OPENSSL_PREFIX),)
OPENSSL_FLAGS := HOSTCFLAGS="-I$(OPENSSL_PREFIX)/include" HOSTLDFLAGS="-L$(OPENSSL_PREFIX)/lib"
endif
endif

################################################################################
# QEMU configuration
################################################################################

QEMU_BINARY   ?= qemu-system-aarch64
QEMU_MACHINE  ?= virt
QEMU_CPU      ?= cortex-a53
QEMU_MEMORY   ?= 512
QEMU_SMP      ?= 2

UBOOT_DIR     ?= $(WORKSPACE)/u-boot
UBOOT_BIN     ?= $(UBOOT_DIR)/u-boot.bin
UBOOT_ELF     ?= $(UBOOT_DIR)/u-boot

################################################################################
# Build / test / clean / flash  (called from sdk.yml redirects)
################################################################################
.PHONY: u-boot-build u-boot-check u-boot-clean u-boot-flash

u-boot-build:
	@[ -d u-boot ] || { echo "ERROR: u-boot directory not found. Run 'cim update' first."; exit 1; }
	$(MAKE) -C u-boot $(UBOOT_DEFCONFIG) CROSS_COMPILE=$(CROSS_COMPILE) $(OPENSSL_FLAGS)
	$(MAKE) -C u-boot olddefconfig CROSS_COMPILE=$(CROSS_COMPILE) $(OPENSSL_FLAGS)
	$(MAKE) -C u-boot CROSS_COMPILE=$(CROSS_COMPILE) CC="$(UBOOT_CC)" $(OPENSSL_FLAGS)

u-boot-check:
	@[ -f u-boot/u-boot.bin ] || { echo "ERROR: u-boot.bin not found. Run 'make sdk-build' first."; exit 1; }
	@echo "U-Boot binary exists - basic build verification passed"
	@ls -lh u-boot/u-boot.bin

u-boot-clean:
	[ -d u-boot ] && $(MAKE) -C u-boot distclean CROSS_COMPILE=$(CROSS_COMPILE) 2>/dev/null || true

u-boot-flash:
	@echo "U-Boot is a bootloader - no flashing needed from here."
	@echo "Output files:"
	@echo "  u-boot/u-boot.bin  - Raw binary"
	@echo "  u-boot/u-boot      - ELF binary"
	@echo "  u-boot/u-boot.dtb  - Device tree blob"
