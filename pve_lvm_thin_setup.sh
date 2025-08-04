#!/bin/bash

# Proxmox LVM-Thin Size Configuration Script
# Proxmox 설치 완료 후 LVM 디렉토리와 LVM-thin 사이즈를 변경하는 스크립트

# 2025-08-04 22:45:15
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

# Function to check required packages
check_required_packages() {
    echo "� Checkning required packages..."
    
    local missing_packages=()
    
    # Check for bc (calculator)
    if ! command -v bc &> /dev/null; then
        missing_packages+=("bc")
    fi
    
    # Check for e2fsck
    if ! command -v e2fsck &> /dev/null; then
        missing_packages+=("e2fsprogs")
    fi
    
    # Check for resize2fs
    if ! command -v resize2fs &> /dev/null; then
        missing_packages+=("e2fsprogs")
    fi
    
    # Check for LVM tools
    if ! command -v lvs &> /dev/null; then
        missing_packages+=("lvm2")
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

# Function to remove Proxmox storage configurations
remove_proxmox_storage_config() {
    echo "🔧 Removing Proxmox storage configurations..."
    
    # Remove local-lvm storage configuration from Proxmox
    if pvesm status --storage local-lvm >/dev/null 2>&1; then
        echo "📝 Removing local-lvm storage configuration..."
        pvesm remove local-lvm 2>/dev/null || true
    fi
    
    # Update storage.cfg to remove local-lvm references
    if [ -f "/etc/pve/storage.cfg" ]; then
        echo "📝 Updating storage configuration..."
        # Create backup
        cp /etc/pve/storage.cfg /etc/pve/storage.cfg.backup.$(date +%Y%m%d_%H%M%S)
        
        # Remove local-lvm section
        sed -i '/^dir: local-lvm$/,/^$/d' /etc/pve/storage.cfg 2>/dev/null || true
        sed -i '/^lvm: local-lvm$/,/^$/d' /etc/pve/storage.cfg 2>/dev/null || true
        sed -i '/^lvmthin: local-lvm$/,/^$/d' /etc/pve/storage.cfg 2>/dev/null || true
    fi
    
    echo "✅ Proxmox storage configurations updated"
}

# Function to schedule boot-time resize
schedule_boot_resize() {
    echo "🔧 Setting up automatic boot-time resize..."
    
    # Remove Proxmox storage configurations first
    remove_proxmox_storage_config
    
    # Create the resize script with improved error handling
    cat > /usr/local/bin/pve-boot-resize.sh << 'EOF'
#!/bin/bash
# Proxmox Boot-time Root Filesystem Resize Script
# This script runs during early boot to resize root filesystem

set -e

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a /var/log/pve-boot-resize.log
}

# Configuration file
CONFIG_FILE="/etc/pve-boot-resize.conf"

# Check if resize is needed
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_message "No resize configuration found, exiting..."
    exit 0
fi

# Read configuration
source "$CONFIG_FILE"

log_message "Starting boot-time root filesystem resize..."
log_message "Target size: $TARGET_ROOT_SIZE"
log_message "Original size: $ORIGINAL_SIZE"

# Wait for LVM to be ready and activate if needed
log_message "Waiting for LVM to be ready..."
sleep 5

# Ensure LVM is activated
log_message "Activating LVM volume group..."
vgchange -ay pve || {
    log_message "ERROR: Failed to activate LVM volume group"
    exit 1
}

# Wait a bit more for activation
sleep 3

# Check if LVM volume exists
if ! lvs /dev/pve/root >/dev/null 2>&1; then
    log_message "ERROR: LVM volume /dev/pve/root not found"
    log_message "Available volumes:"
    lvs || true
    exit 1
fi

# Get current size and check VG space
current_size=$(lvs --noheadings --units g --nosuffix -o lv_size /dev/pve/root | tr -d ' ')
target_size_num=$(echo "$TARGET_ROOT_SIZE" | sed 's/G//')
vg_size=$(vgs --noheadings --units g --nosuffix -o vg_size pve | tr -d ' ')
free_space=$(vgs --noheadings --units g --nosuffix -o vg_free pve | tr -d ' ')

log_message "Current size: ${current_size}G"
log_message "Target size: ${target_size_num}G"
log_message "VG size: ${vg_size}G"
log_message "Free space: ${free_space}G"

# Check if resize is actually needed
if (( $(echo "$current_size <= $target_size_num" | bc -l) )); then
    log_message "Root volume is already at target size or smaller, no resize needed"
    rm -f "$CONFIG_FILE"
    exit 0
fi

# Special handling for pve_lvm_resize.sh systems (very little free space)
if (( $(echo "$free_space < 1" | bc -l) )); then
    log_message "Detected pve_lvm_resize.sh system with minimal free space"
    log_message "Will need to shrink root volume significantly"
    
    # Calculate how much space we need to free up
    space_to_free=$(echo "scale=2; $current_size - $target_size_num" | bc)
    log_message "Space to free up: ${space_to_free}G"
    
    if (( $(echo "$space_to_free < 10" | bc -l) )); then
        log_message "ERROR: Insufficient space reduction (${space_to_free}G). Need at least 10GB reduction."
        exit 1
    fi
fi

# Create a backup of fstab
cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)

