#!/bin/bash

# Proxmox LVM-Thin Setup Script
# LVM을 LVM-thin으로 변경하거나 새로 설정하는 스크립트

set -e

echo "=============================="
echo "Proxmox LVM-Thin Setup Tool"
echo "Convert LVM to LVM-thin or setup new LVM-thin"
echo "250504 121253"
echo "=============================="

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
   echo "sudo ./pve_lvm_thin_setup.sh"
   exit 1
fi

# Function to check if LVM-thin is already configured
check_lvm_thin() {
    echo "🔍 Checking for existing data volume..."
    
    if lvs /dev/pve/data >/dev/null 2>&1; then
        echo "📊 Current LVM status:"
        lvs
        echo ""
        echo "🔍 Checking if LVM-thin is already configured..."
        
        # Check if data volume is thin
        if lvs -o lv_name,lv_layout /dev/pve/data | grep -q "thin"; then
            echo "✅ LVM-thin is already configured on /dev/pve/data"
            return 0
        else
            echo "📝 Found regular LVM volume. Will convert to LVM-thin."
            return 1
        fi
    else
        echo "📝 No existing data volume found. Will create new LVM-thin."
        echo "🔍 Returning status 2 for new LVM-thin setup"
        return 2
    fi
}

# Function to backup existing data volume
backup_data_volume() {
    echo "🔄 Creating backup of existing data volume..."
    
    # Create backup directory
    mkdir -p /root/lvm_backup
    
    # Get available space for backup
    available_space=$(df /root | awk 'NR==2 {print $4}')
    data_size=$(lvs --noheadings --units b --nosuffix -o lv_size /dev/pve/data | tr -d ' ')
    
    if [ "$available_space" -lt "$data_size" ]; then
        echo "⚠️  Warning: Insufficient space for full backup."
        echo "   Available: $(numfmt --to=iec $available_space)B"
        echo "   Data size: $(numfmt --to=iec $data_size)B"
        read -p "Continue without backup? (y/N): " skip_backup
        if [[ "$skip_backup" != "y" && "$skip_backup" != "Y" ]]; then
            echo "❌ Operation cancelled."
            exit 1
        fi
        return 1
    fi
    
    # Create backup
    dd if=/dev/pve/data of=/root/lvm_backup/data_backup.img bs=1M status=progress
    echo "✅ Backup created: /root/lvm_backup/data_backup.img"
    return 0
}

# Function to convert existing LVM to LVM-thin
convert_to_lvm_thin() {
    echo "🔄 Converting existing LVM to LVM-thin..."
    
    # Get current volume size
    current_size=$(lvs --noheadings --units b --nosuffix -o lv_size /dev/pve/data | tr -d ' ')
    
    # Remove existing data volume
    echo "🔄 Removing existing data volume..."
    lvremove -f /dev/pve/data
    
    # Create thin pool
    echo "🔄 Creating LVM-thin pool..."
    lvcreate -l 100%FREE -T pve/data
    
    # Create thin volume with same size as original
    echo "🔄 Creating thin volume..."
    lvcreate -V $(numfmt --from=iec $(numfmt --to=iec $current_size)B) -T pve/data -n data
    
    echo "✅ LVM-thin conversion completed!"
}

