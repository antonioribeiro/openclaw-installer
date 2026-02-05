#!/bin/bash
#
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                    OpenClaw Bootstrap Script                          ║
# ║                    for Ubuntu VPS with Tailscale                         ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# This minimal script sets up the openclaw user, clones the repository,
# and runs the full installer. Designed for "curl | bash" usage.
#
# Version 0.1.1
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

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                  OpenClaw Bootstrap Script                       ║"
echo "║                  for Ubuntu VPS with Tailscale            v0.1.2 ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

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

# Step 2: Clone or update the repository
echo ""
echo -e "${CYAN}▶${NC} Fetching OpenClaw installer..."

# Fix git safe.directory issue for the openclaw user
git config --global --add safe.directory "$REPO_DIR" >/dev/null 2>&1 || true

if [ -d "$REPO_DIR/.git" ]; then
    echo "Updating existing repository..."
    # Ensure correct ownership
    chown -R "$OPENCLAW_USER:$OPENCLAW_USER" "$REPO_DIR" 2>/dev/null || true

    # Run git commands as root to avoid ownership issues
    (cd "$REPO_DIR" && git fetch --depth 1 >/dev/null 2>&1 && git checkout -f main >/dev/null 2>&1 && git reset --hard origin/main >/dev/null 2>&1)

    echo -e "${GREEN}✓${NC} Repository updated ($(cd "$REPO_DIR" && git log -1 --format='%h' 2>/dev/null || echo 'main'))"
else
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
echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""
exec su - "$OPENCLAW_USER" -c "cd \"$REPO_DIR\" && OPENCLAW_REEXEC=1 ./installer.sh"
