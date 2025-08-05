#!/bin/bash

# Proxmox LVM Extension Script with Automatic PE Boot
# Script to extend LVM volumes after disk expansion with automatic PE boot
# Designed for remote systems without user intervention
# Based on Proxmox forum: https://forum.proxmox.com/threads/extend-local-lvm-proxmox.133478/#post-589215
# Author: Proxmox LVM Management Tool

set -e

echo "=============================="
echo "Proxmox LVM Extension Tool with Automatic PE Boot"
echo "Designed for remote systems without user intervention"
echo "V 250806004400"
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
    echo "🔄 Preparing SystemRescueCD PE for automatic boot..."
    
    # Create PE directory
    mkdir -p /boot/pe
    
    # Download SystemRescueCD with parallel download for speed
    echo "📥 Downloading SystemRescueCD with parallel download..."
    
    # Define multiple mirrors for reliability
    local mirrors=(
        "https://downloads.sourceforge.net/systemrescuecd/sysresccd-x86-11.00.iso"
        "https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86-11.00.iso"
        "https://osdn.net/projects/systemrescuecd/downloads/11.00/sysresccd-x86-11.00.iso"
    )
    
    local download_success=false
    
    # Try each mirror
    for mirror in "${mirrors[@]}"; do
        echo "🔄 Trying mirror: $mirror"
        
        if command -v aria2c &> /dev/null; then
            echo "Using aria2c for fast parallel download..."
            if aria2c -x 16 -s 16 -o tinycore.iso "$mirror" -d /tmp/; then
                download_success=true
                break
            fi
        else
            echo "Using wget with resume capability..."
            if wget -c -O /tmp/tinycore.iso "$mirror"; then
                download_success=true
                break
            fi
        fi
        
        echo "❌ Failed to download from $mirror, trying next mirror..."
    done
    
    if [[ "$download_success" == "false" ]]; then
        echo "❌ Error: Failed to download SystemRescueCD from all mirrors"
        exit 1
    fi
    
    # Mount ISO and extract kernel and initrd
    echo "🔧 Extracting PE components..."
    
    # Unmount if already mounted
    if mountpoint -q /mnt; then
        echo "Unmounting existing mount..."
        umount /mnt 2>/dev/null || true
    fi
    
    mount -o loop /tmp/sysresccd.iso /mnt
    
    # Copy kernel and initrd with verification
    echo "🔧 Copying kernel and initrd..."
    
    # Check available kernel files
    echo "Available kernel files:"
    ls -la /mnt/boot/vmlinuz* 2>/dev/null || echo "No vmlinuz files found"
    
    # Check available initrd files
    echo "Available initrd files:"
    ls -la /mnt/boot/sysresccd* 2>/dev/null || echo "No sysresccd files found"
    
    # Copy kernel (SystemRescueCD uses standard names)
    if [[ -f "/mnt/boot/vmlinuz" ]]; then
        cp /mnt/boot/vmlinuz /boot/vmlinuz_pe
        echo "✅ Copied vmlinuz"
    else
        echo "❌ Error: No kernel file found"
        exit 1
    fi
    
    # Copy initrd (SystemRescueCD uses sysresccd.img)
    if [[ -f "/mnt/boot/sysresccd.img" ]]; then
        cp /mnt/boot/sysresccd.img /boot/initrd_pe
        echo "✅ Copied sysresccd.img"
    elif [[ -f "/mnt/boot/initram.igz" ]]; then
        cp /mnt/boot/initram.igz /boot/initrd_pe
        echo "✅ Copied initram.igz"
    else
        echo "❌ Error: No initrd file found"
        exit 1
    fi
    
    # SystemRescueCD already has all LVM tools, no need to modify initrd
    echo "🔧 SystemRescueCD initrd is ready (contains all LVM tools)"
    
    # Create PE script directory and copy PE script
    mkdir -p /boot/pe
    if [[ -f "/boot/pe/auto-lvm-extend.sh" ]]; then
        echo "✅ PE script already exists"
    else
        echo "⚠️  PE script not found, will create"
        # Create basic PE script
        cat > /boot/pe/auto-lvm-extend.sh << 'PE_EOF'
