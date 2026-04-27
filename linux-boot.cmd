echo "Loading Linux kernel..."
fatload nvme 0:1 0x40400000 Image
echo "Loading initramfs..."
fatload nvme 0:1 0x44000000 initramfs.cpio.gz
echo "Setting bootargs..."
setenv bootargs console=ttyAMA0 earlyprintk=serial
echo "Booting Linux..."
booti 0x40400000 0x44000000:${filesize} ${fdt_addr}
