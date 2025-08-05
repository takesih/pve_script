#!/bin/bash

# Proxmox LVM Extension Script with Automatic PE Boot
# Script to extend LVM volumes after disk expansion with automatic PE boot
# Designed for remote systems without user intervention
# Based on Proxmox forum: https://forum.proxmox.com/threads/extend-local-lvm-proxmox.133478/#post-589215
# Version: 2025-08-05 234855
# Author: Proxmox LVM Management Tool

set -e

echo "=============================="
echo "Proxmox LVM Extension Tool with Automatic PE Boot"
echo "Designed for remote systems without user intervention"
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
    
    # Check for aria2c (for fast downloads)
    if ! command -v aria2c &> /dev/null; then
        missing_packages+=("aria2")
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
    echo "Disk Usage:"
    df -h /
    echo ""
}

# Function to collect all configuration
collect_configuration() {
    echo "🔧 Configuration Collection"
    echo "=========================="
    echo ""
    
    # Get total VG size
    local total_vg_size=$(vgs --noheadings --units g --nosuffix -o vg_size pve | tr -d ' ')
    echo "Total Volume Group size: ${total_vg_size}GB"
    echo ""
    
    # Get current usage
    local current_usage=$(df / | awk 'NR==2 {print $3}')
    local current_usage_gb=$((current_usage / 1024 / 1024))
    echo "Current root usage: ${current_usage_gb}GB"
    echo ""
    
    echo "Size Configuration Options:"
    echo "1. Root: 15GB, Data: remaining space (Recommended)"
    echo "2. Custom sizes"
    echo "3. Percentage based (Root: 20%, Data: 80%)"
    echo ""
    
    read -p "Select option (1-3): " size_option
    
    case $size_option in
        1)
            ROOT_SIZE="15G"
            DATA_SIZE="remaining"
            echo "Selected: Root 15GB, Data remaining space"
            ;;
        2)
            echo "Minimum recommended root size: ${current_usage_gb}GB"
            read -p "Enter root volume size (e.g., 20G): " ROOT_SIZE
            echo "Selected: Root ${ROOT_SIZE}, Data remaining space"
            ;;
        3)
            ROOT_SIZE="20%"
            DATA_SIZE="80%"
            echo "Selected: Root 20%, Data 80%"
            ;;
        *)
            echo "Invalid option. Using recommended configuration."
            ROOT_SIZE="15G"
            DATA_SIZE="remaining"
            ;;
    esac
    
    # Calculate actual sizes
    calculate_sizes
    
    echo ""
    echo "Data Volume Configuration:"
    echo "1. Create LVM-thin pool (Recommended for Proxmox)"
    echo "2. Create regular LVM volume"
    echo "3. Skip data volume creation"
    echo ""
    
    read -p "Select data volume option (1-3): " data_option
    
    case $data_option in
        1)
            DATA_VOLUME_TYPE="thin"
            echo "Selected: LVM-thin pool"
            ;;
        2)
            DATA_VOLUME_TYPE="regular"
            echo "Selected: Regular LVM volume"
            ;;
        3)
            DATA_VOLUME_TYPE="skip"
            echo "Selected: Skip data volume creation"
            ;;
        *)
            echo "Invalid option. Using LVM-thin pool."
            DATA_VOLUME_TYPE="thin"
            ;;
    esac
    
    # Check if data volume exists and needs structure fix
    if [[ "$DATA_VOLUME_TYPE" != "skip" ]]; then
        if lvs /dev/pve/data >/dev/null 2>&1; then
            echo ""
            echo "Existing data volume detected. Structure options:"
            echo "1. Fix structure if needed (Recommended)"
            echo "2. Keep existing structure"
            echo "3. Skip data volume operations"
            echo ""
            
            read -p "Select option (1-3): " structure_option
            
            case $structure_option in
                1)
                    FIX_STRUCTURE="yes"
                    echo "Selected: Fix structure if needed"
                    ;;
                2)
                    FIX_STRUCTURE="no"
                    echo "Selected: Keep existing structure"
                    ;;
                3)
                    DATA_VOLUME_TYPE="skip"
                    echo "Selected: Skip data volume operations"
                    ;;
                *)
                    echo "Invalid option. Fixing structure if needed."
                    FIX_STRUCTURE="yes"
                    ;;
            esac
        else
            FIX_STRUCTURE="no"
        fi
    else
        FIX_STRUCTURE="no"
    fi
}

