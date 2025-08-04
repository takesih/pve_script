#!/bin/bash

# Proxmox VE Temperature Monitor Setup Script
# Adds real-time temperature monitoring to Proxmox VE dashboard

# 2025-08-04
set -e

echo "=============================="
echo "Proxmox VE Temperature Monitor"
echo "Add real-time temperature monitoring to dashboard"
echo "=============================="

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
   echo "sudo ./pve_temperature_monitor.sh"
   exit 1
fi

# Function to check required packages
check_required_packages() {
    echo "🔍 Checking required packages..."
    
    local missing_packages=()
    
    # Check for lm-sensors
    if ! command -v sensors &> /dev/null; then
        missing_packages+=("lm-sensors")
    fi
    
    # Check for smartmontools
    if ! command -v smartctl &> /dev/null; then
        missing_packages+=("smartmontools")
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

# Function to detect sensors
detect_sensors() {
    echo "🔍 Detecting hardware sensors..."
    
    # Run sensors-detect non-interactively
    echo "🔧 Running sensors detection..."
    sensors-detect --auto
    
    # Load sensor modules
    echo "🔧 Loading sensor modules..."
    modprobe coretemp 2>/dev/null || true
    modprobe k10temp 2>/dev/null || true
    modprobe nct6775 2>/dev/null || true
    modprobe it87 2>/dev/null || true
    
    # Test sensors
    echo "📊 Testing sensor detection..."
    if sensors &>/dev/null; then
        echo "✅ Hardware sensors detected successfully"
        sensors
    else
        echo "⚠️  No hardware sensors detected or sensors not working"
        echo "   This may be normal for virtual machines or some hardware"
    fi
    echo ""
}

# Function to backup original files
backup_files() {
    echo "💾 Creating backup of original files..."
    
    local backup_dir="/root/pve_temperature_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup Proxmox files that will be modified
    if [ -f "/usr/share/perl5/PVE/API2/Nodes.pm" ]; then
        cp "/usr/share/perl5/PVE/API2/Nodes.pm" "$backup_dir/"
        echo "✅ Backed up Nodes.pm"
    fi
    
    if [ -f "/usr/share/pve-manager/js/pvemanagerlib.js" ]; then
        cp "/usr/share/pve-manager/js/pvemanagerlib.js" "$backup_dir/"
        echo "✅ Backed up pvemanagerlib.js"
    fi
    
    echo "📁 Backup created in: $backup_dir"
    echo ""
}

# Function to modify Proxmox API
modify_proxmox_api() {
    echo "🔧 Modifying Proxmox API to include temperature data..."
    
    local nodes_pm="/usr/share/perl5/PVE/API2/Nodes.pm"
    
    if [ ! -f "$nodes_pm" ]; then
        echo "❌ Nodes.pm not found at expected location"
        return 1
    fi
    
    # Check if already modified
    if grep -q "thermal-state" "$nodes_pm"; then
        echo "✅ Proxmox API already modified for temperature monitoring"
        return 0
    fi
    
    # Create the temperature monitoring code
    cat > /tmp/temperature_code.pl << 'EOF'
    # Temperature monitoring addition
    my $thermal = {};
    
    # Get CPU temperature from sensors
    if (-x '/usr/bin/sensors') {
        my $sensors_output = `sensors 2>/dev/null`;
        if ($sensors_output) {
            # Parse CPU temperature
            if ($sensors_output =~ /Core\s+\d+:\s+\+?(\d+(?:\.\d+)?)\s*°?C/i) {
                $thermal->{'cpu-thermal'} = $1;
            } elsif ($sensors_output =~ /CPU\s*Temperature:\s*\+?(\d+(?:\.\d+)?)\s*°?C/i) {
                $thermal->{'cpu-thermal'} = $1;
            } elsif ($sensors_output =~ /Tctl:\s*\+?(\d+(?:\.\d+)?)\s*°?C/i) {
                $thermal->{'cpu-thermal'} = $1;
            }
        }
    }
    
    # Get disk temperatures from smartctl
    if (-x '/usr/sbin/smartctl') {
        my @disks = glob('/dev/sd* /dev/nvme*');
        my $max_disk_temp = 0;
        
        foreach my $disk (@disks) {
            next unless -b $disk;
            my $smart_output = `smartctl -A $disk 2>/dev/null`;
            if ($smart_output) {
                # Parse temperature from SMART data
                if ($smart_output =~ /Temperature_Celsius.*?(\d+)/i ||
                    $smart_output =~ /Airflow_Temperature_Cel.*?(\d+)/i ||
                    $smart_output =~ /Temperature.*?(\d+)/i) {
                    $max_disk_temp = $1 if $1 > $max_disk_temp;
                }
            }
        }
        
        $thermal->{'disk-thermal'} = $max_disk_temp if $max_disk_temp > 0;
    }
    
    $res->{'thermal-state'} = $thermal if %$thermal;
EOF
    
    # Find the right place to insert the code (before the return statement)
    local insert_line=$(grep -n "return \$res;" "$nodes_pm" | tail -1 | cut -d: -f1)
    
    if [ -z "$insert_line" ]; then
        echo "❌ Could not find insertion point in Nodes.pm"
        return 1
    fi
    
    # Insert the temperature monitoring code
    head -n $((insert_line - 1)) "$nodes_pm" > /tmp/nodes_pm_new
    cat /tmp/temperature_code.pl >> /tmp/nodes_pm_new
    tail -n +$insert_line "$nodes_pm" >> /tmp/nodes_pm_new
    
    # Replace the original file
    mv /tmp/nodes_pm_new "$nodes_pm"
    rm -f /tmp/temperature_code.pl
    
    echo "✅ Proxmox API modified successfully"
}

# Function to modify Proxmox web interface
modify_web_interface() {
    echo "🔧 Modifying Proxmox web interface to display temperature..."
    
    local pvemanager_js="/usr/share/pve-manager/js/pvemanagerlib.js"
    
    if [ ! -f "$pvemanager_js" ]; then
        echo "❌ pvemanagerlib.js not found at expected location"
        return 1
    fi
    
    # Check if already modified
    if grep -q "thermal-state" "$pvemanager_js"; then
        echo "✅ Web interface already modified for temperature display"
        return 0
    fi
    
    # Create temperature display code
    cat > /tmp/temperature_js.js << 'EOF'
            // Temperature monitoring display
            if (data['thermal-state']) {
                var thermal = data['thermal-state'];
                if (thermal['cpu-thermal']) {
                    items.push({
                        itemId: 'thermal',
                        colspan: 2,
                        printBar: false,
                        title: gettext('CPU Temperature'),
                        textField: 'thermal',
                        renderer: function(value) {
                            return thermal['cpu-thermal'] + '°C';
                        }
                    });
                }
                if (thermal['disk-thermal']) {
                    items.push({
                        itemId: 'disk-thermal',
                        colspan: 2,
                        printBar: false,
                        title: gettext('Disk Temperature'),
                        textField: 'disk-thermal',
                        renderer: function(value) {
                            return thermal['disk-thermal'] + '°C';
                        }
                    });
                }
            }
EOF
    
    # Find the right place to insert (after CPU usage section)
    local insert_line=$(grep -n "title: gettext('CPU usage')" "$pvemanager_js" | head -1 | cut -d: -f1)
    
    if [ -z "$insert_line" ]; then
        echo "❌ Could not find insertion point in pvemanagerlib.js"
        return 1
    fi
    
    # Find the end of the CPU usage block
    local end_line=$(tail -n +$insert_line "$pvemanager_js" | grep -n "})" | head -1 | cut -d: -f1)
    end_line=$((insert_line + end_line))
    
    # Insert the temperature display code
    head -n $end_line "$pvemanager_js" > /tmp/pvemanager_js_new
    cat /tmp/temperature_js.js >> /tmp/pvemanager_js_new
    tail -n +$((end_line + 1)) "$pvemanager_js" >> /tmp/pvemanager_js_new
    
    # Replace the original file
    mv /tmp/pvemanager_js_new "$pvemanager_js"
    rm -f /tmp/temperature_js.js
    
    echo "✅ Web interface modified successfully"
}

# Function to restart Proxmox services
restart_services() {
    echo "🔄 Restarting Proxmox services..."
    
    systemctl restart pveproxy
    systemctl restart pvedaemon
    
    echo "✅ Proxmox services restarted"
    echo ""
}

# Function to create temperature monitoring script
create_monitoring_script() {
    echo "🔧 Creating temperature monitoring script..."
    
    cat > /usr/local/bin/pve-temp-monitor << 'EOF'
#!/bin/bash
# Proxmox Temperature Monitor Script

# Get CPU temperature
get_cpu_temp() {
    if command -v sensors >/dev/null 2>&1; then
        sensors 2>/dev/null | grep -E "(Core|CPU|Tctl)" | grep -oE '\+[0-9]+\.[0-9]+°C' | head -1 | tr -d '+°C'
    fi
}

# Get disk temperature
get_disk_temp() {
    if command -v smartctl >/dev/null 2>&1; then
        local max_temp=0
        for disk in /dev/sd* /dev/nvme*; do
            if [ -b "$disk" ]; then
                local temp=$(smartctl -A "$disk" 2>/dev/null | grep -i temperature | awk '{print $10}' | head -1)
                if [[ "$temp" =~ ^[0-9]+$ ]] && [ "$temp" -gt "$max_temp" ]; then
                    max_temp=$temp
                fi
            fi
        done
        [ "$max_temp" -gt 0 ] && echo "$max_temp"
    fi
}

# Main execution
case "$1" in
    cpu)
        get_cpu_temp
        ;;
    disk)
        get_disk_temp
        ;;
    all)
        echo "CPU: $(get_cpu_temp)°C"
        echo "Disk: $(get_disk_temp)°C"
        ;;
    *)
        echo "Usage: $0 {cpu|disk|all}"
        exit 1
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/pve-temp-monitor
    echo "✅ Temperature monitoring script created"
}

