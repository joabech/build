################################################################################
# Busybox static build + cpio initramfs generation
################################################################################
BUSYBOX_DIR           ?= $(WORKSPACE)/busybox
BUSYBOX_INSTALL       ?= $(OUT_DIR)/busybox-root
INITRAMFS             ?= $(OUT_DIR)/initramfs.cpio.gz
BUSYBOX_CROSS_COMPILE := $(TOOLCHAIN_AARCH64_LINUX)/$(CROSS_COMPILE_LINUX)
BUSYBOX_CONFIG_STAMP  := $(OUT_DIR)/busybox.config.stamp

# Use ccache automatically when available
CCACHE := $(shell command -v ccache 2>/dev/null)
ifneq ($(CCACHE),)
BUSYBOX_CC := ccache $(BUSYBOX_CROSS_COMPILE)gcc
else
BUSYBOX_CC := $(BUSYBOX_CROSS_COMPILE)gcc
endif

################################################################################
# Build / clean targets (called from sdk.yml redirects)
################################################################################
.PHONY: busybox-config busybox-build busybox-initramfs busybox-clean

$(BUSYBOX_CONFIG_STAMP):
	@[ -d $(BUSYBOX_DIR) ] || { echo "ERROR: busybox directory not found. Run 'cim update' first."; exit 1; }
	$(MAKE) -C $(BUSYBOX_DIR) \
		CROSS_COMPILE=$(BUSYBOX_CROSS_COMPILE) \
		defconfig
	sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' $(BUSYBOX_DIR)/.config
	@touch $(BUSYBOX_CONFIG_STAMP)

busybox-config: $(BUSYBOX_CONFIG_STAMP)

busybox-build: $(BUSYBOX_CONFIG_STAMP)
	$(MAKE) -C $(BUSYBOX_DIR) \
		CROSS_COMPILE=$(BUSYBOX_CROSS_COMPILE) \
		CC="$(BUSYBOX_CC)"
	$(MAKE) -C $(BUSYBOX_DIR) \
		CROSS_COMPILE=$(BUSYBOX_CROSS_COMPILE) \
		CONFIG_PREFIX=$(BUSYBOX_INSTALL) \
		install

busybox-initramfs: busybox-build
	mkdir -p $(BUSYBOX_INSTALL)/proc $(BUSYBOX_INSTALL)/sys $(BUSYBOX_INSTALL)/dev
	@echo '#!/bin/sh' > $(BUSYBOX_INSTALL)/init
	@echo 'mount -t proc proc /proc' >> $(BUSYBOX_INSTALL)/init
	@echo 'mount -t sysfs sysfs /sys' >> $(BUSYBOX_INSTALL)/init
	@echo 'mount -t devtmpfs devtmpfs /dev' >> $(BUSYBOX_INSTALL)/init
	@echo 'exec /bin/sh' >> $(BUSYBOX_INSTALL)/init
	chmod +x $(BUSYBOX_INSTALL)/init
	cd $(BUSYBOX_INSTALL) && find . | cpio -H newc -o | gzip > $(INITRAMFS)

busybox-clean:
	@[ -d $(BUSYBOX_DIR) ] && $(MAKE) -C $(BUSYBOX_DIR) clean || true
	rm -f $(BUSYBOX_CONFIG_STAMP)
	rm -rf $(BUSYBOX_INSTALL) $(INITRAMFS)