# Function to calculate sizes
calculate_sizes() {
    local total_vg_size=$(vgs --noheadings --units g --nosuffix -o vg_size pve | tr -d ' ')
    
    if [[ "$ROOT_SIZE" == *"%" ]]; then
        local root_percent=${ROOT_SIZE%\%}
        ROOT_SIZE_CALC=$((total_vg_size * root_percent / 100))G
    else
        ROOT_SIZE_CALC="$ROOT_SIZE"
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
                echo "❌ Operation cancelled."
                exit 1
                ;;
            *)
                echo "Invalid option. Cleaning existing configuration..."
                cleanup_existing_pe_config
                ;;
        esac
    else
        echo "✅ No existing PE configuration found"
    fi
}

# Function to cleanup existing PE configuration
cleanup_existing_pe_config() {
    echo "🔄 Cleaning existing PE configuration..."
    
    # Remove GRUB entry
    if [[ -f "/etc/grub.d/40_pe_lvm_extend" ]]; then
        rm -f /etc/grub.d/40_pe_lvm_extend
        echo "  - Removed GRUB entry"
    fi
    
    # Remove PE directory
    if [[ -d "/boot/pe" ]]; then
        rm -rf /boot/pe
        echo "  - Removed PE directory"
    fi
    
    # Remove temporary files
    if [[ -f "/tmp/tinycore.iso" ]]; then
        rm -f /tmp/tinycore.iso
        echo "  - Removed temporary ISO"
    fi
    
    # Update GRUB
    update-grub
    
    echo "✅ Existing PE configuration cleaned"
}

# Function to download and prepare Linux PE
prepare_linux_pe() {
    echo "🔄 Preparing Tiny Core Linux PE for automatic boot..."
    
    # Create PE directory
    mkdir -p /boot/pe
    
    # Download Tiny Core Linux with parallel download for speed
    echo "📥 Downloading Tiny Core Linux with parallel download..."
    
    # Use aria2c if available, otherwise use wget with resume
    if command -v aria2c &> /dev/null; then
        echo "Using aria2c for fast parallel download..."
        aria2c -x 16 -s 16 -o tinycore.iso "http://tinycorelinux.net/12.x/x86_64/release/TinyCorePure64-12.0.iso" -d /tmp/
    else
        echo "Using wget with resume capability..."
        wget -c -O /tmp/tinycore.iso "http://tinycorelinux.net/12.x/x86_64/release/TinyCorePure64-12.0.iso"
    fi
    
    # Mount ISO and extract kernel and initrd
    echo "🔧 Extracting PE components..."
    
    # Unmount if already mounted
    if mountpoint -q /mnt; then
        echo "Unmounting existing mount..."
        umount /mnt 2>/dev/null || true
    fi
    
    mount -o loop /tmp/tinycore.iso /mnt
    
    # Copy kernel and initrd
    cp /mnt/boot/vmlinuz64 /boot/pe/vmlinuz
    cp /mnt/boot/corepure64.gz /boot/pe/initrd
    
    # Create custom initrd with LVM tools
    echo "🔧 Creating custom initrd with LVM tools..."
    mkdir -p /tmp/initrd-extract
    cd /tmp/initrd-extract
    zcat /boot/pe/initrd | cpio -idmv
    
    # Add LVM tools to initrd (Tiny Core already has basic LVM tools)
    # Copy additional tools if needed
    if [[ -f "/sbin/lvs" ]]; then
        cp /sbin/lvs /tmp/initrd-extract/sbin/ 2>/dev/null || true
    fi
    if [[ -f "/sbin/vgs" ]]; then
        cp /sbin/vgs /tmp/initrd-extract/sbin/ 2>/dev/null || true
    fi
    if [[ -f "/sbin/pvs" ]]; then
        cp /sbin/pvs /tmp/initrd-extract/sbin/ 2>/dev/null || true
    fi
    if [[ -f "/sbin/lvcreate" ]]; then
        cp /sbin/lvcreate /tmp/initrd-extract/sbin/ 2>/dev/null || true
    fi
    if [[ -f "/sbin/lvextend" ]]; then
        cp /sbin/lvextend /tmp/initrd-extract/sbin/ 2>/dev/null || true
    fi
    if [[ -f "/sbin/pvresize" ]]; then
        cp /sbin/pvresize /tmp/initrd-extract/sbin/ 2>/dev/null || true
    fi
    if [[ -f "/sbin/resize2fs" ]]; then
        cp /sbin/resize2fs /tmp/initrd-extract/sbin/ 2>/dev/null || true
    fi
    if [[ -f "/sbin/mkfs.ext4" ]]; then
        cp /sbin/mkfs.ext4 /tmp/initrd-extract/sbin/ 2>/dev/null || true
    fi
    if [[ -f "/usr/bin/bc" ]]; then
        cp /usr/bin/bc /tmp/initrd-extract/usr/bin/ 2>/dev/null || true
    fi
    
    # Repack initrd
    find . | cpio -o -H newc | gzip > /boot/pe/initrd-custom
    
    # Cleanup
    cd /
    umount /mnt
    rm -rf /tmp/initrd-extract
    
    echo "✅ Tiny Core Linux PE prepared successfully (Size: ~16MB)"
}