# Try to stop services that might interfere
log_message "Stopping services that might interfere..."
systemctl stop pveproxy pvedaemon pve-cluster pve-firewall pve-ha-lrm pve-ha-crm || true

# Stop additional services that might lock the filesystem
systemctl stop cron rsyslog || true

# Kill processes that might be using the filesystem
log_message "Terminating processes that might interfere..."
# First try gentle approach
lsof / 2>/dev/null | awk 'NR>1 {print $2}' | sort -u | while read pid; do
    [ "$pid" != "$$" ] && kill -TERM "$pid" 2>/dev/null || true
done
sleep 3

# Then force kill if needed
fuser -km / || true
sleep 2

# Ensure no swap is active on the root volume
log_message "Disabling swap if active..."
swapoff -a || true

# Sync and remount root as read-only
log_message "Syncing filesystem..."
sync
sleep 2

log_message "Attempting to remount root filesystem as read-only..."
if ! mount -o remount,ro /; then
    log_message "WARNING: Could not remount root as read-only, attempting force..."
    mount -o remount,ro,force / || {
        log_message "ERROR: Failed to remount root as read-only"
        exit 1
    }
fi

# Check filesystem integrity
log_message "Checking filesystem integrity..."
if ! e2fsck -f -y /dev/pve/root; then
    log_message "ERROR: Filesystem check failed"
    mount -o remount,rw /
    exit 1
fi

# Get filesystem block size and calculate blocks needed
log_message "Calculating filesystem parameters..."
block_size=$(tune2fs -l /dev/pve/root | grep "Block size" | awk '{print $3}')
target_size_bytes=$(echo "$TARGET_ROOT_SIZE" | sed 's/G//' | awk '{print $1 * 1024 * 1024 * 1024}')
target_blocks=$((target_size_bytes / block_size))

log_message "Block size: $block_size bytes"
log_message "Target size: $target_size_bytes bytes ($target_blocks blocks)"

# Resize filesystem first with block count
log_message "Resizing filesystem to $target_blocks blocks..."
if ! resize2fs /dev/pve/root "$target_blocks"; then
    log_message "ERROR: Filesystem resize failed"
    log_message "Attempting with size specification..."
    if ! resize2fs /dev/pve/root "$TARGET_ROOT_SIZE"; then
        log_message "ERROR: Filesystem resize failed completely"
        mount -o remount,rw /
        exit 1
    fi
fi

