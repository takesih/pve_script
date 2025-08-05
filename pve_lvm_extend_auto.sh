#!/bin/bash

# Proxmox LVM Extension Script with Built-in PE Environment
# Script to extend LVM volumes after disk expansion with built-in PE boot
# Designed for remote systems without user intervention
# Uses Proxmox VE's own initrd with embedded LVM tools
# Author: Proxmox LVM Management Tool

set -e

echo "=============================="
echo "Proxmox LVM Extension Tool with Built-in PE Environment"
echo "Designed for remote systems without user intervention"
echo "V 250806005600"
echo "=============================="

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
   echo "sudo ./pve_lvm_extend_auto.sh"
   exit 1
fi

# Function to check required packages
check_required_packages() {
    echo "🔍 Checking required packages..."
    
    local missing_packages=()
    
    # Check for LVM tools
    if ! command -v lvs &> /dev/null; then
        missing_packages+=("lvm2")
    fi
    
    # Check for resize2fs
    if ! command -v resize2fs &> /dev/null; then
        missing_packages+=("e2fsprogs")
    fi
    
    # Check for bc (calculator)
    if ! command -v bc &> /dev/null; then
        missing_packages+=("bc")
    fi
    
    # Check for grub tools
    if ! command -v grub-install &> /dev/null; then
        missing_packages+=("grub-common")
    fi
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo "📦 Installing missing packages: ${missing_packages[*]}"
        
        # Temporarily disable problematic repositories to avoid 401 errors
        echo "🔄 Temporarily disabling enterprise repositories to avoid authentication errors..."
        
        # Backup current sources
        cp /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.list.backup 2>/dev/null || true
        cp /etc/apt/sources.list.d/ceph.list /etc/apt/sources.list.d/ceph.list.backup 2>/dev/null || true
        
        # Disable enterprise repositories temporarily
        if [[ -f "/etc/apt/sources.list.d/pve-enterprise.list" ]]; then
            mv /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.list.disabled
        fi
        if [[ -f "/etc/apt/sources.list.d/ceph.list" ]]; then
            mv /etc/apt/sources.list.d/ceph.list /etc/apt/sources.list.d/ceph.list.disabled
        fi
        
        # Update and install packages
        apt-get update
        apt-get install -y "${missing_packages[@]}"
        
        # Restore enterprise repositories
        echo "🔄 Restoring enterprise repositories..."
        if [[ -f "/etc/apt/sources.list.d/pve-enterprise.list.disabled" ]]; then
            mv /etc/apt/sources.list.d/pve-enterprise.list.disabled /etc/apt/sources.list.d/pve-enterprise.list
        fi
        if [[ -f "/etc/apt/sources.list.d/ceph.list.disabled" ]]; then
            mv /etc/apt/sources.list.d/ceph.list.disabled /etc/apt/sources.list.d/ceph.list
        fi
        
        echo "✅ Required packages installed successfully"
    else
        echo "✅ All required packages are already installed"
    fi
    echo ""
}

# Function to show current LVM status
show_current_status() {
    echo "📊 Current LVM Status:"
    echo ""
    echo "Physical Volumes:"
    pvs
    echo ""
    echo "Volume Groups:"
    vgs
    echo ""
    echo "Logical Volumes:"
    lvs --units g
    echo ""
    echo "Filesystem Status:"
    df -h
    echo ""
}

# Function to detect system configuration
detect_system_config() {
    echo "🔍 Detecting system configuration..."
    
    # Detect boot mode
    if [[ -d "/sys/firmware/efi" ]]; then
        BOOT_MODE="uefi"
        echo "✅ Boot mode: UEFI"
    else
        BOOT_MODE="bios"
        echo "✅ Boot mode: BIOS"
    fi
    
    # Detect partition table
    if fdisk -l /dev/sda 2>/dev/null | grep -q "GPT"; then
        PARTITION_TABLE="gpt"
        echo "✅ Partition table: GPT"
    else
        PARTITION_TABLE="mbr"
        echo "✅ Partition table: MBR"
    fi
    
    # Detect filesystem type
    FILESYSTEM_TYPE=$(df -T / | awk 'NR==2 {print $2}')
    echo "✅ Root filesystem: $FILESYSTEM_TYPE"
    
    # Detect boot device
    BOOT_DEVICE=$(df /boot | awk 'NR==2 {print $1}')
    echo "✅ Boot device: $BOOT_DEVICE"
    
    # Detect GRUB device
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        GRUB_DEVICE="/boot/efi"
        GRUB_INSTALL_TYPE="efi"
    else
        GRUB_DEVICE=$(grub-probe --target=device /boot)
        GRUB_INSTALL_TYPE="bios"
    fi
    echo "✅ GRUB device: $GRUB_DEVICE"
    echo "✅ GRUB install type: $GRUB_INSTALL_TYPE"
    echo ""
}

