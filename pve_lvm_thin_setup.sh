#!/bin/bash

# Proxmox LVM-Thin Size Configuration Script
# Proxmox 설치 완료 후 LVM 디렉토리와 LVM-thin 사이즈를 변경하는 스크립트

# 2025-08-04 12:19:40
set -e

echo "=============================="
echo "Proxmox LVM-Thin Size Configuration Tool"
echo "Resize LVM directories and LVM-thin after Proxmox installation"
echo "=============================="

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
   echo "sudo ./pve_lvm_thin_setup.sh"
   exit 1
fi

# Function to check system compatibility
check_system_compatibility() {
    echo "🔍 Checking system compatibility..."
    
    # Check if VG has free space
    free_space=$(vgs --noheadings --units g --nosuffix -o vg_free pve | tr -d ' ')
    total_vg_size=$(vgs --noheadings --units g --nosuffix -o vg_size pve | tr -d ' ')
    current_root_size=$(lvs --noheadings --units g --nosuffix -o lv_size /dev/pve/root | tr -d ' ')
    
    echo "📊 System Analysis:"
    echo "   Total VG size: ${total_vg_size}GB"
    echo "   Current root size: ${current_root_size}GB"
    echo "   Free space: ${free_space}GB"
    echo ""
    
    # Check if this system used pve_lvm_resize.sh (root volume uses most/all space)
    root_usage_percent=$(echo "scale=2; $current_root_size * 100 / $total_vg_size" | bc)
    
    if (( $(echo "$root_usage_percent > 90" | bc -l) )); then
        echo "🔍 Detected: System appears to have used pve_lvm_resize.sh"
        echo "   Root volume uses ${root_usage_percent}% of total space"
        echo "   Will need to shrink root volume to create data volume"
        SYSTEM_TYPE="post_resize"
    elif (( $(echo "$free_space < 5" | bc -l) )); then
        echo "🔍 Detected: Limited free space available"
        echo "   Will need to shrink root volume to create adequate data volume"
        SYSTEM_TYPE="limited_space"
    else
        echo "🔍 Detected: Standard Proxmox installation"
        echo "   Sufficient free space available"
        SYSTEM_TYPE="standard"
    fi
    echo ""
}

