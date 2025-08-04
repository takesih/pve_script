#!/bin/bash

# Proxmox VE Temperature Monitor Setup Script
# Adds real-time temperature monitoring to Proxmox VE dashboard
# Version: 2025-01-08
# Author: Proxmox Temperature Monitor Tool

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

# Function to show operation menu
show_menu() {
    echo ""
    echo "🔧 Select operation:"
    echo "1) Install temperature monitoring (new installation)"
    echo "2) Repair/Update temperature monitoring (fix existing installation)"
    echo "3) Remove temperature monitoring (restore original files)"
    echo "4) Test current temperature monitoring"
    echo "5) Exit"
    echo ""
}

# Function to handle Proxmox repository issues
fix_proxmox_repositories() {
    echo "🔧 Checking Proxmox repositories..."
    
    # Check if enterprise repositories are causing issues
    if grep -q "enterprise.proxmox.com" /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null; then
        echo "⚠️  Enterprise repository detected but may not be accessible"
        echo "🔧 Temporarily disabling enterprise repositories for package installation..."
        
        # Backup original repository files
        cp /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.list.bak 2>/dev/null || true
        cp /etc/apt/sources.list.d/ceph.list /etc/apt/sources.list.d/ceph.list.bak 2>/dev/null || true
        
        # Comment out enterprise repositories
        sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null || true
        sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list 2>/dev/null || true
        
        # Add no-subscription repository if not present
        if ! grep -q "pve-no-subscription" /etc/apt/sources.list.d/pve-no-subscription.list 2>/dev/null; then
            echo "📦 Adding no-subscription repository..."
            echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
        fi
        
        echo "✅ Repository configuration updated for package installation"
    fi
}

# Function to restore repositories
restore_repositories() {
    echo "🔧 Restoring original repository configuration..."
    
    # Restore enterprise repositories if backups exist
    if [ -f /etc/apt/sources.list.d/pve-enterprise.list.bak ]; then
        mv /etc/apt/sources.list.d/pve-enterprise.list.bak /etc/apt/sources.list.d/pve-enterprise.list
        echo "✅ Enterprise repository restored"
    fi
    
    if [ -f /etc/apt/sources.list.d/ceph.list.bak ]; then
        mv /etc/apt/sources.list.d/ceph.list.bak /etc/apt/sources.list.d/ceph.list
        echo "✅ Ceph repository restored"
    fi
}

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
        
        # Fix repository issues before package installation
        fix_proxmox_repositories
        
        # Update package list with error handling
        echo "🔄 Updating package lists..."
        if ! apt-get update 2>/dev/null; then
            echo "⚠️  Package list update had some warnings, but continuing..."
        fi
        
        # Install packages with error handling
        if apt-get install -y "${missing_packages[@]}" 2>/dev/null; then
            echo "✅ Required packages installed successfully"
        else
            echo "⚠️  Some packages may have installation warnings, but continuing..."
        fi
        
        # Restore repositories
        restore_repositories
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

