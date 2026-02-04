.PHONY: help install status logs config tailscale onboard webui restart clean harden backup update

SHELL = /bin/bash

OPENCLAW_CONFIG_DIR=$(HOME)/.openclaw
LOG_FILE=/var/log/openclaw_install.log

help:
	@echo "OpenClaw Installation Script - Linux Host Deployment"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  install   - Run installation script (as openclaw user)"
	@echo "  status    - Show OpenClaw, gateway, and system status"
	@echo "  logs      - View OpenClaw installation and service logs"
	@echo "  config    - View OpenClaw configuration"
	@echo "  tailscale - Start Tailscale daemon and authenticate"
	@echo "  onboard   - Run OpenClaw onboarding (interactive)"
	@echo "  webui     - Start OpenClaw gateway service"
	@echo "  restart   - Restart OpenClaw gateway service"
	@echo "  harden    - Restrict SSH/gateway to Tailscale-only access"
	@echo "  backup    - Backup OpenClaw config to /tmp (excludes browser cache)"
	@echo "  update    - Update OpenClaw to latest version and restart gateway"
	@echo "  clean     - Remove OpenClaw config and data"
	@echo "  help      - Show this help message"
	@echo ""
	@echo "Note: Run as 'openclaw' user. Use 'su - openclaw' to switch."

install:
	@echo "Running OpenClaw installation script..."
	@../install.sh

status:
	@echo "=== OpenClaw Status ==="
	@echo ""
	@echo "--- OpenClaw Command ---"
	@command -v openclaw >/dev/null 2>&1 && echo "OpenClaw: $$(openclaw --version 2>/dev/null)" || echo "OpenClaw: Not installed"
	@echo ""
	@echo "--- Node.js ---"
	@command -v node >/dev/null 2>&1 && echo "Node.js: $$(node --version 2>/dev/null)" || echo "Node.js: Not installed"
	@echo ""
	@echo "--- Tailscale ---"
	@command -v tailscale >/dev/null 2>&1 && echo "Tailscale: $$(tailscale version | head -1 2>/dev/null)" || echo "Tailscale: Not installed"
	@if command -v tailscale >/dev/null 2>&1; then \
		if sudo tailscale status >/dev/null 2>&1; then \
			echo "Status: Authenticated"; \
			echo "Tailscale IPs: $$(sudo tailscale ip -4 2>/dev/null)"; \
		else \
			echo "Status: NOT authenticated (run 'make tailscale')"; \
		fi \
	fi
	@echo ""
	@echo "--- OpenClaw Gateway Service ---"
	@systemctl --user is-active openclaw-gateway >/dev/null 2>&1 && echo "Gateway: Running (port 18789)" || echo "Gateway: Not running"
	@echo ""
	@echo "--- System ---"
	@echo "Uptime: $$(uptime -p 2>/dev/null || uptime)"
	@echo "Disk: $$(df -h / | tail -1 | awk '{print $$4 " available"}')"

logs:
	@echo "=== Installation Log ==="
	@sudo cat $(LOG_FILE) 2>/dev/null || echo "No installation log found."
	@echo ""
	@echo "=== OpenClaw Service Logs (journalctl) ==="
	@echo "Use: journalctl --user -u openclaw* -f"
	@echo ""
	@echo "Recent logs:"
	@journalctl --user -u openclaw* -n 20 --no-pager 2>/dev/null || echo "No service logs found."

config:
	@echo "=== OpenClaw Configuration ==="
	@cat $(OPENCLAW_CONFIG_DIR)/openclaw.json 2>/dev/null || echo "No configuration found. Run 'make install' first."
	@echo ""
	@echo "Configuration location: $(OPENCLAW_CONFIG_DIR)/openclaw.json"

tailscale:
	@echo "Starting Tailscale daemon and authentication..."
	@echo "You'll need to open the URL shown below in your browser to authenticate."
	@echo ""
	@sudo systemctl start tailscale 2>/dev/null || true
	@sudo tailscale up

