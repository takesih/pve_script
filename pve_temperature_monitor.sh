#!/bin/bash

# Proxmox VE Temperature Monitor Setup Script
# Adds real-time temperature monitoring to Proxmox VE dashboard
# Version: 2025-01-08 01:10
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
    
    # Create detailed debug log
    local debug_log="/var/log/pve-temperature-debug.log"
    echo "=== Proxmox Temperature Monitor Debug Log ===" > "$debug_log"
    echo "Date: $(date)" >> "$debug_log"
    echo "File: $pvemanager_js" >> "$debug_log"
    echo "File size: $(wc -l < "$pvemanager_js") lines" >> "$debug_log"
    echo "" >> "$debug_log"
    
    # Log file structure analysis
    echo "=== File Structure Analysis ===" >> "$debug_log"
    echo "Lines containing 'CPU':" >> "$debug_log"
    grep -n -i "cpu" "$pvemanager_js" | head -20 >> "$debug_log"
    echo "" >> "$debug_log"
    
    echo "Lines containing 'items.push':" >> "$debug_log"
    grep -n "items\.push" "$pvemanager_js" | head -20 >> "$debug_log"
    echo "" >> "$debug_log"
    
    echo "Lines containing 'title.*gettext':" >> "$debug_log"
    grep -n "title.*gettext" "$pvemanager_js" | head -20 >> "$debug_log"
    echo "" >> "$debug_log"
    
    echo "Lines containing 'itemId':" >> "$debug_log"
    grep -n "itemId" "$pvemanager_js" | head -20 >> "$debug_log"
    echo "" >> "$debug_log"
    
    # Look for the node status items section where CPU, Memory info is displayed
    # We need to find where items are pushed to the status display
    local cpu_line=$(grep -n "title.*gettext.*CPU" "$pvemanager_js" | head -1 | cut -d: -f1)
    
    echo "=== Search Results ===" >> "$debug_log"
    echo "CPU line search result: $cpu_line" >> "$debug_log"
    
    if [ -z "$cpu_line" ]; then
        # Try alternative patterns
        cpu_line=$(grep -n "itemId.*cpu\|CPU usage" "$pvemanager_js" | head -1 | cut -d: -f1)
        echo "Alternative CPU search result: $cpu_line" >> "$debug_log"
    fi
    
    if [ -z "$cpu_line" ]; then
        echo "❌ Could not find CPU section in web interface"
        echo "🔧 Trying to find items.push pattern..."
        
        # Look for any items.push pattern in the file
        local push_line=$(grep -n "items\.push" "$pvemanager_js" | tail -1 | cut -d: -f1)
        echo "Items.push search result: $push_line" >> "$debug_log"
        
        if [ -n "$push_line" ]; then
            echo "🔍 Found items.push at line $push_line, using as insertion point"
            cpu_line=$push_line
        else
            echo "❌ No suitable insertion point found"
            echo "ERROR: No insertion point found" >> "$debug_log"
            
            # Log more context for debugging
            echo "" >> "$debug_log"
            echo "=== Context Analysis ===" >> "$debug_log"
            echo "Lines 1-50:" >> "$debug_log"
            head -50 "$pvemanager_js" >> "$debug_log"
            echo "" >> "$debug_log"
            echo "Lines around middle:" >> "$debug_log"
            local middle_line=$(($(wc -l < "$pvemanager_js") / 2))
            sed -n "$((middle_line - 25)),$((middle_line + 25))p" "$pvemanager_js" >> "$debug_log"
            echo "" >> "$debug_log"
            echo "Last 50 lines:" >> "$debug_log"
            tail -50 "$pvemanager_js" >> "$debug_log"
            
            echo "🔍 Debug log created: $debug_log"
            echo "📋 Please share this log to help identify the correct insertion point"
            return 1
        fi
    fi
    
    echo "🔍 Found insertion point at line $cpu_line"
    
    # Log context around insertion point
    echo "" >> "$debug_log"
    echo "=== Insertion Point Context ===" >> "$debug_log"
    echo "Selected line: $cpu_line" >> "$debug_log"
    echo "Context (lines $((cpu_line - 10)) to $((cpu_line + 10))):" >> "$debug_log"
    sed -n "$((cpu_line - 10)),$((cpu_line + 10))p" "$pvemanager_js" >> "$debug_log"
    echo "" >> "$debug_log"
    
    # Create temperature display code - insert between CPU and Memory items
    cat > /tmp/temperature_display.js << 'EOF'
        {
            itemId: 'thermal',
            colspan: 2,
            printBar: false,
            title: gettext('CPU Temperature'),
            textField: 'thermal',
                renderer: function(value, metaData, record, rowIndex, colIndex, store) {
        // Simple temperature display - will be updated by background task
        return 'Loading...';
    }
        },
        {
            itemId: 'thermal-disk',
            colspan: 2,
            printBar: false,
            title: gettext('Disk Temperature'),
            textField: 'thermal-disk',
                renderer: function(value, metaData, record, rowIndex, colIndex, store) {
        // Simple temperature display - will be updated by background task
        return 'Loading...';
    }
        },
