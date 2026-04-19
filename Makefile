################################################################################
# Makefile suppose to be used with/from a Code in Motion workspace, which gives
# a couple of default variables such as workspace, toolchains, out directory
# etc.
################################################################################

################################################################################
# QEMU configuration and targets (orchestration level)
################################################################################
QEMU_BINARY     ?= qemu-system-aarch64
QEMU_MACHINE    ?= virt
QEMU_CPU        ?= cortex-a53
QEMU_MEMORY     ?= 512
QEMU_SMP        ?= 2

UBOOT_DIR       ?= $(WORKSPACE)/u-boot
UBOOT_BIN       ?= $(OUT_DIR)/u-boot/u-boot.bin
UBOOT_ELF       ?= $(OUT_DIR)/u-boot/u-boot

HELLO_DIR       ?= $(WORKSPACE)/hello-world
HELLO_OUT       ?= $(OUT_DIR)/hello-world
HELLO_ELF       ?= $(HELLO_OUT)/hello-world.elf
HELLO_BIN       ?= $(HELLO_OUT)/hello-world.bin

LINUX_DIR       ?= $(WORKSPACE)/linux
LINUX_IMAGE     ?= $(OUT_DIR)/linux/arch/arm64/boot/Image
INITRAMFS       ?= $(OUT_DIR)/initramfs.cpio.gz
BOOT_DIR        ?= $(OUT_DIR)/boot

MKIMAGE         ?= $(OUT_DIR)/u-boot/tools/mkimage
LINUX_BOOT_CMD  ?= $(WORKSPACE)/build/linux-boot.cmd
BOOT_SCR        ?= $(BOOT_DIR)/boot.scr


################################################################################
# QEMU helper macros and targets. Normally these shouldn't be needed, since we
# would have targets that will build things as needed. This is just a way to
# give more straight forward error messages.
################################################################################
define check_qemu
	@command -v $(QEMU_BINARY) >/dev/null 2>&1 || { \
		echo "ERROR: $(QEMU_BINARY) not found"; \
		echo "  Ubuntu/Debian: sudo apt install qemu-system-arm"; \
		echo "  Fedora:        sudo dnf install qemu-system-aarch64"; \
		echo "  macOS:         brew install qemu"; \
		exit 1; }
endef

define check_uboot
	@[ -f "$(UBOOT_BIN)" ] || { echo "ERROR: $(UBOOT_BIN) not found. Run 'make sdk-build' first."; exit 1; }
endef

define check_hello
	@[ -f "$(HELLO_ELF)" ] || { echo "ERROR: $(HELLO_ELF) not found. Run 'make hello-world-build' first."; exit 1; }
endef

define check_linux
	@[ -f "$(LINUX_IMAGE)" ] || { echo "ERROR: $(LINUX_IMAGE) not found. Run 'make linux-build' first."; exit 1; }
endef

define check_initramfs
	@[ -f "$(INITRAMFS)" ] || { echo "ERROR: $(INITRAMFS) not found. Run 'make busybox-build' first."; exit 1; }
endef

define check_boot_scr
	@[ -f "$(BOOT_SCR)" ] || { echo "ERROR: $(BOOT_SCR) not found. Run 'make linux-boot-script' first."; exit 1; }
endef

# QEMU runner macro - takes extra arguments as parameter
# Usage: $(call run_qemu,<extra-args>)
define run_qemu
	$(QEMU_BINARY) \
		-machine $(QEMU_MACHINE) \
		-cpu $(QEMU_CPU) \
		-smp $(QEMU_SMP) \
		-m $(QEMU_MEMORY) \
		-bios $(UBOOT_BIN) \
		$(1)
endef

################################################################################
# Boot script generation
################################################################################
.PHONY: linux-boot-script

linux-boot-script: $(BOOT_SCR)

$(BOOT_SCR): $(LINUX_BOOT_CMD)
	@[ -f "$(MKIMAGE)" ] || { echo "ERROR: $(MKIMAGE) not found. Run 'make u-boot-build' first."; exit 1; }
	@mkdir -p $(dir $@)
	$(MKIMAGE) -A arm64 -O linux -T script -C none -n "Linux Boot" -d $< $@

################################################################################
# QEMU targets
################################################################################
.PHONY: qemu qemu-gdb qemu-attach qemu-monitor qemu-gfx qemu-hello qemu-linux