# Function to create new LVM-thin setup
create_new_lvm_thin() {
    echo "🔄 Creating new LVM-thin setup..."
    echo "🔍 Starting create_new_lvm_thin function..."
    
    # Get current root volume size
    root_size=$(lvs --noheadings --units b --nosuffix -o lv_size /dev/pve/root | tr -d ' ')
    root_size_gb=$(numfmt --from=iec --to=iec $root_size | sed 's/[^0-9]//g')
    
    echo "📊 Current root volume size: ${root_size_gb}GB"
    echo "🔍 Raw root size in bytes: $root_size"
    
    # Calculate space allocation (root: 20GB, thin pool: rest)
    echo "🔍 Comparing root_size_gb ($root_size_gb) with 50..."
    if [ "$root_size_gb" -gt 50 ]; then
        echo "🔍 Root volume is large (>50GB), will resize to 20GB"
        # If root is large enough, resize to 20GB and use rest for thin pool
        echo "🔄 Resizing root volume to 20GB..."
        lvresize -L 20G /dev/pve/root
        
        # Resize filesystem
        echo "🔄 Resizing filesystem..."
        resize2fs -p /dev/pve/root
        
        # Create thin pool with remaining space
        echo "🔄 Creating LVM-thin pool..."
        lvcreate -l 100%FREE -T pve/data
        
        # Create thin volume using 90% of thin pool space
        echo "🔄 Creating thin volume..."
        thin_pool_size=$(lvs --noheadings --units b --nosuffix -o lv_size /dev/pve/data | tr -d ' ')
        thin_volume_size=$((thin_pool_size * 90 / 100))
        lvcreate -V $(numfmt --to=iec $thin_volume_size)B -T pve/data -n data
        
    else
        echo "🔍 Root volume is small (<=50GB), using 80% of space for thin pool"
        # If root is small, use 80% of current space for thin pool
        echo "🔄 Root volume is small, using 80% of space for thin pool..."
        thin_space=$((root_size * 80 / 100))
        
        # Resize root volume
        echo "🔄 Resizing root volume..."
        lvresize -L $(numfmt --to=iec $thin_space)B /dev/pve/root
        
        # Resize filesystem
        echo "🔄 Resizing filesystem..."
        resize2fs -p /dev/pve/root
        
        # Create thin pool
        echo "🔄 Creating LVM-thin pool..."
        lvcreate -l 100%FREE -T pve/data
        
        # Create thin volume using 90% of thin pool space
        echo "🔄 Creating thin volume..."
        thin_pool_size=$(lvs --noheadings --units b --nosuffix -o lv_size /dev/pve/data | tr -d ' ')
        thin_volume_size=$((thin_pool_size * 90 / 100))
        lvcreate -V $(numfmt --to=iec $thin_volume_size)B -T pve/data -n data
    fi
    
    echo "✅ New LVM-thin setup completed!"
}

# Main execution
echo "📊 Checking current LVM status..."
lvs

echo ""
echo "⚠️  Warnings:"
echo "1. Stop all VMs and CTs before performing this operation."
echo "2. All data in existing data volume will be lost unless backed up."
echo "3. Do not reboot the system during the operation."
echo "4. This operation will create LVM-thin pool and volume."
echo ""

read -p "Continue? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ Operation cancelled."
    exit 1
fi

# Check current LVM-thin status
check_lvm_thin
lvm_status=$?

echo "🔍 LVM status code: $lvm_status"

# Force execution if status is 2 (no data volume found)
if [ "$lvm_status" -eq 2 ]; then
    echo "🔄 Creating new LVM-thin setup..."
    echo "🚀 Starting LVM-thin creation process..."
    create_new_lvm_thin
elif [ "$lvm_status" -eq 0 ]; then
    echo "✅ LVM-thin is already properly configured."
    echo "📊 Current LVM status:"
    lvs
    exit 0
elif [ "$lvm_status" -eq 1 ]; then
    echo "🔄 Converting existing LVM to LVM-thin..."
    
    # Ask for backup
    read -p "Create backup of existing data? (y/N): " backup_confirm
    if [[ "$backup_confirm" == "y" || "$backup_confirm" == "Y" ]]; then
        backup_data_volume
    fi
    
    convert_to_lvm_thin
else
    echo "❌ Unexpected LVM status: $lvm_status"
    echo "🔄 Forcing new LVM-thin setup..."
    create_new_lvm_thin
fi

echo ""
echo "📊 Final LVM status:"
lvs

echo ""
echo "💡 Next steps:"
echo "1. Check storage settings in Proxmox web interface."
echo "2. Add content to local storage."
echo "3. Restart VMs and CTs."
echo "4. If backup was created, restore data if needed."

if [ -f "/root/lvm_backup/data_backup.img" ]; then
    echo ""
    echo "📁 Backup available at: /root/lvm_backup/data_backup.img"
    echo "To restore: dd if=/root/lvm_backup/data_backup.img of=/dev/pve/data"
fi 