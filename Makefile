################################################################################
# Variables
################################################################################
WORKSPACE            ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)
TOOLCHAIN_AARCH64_BM ?= $(WORKSPACE)/toolchains/aarch64-bm/bin

export PATH := $(TOOLCHAIN_AARCH64_BM):$(PATH)

################################################################################
# QEMU configuration and targets (orchestration level)
################################################################################

QEMU_BINARY 	  ?= qemu-system-aarch64
QEMU_MACHINE    ?= virt
QEMU_CPU        ?= cortex-a53
QEMU_MEMORY     ?= 512
QEMU_SMP        ?= 2

UBOOT_DIR 		  ?= $(WORKSPACE)/u-boot
UBOOT_BIN 		  ?= $(UBOOT_DIR)/u-boot.bin
UBOOT_ELF 		  ?= $(UBOOT_DIR)/u-boot

HELLO_DIR       ?= $(WORKSPACE)/hello-world
HELLO_ELF       ?= $(HELLO_DIR)/hello-world.elf

# Helper macros
define check_uboot
	@[ -f "$(UBOOT_BIN)" ] || { echo "ERROR: $(UBOOT_BIN) not found. Run 'make sdk-build' first."; exit 1; }
endef

define check_qemu
	@command -v $(QEMU_BINARY) >/dev/null 2>&1 || { \
		echo "ERROR: $(QEMU_BINARY) not found"; \
		echo "  Ubuntu/Debian: sudo apt install qemu-system-arm"; \
		echo "  Fedora:        sudo dnf install qemu-system-aarch64"; \
		echo "  macOS:         brew install qemu"; \
		exit 1; }
endef

define check_hello
	@[ -f "$(HELLO_ELF)" ] || { echo "ERROR: $(HELLO_ELF) not found. Run 'make hello-world-build' first."; exit 1; }
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

# QEMU targets
.PHONY: qemu qemu-gdb qemu-attach qemu-monitor qemu-gfx qemu-hello

qemu: $(UBOOT_BIN)
	$(call check_uboot)
	$(call check_qemu)
	@echo "Press Ctrl+A then X to quit."
	@echo ""
	$(call run_qemu,-nographic)

qemu-gdb: $(UBOOT_BIN)
	$(call check_uboot)
	$(call check_qemu)
	@echo "QEMU waiting for GDB on port 1234..."
	@echo "Connect with: aarch64-none-elf-gdb -ex 'target remote :1234' u-boot/u-boot"
	@echo ""
	$(call run_qemu,-nographic -s -S)

qemu-attach: $(UBOOT_ELF)
	@echo "Attaching GDB to QEMU on port 1234..."
	$(TOOLCHAIN_AARCH64_BM)/aarch64-none-elf-gdb -ex 'target remote :1234' $(UBOOT_ELF)

qemu-monitor: $(UBOOT_BIN)
	$(call check_uboot)
	$(call check_qemu)
	$(call run_qemu,-serial mon:stdio)

qemu-gfx: $(UBOOT_BIN)
	$(call check_uboot)
	$(call check_qemu)
	$(call run_qemu,-serial stdio)

# QEMU with hello-world on virtio disk
qemu-hello: $(UBOOT_BIN)
	$(call check_uboot)
	$(call check_qemu)
	$(call check_hello)
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
	$(call run_qemu,-nographic -drive file=fat:rw:$(HELLO_DIR),format=raw,if=virtio)