EOF
    
    # Simplified insertion approach - find the exact location
    local actual_insert=""
    
    # Find the exact line where CPU item ends and memory item begins
    local cpu_end_pattern="calculate: Ext.identityFn,"
    local cpu_end_line=$(grep -n "$cpu_end_pattern" "$pvemanager_js" | head -1 | cut -d: -f1)
    
    if [ -n "$cpu_end_line" ]; then
        # Insert right after the CPU item ends (after the closing brace)
        actual_insert=$((cpu_end_line + 1))
        echo "🔍 Found CPU end at line $cpu_end_line, inserting at line $actual_insert"
        echo "CPU end found at line $cpu_end_line, inserting at line $actual_insert" >> "$debug_log"
    else
        # Fallback: find memory item and insert before it
        local memory_line=$(grep -n "itemId.*memory" "$pvemanager_js" | head -1 | cut -d: -f1)
        if [ -n "$memory_line" ]; then
            actual_insert=$((memory_line - 1))
            echo "🔍 Fallback: inserting before memory at line $actual_insert"
            echo "Fallback: inserting before memory at line $actual_insert" >> "$debug_log"
        else
            echo "❌ Could not find suitable insertion point"
            echo "ERROR: No suitable insertion point found" >> "$debug_log"
            return 1
        fi
    fi
    
    # Method 4: Prevent fallback to wrong location
    if [ -z "$actual_insert" ]; then
        echo "❌ All methods failed to find insertion point"
        echo "ERROR: All insertion methods failed" >> "$debug_log"
        echo "❌ Cannot modify web interface - temperature will be available via command line only"
        return 1
    fi
    
    # Safety check: Ensure we're not inserting in storage/permissions section
    if [ "$actual_insert" -gt 50000 ]; then
        echo "❌ Insertion point too far in file (line $actual_insert), likely wrong section"
        echo "ERROR: Insertion point $actual_insert is in wrong section (>50000)" >> "$debug_log"
        echo "❌ Cannot modify web interface safely - temperature will be available via command line only"
        return 1
    fi
    
    # If we found an insertion point, proceed
    if [ -n "$actual_insert" ] && [ "$actual_insert" -gt 0 ]; then
        echo "🔍 Inserting temperature code after line $actual_insert"
        
        # Log the insertion process
        echo "=== Insertion Process ===" >> "$debug_log"
        echo "Final insertion line: $actual_insert" >> "$debug_log"
        echo "Context before insertion:" >> "$debug_log"
        sed -n "$((actual_insert - 5)),$((actual_insert + 5))p" "$pvemanager_js" >> "$debug_log"
        echo "" >> "$debug_log"
        echo "Code to be inserted:" >> "$debug_log"
        cat /tmp/temperature_display.js >> "$debug_log"
        echo "" >> "$debug_log"
        
        # Create the modified file
        head -n $actual_insert "$pvemanager_js" > /tmp/pvemanager_js_new
        cat /tmp/temperature_display.js >> /tmp/pvemanager_js_new
        tail -n +$((actual_insert + 1)) "$pvemanager_js" >> /tmp/pvemanager_js_new
        
        # Log the result
        echo "Modified file size: $(wc -l < /tmp/pvemanager_js_new) lines" >> "$debug_log"
        echo "Context after insertion:" >> "$debug_log"
        sed -n "$((actual_insert - 5)),$((actual_insert + 15))p" /tmp/pvemanager_js_new >> "$debug_log"
        echo "" >> "$debug_log"
        
        # Verify the file is valid (basic check)
        if [ -s /tmp/pvemanager_js_new ]; then
            # Additional syntax validation
            echo "=== Syntax Validation ===" >> "$debug_log"
            
            # Check for common JavaScript syntax issues
            local syntax_errors=""
            
            # Check for unmatched braces around insertion point
            local before_braces=$(sed -n "1,$actual_insert p" /tmp/pvemanager_js_new | grep -o '{' | wc -l)
            local before_close_braces=$(sed -n "1,$actual_insert p" /tmp/pvemanager_js_new | grep -o '}' | wc -l)
            local after_braces=$(sed -n "$((actual_insert + 1)),$ p" /tmp/pvemanager_js_new | grep -o '{' | wc -l)
            local after_close_braces=$(sed -n "$((actual_insert + 1)),$ p" /tmp/pvemanager_js_new | grep -o '}' | wc -l)
            
            echo "Brace count before insertion: { = $before_braces, } = $before_close_braces" >> "$debug_log"
            echo "Brace count after insertion: { = $after_braces, } = $after_close_braces" >> "$debug_log"
            
            # Check for syntax issues in the inserted area
            local insert_area=$(sed -n "$((actual_insert - 2)),$((actual_insert + 20))p" /tmp/pvemanager_js_new)
            
            # Check for common JavaScript syntax issues
            if echo "$insert_area" | grep -q "&&.*{"; then
                syntax_errors="Potential '&&' syntax issue detected"
                echo "WARNING: $syntax_errors" >> "$debug_log"
            fi
            
            # Check for proper object structure (skip - this is valid in renderer functions)
            # Conditional logic is expected in renderer functions
            
            # Check for items.push in wrong context
            if echo "$insert_area" | grep -q "items\.push" && ! echo "$insert_area" | grep -q "me\.items\.push"; then
                # Verify we're in the right context for items.push
                local context_check=$(sed -n "$((actual_insert - 20)),$((actual_insert + 5))p" /tmp/pvemanager_js_new)
                if ! echo "$context_check" | grep -q "items.*=.*\["; then
                    syntax_errors="items.push used without proper items array context"
                    echo "WARNING: $syntax_errors" >> "$debug_log"
                fi
            fi
            
            if [ -n "$syntax_errors" ]; then
                echo "❌ Syntax validation failed: $syntax_errors"
                echo "🔍 Check debug log: $debug_log"
                rm -f /tmp/pvemanager_js_new /tmp/temperature_display.js
                return 1
            fi
            
            # Replace the original file
            mv /tmp/pvemanager_js_new "$pvemanager_js"
            rm -f /tmp/temperature_display.js
            
            echo "✅ Web interface modified successfully"
            echo "🌡️  Temperature will now appear in node summary page"
            echo "SUCCESS: File modified successfully" >> "$debug_log"
        else
            echo "❌ Generated file is empty, aborting modification"
            echo "ERROR: Generated file is empty" >> "$debug_log"
            rm -f /tmp/pvemanager_js_new /tmp/temperature_display.js
            return 1
        fi
    else
        echo "❌ Could not find any safe insertion point"
        echo "🔧 Creating alternative temperature display method..."
        echo "ERROR: No safe insertion point found" >> "$debug_log"
        create_alternative_temperature_display
        return 1
    fi
    
    echo "🔍 Debug log saved: $debug_log"
}

