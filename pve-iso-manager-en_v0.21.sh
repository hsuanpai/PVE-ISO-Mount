#!/bin/bash
# Proxmox Dynamic ISO NFS Mount Management Script - Support 9-level Menu
# Purpose: Mount with Read Only NFS share folder.
# Initial Date: 07/01/2025
# Update Date: 07/02/2025
# Version : v0.21
# Auther: Mark Lin / Claude AI Sonnet4
#########################################################################
# Configuration file path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "/etc/pve" ]; then
  CONFIG_FILE="/etc/pve/iso-mount-config.json"
else
  CONFIG_FILE="$SCRIPT_DIR/iso-mount-config.json"
fi
PVE_STORAGE_CFG="/etc/pve/storage.cfg"

# Default configuration
DEFAULT_CONFIG='{
  "iso_configs": {
    "1": {
      "label": "Linux OS",
      "items": {
        "1": {
          "name": "ROCKY9-ISO",
          "label": "Rocky Linux 9",
          "nfs_server": "10.160.88.33",
          "nfs_export": "/OSimg/Linux/Rocky_Linux/Rocky_Linux_9",
          "mount_base": "/mnt/rocky9-iso",
          "mount_target": "/mnt/rocky9-iso/template/iso"
        }
      }
    },
    "2": {
      "label": "Windows OS",
      "items": {
        "1": {
          "name": "Win2008R2-ISO",
          "label": "Windows 2008 R2",
          "nfs_server": "192.168.1.1",
          "nfs_export": "/OSimg/Windows/Win2008/WS2008R2",
          "mount_base": "/mnt/win2008r2-iso",
          "mount_target": "/mnt/win2008r2-iso/template/iso"
        }
      }
    }
  }
}'

# Check if running in Proxmox environment
is_pve() {
  [ -f "$PVE_STORAGE_CFG" ]
}

# Initialize configuration file
init_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "📝 Initializing configuration file $CONFIG_FILE"
    echo "$DEFAULT_CONFIG" | jq . > "$CONFIG_FILE"
  fi
}

# Read configuration file
read_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    init_config
  fi
  cat "$CONFIG_FILE"
}

# Save configuration file
save_config() {
  local config="$1"
  echo "$config" | jq . > "$CONFIG_FILE"
  echo "💾 Configuration saved"
}

# Add Storage configuration to storage.cfg
add_storage_cfg() {
  local name="$1"
  local mount_base="$2"  # Use mount_base instead of mount_target
  
  if ! is_pve; then
    echo "⚠️ Not in Proxmox environment, skipping storage.cfg configuration"
    return
  fi
  
  if grep -q "^dir: $name" "$PVE_STORAGE_CFG"; then
    echo "⚠️ Storage '$name' already exists in storage.cfg, skipping"
    return
  fi
  
  echo "" >> "$PVE_STORAGE_CFG"
  echo "dir: $name" >> "$PVE_STORAGE_CFG"
  echo "    path $mount_base" >> "$PVE_STORAGE_CFG"
  echo "    content iso" >> "$PVE_STORAGE_CFG"
  echo "✅ Added $name configuration to $PVE_STORAGE_CFG (path: $mount_base)"
}

# Remove Storage configuration from storage.cfg
remove_storage_cfg() {
  local name="$1"
  
  if ! is_pve; then
    echo "⚠️ Not in Proxmox environment, skipping storage.cfg operation"
    return
  fi
  
  # Use sed to remove storage block
  sed -i "/^dir: $name$/,/^$/d" "$PVE_STORAGE_CFG"
  echo "🗑️ Removed $name from storage.cfg"
}

# Mount NFS
mount_nfs() {
  local name="$1"
  local nfs_server="$2"
  local nfs_export="$3"
  local mount_target="$4"
  local mount_base="$5"
  
  # Create full mount directory structure
  mkdir -p "$mount_target"
  echo "🔗 Mounting NFS ($name) to $mount_target..."
  mount -o ro "$nfs_server:$nfs_export" "$mount_target"
  
  if [ $? -ne 0 ]; then
    echo "❌ NFS mount failed"
    return 1
  fi
  
  # Add to storage.cfg using mount_base (not mount_target)
  add_storage_cfg "$name" "$mount_base"
  echo "✅ $name mounted successfully"
  echo "📁 NFS mounted at: $mount_target"
  echo "📝 Proxmox storage path: $mount_base"
  return 0
}