# Function to create automatic PE boot script
create_pe_boot_script() {
    echo "🔄 Creating automatic PE boot script..."
    
    cat > /boot/pe/auto-lvm-extend.sh << 'EOF'
#!/bin/sh

# Auto LVM Extension Script for PE Boot
echo "🚀 Starting automatic LVM extension in PE environment..."

# Wait for system to be ready
sleep 10

# Load configuration from saved file
if [[ -f "/boot/pe/lvm_config.txt" ]]; then
    source /boot/pe/lvm_config.txt
    echo "✅ Configuration loaded"
else
    echo "❌ Configuration file not found"
    echo "🔄 Attempting to continue with default settings..."
    
    # Set default values
    ROOT_SIZE_CALC="15G"
    DATA_VOLUME_TYPE="thin"
fi

# Show current system status
echo "📊 Current system status:"
df -h
echo ""
lvs --units g
echo ""

# Perform LVM operations
echo "🔄 Performing LVM extension operations..."

# Resize physical volume
echo "📏 Resizing physical volume..."
if pvresize /dev/nvme0n1p3; then
    echo "✅ Physical volume resized successfully"
else
    echo "⚠️  Physical volume resize failed, continuing..."
fi

# Extend root volume
echo "📏 Extending root volume to $ROOT_SIZE_CALC..."
if lvextend -L "$ROOT_SIZE_CALC" /dev/pve/root; then
    echo "✅ Root volume extended successfully"
else
    echo "❌ Root volume extension failed"
    exit 1
fi

# Resize filesystem
echo "📏 Resizing filesystem..."
if resize2fs /dev/pve/root; then
    echo "✅ Filesystem resized successfully"
else
    echo "❌ Filesystem resize failed"
    exit 1
fi

# Handle data volume
if [[ "$DATA_VOLUME_TYPE" == "thin" ]]; then
    echo "🔄 Creating LVM-thin data volume..."
    
    # Check if data volume exists
    if ! lvs /dev/pve/data &>/dev/null; then
        echo "📏 Creating thin pool..."
        local free_space=$(vgs --noheadings --units g --nosuffix -o vg_free pve | tr -d ' ')
        
        # Ensure free_space is a valid number
        if [[ ! "$free_space" =~ ^[0-9]+$ ]]; then
            echo "❌ Invalid free space: $free_space"
            exit 1
        fi
        
        # Calculate pool size (95% of free space)
        local pool_size=$((free_space * 95 / 100))
        
        echo "Free space: ${free_space}G"
        echo "Pool size: ${pool_size}G"
        
        if lvcreate -L "${pool_size}G" -T pve/data; then
            echo "✅ Thin pool created successfully"
        else
            echo "❌ Thin pool creation failed"
            exit 1
        fi
        
        echo "📏 Creating thin volume..."
        local thin_pool_size=$(lvs --noheadings --units g --nosuffix -o lv_size /dev/pve/data | tr -d ' ')
        
        # Ensure thin_pool_size is a valid number
        if [[ ! "$thin_pool_size" =~ ^[0-9]+$ ]]; then
            echo "❌ Invalid thin pool size: $thin_pool_size"
            exit 1
        fi
        
        # Calculate thin volume size (95% of pool size)
        local thin_volume_size=$((thin_pool_size * 95 / 100))
        
        echo "Thin pool size: ${thin_pool_size}G"
        echo "Thin volume size: ${thin_volume_size}G"
        
        if lvcreate -V "${thin_volume_size}G" -T pve/data -n data; then
            echo "✅ Thin volume created successfully"
        else
            echo "❌ Thin volume creation failed"
            exit 1
        fi
        
        echo "📏 Formatting thin volume..."
        if mkfs.ext4 /dev/pve/data; then
            echo "✅ Thin volume formatted successfully"
        else
            echo "❌ Thin volume formatting failed"
            exit 1
        fi
        
        echo "📏 Mounting thin volume..."
        mkdir -p /mnt/pve/data
        echo "/dev/pve/data /mnt/pve/data ext4 defaults 0 2" >> /etc/fstab
        mount /dev/pve/data /mnt/pve/data
        
        echo "✅ LVM-thin data volume created successfully"
    else
        echo "✅ Data volume already exists"
    fi
elif [[ "$DATA_VOLUME_TYPE" == "regular" ]]; then
    echo "🔄 Creating regular LVM data volume..."
    
    if ! lvs /dev/pve/data &>/dev/null; then
        local free_space=$(vgs --noheadings --units g --nosuffix -o vg_free pve | tr -d ' ')
        
        # Ensure free_space is a valid number
        if [[ ! "$free_space" =~ ^[0-9]+$ ]]; then
            echo "❌ Invalid free space: $free_space"
            exit 1
        fi
        
        echo "Free space: ${free_space}G"
        
        if lvcreate -L "${free_space}G" -n data pve; then
            echo "✅ Regular LVM volume created successfully"
        else
            echo "❌ Regular LVM volume creation failed"
            exit 1
        fi
        
        if mkfs.ext4 /dev/pve/data; then
            echo "✅ Data volume formatted successfully"
        else
            echo "❌ Data volume formatting failed"
            exit 1
        fi
        
        mkdir -p /mnt/pve/data
        echo "/dev/pve/data /mnt/pve/data ext4 defaults 0 2" >> /etc/fstab
        mount /dev/pve/data /mnt/pve/data
        
        echo "✅ Regular LVM data volume created successfully"
    else
        echo "✅ Data volume already exists"
    fi
fi

echo "✅ LVM extension completed successfully"
echo "🔄 Rebooting back to Proxmox VE..."

# Wait a moment before reboot
sleep 5

# Reboot to Proxmox VE
reboot
EOF

    chmod +x /boot/pe/auto-lvm-extend.sh
    echo "✅ PE boot script created successfully"
}
            lvcreate -V "${thin_volume_size}G" -T pve/data -n data
            
            mkfs.ext4 /dev/pve/data
            log_message "LVM-thin data volume created successfully"
        else
            log_message "Data volume already exists, extending..."
            lvextend -l +100%FREE /dev/pve/data
            resize2fs /dev/pve/data
        fi
    elif [[ "$DATA_VOLUME_TYPE" == "regular" ]]; then
        log_message "Creating regular LVM data volume..."
        
        if ! lvs /dev/pve/data >/dev/null 2>&1; then
            local free_space=$(vgs --noheadings --units g --nosuffix -o vg_free pve | tr -d ' ')
            local data_size=$((free_space * 95 / 100))
            
            lvcreate -L "${data_size}G" -n data pve
            mkfs.ext4 /dev/pve/data
            log_message "Regular LVM data volume created successfully"
        else
            log_message "Data volume already exists, extending..."
            lvextend -l +100%FREE /dev/pve/data
            resize2fs /dev/pve/data
        fi
    fi