# Resize logical volume
log_message "Resizing logical volume to $TARGET_ROOT_SIZE..."
if ! lvresize -L "$TARGET_ROOT_SIZE" /dev/pve/root -y; then
    log_message "ERROR: Logical volume resize failed"
    log_message "Attempting to resize filesystem back..."
    resize2fs /dev/pve/root || true
    mount -o remount,rw /
    exit 1
fi

# Final filesystem check and resize to fit the new LV size
log_message "Final filesystem resize to fit logical volume..."
resize2fs /dev/pve/root || {
    log_message "WARNING: Final filesystem resize failed, but LV resize succeeded"
}

# Remount root as read-write
log_message "Remounting root filesystem as read-write..."
if ! mount -o remount,rw /; then
    log_message "ERROR: Failed to remount root as read-write"
    exit 1
fi

# Verify the resize
new_size=$(lvs --noheadings --units g --nosuffix -o lv_size /dev/pve/root | tr -d ' ')
log_message "Resize completed. New size: ${new_size}G"

# Remove configuration file to prevent re-running
rm -f "$CONFIG_FILE"

# Create LVM-thin data volume if this was a pve_lvm_resize.sh system
if [[ -n "$CREATE_DATA_VOLUME" && "$CREATE_DATA_VOLUME" == "true" ]]; then
    log_message "Creating LVM-thin data volume for pve_lvm_resize.sh system..."
    
    # Wait a bit for LVM to settle after resize
    sleep 3
    
    # Check available space
    free_space=$(vgs --noheadings --units g --nosuffix -o vg_free pve | tr -d ' ')
    log_message "Available free space: ${free_space}G"
    
    if (( $(echo "$free_space < 5" | bc -l) )); then
        log_message "ERROR: Insufficient free space (${free_space}G) for data volume"
        log_message "Root resize may not have freed enough space"
    else
        # Create thin pool with remaining space
        if lvcreate -l 100%FREE -T pve/data; then
            log_message "LVM-thin pool created successfully"
            
            # Wait for thin pool to be ready
            sleep 2
            
            # Get thin pool size for thin volume creation
            thin_pool_size=$(lvs --noheadings --units g --nosuffix -o lv_size /dev/pve/data | tr -d ' ')
            log_message "Thin pool size: ${thin_pool_size}G"
            
            # Create thin volume (use 95% of pool size for over-provisioning)
            thin_volume_size=$(echo "scale=0; $thin_pool_size * 95 / 100" | bc)
            
            if lvcreate -V ${thin_volume_size}G -T pve/data -n data; then
                log_message "LVM-thin data volume created successfully (${thin_volume_size}G)"
                
                # Configure Proxmox storage for the new LVM-thin volume
                log_message "Configuring Proxmox storage for LVM-thin..."
                
                # Wait for the volume to be ready
                sleep 2
                
                # Add LVM-thin storage configuration
                cat >> /etc/pve/storage.cfg << STORAGE_EOF

lvmthin: local-lvm
	thinpool data
	vgname pve
	content vztmpl,backup,iso,rootdir,images
	nodes $(hostname)
STORAGE_EOF
                
                log_message "Proxmox LVM-thin storage configuration added"
                log_message "LVM-thin setup completed during boot!"
                log_message "pve_lvm_resize.sh system recovery completed successfully!"
            else
                log_message "ERROR: Failed to create thin volume"
            fi
        else
            log_message "ERROR: Failed to create thin pool"
        fi
    fi
fi

# Restart services
log_message "Restarting Proxmox services..."
systemctl start pve-cluster pvedaemon pveproxy || true

log_message "Boot-time resize completed successfully!"
log_message "System will continue normal boot process..."

exit 0
EOF

    chmod +x /usr/local/bin/pve-boot-resize.sh
    
    # Create systemd service with improved timing
    cat > /etc/systemd/system/pve-boot-resize.service << 'EOF'