# Function to get user input for size configuration
get_size_configuration() {
    echo "🔧 LVM Size Configuration"
    echo "Current storage layout:"
    echo ""
    
    # Show current LVM status
    echo "📊 Current LVM volumes:"
    lvs --units g
    echo ""
    
    # Show current disk usage
    echo "📊 Current disk usage:"
    df -h /
    echo ""
    
    # Get total VG size
    total_vg_size=$(vgs --noheadings --units g --nosuffix -o vg_size pve | tr -d ' ')
    echo "📊 Total Volume Group size: ${total_vg_size}GB"
    echo ""
    
    # Provide different options based on system type
    if [[ "$SYSTEM_TYPE" == "post_resize" || "$SYSTEM_TYPE" == "limited_space" ]]; then
        # Calculate safe minimum size based on current usage
        current_usage=$(df / | awk 'NR==2 {print $3}')
        current_usage_gb=$(echo "scale=0; $current_usage / 1024 / 1024 + 5" | bc)  # Add 5GB buffer
        
        echo "🔧 Size Configuration Options (Root volume will be shrunk):"
        echo "   Current root usage: $(echo "scale=1; $current_usage / 1024 / 1024" | bc)GB"
        echo "   Recommended minimum: ${current_usage_gb}GB"
        echo ""
        echo "1. Safe minimum (Root: ${current_usage_gb}GB, Data: remaining space)"
        echo "2. Balanced (Root: 30GB, Data: remaining space) - Recommended"
        echo "3. Conservative (Root: 40GB, Data: remaining space)"
        echo "4. Custom sizes"
        echo "5. Skip shrinking (keep current root size, create thin data volume)"
        echo ""
        
        read -p "Select option (1-5): " size_option
        
        case $size_option in
            1)
                ROOT_SIZE="${current_usage_gb}G"
                DATA_SIZE="remaining"
                echo "✅ Selected: Root ${current_usage_gb}GB (safe minimum), Data remaining space"
                ;;
            2)
                ROOT_SIZE="30G"
                DATA_SIZE="remaining"
                echo "✅ Selected: Root 30GB, Data remaining space"
                ;;
            3)
                ROOT_SIZE="40G"
                DATA_SIZE="remaining"
                echo "✅ Selected: Root 40GB, Data remaining space"
                ;;
            4)
                echo "💡 Minimum recommended size: ${current_usage_gb}GB"
                read -p "Enter root volume size (e.g., 25G): " ROOT_SIZE
                read -p "Enter data volume size (e.g., 100G or 'remaining'): " DATA_SIZE
                echo "✅ Selected: Root ${ROOT_SIZE}, Data ${DATA_SIZE}"
                ;;
            5)
                ROOT_SIZE="current"
                DATA_SIZE="remaining"
                echo "✅ Selected: Keep current root size, Data remaining space"
                ;;
            *)
                echo "❌ Invalid option. Using balanced configuration."
                ROOT_SIZE="30G"
                DATA_SIZE="remaining"
                ;;
        esac
    else
        echo "🔧 Size Configuration Options:"
        echo "1. Automatic (Root: 20GB, Data: remaining space)"
        echo "2. Custom sizes"
        echo "3. Percentage based (Root: 30%, Data: 70%)"
        echo ""
        
        read -p "Select option (1-3): " size_option
        
        case $size_option in
            1)
                ROOT_SIZE="20G"
                DATA_SIZE="remaining"
                echo "✅ Selected: Root 20GB, Data remaining space"
                ;;
            2)
                read -p "Enter root volume size (e.g., 25G): " ROOT_SIZE
                read -p "Enter data volume size (e.g., 100G or 'remaining'): " DATA_SIZE
                echo "✅ Selected: Root ${ROOT_SIZE}, Data ${DATA_SIZE}"
                ;;
            3)
                ROOT_SIZE="30%"
                DATA_SIZE="70%"
                echo "✅ Selected: Root 30%, Data 70%"
                ;;
            *)
                echo "❌ Invalid option. Using automatic configuration."
                ROOT_SIZE="20G"
                DATA_SIZE="remaining"
                ;;
        esac
    fi
}

# Function to calculate sizes based on user input
calculate_sizes() {
    local total_vg_size=$(vgs --noheadings --units g --nosuffix -o vg_size pve | tr -d ' ')
    
    if [[ "$ROOT_SIZE" == *"%" ]]; then
        local root_percent=${ROOT_SIZE%\%}
        ROOT_SIZE_CALC=$(echo "scale=0; $total_vg_size * $root_percent / 100" | bc)G
    elif [[ "$ROOT_SIZE" == "current" ]]; then
        local current_root_size=$(lvs --noheadings --units g --nosuffix -o lv_size /dev/pve/root | tr -d ' ')
        ROOT_SIZE_CALC="${current_root_size}G"
    else
        ROOT_SIZE_CALC="$ROOT_SIZE"
    fi
    
    if [[ "$DATA_SIZE" == *"%" ]]; then
        local data_percent=${DATA_SIZE%\%}
        DATA_SIZE_CALC=$(echo "scale=0; $total_vg_size * $data_percent / 100" | bc)G
    elif [[ "$DATA_SIZE" == "remaining" ]]; then
        DATA_SIZE_CALC="100%FREE"
    else
        DATA_SIZE_CALC="$DATA_SIZE"
    fi
    
    echo "📊 Calculated sizes:"
    echo "   Root volume: $ROOT_SIZE_CALC"
    echo "   Data volume: $DATA_SIZE_CALC"
}

