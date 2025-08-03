#!/bin/bash

# Proxmox LVM-Thin Setup Script
# LVM을 LVM-thin으로 변경하거나 새로 설정하는 스크립트

set -e

echo "=============================="
echo "Proxmox LVM-Thin Setup Tool"
echo "Convert LVM to LVM-thin or setup new LVM-thin"
echo "=============================="

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
   echo "sudo ./pve_lvm_thin_setup.sh"
   exit 1
fi

# Function to check if LVM-thin is already configured
check_lvm_thin() {
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
    
    # Calculate available space (leave 20% for root)
    total_space=$(lvs --noheadings --units b --nosuffix -o lv_size /dev/pve/root | tr -d ' ')
    thin_space=$((total_space * 80 / 100))
    
    # Resize root volume to leave space for thin pool
    echo "🔄 Resizing root volume..."
    lvresize -L $(numfmt --to=iec $thin_space)B /dev/pve/root
    
    # Create thin pool
    echo "🔄 Creating LVM-thin pool..."
    lvcreate -l 100%FREE -T pve/data
    
    # Create thin volume using 80% of available space
    echo "🔄 Creating thin volume..."
    thin_volume_size=$(lvs --noheadings --units b --nosuffix -o lv_size /dev/pve/data | tr -d ' ')
    thin_volume_size=$((thin_volume_size * 80 / 100))
    lvcreate -V $(numfmt --to=iec $thin_volume_size)B -T pve/data -n data
    
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

case $lvm_status in
    0)
        echo "✅ LVM-thin is already properly configured."
        echo "📊 Current LVM status:"
        lvs
        exit 0
        ;;
    1)
        echo "🔄 Converting existing LVM to LVM-thin..."
        
        # Ask for backup
        read -p "Create backup of existing data? (y/N): " backup_confirm
        if [[ "$backup_confirm" == "y" || "$backup_confirm" == "Y" ]]; then
            backup_data_volume
        fi
        
        convert_to_lvm_thin
        ;;
    2)
        echo "🔄 Creating new LVM-thin setup..."
        create_new_lvm_thin
        ;;
esac

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