[Unit]
Description=Proxmox Boot-time Root Filesystem Resize
DefaultDependencies=false
After=systemd-remount-fs.service lvm2-activation.service lvm2-monitor.service
Before=local-fs.target systemd-fsck-root.service multi-user.target
Conflicts=shutdown.target reboot.target halt.target
RequiresMountsFor=/
ConditionPathExists=/etc/pve-boot-resize.conf
ConditionVirtualization=!container

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pve-boot-resize.sh
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=yes
TimeoutSec=600
KillMode=none
SuccessExitStatus=0
FailureAction=none

[Install]
WantedBy=sysinit.target
EOF

    # Create configuration file
    cat > /etc/pve-boot-resize.conf << EOF
TARGET_ROOT_SIZE="$ROOT_SIZE_CALC"
ORIGINAL_SIZE="$(lvs --noheadings --units g --nosuffix -o lv_size /dev/pve/root | tr -d ' ')G"
CREATE_DATA_VOLUME="$PVE_LVM_RESIZE_DETECTED"
CREATED_DATE="$(date)"
EOF

    # Enable the service
    systemctl enable pve-boot-resize.service
    
    # Create a fallback script for manual execution
    cat > /usr/local/bin/pve-manual-resize.sh << 'EOF'
#!/bin/bash
# Manual fallback script for root filesystem resize
echo "Manual Root Filesystem Resize Script"
echo "This script should be run from a rescue environment"
echo ""

if [ ! -f "/etc/pve-boot-resize.conf" ]; then
    echo "ERROR: No resize configuration found"
    exit 1
fi

source /etc/pve-boot-resize.conf
echo "Target size: $TARGET_ROOT_SIZE"
echo ""

echo "Steps to perform manually:"
echo "1. Boot from Proxmox installation media or live Linux"
echo "2. Activate LVM: vgchange -ay pve"
echo "3. Check filesystem: e2fsck -f /dev/pve/root"
echo "4. Shrink filesystem: resize2fs /dev/pve/root $TARGET_ROOT_SIZE"
echo "5. Shrink LV: lvresize -L $TARGET_ROOT_SIZE /dev/pve/root"
echo "6. Remove config: rm -f /etc/pve-boot-resize.conf"
echo "7. Reboot to normal system"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

echo "Activating LVM..."
vgchange -ay pve

echo "Checking filesystem..."
e2fsck -f /dev/pve/root

echo "Resizing filesystem..."
resize2fs /dev/pve/root "$TARGET_ROOT_SIZE"

echo "Resizing logical volume..."
lvresize -L "$TARGET_ROOT_SIZE" /dev/pve/root

echo "Cleaning up..."
rm -f /etc/pve-boot-resize.conf

echo "Manual resize completed!"
EOF
    chmod +x /usr/local/bin/pve-manual-resize.sh
    
    echo "✅ Boot-time resize scheduled successfully!"
    echo ""
    echo "📋 What happens next:"
    echo "1. System will reboot"
    echo "2. During boot, root filesystem will be resized automatically"
    echo "3. System will boot normally with resized root volume"
    echo "4. Re-run this script to create LVM-thin data volume"
    echo ""
    echo "🔍 Monitoring:"
    echo "   - Service status: systemctl status pve-boot-resize.service"
    echo "   - Resize log: /var/log/pve-boot-resize.log"
    echo ""
    echo "🆘 Fallback option:"
    echo "   If boot resize fails, use: /usr/local/bin/pve-manual-resize.sh"
    echo "   (Run from rescue environment)"
    echo ""
    
    # For pve_lvm_resize.sh systems, automatically reboot
    if [[ "$PVE_LVM_RESIZE_DETECTED" == "true" ]]; then
        echo "🔄 Automatically rebooting system for pve_lvm_resize.sh recovery..."
        echo "   System will reboot in 10 seconds..."
        echo "   After reboot, the system will be fully configured with LVM-thin."
        sleep 10
        reboot
    else
        # For other systems, ask for confirmation
        read -p "Reboot now to apply resize? (y/N): " reboot_now
        if [[ "$reboot_now" == "y" || "$reboot_now" == "Y" ]]; then
            echo "🔄 Rebooting system..."
            sleep 3
            reboot
        else
            echo "⚠️  Please reboot manually to apply the resize."
            echo "   After reboot, re-run this script to create LVM-thin data volume."
            exit 0
        fi
    fi
}