# Function to create temperature display extension
create_temperature_extension() {
    echo "🔧 Creating temperature display extension..."
    
    # Create a separate JavaScript file for temperature display
    cat > /usr/share/pve-manager/js/pve-temperature-monitor.js << 'EOF'
// Proxmox Temperature Monitor Extension
// Adds temperature display to node summary

Ext.define('PVE.node.TemperatureStatus', {
    extend: 'Ext.panel.Panel',
    alias: 'widget.pveNodeTemperatureStatus',
    
    title: gettext('Temperature'),
    bodyPadding: 10,
    
    initComponent: function() {
        var me = this;
        
        me.items = [
            {
                xtype: 'displayfield',
                fieldLabel: gettext('CPU Temperature'),
                name: 'cpu-temp',
                value: gettext('Loading...')
            },
            {
                xtype: 'displayfield', 
                fieldLabel: gettext('Disk Temperature'),
                name: 'disk-temp',
                value: gettext('Loading...')
            }
        ];
        
        me.callParent();
        
        // Load temperature data
        me.loadTemperatureData();
        
        // Set up periodic updates
        me.temperatureTask = Ext.TaskManager.start({
            run: me.loadTemperatureData,
            scope: me,
            interval: 10000 // Update every 10 seconds
        });
    },
    
    loadTemperatureData: function() {
        var me = this;
        
        PVE.Utils.API2Request({
            url: '/nodes/' + me.nodename + '/status',
            method: 'GET',
            success: function(response) {
                var data = response.result.data;
                if (data && data['thermal-state']) {
                    var thermal = data['thermal-state'];
                    
                    if (thermal['cpu-thermal']) {
                        me.down('[name=cpu-temp]').setValue(thermal['cpu-thermal'] + '°C');
                    }
                    
                    if (thermal['disk-thermal']) {
                        me.down('[name=disk-temp]').setValue(thermal['disk-thermal'] + '°C');
                    }
                }
            },
            failure: function() {
                me.down('[name=cpu-temp]').setValue(gettext('N/A'));
                me.down('[name=disk-temp]').setValue(gettext('N/A'));
            }
        });
    },
    
    destroy: function() {
        var me = this;
        if (me.temperatureTask) {
            Ext.TaskManager.stop(me.temperatureTask);
        }
        me.callParent();
    }
});
EOF
    
    echo "✅ Temperature extension created"
}



# Function to modify Proxmox web interface for temperature display
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
    
    echo "🔍 Finding node summary section for temperature integration..."
    
    # Look for the node status items section where CPU, Memory info is displayed
    # We need to find where items are pushed to the status display
    local cpu_line=$(grep -n "title.*gettext.*CPU" "$pvemanager_js" | head -1 | cut -d: -f1)
    
    if [ -z "$cpu_line" ]; then
        # Try alternative patterns
        cpu_line=$(grep -n "itemId.*cpu\|CPU usage" "$pvemanager_js" | head -1 | cut -d: -f1)
    fi
    
    if [ -z "$cpu_line" ]; then
        echo "❌ Could not find CPU section in web interface"
        echo "🔧 Trying to find items.push pattern..."
        
        # Look for any items.push pattern in the file
        local push_line=$(grep -n "items\.push" "$pvemanager_js" | tail -1 | cut -d: -f1)
        if [ -n "$push_line" ]; then
            echo "🔍 Found items.push at line $push_line, using as insertion point"
            cpu_line=$push_line
        else
            echo "❌ No suitable insertion point found"
            return 1
        fi
    fi
    
    echo "🔍 Found insertion point at line $cpu_line"
    
    # Create temperature display code that matches Proxmox's existing pattern
    cat > /tmp/temperature_display.js << 'EOF'
            
            // Add temperature monitoring to node status
            if (data && data['thermal-state']) {
                var thermal = data['thermal-state'];
                
                // CPU Temperature
                if (thermal['cpu-thermal']) {
                    items.push({
                        itemId: 'thermal-cpu',
                        colspan: 2,
                        printBar: false,
                        title: gettext('CPU Temperature'),
                        textField: 'thermal-cpu',
                        renderer: function(value) {
                            return thermal['cpu-thermal'] + '°C';
                        }
                    });
                }
                
                // Disk Temperature  
                if (thermal['disk-thermal']) {
                    items.push({
                        itemId: 'thermal-disk',
                        colspan: 2, 
                        printBar: false,
                        title: gettext('Disk Temperature'),
                        textField: 'thermal-disk',
                        renderer: function(value) {
                            return thermal['disk-thermal'] + '°C';
                        }
                    });
                }
            }
