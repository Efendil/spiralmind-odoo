#!/bin/bash

set -e

# Startup script for Addon Watcher
# This script starts the addon watcher in the background when the container boots

SCRIPT_DIR="/scripts"
ADDON_WATCHER="$SCRIPT_DIR/addon-watcher.sh"
WATCHER_LOG="/var/log/odoo-addon-watcher-startup.log"
WATCHER_PID_FILE="/tmp/addon-watcher.pid"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} $*" | tee -a "$WATCHER_LOG"
}

log_info() {
    log "${BLUE}[STARTUP]${NC} $*"
}

log_warn() {
    log "${YELLOW}[STARTUP]${NC} $*"
}

log_error() {
    log "${RED}[STARTUP]${NC} $*"
}

log_success() {
    log "${GREEN}[STARTUP]${NC} $*"
}

# Function to run deployment scan
run_deployment_scan() {
    if [ ! -f "$ADDON_WATCHER" ]; then
        log_error "Addon watcher script not found: $ADDON_WATCHER"
        return 1
    fi

    # Make sure the script is executable
    chmod +x "$ADDON_WATCHER"

    log_info "Running deployment scan..."

    # Run deployment scan (one-time)
    if "$ADDON_WATCHER" --deploy 2>&1 | tee -a "$WATCHER_LOG"; then
        log_success "Deployment scan completed successfully"
        return 0
    else
        log_error "Deployment scan failed"
        return 1
    fi
}

# Function alias for backwards compatibility
start_watcher() {
    run_deployment_scan
}

# Function to stop addon watcher (not needed for deployment-only mode)
stop_watcher() {
    log_info "Deployment-only mode - no running processes to stop"
}

# Function to restart addon watcher (just run deployment scan)
restart_watcher() {
    log_info "Running fresh deployment scan..."
    run_deployment_scan
}

# Function to show watcher status
show_status() {
    log_info "Deployment-only mode - watcher runs on container start only"

    # Show recent log entries
    if [ -f "/var/log/odoo-addon-watcher.log" ]; then
        echo ""
        echo -e "${BLUE}Recent addon watcher activity:${NC}"
        tail -n 10 /var/log/odoo-addon-watcher.log
    else
        log_info "No previous watcher activity found"
    fi
}

# Function to wait for Odoo to be ready
wait_for_odoo() {
    local max_attempts=30
    local attempt=0

    log_info "Waiting for Odoo to be ready..."

    while [ $attempt -lt $max_attempts ]; do
        # Check if Odoo process is running
        if pgrep -f "odoo" > /dev/null; then
            # Wait a bit more to ensure it's fully started
            sleep 5
            log_success "Odoo is ready"
            return 0
        fi

        attempt=$((attempt + 1))
        log_info "Attempt $attempt/$max_attempts - waiting for Odoo..."
        sleep 2
    done

    log_warn "Odoo not detected after $max_attempts attempts, starting watcher anyway"
    return 0
}

# Main script logic
case "${1:-start}" in
    "start"|"deploy")
        log_info "=== Running Deployment Scan ==="
        wait_for_odoo
        run_deployment_scan
        ;;
    "stop")
        stop_watcher
        ;;
    "restart"|"rescan")
        restart_watcher
        ;;
    "status")
        show_status
        ;;
    "auto")
        # Auto mode: used by container startup
        log_info "=== Auto-starting Deployment Scan ==="

        # Small delay to let container fully initialize
        sleep 10

        wait_for_odoo
        run_deployment_scan
        ;;
    "help"|"--help"|"-h")
        echo "Addon Watcher Startup Script - Deployment-only Mode"
        echo ""
        echo "Usage:"
        echo "  $0 [start|deploy|rescan|status|auto|help]"
        echo ""
        echo "Commands:"
        echo "  start/deploy  - Run deployment scan (default)"
        echo "  rescan        - Run fresh deployment scan"
        echo "  status        - Show watcher status and recent activity"
        echo "  auto          - Auto-start mode (used by container)"
        echo "  help          - Show this help"
        echo ""
        echo "Note: This runs only on deployment, not continuously."
        echo ""
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use 'help' for usage information"
        exit 1
        ;;
esac