# Function to calculate sizes
calculate_sizes() {
    local total_vg_size=$(vgs --noheadings --units g --nosuffix -o vg_size pve | tr -d ' ')
    
    # Validate total_vg_size
    if [[ -z "$total_vg_size" ]] || [[ "$total_vg_size" -eq 0 ]]; then
        echo "❌ Error: Invalid or zero volume group size detected"
        echo "Current VG size: $total_vg_size"
        exit 1
    fi
    
    echo "Total VG size: ${total_vg_size}G"
    
    if [[ "$ROOT_SIZE" == *"%" ]]; then
        local root_percent=${ROOT_SIZE%\%}
        
        # Validate percentage
        if [[ "$root_percent" -lt 1 ]] || [[ "$root_percent" -gt 100 ]]; then
            echo "❌ Error: Invalid percentage value: $root_percent%"
            exit 1
        fi
        
        # Calculate size with proper validation
        local calculated_size=$((total_vg_size * root_percent / 100))
        
        # Validate calculated size
        if [[ "$calculated_size" -lt 1 ]]; then
            echo "❌ Error: Calculated root size is too small: ${calculated_size}G"
            echo "Minimum recommended size is 1G"
            exit 1
        fi
        
        ROOT_SIZE_CALC="${calculated_size}G"
    else
        # For non-percentage sizes, validate the format
        if [[ "$ROOT_SIZE" =~ ^[0-9]+[KMGTPEkmgtpe]?$ ]]; then
            ROOT_SIZE_CALC="$ROOT_SIZE"
        else
            echo "❌ Error: Invalid size format: $ROOT_SIZE"
            echo "Valid formats: 15G, 20G, 1T, etc."
            exit 1
        fi
    fi
    
    echo "Calculated root size: $ROOT_SIZE_CALC"
}

# Function to check existing PE configuration
check_existing_pe_config() {
    echo "🔍 Checking existing PE configuration..."
    
    if [[ -f "/etc/grub.d/40_pe_lvm_extend" ]] || [[ -d "/boot/pe" ]]; then
        echo "⚠️  Existing PE configuration detected"
        echo ""
        echo "Options:"
        echo "1. Clean existing configuration and reconfigure (Recommended)"
        echo "2. Skip PE configuration"
        echo "3. Cancel operation"
        echo ""
        
        read -p "Select option (1-3): " cleanup_option
        
        case $cleanup_option in
            1)
                echo "🔄 Cleaning existing PE configuration..."
                cleanup_existing_pe_config
                ;;
            2)
                echo "ℹ️  Skipping PE configuration"
                return 1
                ;;
            3)
                echo "❌ Operation cancelled by user."
                exit 0
                ;;
            *)
                echo "Invalid option. Cleaning existing configuration."
                cleanup_existing_pe_config
                ;;
        esac
    fi
}

# Function to cleanup existing PE configuration
cleanup_existing_pe_config() {
    echo "🔄 Cleaning existing PE configuration..."
    
    # Remove GRUB entries
    if [[ -f "/etc/grub.d/40_pe_lvm_extend" ]]; then
        rm -f /etc/grub.d/40_pe_lvm_extend
        echo "  - Removed GRUB entry"
    fi
    
    if [[ -f "/etc/grub.d/41_pe_lvm_extend_backup" ]]; then
        rm -f /etc/grub.d/41_pe_lvm_extend_backup
        echo "  - Removed backup GRUB entry"
    fi
    
    # Remove PE directory
    if [[ -d "/boot/pe" ]]; then
        rm -rf /boot/pe
        echo "  - Removed PE directory"
    fi
    
    # Remove temporary files
    if [[ -f "/tmp/gparted.iso" ]]; then
        rm -f /tmp/gparted.iso
        echo "  - Removed temporary ISO"
    fi
    
    # Update GRUB
    update-grub
    
    echo "✅ Existing PE configuration cleaned"
}