# Function to check if system was processed by pve_lvm_resize.sh
check_pve_lvm_resize_system() {
    echo "🔍 Checking if system was processed by pve_lvm_resize.sh..."
    
    # Check if data volume is missing (key indicator of pve_lvm_resize.sh usage)
    if ! lvs /dev/pve/data >/dev/null 2>&1; then
        # Get current root size and VG size
        current_root_size=$(lvs --noheadings --units g --nosuffix -o lv_size /dev/pve/root | tr -d ' ')
        total_vg_size=$(vgs --noheadings --units g --nosuffix -o vg_size pve | tr -d ' ')
        free_space=$(vgs --noheadings --units g --nosuffix -o vg_free pve | tr -d ' ')
        
        # Calculate usage percentage
        root_usage_percent=$(echo "scale=2; $current_root_size * 100 / $total_vg_size" | bc)
        
        # If root uses >95% and no data volume exists, likely pve_lvm_resize.sh was used
        if (( $(echo "$root_usage_percent > 95" | bc -l) )) && (( $(echo "$free_space < 2" | bc -l) )); then
            echo "🔍 DETECTED: System appears to have been processed by pve_lvm_resize.sh"
            echo "   - No data volume exists"
            echo "   - Root volume uses ${root_usage_percent}% of total space"
            echo "   - Free space: ${free_space}GB"
            echo ""
            echo "🔧 This system needs special handling for LVM-thin setup."
            echo "   Root volume must be shrunk first to create space for data volume."
            echo ""
            
            echo "✅ Automatic recovery will be configured for pve_lvm_resize.sh system."
            echo "   This system will be processed with safe default settings."
            PVE_LVM_RESIZE_DETECTED=true
            return 0
        fi
    fi
    
    echo "✅ System appears to be in standard configuration."
    PVE_LVM_RESIZE_DETECTED=false
}

# Function to check if boot resize was completed
check_boot_resize_status() {
    if [[ -f "/var/log/pve-boot-resize.log" ]]; then
        echo "🔍 Checking boot-time resize status..."
        echo ""
        echo "📋 Boot resize log:"
        tail -10 /var/log/pve-boot-resize.log
        echo ""
        
        if grep -q "Boot-time resize completed successfully" /var/log/pve-boot-resize.log; then
            echo "✅ Boot-time resize was completed successfully!"
            
            # Check if LVM-thin was also created during boot
            if grep -q "LVM-thin setup completed during boot" /var/log/pve-boot-resize.log; then
                echo "✅ LVM-thin data volume was also created during boot!"
                echo "   Your system is now fully configured with LVM-thin storage."
                echo ""
                echo "📊 Current LVM status:"
                lvs --units g
                echo ""
                echo "💡 Next steps:"
                echo "1. Go to Proxmox web interface → Datacenter → Storage"
                echo "2. Edit 'local' storage and add content types (Disk image, Container)"
                echo "3. Your LVM-thin storage is ready for VMs and containers!"
                echo ""
                echo "🎉 Setup completed! No further action needed."
                exit 0
            else
                echo "   Root resize completed, but data volume creation is still needed."
                echo "   Continuing with LVM-thin data volume setup..."
            fi
            echo ""
            return 0
        else
            echo "⚠️  Boot-time resize may have failed or is incomplete."
            echo "   Check the full log: /var/log/pve-boot-resize.log"
            echo ""
            read -p "Continue anyway? (y/N): " continue_anyway
            if [[ "$continue_anyway" != "y" && "$continue_anyway" != "Y" ]]; then
                echo "❌ Operation cancelled."
                exit 1
            fi
        fi
    fi
    
    # Check if resize service is still pending
    if [[ -f "/etc/pve-boot-resize.conf" ]]; then
        echo "⚠️  Boot-time resize is still scheduled but not completed."
        echo "   Configuration file still exists: /etc/pve-boot-resize.conf"
        echo ""
        echo "💡 Possible reasons:"
        echo "   1. System hasn't been rebooted yet"
        echo "   2. Resize service failed during boot"
        echo "   3. Service was disabled"
        echo ""
        
        # Check service status
        if systemctl is-enabled pve-boot-resize.service >/dev/null 2>&1; then
            echo "🔍 Service status: $(systemctl is-active pve-boot-resize.service 2>/dev/null || echo 'inactive')"
            echo "   Service is enabled but may have failed"
        else
            echo "🔍 Service is not enabled"
        fi
        
        echo ""
        read -p "Do you want to remove the pending resize and continue? (y/N): " remove_pending
        if [[ "$remove_pending" == "y" || "$remove_pending" == "Y" ]]; then
            rm -f /etc/pve-boot-resize.conf
            systemctl disable pve-boot-resize.service 2>/dev/null || true
            echo "✅ Pending resize configuration removed."
        else
            echo "❌ Please reboot to complete the resize or fix the issue first."
            exit 1
        fi
    fi
}