# Boot up u-boot with QEMU
qemu:
	$(call check_qemu)
	$(call check_uboot)
	@echo "Press Ctrl+A then X to quit."
	@echo ""
	$(call run_qemu,-nographic)

# Launch a gdb server with QEMU
qemu-gdb:
	$(call check_qemu)
	$(call check_uboot)
	@echo "QEMU waiting for GDB on port 1234..."
	@echo "Connect with: aarch64-none-elf-gdb -ex 'target remote :1234' $(UBOOT_ELF)"
	@echo ""
	$(call run_qemu,-nographic -s -S)

# Attach to the launched GDB session
qemu-attach:
	$(call check_uboot)
	@echo "Attaching GDB to QEMU on port 1234..."
	$(TOOLCHAIN_AARCH64_BM)/aarch64-none-elf-gdb -ex 'target remote :1234' $(UBOOT_ELF)

# Require display, X11 or similar
qemu-monitor:
	$(call check_qemu)
	$(call check_uboot)
	$(call run_qemu,-serial mon:stdio)

# Require display, X11 or similar
qemu-gfx:
	$(call check_qemu)
	$(call check_uboot)
	$(call run_qemu,-serial stdio)

# QEMU with hello-world on virtio disk
qemu-hello:
	$(call check_hello)
	$(call check_qemu)
	$(call check_uboot)
	@echo "Starting QEMU with hello-world on virtio disk..."
	@echo ""
	@echo "At the U-Boot prompt (=>), type:"
	@echo "  fatload virtio 0:1 0x40400000 hello-world.bin"
	@echo "  go 0x40400000"
	@echo ""
	@echo "Or run the automated script:"
	@echo "  ./hello-world/run-hello.sh"
	@echo ""
	@echo "Press Ctrl+A then X to quit."
	@echo ""
	$(call run_qemu,-nographic -drive file=fat:rw:$(HELLO_OUT),format=raw,if=virtio)

# QEMU with Linux + busybox initramfs on virtio disk (auto-boot via boot.scr)
qemu-linux:
	$(call check_boot_scr)
	$(call check_initramfs)
	$(call check_linux)
	$(call check_qemu)
	$(call check_uboot)
	@mkdir -p $(BOOT_DIR)
	@cp -u $(LINUX_IMAGE) $(BOOT_DIR)/Image
	@cp -u $(INITRAMFS) $(BOOT_DIR)/initramfs.cpio.gz
	@echo "Starting QEMU with Linux + busybox initramfs (auto-boot via boot.scr)..."
	@echo ""
	$(call run_qemu,-nographic -drive file=fat:rw:$(BOOT_DIR),format=raw,if=virtio)

################################################################################
# Help
################################################################################
help:
	@echo "Build targets:"
	@echo "  make sdk-build        - Build U-Boot, Linux, busybox, hello-world and boot script"
	@echo "  make sdk-test         - Verify the build output"
	@echo "  make sdk-clean        - Remove build artifacts"
	@echo ""
	@echo "QEMU / debug targets:"
	@echo "  make qemu             - Run U-Boot (serial console, Ctrl+A X to quit)"
	@echo "  make qemu-gdb         - Run with GDB server on :1234 (blocks)"
	@echo "  make qemu-monitor     - Run with QEMU monitor on stdio"
	@echo "  make qemu-gfx         - Run with graphical output"
	@echo "  make qemu-hello       - Run U-Boot with hello-world on virtio disk"
	@echo "  make qemu-linux       - Run U-Boot -> Linux -> busybox shell"
	@echo "  make qemu-attach      - Attach aarch64-none-elf-gdb to a running qemu-gdb session"
	@echo "  Workflow: terminal 1: make qemu-gdb  |  terminal 2: make qemu-attach"
	@echo ""
	@echo "Configuration:"
	@echo "  CROSS_COMPILE        = $(CROSS_COMPILE)"
	@echo "  UBOOT_DEFCONFIG      = $(UBOOT_DEFCONFIG)"
	@echo "  TOOLCHAIN_AARCH64_BM = $(TOOLCHAIN_AARCH64_BM)"
	@echo "  QEMU_MACHINE/CPU     = $(QEMU_MACHINE) / $(QEMU_CPU)"
	@echo "  ccache               = $(if $(CCACHE),$(CCACHE),not found)"
