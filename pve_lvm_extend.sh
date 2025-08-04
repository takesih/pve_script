#!/bin/bash

# Proxmox LVM Extension Script
# Script to extend LVM volumes after disk expansion
# Based on Proxmox forum: https://forum.proxmox.com/threads/extend-local-lvm-proxmox.133478/#post-589215
# Version: 2025-01-08
# Author: Proxmox LVM Management Tool

set -e

echo "=============================="
echo "Proxmox LVM Extension Tool"
echo "Extend LVM volumes after disk expansion"
echo "=============================="

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
   echo "sudo ./pve_lvm_extend.sh"
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

# Function to resize physical volume
resize_physical_volume() {
    echo "🔄 Resizing Physical Volume..."
    
    # Get the PV device
    local pv_device=$(pvs --noheadings -o pv_name | head -1 | tr -d ' ')
    
    if [[ -z "$pv_device" ]]; then
        echo "❌ Error: No physical volume found"
        exit 1
    fi
    
    echo "Physical Volume device: $pv_device"
    
    # Resize the PV
    echo "Resizing PV to use all available space..."
    pvresize "$pv_device"
    
    echo "✅ Physical Volume resized successfully"
    echo ""
}

# Function to extend root volume
extend_root_volume() {
    local root_size="$1"
    
    echo "🔄 Extending root volume to $root_size..."
    
    # Get current root size
    local current_root_size=$(lvs --noheadings --units g --nosuffix -o lv_size /dev/pve/root | tr -d ' ')
    local target_root_size=$(echo "$root_size" | sed 's/G//')
    
    echo "Current root size: ${current_root_size}G"
    echo "Target root size: ${target_root_size}G"
    
    if (( $(echo "$current_root_size >= $target_root_size" | bc -l) )); then
        echo "ℹ️  Root volume is already at or larger than target size"
        return 0
    fi
    
    # Calculate space to add
    local space_to_add=$(echo "scale=0; $target_root_size - $current_root_size" | bc)
    echo "Space to add: ${space_to_add}G"
    
    # Extend logical volume
    echo "Extending logical volume..."
    lvextend -L "${target_root_size}G" /dev/pve/root
    
    # Extend filesystem
    echo "Extending filesystem..."
    resize2fs /dev/pve/root
    
    echo "✅ Root volume extended successfully"
    echo ""
}

# Function to extend data volume
extend_data_volume() {
    echo "🔄 Extending data volume to use remaining space..."
    
    # Get available free space
    local free_space=$(vgs --noheadings --units g --nosuffix -o vg_free pve | tr -d ' ')
    echo "Available free space: ${free_space}G"
    
    if (( $(echo "$free_space < 1" | bc -l) )); then
        echo "⚠️  No significant free space available for data volume"
        return 0
    fi
    
    # Extend data volume to use all remaining space
    echo "Extending data volume..."
    lvextend -l +100%FREE /dev/pve/data
    
    echo "✅ Data volume extended successfully"
    echo ""
}

# Function to get custom sizes
get_custom_sizes() {
    echo "🔧 Custom Size Configuration"
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

# Function to check if data volume exists
check_data_volume() {
    if ! lvs /dev/pve/data >/dev/null 2>&1; then
        echo "❌ Error: /dev/pve/data volume does not exist"
        echo "This script is designed for systems with existing data volume"
        echo "For new LVM-thin setup, use pve_lvm_thin_setup.sh"
        exit 1
    fi
}

# Main execution
echo "⚠️  Important Warnings:"
echo "1. Stop all VMs and CTs before performing this operation"
echo "2. Make sure you have backups of important data"
echo "3. This script extends existing LVM volumes after disk expansion"
echo "4. The underlying disk/partition must already be expanded"
echo ""

read -p "Continue with LVM extension operation (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ Operation cancelled."
    exit 1
fi

# Check and install required packages
check_required_packages

# Show current status
show_current_status

# Check if data volume exists
check_data_volume

# Get size configuration
get_custom_sizes

# Calculate actual sizes
calculate_sizes

echo ""
echo "Operation Summary:"
echo "  Root volume will be extended to: $ROOT_SIZE_CALC"
echo "  Data volume will use remaining space"
echo ""

read -p "Proceed with these settings (y/N): " final_confirm
if [[ "$final_confirm" != "y" && "$final_confirm" != "Y" ]]; then
    echo "❌ Operation cancelled."
    exit 1
fi

# Resize physical volume
resize_physical_volume

# Extend root volume
extend_root_volume "$ROOT_SIZE_CALC"

# Extend data volume
extend_data_volume

echo ""
echo "Final LVM status:"
lvs --units g

echo ""
echo "Storage usage:"
df -h /

echo ""
echo "✅ LVM extension completed successfully!"
echo ""
echo "📊 Summary:"
echo "  Root volume: Extended to $ROOT_SIZE_CALC"
echo "  Data volume: Extended to use remaining space"
echo ""
echo "🔧 Next steps:"
echo "1. Verify storage in Proxmox web interface"
echo "2. Restart VMs and CTs if needed"
echo "3. Monitor storage usage"
echo ""
echo "🎉 Extension completed!" 