# Unmount NFS
umount_nfs() {
  local name="$1"
  local mount_target="$2"
  
  echo "🔓 Unmounting NFS ($name) from $mount_target..."
  umount "$mount_target" 2>/dev/null
  
  if [ $? -eq 0 ]; then
    echo "✅ $name unmounted successfully"
    remove_storage_cfg "$name"
  else
    echo "⚠️ $name may not be mounted or unmount failed"
  fi
}

# Check mount status
check_mount_status() {
  local mount_target="$1"
  mount | grep -q "$mount_target"
}

# Check storage.cfg configuration
check_storage_cfg() {
  local name="$1"
  if is_pve; then
    grep -q "^dir: $name" "$PVE_STORAGE_CFG"
  else
    return 1
  fi
}

# Show all status
show_all_status() {
  local config=$(read_config)
  echo ""
  echo "======== All ISO Mount Status ========"
  
  echo "$config" | jq -r '.iso_configs | to_entries[] | "\(.key): \(.value.label)"' | while read line; do
    level1_key=$(echo "$line" | cut -d: -f1)
    level1_label=$(echo "$line" | cut -d: -f2-)
    
    echo "[$level1_label]"
    
    echo "$config" | jq -r ".iso_configs[\"$level1_key\"].items | to_entries[]? | \"\(.key): \(.value.name) - \(.value.label) - \(.value.mount_target)\"" | while read item_line; do
      if [ -n "$item_line" ]; then
        item_name=$(echo "$item_line" | cut -d: -f2 | cut -d' ' -f1)
        item_label=$(echo "$item_line" | cut -d' ' -f3-)
        mount_target=$(echo "$item_line" | awk -F' - ' '{print $3}')
        
        if check_mount_status "$mount_target"; then
          echo "  ✅ $item_label (Mounted)"
        else
          echo "  ❌ $item_label (Not Mounted)"
        fi
        
        if check_storage_cfg "$item_name"; then
          echo "    ✅ Storage in cfg"
        else
          echo "    ❌ Storage not in cfg"
        fi
      fi
    done
    echo ""
  done
  echo "================================="
}

# Display menu for specified level
show_menu() {
  local level="$1"
  local path="$2"
  local config=$(read_config)
  
  # Parse current position based on path level
  case $level in
    1)
      echo ""
      echo "======= Proxmox ISO Management Menu ======="
      # Check if config has any items and display them
      local config_check=$(echo "$config" | jq -e '.iso_configs' 2>/dev/null)
      if [ $? -eq 0 ]; then
        local has_items=$(echo "$config" | jq -r '.iso_configs | length' 2>/dev/null)
        if [ -n "$has_items" ] && [ "$has_items" != "null" ] && [ "$has_items" -gt 0 ] 2>/dev/null; then
          echo "$config" | jq -r '.iso_configs | to_entries[] | "\(.key). \(.value.label)"' 2>/dev/null
        else
          echo "No categories configured yet"
        fi
      else
        echo "No categories configured yet"
      fi
      echo ""
      echo "A. Add Main Category"
      echo "S. Show All Status"
      echo "Q. Quit"
      echo "==========================================="
      ;;
    2)
      local parent_key="$path"
      local parent_label=$(echo "$config" | jq -r ".iso_configs[\"$parent_key\"].label")
      echo ""
      echo "===== $parent_label Submenu ====="
      echo "$config" | jq -r ".iso_configs[\"$parent_key\"].items | to_entries[]? | \"\(.key). \(.value.label)\""
      echo ""
      echo "A. Add ISO Item"
      echo "E. Edit This Category"
      echo "D. Delete This Category"
      echo "B. Back to Previous"
      echo "Q. Quit"
      echo "=============================="
      ;;
    3)
      local parent_key=$(echo "$path" | cut -d'/' -f1)
      local item_key=$(echo "$path" | cut -d'/' -f2)
      local item_data=$(echo "$config" | jq -r ".iso_configs[\"$parent_key\"].items[\"$item_key\"]")
      local item_label=$(echo "$item_data" | jq -r '.label')
      local mount_target=$(echo "$item_data" | jq -r '.mount_target')
      
      echo ""
      echo "===== $item_label Operation Menu ====="
      
      if check_mount_status "$mount_target"; then
        echo "1. Unmount NFS"
        echo "📊 Status: ✅ Mounted"
      else
        echo "1. Mount NFS"
        echo "📊 Status: ❌ Not Mounted"
      fi
      
      echo "2. Edit This ISO"
      echo "3. Delete This ISO"
      echo "4. Show Details"
      echo "B. Back to Previous"
      echo "Q. Quit"
      echo "================================="
      ;;
  esac
}