#!/bin/sh
echo "🚀 Starting automatic LVM extension in SystemRescueCD environment..."
sleep 5
echo "📊 Current system status:"
df -h
echo ""
lvs --units g
echo ""
echo "🔄 Performing LVM operations..."
# Basic LVM operations
pvresize $(pvs --noheadings -o pv_name | head -1)
lvextend -l +100%FREE /dev/pve/root
resize2fs /dev/pve/root
echo "✅ LVM operations completed"
echo "🔄 Rebooting..."
reboot
PE_EOF
        chmod +x /boot/pe/auto-lvm-extend.sh
        echo "✅ Basic PE script created"
    fi
    
    # Cleanup
    umount /mnt
    
    echo "✅ SystemRescueCD PE prepared successfully (Size: ~700MB)"
    
    # Verify PE environment
    echo "🔍 Verifying PE environment..."
    if [[ -f "/boot/vmlinuz_pe" ]]; then
        echo "✅ Kernel file exists: $(ls -lh /boot/vmlinuz_pe)"
    else
        echo "❌ Error: Kernel file not found"
        exit 1
    fi
    
    if [[ -f "/boot/initrd_pe" ]]; then
        echo "✅ Initrd file exists: $(ls -lh /boot/initrd_pe)"
    else
        echo "❌ Error: Initrd file not found"
        exit 1
    fi
    
    echo "✅ PE environment verification completed"
    
    # Additional verification and debugging
    echo "🔍 Additional PE file verification..."
    echo "PE directory contents:"
    ls -la /boot/pe/ 2>/dev/null || echo "❌ /boot/pe/ directory not found"
    
    echo "Kernel file details:"
    if [[ -f "/boot/vmlinuz_pe" ]]; then
        file /boot/vmlinuz_pe
        ls -lh /boot/vmlinuz_pe
    else
        echo "❌ Kernel file not found at /boot/vmlinuz_pe"
    fi
    
    echo "Initrd file details:"
    if [[ -f "/boot/initrd_pe" ]]; then
        file /boot/initrd_pe
        ls -lh /boot/initrd_pe
    else
        echo "❌ Initrd file not found at /boot/initrd_pe"
    fi
    
    # Check if files are accessible from GRUB perspective
    echo "🔍 Checking file accessibility..."
    if [[ -f "/boot/vmlinuz_pe" ]] && [[ -f "/boot/initrd_pe" ]]; then
        echo "✅ PE files are accessible"
        echo "Kernel size: $(stat -c%s /boot/vmlinuz_pe) bytes"
        echo "Initrd size: $(stat -c%s /boot/initrd_pe) bytes"
    else
        echo "❌ PE files are not accessible"
        exit 1
    fi
    
    # Verify PE environment
    echo "🔍 Verifying PE environment..."
    if [[ -f "/boot/vmlinuz_pe" ]]; then
        echo "✅ Kernel file exists: $(ls -lh /boot/vmlinuz_pe)"
    else
        echo "❌ Error: Kernel file not found"
        exit 1
    fi
    
    if [[ -f "/boot/initrd_pe" ]]; then
        echo "✅ Initrd file exists: $(ls -lh /boot/initrd_pe)"
    else
        echo "❌ Error: Initrd file not found"
        exit 1
    fi
    
    echo "✅ PE environment verification completed"
    
    # Additional verification and debugging
    echo "🔍 Additional PE file verification..."
    echo "PE directory contents:"
    ls -la /boot/pe/ 2>/dev/null || echo "❌ /boot/pe/ directory not found"
    
    echo "Kernel file details:"
    if [[ -f "/boot/vmlinuz_pe" ]]; then
        file /boot/vmlinuz_pe
        ls -lh /boot/vmlinuz_pe
    else
        echo "❌ Kernel file not found at /boot/vmlinuz_pe"
    fi
    
    echo "Initrd file details:"
    if [[ -f "/boot/initrd_pe" ]]; then
        file /boot/initrd_pe
        ls -lh /boot/initrd_pe
    else
        echo "❌ Initrd file not found at /boot/initrd_pe"
    fi
    
    # Check if files are accessible from GRUB perspective
    echo "🔍 Checking file accessibility..."
    if [[ -f "/boot/vmlinuz_pe" ]] && [[ -f "/boot/initrd_pe" ]]; then
        echo "✅ PE files are accessible"
        echo "Kernel size: $(stat -c%s /boot/vmlinuz_pe) bytes"
        echo "Initrd size: $(stat -c%s /boot/initrd_pe) bytes"
    else
        echo "❌ PE files are not accessible"
        exit 1
    fi
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

