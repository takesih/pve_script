#!/bin/bash

# ==============================
# Proxmox LVM Auto-Resize PE System
# Fully Automated Disk Re-partitioning and LVM Resizing
# V 250806006000
# ==============================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PE_FLAG_FILE="/mnt/pve_pe_done"
PE_LOG_FILE="/var/log/pve-pe-resize.log"
PE_GRUB_ENTRY="/etc/grub.d/40_pe_lvm_auto_resize"
PE_BOOT_FILES=("/boot/initrd_pe" "/boot/vmlinuz_pe" "/boot/pe")
PE_GRUB_FILES=("$PE_GRUB_ENTRY")

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$PE_LOG_FILE" 2>/dev/null || echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$PE_LOG_FILE" 2>/dev/null || echo -e "${RED}[ERROR]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$PE_LOG_FILE" 2>/dev/null || echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$PE_LOG_FILE" 2>/dev/null || echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running in PE environment
is_pe_environment() {
    [[ -f "/proc/cmdline" ]] && grep -q "pve_pe_auto_resize" /proc/cmdline 2>/dev/null
}

# Check if PE operations are complete
is_pe_complete() {
    [[ -f "$PE_FLAG_FILE" ]]
}

# Cleanup PE environment
cleanup_pe_environment() {
    log "🧹 Cleaning up PE environment..."
    
    # Remove PE boot files
    for file in "${PE_BOOT_FILES[@]}"; do
        if [[ -e "$file" ]]; then
            rm -rf "$file"
            log "  - Removed: $file"
        fi
    done
    
    # Remove GRUB entry
    for file in "${PE_GRUB_FILES[@]}"; do
        if [[ -e "$file" ]]; then
            rm -f "$file"
            log "  - Removed: $file"
        fi
    done
    
    # Update GRUB
    if command -v update-grub >/dev/null 2>&1; then
        log "🔄 Updating GRUB configuration..."
        if update-grub; then
            log "✅ GRUB updated successfully"
        else
            warn "⚠️  GRUB update failed"
        fi
    fi
    
    # Remove flag file
    if [[ -f "$PE_FLAG_FILE" ]]; then
        rm -f "$PE_FLAG_FILE"
        log "  - Removed flag file: $PE_FLAG_FILE"
    fi
    
    log "✅ PE environment cleanup completed"
}

# Create PE boot script
create_pe_boot_script() {
    local script_path="/boot/pe/auto-lvm.sh"
    
    log "📝 Creating PE boot script..."
    
    mkdir -p /boot/pe
    
    cat > "$script_path" << 'EOF'
#!/bin/bash

# ==============================
# PE Auto LVM Resize Script
# ==============================

set -euo pipefail

# Logging
LOG_FILE="/tmp/pe-lvm.log"
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[ERROR] $1" | tee -a "$LOG_FILE"
}

# Initialize system
log "🚀 PE Auto LVM Resize starting..."

# Wait for system to be ready
sleep 5

# Check if root filesystem is mounted
if ! mountpoint -q /; then
    error "Root filesystem not mounted"
    exit 1
fi

# Check if we're in the right environment
if ! command -v lvs >/dev/null 2>&1; then
    error "LVM tools not available"
    exit 1
fi

log "📊 Current LVM status:"
lvs --units g 2>/dev/null || log "lvs not available"
echo ""

# Step 1: Check and repair filesystem
log "🔍 Checking filesystem integrity..."
if e2fsck -f /dev/pve/root; then
    log "✅ Filesystem check completed"
else
    error "❌ Filesystem check failed"
    exit 1
fi

# Step 2: Resize filesystem to 15G
log "📏 Resizing filesystem to 15G..."
if resize2fs /dev/pve/root 15G; then
    log "✅ Filesystem resized to 15G"
else
    error "❌ Filesystem resize failed"
    exit 1
fi

# Step 3: Reduce logical volume to 15G
log "📏 Reducing logical volume to 15G..."
if lvreduce -L 15G /dev/pve/root -y; then
    log "✅ Logical volume reduced to 15G"
else
    error "❌ Logical volume reduction failed"
    exit 1
fi