# Add main category
add_main_category() {
  local config=$(read_config)
  
  echo ""
  echo "===== Add Main Category ====="
  read -r -p "Enter category name: " category_name
  
  if [ -z "$category_name" ]; then
    echo "❌ Category name cannot be empty"
    return
  fi
  
  # Find next available key
  local next_key=1
  while echo "$config" | jq -e ".iso_configs[\"$next_key\"]" > /dev/null 2>&1; do
    ((next_key++))
  done
  
  config=$(echo "$config" | jq ".iso_configs[\"$next_key\"] = {\"label\": \"$category_name\", \"items\": {}}")
  save_config "$config"
  echo "✅ Main category '$category_name' added successfully (ID: $next_key)"
}

# Add ISO item
add_iso_item() {
  local parent_key="$1"
  local config=$(read_config)
  
  echo ""
  echo "===== Add ISO Item ====="
  read -r -p "Enter ISO name (Storage Name): " iso_name
  read -r -p "Enter ISO label: " iso_label
  
  # Default NFS server
  echo "NFS server IP [default: 10.160.88.33]: "
  read -r -p "NFS server: " nfs_server
  nfs_server=${nfs_server:-10.160.88.33}
  
  echo "Enter NFS export path (both \\ and / formats supported):"
  read -r -p "NFS export path: " nfs_export_raw
  
  # Clean and process the path
  local nfs_export="$nfs_export_raw"
  
  # Check if path includes server IP (UNC format like \\server\path or //server/path)
  if [[ "$nfs_export" =~ ^\\\\[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(.*)$ ]]; then
    # Extract path part from UNC format \\IP\path
    nfs_export="${BASH_REMATCH[1]}"
    echo "🔧 Detected UNC format, extracted path: '$nfs_export'"
  elif [[ "$nfs_export" =~ ^//[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(.*)$ ]]; then
    # Extract path part from format //IP/path  
    nfs_export="${BASH_REMATCH[1]}"
    echo "🔧 Detected server/path format, extracted path: '$nfs_export'"
  fi
  
  echo "📝 Using NFS export path: '$nfs_export'"
  
  # Auto-generate mount base from storage name
  local mount_base="/mnt/$iso_name"
  echo "📁 Auto-generated mount path: $mount_base"
  echo "Press Enter to accept or type new path:"
  read -r -p "Mount base path [$mount_base]: " mount_base_input
  mount_base=${mount_base_input:-$mount_base}
  
  if [ -z "$iso_name" ] || [ -z "$iso_label" ] || [ -z "$nfs_server" ] || [ -z "$nfs_export" ] || [ -z "$mount_base" ]; then
    echo "❌ All fields are required"
    return
  fi
  
  # Find next available item key
  local next_key=1
  while echo "$config" | jq -e ".iso_configs[\"$parent_key\"].items[\"$next_key\"]" > /dev/null 2>&1; do
    ((next_key++))
  done
  
  local mount_target="$mount_base/template/iso"
  
  # Create JSON safely using printf to avoid shell quoting issues
  local new_item=$(printf '%s\n' "$iso_name" "$iso_label" "$nfs_server" "$nfs_export" "$mount_base" "$mount_target" | \
    jq -R -s 'split("\n") | {
      "name": .[0],
      "label": .[1],
      "nfs_server": .[2],
      "nfs_export": .[3],
      "mount_base": .[4],
      "mount_target": .[5]
    }')
  
  config=$(echo "$config" | jq --argjson item "$new_item" ".iso_configs[\"$parent_key\"].items[\"$next_key\"] = \$item")
  if [ $? -ne 0 ]; then
    echo "❌ Error updating configuration"
    return 1
  fi
  save_config "$config"
  echo "✅ ISO item '$iso_label' added successfully (ID: $next_key)"
}

# Edit main category
edit_main_category() {
  local category_key="$1"
  local config=$(read_config)
  local current_label=$(echo "$config" | jq -r ".iso_configs[\"$category_key\"].label")
  
  echo ""
  echo "===== Edit Main Category ====="
  echo "Current name: $current_label"
  read -r -p "Enter new name (press Enter to keep unchanged): " new_name
  
  if [ -n "$new_name" ]; then
    config=$(echo "$config" | jq ".iso_configs[\"$category_key\"].label = \"$new_name\"")
    save_config "$config"
    echo "✅ Main category updated to '$new_name'"
  else
    echo "📝 Keep original name"
  fi
}

# Edit ISO item
edit_iso_item() {
  local parent_key="$1"
  local item_key="$2"
  local config=$(read_config)
  local item_data=$(echo "$config" | jq ".iso_configs[\"$parent_key\"].items[\"$item_key\"]")
  
  echo ""
  echo "===== Edit ISO Item ====="
  echo "Current configuration:"
  echo "$item_data" | jq -r 'to_entries[] | "  \(.key): \(.value)"'
  echo ""
  
  local current_name=$(echo "$item_data" | jq -r '.name')
  local current_label=$(echo "$item_data" | jq -r '.label')
  local current_server=$(echo "$item_data" | jq -r '.nfs_server')
  local current_export=$(echo "$item_data" | jq -r '.nfs_export')
  local current_base=$(echo "$item_data" | jq -r '.mount_base')
  
  read -r -p "Storage Name [$current_name]: " new_name
  read -r -p "ISO Label [$current_label]: " new_label
  read -r -p "NFS Server [$current_server]: " new_server
  
  echo "NFS Export Path [$current_export]:"
  read -r -p "New path: " new_export_input
  
  if [ -n "$new_export_input" ]; then
    local new_export="$new_export_input"
    
    # Check if path includes server IP (UNC format)
    if [[ "$new_export" =~ ^\\\\[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(.*)$ ]]; then
      # Extract path part from UNC format \\IP\path
      new_export="${BASH_REMATCH[1]}"
      echo "🔧 Detected UNC format, extracted path: '$new_export'"
    elif [[ "$new_export" =~ ^//[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(.*)$ ]]; then
      # Extract path part from format //IP/path
      new_export="${BASH_REMATCH[1]}"
      echo "🔧 Detected server/path format, extracted path: '$new_export'"
    fi
    
    new_export_input="$new_export"
    echo "📝 Using: '$new_export_input'"
  fi
  
  echo "Mount Base Path [$current_base]:"
  read -r -p "New mount base: " new_base_input
  
  # Use new values or keep original
  new_name=${new_name:-$current_name}
  new_label=${new_label:-$current_label}
  new_server=${new_server:-$current_server}
  local new_export=${new_export_input:-$current_export}
  local new_base=${new_base_input:-$current_base}
  
  # Auto-update mount base if storage name changed
  if [ "$new_name" != "$current_name" ] && [ -z "$new_base_input" ]; then
    new_base="/mnt/$new_name"
    echo "📁 Auto-updated mount base to: $new_base"
  fi
  
  local new_target="$new_base/template/iso"
  
  # Create JSON safely using printf to avoid shell quoting issues
  local updated_item=$(printf '%s\n' "$new_name" "$new_label" "$new_server" "$new_export" "$new_base" "$new_target" | \
    jq -R -s 'split("\n") | {
      "name": .[0],
      "label": .[1],
      "nfs_server": .[2], 
      "nfs_export": .[3],
      "mount_base": .[4],
      "mount_target": .[5]
    }')
  
  config=$(echo "$config" | jq --argjson item "$updated_item" ".iso_configs[\"$parent_key\"].items[\"$item_key\"] = \$item")
  if [ $? -ne 0 ]; then
    echo "❌ Error updating configuration"
    return 1
  fi
  save_config "$config"
  echo "✅ ISO item updated"
}

# Delete main category
delete_main_category() {
  local category_key="$1"
  local config=$(read_config)
  local category_label=$(echo "$config" | jq -r ".iso_configs[\"$category_key\"].label")
  
  echo ""
  echo "⚠️ Confirm deletion of main category '$category_label'?"
  echo "This will also delete all ISO items under this category!"
  read -r -p "Type 'YES' to confirm deletion: " confirm
  
  if [ "$confirm" = "YES" ]; then
    # First unmount all NFS under this category
    echo "$config" | jq -r ".iso_configs[\"$category_key\"].items | to_entries[]? | \"\(.value.name) \(.value.mount_target)\"" | while read name target; do
      if [ -n "$name" ] && [ -n "$target" ]; then
        umount_nfs "$name" "$target"
      fi
    done
    
    config=$(echo "$config" | jq "del(.iso_configs[\"$category_key\"])")
    save_config "$config"
    echo "✅ Main category '$category_label' deleted"
    return 0
  else
    echo "📝 Deletion cancelled"
    return 1
  fi
}

# Delete ISO item
delete_iso_item() {
  local parent_key="$1"
  local item_key="$2"
  local config=$(read_config)
  local item_data=$(echo "$config" | jq ".iso_configs[\"$parent_key\"].items[\"$item_key\"]")
  local item_label=$(echo "$item_data" | jq -r '.label')
  local item_name=$(echo "$item_data" | jq -r '.name')
  local mount_target=$(echo "$item_data" | jq -r '.mount_target')
  
  echo ""
  echo "⚠️ Confirm deletion of ISO item '$item_label'?"
  read -r -p "Type 'YES' to confirm deletion: " confirm
  
  if [ "$confirm" = "YES" ]; then
    # First unmount NFS
    umount_nfs "$item_name" "$mount_target"
    
    config=$(echo "$config" | jq "del(.iso_configs[\"$parent_key\"].items[\"$item_key\"])")
    save_config "$config"
    echo "✅ ISO item '$item_label' deleted"
    return 0
  else
    echo "📝 Deletion cancelled"
    return 1
  fi
}

# Show ISO details
show_iso_details() {
  local parent_key="$1"
  local item_key="$2"
  local config=$(read_config)
  local item_data=$(echo "$config" | jq ".iso_configs[\"$parent_key\"].items[\"$item_key\"]")
  
  echo ""
  echo "======= ISO Details ======="
  echo "$item_data" | jq -r 'to_entries[] | "\(.key): \(.value)"'
  
  local mount_target=$(echo "$item_data" | jq -r '.mount_target')
  local item_name=$(echo "$item_data" | jq -r '.name')
  
  echo ""
  echo "====== Live Status ======"
  if check_mount_status "$mount_target"; then
    echo "Mount Status: ✅ Mounted"
  else
    echo "Mount Status: ❌ Not Mounted"
  fi
  
  if check_storage_cfg "$item_name"; then
    echo "Storage CFG: ✅ Configured"
  else
    echo "Storage CFG: ❌ Not Configured"
  fi
  echo "========================"
}

# Main program
main() {
  # Check if jq is installed
  if ! command -v jq &> /dev/null; then
    echo "❌ This script requires jq tool, please install first:"
    echo "   apt update && apt install -y jq"
    exit 1
  fi
  
  # Show environment info
  if is_pve; then
    echo "🏠 Proxmox VE Environment Detected"
    echo "📁 Config file: $CONFIG_FILE"
  else
    echo "🖥️ Standalone Environment (Non-PVE)"
    echo "📁 Config file: $CONFIG_FILE"
    echo "ℹ️ Storage.cfg operations will be skipped"
  fi
  echo ""
  
  # Initialize configuration
  init_config
  
  # Test config read
  local test_config=$(read_config)
  if [ -z "$test_config" ]; then
    echo "❌ Error: Cannot read configuration file"
    echo "Creating new configuration..."
    echo "$DEFAULT_CONFIG" | jq . > "$CONFIG_FILE"
  fi
  
  local current_level=1
  local current_path=""
  
  while true; do
    show_menu $current_level "$current_path"
    read -r -p "Please enter option: " choice
    
    case $current_level in
      1)
        # Main menu
        case "${choice,,}" in
          [1-9])
            local config=$(read_config)
            if echo "$config" | jq -e ".iso_configs[\"$choice\"]" > /dev/null 2>&1; then
              current_level=2
              current_path="$choice"
            else
              echo "❌ Invalid option"
            fi
            ;;
          a)
            add_main_category
            ;;
          s)
            show_all_status
            ;;
          q)
            echo "👋 Goodbye!"
            exit 0
            ;;
          *)
            echo "❌ Please enter correct option!"
            ;;
        esac
        ;;
      2)
        # Second level menu
        case "${choice,,}" in
          [1-9])
            local config=$(read_config)
            local parent_key="$current_path"
            if echo "$config" | jq -e ".iso_configs[\"$parent_key\"].items[\"$choice\"]" > /dev/null 2>&1; then
              current_level=3
              current_path="$parent_key/$choice"
            else
              echo "❌ Invalid option"
            fi
            ;;
          a)
            add_iso_item "$current_path"
            ;;
          e)
            edit_main_category "$current_path"
            ;;
          d)
            if delete_main_category "$current_path"; then
              current_level=1
              current_path=""
            fi
            ;;
          b)
            current_level=1
            current_path=""
            ;;
          q)
            echo "👋 Goodbye!"
            exit 0
            ;;
          *)
            echo "❌ Please enter correct option!"
            ;;
        esac
        ;;
      3)
        # Third level menu (ISO operations)
        local parent_key=$(echo "$current_path" | cut -d'/' -f1)
        local item_key=$(echo "$current_path" | cut -d'/' -f2)
        local config=$(read_config)
        local item_data=$(echo "$config" | jq ".iso_configs[\"$parent_key\"].items[\"$item_key\"]")
        
        case "${choice,,}" in
          1)
            # Mount/Unmount
            local item_name=$(echo "$item_data" | jq -r '.name')
            local nfs_server=$(echo "$item_data" | jq -r '.nfs_server')
            local nfs_export=$(echo "$item_data" | jq -r '.nfs_export')
            local mount_target=$(echo "$item_data" | jq -r '.mount_target')
            local mount_base=$(echo "$item_data" | jq -r '.mount_base')
            
            if check_mount_status "$mount_target"; then
              umount_nfs "$item_name" "$mount_target"
            else
              mount_nfs "$item_name" "$nfs_server" "$nfs_export" "$mount_target" "$mount_base"
            fi
            ;;
          2)
            edit_iso_item "$parent_key" "$item_key"
            ;;
          3)
            if delete_iso_item "$parent_key" "$item_key"; then
              current_level=2
              current_path="$parent_key"
            fi
            ;;
          4)
            show_iso_details "$parent_key" "$item_key"
            ;;
          b)
            current_level=2
            current_path="$parent_key"
            ;;
          q)
            echo "👋 Goodbye!"
            exit 0
            ;;
          *)
            echo "❌ Please enter correct option!"
            ;;
        esac
        ;;
    esac
    
    # Short pause to let user see messages
    if [[ ! "${choice,,}" =~ ^[bq]$ ]]; then
      echo ""
      read -r -p "Press Enter to continue..."
    fi
  done
}

# Execute main program
main "$@"