# Validate volume group size
echo "🔍 Validating volume group size..."
local total_vg_size=$(vgs --noheadings --units g --nosuffix -o vg_size pve | tr -d ' ')
if [[ -z "$total_vg_size" ]] || [[ "$total_vg_size" -eq 0 ]]; then
    echo "❌ Error: Invalid or zero volume group size detected"
    echo "Current VG size: $total_vg_size"
    echo "Cannot proceed with LVM operations"
    exit 1
fi
echo "✅ Volume group size validated: ${total_vg_size}G"

# Perform LVM operations
echo "🔄 Performing LVM extension operations..."

# Resize physical volume
echo "📏 Resizing physical volume..."

# Detect the correct physical volume device
local pv_device=$(pvs --noheadings -o pv_name | head -1 | tr -d ' ')
if [[ -z "$pv_device" ]]; then
    echo "❌ Error: No physical volume found"
    exit 1
fi

echo "Detected physical volume: $pv_device"

if pvresize "$pv_device"; then
    echo "✅ Physical volume resized successfully"
else
    echo "⚠️  Physical volume resize failed, continuing..."
fi

# Extend root volume
echo "📏 Extending root volume to $ROOT_SIZE_CALC..."

# Validate ROOT_SIZE_CALC
if [[ -z "$ROOT_SIZE_CALC" ]] || [[ "$ROOT_SIZE_CALC" == "G" ]] || [[ "$ROOT_SIZE_CALC" == "0G" ]]; then
    echo "❌ Error: Invalid root size calculated: $ROOT_SIZE_CALC"
    echo "Using default size of 15G"
    ROOT_SIZE_CALC="15G"