# Step 4: Remove existing data volume if exists
log "🗑️  Removing existing data volume..."
if lvremove -y /dev/pve/data 2>/dev/null; then
    log "✅ Existing data volume removed"
else
    log "ℹ️  No existing data volume to remove"
fi

# Step 5: Create new thin pool with remaining space
log "📦 Creating thin pool with remaining space..."
AVAILABLE_SPACE=$(vgs --noheadings --units g --nosuffix -o vg_free pve 2>/dev/null | tr -d ' ')
if [[ -n "$AVAILABLE_SPACE" ]] && [[ "$AVAILABLE_SPACE" -gt 0 ]]; then
    log "📏 Available space: ${AVAILABLE_SPACE}G"
    
    if lvcreate -L ${AVAILABLE_SPACE}G -T pve/data; then
        log "✅ Thin pool created successfully"
    else
        error "❌ Thin pool creation failed"
        exit 1
    fi
else
    error "❌ Cannot determine available space"
    exit 1
fi

# Step 6: Verify operations
log "🔍 Verifying LVM operations..."
lvs --units g 2>/dev/null || log "lvs not available"
echo ""

# Step 7: Create completion flag
log "✅ Creating completion flag..."
if touch /mnt/pve_pe_done; then
    log "✅ Completion flag created"
else
    error "❌ Failed to create completion flag"
fi

# Step 8: Reboot
log "🔄 Rebooting in 5 seconds..."
sleep 5
reboot

EOF

    chmod +x "$script_path"
    log "✅ PE boot script created: $script_path"
}

# Create minimal initrd with embedded script
create_minimal_initrd() {
    local workdir="/tmp/initrd-minimal"
    
    log "🔧 Creating minimal initrd with embedded LVM script..."
    
    # Clean up previous workdir
    rm -rf "$workdir"
    mkdir -p "$workdir"
    
    # Create essential directory structure
    mkdir -p "$workdir"/{bin,sbin,etc,proc,dev,usr/bin,usr/sbin,lib,lib64}
    
    # Copy essential binaries
    cp /bin/busybox "$workdir/bin/" 2>/dev/null || {
        # If busybox not available, copy essential tools
        for tool in sh mount mknod reboot sleep df echo ls cat; do
            if command -v "$tool" >/dev/null 2>&1; then
                cp "$(command -v "$tool")" "$workdir/bin/"
            fi
        done
    }
    
    # Create symlinks for essential tools
    cd "$workdir/bin"
    for tool in sh mount mknod reboot sleep df echo ls cat; do
        if [[ -f "$tool" ]]; then
            ln -sf "$tool" "$tool"
        fi
    done
    
    # Copy LVM tools if available
    for tool in lvs pvs vgs lvreduce lvcreate lvremove resize2fs e2fsck; do
        if command -v "$tool" >/dev/null 2>&1; then
            cp "$(command -v "$tool")" "$workdir/bin/"
        fi
    done
    
    # Create init script
    cat > "$workdir/init" << 'EOF'
#!/bin/sh

# ==============================
# Minimal PE Init Script
# ==============================

set -e

echo "🚀 PE Environment starting..."

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Create essential device nodes
mknod /dev/console c 5 1
mknod /dev/null c 1 3
mknod /dev/zero c 1 5

# Wait for system to be ready
sleep 3

# Execute LVM resize script
if [[ -f "/boot/pe/auto-lvm.sh" ]]; then
    echo "📝 Executing LVM resize script..."
    /bin/sh /boot/pe/auto-lvm.sh
else
    echo "❌ LVM script not found"
    reboot
fi

EOF

    chmod +x "$workdir/init"
    
    # Pack initrd
    cd "$workdir"
    find . -type f -o -type d | grep -v "^\.$" | grep -v "/dri/" | grep -v "/debug/" | grep -v "/irq/" | grep -v "/fscaps" | grep -v "/uevent_helper" | grep -v "/rcu_normal" | grep -v "/crash_elfcorehdr" | cpio -o -H newc 2>/dev/null | gzip > /boot/initrd_pe
    
    # Copy kernel
    cp /boot/vmlinuz-$(uname -r) /boot/vmlinuz_pe
    
    log "✅ Minimal initrd created successfully"
}

