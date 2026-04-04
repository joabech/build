################################################################################
# Variables
################################################################################
WORKSPACE       ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)

HELLO_DIR       ?= $(WORKSPACE)/hello-world
HELLO_BIN       ?= $(HELLO_DIR)/hello-world.bin
HELLO_ELF       ?= $(HELLO_DIR)/hello-world.elf

UBOOT_DIR       ?= $(WORKSPACE)/u-boot
MKIMAGE         ?= $(UBOOT_DIR)/tools/mkimage

################################################################################
# Build Targets
################################################################################
.PHONY: hello-world-build hello-world-clean run-hello

hello-world-build:
	@$(MAKE) \
		-C $(HELLO_DIR) \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		TOOLCHAIN_PATH=$(TOOLCHAIN_AARCH64_BM) \
		MKIMAGE=$(MKIMAGE) \
		all

hello-world-clean:
	@$(MAKE) -C $(HELLO_DIR) clean

################################################################################
# Run automated hello-world test via expect script
################################################################################

run-hello: hello-world-build
	@$(HELLO_DIR)/run-hello.sh
