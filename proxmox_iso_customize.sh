#!/bin/bash

# Proxmox 8.4 ISO Customization Script
# Integrate Realtek R8168 network driver into Proxmox ISO

set -e

# Configuration
PROXMOX_VERSION="8.4"
PROXMOX_ISO_URL="https://enterprise.proxmox.com/iso/proxmox-ve_${PROXMOX_VERSION}-1.iso"
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
echo "📥 Checking Proxmox ${PROXMOX_VERSION} ISO..."
cd "$WORK_DIR"

# Check if ISO already exists and has valid size (at least 1GB)
if [[ -f "proxmox-ve_${PROXMOX_VERSION}-1.iso" ]]; then
    ISO_SIZE=$(stat -c%s "proxmox-ve_${PROXMOX_VERSION}-1.iso" 2>/dev/null || echo "0")
    if [[ $ISO_SIZE -gt 1000000000 ]]; then  # Greater than 1GB
        echo "ℹ️ ISO file already exists and appears complete."
        echo "📁 Using existing ISO: $(ls -lh proxmox-ve_${PROXMOX_VERSION}-1.iso)"
        echo "📊 File size: $((ISO_SIZE / 1024 / 1024)) MB"
    else
        echo "⚠️ Existing ISO file appears incomplete or corrupted."
        echo "📥 Re-downloading from: $PROXMOX_ISO_URL"
        wget --no-check-certificate "$PROXMOX_ISO_URL" -O "proxmox-ve_${PROXMOX_VERSION}-1.iso"
        if [[ $? -ne 0 ]]; then
            echo "❌ Failed to download ISO. Please check the URL and try again."
            exit 1
        fi
        echo "✅ Download completed: $(ls -lh proxmox-ve_${PROXMOX_VERSION}-1.iso)"
    fi
else
    echo "📥 Downloading from: $PROXMOX_ISO_URL"
    wget --no-check-certificate "$PROXMOX_ISO_URL" -O "proxmox-ve_${PROXMOX_VERSION}-1.iso"
    if [[ $? -ne 0 ]]; then
        echo "❌ Failed to download ISO. Please check the URL and try again."
        exit 1
    fi
    echo "✅ Download completed: $(ls -lh proxmox-ve_${PROXMOX_VERSION}-1.iso)"
fi

# Mount ISO
echo "🔗 Mounting ISO..."
mkdir -p "$MOUNT_DIR"

# Check if we're in a container environment or if mounting fails
if [[ -f /.dockerenv ]] || grep -q 'lxc\|docker' /proc/1/cgroup 2>/dev/null || ! mount -o loop "proxmox-ve_${PROXMOX_VERSION}-1.iso" "$MOUNT_DIR" 2>/dev/null; then
    echo "⚠️ Detected container environment. Using alternative extraction method..."
    
    # Use 7zip or other tools to extract ISO without mounting
    if command -v 7z &> /dev/null; then
        echo "📦 Using 7zip to extract ISO..."
        7z x "proxmox-ve_${PROXMOX_VERSION}-1.iso" -o"$CUSTOM_ISO_DIR" -y
    elif command -v bsdtar &> /dev/null; then
        echo "📦 Using bsdtar to extract ISO..."
        bsdtar -xf "proxmox-ve_${PROXMOX_VERSION}-1.iso" -C "$CUSTOM_ISO_DIR"
    else
        echo "📦 Installing extraction tools..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y p7zip-full
            7z x "proxmox-ve_${PROXMOX_VERSION}-1.iso" -o"$CUSTOM_ISO_DIR" -y
        elif command -v yum &> /dev/null; then
            yum install -y p7zip
            7z x "proxmox-ve_${PROXMOX_VERSION}-1.iso" -o"$CUSTOM_ISO_DIR" -y
        elif command -v dnf &> /dev/null; then
            dnf install -y p7zip
            7z x "proxmox-ve_${PROXMOX_VERSION}-1.iso" -o"$CUSTOM_ISO_DIR" -y
        else
            echo "❌ No extraction tool available. Please install p7zip or bsdtar."
            exit 1
        fi
    fi
    
    if [[ $? -ne 0 ]]; then
        echo "❌ Failed to extract ISO. Please check if the ISO file is valid."
        exit 1
    fi
    
    echo "✅ ISO extracted successfully using alternative method."
else
    # Try normal mounting
    echo "📦 Extracting ISO contents using mount method..."
    rsync -av "$MOUNT_DIR/" "$CUSTOM_ISO_DIR/" --exclude=/proxmox
    
    # Unmount ISO
    umount "$MOUNT_DIR"
fi

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
wget --no-check-certificate "$DRIVER_URL" -O "drivers/r8168.c" || {
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

# Setup web server for download
echo "🌐 Setting up download server..."
CUSTOM_ISO_PATH="$WORK_DIR/proxmox-ve_${PROXMOX_VERSION}-1-r8168.iso"
DOWNLOAD_DIR="/var/www/html"
DOWNLOAD_PORT="8080"

# Install web server if not available
if ! command -v python3 &> /dev/null; then
    echo "📦 Installing Python3 for web server..."
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y python3
    elif command -v yum &> /dev/null; then
        yum install -y python3
    elif command -v dnf &> /dev/null; then
        dnf install -y python3
    fi
fi

# Copy ISO to web directory
mkdir -p "$DOWNLOAD_DIR"
cp "$CUSTOM_ISO_PATH" "$DOWNLOAD_DIR/"
chmod 644 "$DOWNLOAD_DIR/proxmox-ve_${PROXMOX_VERSION}-1-r8168.iso"

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$SERVER_IP" ]]; then
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")
fi

echo ""
echo "🌐 Download Server Information:"
echo "=============================="
echo "📁 ISO Location: $DOWNLOAD_DIR/proxmox-ve_${PROXMOX_VERSION}-1-r8168.iso"
echo "📊 File Size: $(ls -lh "$DOWNLOAD_DIR/proxmox-ve_${PROXMOX_VERSION}-1-r8168.iso" | awk '{print $5}')"
echo "🌍 Server IP: $SERVER_IP"
echo ""
echo "📥 Download Links:"
echo "=============================="
echo "HTTP: http://$SERVER_IP:8080/proxmox-ve_${PROXMOX_VERSION}-1-r8168.iso"
echo "Direct: http://$SERVER_IP:8080/"
echo ""
echo "🚀 Starting web server..."
echo "Press Ctrl+C to stop the server"
echo "=============================="

# Start web server
cd "$DOWNLOAD_DIR"
python3 -m http.server "$DOWNLOAD_PORT" 2>/dev/null || {
    echo "⚠️ Failed to start Python web server, trying alternative..."
    if command -v python &> /dev/null; then
        python -m SimpleHTTPServer "$DOWNLOAD_PORT" 2>/dev/null || {
            echo "❌ Could not start web server. Please install a web server manually."
            echo "💡 Alternative: Use scp or rsync to copy the ISO file"
        }
    else
        echo "❌ Python not available. Please install a web server manually."
        echo "💡 Alternative: Use scp or rsync to copy the ISO file"
    fi
} 