# Function to resize root volume
resize_root_volume() {
    echo "🔄 Resizing root volume to $ROOT_SIZE_CALC..."
    
    # Check if root volume needs resizing
    current_root_size=$(lvs --noheadings --units g --nosuffix -o lv_size /dev/pve/root | tr -d ' ')
    target_root_size=$(echo "$ROOT_SIZE_CALC" | sed 's/G//')
    
    # Skip resizing if keeping current size
    if [[ "$ROOT_SIZE" == "current" ]]; then
        echo "✅ Keeping current root volume size (${current_root_size}G)"
        return 0
    fi
    
    if (( $(echo "$current_root_size > $target_root_size" | bc -l) )); then
        echo "🔄 Shrinking root volume from ${current_root_size}G to ${target_root_size}G..."
        
        # Check filesystem usage before shrinking
        current_usage=$(df / | awk 'NR==2 {print $3}')
        current_usage_gb=$(echo "scale=2; $current_usage / 1024 / 1024" | bc)
        
        echo "📊 Filesystem usage analysis:"
        echo "   Current usage: ${current_usage_gb}GB"
        echo "   Target size: ${target_root_size}GB"
        echo "   Available after shrink: $(echo "scale=2; $target_root_size - $current_usage_gb" | bc)GB"
        
        if (( $(echo "$current_usage_gb > $target_root_size - 3" | bc -l) )); then
            echo "❌ Error: Current filesystem usage (${current_usage_gb}GB) is too close to target size (${target_root_size}GB)"
            echo "   Need at least 3GB free space for safe operation"
            echo ""
            echo "💡 Options:"
            echo "   1. Clean up files to free space"
            echo "   2. Choose a larger root size (recommended: $(echo "scale=0; $current_usage_gb + 5" | bc)GB or more)"
            echo "   3. Cancel and run cleanup first"
            echo ""
            read -p "Do you want to continue anyway? (NOT RECOMMENDED) (y/N): " force_continue
            if [[ "$force_continue" != "y" && "$force_continue" != "Y" ]]; then
                echo "❌ Operation cancelled for safety."
                exit 1
            fi
            echo "⚠️  Proceeding with insufficient space - HIGH RISK!"
        fi
        
        echo "⚠️  WARNING: Root filesystem shrinking requires offline operation!"
        echo "   ext4 filesystem cannot be shrunk while mounted"
        echo ""
        echo "🔧 Alternative approaches:"
        echo "   1. Boot from Proxmox rescue/installation media"
        echo "   2. Use a live Linux USB/CD"
        echo "   3. Choose a larger root size to avoid shrinking"
        echo ""
        echo "� Recommendped: Choose option 2 (Root focused: 30GB) or 4 (Custom) with larger size"
        echo ""
        
        read -p "Do you want to continue with offline shrinking? (y/N): " offline_continue
        if [[ "$offline_continue" != "y" && "$offline_continue" != "Y" ]]; then
            echo "❌ Operation cancelled. Please restart and choose a larger root size."
            exit 1
        fi
        
        echo ""
        echo "🚨 CRITICAL: This operation requires system reboot into rescue mode!"
        echo "📋 Manual steps required:"
        echo "   1. Boot from Proxmox installation media or live Linux"
        echo "   2. Activate LVM: vgchange -ay pve"
        echo "   3. Check filesystem: e2fsck -f /dev/pve/root"
        echo "   4. Shrink filesystem: resize2fs /dev/pve/root $ROOT_SIZE_CALC"
        echo "   5. Shrink LV: lvresize -L $ROOT_SIZE_CALC /dev/pve/root"
        echo "   6. Reboot back to normal system"
        echo "   7. Re-run this script to create LVM-thin data volume"
        echo ""
        echo "❌ Cannot proceed with online root filesystem shrinking."
        echo "   Please follow the manual steps above or choose a larger root size."
        exit 1
        
    elif (( $(echo "$current_root_size < $target_root_size" | bc -l) )); then
        echo "🔄 Expanding root volume from ${current_root_size}G to ${target_root_size}G..."
        
        # First expand logical volume
        echo "🔄 Expanding logical volume..."
        lvresize -L $ROOT_SIZE_CALC /dev/pve/root
        
        # Then expand filesystem
        echo "🔄 Expanding filesystem..."
        resize2fs /dev/pve/root
    else
        echo "✅ Root volume is already the correct size (${current_root_size}G)"
    fi
}