EOF
    
    # Try multiple approaches to find a safe insertion point
    local actual_insert=""
    
    # Method 1: Look for a specific pattern in node summary
    if [ -n "$cpu_line" ]; then
        # Look for the end of the current items block
        local context_lines=$(sed -n "$((cpu_line - 5)),$((cpu_line + 30))p" "$pvemanager_js")
        local block_end=$(echo "$context_lines" | grep -n "})" | tail -1 | cut -d: -f1)
        
        if [ -n "$block_end" ]; then
            actual_insert=$((cpu_line - 5 + block_end - 1))
            echo "🔍 Method 1: Found insertion point at line $actual_insert"
        fi
    fi
    
    # Method 2: If Method 1 fails, look for the last items.push in the file
    if [ -z "$actual_insert" ]; then
        local last_push=$(grep -n "items\.push" "$pvemanager_js" | tail -1 | cut -d: -f1)
        if [ -n "$last_push" ]; then
            actual_insert=$last_push
            echo "🔍 Method 2: Using last items.push at line $actual_insert"
        fi
    fi
    
    # Method 3: If all else fails, look for a generic pattern
    if [ -z "$actual_insert" ]; then
        # Look for any function that seems to be building status items
        local status_func=$(grep -n "function.*status\|status.*function" "$pvemanager_js" | head -1 | cut -d: -f1)
        if [ -n "$status_func" ]; then
            # Find the end of this function
            local func_end=$(sed -n "$status_func,$((status_func + 100))p" "$pvemanager_js" | grep -n "^[[:space:]]*}" | head -1 | cut -d: -f1)
            if [ -n "$func_end" ]; then
                actual_insert=$((status_func + func_end - 2))
                echo "🔍 Method 3: Using function end at line $actual_insert"
            fi
        fi
    fi
    
    # If we found an insertion point, proceed
    if [ -n "$actual_insert" ] && [ "$actual_insert" -gt 0 ]; then
        echo "🔍 Inserting temperature code after line $actual_insert"
        
        # Create the modified file
        head -n $actual_insert "$pvemanager_js" > /tmp/pvemanager_js_new
        cat /tmp/temperature_display.js >> /tmp/pvemanager_js_new
        tail -n +$((actual_insert + 1)) "$pvemanager_js" >> /tmp/pvemanager_js_new
        
        # Verify the file is valid (basic check)
        if [ -s /tmp/pvemanager_js_new ]; then
            # Replace the original file
            mv /tmp/pvemanager_js_new "$pvemanager_js"
            rm -f /tmp/temperature_display.js
            
            echo "✅ Web interface modified successfully"
            echo "🌡️  Temperature will now appear in node summary page"
        else
            echo "❌ Generated file is empty, aborting modification"
            rm -f /tmp/pvemanager_js_new /tmp/temperature_display.js
            return 1
        fi
    else
        echo "❌ Could not find any safe insertion point"
        echo "🔧 Creating alternative temperature display method..."
        create_alternative_temperature_display
        return 1
    fi
}

