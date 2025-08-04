#!/bin/bash

# Proxmox LVM Extension Script with Automatic PE Boot
# Script to extend LVM volumes after disk expansion with automatic PE boot
# Designed for remote systems without user intervention
# Based on Proxmox forum: https://forum.proxmox.com/threads/extend-local-lvm-proxmox.133478/#post-589215
# Version: 2025-01-08
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
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo "📦 Installing missing packages: ${missing_packages[*]}"
        apt-get update
        apt-get install -y "${missing_packages[@]}"
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
    local current_usage_gb=$(echo "scale=1; $current_usage / 1024 / 1024" | bc)
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
        ROOT_SIZE_CALC=$(echo "scale=0; $total_vg_size * $root_percent / 100" | bc)G
    else
        ROOT_SIZE_CALC="$ROOT_SIZE"
    fi
    
    echo "Calculated root size: $ROOT_SIZE_CALC"
}

# Function to download and prepare Linux PE
prepare_linux_pe() {
    echo "🔄 Preparing Linux PE for automatic boot..."
    
    # Create PE directory
    mkdir -p /boot/pe
    
    # Download Ubuntu Live ISO (minimal version)
    echo "📥 Downloading Ubuntu Live ISO..."
    wget -O /tmp/ubuntu-live.iso "https://releases.ubuntu.com/22.04.3/ubuntu-22.04.3-desktop-amd64.iso"
    
    # Mount ISO and extract kernel and initrd
    echo "🔧 Extracting PE components..."
    mount -o loop /tmp/ubuntu-live.iso /mnt
    
    # Copy kernel and initrd
    cp /mnt/casper/vmlinuz /boot/pe/
    cp /mnt/casper/initrd /boot/pe/
    
    # Create custom initrd with LVM tools
    echo "🔧 Creating custom initrd with LVM tools..."
    mkdir -p /tmp/initrd-extract
    cd /tmp/initrd-extract
    zcat /boot/pe/initrd | cpio -idmv
    
    # Add LVM tools to initrd
    cp /sbin/lvs /tmp/initrd-extract/sbin/
    cp /sbin/vgs /tmp/initrd-extract/sbin/
    cp /sbin/pvs /tmp/initrd-extract/sbin/
    cp /sbin/lvcreate /tmp/initrd-extract/sbin/
    cp /sbin/lvextend /tmp/initrd-extract/sbin/
    cp /sbin/pvresize /tmp/initrd-extract/sbin/
    cp /sbin/resize2fs /tmp/initrd-extract/sbin/
    cp /sbin/mkfs.ext4 /tmp/initrd-extract/sbin/
    cp /sbin/bc /tmp/initrd-extract/sbin/
    
    # Repack initrd
    find . | cpio -o -H newc | gzip > /boot/pe/initrd-custom
    
    # Cleanup
    cd /
    umount /mnt
    rm -rf /tmp/initrd-extract
    
    echo "✅ Linux PE prepared successfully"
}

# Function to create automatic PE boot script
create_pe_boot_script() {
    echo "🔄 Creating automatic PE boot script..."
    
    cat > /boot/pe/auto-lvm-extend.sh << 'EOF'
#!/bin/bash

# Automatic LVM Extension PE Script
# Runs automatically during PE boot

set -e

echo "=============================="
echo "Automatic LVM Extension - PE Boot"
echo "=============================="

# Configuration file
CONFIG_FILE="/boot/pe/lvm-config.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ Error: Configuration file not found"
    exit 1
fi

# Load configuration
source "$CONFIG_FILE"

echo "Configuration loaded:"
echo "  Root size: $ROOT_SIZE_CALC"
echo "  Data volume type: $DATA_VOLUME_TYPE"
echo "  Fix structure: $FIX_STRUCTURE"
echo ""

# Function to log operations
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a /var/log/auto-lvm-extend.log
}

log_message "Starting automatic LVM extension operations..."