fi

log_message "LVM extension operations completed successfully!"

# Show final status
echo ""
echo "Final LVM status:"
lvs --units g

echo ""
echo "✅ Automatic PE operations completed!"
echo "Rebooting to Proxmox VE in 10 seconds..."

# Wait and reboot to PVE
sleep 10
reboot
EOF

    chmod +x /boot/pe/auto-lvm-extend.sh
    
    # Create configuration file
    cat > /boot/pe/lvm_config.txt << EOF
ROOT_SIZE_CALC="$ROOT_SIZE_CALC"
DATA_VOLUME_TYPE="$DATA_VOLUME_TYPE"
FIX_STRUCTURE="$FIX_STRUCTURE"
CREATED_DATE="$(date)"
EOF
    
    echo "✅ Automatic PE boot script created successfully!"
}

# Function to detect system configuration
detect_system_config() {
    echo "🔍 Detecting system configuration..."
    
    # Detect disk and partition information
    local boot_disk=$(df /boot | awk 'NR==2 {print $1}' | sed 's/[0-9]*$//')
    local boot_partition=$(df /boot | awk 'NR==2 {print $1}' | sed 's/.*\([0-9]*\)$/\1/')
    
    echo "Boot disk: $boot_disk"
    echo "Boot partition: $boot_partition"
    
    # Detect partition table type
    local partition_table=$(fdisk -l "$boot_disk" 2>/dev/null | grep "Disklabel type" | awk '{print $3}')
    echo "Partition table: $partition_table"
    
    # Detect filesystem type
    local filesystem_type=$(df -T /boot | awk 'NR==2 {print $2}')
    echo "Filesystem type: $filesystem_type"
    
    # Store configuration
    BOOT_DISK="$boot_disk"
    BOOT_PARTITION="$boot_partition"
    PARTITION_TABLE="$partition_table"
    FILESYSTEM_TYPE="$filesystem_type"
    
    echo "✅ System configuration detected"
}

