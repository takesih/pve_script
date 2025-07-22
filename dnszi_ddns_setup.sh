#!/bin/bash

# DNSZI DDNS Setup Script
# Automatically configure DDNS updates for DNSZI service

set -e

# Configuration
CRON_FILE="/etc/crontab"
DDNS_SCRIPT="/usr/local/bin/dnszi_ddns_update.sh"

echo "=============================="
echo "DNSZI DDNS Setup Tool"
echo "=============================="
echo "1. Install DDNS Auto Update"
echo "2. Remove DDNS Auto Update"
echo "=============================="

read -p "Choose an option (1 or 2): " choice

if [[ "$choice" == "1" ]]; then
    echo "🔄 Installing DNSZI DDNS Auto Update..."
    
    # Get user input for configuration
    echo ""
    echo "📝 Please enter your DNSZI configuration:"
    read -p "Username: " username
    read -p "Auth Key: " auth_key
    read -p "Domain: " domain
    read -p "Alias/Record: " alias
    
    # Validate inputs
    if [[ -z "$username" || -z "$auth_key" || -z "$domain" || -z "$alias" ]]; then
        echo "❌ All fields are required. Please try again."
        exit 1
    fi
    
    # Build DDNS URL
    DDNS_URL="https://ddns.dnszi.com/set.html?user=${username}&auth=${auth_key}&domain=${domain}&record=${alias}"
    
    echo ""
    echo "📋 Configuration Summary:"
    echo "- Username: $username"
    echo "- Domain: $domain"
    echo "- Alias: $alias"
    echo "- URL: $DDNS_URL"
    echo ""
    
    read -p "Continue with this configuration? (y/N): " confirm_config
    if [[ "$confirm_config" != "y" && "$confirm_config" != "Y" ]]; then
        echo "❌ Configuration cancelled."
        exit 1
    fi
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo "❌ This script must be run as root."
        echo "sudo ./dnszi_ddns_setup.sh"
        exit 1
    fi
    
    # Check if cron is installed
    if ! command -v cron &> /dev/null; then
        echo "📦 Installing cron..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y cron
        elif command -v yum &> /dev/null; then
            yum install -y cronie
        elif command -v dnf &> /dev/null; then
            dnf install -y cronie
        else
            echo "❌ Package manager not found. Please install cron manually."
            exit 1
        fi
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        echo "❌ curl is not installed. Please install curl first."
        exit 1
    fi
    
    # Create DDNS update script
    echo "📝 Creating DDNS update script..."
    cat > "$DDNS_SCRIPT" << EOF
#!/bin/bash
# DNSZI DDNS Update Script
echo "🔄 Updating DNSZI DDNS..."
response=\$(curl -s '${DDNS_URL}')
echo "Response: \$response"
if [ \$? -eq 0 ]; then
    echo "✅ DDNS update completed successfully"
else
    echo "❌ DDNS update failed"
fi
EOF
    
    chmod +x "$DDNS_SCRIPT"
    
    # Test the DDNS update
    echo "🧪 Testing DDNS update..."
    if curl -s "$DDNS_URL" > /dev/null; then
        echo "✅ DDNS update test successful"
    else
        echo "⚠️ DDNS update test failed, but continuing..."
    fi
    
    # Add to crontab
    echo "📅 Adding to crontab..."
    
    # Check if crontab entry already exists
    if grep -q "dnszi_ddns_update.sh" "$CRON_FILE"; then
        echo "⚠️ Crontab entry already exists. Removing old entry..."
        sed -i '/dnszi_ddns_update.sh/d' "$CRON_FILE"
    fi
    
    # Add new crontab entries
    echo "" >> "$CRON_FILE"
    echo "# DNSZI DDNS Auto Update" >> "$CRON_FILE"
    echo "# Update on boot" >> "$CRON_FILE"
    echo "@reboot root $DDNS_SCRIPT" >> "$CRON_FILE"
    echo "# Update every 3 hours" >> "$CRON_FILE"
    echo "0 */3 * * * root $DDNS_SCRIPT" >> "$CRON_FILE"
    
    # Restart cron service
    echo "🔄 Restarting cron service..."
    if command -v systemctl &> /dev/null; then
        systemctl restart cron
    elif command -v service &> /dev/null; then
        service cron restart
    fi
    
    echo "✅ DNSZI DDNS Auto Update installed successfully!"
    echo ""
    echo "📋 Configuration:"
    echo "- Update script: $DDNS_SCRIPT"
    echo "- Crontab file: $CRON_FILE"
    echo "- Boot update: Enabled"
    echo "- Schedule: Every 3 hours"
    echo ""
    
    # Execute the DDNS update script once to test
    echo "🧪 Executing DDNS update script for testing..."
    if "$DDNS_SCRIPT"; then
        echo "✅ DDNS update script executed successfully!"
    else
        echo "⚠️ DDNS update script execution failed, but installation completed."
    fi
    
    echo ""
    echo "💡 To check status:"
    echo "crontab -l"
    echo "tail -f /var/log/syslog | grep dnszi"

elif [[ "$choice" == "2" ]]; then
    echo "🔄 Removing DNSZI DDNS Auto Update..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo "❌ This script must be run as root."
        echo "sudo ./dnszi_ddns_setup.sh"
        exit 1
    fi
    
    # Remove from crontab
    if grep -q "dnszi_ddns_update.sh" "$CRON_FILE"; then
        echo "🗑️ Removing crontab entries..."
        sed -i '/dnszi_ddns_update.sh/d' "$CRON_FILE"
        sed -i '/DNSZI DDNS Auto Update/d' "$CRON_FILE"
        sed -i '/Update on boot/d' "$CRON_FILE"
        sed -i '/Update every 3 hours/d' "$CRON_FILE"
        # Remove empty lines that might be left
        sed -i '/^$/d' "$CRON_FILE"
    else
        echo "ℹ️ No crontab entries found to remove."
    fi
    
    # Remove update script
    if [[ -f "$DDNS_SCRIPT" ]]; then
        echo "🗑️ Removing update script..."
        rm -f "$DDNS_SCRIPT"
    else
        echo "ℹ️ Update script not found."
    fi
    
    # Restart cron service
    echo "🔄 Restarting cron service..."
    if command -v systemctl &> /dev/null; then
        systemctl restart cron
    elif command -v service &> /dev/null; then
        service cron restart
    fi
    
    echo "✅ DNSZI DDNS Auto Update removed successfully!"

else
    echo "❌ Invalid option selected."
    exit 1
fi 