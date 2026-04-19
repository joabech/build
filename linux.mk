################################################################################
# Linux kernel build for AArch64 QEMU virt
################################################################################
LINUX_DIR               ?= $(WORKSPACE)/linux
LINUX_OUT               ?= $(OUT_DIR)/linux

LINUX_CROSS_COMPILE     := $(TOOLCHAIN_AARCH64_LINUX)/$(CROSS_COMPILE_LINUX)
LINUX_CONFIG_STAMP      := $(LINUX_OUT)/.config.stamp

# Use ccache automatically when available
CCACHE := $(shell command -v ccache 2>/dev/null)
ifneq ($(CCACHE),)
LINUX_CC := ccache $(LINUX_CROSS_COMPILE)gcc
else
LINUX_CC := $(LINUX_CROSS_COMPILE)gcc
endif

################################################################################
# Build / clean targets (called from sdk.yml redirects)
################################################################################
.PHONY: linux-config linux-build linux-clean

$(LINUX_CONFIG_STAMP):
	@[ -d $(LINUX_DIR) ] || { echo "ERROR: linux directory not found. Run 'cim update' first."; exit 1; }
	$(MAKE) -C $(LINUX_DIR) \
		O=$(LINUX_OUT) \
		ARCH=$(ARCH) \
		CROSS_COMPILE=$(LINUX_CROSS_COMPILE) \
		defconfig
	$(MAKE) -C $(LINUX_DIR) \
		O=$(LINUX_OUT) \
		ARCH=$(ARCH) \
		CROSS_COMPILE=$(LINUX_CROSS_COMPILE) \
		olddefconfig
	@touch $(LINUX_CONFIG_STAMP)

linux-config: $(LINUX_CONFIG_STAMP)

linux-build: $(LINUX_CONFIG_STAMP)
	$(MAKE) -C $(LINUX_DIR) \
		O=$(LINUX_OUT) \
		ARCH=arm64 \
		CROSS_COMPILE=$(LINUX_CROSS_COMPILE) \
		CC="$(LINUX_CC)" \
		Image

linux-clean:
	@[ -d $(LINUX_DIR) ] && $(MAKE) -C $(LINUX_DIR) ARCH=$(ARCH) mrproper 2>/dev/null || true
	rm -f $(LINUX_CONFIG_STAMP)