# Activate LVM
log_message "Activating LVM..."
vgchange -ay pve

# Resize physical volume
log_message "Resizing Physical Volume..."
pvresize /dev/nvme0n1p3

# Extend root volume
log_message "Extending root volume to $ROOT_SIZE_CALC..."
lvextend -L "$ROOT_SIZE_CALC" /dev/pve/root
resize2fs /dev/pve/root

# Handle data volume
if [[ "$DATA_VOLUME_TYPE" != "skip" ]]; then
    if [[ "$FIX_STRUCTURE" == "yes" ]]; then
        log_message "Fixing data volume structure..."
        
        # Remove existing data volume if it exists
        if lvs /dev/pve/data >/dev/null 2>&1; then
            lvremove -f /dev/pve/data
        fi
        
        # Create thin pool
        local free_space=$(vgs --noheadings --units g --nosuffix -o vg_free pve | tr -d ' ')
        local pool_size=$(echo "scale=0; $free_space * 95 / 100" | bc)
        
        log_message "Creating thin pool with ${pool_size}G..."
        lvcreate -L "${pool_size}G" -T pve/data
        
        # Create thin volume
        local thin_pool_size=$(lvs --noheadings --units g --nosuffix -o lv_size /dev/pve/data | tr -d ' ')
        local thin_volume_size=$(echo "scale=0; $thin_pool_size * 95 / 100" | bc)
        
        log_message "Creating thin volume with ${thin_volume_size}G..."
        lvcreate -V "${thin_volume_size}G" -T pve/data -n data
        
        # Create filesystem
        mkfs.ext4 /dev/pve/data
        
        log_message "Data volume structure fixed successfully"
    elif [[ "$DATA_VOLUME_TYPE" == "thin" ]]; then
        log_message "Creating LVM-thin data volume..."
        
        # Check if data volume exists
        if ! lvs /dev/pve/data >/dev/null 2>&1; then
            local free_space=$(vgs --noheadings --units g --nosuffix -o vg_free pve | tr -d ' ')
            local pool_size=$(echo "scale=0; $free_space * 95 / 100" | bc)
            
            log_message "Creating thin pool with ${pool_size}G..."
            lvcreate -L "${pool_size}G" -T pve/data
            
            local thin_pool_size=$(lvs --noheadings --units g --nosuffix -o lv_size /dev/pve/data | tr -d ' ')
            local thin_volume_size=$(echo "scale=0; $thin_pool_size * 95 / 100" | bc)
            
            log_message "Creating thin volume with ${thin_volume_size}G..."
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
            local data_size=$(echo "scale=0; $free_space * 95 / 100" | bc)
            
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
    cat > /boot/pe/lvm-config.conf << EOF
ROOT_SIZE_CALC="$ROOT_SIZE_CALC"
DATA_VOLUME_TYPE="$DATA_VOLUME_TYPE"
FIX_STRUCTURE="$FIX_STRUCTURE"
CREATED_DATE="$(date)"
EOF
    
    echo "✅ Automatic PE boot script created successfully!"
}

# Function to configure GRUB for automatic PE boot
configure_grub_pe_boot() {
    echo "🔄 Configuring GRUB for automatic PE boot..."
    
    # Create GRUB entry for PE boot
    cat > /etc/grub.d/40_pe_lvm_extend << 'EOF'
#!/bin/bash
exec tail -n +3 $0
# PE Boot entry for LVM extension
menuentry "PE Boot - LVM Extension" {
    set root=(hd0,1)
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
    echo "  - Config: /boot/pe/lvm-config.conf"
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

# Prepare Linux PE
prepare_linux_pe

# Create automatic PE boot script
create_pe_boot_script

# Configure GRUB for automatic PE boot
configure_grub_pe_boot

# Provide automatic boot information
provide_automatic_boot_info

echo ""
echo "🎉 Automatic PE boot configuration completed!" 