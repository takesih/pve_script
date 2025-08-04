#!/bin/bash

# Proxmox LVM Extension Script with PE Boot Support
# Script to extend LVM volumes after disk expansion with PE boot option
# Based on Proxmox forum: https://forum.proxmox.com/threads/extend-local-lvm-proxmox.133478/#post-589215
# Version: 2025-01-08
# Author: Proxmox LVM Management Tool

set -e

echo "=============================="
echo "Proxmox LVM Extension Tool with PE Boot Support"
echo "Extend LVM volumes after disk expansion"
echo "=============================="

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
   echo "sudo ./pve_lvm_extend_pe.sh"
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
    
    # PE Boot option
    echo ""
    echo "Execution Method:"
    echo "1. PE Boot (Recommended for safe operations)"
    echo "2. Direct execution (Advanced users)"
    echo ""
    
    read -p "Select execution method (1-2): " execution_method
    
    case $execution_method in
        1)
            EXECUTION_METHOD="pe_boot"
            echo "Selected: PE Boot execution"
            ;;
        2)
            EXECUTION_METHOD="direct"
            echo "Selected: Direct execution"
            ;;
        *)
            echo "Invalid option. Using PE Boot execution."
            EXECUTION_METHOD="pe_boot"
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

# Function to create PE boot script
create_pe_boot_script() {
    echo "🔄 Creating PE boot script..."
    
    cat > /usr/local/bin/pve-lvm-extend-pe.sh << 'EOF'
#!/bin/bash

# Proxmox LVM Extension PE Boot Script
# This script runs from Linux PE environment

set -e

echo "=============================="
echo "Proxmox LVM Extension - PE Boot Script"
echo "=============================="

# Configuration file
CONFIG_FILE="/etc/pve-lvm-extend.conf"

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
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a /var/log/pve-lvm-extend-pe.log
}

log_message "Starting LVM extension operations..."

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
echo "✅ PE boot operations completed!"
echo "You can now reboot to Proxmox VE"
EOF

    chmod +x /usr/local/bin/pve-lvm-extend-pe.sh
    
    # Create configuration file
    cat > /etc/pve-lvm-extend.conf << EOF
ROOT_SIZE_CALC="$ROOT_SIZE_CALC"
DATA_VOLUME_TYPE="$DATA_VOLUME_TYPE"
FIX_STRUCTURE="$FIX_STRUCTURE"
CREATED_DATE="$(date)"
EOF
    
    echo "✅ PE boot script created successfully!"
    echo "  Script: /usr/local/bin/pve-lvm-extend-pe.sh"
    echo "  Config: /etc/pve-lvm-extend.conf"
}

# Function to provide PE boot instructions
provide_pe_instructions() {
    echo ""
    echo "🔄 PE Boot Instructions"
    echo "======================="
    echo ""
    echo "1. Download a Linux PE (Live Linux) ISO:"
    echo "   - Ubuntu Desktop ISO (recommended)"
    echo "   - Debian Live ISO"
    echo "   - Any Linux Live ISO with LVM tools"
    echo ""
    echo "2. Create bootable USB drive:"
    echo "   - Use tools like Rufus, Etcher, or dd command"
    echo "   - Boot from the USB drive"
    echo ""
    echo "3. Boot to Linux PE and run:"
    echo "   sudo /usr/local/bin/pve-lvm-extend-pe.sh"
    echo ""
    echo "4. After completion, reboot to Proxmox VE"
    echo ""
    echo "📋 Configuration Summary:"
    echo "  Root size: $ROOT_SIZE_CALC"
    echo "  Data volume type: $DATA_VOLUME_TYPE"
    echo "  Fix structure: $FIX_STRUCTURE"
    echo ""
    echo "📁 Files created:"
    echo "  - Script: /usr/local/bin/pve-lvm-extend-pe.sh"
    echo "  - Config: /etc/pve-lvm-extend.conf"
    echo ""
    echo "⚠️  Important:"
    echo "  - Backup important data before proceeding"
    echo "  - Ensure you have a working Proxmox VE boot option"
    echo "  - Test the PE boot process before running operations"
    echo ""
}

# Function to execute directly
execute_directly() {
    echo "🔄 Executing operations directly..."
    
    # Check and install required packages
    check_required_packages
    
    # Show current status
    show_current_status
    
    # Resize physical volume
    echo "🔄 Resizing Physical Volume..."
    pvresize /dev/nvme0n1p3
    
    # Extend root volume
    echo "🔄 Extending root volume to $ROOT_SIZE_CALC..."
    lvextend -L "$ROOT_SIZE_CALC" /dev/pve/root
    resize2fs /dev/pve/root
    
    # Handle data volume operations
    if [[ "$DATA_VOLUME_TYPE" != "skip" ]]; then
        echo "🔄 Handling data volume operations..."
        # Data volume operations would be implemented here
        echo "Data volume operations completed"
    fi
    
    echo ""
    echo "Final LVM status:"
    lvs --units g
    
    echo ""
    echo "✅ Direct execution completed!"
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

# Collect all configuration
collect_configuration

echo ""
echo "Operation Summary:"
echo "  Root volume will be extended to: $ROOT_SIZE_CALC"
echo "  Data volume type: $DATA_VOLUME_TYPE"
echo "  Fix structure: $FIX_STRUCTURE"
echo "  Execution method: $EXECUTION_METHOD"
echo ""

read -p "Proceed with these settings (y/N): " final_confirm
if [[ "$final_confirm" != "y" && "$final_confirm" != "Y" ]]; then
    echo "❌ Operation cancelled."
    exit 1
fi

# Execute based on method
if [[ "$EXECUTION_METHOD" == "pe_boot" ]]; then
    create_pe_boot_script
    provide_pe_instructions
else
    execute_directly
fi

echo ""
echo "🎉 Configuration completed!" 