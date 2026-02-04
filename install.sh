#!/bin/bash
#
# OpenClaw Installation Script for Ubuntu VPS
# This script installs OpenClaw with Tailscale protection on a clean Ubuntu VPS.
# It is idempotent and can be run multiple times safely.
#
# Usage: sudo ./install.sh
#

set -euo pipefail

# ============================================================================
# CONSTANTS
# ============================================================================

readonly LOG_FILE="/var/log/openclaw_install.log"
readonly NODE_VERSION_REQUIRED=22
readonly MIN_DISK_SPACE_GB=2
readonly OPENCLAW_CONFIG_DIR="$HOME/.openclaw"
readonly OPENCLAW_CONFIG_FILE="$OPENCLAW_CONFIG_DIR/openclaw.json"

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Sudo wrapper - empty if running as root, "sudo" otherwise
SUDO=""
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
fi

# Parse command-line arguments
HARDENED_MODE=false

for arg in "$@"; do
    case $arg in
        --hardened)
            HARDENED_MODE=true
            ;;
    esac
done

# Add user bin to PATH for npm global installs
export PATH="$HOME/.local/bin:$PATH"

# Track whether gateway was running before installation (to restart after)
GATEWAY_WAS_RUNNING=false

# Source OS release info for version detection (needed by multiple functions)
if [ -f /etc/os-release ]; then
    source /etc/os-release
else
    echo "Warning: /etc/os-release not found. Some features may not work correctly."
fi

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

setup_logging() {
    $SUDO touch "$LOG_FILE" 2>/dev/null || touch "$LOG_FILE"
    chmod 640 "$LOG_FILE" 2>/dev/null || true
}

# Internal logging - writes to log file only
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

log_info() {
    log_message "INFO" "$@"
}

log_success() {
    log_message "SUCCESS" "$@"
}

log_warning() {
    log_message "WARNING" "$@"
}

log_error() {
    log_message "ERROR" "$@"
}

log_debug() {
    log_message "DEBUG" "$@"
}

# Console output - shows progress to user (also logged)
log_step() {
    local message="$*"
    log_info "STEP: $message"
    echo -e "${CYAN}▶${NC} ${BOLD}$message${NC}"
}

step_done() {
    local message="${1:-Done}"
    log_success "STEP_COMPLETE: $message"
    echo -e "${GREEN}✓${NC} $message"
}

step_failed() {
    local message="$*"
    log_error "STEP_FAILED: $message"
    echo -e "${RED}✗${NC} ${RED}$message${NC}" >&2
    exit 1
}

# Show final error message with log location
show_error_and_exit() {
    local message="$*"
    echo ""
    echo -e "${RED}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}.  INSTALLATION FAILED${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${RED}Error: $message${NC}"
    echo ""
    echo -e "Check ${BLUE}$LOG_FILE${NC} for details."
    echo ""
    exit 1
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

error_handler() {
    local line_number=$1
    local error_code=$2
    log_error "Script failed at line $line_number with exit code $error_code"
    show_error_and_exit "Installation failed at line $line_number"
}

trap 'error_handler ${LINENO} $?' ERR

# ============================================================================
# TEST FUNCTIONS
# ============================================================================

test_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1
}

test_service() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null || \
    service "$service" status >/dev/null 2>&1
}

# ============================================================================
# PHASE 1: PRE-INSTALL CHECKS & USER SETUP
# ============================================================================