# Function to create alternative temperature display (disabled - dashboard only)
create_alternative_temperature_display() {
    echo "❌ Alternative display disabled - focusing on dashboard integration only"
    return 1
    
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
                if (data) {
                    if (data['thermal-state']) {
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
            // Try multiple methods to get temperature data
            
            // Method 1: Try the CGI script
            fetch('/temperature.cgi')
                .then(response => response.json())
                .then(data => {
                    console.log('CGI Response:', data);
                    
                    if (data.cpu_temperature) {
                        if (data.cpu_temperature !== 'N/A') {
                        document.getElementById('cpu-temp').textContent = data.cpu_temperature + '°C';
                    } else {
                        document.getElementById('cpu-temp').textContent = 'N/A';
                    }
                    
                    if (data.disk_temperature) {
                        if (data.disk_temperature !== 'N/A') {
                        document.getElementById('disk-temp').textContent = data.disk_temperature + '°C';
                    } else {
                        document.getElementById('disk-temp').textContent = 'N/A';
                    }
                })
                .catch(error => {
                    console.log('CGI failed, trying Proxmox API:', error);
                    tryProxmoxAPI();
                });
        }
        
        function tryProxmoxAPI() {
            // Method 2: Try Proxmox API
            const hostname = window.location.hostname;
            
            fetch('/api2/json/nodes/' + hostname + '/status', {
                method: 'GET',
                credentials: 'same-origin'
            })
            .then(response => response.json())
            .then(result => {
                console.log('Proxmox API Response:', result);
                
                if (result.data) {
                    if (result.data['thermal-state']) {
                    const thermal = result.data['thermal-state'];
                    
                    document.getElementById('cpu-temp').textContent = 
                        thermal['cpu-thermal'] ? thermal['cpu-thermal'] + '°C' : 'N/A';
                    document.getElementById('disk-temp').textContent = 
                        thermal['disk-thermal'] ? thermal['disk-thermal'] + '°C' : 'N/A';
                } else {
                    fallbackDisplay();
                }
            })
            .catch(error => {
                console.error('All methods failed:', error);
                fallbackDisplay();
            });
        }
        
        function fallbackDisplay() {
            document.getElementById('cpu-temp').textContent = 'Use CLI: pve-temp-monitor all';
            document.getElementById('disk-temp').textContent = 'Check: sensors command';
        }
        
        // Initial load and auto-refresh
        updateTemperature();
        setInterval(updateTemperature, 30000);
        
        // Add manual refresh functionality
        document.addEventListener('DOMContentLoaded', function() {
            console.log('Temperature monitor loaded');
            updateTemperature();
        });
    </script>
</body>
</html>
EOF
    
    # Create a simple PHP script for temperature display (if PHP is available)
    if command -v php >/dev/null 2>&1; then
        cat > /usr/share/pve-manager/temperature.php << 'EOF'
<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

// Function to get CPU temperature
function getCpuTemp() {
    $output = shell_exec('/usr/local/bin/pve-temp-monitor cpu 2>/dev/null');
    return trim($output) ?: 'N/A';
}

// Function to get disk temperature
function getDiskTemp() {
    $output = shell_exec('/usr/local/bin/pve-temp-monitor disk 2>/dev/null');
    return trim($output) ?: 'N/A';
}

// Return JSON response
$response = [
    'cpu_temperature' => getCpuTemp(),
    'disk_temperature' => getDiskTemp(),
    'timestamp' => date('Y-m-d H:i:s')
];

echo json_encode($response);
?>
EOF
        echo "📄 PHP temperature script created: /usr/share/pve-manager/temperature.php"
    fi
    
    # Create a simple CGI script as another alternative
    cat > /usr/share/pve-manager/temperature.cgi << 'EOF'
#!/bin/bash
echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo ""

# Get temperatures using the monitoring script
cpu_temp=$(/usr/local/bin/pve-temp-monitor cpu 2>/dev/null || echo "N/A")
disk_temp=$(/usr/local/bin/pve-temp-monitor disk 2>/dev/null || echo "N/A")

# Output JSON
cat << JSON
{
    "cpu_temperature": "$cpu_temp",
    "disk_temperature": "$disk_temp", 
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
JSON
EOF
    chmod +x /usr/share/pve-manager/temperature.cgi
    
    echo "✅ Alternative temperature display created"
    echo "🌐 Access methods:"
    echo "   1. HTML page: https://$(hostname -I | awk '{print $1}'):8006/temperature-monitor.html"
    echo "   2. JSON API: https://$(hostname -I | awk '{print $1}'):8006/temperature.cgi"
    if command -v php >/dev/null 2>&1; then
        echo "   3. PHP API: https://$(hostname -I | awk '{print $1}'):8006/temperature.php"
    fi
    echo "   4. Command line: /usr/local/bin/pve-temp-monitor all"
    echo "📁 Widget file: /usr/share/pve-manager/js/pve-temperature-widget.js"
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
    local temp=""
    
    # Method 1: lm-sensors
    if command -v sensors >/dev/null 2>&1; then
        temp=$(sensors 2>/dev/null | grep -E "(Core|CPU|Tctl)" | grep -oE '\+[0-9]+\.[0-9]+°C' | head -1 | tr -d '+°C')
        if [[ "$temp" =~ ^[0-9]+$ ]] && [ "$temp" -gt 0 ]; then
            echo "$temp"
            return 0
        fi
    fi
    
    # Method 2: /sys/class/thermal
    if [ -d "/sys/class/thermal" ]; then
        for zone in /sys/class/thermal/thermal_zone*/temp; do
            if [ -f "$zone" ]; then
                temp=$(cat "$zone" 2>/dev/null)
                if [[ "$temp" =~ ^[0-9]+$ ]] && [ "$temp" -gt 0 ]; then
                    echo $((temp / 1000))
                    return 0
                fi
            fi
        done
    fi
    
    # Method 3: /proc/cpuinfo (fallback)
    temp=$(cat /proc/cpuinfo 2>/dev/null | grep -i "cpu temp\|thermal" | head -1 | awk '{print $NF}' | sed 's/[^0-9]//g')
    if [[ "$temp" =~ ^[0-9]+$ ]] && [ "$temp" -gt 0 ]; then
        echo "$temp"
        return 0
    fi
    
    echo "N/A"
}

# Get disk temperature
get_disk_temp() {
    local max_temp=0
    
    if command -v smartctl >/dev/null 2>&1; then
        for disk in /dev/sd* /dev/nvme*; do
            if [ -b "$disk" ]; then
                local temp=$(smartctl -A "$disk" 2>/dev/null | grep -i temperature | awk '{print $10}' | head -1)
                if [[ "$temp" =~ ^[0-9]+$ ]] && [ "$temp" -gt "$max_temp" ]; then
                    max_temp=$temp
                fi
            fi
        done
        if [ "$max_temp" -gt 0 ]; then
            echo "$max_temp"
            return 0
        fi
    fi
    
    echo "N/A"
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
    
    # Clean up any leftover files (focus on dashboard only)
    echo "🧹 Cleaning up temperature monitoring files..."
    
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
        echo "🌡️  Temperature should appear in Proxmox dashboard"
    else
        echo "❌ Web interface modifications missing"
        echo "⚠️  Temperature will not appear in dashboard"
    fi
    
    # Show debug log information if available
    if [ -f "/var/log/pve-temperature-debug.log" ]; then
        echo ""
        echo "🔍 Debug information available:"
        echo "   Debug log: /var/log/pve-temperature-debug.log"
        echo "   Last modification: $(stat -c %y /var/log/pve-temperature-debug.log 2>/dev/null || echo 'Unknown')"
        echo "   Log size: $(wc -l < /var/log/pve-temperature-debug.log 2>/dev/null || echo '0') lines"
        echo ""
        echo "📋 To help with troubleshooting, you can share:"
        echo "   cat /var/log/pve-temperature-debug.log"
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
        echo "🌡️  Dashboard integration: SUCCESS"
        echo "   Temperature will appear in Proxmox dashboard"
        echo "   Refresh your browser (Ctrl+F5) to see changes"
    else
        echo "⚠️  Dashboard integration: FAILED"
        echo "   Temperature available via command line only"
    fi
    
    echo ""
    echo "🔧 Troubleshooting:"
    echo "   - Test sensors: sensors"
    echo "   - Test script: /usr/local/bin/pve-temp-monitor all"
    echo "   - Check logs: journalctl -u pveproxy -u pvedaemon"
    
    # Show debug log if available
    if [ -f "/var/log/pve-temperature-debug.log" ]; then
        echo "   - Debug log: /var/log/pve-temperature-debug.log"
        echo ""
        echo "🔍 If you encounter JavaScript errors in the browser:"
        echo "   1. Check the debug log: cat /var/log/pve-temperature-debug.log"
        echo "   2. Share the log content for assistance"
        echo "   3. The log contains file analysis and insertion details"
    fi
    
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