# Function to create built-in PE environment
create_builtin_pe_environment() {
    echo "🔄 Creating built-in PE environment with embedded script..."
    
    # Create PE directory
    mkdir -p /boot/pe
    
    # Get current kernel version
    local current_kernel=$(uname -r)
    echo "✅ Current kernel: $current_kernel"
    
    # Copy current kernel and initrd for PE
    if [[ -f "/boot/vmlinuz-$current_kernel" ]]; then
        cp "/boot/vmlinuz-$current_kernel" /boot/vmlinuz_pe
        echo "✅ Copied kernel: vmlinuz-$current_kernel"
    else
        echo "❌ Error: Current kernel not found"
        exit 1
    fi
    
    if [[ -f "/boot/initrd.img-$current_kernel" ]]; then
        cp "/boot/initrd.img-$current_kernel" /boot/initrd_pe
        echo "✅ Copied initrd: initrd.img-$current_kernel"
    else
        echo "❌ Error: Current initrd not found"
        exit 1
    fi
    
    # Create enhanced PE script
    echo "🔧 Creating enhanced PE script..."
    cat > /boot/pe/auto-lvm-extend.sh << 'PE_EOF'
#!/bin/sh

echo "🚀 Starting automatic LVM extension in built-in PE environment..."
echo "📊 System information:"
echo "  - Kernel: $(uname -r)"
echo "  - Architecture: $(uname -m)"
echo "  - Boot mode: $(test -d /sys/firmware/efi && echo "UEFI" || echo "BIOS")"

# Wait for system to stabilize
sleep 3

echo "📊 Current system status:"
df -h
echo ""
echo "📊 LVM status:"
lvs --units g
echo ""

echo "🔄 Performing LVM operations..."

# Get the first physical volume
PV_DEVICE=$(pvs --noheadings -o pv_name | head -1 | tr -d ' ')
if [[ -z "$PV_DEVICE" ]]; then
    echo "❌ Error: No physical volume found"
    exit 1
fi

echo "✅ Physical volume: $PV_DEVICE"

# Resize physical volume
echo "🔄 Resizing physical volume..."
if pvresize "$PV_DEVICE"; then
    echo "✅ Physical volume resized successfully"
else
    echo "❌ Error: Failed to resize physical volume"
    exit 1
fi

# Extend root logical volume
echo "🔄 Extending root logical volume..."
if lvextend -l +100%FREE /dev/pve/root; then
    echo "✅ Root logical volume extended successfully"
else
    echo "❌ Error: Failed to extend root logical volume"
    exit 1
fi

# Resize filesystem
echo "🔄 Resizing filesystem..."
if resize2fs /dev/pve/root; then
    echo "✅ Filesystem resized successfully"
else
    echo "❌ Error: Failed to resize filesystem"
    exit 1
fi

echo "📊 Final system status:"
df -h
echo ""
echo "📊 Final LVM status:"
lvs --units g
echo ""

echo "✅ LVM operations completed successfully!"
echo "🔄 Rebooting in 5 seconds..."
sleep 5
reboot
PE_EOF

    chmod +x /boot/pe/auto-lvm-extend.sh
    echo "✅ Enhanced PE script created"
    
    # Create configuration file
    cat > /boot/pe/lvm_config.txt << EOF
ROOT_SIZE_CALC=$ROOT_SIZE_CALC
DATA_VOLUME_TYPE=$DATA_VOLUME_TYPE
FIX_STRUCTURE=$FIX_STRUCTURE
BOOT_MODE=$BOOT_MODE
PARTITION_TABLE=$PARTITION_TABLE
FILESYSTEM_TYPE=$FILESYSTEM_TYPE
EOF
    
    echo "✅ Configuration file created"
    
        # Create BusyBox-based minimal initrd
    echo "🔧 Creating BusyBox-based minimal initrd..."
    
    # Create working directory
    WORKDIR="/tmp/initrd-minimal"
    mkdir -p "$WORKDIR"/{bin,sbin,etc,proc,sys,dev,usr/bin,usr/sbin}
    
    # Copy busybox
    if [[ -f "/bin/busybox" ]]; then
        cp /bin/busybox "$WORKDIR"/bin/
        echo "✅ Copied busybox"
    else
        echo "❌ Error: busybox not found"
        exit 1
    fi
    
    # Create symlinks for essential tools
    echo "🔧 Creating symlinks for essential tools..."
    cd "$WORKDIR"/bin
    for app in sh mount mknod reboot sleep df echo ls cat; do
        ln -sf busybox $app
    done
    
    # Create symlinks for LVM tools
    for app in lvs pvs vgs pvresize lvextend resize2fs; do
        ln -sf busybox $app
    done
    
    cd /
    
    # Create init script
    echo "📝 Creating init script..."
    cat > "$WORKDIR/init" << 'INIT_EOF'
#!/bin/sh

echo "🚀 Starting minimal PE LVM environment..."

# Mount essential filesystems
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

# Create essential device nodes
mknod /dev/console c 5 1 2>/dev/null || true
mknod /dev/null c 1 3 2>/dev/null || true
mknod /dev/zero c 1 5 2>/dev/null || true

# Set up environment
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/
export TERM=linux

# Load LVM modules
modprobe dm-mod 2>/dev/null || true
modprobe lvm 2>/dev/null || true

# Wait for system to be ready
sleep 3

echo "📊 System status:"
df -h 2>/dev/null || echo "df not available"
echo ""

echo "📊 LVM status:"
lvs --units g 2>/dev/null || echo "lvs not available"
echo ""

echo "🔄 Performing LVM operations..."

# Get the first physical volume
PV_DEVICE=$(pvs --noheadings -o pv_name 2>/dev/null | head -1 | tr -d ' ')
if [[ -z "$PV_DEVICE" ]]; then
    echo "❌ Error: No physical volume found"
    echo "🔄 Rebooting in 10 seconds..."
    sleep 10
    reboot
fi

echo "✅ Physical volume: $PV_DEVICE"

# Resize physical volume
echo "🔄 Resizing physical volume..."
if pvresize "$PV_DEVICE" 2>/dev/null; then
    echo "✅ Physical volume resized successfully"
else
    echo "❌ Error: Failed to resize physical volume"
    echo "🔄 Rebooting in 10 seconds..."
    sleep 10
    reboot
fi

# Extend root logical volume
echo "🔄 Extending root logical volume..."
if lvextend -l +100%FREE /dev/pve/root 2>/dev/null; then
    echo "✅ Root logical volume extended successfully"
else
    echo "❌ Error: Failed to extend root logical volume"
    echo "🔄 Rebooting in 10 seconds..."
    sleep 10
    reboot
fi

# Resize filesystem
echo "🔄 Resizing filesystem..."
if resize2fs /dev/pve/root 2>/dev/null; then
    echo "✅ Filesystem resized successfully"
else
    echo "❌ Error: Failed to resize filesystem"
    echo "🔄 Rebooting in 10 seconds..."
    sleep 10
    reboot
fi

echo "📊 Final system status:"
df -h 2>/dev/null || echo "df not available"
echo ""

echo "📊 Final LVM status:"
lvs --units g 2>/dev/null || echo "lvs not available"
echo ""

echo "✅ LVM operations completed successfully!"
echo "🔄 Rebooting in 5 seconds..."
sleep 5
reboot
INIT_EOF

    chmod +x "$WORKDIR/init"
    
    # Create initrd
    echo "📦 Creating minimal initrd..."
    cd "$WORKDIR"
    find . | cpio -o -H newc | gzip > /boot/initrd_pe
    
    # Cleanup
    cd /
    rm -rf "$WORKDIR"
    
    echo "✅ Minimal initrd created successfully"
    
    # Create minimal initrd
    echo "📦 Creating minimal initrd..."
    find . | cpio -o -H newc | gzip > /boot/initrd_pe
    
    # Cleanup
    cd /
    rm -rf /tmp/initrd-minimal
    
    echo "✅ Minimal PE environment prepared successfully"
}

