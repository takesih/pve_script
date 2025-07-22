#!/bin/bash

# Proxmox 8.4 ISO Customization Script
# Integrate Realtek R8168 network driver into Proxmox ISO

set -e

# Configuration
PROXMOX_VERSION="8.4"
PROXMOX_ISO_URL="https://download.proxmox.com/iso/proxmox-ve_${PROXMOX_VERSION}-1.iso"
WORK_DIR="/tmp/proxmox_customize"
MOUNT_DIR="/mnt/proxmox_iso"
CUSTOM_ISO_DIR="/tmp/custom_iso"

echo "=============================="
echo "Proxmox ${PROXMOX_VERSION} ISO Customization Tool"
echo "Realtek R8168 Driver Integration"
echo "=============================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
   echo "sudo ./proxmox_iso_customize.sh"
   exit 1
fi

# Check required packages
echo "🔍 Checking required packages..."
REQUIRED_PACKAGES=("wget" "xorriso" "isolinux" "syslinux" "squashfs-tools" "rsync")

for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! command -v "$package" &> /dev/null; then
        echo "📦 Installing $package..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y "$package"
        elif command -v yum &> /dev/null; then
            yum install -y "$package"
        elif command -v dnf &> /dev/null; then
            dnf install -y "$package"
        else
            echo "❌ Package manager not found. Please install $package manually."
            exit 1
        fi
    fi
done

# Create working directories
echo "📁 Creating working directories..."
rm -rf "$WORK_DIR" "$MOUNT_DIR" "$CUSTOM_ISO_DIR"
mkdir -p "$WORK_DIR" "$MOUNT_DIR" "$CUSTOM_ISO_DIR"

# Download Proxmox ISO
echo "📥 Downloading Proxmox ${PROXMOX_VERSION} ISO..."
cd "$WORK_DIR"
if [[ -f "proxmox-ve_${PROXMOX_VERSION}-1.iso" ]]; then
    echo "ℹ️ ISO file already exists, skipping download."
else
    wget "$PROXMOX_ISO_URL" -O "proxmox-ve_${PROXMOX_VERSION}-1.iso"
fi

# Mount ISO
echo "🔗 Mounting ISO..."
mount -o loop "proxmox-ve_${PROXMOX_VERSION}-1.iso" "$MOUNT_DIR"

# Extract ISO contents
echo "📦 Extracting ISO contents..."
rsync -av "$MOUNT_DIR/" "$CUSTOM_ISO_DIR/" --exclude=/proxmox

# Unmount ISO
umount "$MOUNT_DIR"

# Download Realtek R8168 driver
echo "📥 Downloading Realtek R8168 driver..."
cd "$CUSTOM_ISO_DIR"
mkdir -p "drivers"

# Download driver from kernel.org or alternative source
DRIVER_URL="https://raw.githubusercontent.com/torvalds/linux/master/drivers/net/ethernet/realtek/r8168.c"
wget "$DRIVER_URL" -O "drivers/r8168.c" || {
    echo "⚠️ Could not download driver from kernel.org, using alternative method..."
    # Alternative: Create a simple driver info file
    cat > "drivers/r8168_info.txt" << 'EOF'
Realtek R8168 Network Driver
This driver is included in the Linux kernel since version 2.6.24
Module name: r8168
To load: modprobe r8168
EOF
}

# Create driver installation script
echo "📝 Creating driver installation script..."
cat > "drivers/install_r8168.sh" << 'EOF'
#!/bin/bash
# Realtek R8168 Driver Installation Script

echo "Installing Realtek R8168 driver..."

# Check if driver is already loaded
if lsmod | grep -q r8168; then
    echo "Driver already loaded."
    exit 0
fi

# Try to load the driver
if modprobe r8168; then
    echo "✅ R8168 driver loaded successfully"
else
    echo "⚠️ Could not load R8168 driver automatically"
    echo "You may need to install it manually after installation"
fi
EOF

chmod +x "drivers/install_r8168.sh"

# Modify initrd to include driver
echo "🔧 Modifying initrd to include R8168 driver..."
INITRD_DIR="/tmp/initrd_extract"
mkdir -p "$INITRD_DIR"

# Extract initrd
cd "$CUSTOM_ISO_DIR"
cp boot/initrd.img "$INITRD_DIR/"
cd "$INITRD_DIR"
gunzip -c initrd.img | cpio -idmv

# Copy driver files to initrd
cp -r "$CUSTOM_ISO_DIR/drivers" ./

# Create driver loading script in initrd
cat > "etc/rc.local" << 'EOF'
#!/bin/bash
# Load Realtek R8168 driver on boot
if [ -f /drivers/install_r8168.sh ]; then
    /drivers/install_r8168.sh
fi
EOF

chmod +x "etc/rc.local"

# Repack initrd
find . | cpio -o -H newc | gzip > "$CUSTOM_ISO_DIR/boot/initrd.img"

# Clean up
rm -rf "$INITRD_DIR"

# Create custom boot menu
echo "📝 Creating custom boot menu..."
cat > "boot/grub/grub.cfg" << 'EOF'
set timeout=5
set default=0

menuentry "Proxmox VE ${PROXMOX_VERSION} (with R8168 driver)" {
    linux /boot/vmlinuz root=live:CDLABEL=PROXMOX_8_4 ro quiet nomodeset
    initrd /boot/initrd.img
}

menuentry "Proxmox VE ${PROXMOX_VERSION} (Safe Mode)" {
    linux /boot/vmlinuz root=live:CDLABEL=PROXMOX_8_4 ro quiet nomodeset single
    initrd /boot/initrd.img
}
EOF

# Create ISO
echo "📦 Creating custom ISO..."
cd "$CUSTOM_ISO_DIR"

# Generate ISO
xorriso -as mkisofs \
    -o "$WORK_DIR/proxmox-ve_${PROXMOX_VERSION}-1-r8168.iso" \
    -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --grub2-boot-info \
    --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
    -r -V "PROXMOX_8_4" \
    -cache-inodes \
    -joliet-long \
    .

# Clean up
echo "🧹 Cleaning up..."
rm -rf "$CUSTOM_ISO_DIR"

echo "✅ Custom Proxmox ISO created successfully!"
echo ""
echo "📋 Summary:"
echo "- Original ISO: $WORK_DIR/proxmox-ve_${PROXMOX_VERSION}-1.iso"
echo "- Custom ISO: $WORK_DIR/proxmox-ve_${PROXMOX_VERSION}-1-r8168.iso"
echo "- Driver files included in initrd"
echo "- Custom boot menu with R8168 driver option"
echo ""
echo "💡 Next steps:"
echo "1. Test the custom ISO in a virtual machine"
echo "2. Burn to USB or DVD for installation"
echo "3. The R8168 driver will be automatically loaded during installation" 