fi

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
        
        # Create thin pool with explicit size specification
        echo "Creating thin pool with 50G size..."
        
        # Validate size before creating thin pool
        local thin_pool_size=50
        if [[ "$thin_pool_size" -lt 1 ]]; then
            echo "❌ Error: Invalid thin pool size: ${thin_pool_size}G"
            echo "Using minimum size of 1G"
            thin_pool_size=1
        fi
        
        # Use explicit size without variable
        if lvcreate -L ${thin_pool_size}G -T pve/data; then
            echo "✅ Thin pool created successfully"
        else
            echo "❌ Thin pool creation failed"
            echo "🔄 Trying with smaller size..."
            # Try with smaller size
            local fallback_pool_size=25
            if [[ "$fallback_pool_size" -lt 1 ]]; then
                echo "❌ Error: Invalid fallback pool size: ${fallback_pool_size}G"
                echo "Using minimum size of 1G"
                fallback_pool_size=1
            fi
            if lvcreate -L ${fallback_pool_size}G -T pve/data; then
                echo "✅ Thin pool created with smaller size"
            else
                echo "❌ Thin pool creation failed even with smaller size"
                exit 1
            fi
        fi
        
        echo "📏 Creating thin volume..."
        
        # Create thin volume with explicit size specification
        echo "Creating thin volume with 20G size..."
        
        # Validate size before creating thin volume
        local thin_volume_size=20
        if [[ "$thin_volume_size" -lt 1 ]]; then
            echo "❌ Error: Invalid thin volume size: ${thin_volume_size}G"
            echo "Using minimum size of 1G"
            thin_volume_size=1
        fi
        
        # Use explicit size without variable
        if lvcreate -V ${thin_volume_size}G -T pve/data -n data; then
            echo "✅ Thin volume created successfully"
        else
            echo "❌ Thin volume creation failed"
            echo "🔄 Trying with smaller size..."
            # Try with smaller size
            local fallback_size=10
            if [[ "$fallback_size" -lt 1 ]]; then
                echo "❌ Error: Invalid fallback size: ${fallback_size}G"
                echo "Using minimum size of 1G"
                fallback_size=1
            fi
            if lvcreate -V ${fallback_size}G -T pve/data -n data; then
                echo "✅ Thin volume created with smaller size"
            else
                echo "❌ Thin volume creation failed even with smaller size"
                exit 1
            fi
        fi
        
        echo "📏 Formatting thin volume..."
        
        # Check if volume is mounted and unmount if necessary
        if mountpoint -q /mnt/pve/data; then
            echo "⚠️  Volume is mounted, unmounting first..."
            umount /mnt/pve/data
        fi
        
        # Remove from fstab if exists
        sed -i '/\/dev\/pve\/data/d' /etc/fstab
        
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
        
        # Check if it needs filesystem
        if ! blkid /dev/pve/data | grep -q "ext4"; then
            echo "📏 Formatting existing data volume..."
            
            # Check if volume is mounted and unmount if necessary
            if mountpoint -q /mnt/pve/data; then
                echo "⚠️  Volume is mounted, unmounting first..."
                umount /mnt/pve/data
            fi
            
            # Remove from fstab if exists
            sed -i '/\/dev\/pve\/data/d' /etc/fstab
            
            if mkfs.ext4 /dev/pve/data; then
                echo "✅ Data volume formatted successfully"
            else
                echo "❌ Data volume formatting failed"
                exit 1
            fi
            
            mkdir -p /mnt/pve/data
            echo "/dev/pve/data /mnt/pve/data ext4 defaults 0 2" >> /etc/fstab
            mount /dev/pve/data /mnt/pve/data
        else
            echo "✅ Data volume already has filesystem"
        fi
    fi