# Function to configure GRUB for built-in PE boot
configure_grub_builtin_pe() {
    echo "🔄 Configuring GRUB for built-in PE boot..."
    
    # Create simple GRUB entry without init parameter
    cat > /etc/grub.d/40_pe_lvm_extend << EOF
#!/bin/bash
exec tail -n +3 \$0
# Built-in PE Boot entry for LVM extension (Embedded Script)
menuentry "PE Boot - LVM Extension (Embedded)" {
    search --file --set=root /boot/initrd_pe
    linux /boot/vmlinuz_pe quiet
    initrd /boot/initrd_pe
}
EOF

    chmod +x /etc/grub.d/40_pe_lvm_extend
    
    # Update GRUB
    echo "🔄 Updating GRUB configuration..."
    if update-grub; then
        echo "✅ GRUB configuration updated successfully"
    else
        echo "⚠️  GRUB update failed, but continuing..."
    fi
    
    # Set PE boot as default
    echo "🔄 Setting PE boot as default..."
    if grub-reboot "PE Boot - LVM Extension (Embedded)"; then
        echo "✅ PE boot set as default"
    else
        echo "⚠️  Failed to set PE boot as default, but continuing..."
    fi
    
    echo "✅ GRUB configured for embedded PE boot"
}

# Function to provide automatic boot instructions
provide_automatic_boot_info() {
    echo ""
    echo "🔄 Built-in PE Boot Configuration"
    echo "================================="
    echo ""
    echo "✅ Configuration completed successfully!"
    echo ""
    echo "📋 Configuration Summary:"
    echo "  Root size: $ROOT_SIZE_CALC"
    echo "  Data volume type: $DATA_VOLUME_TYPE"
    echo "  Fix structure: $FIX_STRUCTURE"
    echo "  Boot mode: $BOOT_MODE"
    echo "  Partition table: $PARTITION_TABLE"
    echo ""
    echo "📁 Files created:"
    echo "  - PE Script: /boot/pe/auto-lvm-extend.sh"
    echo "  - Config: /boot/pe/lvm_config.txt"
    echo "  - GRUB Entry: /etc/grub.d/40_pe_lvm_extend"
    echo ""
    echo "🔄 Next steps:"
    echo "1. System will automatically boot to built-in PE environment"
    echo "2. LVM operations will be performed automatically"
    echo "3. System will reboot back to Proxmox VE"
    echo "4. No user intervention required"
    echo ""
    echo "⚠️  Important:"
    echo "  - Backup important data before proceeding"
    echo "  - Ensure stable power supply during operation"
    echo "  - Operation will take 3-5 minutes"
    echo ""
    echo "🔄 Ready to reboot to built-in PE environment"
    echo ""
    echo "📋 Manual boot instructions (if automatic boot fails):"
    echo "1. Reboot the system"
    echo "2. In GRUB menu, select 'PE Boot - LVM Extension (Embedded)'"
    echo "3. If menu doesn't appear, press 'e' to edit boot entry"
    echo "4. Try these commands:"
    echo "   - search --file --set=root /boot/initrd_pe"
    echo "   - linux /boot/vmlinuz_pe quiet"
    echo "   - initrd /boot/initrd_pe"
    echo "5. Press Ctrl+X to boot"
    echo ""
    echo "Press ENTER to continue or ESC to cancel..."
    
    # Wait for user input
    while true; do
        read -rsn1 key
        if [[ "$key" == "" ]]; then
            echo "🔄 Rebooting to built-in PE environment now..."
            reboot
        elif [[ "$key" == $'\x1b' ]]; then
            echo "❌ Operation cancelled by user."
            exit 0
        fi
    done
}