# Function to check system compatibility
check_system_compatibility() {
    echo "🔍 Checking system compatibility..."
    
# Check if this system was processed by pve_lvm_resize.sh
    check_pve_lvm_resize_system
    
    # Check boot resize status first
    check_boot_resize_status
    
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
    if [[ "$PVE_LVM_RESIZE_DETECTED" == "true" ]]; then
        # Special handling for pve_lvm_resize.sh systems - use safe automatic defaults
        current_usage=$(df / | awk 'NR==2 {print $3}')
        current_usage_gb=$(echo "scale=0; $current_usage / 1024 / 1024 + 8" | bc)  # Add 8GB buffer for safety
        
        # Ensure minimum 20GB for root
        if (( $(echo "$current_usage_gb < 20" | bc -l) )); then
            current_usage_gb=20
        fi
        
        echo "🔧 Automatic Size Configuration for pve_lvm_resize.sh System:"
        echo "   Current root usage: $(echo "scale=1; $current_usage / 1024 / 1024" | bc)GB"
        echo "   Current root size: $(lvs --noheadings --units g --nosuffix -o lv_size /dev/pve/root | tr -d ' ')GB"
        echo "   Selected root size: ${current_usage_gb}GB (safe automatic)"
        echo ""
        echo "⚠️  Root volume will be shrunk and LVM-thin data volume will be created."
        echo "   This will happen automatically during next boot."
        echo ""
        
        ROOT_SIZE="${current_usage_gb}G"
        DATA_SIZE="remaining"
        echo "✅ Auto-selected: Root ${current_usage_gb}GB, Data remaining space (LVM-thin)"
    elif [[ "$SYSTEM_TYPE" == "post_resize" || "$SYSTEM_TYPE" == "limited_space" ]]; then
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
        
        # For pve_lvm_resize.sh systems, automatically schedule boot resize
        if [[ "$PVE_LVM_RESIZE_DETECTED" == "true" ]]; then
            echo "🔧 Automatically scheduling boot-time resize for pve_lvm_resize.sh system..."
            echo "   This is required for remote systems without console access."
            schedule_boot_resize
            return 0
        else
            # For other systems, provide options
            echo "🔧 Root filesystem shrinking options:"
            echo "1. Schedule automatic resize on next boot (Recommended)"
            echo "2. Manual offline operation (Advanced users)"
            echo "3. Cancel and choose larger root size"
            echo ""
            
            read -p "Select option (1-3): " shrink_option
            
            case $shrink_option in
                1)
                    echo "✅ Scheduling automatic resize on next boot..."
                    schedule_boot_resize
                    return 0
                    ;;
                2)
                    echo ""
                    echo "🚨 CRITICAL: Manual offline operation required!"
                    echo "📋 Manual steps:"
                    echo "   1. Boot from Proxmox installation media or live Linux"
                    echo "   2. Activate LVM: vgchange -ay pve"
                    echo "   3. Check filesystem: e2fsck -f /dev/pve/root"
                    echo "   4. Shrink filesystem: resize2fs /dev/pve/root $ROOT_SIZE_CALC"
                    echo "   5. Shrink LV: lvresize -L $ROOT_SIZE_CALC /dev/pve/root"
                    echo "   6. Reboot back to normal system"
                    echo "   7. Re-run this script to create LVM-thin data volume"
                    echo ""
                    echo "❌ Cannot proceed with online root filesystem shrinking."
                    exit 1
                    ;;
                3)
                    echo "❌ Operation cancelled. Please restart and choose a larger root size."
                    exit 1
                    ;;
                *)
                    echo "❌ Invalid option. Scheduling automatic resize..."
                    schedule_boot_resize
                    return 0
                    ;;
            esac
        fi
        
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
    
    # Configure Proxmox storage for the new LVM-thin volume
    echo "🔧 Configuring Proxmox storage..."
    configure_proxmox_storage
}