# Function to create alternative temperature display
create_alternative_temperature_display() {
    echo "🔧 Creating alternative temperature display method..."
    
    # Create a simple temperature widget that can be manually added
    cat > /usr/share/pve-manager/js/pve-temperature-widget.js << 'EOF'
// Proxmox Temperature Widget
// Manual integration for temperature display

// Add this to your custom Proxmox modifications
Ext.define('PVE.node.TemperatureWidget', {
    extend: 'Ext.Component',
    alias: 'widget.pveTemperatureWidget',
    
    html: '<div id="pve-temperature-display" style="padding: 10px; background: #f5f5f5; border: 1px solid #ddd; border-radius: 4px; margin: 5px 0;">' +
          '<div style="font-weight: bold; margin-bottom: 5px;">🌡️ System Temperature</div>' +
          '<div id="cpu-temp">CPU: Loading...</div>' +
          '<div id="disk-temp">Disk: Loading...</div>' +
          '</div>',
    
    initComponent: function() {
        var me = this;
        me.callParent();
        
        // Start temperature monitoring
        me.updateTemperature();
        me.tempTask = Ext.TaskManager.start({
            run: me.updateTemperature,
            scope: me,
            interval: 10000 // Update every 10 seconds
        });
    },
    
    updateTemperature: function() {
        var me = this;
        
        Ext.Ajax.request({
            url: '/nodes/' + me.nodename + '/status',
            method: 'GET',
            success: function(response) {
                var data = Ext.decode(response.responseText).data;
                if (data && data['thermal-state']) {
                    var thermal = data['thermal-state'];
                    
                    if (thermal['cpu-thermal']) {
                        Ext.get('cpu-temp').setHtml('CPU: ' + thermal['cpu-thermal'] + '°C');
                    }
                    
                    if (thermal['disk-thermal']) {
                        Ext.get('disk-temp').setHtml('Disk: ' + thermal['disk-thermal'] + '°C');
                    }
                }
            },
            failure: function() {
                Ext.get('cpu-temp').setHtml('CPU: N/A');
                Ext.get('disk-temp').setHtml('Disk: N/A');
            }
        });
    },
    
    destroy: function() {
        var me = this;
        if (me.tempTask) {
            Ext.TaskManager.stop(me.tempTask);
        }
        me.callParent();
    }
});
EOF
    
    # Create a simple HTML page for temperature monitoring
    cat > /usr/share/pve-manager/temperature-monitor.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Proxmox Temperature Monitor</title>
    <meta charset="utf-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .temp-item { display: flex; justify-content: space-between; padding: 10px; margin: 5px 0; background: #f9f9f9; border-radius: 4px; }
        .temp-label { font-weight: bold; }
        .temp-value { color: #666; }
        .refresh-btn { background: #007cbb; color: white; border: none; padding: 10px 20px; border-radius: 4px; cursor: pointer; }
        .refresh-btn:hover { background: #005a87; }
    </style>
</head>
<body>
    <div class="container">
        <h2>🌡️ Proxmox Temperature Monitor</h2>
        <div id="temperature-data">
            <div class="temp-item">
                <span class="temp-label">CPU Temperature:</span>
                <span class="temp-value" id="cpu-temp">Loading...</span>
            </div>
            <div class="temp-item">
                <span class="temp-label">Disk Temperature:</span>
                <span class="temp-value" id="disk-temp">Loading...</span>
            </div>
        </div>
        <button class="refresh-btn" onclick="updateTemperature()">Refresh</button>
        <p><small>Auto-refresh every 30 seconds</small></p>
    </div>

    <script>
        function updateTemperature() {
            fetch('/api2/json/nodes/' + window.location.hostname + '/status')
                .then(response => response.json())
                .then(data => {
                    if (data.data && data.data['thermal-state']) {
                        const thermal = data.data['thermal-state'];
                        
                        if (thermal['cpu-thermal']) {
                            document.getElementById('cpu-temp').textContent = thermal['cpu-thermal'] + '°C';
                        }
                        
                        if (thermal['disk-thermal']) {
                            document.getElementById('disk-temp').textContent = thermal['disk-thermal'] + '°C';
                        }
                    }
                })
                .catch(error => {
                    document.getElementById('cpu-temp').textContent = 'Error';
                    document.getElementById('disk-temp').textContent = 'Error';
                });
        }
        
        // Initial load and auto-refresh
        updateTemperature();
        setInterval(updateTemperature, 30000);
    </script>
</body>
</html>
EOF
    
    echo "✅ Alternative temperature display created"
    echo "🌐 Access temperature monitor at: https://your-proxmox-ip:8006/temperature-monitor.html"
    echo "📁 Widget file created: /usr/share/pve-manager/js/pve-temperature-widget.js"
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

# Function to remove temperature monitoring
remove_temperature_monitoring() {
    echo "🗑️  Removing temperature monitoring..."
    
    # Find the most recent backup
    local backup_dir=$(ls -td /root/pve_temperature_backup_* 2>/dev/null | head -1)
    
    if [ -z "$backup_dir" ]; then
        echo "❌ No backup directory found. Cannot safely remove modifications."
        echo "   Manual restoration required."
        return 1
    fi
    
    echo "📁 Using backup from: $backup_dir"
    
    # Restore original files
    if [ -f "$backup_dir/Nodes.pm" ]; then
        cp "$backup_dir/Nodes.pm" "/usr/share/perl5/PVE/API2/Nodes.pm"
        echo "✅ Restored Nodes.pm"
    fi
    
    if [ -f "$backup_dir/pvemanagerlib.js" ]; then
        cp "$backup_dir/pvemanagerlib.js" "/usr/share/pve-manager/js/pvemanagerlib.js"
        echo "✅ Restored pvemanagerlib.js"
    fi
    
    # Remove monitoring script
    if [ -f "/usr/local/bin/pve-temp-monitor" ]; then
        rm -f "/usr/local/bin/pve-temp-monitor"
        echo "✅ Removed temperature monitoring script"
    fi
    
    # Remove alternative temperature display files
    if [ -f "/usr/share/pve-manager/js/pve-temperature-widget.js" ]; then
        rm -f "/usr/share/pve-manager/js/pve-temperature-widget.js"
        echo "✅ Removed temperature widget"
    fi
    
    if [ -f "/usr/share/pve-manager/temperature-monitor.html" ]; then
        rm -f "/usr/share/pve-manager/temperature-monitor.html"
        echo "✅ Removed temperature monitor page"
    fi
    
    # Restart services
    restart_services
    
    echo "✅ Temperature monitoring removed successfully"
    echo "💡 Refresh your Proxmox web interface to see changes"
}

# Function to test temperature monitoring
test_temperature_monitoring() {
    echo "🧪 Testing temperature monitoring..."
    
    # Test if monitoring script exists
    if [ ! -f "/usr/local/bin/pve-temp-monitor" ]; then
        echo "❌ Temperature monitoring script not found"
        echo "   Run installation first"
        return 1
    fi
    
    echo "📊 Current temperatures:"
    /usr/local/bin/pve-temp-monitor all 2>/dev/null || echo "❌ Temperature monitoring script failed"
    
    echo ""
    echo "🔍 Raw sensor output:"
    if command -v sensors >/dev/null 2>&1; then
        sensors 2>/dev/null || echo "❌ No sensors output available"
    else
        echo "❌ lm-sensors not installed"
    fi
    
    echo ""
    echo "🔍 Smart disk temperatures:"
    if command -v smartctl >/dev/null 2>&1; then
        for disk in /dev/sd[a-z] /dev/nvme[0-9]*; do
            if [ -b "$disk" ]; then
                echo -n "$disk: "
                smartctl -A "$disk" 2>/dev/null | grep -i temperature | awk '{print $10"°C"}' | head -1 || echo "N/A"
            fi
        done
    else
        echo "❌ smartmontools not installed"
    fi
    
    echo ""
    echo "🔍 Checking Proxmox modifications:"
    if grep -q "thermal-state" "/usr/share/perl5/PVE/API2/Nodes.pm" 2>/dev/null; then
        echo "✅ API modifications present"
    else
        echo "❌ API modifications missing"
    fi
    
    if [ -f "/usr/local/bin/pve-temperature-api" ]; then
        echo "✅ Temperature API endpoint present"
        echo "🧪 Testing API endpoint:"
        /usr/local/bin/pve-temperature-api 2>/dev/null | head -10 || echo "❌ API test failed"
    else
        echo "❌ Temperature API missing"
    fi
    
    echo "🔍 Checking Proxmox web interface modifications:"
    if grep -q "thermal-state" "/usr/share/pve-manager/js/pvemanagerlib.js" 2>/dev/null; then
        echo "✅ Web interface modifications present"
        echo "🌡️  Temperature should appear in node summary page"
    elif [ -f "/usr/share/pve-manager/js/pve-temperature-widget.js" ]; then
        echo "✅ Alternative temperature widget available"
        echo "🌐 Access at: https://$(hostname -I | awk '{print $1}'):8006/temperature-monitor.html"
    else
        echo "❌ Web interface modifications missing"
        echo "⚠️  Temperature will not appear in web interface"
    fi
}

# Function to install temperature monitoring
install_temperature_monitoring() {
    echo ""
    echo "🚀 Starting temperature monitoring installation..."
    echo ""
    echo "⚠️  Important Notes:"
    echo "1. This will modify Proxmox VE system files"
    echo "2. Backups will be created automatically"
    echo "3. Proxmox services will be restarted"
    echo "4. Temperature sensors must be supported by your hardware"
    echo "5. Virtual machines may not have temperature sensors"
    echo ""
    
    read -p "Continue with temperature monitoring installation? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "❌ Installation cancelled."
        return 1
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
    echo "✅ Temperature monitoring installation completed!"
    echo ""
    echo "💡 How to check temperatures:"
    echo "1. Command line: /usr/local/bin/pve-temp-monitor all"
    echo "2. Proxmox API: pvesh get /nodes/\$(hostname)/status"
    echo "3. Raw sensors: sensors"
    echo ""
    
    # Check if web interface was successfully modified
    if grep -q "thermal-state" "/usr/share/pve-manager/js/pvemanagerlib.js" 2>/dev/null; then
        echo "🌡️  Web interface integration: SUCCESS"
        echo "   Temperature will appear in Proxmox node summary page"
        echo "   Refresh your browser (Ctrl+F5) to see changes"
    elif [ -f "/usr/share/pve-manager/js/pve-temperature-widget.js" ]; then
        echo "🌐 Alternative web interface available:"
        echo "   Access at: https://$(hostname -I | awk '{print $1}'):8006/temperature-monitor.html"
        echo "   Widget file: /usr/share/pve-manager/js/pve-temperature-widget.js"
    else
        echo "⚠️  Web interface integration: FAILED"
        echo "   Temperature available via command line only"
    fi
    
    echo ""
    echo "🔧 Troubleshooting:"
    echo "   - Test sensors: sensors"
    echo "   - Test script: /usr/local/bin/pve-temp-monitor all"
    echo "   - Check logs: journalctl -u pveproxy -u pvedaemon"
    echo ""
    echo "📁 Backups are stored in: /root/pve_temperature_backup_*"
    echo ""
    echo "🎉 Temperature monitoring is now active!"
}

# Function to repair temperature monitoring
repair_temperature_monitoring() {
    echo ""
    echo "🔧 Starting temperature monitoring repair/update..."
    echo ""
    echo "⚠️  This will:"
    echo "1. Re-apply temperature monitoring modifications"
    echo "2. Update monitoring scripts"
    echo "3. Restart Proxmox services"
    echo "4. Test functionality"
    echo ""
    
    read -p "Continue with repair/update? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "❌ Repair cancelled."
        return 1
    fi
    
    # Execute repair steps (similar to install but skip package check)
    detect_sensors
    backup_files
    modify_proxmox_api
    modify_web_interface
    create_monitoring_script
    restart_services
    test_temperature_monitoring
    
    echo ""
    echo "✅ Temperature monitoring repair completed!"
    echo "💡 Refresh your Proxmox web interface to see changes"
}

# Main execution
echo "📊 Checking current system status..."
echo "Proxmox VE version: $(pveversion | head -1)"

# Check if temperature monitoring is already installed
if grep -q "thermal-state" "/usr/share/perl5/PVE/API2/Nodes.pm" 2>/dev/null; then
    echo "🔍 Status: Temperature monitoring appears to be installed"
else
    echo "🔍 Status: Temperature monitoring not detected"
fi

# Main menu loop
while true; do
    show_menu
    read -p "Select option (1-5): " choice
    
    case $choice in
        1)
            install_temperature_monitoring
            ;;
        2)
            repair_temperature_monitoring
            ;;
        3)
            remove_temperature_monitoring
            ;;
        4)
            test_temperature_monitoring
            ;;
        5)
            echo "👋 Goodbye!"
            exit 0
            ;;
        *)
            echo "❌ Invalid option. Please select 1-5."
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
done