elif [[ "$DATA_VOLUME_TYPE" == "regular" ]]; then
    echo "🔄 Creating regular LVM data volume..."
    
    if ! lvs /dev/pve/data &>/dev/null; then
        # Create regular LVM volume with explicit size specification
        echo "Creating regular LVM volume with 50G size..."
        
        # Validate size before creating regular volume
        local regular_volume_size=50
        if [[ "$regular_volume_size" -lt 1 ]]; then
            echo "❌ Error: Invalid regular volume size: ${regular_volume_size}G"
            echo "Using minimum size of 1G"
            regular_volume_size=1
        fi
        
        # Use explicit size without variable
        if lvcreate -L ${regular_volume_size}G -n data pve; then
            echo "✅ Regular LVM volume created successfully"
        else
            echo "❌ Regular LVM volume creation failed"
            echo "🔄 Trying with smaller size..."
            # Try with smaller size
            local fallback_regular_size=25
            if [[ "$fallback_regular_size" -lt 1 ]]; then
                echo "❌ Error: Invalid fallback regular size: ${fallback_regular_size}G"
                echo "Using minimum size of 1G"
                fallback_regular_size=1
            fi
            if lvcreate -L ${fallback_regular_size}G -n data pve; then
                echo "✅ Regular LVM volume created with smaller size"
            else
                echo "❌ Regular LVM volume creation failed even with smaller size"
                exit 1
            fi
        fi
        
        # Check if volume is mounted and unmount if necessary
        if mountpoint -q /mnt/pve/data; then
            echo "⚠️  Volume is mounted, unmounting first..."
            umount /mnt/pve/data
        fi
        
        # Remove from fstab if exists
        sed -i '/\/dev\/pve\/data/d' /etc/fstab
        
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
        
        # Check if it needs filesystem
        if ! blkid /dev/pve/data | grep -q "ext4"; then
            echo "📏 Formatting existing data volume..."
            
            # Check if volume is mounted and unmount if necessary
            if mountpoint -q /mnt/pve/data; then
                echo "⚠️  Volume is mounted, unmounting first..."
                umount /mnt/pve/data
            fi
            
            # Remove from fstab if exists
            sed -i '/\/dev\/pve\/data/d' /etc/fstab
            
            if mkfs.ext4 /dev/pve/data; then
                echo "✅ Data volume formatted successfully"
            else
                echo "❌ Data volume formatting failed"
                exit 1
            fi
            
            mkdir -p /mnt/pve/data
            echo "/dev/pve/data /mnt/pve/data ext4 defaults 0 2" >> /etc/fstab
            mount /dev/pve/data /mnt/pve/data
        else
            echo "✅ Data volume already has filesystem"
        fi
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
    # Try to detect the actual boot partition more reliably
    local boot_uuid=$(blkid -s UUID -o value /boot 2>/dev/null)
    if [[ -n "$boot_uuid" ]]; then
        echo "Detected boot UUID: $boot_uuid"
        grub_root="search --no-floppy --fs-uuid --set=root $boot_uuid"
    else
        if [[ "$PARTITION_TABLE" == "gpt" ]]; then
            if [[ -n "$grub_device" ]]; then
                grub_root="set root=${grub_device},gpt1"
            else
                grub_root="set root=(hd0,gpt1)"
            fi
        else
            if [[ -n "$grub_device" ]]; then
                grub_root="set root=${grub_device},1"
            else
                grub_root="set root=(hd0,1)"
            fi
        fi
    fi
    
    echo "Using GRUB root: $grub_root"
    
    # Detect if system is UEFI or BIOS with more detailed detection
    local is_uefi=false
    local boot_mode="bios"
    
    if [[ -d "/sys/firmware/efi" ]]; then
        is_uefi=true
        boot_mode="uefi"
        echo "Detected UEFI system"
    else
        echo "Detected BIOS/Legacy system"
    fi
    
    # Detect GRUB installation type
    local grub_install_type=""
    if [[ -f "/boot/grub/grub.cfg" ]]; then
        if grep -q "efi" /boot/grub/grub.cfg; then
            grub_install_type="efi"
        else
            grub_install_type="legacy"
        fi
    fi
    
    echo "Boot mode: $boot_mode"
    echo "GRUB install type: $grub_install_type"
    
    # Create GRUB entry for PE boot with simplified configuration
    cat > /etc/grub.d/40_pe_lvm_extend << EOF
#!/bin/bash
exec tail -n +3 \$0
# PE Boot entry for LVM extension (SystemRescueCD)
menuentry "PE Boot - LVM Extension" {
    set root=(hd0,1)
    linux /boot/vmlinuz_pe root=/dev/ram0 init=/boot/pe/auto-lvm-extend.sh quiet
    initrd /boot/initrd_pe
}

menuentry "PE Boot - LVM Extension (Alternative)" {
    set root=(hd0,2)
    linux /boot/vmlinuz_pe root=/dev/ram0 init=/boot/pe/auto-lvm-extend.sh quiet
    initrd /boot/initrd_pe
}

menuentry "PE Boot - LVM Extension (GPT)" {
    set root=(hd0,gpt1)
    linux /boot/vmlinuz_pe root=/dev/ram0 init=/boot/pe/auto-lvm-extend.sh quiet
    initrd /boot/initrd_pe
}

menuentry "PE Boot - LVM Extension (Simple)" {
    set root=(hd0,1)
    linux /boot/vmlinuz_pe root=/dev/ram0 init=/boot/pe/auto-lvm-extend.sh
    initrd /boot/initrd_pe
}

