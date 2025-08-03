#!/bin/bash

# Proxmox LVM-Thin Setup Script (Fixed Version)
# LVM을 LVM-thin으로 변경하거나 새로 설정하는 스크립트

set -e

echo "=============================="
echo "Proxmox LVM-Thin Setup Tool (Fixed)"
echo "Convert LVM to LVM-thin or setup new LVM-thin"
echo "=============================="

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
   echo "sudo ./pve_lvm_thin_setup_fixed.sh"
   exit 1
fi

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

# Check if data volume exists
echo "🔍 Checking for existing data volume..."
if lvs /dev/pve/data >/dev/null 2>&1; then
    echo "📝 Found existing data volume."
    echo "📊 Current LVM status:"
    lvs
    
    # Check if it's already thin
    if lvs -o lv_name,lv_layout /dev/pve/data | grep -q "thin"; then
        echo "✅ LVM-thin is already configured on /dev/pve/data"
        echo "📊 Current LVM status:"
        lvs
        exit 0
    else
        echo "🔄 Converting existing LVM to LVM-thin..."
        echo "⚠️  This will delete existing data volume!"
        read -p "Continue with conversion? (y/N): " convert_confirm
        if [[ "$convert_confirm" != "y" && "$convert_confirm" != "Y" ]]; then
            echo "❌ Conversion cancelled."
            exit 1
        fi
        
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
    fi
else
    echo "📝 No existing data volume found. Creating new LVM-thin setup..."
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