# Function to configure Proxmox storage
configure_proxmox_storage() {
    echo "📝 Configuring Proxmox storage for LVM-thin..."
    
    # Remove any existing local-lvm configuration
    if pvesm status --storage local-lvm >/dev/null 2>&1; then
        echo "📝 Removing existing local-lvm storage configuration..."
        pvesm remove local-lvm 2>/dev/null || true
    fi
    
    # Wait for LVM-thin volume to be ready
    sleep 2
    
    # Check if storage.cfg exists and create backup
    if [ -f "/etc/pve/storage.cfg" ]; then
        cp /etc/pve/storage.cfg /etc/pve/storage.cfg.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Add LVM-thin storage configuration
    if ! grep -q "lvmthin: local-lvm" /etc/pve/storage.cfg 2>/dev/null; then
        echo "📝 Adding LVM-thin storage configuration..."
        cat >> /etc/pve/storage.cfg << 'STORAGE_EOF'

lvmthin: local-lvm
	thinpool data
	vgname pve
	content vztmpl,backup,iso,rootdir,images
STORAGE_EOF
        echo "✅ LVM-thin storage configuration added"
    else
        echo "✅ LVM-thin storage configuration already exists"
    fi
    
    # Restart PVE storage daemon to reload configuration
    echo "🔄 Restarting PVE storage daemon..."
    systemctl restart pve-storage || true
    
    # Verify storage configuration
    sleep 3
    if pvesm status --storage local-lvm >/dev/null 2>&1; then
        echo "✅ LVM-thin storage is now available in Proxmox"
    else
        echo "⚠️  LVM-thin storage may need manual configuration in Proxmox web interface"
    fi

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

# Special handling for pve_lvm_resize.sh systems
if [[ "$PVE_LVM_RESIZE_DETECTED" == "true" ]]; then
    echo ""
    echo "🔍 DETECTED: pve_lvm_resize.sh system"
    echo "   This system will be automatically configured for remote operation."
    echo "   No user input will be required during boot-time resize."
    echo "   System will automatically reboot and complete the setup."
    echo ""
    echo "📋 What will happen:"
    echo "   1. Boot-time resize service will be configured"
    echo "   2. System will reboot automatically"
    echo "   3. During boot: Root volume will be shrunk"
    echo "   4. During boot: LVM-thin data volume will be created"
    echo "   5. System will boot normally with LVM-thin configured"
    echo ""
fi

echo ""

read -p "Continue with LVM resize operation? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ Operation cancelled."
    exit 1
fi

# Check and install required packages
check_required_packages

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
echo "📊 Storage usage:"
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