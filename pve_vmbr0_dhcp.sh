#!/bin/bash

INTERFACES_FILE="/etc/network/interfaces"
BACKUP_FILE="/etc/network/interfaces.bak"

echo "=============================="
echo "Proxmox vmbr0 DHCP Config Tool"
echo "1. Convert vmbr0 to DHCP"
echo "2. Restore from Backup"
echo "=============================="
read -p "Choose an option (1 or 2): " choice

if [[ "$choice" == "1" ]]; then
    if [[ -f "$BACKUP_FILE" ]]; then
        echo "⚠️ Backup already exists: $BACKUP_FILE"
        read -p "Do you want to overwrite it? (y/n): " confirm
        if [[ "$confirm" != "y" ]]; then
            echo "❌ Operation cancelled."
            exit 1
        fi
    fi

    cp "$INTERFACES_FILE" "$BACKUP_FILE"

    awk '
    /^iface vmbr0 inet static$/ {
        print "iface vmbr0 inet dhcp"
        skip = 1
        next
    }
    /^iface / { skip = 0 }

    skip && ($1 == "address" || $1 == "gateway") {
        next
    }

    { print }
    ' "$BACKUP_FILE" > "$INTERFACES_FILE"

    echo "✅ vmbr0 successfully converted to DHCP."
    echo "🗂️ Backup saved at: $BACKUP_FILE"

elif [[ "$choice" == "2" ]]; then
    if [[ -f "$BACKUP_FILE" ]]; then
        cp "$BACKUP_FILE" "$INTERFACES_FILE"
        echo "✅ Successfully restored from backup."
    else
        echo "❌ Backup file not found: $BACKUP_FILE"
        exit 1
    fi
else
    echo "❌ Invalid option selected."
    exit 1
fi