# Function to generate appropriate GRUB configuration
generate_grub_config() {
    echo "🔄 Generating GRUB configuration..."
    
    # Get current boot device information
    local boot_device=$(df /boot | awk 'NR==2 {print $1}')
    local boot_disk=$(echo "$boot_device" | sed 's/[0-9]*$//')
    local boot_partition=$(echo "$boot_device" | sed 's/.*\([0-9]*\)$/\1/')
    
    echo "Boot device: $boot_device"
    echo "Boot disk: $boot_disk"
    echo "Boot partition: $boot_partition"
    
    # Detect actual GRUB device mapping
    local grub_device=""
    local grub_root=""
    
    # Try to detect the actual GRUB device
    if [[ -f "/boot/grub/device.map" ]]; then
        grub_device=$(cat /boot/grub/device.map | grep "$boot_disk" | awk '{print $1}')
        echo "GRUB device map: $grub_device"
    fi
    
    # Determine GRUB root specification based on system configuration
    if [[ "$PARTITION_TABLE" == "gpt" ]]; then
        if [[ -n "$grub_device" ]]; then
            grub_root="${grub_device},gpt1"
        else
            grub_root="(hd0,gpt1)"
        fi
    else
        if [[ -n "$grub_device" ]]; then
            grub_root="${grub_device},1"
        else
            grub_root="(hd0,1)"
        fi
    fi
    
    echo "Using GRUB root: $grub_root"
    
    # Create GRUB entry for PE boot with more robust configuration
    cat > /etc/grub.d/40_pe_lvm_extend << EOF
#!/bin/bash
exec tail -n +3 \$0
# PE Boot entry for LVM extension
menuentry "PE Boot - LVM Extension" {
    insmod ext2
    insmod ext4
    insmod part_gpt
    insmod part_msdos
    insmod lvm
    set root=$grub_root
    linux /pe/vmlinuz root=/dev/ram0 init=/boot/pe/auto-lvm-extend.sh quiet splash
    initrd /pe/initrd-custom
}
EOF

    chmod +x /etc/grub.d/40_pe_lvm_extend
    
    # Update GRUB
    update-grub
    
    # Set PE boot as default for next boot
    grub-reboot "PE Boot - LVM Extension"
    
    echo "✅ GRUB configured for automatic PE boot"
    echo "  Root specification: $grub_root"
    echo "  Partition table: $PARTITION_TABLE"
    echo "  Filesystem: $FILESYSTEM_TYPE"
    echo "  Boot device: $boot_device"
    echo "  GRUB device: $grub_device"
    
    # Show current GRUB configuration for debugging
    echo ""
    echo "🔍 Current GRUB configuration:"
    grep -A 10 -B 5 "PE Boot" /boot/grub/grub.cfg 2>/dev/null || echo "GRUB config not found"
}

