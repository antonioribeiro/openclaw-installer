#!/bin/bash
#
# OpenClaw Auto-Update Script
# Checks for updates, installs them, and restarts the gateway if needed.
# Designed to be run from cron or manually.
#
# Usage: ./update-openclaw.sh [--quiet]
#

set -euo pipefail

# ============================================================================
# CONSTANTS
# ============================================================================

readonly LOG_FILE="$HOME/.openclaw/update.log"
readonly LOCK_FILE="/tmp/openclaw-update.lock"
readonly LOCK_TIMEOUT=3600  # 1 hour

# Color definitions (disable for cron)
if [ -t 1 ] && [ "${1:-}" != "--quiet" ]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly CYAN='\033[0;36m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly CYAN=''
    readonly NC=''
fi

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_message() {
    local level="$1"
    shift
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local message="[$timestamp] [$level] $*"
    echo "$message" >> "$LOG_FILE"
    if [ "${1:-}" != "--quiet" ]; then
        echo -e "${message}"
    fi
}

log_info() { log_message "INFO" "$@"; }
log_success() { log_message "SUCCESS" "$@"; }
log_error() { log_message "ERROR" "$@"; }

# ============================================================================
# LOCK FILE MANAGEMENT
# ============================================================================

acquire_lock() {
    # Check if lock file exists and is fresh
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
        local lock_age
        lock_age=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo "0")))

        # Check if process is still running
        if [ "$lock_age" -lt "$LOCK_TIMEOUT" ] && kill -0 "$lock_pid" 2>/dev/null; then
            log_info "Another update is already running (PID: $lock_pid)"
            exit 0
        fi

        # Lock is stale, remove it
        rm -f "$LOCK_FILE"
    fi

    # Create new lock
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT
}

# ============================================================================
# VERSION FUNCTIONS
# ============================================================================

get_current_version() {
    openclaw --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown"
}

# ============================================================================
# UPDATE FUNCTIONS
# ============================================================================

run_update() {
    local current_version
    current_version=$(get_current_version)

    log_info "Current OpenClaw version: $current_version"
    log_info "Checking for updates..."

    # Set up environment for npm
    export PATH="$HOME/.local/bin:$PATH"

    # Try update first, fall back to fresh install if it fails
    if npm update -g openclaw >> "$LOG_FILE" 2>&1; then
        local new_version
        new_version=$(get_current_version)

        if [ "$new_version" != "$current_version" ]; then
            log_success "OpenClaw updated: $current_version → $new_version"
            return 0  # Version changed
        else
            log_info "OpenClaw is already up to date ($current_version)"
            return 1  # No change
        fi
    else
        log_warning "npm update failed, trying fresh install..."
        # Clear npm cache and do fresh install
        npm cache clean --force >> "$LOG_FILE" 2>&1 || true

        if npm install -g openclaw@latest >> "$LOG_FILE" 2>&1; then
            local new_version
            new_version=$(get_current_version)

            if [ "$new_version" != "$current_version" ]; then
                log_success "OpenClaw reinstalled: $current_version → $new_version"
                return 0
            else
                log_success "OpenClaw reinstalled (same version: $current_version)"
                return 1
            fi
        else
            log_error "Update failed. Check $LOG_FILE for details."
            return 2
        fi
    fi
}

restart_gateway() {
    local user_id
    user_id="$(id -u)"
    export XDG_RUNTIME_DIR="/run/user/${user_id}"

    if systemctl --user is-active --quiet openclaw-gateway 2>/dev/null; then
        log_info "Restarting OpenClaw gateway..."
        if systemctl --user restart openclaw-gateway >> "$LOG_FILE" 2>&1; then
            # Wait a moment for restart
            sleep 3
            if systemctl --user is-active --quiet openclaw-gateway; then
                log_success "Gateway restarted successfully"
                return 0
            else
                log_error "Gateway failed to start after restart"
                return 1
            fi
        else
            log_error "Failed to restart gateway"
            return 1
        fi
    else
        log_info "Gateway is not running, skipping restart"
        return 0
    fi
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

main() {
    local quiet=false
    [ "${1:-}" = "--quiet" ] && quiet=true

    if [ "$quiet" = false ]; then
        echo -e "${CYAN}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}.  OpenClaw Auto-Update${NC}"
        echo -e "${CYAN}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo ""
    fi

    # Prevent concurrent runs
    acquire_lock

    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"

    # Run update
    if run_update; then
        # Version changed, restart gateway
        restart_gateway
        local exit_code=$?

        if [ "$quiet" = false ]; then
            echo ""
            if [ $exit_code -eq 0 ]; then
                echo -e "${GREEN}✓${NC} Update completed successfully"
                echo -e "${GREEN}✓${NC} Gateway restarted"
            else
                echo -e "${YELLOW}⚠${NC} Update applied but gateway had issues"
            fi
        fi
        exit $exit_code
    elif [ $? -eq 1 ]; then
        # No update available
        [ "$quiet" = false ] && echo -e "${GREEN}✓${NC} Already up to date"
        exit 0
    else
        # Update failed
        if [ "$quiet" = false ]; then
            echo ""
            echo -e "${RED}✗${NC} Update failed. Check logs:"
            echo -e "  ${CYAN}cat $LOG_FILE${NC}"
        fi
        exit 1
    fi
}

main "$@"
