#!/bin/bash

set -e

# Addon Watcher Script for Odoo
# Scans addon directories on deployment and upgrades changed modules
# Based on to-do.txt requirements - runs only on deploy, not continuously

SCRIPT_NAME="addon-watcher"
LOG_FILE="/var/log/odoo-addon-watcher.log"
ADDONS_BASE_DIR="/mnt"
WATCH_DIRS=()
ODOO_CONFIG="/etc/odoo/odoo.conf"
ODOO_BIN="/usr/bin/odoo"
PYTHON_BIN="/usr/bin/python3"
STATE_FILE="/tmp/addon-states.json"
UPGRADE_LOCK="/tmp/addon-upgrade.lock"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "${BLUE}[${SCRIPT_NAME}]${NC} $*"
}

log_warn() {
    log "WARN" "${YELLOW}[${SCRIPT_NAME}]${NC} $*"
}

log_error() {
    log "ERROR" "${RED}[${SCRIPT_NAME}]${NC} $*"
}

log_success() {
    log "SUCCESS" "${GREEN}[${SCRIPT_NAME}]${NC} $*"
}

# Function to get database name from config
get_database_name() {
    local db_name=""

    # Try to get from environment first
    if [ -n "$POSTGRES_DB" ]; then
        db_name="$POSTGRES_DB"
    elif [ -n "$DB_NAME" ]; then
        db_name="$DB_NAME"
    else
        # Default database name
        db_name="postgres"
    fi

    echo "$db_name"
}