# Function to provide automatic boot instructions
provide_automatic_boot_info() {
    echo ""
    echo "🔄 Automatic PE Boot Configuration"
    echo "================================="
    echo ""
    echo "✅ Configuration completed successfully!"
    echo ""
    echo "📋 Configuration Summary:"
    echo "  Root size: $ROOT_SIZE_CALC"
    echo "  Data volume type: $DATA_VOLUME_TYPE"
    echo "  Fix structure: $FIX_STRUCTURE"
    echo ""
    echo "📁 Files created:"
    echo "  - PE Script: /boot/pe/auto-lvm-extend.sh"
    echo "  - Config: /boot/pe/lvm_config.txt"
    echo "  - GRUB Entry: /etc/grub.d/40_pe_lvm_extend"
    echo ""
    echo "🔄 Next steps:"
    echo "1. System will automatically boot to PE environment"
    echo "2. LVM operations will be performed automatically"
    echo "3. System will reboot back to Proxmox VE"
    echo "4. No user intervention required"
    echo ""
    echo "⚠️  Important:"
    echo "  - Backup important data before proceeding"
    echo "  - Ensure stable power supply during operation"
    echo "  - Operation will take 5-10 minutes"
    echo ""
    echo "🔄 Rebooting to PE environment in 30 seconds..."
    echo "Press Ctrl+C to cancel"
    
    # Countdown
    for i in {30..1}; do
        echo -n "Rebooting in $i seconds... "
        sleep 1
        echo ""
    done
    
    echo "🔄 Rebooting to PE environment now..."
    reboot
}

# Main execution
echo "⚠️  Important Warnings:"
echo "1. Stop all VMs and CTs before performing this operation"
echo "2. Make sure you have backups of important data"
echo "3. This script will automatically boot to PE and perform operations"
echo "4. No user intervention will be possible during PE boot"
echo "5. System will automatically reboot back to Proxmox VE"
echo ""

read -p "Continue with automatic LVM extension operation (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ Operation cancelled."
    exit 1
fi

# Check and install required packages
check_required_packages

# Show current status
show_current_status

# Collect all configuration
collect_configuration

echo ""
echo "Operation Summary:"
echo "  Root volume will be extended to: $ROOT_SIZE_CALC"
echo "  Data volume type: $DATA_VOLUME_TYPE"
echo "  Fix structure: $FIX_STRUCTURE"
echo ""

read -p "Proceed with automatic PE boot configuration (y/N): " final_confirm
if [[ "$final_confirm" != "y" && "$final_confirm" != "Y" ]]; then
    echo "❌ Operation cancelled."
    exit 1
fi

# Check existing PE configuration
if check_existing_pe_config; then
    # Prepare Linux PE
    prepare_linux_pe
    
    # Create automatic PE boot script
    create_pe_boot_script
    
    # Detect system configuration
    detect_system_config
    
    # Configure GRUB for automatic PE boot
    generate_grub_config
else
    echo "ℹ️  PE configuration skipped"
fi

# Provide automatic boot information
provide_automatic_boot_info

echo ""
echo "🎉 Automatic PE boot configuration completed!" 