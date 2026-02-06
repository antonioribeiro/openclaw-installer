#!/bin/bash
#
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                    OpenClaw Bootstrap Script                             ║
# ║                    for Ubuntu VPS with Tailscale                         ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# This minimal script sets up the openclaw user, clones the repository,
# and runs the full installer. Designed for "curl | bash" usage.
#

set -euo pipefail

readonly OPENCLAW_USER="openclaw"
readonly REPO_URL="https://github.com/antonioribeiro/openclaw-installer.git"
readonly REPO_DIR="/home/$OPENCLAW_USER/installer"

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# Must run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Please run: sudo $0"
    exit 1
fi

# Step 1: Create openclaw user
echo -e "${CYAN}▶${NC} Setting up openclaw user..."
if id "$OPENCLAW_USER" &>/dev/null; then
    echo -e "${GREEN}✓${NC} User '$OPENCLAW_USER' already exists"
else
    echo "Creating user '$OPENCLAW_USER'..."
    useradd -m -s /bin/bash "$OPENCLAW_USER"
    usermod -aG sudo "$OPENCLAW_USER"
    mkdir -p /etc/sudoers.d
    echo "$OPENCLAW_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/openclaw
    chmod 440 /etc/sudoers.d/openclaw
    echo -e "${GREEN}✓${NC} User '$OPENCLAW_USER' created with passwordless sudo"
fi

# Step 2: Clone the repository (or use mounted files in Docker)
echo ""
echo -e "${CYAN}▶${NC} Fetching OpenClaw installer..."

if [ "${OPENCLAW_ENV:-}" = "docker" ]; then
    # Docker mode: files are already mounted at /mnt, just copy them
    rm -rf "$REPO_DIR" 2>/dev/null || true
    mkdir -p "$REPO_DIR"
    cp -r /mnt/* "$REPO_DIR/"
    chown -R "$OPENCLAW_USER:$OPENCLAW_USER" "$REPO_DIR"
    echo -e "${GREEN}✓${NC} Using mounted files from /mnt"
else
    # VPS mode: clone from GitHub
    git config --global --add safe.directory "$REPO_DIR" >/dev/null 2>&1 || true
    rm -rf "$REPO_DIR" 2>/dev/null || true
    mkdir -p "$REPO_DIR"
    chown -R "$OPENCLAW_USER:$OPENCLAW_USER" "/home/$OPENCLAW_USER"

    if git clone "$REPO_URL" "$REPO_DIR" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Repository cloned to $REPO_DIR"
    else
        echo -e "${RED}✗${NC} Failed to clone repository"
        echo "Please ensure git is installed: apt install -y git"
        exit 1
    fi
fi

# Step 3: Run the full installer
echo ""
echo -e "${CYAN}▶${NC} Running OpenClaw installer..."
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo ""

# Create log file with proper permissions for openclaw user
touch /var/log/openclaw_install.log
chmod 666 /var/log/openclaw_install.log

# Switch to openclaw user and run installer
exec su - "$OPENCLAW_USER" -c "cd \"$REPO_DIR\" && ./installer.sh"