pre_install_checks() {
    log_step "Running pre-install checks"

    local OPENCLAW_USER="openclaw"

    # If running as root, set up the openclaw user
    if [ "$EUID" -eq 0 ]; then
        echo ""
        echo -e "${YELLOW}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}.  RUNNING AS ROOT - SETTING UP OPENCLAW USER${NC}"
        echo -e "${YELLOW}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo ""

        # Check if user already exists
        if id "$OPENCLAW_USER" &>/dev/null; then
            echo -e "${GREEN}✓${NC} User '$OPENCLAW_USER' already exists"
        else
            echo "Creating user '$OPENCLAW_USER'..."
            useradd -m -s /bin/bash "$OPENCLAW_USER"
            usermod -aG sudo "$OPENCLAW_USER"

            # Set up passwordless sudo for the openclaw user
            # Ensure /etc/sudoers.d exists first (may not in some Docker containers)
            mkdir -p /etc/sudoers.d
            echo "$OPENCLAW_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/openclaw
            chmod 440 /etc/sudoers.d/openclaw

            echo -e "${GREEN}✓${NC} User '$OPENCLAW_USER' created with passwordless sudo"
        fi

        # Detect Docker/CI environment
        local IN_DOCKER=false
        if [ -f /.dockerenv ] || [ "$container" = "docker" ] || [ ! -t 0 ]; then
            IN_DOCKER=true
        fi

        if [ "$IN_DOCKER" = true ]; then
            echo ""
            echo -e "${CYAN}Docker/CI environment detected.${NC}"
            echo "Continuing installation as '$OPENCLAW_USER' user..."
            echo ""

            # Copy the script to a location accessible by the openclaw user
            local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            local SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"

            # Ensure the script is accessible and executable
            chmod +x "$SCRIPT_PATH"
            chmod 755 "$HOME" 2>/dev/null || true
            chown -R "$OPENCLAW_USER:$OPENCLAW_USER" "/home/$OPENCLAW_USER" 2>/dev/null || true

            # Run the installation as the openclaw user with proper environment
            # Use su - with -c to get a proper login shell
            su - "$OPENCLAW_USER" -c "cd \"$SCRIPT_DIR\" && \"$SCRIPT_PATH\""
            exit $?
        fi

        # Interactive mode: show instructions and exit
        echo ""
        echo -e "${BOLD}Next steps:${NC}"
        echo "  1. Switch to the openclaw user:"
        echo -e "     ${CYAN}su - openclaw${NC}"
        echo ""
        echo "  2. Re-run the installation:"
        local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

        # Check if there's a server subdirectory in the script's directory
        if [ -d "$SCRIPT_DIR/server" ]; then
            echo -e "     ${CYAN}cd $SCRIPT_DIR/server && make install${NC}"
        else
            echo -e "     ${CYAN}cd $SCRIPT_DIR && ./install.sh${NC}"
        fi
        echo ""
        echo -e "${YELLOW}Why?${NC} OpenClaw and Homebrew cannot run as root."
        echo "       The installation will continue under the '$OPENCLAW_USER' account."
        echo ""

        # Copy the repo to the new user's home for convenience
        if [ "$SCRIPT_DIR" != "/home/$OPENCLAW_USER" ]; then
            mkdir -p "/home/$OPENCLAW_USER/$(basename "$SCRIPT_DIR")" 2>/dev/null || true
            cp -r "$SCRIPT_DIR"/* "/home/$OPENCLAW_USER/$(basename "$SCRIPT_DIR")/" 2>/dev/null || true
            echo -e "${GREEN}✓${NC} Files copied to /home/$OPENCLAW_USER/$(basename "$SCRIPT_DIR")/"
        fi

        exit 0
    fi

    # Check if we're running as the openclaw user (recommended)
    if [ "$(whoami)" != "$OPENCLAW_USER" ]; then
        echo ""
        echo -e "${YELLOW}Warning:${NC} You're not running as the '$OPENCLAW_USER' user."
        echo "For best results, run as '$OPENCLAW_USER'."
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Exiting. Run as '$OPENCLAW_USER' or as root to create the user."
            exit 1
        fi
    fi

    # Stop OpenClaw gateway if running (to avoid file conflicts during update)
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    if systemctl --user is-active --quiet openclaw-gateway 2>/dev/null; then
        echo ""
        echo -e "${YELLOW}Stopping OpenClaw gateway for installation...${NC}"
        systemctl --user stop openclaw-gateway 2>/dev/null || true
        GATEWAY_WAS_RUNNING=true
    else
        GATEWAY_WAS_RUNNING=false
    fi

    # Detect Ubuntu version
    if [ ! -f /etc/os-release ]; then
        step_failed "Cannot detect OS version"
    fi
    source /etc/os-release

    # Check available disk space
    local available_space
    available_space=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
    if [ "$available_space" -lt "$MIN_DISK_SPACE_GB" ]; then
        step_failed "Insufficient disk space. Need ${MIN_DISK_SPACE_GB}GB, have ${available_space}GB"
    fi

    step_done "Pre-install checks passed ($ID $VERSION_ID, ${available_space}GB free)"
}

# ============================================================================
# PHASE 2: UPDATE SYSTEM
# ============================================================================

update_system() {
    log_step "Updating system packages"

    $SUDO apt update >>"$LOG_FILE" 2>&1
    DEBIAN_FRONTEND=noninteractive $SUDO apt upgrade -y >>"$LOG_FILE" 2>&1

    local essential_packages="curl wget gnupg lsb-release ca-certificates iputils-ping git make unzip zip jq"
    DEBIAN_FRONTEND=noninteractive $SUDO apt install -y $essential_packages >>"$LOG_FILE" 2>&1

    # Test: curl should work
    if ! curl -s --connect-timeout 5 https://www.google.com >/dev/null 2>&1; then
        step_failed "Internet connectivity check failed"
    fi

    step_done "System updated and essential packages installed"
}

# ============================================================================
# PHASE 3: INSTALL TAILSCALE
# ============================================================================

install_tailscale() {
    log_step "Installing Tailscale"

    if test_command tailscale; then
        step_done "Tailscale already installed ($(tailscale version | head -1))"
        return 0
    fi

    # Download and dearmor GPG key (to temp file first, then move with sudo)
    local temp_keyring=$(mktemp)
    log_info "Downloading Tailscale GPG key..."
    if ! curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.gpg" \
        | gpg --batch --yes --dearmor -o "$temp_keyring" 2>>"$LOG_FILE"; then
        rm -f "$temp_keyring"
        step_failed "Failed to download Tailscale GPG key"
    fi

    # Verify the keyring was created and has content
    if [ ! -s "$temp_keyring" ]; then
        rm -f "$temp_keyring"
        step_failed "Tailscale GPG keyring is empty"
    fi

    if ! $SUDO mv "$temp_keyring" /usr/share/keyrings/tailscale-archive-keyring.gpg 2>>"$LOG_FILE"; then
        rm -f "$temp_keyring"
        step_failed "Failed to install Tailscale GPG keyring"
    fi

    # Fix permissions so apt can read the keyring
    $SUDO chmod 644 /usr/share/keyrings/tailscale-archive-keyring.gpg 2>>"$LOG_FILE"

    # Add repository (use sudo to write to /etc)
    log_info "Adding Tailscale repository..."
    if ! echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu $VERSION_CODENAME main" \
        | $SUDO tee /etc/apt/sources.list.d/tailscale.list >/dev/null 2>>"$LOG_FILE"; then
        step_failed "Failed to add Tailscale repository"
    fi

    log_info "Updating apt and installing Tailscale..."
    if ! $SUDO apt update >>"$LOG_FILE" 2>&1; then
        step_failed "Failed to update apt for Tailscale"
    fi
    if ! DEBIAN_FRONTEND=noninteractive $SUDO apt install -y tailscale >>"$LOG_FILE" 2>&1; then
        step_failed "Failed to install Tailscale package"
    fi

    # Test: tailscale command should exist
    if ! test_command tailscale; then
        step_failed "Tailscale installation failed - command not found"
    fi

    $SUDO systemctl enable tailscale >>"$LOG_FILE" 2>&1 || true

    step_done "Tailscale installed ($(tailscale version | head -1))"
}

# ============================================================================
# PHASE 4: CONFIGURE FIREWALL
# ============================================================================

configure_firewall() {
    log_step "Configuring UFW firewall"

    if ! test_command ufw; then
        DEBIAN_FRONTEND=noninteractive $SUDO apt install -y ufw >>"$LOG_FILE" 2>&1
    fi

    $SUDO ufw --force reset >/dev/null 2>&1
    $SUDO ufw default deny incoming >/dev/null 2>&1
    $SUDO ufw default allow outgoing >/dev/null 2>&1
    $SUDO ufw allow 22/tcp >/dev/null 2>&1
    $SUDO ufw allow 41641/udp >/dev/null 2>&1
    echo "y" | $SUDO ufw enable >/dev/null 2>&1 || ufw --force enable >/dev/null 2>&1

    # Test: ufw should be active
    if ! $SUDO ufw status | grep -q "Status: active"; then
        step_failed "UFW firewall is not active"
    fi

    step_done "Firewall configured and enabled"
}

# ============================================================================
# PHASE 4.5: INSTALL FAIL2BAN
# ============================================================================

install_fail2ban() {
    log_step "Installing Fail2ban for brute-force protection"

    if command -v fail2ban-server >/dev/null 2>&1; then
        step_done "Fail2ban already installed"
        return 0
    fi

    DEBIAN_FRONTEND=noninteractive $SUDO apt install -y fail2ban >>"$LOG_FILE" 2>&1

    # Create jail.local for SSH protection
    $SUDO tee /etc/fail2ban/jail.local >/dev/null <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
destemail = root@localhost
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 1h
EOF

    $SUDO systemctl enable --now fail2ban >>"$LOG_FILE" 2>&1
    step_done "Fail2ban installed (3 failed attempts = 1hr ban)"
}

# ============================================================================
# PHASE 4.6: HARDEN SSH (Only in --hardened mode)
# ============================================================================

harden_ssh() {
    # Only run in hardened mode
    if [ "$HARDENED_MODE" != true ]; then
        return 0
    fi

    log_step "Hardening SSH configuration"

    # CRITICAL: Check if user has SSH keys BEFORE disabling password auth
    local has_ssh_keys=false

    # Check for common SSH key locations for openclaw user
    if [ -d "$HOME/.ssh" ]; then
        if ls "$HOME/.ssh/id_"* >/dev/null 2>&1; then
            has_ssh_keys=true
        fi
    fi

    # Also check root's keys (user might be root before switching)
    if [ -d /root/.ssh ]; then
        if ls /root/.ssh/id_* >/dev/null 2>&1; then
            has_ssh_keys=true
        fi
    fi

    # Check authorized_keys to see if ANY keys are configured
    if [ -f "$HOME/.ssh/authorized_keys" ] && [ -s "$HOME/.ssh/authorized_keys" ]; then
        has_ssh_keys=true
    fi

    if [ "$has_ssh_keys" = false ]; then
        log_warning "No SSH keys found! Skipping SSH hardening to avoid lockout."
        echo ""
        echo -e "${YELLOW}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}.  SSH HARDENING SKIPPED${NC}"
        echo -e "${YELLOW}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "SSH keys are required for key-only authentication."
        echo -e "To set up SSH keys:"
        echo -e "  ${CYAN}ssh-keygen -t ed25519${NC}"
        echo -e "  ${CYAN}ssh-copy-id openclaw@your-server${NC}"
        echo ""
        echo -e "Then run: ${CYAN}./install.sh --hardened${NC}"
        return 0
    fi

    # SSH keys found - proceed with hardening
    local ssh_config="/etc/ssh/sshd_config"
    local backup_config="/etc/ssh/sshd_config.backup"

    # Backup original config
    if [ ! -f "$backup_config" ]; then
        $SUDO cp "$ssh_config" "$backup_config"
        log_info "Backed up SSH config to $backup_config"
    fi

    # Create hardened config
    $SUDO tee "$ssh_config" >/dev/null <<EOF
# Security-hardened SSH configuration
Port 22
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30s
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers openclaw root
UseDNS yes
EOF

    # Test config before restarting
    if $SUDO sshd -t 2>>"$LOG_FILE"; then
        $SUDO systemctl reload sshd >>"$LOG_FILE" 2>&1
        step_done "SSH hardened (key-only auth, no root login)"
    else
        $SUDO cp "$backup_config" "$ssh_config"
        step_failed "SSH config test failed, restored backup"
    fi
}

# ============================================================================
# PHASE 5: INSTALL GOOGLE CHROME
# ============================================================================

install_google_chrome() {
    log_step "Installing Google Chrome for browser automation"

    # Check if already installed
    if [ -f /opt/google/chrome/google-chrome ]; then
        step_done "Google Chrome already installed"
        return 0
    fi

    # Download Google Chrome deb package
    local chrome_deb="/tmp/google-chrome-stable_current_amd64.deb"
    local chrome_url="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"

    log_info "Downloading Google Chrome..."
    if ! curl -fL "$chrome_url" -o "$chrome_deb" >>"$LOG_FILE" 2>&1; then
        step_failed "Failed to download Google Chrome"
    fi

    # Install Google Chrome
    log_info "Installing Google Chrome (this may take a few minutes)..."
    DEBIAN_FRONTEND=noninteractive $SUDO apt install -y "$chrome_deb" >>"$LOG_FILE" 2>&1

    # Clean up deb file
    rm -f "$chrome_deb"

    # Create symlink for OpenClaw compatibility
    if [ -f /opt/google/chrome/google-chrome ]; then
        $SUDO ln -sf /opt/google/chrome/google-chrome /usr/bin/chromium-browser
        log_info "Created symlink: /usr/bin/chromium-browser -> google-chrome"
    fi

    # Verify installation
    if [ ! -f /opt/google/chrome/google-chrome ]; then
        step_failed "Google Chrome installation failed"
    fi

    local chrome_version=$(/opt/google/chrome/google-chrome --version 2>/dev/null)
    step_done "Google Chrome installed ($chrome_version)"
}

# ============================================================================
# PHASE 7: INSTALL NODE.JS
# ============================================================================

install_nodejs() {
    log_step "Installing Node.js $NODE_VERSION_REQUIRED.x"

    # Check existing
    if test_command node; then
        local current_version
        current_version=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
        if [ "$current_version" -ge "$NODE_VERSION_REQUIRED" ]; then
            # Upgrade npm
            log_info "Upgrading npm..."
            npm install -g npm@latest >>"$LOG_FILE" 2>&1 || true
            step_done "Node.js $(node --version) already installed (npm upgraded)"
            return 0
        fi
    fi

    # Remove old versions
    $SUDO apt remove -y nodejs npm libnode-dev >/dev/null 2>&1 || true
    $SUDO rm -f /etc/apt/sources.list.d/nodesource.list
    $SUDO rm -f /etc/apt/keyrings/nodesource.gpg

    # Add NodeSource repository
    local nodesource_keyring="/etc/apt/keyrings/nodesource.gpg"
    local temp_keyring=$(mktemp)
    curl -fsSL "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" \
        | gpg --batch --yes --dearmor -o "$temp_keyring" 2>/dev/null
    $SUDO mv "$temp_keyring" "$nodesource_keyring"
    $SUDO chmod 644 "$nodesource_keyring" 2>/dev/null

    echo "deb [signed-by=$nodesource_keyring] https://deb.nodesource.com/node_${NODE_VERSION_REQUIRED}.x nodistro main" \
        | $SUDO tee /etc/apt/sources.list.d/nodesource.list >/dev/null

    $SUDO apt update >>"$LOG_FILE" 2>&1
    DEBIAN_FRONTEND=noninteractive $SUDO apt install -y nodejs >>"$LOG_FILE" 2>&1

    # Upgrade npm
    npm install -g npm@latest >>"$LOG_FILE" 2>&1 || true

    # Test: node and npm should work
    if ! test_command node; then
        step_failed "Node.js installation failed - command not found"
    fi
    if ! test_command npm; then
        step_failed "npm installation failed - command not found"
    fi

    local node_version
    node_version=$(node --version 2>/dev/null)
    local npm_version
    npm_version=$(npm --version 2>/dev/null)

    step_done "Node.js $node_version and npm $npm_version installed"
}

# ============================================================================
# PHASE 6: INSTALL HOMEBREW
# ============================================================================

install_homebrew() {
    log_step "Installing Homebrew for Linux"

    if test_command brew; then
        brew update >>"$LOG_FILE" 2>&1 || true
        step_done "Homebrew already installed ($(brew --version | head -1))"
        return 0
    fi

    # Install Homebrew (we're running as non-root openclaw user)
    export NONINTERACTIVE=1
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >>"$LOG_FILE" 2>&1

    # Set up Homebrew environment for current session
    if [ -d /home/linuxbrew/.linuxbrew ]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
    fi

    # Add to .bashrc
    local profile_file="$HOME/.bashrc"
    if ! grep -q 'brew shellenv' "$profile_file" 2>/dev/null; then
        echo '' >> "$profile_file"
        echo '# Homebrew' >> "$profile_file"
        echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"' >> "$profile_file"
    fi

    # Test: brew should work
    if ! test_command brew; then
        step_failed "Homebrew installation failed - command not found"
    fi

    step_done "Homebrew installed ($(brew --version | head -1))"
}

# ============================================================================
# PHASE 7: INSTALL GO
# ============================================================================

install_go() {
    log_step "Installing Go"

    if test_command go; then
        step_done "Go already installed ($(go version 2>/dev/null))"
        return 0
    fi

    # Install Go via apt (reliable version)
    DEBIAN_FRONTEND=noninteractive $SUDO apt install -y golang-go >>"$LOG_FILE" 2>&1

    # Test: go should work
    if ! test_command go; then
        step_failed "Go installation failed - command not found"
    fi

    step_done "Go $(go version 2>/dev/null | awk '{print $3}') installed"
}

# ============================================================================
# PHASE 8: INSTALL OPENCLAW
# ============================================================================

install_openclaw() {
    log_step "Installing OpenClaw"

    mkdir -p "$OPENCLAW_CONFIG_DIR" 2>/dev/null || true
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true

    # Ensure npm can install globally
    if ! npm config get prefix 2>/dev/null | grep -q "$HOME/.local"; then
        npm config set prefix "$HOME/.local" >>"$LOG_FILE" 2>&1
    fi

    # Install OpenClaw (without --silent to see errors)
    log_info "Running: npm install -g openclaw@latest"
    if npm install -g openclaw@latest >>"$LOG_FILE" 2>&1; then
        : # success
    else
        # Check for specific error
        log_error "npm install failed. Checking for common issues..."
        if ! npm --version >>"$LOG_FILE" 2>&1; then
            step_failed "npm is not available. Node.js installation may have failed."
        fi
        step_failed "OpenClaw installation failed - check logs"
    fi

    # Test: openclaw command should work
    if ! test_command openclaw; then
        step_failed "OpenClaw installation failed - command not found"
    fi

    local openclaw_version
    openclaw_version=$(openclaw --version 2>/dev/null)

    step_done "OpenClaw $openclaw_version installed"
}

# ============================================================================
# ENABLE SYSTEMD USER SERVICES
# ============================================================================

enable_systemd_user_services() {
    log_step "Enabling systemd user services"

    # Get current user's UID
    local USER_ID=$(id -u)

    # Enable user lingering so the user manager starts automatically
    $SUDO loginctl enable-linger "$(whoami)" >/dev/null 2>&1 || true

    # Set up XDG_RUNTIME_DIR for the current user
    if [ ! -d "/run/user/$USER_ID" ]; then
        $SUDO mkdir -p "/run/user/$USER_ID"
        $SUDO chmod 700 "/run/user/$USER_ID"
        $SUDO chown "$(whoami):$(whoami)" "/run/user/$USER_ID"
    fi

    # Add to bash profile so it's available in all shells
    if ! grep -q 'XDG_RUNTIME_DIR' "$HOME/.bashrc" 2>/dev/null; then
        echo '' >> "$HOME/.bashrc"
        echo '# XDG Runtime Directory for systemd user services' >> "$HOME/.bashrc"
        echo "export XDG_RUNTIME_DIR=/run/user/$USER_ID" >> "$HOME/.bashrc"
    fi

    # Also set for current session
    export XDG_RUNTIME_DIR="/run/user/$USER_ID"

    step_done "Systemd user services enabled (UID: $USER_ID)"
}

# ============================================================================
# PHASE 9: RUN ONBOARDING
# ============================================================================

run_onboarding() {
    log_step "Checking OpenClaw onboarding"

    # Check if already configured by verifying config file exists and is valid
    if [ -f "$OPENCLAW_CONFIG_FILE" ]; then
        # Also check if the gateway service file exists (indicates --install-daemon was run)
        if systemctl --user list-unit-files 2>/dev/null | grep -q "openclaw-gateway.service"; then
            local instance_id
            instance_id=$(cat "$OPENCLAW_CONFIG_FILE" 2>/dev/null | jq -r '.instanceId // "unknown"' 2>/dev/null || echo "configured")

            # Check if running in interactive mode
            if [ -t 0 ]; then
                echo ""
                echo -e "${CYAN}╶════════════════════════════════════════════════════════════════════════════${NC}"
                echo -e "${CYAN}.  OPENCLAW ALREADY CONFIGURED${NC}"
                echo -e "${CYAN}╶════════════════════════════════════════════════════════════════════════════${NC}"
                echo ""
                echo -e "  Instance: ${BOLD}$instance_id${NC}"
                echo ""
                echo -e "What would you like to do?"
                echo -e "  ${GREEN}1${NC}) Keep existing config and restart gateway"
                echo -e "  ${RED}2${NC}) Full re-onboarding ${RED}(deletes ALL configuration)${NC}"
                echo ""
                read -p "  Choice [1-2]: " -n 1 -r
                echo ""
                echo ""

                case $REPLY in
                    1)
                        echo -e "${GREEN}Keeping existing config, gateway will be restarted...${NC}"
                        return 0
                        ;;
                    2)
                        echo -e "${RED}╶════════════════════════════════════════════════════════════════════════════${NC}"
                        echo -e "${RED}.  WARNING: THIS WILL DELETE YOUR OPENCLAW CONFIGURATION${NC}"
                        echo -e "${RED}╶════════════════════════════════════════════════════════════════════════════${NC}"
                        echo ""
                        echo -e "  ${RED}• All channels will be removed${NC}"
                        echo -e "  ${RED}• All settings will be reset${NC}"
                        echo -e "  ${RED}• Your API keys and credentials will be deleted${NC}"
                        echo ""
                        echo -e "  Instance: ${BOLD}$instance_id${NC}"
                        echo ""
                        read -p "  Type '${BOLD}DELETE${NC}' to confirm: " -r
                        echo ""
                        if [ "$REPLY" = "DELETE" ]; then
                            # Remove existing config to force re-onboarding
                            rm -f "$OPENCLAW_CONFIG_FILE"
                            rm -rf "$OPENCLAW_CONFIG_DIR/channels" 2>/dev/null || true
                            echo -e "${GREEN}Config deleted. Starting fresh onboarding...${NC}"
                        else
                            echo -e "${YELLOW}Cancelled. Keeping existing config.${NC}"
                            return 0
                        fi
                        ;;
                    *)
                        echo -e "${YELLOW}Invalid choice. Keeping existing config.${NC}"
                        return 0
                        ;;
                esac
            else
                # Non-interactive mode - keep existing config
                step_done "OpenClaw already configured (instance: $instance_id)"
                return 0
            fi
        fi
        log_info "Config file exists but gateway service not found. Re-running onboarding..."
    fi

    # Set XDG_RUNTIME_DIR for onboarding
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"

    # Check if running in non-interactive environment
    local non_interactive=false
    if [ ! -t 0 ]; then
        non_interactive=true
        echo ""
        echo -e "${YELLOW}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}.  NON-INTERACTIVE MODE DETECTED${NC}"
        echo -e "${YELLOW}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "Attempting automatic onboarding with ${CYAN}--install-daemon${NC} flag..."
        echo ""
    fi

    log_info "Starting onboarding with --install-daemon..."

    # Run onboarding with --install-daemon flag
    # In non-interactive mode, we still try - openclaw may have auto-confirmation
    if openclaw onboard --install-daemon 2>&1 | tee -a "$LOG_FILE"; then
        # Verify onboarding actually created the config
        if [ -f "$OPENCLAW_CONFIG_FILE" ]; then
            step_done "OpenClaw onboarding completed"
            return 0
        else
            log_warning "Onboarding command succeeded but config file not found"
        fi
    else
        log_warning "Onboarding command exited with error code $?"
    fi

    # If we get here, onboarding didn't complete successfully
    if [ "$non_interactive" = true ]; then
        echo ""
        echo -e "${YELLOW}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}.  AUTOMATIC ONBOARDING INCOMPLETE${NC}"
        echo -e "${YELLOW}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "To complete onboarding, run:"
        echo -e "  ${CYAN}openclaw onboard --install-daemon${NC}"
        echo ""
        echo -e "Then start the gateway:"
        echo -e "  ${CYAN}systemctl --user start openclaw-gateway${NC}"
        echo ""
        # Don't fail the script - continue to gateway startup which will detect the issue
        return 0
    fi

    # Interactive mode - fail if onboarding didn't work
    step_failed "OpenClaw onboarding failed. Check logs at: $LOG_FILE"
}

# ============================================================================
# PHASE 10.5: CONFIGURE VPS DEFAULTS
# ============================================================================

configure_vps_defaults() {
    log_step "Applying VPS-friendly configuration defaults"

    # Only proceed if config file exists
    if [ ! -f "$OPENCLAW_CONFIG_FILE" ]; then
        log_info "No config file found, skipping VPS defaults"
        return 0
    fi

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        log_warning "jq not found, skipping VPS defaults configuration"
        return 0
    fi

    local config_modified=false

    # Ensure browser is configured for headless VPS operation
    log_info "Checking browser configuration..."

    # Check if browser section exists, if not add it
    if ! jq -e '.browser' "$OPENCLAW_CONFIG_FILE" >/dev/null 2>&1; then
        log_info "Adding browser configuration for headless VPS..."
        local temp_config
        temp_config=$(mktemp)
        jq '.browser = {
            "enabled": true,
            "headless": true,
            "noSandbox": false,
            "defaultProfile": "openclaw",
            "profiles": {
                "openclaw": {
                    "cdpPort": 18800,
                    "driver": "openclaw",
                    "color": "#FF4500"
                }
            }
        }' "$OPENCLAW_CONFIG_FILE" > "$temp_config"
        mv "$temp_config" "$OPENCLAW_CONFIG_FILE"
        config_modified=true
    else
        # Browser section exists, check/update headless setting
        local current_headless
        current_headless=$(jq -r '.browser.headless // "false"' "$OPENCLAW_CONFIG_FILE")

        if [ "$current_headless" != "true" ]; then
            log_info "Setting browser.headless = true for VPS..."
            local temp_config
            temp_config=$(mktemp)
            jq '.browser.headless = true' "$OPENCLAW_CONFIG_FILE" > "$temp_config"
            mv "$temp_config" "$OPENCLAW_CONFIG_FILE"
            config_modified=true
        fi

        # Ensure defaultProfile is set
        local current_profile
        current_profile=$(jq -r '.browser.defaultProfile // ""' "$OPENCLAW_CONFIG_FILE")

        if [ -z "$current_profile" ] || [ "$current_profile" = "null" ]; then
            log_info "Setting browser.defaultProfile..."
            local temp_config
            temp_config=$(mktemp)
            jq '.browser.defaultProfile = "openclaw"' "$OPENCLAW_CONFIG_FILE" > "$temp_config"
            mv "$temp_config" "$OPENCLAW_CONFIG_FILE"
            config_modified=true
        fi

        # Ensure profiles section exists with openclaw profile
        if ! jq -e '.browser.profiles.openclaw' "$OPENCLAW_CONFIG_FILE" >/dev/null 2>&1; then
            log_info "Adding browser profile configuration..."
            local temp_config
            temp_config=$(mktemp)
            jq '.browser.profiles.openclaw = {
                "cdpPort": 18800,
                "driver": "openclaw",
                "color": "#FF4500"
            }' "$OPENCLAW_CONFIG_FILE" > "$temp_config"
            mv "$temp_config" "$OPENCLAW_CONFIG_FILE"
            config_modified=true
        fi
    fi

    if [ "$config_modified" = true ]; then
        step_done "VPS configuration applied (gateway will restart)"
        # Signal that gateway needs restart (already running from onboarding)
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        if systemctl --user is-active --quiet openclaw-gateway 2>/dev/null; then
            log_info "Restarting gateway to apply new configuration..."
            systemctl --user restart openclaw-gateway >>"$LOG_FILE" 2>&1
            # Wait a bit for restart
            sleep 3
        fi
    else
        step_done "VPS configuration already optimal"
    fi
}

# ============================================================================
# FIX CREDENTIAL PERMISSIONS
# ============================================================================

fix_credential_permissions() {
    log_step "Securing OpenClaw credentials"

    if [ -d "$OPENCLAW_CONFIG_DIR" ]; then
        # Config directory should be 700 (user only)
        chmod 700 "$OPENCLAW_CONFIG_DIR" 2>/dev/null || true

        # Credentials subdirectory should be 700
        if [ -d "$OPENCLAW_CONFIG_DIR/credentials" ]; then
            chmod 700 "$OPENCLAW_CONFIG_DIR/credentials"
        fi

        # Config file should be 600
        if [ -f "$OPENCLAW_CONFIG_FILE" ]; then
            chmod 600 "$OPENCLAW_CONFIG_FILE"
        fi

        step_done "Credential permissions secured"
    else
        log_info "OpenClaw config not created yet, will secure later"
    fi
}

# ============================================================================
# PHASE 11: START AND VERIFY GATEWAY
# ============================================================================

start_and_verify_gateway() {
    if [ "$GATEWAY_WAS_RUNNING" = true ]; then
        log_step "Restarting OpenClaw gateway"
    else
        log_step "Starting OpenClaw gateway"
    fi

    export XDG_RUNTIME_DIR="/run/user/$(id -u)"

    # Check if the service file exists
    if ! systemctl --user list-unit-files | grep -q "openclaw-gateway.service"; then
        log_warning "Gateway service file not found. Onboarding may not have completed successfully."
        echo ""
        echo -e "${YELLOW}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}.  GATEWAY SERVICE NOT FOUND${NC}"
        echo -e "${YELLOW}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "To complete setup, run:"
        echo -e "  ${CYAN}openclaw onboard --install-daemon${NC}"
        echo -e "  ${CYAN}systemctl --user start openclaw-gateway${NC}"
        echo ""
        return 0
    fi

    # Start the service
    log_info "Starting openclaw-gateway service..."
    systemctl --user start openclaw-gateway >>"$LOG_FILE" 2>&1
    systemctl --user enable openclaw-gateway >>"$LOG_FILE" 2>&1

    # Wait for it to be active
    local max_wait=30
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if systemctl --user is-active openclaw-gateway >/dev/null 2>&1; then
            log_debug "Gateway is active after ${waited}s"
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done

    # Check if service is active
    if ! systemctl --user is-active openclaw-gateway >/dev/null 2>&1; then
        log_warning "Gateway service not active. Status:"
        systemctl --user status openclaw-gateway >>"$LOG_FILE" 2>&1
        echo ""
        echo -e "${YELLOW}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}.  GATEWAY SERVICE NOT ACTIVE${NC}"
        echo -e "${YELLOW}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "To start the gateway manually:"
        echo -e "  ${CYAN}systemctl --user start openclaw-gateway${NC}"
        echo -e "  ${CYAN}systemctl --user status openclaw-gateway${NC}"
        echo ""
        return 0
    fi

    # Health check - verify gateway is listening on port 18789
    local gateway_ready=false

    # Try curl health check first
    if command -v curl >/dev/null 2>&1; then
        for _ in {1..10}; do
            if curl -s http://127.0.0.1:18789/health >/dev/null 2>&1 || \
               curl -s http://127.0.0.1:18789 >/dev/null 2>&1; then
                gateway_ready=true
                log_debug "Gateway health check passed (curl)"
                break
            fi
            sleep 1
        done
    fi

    # Fallback: check if port is listening
    if [ "$gateway_ready" = false ]; then
        if command -v ss >/dev/null 2>&1; then
            if ss -tlnp 2>/dev/null | grep -q ":18789"; then
                gateway_ready=true
                log_debug "Gateway is listening on port 18789"
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tlnp 2>/dev/null | grep -q ":18789"; then
                gateway_ready=true
                log_debug "Gateway is listening on port 18789"
            fi
        fi
    fi

    # Fallback: check if process is running
    if [ "$gateway_ready" = false ]; then
        if pgrep -f "openclaw.*gateway" >/dev/null 2>&1; then
            gateway_ready=true
            log_debug "Gateway process detected"
        fi
    fi

    if [ "$gateway_ready" = true ]; then
        step_done "OpenClaw gateway running and accessible on port 18789"
    else
        log_warning "Gateway service is active but health check failed"
        echo ""
        echo -e "${YELLOW}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}.  GATEWAY MAY NOT BE FULLY READY${NC}"
        echo -e "${YELLOW}╶════════════════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "Check status with: ${CYAN}systemctl --user status openclaw-gateway${NC}"
        echo -e "View logs with:    ${CYAN}journalctl --user -u openclaw-gateway -f${NC}"
        echo ""
    fi
}

# ============================================================================
# RESTRICT TO TAILSCALE (Interactive in --hardened mode)
# ============================================================================

restrict_to_tailscale() {
    # Only run in hardened mode
    if [ "$HARDENED_MODE" != true ]; then
        return 0
    fi

    # Only run interactively
    if [ ! -t 0 ]; then
        return 0
    fi

    # Check if Tailscale is authenticated
    if ! $SUDO tailscale status >/dev/null 2>&1; then
        log_info "Tailscale not authenticated yet. Run '$SUDO tailscale up' first."
        return 0
    fi

    # Get Tailscale network info
    local tailscale_ips
    tailscale_ips=$($SUDO tailscale ip -4 2>/dev/null)

    if [ -z "$tailscale_ips" ]; then
        log_info "No Tailscale IPs found"
        return 0
    fi

    echo ""
    echo -e "${CYAN}╶════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}.  TAILSCALE-ONLY ACCESS MODE${NC}"
    echo -e "${CYAN}╶════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Restrict SSH and gateway access to Tailscale network only."
    echo -e "This blocks public internet access to these services."
    echo ""
    echo -e "Current Tailscale IPs: ${GREEN}$tailscale_ips${NC}"
    echo ""
    echo -e "This will:"
    echo -e "  ${YELLOW}•${NC} Remove public SSH access (port 22 from any)"
    echo -e "  ${YELLOW}•${NC} Allow SSH only from Tailscale network (100.64.0.0/10)"
    echo -e "  ${YELLOW}•${NC} Allow gateway (18789) only from Tailscale network"
    echo ""
    read -p "Enable Tailscale-only access? [y/N] " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        $SUDO ufw delete allow 22/tcp 2>/dev/null || true
        $SUDO ufw allow from 100.64.0.0/10 to any port 22 proto tcp
        $SUDO ufw allow from 100.64.0.0/10 to any port 18789 proto tcp
        $SUDO ufw reload >>"$LOG_FILE" 2>&1
        step_done "SSH and gateway now Tailscale-only"
    else
        log_info "Skipped Tailscale-only configuration"
    fi
}

# ============================================================================
# PHASE 11.5: SETUP AUTO-UPDATE CRON
# ============================================================================

setup_auto_update_cron() {
    log_step "Setting up daily auto-update (3:00 AM)"

    # Find the update script relative to this install script
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local update_script="$script_dir/server/update-openclaw.sh"

    # Make sure it exists and is executable
    if [ ! -f "$update_script" ]; then
        log_warning "Update script not found at $update_script"
        return 0
    fi

    chmod +x "$update_script"

    local cron_entry="0 3 * * * $update_script --quiet >> $HOME/.openclaw/update-cron.log 2>&1"

    # Check if already exists
    if crontab -l 2>/dev/null | grep -q "update-openclaw.sh"; then
        log_info "Crontab entry already exists"
        return 0
    fi

    # Add to crontab
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -

    step_done "Daily auto-update scheduled at 3:00 AM"
}

# ============================================================================
# PHASE 11: PERSIST LOGS
# ============================================================================

persist_logs() {
    if [ -d /logs ] && [ -f "$LOG_FILE" ]; then
        cp "$LOG_FILE" /logs/openclaw_install.log 2>/dev/null || true
        if [ -d "$OPENCLAW_CONFIG_DIR" ]; then
            cp -r "$OPENCLAW_CONFIG_DIR" /logs/ 2>/dev/null || true
        fi
    fi
}

# ============================================================================
# DISPLAY SUMMARY
# ============================================================================

display_summary() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}.  INSTALLATION COMPLETE${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Show installed versions
    echo -e "${BOLD}Installed Components:${NC}"
    test_command node && echo -e "  ${GREEN}✓${NC} Node.js ${BLUE}$(node --version)${NC}"
    test_command npm && echo -e "  ${GREEN}✓${NC} npm ${BLUE}$(npm --version)${NC}"
    test_command go && echo -e "  ${GREEN}✓${NC} Go ${BLUE}$(go version 2>/dev/null | awk '{print $3}')${NC}"
    test_command brew && echo -e "  ${GREEN}✓${NC} Homebrew ${BLUE}$(brew --version | head -1)${NC}"
    test_command tailscale && echo -e "  ${GREEN}✓${NC} Tailscale ${BLUE}$(tailscale version | head -1)${NC}"
    test_command openclaw && echo -e "  ${GREEN}✓${NC} OpenClaw ${BLUE}$(openclaw --version)${NC}"
    echo ""

    # Tailscale authentication
    if test_command tailscale; then
        if $SUDO tailscale status >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Tailscale: ${BLUE}Authenticated${NC}"
        else
            echo -e "  ${YELLOW}⚠${NC} Tailscale: ${YELLOW}NOT authenticated${NC}"
            echo ""
            echo -e "${YELLOW}To authenticate Tailscale, run:${NC}"
            echo -e "  ${CYAN}$SUDO tailscale up${NC}"
        fi
    fi

    # Onboarding status
    if [ -f "$OPENCLAW_CONFIG_FILE" ]; then
        echo ""
        echo -e "  ${GREEN}✓${NC} OpenClaw: ${BLUE}Configured${NC}"
    else
        echo ""
        echo -e "  ${YELLOW}⚠${NC} OpenClaw: ${YELLOW}Not configured${NC}"
        echo -e "${YELLOW}  Run: openclaw onboard --install-daemon${NC}"
    fi

    echo ""
    echo -e "${BOLD}Log file:${NC} ${BLUE}$LOG_FILE${NC}"
    echo -e "${BOLD}Config dir:${NC} ${BLUE}$OPENCLAW_CONFIG_DIR${NC}"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

main() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                   OpenClaw Installation Script                   ║"
    echo "║                   for Ubuntu VPS with Tailscale                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if [ "$HARDENED_MODE" = true ]; then
        echo -e "${YELLOW}Running in HARDENED mode${NC}"
        echo ""
    fi
    echo ""

    setup_logging
    log_info "Starting OpenClaw installation..."
    if [ "$HARDENED_MODE" = true ]; then
        log_info "Hardened mode enabled"
    fi

    pre_install_checks
    update_system
    install_tailscale
    configure_firewall
    install_fail2ban
    harden_ssh
    install_google_chrome
    install_nodejs
    install_homebrew
    install_go
    install_openclaw
    enable_systemd_user_services
    run_onboarding
    configure_vps_defaults
    fix_credential_permissions
    start_and_verify_gateway
    restrict_to_tailscale
    setup_auto_update_cron

    persist_logs
    display_summary

    log_info "Installation completed successfully"
}

main "$@"
