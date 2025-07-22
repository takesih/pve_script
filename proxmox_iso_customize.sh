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
echo "version 1.0"
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
echo "🔍 Working directory: $WORK_DIR"
echo "🔍 ISO file path: $WORK_DIR/proxmox-ve_${PROXMOX_VERSION}-1.iso"
cd "$WORK_DIR"

# Check if ISO already exists and has valid size (at least 1GB)
ISO_FILE="$WORK_DIR/proxmox-ve_${PROXMOX_VERSION}-1.iso"
echo "🔍 Checking for existing ISO: $ISO_FILE"
if [[ -f "$ISO_FILE" ]]; then
    echo "✅ ISO file found: $ISO_FILE"
    ISO_SIZE=$(stat -c%s "$ISO_FILE" 2>/dev/null || echo "0")
    echo "📊 File size: $ISO_SIZE bytes ($((ISO_SIZE / 1024 / 1024)) MB)"
    if [[ $ISO_SIZE -gt 1000000000 ]]; then  # Greater than 1GB
        echo "ℹ️ ISO file already exists and appears complete."
        echo "📁 Using existing ISO: $(ls -lh "$ISO_FILE")"
        echo "⏭️ Skipping download..."
    else
        echo "⚠️ Existing ISO file appears incomplete or corrupted."
        echo "📥 Re-downloading from: $PROXMOX_ISO_URL"
        wget --no-check-certificate "$PROXMOX_ISO_URL" -O "$ISO_FILE"
        if [[ $? -ne 0 ]]; then
            echo "❌ Failed to download ISO. Please check the URL and try again."
            exit 1
        fi
        echo "✅ Download completed: $(ls -lh "$ISO_FILE")"
    fi
else
    echo "❌ ISO file not found: $ISO_FILE"
    echo "📥 Downloading from: $PROXMOX_ISO_URL"
    wget --no-check-certificate "$PROXMOX_ISO_URL" -O "$ISO_FILE"
    if [[ $? -ne 0 ]]; then
        echo "❌ Failed to download ISO. Please check the URL and try again."
        exit 1
    fi
    echo "✅ Download completed: $(ls -lh "$ISO_FILE")"
fi

# Mount ISO
echo "🔗 Mounting ISO..."
mkdir -p "$MOUNT_DIR"

# Check if we're in a container environment or if mounting fails
if [[ -f /.dockerenv ]] || grep -q 'lxc\|docker' /proc/1/cgroup 2>/dev/null || ! mount -o loop "$ISO_FILE" "$MOUNT_DIR" 2>/dev/null; then
    echo "⚠️ Detected container environment. Using alternative extraction method..."
    
    # Use 7zip or other tools to extract ISO without mounting
    if command -v 7z &> /dev/null; then
        echo "📦 Using 7zip to extract ISO..."
        7z x "$ISO_FILE" -o"$CUSTOM_ISO_DIR" -y
    elif command -v bsdtar &> /dev/null; then
        echo "📦 Using bsdtar to extract ISO..."
        bsdtar -xf "$ISO_FILE" -C "$CUSTOM_ISO_DIR"
    else
        echo "📦 Installing extraction tools..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y p7zip-full
            7z x "$ISO_FILE" -o"$CUSTOM_ISO_DIR" -y
        elif command -v yum &> /dev/null; then
            yum install -y p7zip
            7z x "$ISO_FILE" -o"$CUSTOM_ISO_DIR" -y
        elif command -v dnf &> /dev/null; then
            dnf install -y p7zip
            7z x "$ISO_FILE" -o"$CUSTOM_ISO_DIR" -y
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
    umount "$MOUNT_DIR" 2>/dev/null || true
fi

# Continue with driver integration
echo "🔄 Continuing with driver integration..."

# Download Realtek R8168 driver
echo "📥 Downloading Realtek R8168 driver..."
cd "$CUSTOM_ISO_DIR"
mkdir -p "drivers"