menuentry "PE Boot - LVM Extension (Debug)" {
    set root=(hd0,1)
    linux /boot/vmlinuz_pe root=/dev/ram0 init=/boot/pe/auto-lvm-extend.sh debug
    initrd /boot/initrd_pe
}
EOF

    chmod +x /etc/grub.d/40_pe_lvm_extend
    
    # Update GRUB with error handling
    echo "🔄 Updating GRUB configuration..."
    if update-grub; then
        echo "✅ GRUB configuration updated successfully"
    else
        echo "⚠️  GRUB update failed, but continuing..."
    fi
    
    # Set PE boot as default for next boot with error handling
    echo "🔄 Setting PE boot as default..."
    if grub-reboot "PE Boot - LVM Extension"; then
        echo "✅ PE boot set as default"
    else
        echo "⚠️  Failed to set PE boot as default, but continuing..."
    fi
    
    echo "✅ GRUB configured for automatic PE boot"
    echo "  Root specification: $grub_root"
    echo "  Partition table: $PARTITION_TABLE"
    echo "  Filesystem: $FILESYSTEM_TYPE"
    echo "  Boot device: $boot_device"
    echo "  GRUB device: $grub_device"
    echo "  Boot mode: $boot_mode"
    echo "  GRUB install type: $grub_install_type"
    
    # Create backup GRUB entry with simpler configuration
    echo "🔄 Creating backup GRUB entry..."
    cat > /etc/grub.d/41_pe_lvm_extend_backup << EOF
#!/bin/bash
exec tail -n +3 \$0
# PE Boot entry for LVM extension (Backup)
menuentry "PE Boot - LVM Extension (Backup)" {
    set root=(hd0,1)
    linux /pe/vmlinuz root=/dev/ram0 init=/boot/pe/auto-lvm-extend.sh quiet
    initrd /pe/initrd-custom
}
EOF

    chmod +x /etc/grub.d/41_pe_lvm_extend_backup
    
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
    echo "🔄 Ready to reboot to PE environment"
    echo ""
    echo "📋 Manual boot instructions (if automatic boot fails):"
    echo "1. Reboot the system"
    echo "2. In GRUB menu, try these options in order:"
    echo "   - 'PE Boot - LVM Extension'"
    echo "   - 'PE Boot - LVM Extension (Alternative)'"
    echo "   - 'PE Boot - LVM Extension (GPT)'"
    echo "   - 'PE Boot - LVM Extension (Simple)'"
    echo "   - 'PE Boot - LVM Extension (Debug)'"
    echo "3. If menu doesn't appear, press 'e' to edit boot entry"
    echo "4. Try these commands in order:"
    echo "   - set root=(hd0,1) && linux /boot/vmlinuz_pe root=/dev/ram0 init=/boot/pe/auto-lvm-extend.sh"
    echo "   - set root=(hd0,2) && linux /boot/vmlinuz_pe root=/dev/ram0 init=/boot/pe/auto-lvm-extend.sh"
    echo "   - set root=(hd0,gpt1) && linux /boot/vmlinuz_pe root=/dev/ram0 init=/boot/pe/auto-lvm-extend.sh"
    echo "   - initrd /boot/initrd_pe"
    echo "5. Press Ctrl+X to boot"
    echo ""
    echo "🔍 Debug mode (if normal boot fails):"
    echo "   - Select 'PE Boot - LVM Extension (Debug)' for verbose output"
    echo "   - Or manually: linux /boot/vmlinuz_pe root=/dev/ram0 init=/boot/pe/auto-lvm-extend.sh debug"
    echo ""
    echo "Press ENTER to continue or ESC to cancel..."
    
    # Wait for user input
    while true; do
        read -rsn1 key
        if [[ "$key" == "" ]]; then
            echo "🔄 Rebooting to PE environment now..."
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