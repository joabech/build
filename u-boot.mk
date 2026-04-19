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
UBOOT_CROSS_COMPILE := $(TOOLCHAIN_AARCH64_BM)/$(CROSS_COMPILE)

# Use ccache automatically when available.  U-Boot sets CC = $(CROSS_COMPILE)gcc
# internally; overriding CC on the command line is the correct way to inject it.
CCACHE := $(shell command -v ccache 2>/dev/null)
ifneq ($(CCACHE),)
UBOOT_CC := ccache $(UBOOT_CROSS_COMPILE)gcc
else
UBOOT_CC := $(UBOOT_CROSS_COMPILE)gcc
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
UBOOT_OUT          ?= $(OUT_DIR)/u-boot
UBOOT_CONFIG_STAMP := $(UBOOT_OUT)/.config.stamp

################################################################################
# Build / test / clean / flash  (called from sdk.yml redirects)
################################################################################
.PHONY: u-boot-config u-boot-build u-boot-check u-boot-clean u-boot-flash

u-boot-check:
	@[ -f $(UBOOT_BIN) ] || { echo "ERROR: $(UBOOT_BIN) not found. Run 'make sdk-build' first."; exit 1; }
	@echo "U-Boot binary exists - basic build verification passed"
	@ls -lh $(UBOOT_BIN)

# The configure step, use a stamp/marker file to avoid re-running it on every
# build.
$(UBOOT_CONFIG_STAMP):
	@[ -d $(UBOOT_DIR) ] || { echo "ERROR: u-boot directory not found. Run 'cim update' first."; exit 1; }
	$(MAKE) -C $(UBOOT_DIR) \
		O=$(UBOOT_OUT) $(UBOOT_DEFCONFIG) \
		CROSS_COMPILE=$(UBOOT_CROSS_COMPILE) \
		$(OPENSSL_FLAGS)
	$(MAKE) -C $(UBOOT_DIR) \
		O=$(UBOOT_OUT) olddefconfig \
		CROSS_COMPILE=$(UBOOT_CROSS_COMPILE) \
		$(OPENSSL_FLAGS)
	@touch $(UBOOT_CONFIG_STAMP)

u-boot-config: $(UBOOT_CONFIG_STAMP)

u-boot-build: $(UBOOT_CONFIG_STAMP)
	$(MAKE) -C $(UBOOT_DIR) \
		O=$(UBOOT_OUT) \
		CROSS_COMPILE=$(UBOOT_CROSS_COMPILE) \
		CC="$(UBOOT_CC)" \
		$(OPENSSL_FLAGS)

u-boot-clean:
	@[ -d $(UBOOT_DIR) ] && \
		$(MAKE) -C $(UBOOT_DIR) \
		CROSS_COMPILE=$(UBOOT_CROSS_COMPILE) \
		distclean 2>/dev/null || true
	rm -f $(UBOOT_CONFIG_STAMP)

u-boot-flash:
	@echo "U-Boot is a bootloader - no flashing needed from here."
	@echo "Output files:"
	@echo "  $(UBOOT_BIN)  - Raw binary"
	@echo "  $(UBOOT_ELF)  - ELF binary"
	@echo "  $(UBOOT_OUT)/u-boot.dtb  - Device tree blob"
