################################################################################
# Variables
################################################################################
HELLO_DIR       ?= $(WORKSPACE)/hello-world
HELLO_OUT       ?= $(OUT_DIR)/hello-world
MKIMAGE         ?= $(OUT_DIR)/u-boot/tools/mkimage

################################################################################
# Build Targets
################################################################################
.PHONY: hello-world-build hello-world-clean run-hello

hello-world-build:
	@mkdir -p $(HELLO_OUT)
	@$(MAKE) \
		-C $(HELLO_DIR) \
		OUTDIR=$(HELLO_OUT) \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		TOOLCHAIN_PATH=$(TOOLCHAIN_AARCH64_BM) \
		MKIMAGE=$(MKIMAGE) \
		all

hello-world-clean:
	@$(MAKE) -C $(HELLO_DIR) OUTDIR=$(HELLO_OUT) clean

################################################################################
# Run automated hello-world test via expect script
################################################################################
run-hello: hello-world-build
	@OUTDIR=$(HELLO_OUT) $(HELLO_DIR)/run-hello.sh