# Function to test temperature monitoring
test_temperature_monitoring() {
    echo "🧪 Testing temperature monitoring..."
    
    echo "📊 Current temperatures:"
    /usr/local/bin/pve-temp-monitor all
    
    echo ""
    echo "🔍 Sensor output:"
    sensors 2>/dev/null || echo "No sensors output available"
    
    echo ""
}

# Main execution
echo "📊 Checking current system status..."
echo "Proxmox VE version: $(pveversion | head -1)"
echo ""

echo "⚠️  Important Notes:"
echo "1. This will modify Proxmox VE system files"
echo "2. Backups will be created automatically"
echo "3. Proxmox services will be restarted"
echo "4. Temperature sensors must be supported by your hardware"
echo "5. Virtual machines may not have temperature sensors"
echo ""

read -p "Continue with temperature monitoring setup? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ Operation cancelled."
    exit 1
fi

# Execute setup steps
check_required_packages
detect_sensors
backup_files
modify_proxmox_api
modify_web_interface
create_monitoring_script
restart_services
test_temperature_monitoring

echo ""
echo "✅ Temperature monitoring setup completed!"
echo ""
echo "💡 Next steps:"
echo "1. Refresh your Proxmox web interface (Ctrl+F5)"
echo "2. Navigate to a node's summary page"
echo "3. Temperature information should now be displayed"
echo "4. If temperatures don't appear, check hardware sensor support"
echo ""
echo "🔧 Troubleshooting:"
echo "   - Test sensors: sensors"
echo "   - Test script: /usr/local/bin/pve-temp-monitor all"
echo "   - Check logs: journalctl -u pveproxy -u pvedaemon"
echo ""
echo "📁 Backups are stored in: /root/pve_temperature_backup_*"
echo ""
echo "🎉 Temperature monitoring is now active in your Proxmox dashboard!"