onboard:
	@echo "Running OpenClaw onboarding (interactive)..."
	@echo "Tip: Use the Web UI option instead of TUI for better compatibility."
	@export XDG_RUNTIME_DIR=/run/user/$$(id -u) && openclaw onboard --install-daemon

webui:
	@echo "Starting OpenClaw gateway..."
	@export XDG_RUNTIME_DIR=/run/user/$$(id -u) && systemctl --user daemon-reload && systemctl --user start openclaw-gateway
	@echo ""
	@echo "Gateway should be running on http://127.0.0.1:18789"
	@echo "If using Tailscale, access via your Tailscale IP: http://<tailscale-ip>:18789"

restart:
	@echo "Restarting OpenClaw gateway..."
	@export XDG_RUNTIME_DIR=/run/user/$$(id -u) && systemctl --user daemon-reload && systemctl --user restart openclaw-gateway
	@echo ""
	@echo "Gateway restarted. Check status with:"
	@echo "  make status"
	@echo "  systemctl --user status openclaw-gateway"

clean:
	@echo "Removing OpenClaw configuration and data..."
	@echo "This will delete:"
	@echo "  - $(OPENCLAW_CONFIG_DIR)/"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		rm -rf $(OPENCLAW_CONFIG_DIR); \
		echo "OpenClaw configuration removed."; \
	else \
		echo "Cancelled."; \
	fi

harden:
	@echo "Restricting SSH and gateway to Tailscale-only access..."
	@echo "This will block public internet access to these services."
	@echo ""
	@echo "Current Tailscale IPs:"
	@sudo tailscale ip -4 2>/dev/null || echo "Not authenticated"
	@echo ""
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		sudo ufw delete allow 22/tcp 2>/dev/null || true; \
		sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp; \
		sudo ufw allow from 100.64.0.0/10 to any port 18789 proto tcp; \
		sudo ufw reload; \
		echo ""; \
		echo "Tailscale-only access enabled."; \
		echo "SSH and gateway (18789) now only accessible from Tailscale network."; \
	else \
		echo "Cancelled."; \
	fi

backup:
	@echo "Creating OpenClaw configuration backup..."
	@echo ""
	@TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
	HOSTNAME=$$(hostname); \
	BACKUP_FILE="/tmp/openclaw-backup-$${HOSTNAME}-$${TIMESTAMP}.zip"; \
	echo "Creating: $$BACKUP_FILE"; \
	echo ""; \
	cd "$(HOME)" && \
	zip -rq "$$BACKUP_FILE" .openclaw \
		-x "*/.openclaw/browser/*" \
		-x "*/.openclaw/canvas/*" \
		-x "*/.openclaw/media/*" \
		-x "*/.openclaw/*.bak*" \
		-x "*/.openclaw/update-check.json" \
		2>/dev/null; \
	if [ -f "$$BACKUP_FILE" ]; then \
		SIZE=$$(du -h "$$BACKUP_FILE" | cut -f1); \
		echo "Backup complete: $$SIZE"; \
		echo ""; \
		echo "Transfer to your local machine:"; \
		echo ""; \
		echo "  # Using scp (replace with your local IP/user):"; \
		echo "  scp $$BACKUP_FILE your-user@your-local-host:~/"; \
		echo ""; \
		echo "  # Using rsync (replace with your local IP/user):"; \
		echo "  rsync -avz --progress $$BACKUP_FILE your-user@your-local-host:~/"; \
		echo ""; \
		echo "  # From your local machine (pull):"; \
		echo "  scp $$(whoami)@$$HOSTNAME:$$BACKUP_FILE ./"; \
		echo ""; \
		ls -lh "$$BACKUP_FILE"; \
	else \
		echo "Backup failed! Check if zip is installed: zip --version"; \
	fi

update:
	@echo "Updating OpenClaw to latest version..."
	@echo ""
	@if [ -f update-openclaw.sh ]; then \
		chmod +x update-openclaw.sh; \
		./update-openclaw.sh; \
	else \
		echo "Error: update-openclaw.sh not found."; \
		echo "Please run this command from the server/ directory."; \
		exit 1; \
	fi