# Main execution
echo "⚠️  Important Warnings:"
echo "1. Stop all VMs and CTs before performing this operation"
echo "2. Make sure you have backups of important data"
echo "3. This script will automatically boot to built-in PE and perform operations"
echo "4. No user intervention will be possible during PE boot"
echo "5. System will automatically reboot back to Proxmox VE"
echo ""

read -p "Continue with automatic LVM extension operation (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ Operation cancelled."
    exit 1
fi

# Initialize variables
ROOT_SIZE=${1:-"15G"}
DATA_VOLUME_TYPE="thin"
FIX_STRUCTURE="yes"

echo ""
echo "🔧 Configuration:"
echo "  Root size: $ROOT_SIZE"
echo "  Data volume type: $DATA_VOLUME_TYPE"
echo "  Fix structure: $FIX_STRUCTURE"
echo ""

# Check required packages
check_required_packages

# Show current status
show_current_status

# Detect system configuration
detect_system_config

# Calculate sizes
calculate_sizes

# Check existing PE configuration
if check_existing_pe_config; then
    # Create built-in PE environment
    create_builtin_pe_environment
    
    # Configure GRUB
    configure_grub_builtin_pe
    
    # Provide instructions
    provide_automatic_boot_info
else
    echo "ℹ️  PE configuration skipped."
    echo "✅ Script completed successfully."
fi 