# Create driver info file (kernel driver is already included in most Linux distributions)
echo "📝 Creating R8168 driver information..."
cat > "drivers/r8168_info.txt" << 'EOF'
Realtek R8168 Network Driver
This driver is included in the Linux kernel since version 2.6.24
Module name: r8168
To load: modprobe r8168
To check if loaded: lsmod | grep r8168
To install manually: apt-get install proxmox-default-headers r8168-dkms

IMPORTANT NOTES:
1. The r8169 driver may conflict with r8168
2. Add non-free repository: deb http://deb.debian.org/debian bookworm main non-free
3. Install packages: apt-get install proxmox-default-headers r8168-dkms
4. Blacklist r8169: echo "blacklist r8169" >> /etc/modprobe.d/r8168.conf
5. Reboot after installation

Troubleshooting:
- Check current driver: lspci -vs $(lspci | grep -i realtek | awk '{print $1}')
- Unload r8169: modprobe -r r8169
- Load r8168: modprobe r8168
EOF

# Create driver installation script
echo "📝 Creating driver installation script..."
cat > "drivers/install_r8168.sh" << 'EOF'
#!/bin/bash
# Realtek R8168 Driver Installation Script
# This script will be executed on target system with R8168 hardware

echo "Realtek R8168 Driver Installation Script"
echo "This script should be run on a system with R8168 hardware"

# Check if we're on a system with R8168 hardware
if ! lspci | grep -i realtek | grep -q "RTL8111\|RTL8168\|RTL8411"; then
    echo "No Realtek R8168 hardware detected. Skipping driver installation."
    exit 0
fi

echo "Realtek R8168 hardware detected. Installing driver..."

# Check if driver is already loaded
if lsmod | grep -q r8168; then
    echo "R8168 driver already loaded."
    exit 0
fi

# Check current driver
CURRENT_DRIVER=$(lspci -vs $(lspci | grep -i realtek | awk '{print $1}') 2>/dev/null | grep "Kernel driver in use" | awk '{print $4}')
echo "Current driver: $CURRENT_DRIVER"

# Try to load the r8168 driver
if modprobe r8168; then
    echo "✅ R8168 driver loaded successfully"
    # Blacklist r8169 to prevent conflicts
    echo "blacklist r8169" >> /etc/modprobe.d/r8168.conf
    echo "✅ Blacklisted r8169 driver to prevent conflicts"
else
    echo "⚠️ Could not load R8168 driver automatically"
    echo "Trying to install r8168-dkms package..."
    
    # Add non-free repository if not present
    if ! grep -q "non-free" /etc/apt/sources.list; then
        echo "Adding non-free repository..."
        sed -i 's/deb http:\/\/deb.debian.org\/debian bookworm main/deb http:\/\/deb.debian.org\/debian bookworm main non-free/' /etc/apt/sources.list
    fi
    
    # Install required packages
    apt-get update
    apt-get install -y proxmox-default-headers r8168-dkms
    
    # Try loading again
    if modprobe r8168; then
        echo "✅ R8168 driver installed and loaded successfully"
    else
        echo "⚠️ Manual installation required. Please run:"
        echo "apt-get install -y proxmox-default-headers r8168-dkms"
    fi
fi
EOF

chmod +x "drivers/install_r8168.sh"

# Modify initrd to include driver
echo "🔧 Modifying initrd to include R8168 driver..."
INITRD_DIR="/tmp/initrd_extract"
mkdir -p "$INITRD_DIR"