# Function to discover all addon directories
discover_addon_directories() {
    WATCH_DIRS=()

    if [ ! -d "$ADDONS_BASE_DIR" ]; then
        log_warn "Addons base directory does not exist: $ADDONS_BASE_DIR"
        return
    fi

    # Find all directories in /mnt that could contain addons
    while IFS= read -r -d '' dir; do
        local dir_name=$(basename "$dir")
        # Skip hidden directories and common non-addon directories
        if [[ "$dir_name" != .* && "$dir_name" != "__pycache__" && "$dir_name" =~ (addons|custom) ]]; then
            WATCH_DIRS+=("$dir")
            log_info "Discovered addon directory: $dir"
        fi
    done < <(find "$ADDONS_BASE_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    # If no addon-like directories found, scan all directories
    if [ ${#WATCH_DIRS[@]} -eq 0 ]; then
        log_info "No addon-specific directories found, scanning all directories in $ADDONS_BASE_DIR"
        while IFS= read -r -d '' dir; do
            local dir_name=$(basename "$dir")
            # Skip hidden directories and common non-addon directories
            if [[ "$dir_name" != .* && "$dir_name" != "__pycache__" ]]; then
                WATCH_DIRS+=("$dir")
                log_info "Added directory: $dir"
            fi
        done < <(find "$ADDONS_BASE_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi

    log_info "Total addon directories to watch: ${#WATCH_DIRS[@]}"
}

# Function to scan addon directories and detect modules
scan_addons() {
    local addon_dir="$1"
    local modules=()

    if [ ! -d "$addon_dir" ]; then
        return
    fi

    # Find all directories containing __manifest__.py or __openerp__.py
    while IFS= read -r -d '' manifest_file; do
        local module_dir=$(dirname "$manifest_file")
        local module_name=$(basename "$module_dir")

        # Skip hidden directories and common non-addon directories
        if [[ "$module_name" != .* && "$module_name" != "__pycache__" ]]; then
            modules+=("$module_name")
        fi
    done < <(find "$addon_dir" -maxdepth 2 -name "__manifest__.py" -o -name "__openerp__.py" -print0 2>/dev/null)

    printf '%s\n' "${modules[@]}"
}

# Function to get directory modification time and file count
get_dir_state() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo "not_exists"
        return
    fi

    # Get modification time and file count as state
    local mod_time=$(find "$dir" -type f \( -name "*.py" -o -name "*.xml" -o -name "*.js" -o -name "*.css" -o -name "*.yml" \) -exec stat -f "%m" {} \; 2>/dev/null | sort -n | tail -1)
    local file_count=$(find "$dir" -type f \( -name "*.py" -o -name "*.xml" -o -name "*.js" -o -name "*.css" -o -name "*.yml" \) | wc -l | tr -d ' ')

    echo "${mod_time:-0}_${file_count:-0}"
}

# Function to load previous states
load_states() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "{}"
    fi
}

# Function to save states
save_states() {
    local states="$1"
    echo "$states" > "$STATE_FILE"
}

# Function to check if module is installed in database
is_module_installed() {
    local module_name="$1"
    local db_name=$(get_database_name)

    # Use Odoo to check module state
    local check_cmd="$PYTHON_BIN $ODOO_BIN -c $ODOO_CONFIG -d $db_name --stop-after-init -e 'import odoo; env = odoo.api.Environment.manage(); cr = odoo.registry(\"$db_name\").cursor(); cr.execute(\"SELECT state FROM ir_module_module WHERE name = %s\", (\"$module_name\",)); result = cr.fetchone(); print(result[0] if result else \"not_found\"); cr.close()'"

    local result=$(eval "$check_cmd" 2>/dev/null | tail -1)

    if [[ "$result" == "installed" || "$result" == "to upgrade" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to install and upgrade modules intelligently
process_modules() {
    local new_modules=("$1")
    local changed_modules=("$2")
    local db_name=$(get_database_name)

    # Create upgrade lock
    if [ -f "$UPGRADE_LOCK" ]; then
        log_warn "Another upgrade process is running, skipping..."
        return
    fi

    echo $$ > "$UPGRADE_LOCK"

    local install_list=()
    local upgrade_list=()

    # Separate new modules for install vs upgrade
    for module in "${new_modules[@]}"; do
        if is_module_installed "$module"; then
            upgrade_list+=("$module")
            log_info "Module $module is installed - will upgrade"
        else
            install_list+=("$module")
            log_info "Module $module is new - will install"
        fi
    done

    # Add changed modules to upgrade list
    for module in "${changed_modules[@]}"; do
        if [[ ! " ${new_modules[@]} " =~ " $module " ]]; then
            upgrade_list+=("$module")
            log_info "Module $module has changes - will upgrade"
        fi
    done

    # Install new modules
    if [ ${#install_list[@]} -gt 0 ]; then
        local install_module_list=$(IFS=','; echo "${install_list[*]}")
        local install_cmd="$PYTHON_BIN $ODOO_BIN -c $ODOO_CONFIG -i $install_module_list -d $db_name --stop-after-init"

        log_info "Installing new modules: ${install_list[*]}"
        log_info "Executing: $install_cmd"

        if timeout 300 $install_cmd >> "$LOG_FILE" 2>&1; then
            log_success "Successfully installed modules: ${install_list[*]}"
        else
            log_error "Failed to install modules: ${install_list[*]}"
            log_error "Check $LOG_FILE for detailed error information"
        fi
    fi

    # Upgrade existing modules
    if [ ${#upgrade_list[@]} -gt 0 ]; then
        local upgrade_module_list=$(IFS=','; echo "${upgrade_list[*]}")
        local upgrade_cmd="$PYTHON_BIN $ODOO_BIN -c $ODOO_CONFIG -u $upgrade_module_list -d $db_name --stop-after-init"

        log_info "Upgrading existing modules: ${upgrade_list[*]}"
        log_info "Executing: $upgrade_cmd"

        if timeout 300 $upgrade_cmd >> "$LOG_FILE" 2>&1; then
            log_success "Successfully upgraded modules: ${upgrade_list[*]}"
        else
            log_error "Failed to upgrade modules: ${upgrade_list[*]}"
            log_error "Check $LOG_FILE for detailed error information"
        fi
    fi

    if [ ${#install_list[@]} -eq 0 ] && [ ${#upgrade_list[@]} -eq 0 ]; then
        log_info "No modules to install or upgrade"
    fi

    # Remove upgrade lock
    rm -f "$UPGRADE_LOCK"
}

# Legacy function for backwards compatibility
upgrade_modules() {
    local modules=("$@")
    process_modules "" "${modules[*]}"
}

# Function to detect and upgrade changed modules
detect_and_upgrade_changes() {
    local current_states="{}"
    local previous_states=$(load_states)
    local changed_modules=()
    local new_modules=()

    log_info "Scanning addon directories for changes..."

    # First discover all addon directories
    discover_addon_directories

    # Build current states
    for watch_dir in "${WATCH_DIRS[@]}"; do
        if [ -d "$watch_dir" ]; then
            log_info "Scanning directory: $watch_dir"

            local modules=($(scan_addons "$watch_dir"))

            for module in "${modules[@]}"; do
                local module_path="$watch_dir/$module"
                local current_state=$(get_dir_state "$module_path")

                # Update current states JSON (simplified approach)
                current_states=$(echo "$current_states" | python3 -c "
import sys, json
states = json.load(sys.stdin)
states['$module'] = '$current_state'
json.dump(states, sys.stdout)
" 2>/dev/null || echo "{\"$module\": \"$current_state\"}")

                # Check if module state changed
                local previous_state=$(echo "$previous_states" | python3 -c "
import sys, json
try:
    states = json.load(sys.stdin)
    print(states.get('$module', 'new'))
except:
    print('new')
" 2>/dev/null || echo "new")

                if [ "$current_state" != "$previous_state" ]; then
                    log_info "Detected changes in module: $module"
                    log_info "  Previous state: $previous_state"
                    log_info "  Current state: $current_state"

                    if [ "$previous_state" == "new" ]; then
                        new_modules+=("$module")
                    else
                        changed_modules+=("$module")
                    fi
                fi
            done
        else
            log_warn "Watch directory does not exist: $watch_dir"
        fi
    done

    # Save current states
    save_states "$current_states"

    # Process new and changed modules
    local total_modules=$((${#new_modules[@]} + ${#changed_modules[@]}))
    if [ $total_modules -gt 0 ]; then
        log_info "Found $total_modules modules to process:"
        [ ${#new_modules[@]} -gt 0 ] && log_info "  New modules: ${new_modules[*]}"
        [ ${#changed_modules[@]} -gt 0 ] && log_info "  Changed modules: ${changed_modules[*]}"
        process_modules "${new_modules[*]}" "${changed_modules[*]}"
    else
        log_info "No new or changed modules detected"
    fi
}

# Function to run initial scan and setup
initial_setup() {
    log_info "Starting Odoo Addon Watcher v1.0"
    log_info "Configuration:"
    log_info "  Scanning base directory: $ADDONS_BASE_DIR"
    log_info "  Odoo config: $ODOO_CONFIG"
    log_info "  Odoo binary: $ODOO_BIN"
    log_info "  Log file: $LOG_FILE"

    # Discover addon directories
    discover_addon_directories
    log_info "  Watch directories: ${WATCH_DIRS[*]}"

    # Create log file if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    # Verify Odoo installation
    if [ ! -f "$ODOO_BIN" ]; then
        log_error "Odoo binary not found: $ODOO_BIN"
        exit 1
    fi

    if [ ! -f "$ODOO_CONFIG" ]; then
        log_error "Odoo config not found: $ODOO_CONFIG"
        exit 1
    fi

    # Initial scan to establish baseline
    log_info "Performing initial addon scan..."
    detect_and_upgrade_changes
}

# Function for deployment-only scan mode
deploy_scan() {
    log_info "Running deployment scan (one-time check)"
    detect_and_upgrade_changes
    log_info "Deployment scan completed"
}

# Function to manually upgrade specific modules
manual_upgrade() {
    local modules=("$@")

    if [ ${#modules[@]} -eq 0 ]; then
        log_error "No modules specified for manual upgrade"
        echo "Usage: $0 --manual-upgrade module1 module2 ..."
        exit 1
    fi

    log_info "Manual upgrade requested for: ${modules[*]}"
    upgrade_modules "${modules[@]}"
}

# Function to show current addon status
show_status() {
    log_info "Current addon status:"

    # Discover addon directories first
    discover_addon_directories

    for watch_dir in "${WATCH_DIRS[@]}"; do
        if [ -d "$watch_dir" ]; then
            echo -e "\n${BLUE}Directory: $watch_dir${NC}"
            local modules=($(scan_addons "$watch_dir"))

            if [ ${#modules[@]} -eq 0 ]; then
                echo "  No addons found"
            else
                for module in "${modules[@]}"; do
                    local module_path="$watch_dir/$module"
                    local state=$(get_dir_state "$module_path")
                    echo -e "  ${GREEN}✓${NC} $module (state: $state)"
                done
            fi
        else
            echo -e "\n${RED}Directory not found: $watch_dir${NC}"
        fi
    done
}

# Main script logic
case "${1:-}" in
    "--deploy"|"-d"|"")
        initial_setup
        deploy_scan
        ;;
    "--scan"|"-s")
        initial_setup
        deploy_scan
        ;;
    "--manual-upgrade"|"--upgrade"|"-u")
        shift
        manual_upgrade "$@"
        ;;
    "--status"|"--show")
        show_status
        ;;
    "--help"|"-h")
        echo "Odoo Addon Watcher - Deployment-based addon upgrading"
        echo ""
        echo "Usage:"
        echo "  $0 --deploy                 Run deployment scan (default)"
        echo "  $0 --scan                   Perform one-time scan and upgrade"
        echo "  $0 --manual-upgrade mod1 mod2  Manually upgrade specific modules"
        echo "  $0 --status                 Show current addon status"
        echo "  $0 --help                   Show this help"
        echo ""
        echo "Examples:"
        echo "  $0 --deploy                # Deployment scan (default)"
        echo "  $0 --scan                  # One-time scan"
        echo "  $0 -u sale_logistics_pricing shipment_management"
        echo ""
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
