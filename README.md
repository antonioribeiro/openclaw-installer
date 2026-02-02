# OpenClaw Installation Script for Ubuntu VPS

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Tests](https://github.com/antonioribeiro/openclaw-installer/actions/workflows/test.yml/badge.svg)](https://github.com/antonioribeiro/openclaw-installer/actions/workflows/test.yml)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%7C24.04-orange)](https://ubuntu.com/)
[![Docker](https://img.shields.io/badge/Docker-Supported-blue)](https://www.docker.com/)

A comprehensive, idempotent bash script to install OpenClaw on a clean Ubuntu VPS with Tailscale protection. The script is well-logged, properly structured with functions, and informative throughout all steps.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
  - [Option A: Direct VPS Deployment (One-Liner)](#option-a-direct-vps-deployment-one-liner)
  - [Option B: Clone and Install](#option-b-clone-and-install)
  - [Option C: Local Testing with Docker](#option-c-local-testing-with-docker)
- [Deployment Methods](#deployment-methods)
  - [Direct VPS Deployment](#direct-vps-deployment)
  - [Docker Local Testing](#docker-local-testing)
  - [Migrating from Docker to VPS](#migrating-from-docker-to-vps)
- [What Gets Installed](#what-gets-installed)
- [Installation Steps](#installation-steps)
- [Post-Installation Steps](#post-installation-steps)
- [Service Management](#service-management)
- [Log Files](#log-files)
- [Configuration Files](#configuration-files)
- [Firewall Rules](#firewall-rules)
- [Project Structure](#project-structure)
- [Architecture Considerations](#architecture-considerations)
- [Troubleshooting](#troubleshooting)
- [Uninstalling](#uninstalling)
- [Security Considerations](#security-considerations)
- [Script Exit Codes](#script-exit-codes)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Idempotent**: Can be run multiple times safely
- **Comprehensive Logging**: All operations logged to `/var/log/openclaw_install.log`
- **Color-coded Output**: Easy-to-read console output with color-coded messages
- **Error Handling**: Robust error handling with clear error messages
- **Security First**: Installs and configures Tailscale for secure access
- **Firewall Configuration**: Automatically sets up UFW firewall rules

## Prerequisites

- Clean Ubuntu VPS (22.04 or 24.04 recommended)
- User with sudo privileges
- Internet connectivity
- Minimum 2GB free disk space

**For local macOS testing:** Use [OrbStack](https://orbstack.dev/) instead of Docker Desktop. OrbStack has proper systemd support which is required for OpenClaw's user services. Docker Desktop does not support systemd in containers.

## Quick Start

### Option A: Direct VPS Deployment (One-Liner)

```bash
curl -fsSL https://raw.githubusercontent.com/antonioribeiro/openclaw-installer/main/install.sh | sudo bash
```

Then authenticate Tailscale:

```bash
sudo tailscale up
```

**That's it!** The OpenClaw gateway will be running automatically after installation completes.

### Option B: Clone and Install

```bash
git clone https://github.com/antonioribeiro/openclaw-installer.git
cd openclaw-installer/server
make install
sudo make tailscale
```

### Option C: Local Testing with Docker

```bash
git clone https://github.com/antonioribeiro/openclaw-installer.git
cd openclaw-installer/docker
make install
make status
```

## Deployment Methods

### Direct VPS Deployment

For production deployment on an Ubuntu VPS:

```bash
# Using the server Makefile helper
cd server

# Install (preserves existing config, starts gateway automatically)
sudo make install

# Check system status
make status

# View logs
make logs

# View OpenClaw config
make config

# Start Tailscale authentication
sudo make tailscale

# Run OpenClaw onboarding (only if needed)
make onboard

# Start OpenClaw gateway (should already be running after install)
make webui

# Remove OpenClaw config and data
make clean
```

### Docker Local Testing

For local testing and development:

```bash
cd docker

# Show all available commands
make help

# Install (preserves existing config, starts gateway automatically)
make install

# Check container and service status
make status

# Start/stop container
make up
make down

# Enter container shell
make shell

# View logs from host
make logs

# View OpenClaw config from host
make config

# Start Tailscale in container
make tailscale

# Run OpenClaw onboarding (only if needed)
make onboard

# Start OpenClaw gateway (should already be running after install)
make webui

# Restart container (keeps config)
make reset

# Complete reset (deletes ALL data including config)
make wipe
```

**Benefits of local testing:**
- Verify the script works before touching your VPS
- Faster iteration if you need to make changes
- No risk to your production environment
- Container state persists in `docker/.disk/` folder

**Pro tip:** After your first run, the OpenClaw config is persisted in `.disk/`. Subsequent `make install` runs will detect the existing config and skip onboarding. To start a fresh container with your saved config:

```bash
cd docker
make reset       # Restart container (keeps config)
make webui       # Start the gateway
```

Need a completely fresh start? Use `make wipe` to delete everything including config.

### Migrating from Docker to VPS

Tested locally and ready to go live? Here's how to migrate your OpenClaw configuration to a VPS without losing your assistant:

**1. Export your config from Docker:**

```bash
# Quick export to a tarball
cd docker
tar -czf openclaw-backup.tar.gz -C .disk/home .openclaw

# Or view/copy specific files
make config  # View your config
# Config is stored at: ./.disk/home/.openclaw/
```

**2. Copy the config to your VPS:**

```bash
# From your local machine
scp -r docker/.disk/home/.openclaw user@your-vps-ip:~/
```

Or create a backup archive:

```bash
cd docker
tar -czf openclaw-config.tar.gz -C .disk/home/.openclaw .
# Then: scp openclaw-config.tar.gz user@your-vps-ip:~/
```

**3. On your VPS, extract and install:**

```bash
# If using tar archive:
tar -xzf openclaw-config.tar.gz -C ~/.openclaw/

# Or if you copied the folder directly, it should already be in place
# Now run the installer (it will skip onboarding since config exists)
cd openclaw-installer/server
sudo make install

# Start the gateway
make webui
```

## What Gets Installed

1. **System Updates**: Latest security patches and essential packages
2. **Tailscale**: Secure VPN for private access to your OpenClaw instance
3. **UFW Firewall**: Configured to allow SSH and Tailscale only
4. **Node.js 22.x**: Required runtime for OpenClaw
5. **Homebrew**: Package manager for additional tools (Linuxbrew - most OpenClaw skills work on Linux, except macOS-only ones like Notes and Reminders)
6. **Go**: Required for some OpenClaw components
7. **OpenClaw**: Latest version installed globally via npm
8. **OpenClaw Gateway**: Systemd user service, started and verified automatically

## Installation Steps

The script performs the following steps in order:

### 1. Pre-install Checks
- Validates sudo privileges
- Detects Ubuntu version
- Checks disk space (minimum 2GB)
- Verifies internet connectivity

### 2. System Update
- Updates package lists
- Upgrades installed packages
- Installs essential tools (curl, wget, gnupg, etc.)

### 3. Tailscale Installation
- Adds Tailscale GPG key and repository
- Installs Tailscale package
- Enables Tailscale service
- **Note**: Does NOT auto-authenticate (you must run `sudo tailscale up`)

### 4. Firewall Configuration
- Installs UFW if not present
- Sets default policies (deny incoming, allow outgoing)
- Allows SSH (port 22) to prevent lockout
- Allows Tailscale WireGuard (UDP 41641)

### 5. Node.js Installation
- Removes old Node.js versions if present
- Adds NodeSource repository for Node.js 22.x
- Installs Node.js and npm

### 6. Homebrew Installation
- Installs Homebrew for Linux
- Adds to PATH in .bashrc

### 7. Go Installation
- Installs Go via apt

### 8. OpenClaw Installation
- Installs OpenClaw globally via npm
- Creates required directories
- Verifies installation

### 9. Systemd User Services
- Enables user lingering
- Sets up XDG_RUNTIME_DIR

### 10. Onboarding
- Runs `openclaw onboard --install-daemon`
- Creates OpenClaw configuration
- Installs systemd user service

### 11. Gateway Startup and Verification
- Starts the `openclaw-gateway` systemd user service
- Verifies gateway is accessible on port 18789
- Enables service to start automatically on reboot

**The installation script provides true end-to-end automation:** after the script completes, the OpenClaw gateway is running and ready to use (only Tailscale authentication remains, which requires browser interaction).

## Post-Installation Steps

### 1. Authenticate Tailscale (Required)

```bash
sudo tailscale up
```

Follow the browser prompts to authenticate your machine with your Tailscale account.

**This is the only manual step required.** The installation script handles everything else including starting the OpenClaw gateway.

### 2. Get Your Tailscale IP

```bash
sudo tailscale ip -4
```

Or check your full status:

```bash
sudo tailscale status
```

### 3. Access OpenClaw

Once Tailscale is authenticated, access OpenClaw at:

```
http://<your-tailscale-ip>:18789
```

The gateway should already be running from the installation. You can verify with:

```bash
make status
# or
systemctl --user status openclaw-gateway
```

### 4. Add Channels

```bash
openclaw channel add <channel-name>
```

## Architecture Considerations

### CPU Architecture Requirements

Most OpenClaw skills work on both **x86_64 (AMD64)** and **ARM64** architectures. However, some skills require ARM64:

| Skill | Purpose | ARM64 Required |
|-------|---------|----------------|
| `summarize` | Local AI text summarization | Yes |
| `camsnap` | Camera snapshot functionality | Yes |

These skills typically use local AI models or macOS-specific frameworks that are only available for ARM64 (Apple Silicon).

**If you're on x86_64:** OpenClaw core functionality works perfectly. You'll just be unable to use ARM-only skills. The installation will skip these with a warning.

**If you need ARM-only skills:** Use an ARM64 VPS (AWS Graviton, Oracle ARM, etc.) or an Apple Silicon Mac.

### macOS Local Testing

For testing on macOS, **OrbStack is required** (not Docker Desktop):

- OrbStack properly supports systemd in Linux containers
- Docker Desktop does not support systemd, which breaks OpenClaw's user services
- Install OrbStack from [orbstack.dev](https://orbstack.dev/)

## Service Management

```bash
# Check OpenClaw gateway service status
systemctl --user status openclaw-gateway

# View OpenClaw gateway logs
journalctl --user -u openclaw-gateway -f

# Restart OpenClaw gateway
systemctl --user restart openclaw-gateway

# Stop OpenClaw gateway
systemctl --user stop openclaw-gateway

# Start OpenClaw gateway
systemctl --user start openclaw-gateway
```

## Log Files

- **Installation Log**: `/var/log/openclaw_install.log`
- **OpenClaw Gateway Logs**: `journalctl --user -u openclaw-gateway`

## Configuration Files

- **OpenClaw Config**: `~/.openclaw/openclaw.json`
- **Channels Directory**: `~/.openclaw/channels/`
- **Logs Directory**: `~/.openclaw/logs/`

## Firewall Rules

The script configures UFW with the following rules:

| Rule | Direction | Purpose |
|------|-----------|---------|
| Default deny incoming | In | Block all incoming traffic |
| Default allow outgoing | Out | Allow all outgoing traffic |
| Allow SSH (22/tcp) | In | Prevent SSH lockout |
| Allow Tailscale (41641/udp) | In | Tailscale WireGuard |

### Viewing Firewall Status

```bash
sudo ufw status numbered
```

## Project Structure

```
openclaw-installer/
├── install.sh            # Common installation script (root)
├── README.md             # This file
├── OPENCLAW.md           # Detailed OpenClaw documentation
├── .gitignore            # Git ignore rules
├── docker/               # Docker-based local testing
│   ├── Makefile          # Docker commands
│   ├── docker-compose.yml
│   ├── Dockerfile
│   ├── .dockerignore
│   └── .disk/            # Docker state (persisted)
└── server/               # Direct Linux VPS deployment
    └── Makefile          # Linux host commands
```

## Troubleshooting

### Script Fails with "Permission Denied"

Make sure you're running with sudo:

```bash
sudo ./install.sh
```

### Tailscale Not Connecting

Check Tailscale service status:

```bash
sudo systemctl status tailscale
```

Authenticate Tailscale:

```bash
sudo tailscale up
```

### OpenClaw Command Not Found

The script adds OpenClaw to the system path. If you still can't run it:

```bash
# Check if OpenClaw is installed
which openclaw

# You may need to log out and log back in for PATH changes
```

### Node.js Version Wrong

Check installed version:

```bash
node --version
```

Should show v22.x.x. If not, the script should have handled the upgrade.

### Firewall Blocking Access

Check UFW status:

```bash
sudo ufw status
```

If you need to allow additional ports:

```bash
sudo ufw allow <port>/<protocol>
```

## Uninstalling

To remove OpenClaw and related components:

```bash
# Stop and disable OpenClaw gateway service
systemctl --user stop openclaw-gateway
systemctl --user disable openclaw-gateway

# Remove OpenClaw
npm uninstall -g openclaw

# Remove Tailscale (optional)
sudo apt remove tailscale

# Remove Node.js (optional)
sudo apt remove nodejs npm

# Reset firewall (optional)
sudo ufw --force reset
```

## Security Considerations

1. **Tailscale Authentication**: The script installs Tailscale but does NOT authenticate it. You must manually run `sudo tailscale up` to complete the setup.

2. **Firewall**: All incoming traffic is blocked except:
   - SSH (port 22) for management access
   - Tailscale WireGuard (UDP 41641) for VPN access

3. **OpenClaw Binding**: OpenClaw binds to `127.0.0.1:18789` by default, accessible only through Tailscale when authenticated.

4. **Logs**: Installation logs contain sensitive information and are protected with file permissions.

## Script Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Missing prerequisites |
| 3 | Installation failure |

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

Feel free to submit issues, fork the repository, and create pull requests for any improvements.

## License

MIT License - See [LICENSE](LICENSE) for details.