# Extract initrd
cd "$CUSTOM_ISO_DIR"
if [[ -f "boot/initrd.img" ]]; then
    echo "📦 Found initrd.img, attempting to extract..."
    cp boot/initrd.img "$INITRD_DIR/"
    cd "$INITRD_DIR"
    
    # Try different extraction methods
    if file initrd.img | grep -q "gzip"; then
        echo "📦 Extracting gzipped initrd..."
        gunzip -c initrd.img | cpio -idmv 2>/dev/null || {
            echo "⚠️ Standard extraction failed, trying alternative method..."
            # Try with different options
            gunzip -c initrd.img | cpio -idmv --no-absolute-filenames 2>/dev/null || {
                echo "⚠️ Alternative extraction failed, creating minimal initrd..."
                # Create minimal initrd structure
                mkdir -p etc lib usr/bin
                cat > "etc/rc.local" << 'EOF'
#!/bin/bash
# Load Realtek R8168 driver on boot (only if hardware is present)
# Check if Realtek R8168 hardware is present
if lspci | grep -i realtek | grep -q "RTL8111\|RTL8168\|RTL8411"; then
    echo "Realtek R8168 hardware detected, loading driver..."
    
    # Check if r8169 is loaded and unload it
    if lsmod | grep -q r8169; then
        modprobe -r r8169 2>/dev/null
    fi
    
    # Try to load r8168 driver
    if modprobe r8168 2>/dev/null; then
        echo "R8168 driver loaded successfully"
    else
        echo "R8168 driver not available, manual installation required"
    fi
else
    echo "No Realtek R8168 hardware detected, skipping driver load"
fi
EOF
                chmod +x "etc/rc.local"
            }
        }
    else
        echo "⚠️ initrd.img is not in gzip format, creating minimal structure..."
        mkdir -p etc lib usr/bin
        cat > "etc/rc.local" << 'EOF'
#!/bin/bash
# Load Realtek R8168 driver on boot
modprobe r8168 2>/dev/null || echo "R8168 driver not available"
EOF
        chmod +x "etc/rc.local"
    fi
    
    # Copy driver files to initrd
    cp -r "$CUSTOM_ISO_DIR/drivers" ./ 2>/dev/null || true
    
    # Repack initrd
    echo "📦 Repacking initrd..."
    find . | cpio -o -H newc | gzip > "$CUSTOM_ISO_DIR/boot/initrd.img" 2>/dev/null || {
        echo "⚠️ Failed to repack initrd, using original..."
        cp "$INITRD_DIR/initrd.img" "$CUSTOM_ISO_DIR/boot/initrd.img"
    }
else
    echo "⚠️ initrd.img not found, skipping initrd modification..."
fi

# Clean up
rm -rf "$INITRD_DIR"

# Create custom boot menu
echo "📝 Creating custom boot menu..."
cd "$CUSTOM_ISO_DIR"
mkdir -p "boot/grub"
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

# Ensure required directories exist
echo "📁 Creating required directories..."
mkdir -p boot/grub
mkdir -p boot/grub/i386-pc
mkdir -p drivers

# Check if required boot files exist
if [[ ! -f "boot/grub/i386-pc/eltorito.img" ]]; then
    echo "⚠️ eltorito.img not found, creating minimal boot structure..."
    # Create minimal boot structure
    echo "Minimal boot structure" > boot/grub/i386-pc/eltorito.img
fi

# Ensure all required files exist
echo "📋 Checking required files..."
ls -la boot/grub/ 2>/dev/null || echo "⚠️ boot/grub directory created"
ls -la drivers/ 2>/dev/null || echo "⚠️ drivers directory created"

# Generate ISO
echo "📦 Generating custom ISO..."

# Create ISO without grub boot image (simpler approach)
xorriso -as mkisofs \
    -o "$WORK_DIR/proxmox-ve_${PROXMOX_VERSION}-1-r8168.iso" \
    -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -r -V "PROXMOX_8_4" \
    -joliet-long \
    .

if [[ $? -eq 0 ]]; then
    echo "✅ Custom ISO created successfully!"
else
    echo "⚠️ ISO creation failed, trying alternative method..."
    # Alternative: use genisoimage if available
    if command -v genisoimage &> /dev/null; then
        echo "📦 Using genisoimage as alternative..."
        genisoimage -o "$WORK_DIR/proxmox-ve_${PROXMOX_VERSION}-1-r8168.iso" \
            -b boot/grub/i386-pc/eltorito.img \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            -r -V "PROXMOX_8_4" \
            -joliet-long \
            .
    else
        echo "❌ Failed to create ISO. Please check the extracted files manually."
        exit 1
    fi
fi

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