# Create GRUB entry
create_grub_entry() {
    log "📝 Creating GRUB entry..."
    
    cat > "$PE_GRUB_ENTRY" << 'EOF'
#!/bin/sh
exec tail -n +3 $0
# PE Boot - LVM Auto Resize
menuentry 'PE Boot - LVM Auto Resize' --class debian --class gnu-linux --class gnu --class os {
    set root='(hd0,1)'
    search --no-floppy --fs-uuid --set=root
    linux /boot/vmlinuz_pe root=/dev/ram0 rw pve_pe_auto_resize=1
    initrd /boot/initrd_pe
}
EOF

    chmod +x "$PE_GRUB_ENTRY"
    log "✅ GRUB entry created: $PE_GRUB_ENTRY"
}

# Setup PE environment
setup_pe_environment() {
    log "🔧 Setting up PE environment..."
    
    # Check if already configured
    if [[ -f "$PE_GRUB_ENTRY" ]]; then
        warn "⚠️  PE environment already configured"
        read -p "Reconfigure PE environment? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "❌ PE setup cancelled"
            return 1
        fi
        
        # Clean up existing configuration
        cleanup_pe_environment
    fi
    
    # Create PE boot script
    create_pe_boot_script
    
    # Create minimal initrd
    create_minimal_initrd
    
    # Create GRUB entry
    create_grub_entry
    
    # Update GRUB
    log "🔄 Updating GRUB configuration..."
    if update-grub; then
        log "✅ GRUB configuration updated"
    else
        error "❌ GRUB update failed"
        return 1
    fi
    
    log "✅ PE environment setup completed"
    return 0
}

# Main execution logic
main() {
    echo "=============================="
    echo "Proxmox LVM Auto-Resize PE System"
    echo "Fully Automated Disk Re-partitioning and LVM Resizing"
    echo "V 250806006000"
    echo "=============================="
    
    # Check if running in PE environment
    if is_pe_environment; then
        log "🔍 Running in PE environment"
        # PE environment logic is handled by the init script
        return 0
    fi
    
    # Check if PE operations are complete
    if is_pe_complete; then
        log "✅ PE operations completed, cleaning up..."
        cleanup_pe_environment
        log "🎉 System restored to Proxmox VE"
        return 0
    fi
    
    # Check if we're running as root
    if [[ $EUID -ne 0 ]]; then
        error "❌ This script must be run as root"
        exit 1
    fi
    
    # Check if we're on a Proxmox VE system
    if ! command -v pvesm >/dev/null 2>&1; then
        error "❌ This script is designed for Proxmox VE systems"
        exit 1
    fi
    
    # Check LVM tools
    for tool in lvs pvs vgs lvreduce lvcreate lvremove resize2fs e2fsck; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            error "❌ Required tool not found: $tool"
            exit 1
        fi
    done
    
    # Show current system status
    log "📊 Current system status:"
    lvs --units g 2>/dev/null || log "lvs not available"
    echo ""
    
    # Confirm operation
    echo "🎯 This will:"
    echo "  1. Shrink /dev/pve/root to 15G"
    echo "  2. Create /dev/pve/data as thin-pool with remaining space"
    echo "  3. Remove existing /dev/pve/data if it exists"
    echo "  4. Reboot into PE environment for operations"
    echo "  5. Automatically return to Proxmox VE"
    echo ""
    
    read -p "Proceed with PE setup? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "❌ Operation cancelled"
        exit 0
    fi
    
    # Setup PE environment
    if setup_pe_environment; then
        log "✅ PE environment ready"
        echo ""
        echo "🚀 System will reboot into PE environment in 10 seconds..."
        echo "   Press Ctrl+C to cancel"
        echo ""
        
        for i in {10..1}; do
            echo -ne "\r🔄 Rebooting in $i seconds... "
            sleep 1
        done
        echo ""
        
        log "🔄 Rebooting into PE environment..."
        grub-reboot "PE Boot - LVM Auto Resize"
        reboot
    else
        error "❌ PE environment setup failed"
        exit 1
    fi
}

# Execute main function
main "$@" 