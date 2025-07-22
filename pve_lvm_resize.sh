#!/bin/bash

# Proxmox LVM Resize Script
# local-lvm을 local에 통합하는 스크립트

set -e

echo "=============================="
echo "Proxmox LVM Resize Tool"
echo "Integrating local-lvm into local"
echo "=============================="

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
   echo "sudo ./pve_lvm_resize.sh"
   exit 1
fi

# Check current LVM status
echo "📊 Checking current LVM status..."
lvs

echo ""
echo "⚠️  Warnings:"
echo "1. Stop all VMs and CTs before performing this operation."
echo "2. All data stored in local-lvm will be deleted."
echo "3. Do not reboot the system during the operation."
echo ""

read -p "Continue? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ Operation cancelled."
    exit 1
fi

# Check if data volume exists
if ! lvs /dev/pve/data >/dev/null 2>&1; then
    echo "❌ /dev/pve/data volume does not exist."
    echo "It may already be integrated or have a different configuration."
    exit 1
fi

echo "🔄 Removing local-lvm data volume..."
lvremove -f /dev/pve/data

echo "🔄 Resizing root volume..."
lvresize -l +100%FREE /dev/pve/root

echo "🔄 Resizing filesystem..."
resize2fs -p /dev/pve/root

echo "✅ LVM resize completed!"
echo ""
echo "📊 Final LVM status:"
lvs

echo ""
echo "💡 Next steps:"
echo "1. Check storage settings in Proxmox web interface."
echo "2. Add content to local storage."
echo "3. Restart VMs and CTs." 