# Function to setup or resize LVM-thin data volume
setup_lvm_thin_data() {
    echo "🔄 Setting up LVM-thin data volume..."
    
    # Check if data volume exists
    if lvs /dev/pve/data >/dev/null 2>&1; then
        echo "📝 Existing data volume found. Removing for resize..."
        
        # Check if it's a thin volume
        if lvs -o lv_name,lv_layout /dev/pve/data | grep -q "thin"; then
            echo "🔄 Removing existing thin volume..."
            lvremove -f /dev/pve/data
        else
            echo "🔄 Removing existing regular volume..."
            lvremove -f /dev/pve/data
        fi
    fi
    
    # Create thin pool
    echo "🔄 Creating LVM-thin pool..."
    if [[ "$DATA_SIZE_CALC" == "100%FREE" ]]; then
        lvcreate -l 100%FREE -T pve/data
    else
        lvcreate -L $DATA_SIZE_CALC -T pve/data
    fi
    
    # Get thin pool size for thin volume creation
    thin_pool_size=$(lvs --noheadings --units g --nosuffix -o lv_size /dev/pve/data | tr -d ' ')
    
    # Create thin volume (use 95% of pool size for over-provisioning)
    thin_volume_size=$(echo "scale=0; $thin_pool_size * 95 / 100" | bc)
    echo "🔄 Creating thin volume (${thin_volume_size}G)..."
    lvcreate -V ${thin_volume_size}G -T pve/data -n data
    
    echo "✅ LVM-thin data volume setup completed!"
}

# Main execution
echo "📊 Checking current LVM status..."
lvs

echo ""
echo "⚠️  Important Warnings:"
echo "1. Stop all VMs and CTs before performing this operation."
echo "2. All data in existing data volume will be lost."
echo "3. Do not reboot the system during the operation."
echo "4. This will resize root volume and recreate data volume as LVM-thin."
echo "5. Make sure you have backups of important data."
echo "6. This script works with systems that used pve_lvm_resize.sh."
echo "7. Root volume will be safely shrunk if needed to create data volume."
echo ""

read -p "Continue with LVM resize operation? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ Operation cancelled."
    exit 1
fi

# Install bc for calculations if not present
if ! command -v bc &> /dev/null; then
    echo "🔧 Installing bc for calculations..."
    apt-get update && apt-get install -y bc
fi

# Check system compatibility
check_system_compatibility

# Get size configuration from user
get_size_configuration

# Calculate actual sizes
calculate_sizes

echo ""
echo "📋 Operation Summary:"
echo "   Root volume will be resized to: $ROOT_SIZE_CALC"
echo "   Data volume will be created as: $DATA_SIZE_CALC (LVM-thin)"
echo ""

read -p "Proceed with these settings? (y/N): " final_confirm
if [[ "$final_confirm" != "y" && "$final_confirm" != "Y" ]]; then
    echo "❌ Operation cancelled."
    exit 1
fi

# Resize root volume
resize_root_volume

# Setup LVM-thin data volume
setup_lvm_thin_data

echo ""
echo "📊 Final LVM status:"
lvs --units g

echo ""
echo "� NStorage usage:"
df -h /

echo ""
echo "✅ LVM-thin resize operation completed successfully!"
echo ""
echo "💡 Next steps:"
echo "1. Go to Proxmox web interface → Datacenter → Storage"
echo "2. Edit 'local' storage and add content types (Disk image, Container)"
echo "3. The data volume is now LVM-thin with over-provisioning capability"
echo "4. You can now create VMs and containers using the resized storage"
echo "5. Monitor thin pool usage: lvs -a"
echo ""
echo "📈 Storage Summary:"
echo "   Root volume: $ROOT_SIZE_CALC (for Proxmox system)"
echo "   Data volume: LVM-thin pool (for VMs and containers)"
echo "   Thin provisioning: Enabled (allows over-allocation)" 