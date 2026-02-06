.PHONY: help install up down shell wipe logs config reset status tailscale onboard webui tunnel ssh-address

help:
	@echo "OpenClaw Installation Script - Docker Test Helper"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  install   - Install OpenClaw (preserves existing config)"
	@echo "  up        - Start the Ubuntu container"
	@echo "  down     - Stop and remove the container"
	@echo "  wipe     - Complete reset (deletes ALL data including config)"
	@echo "  shell     - Enter the container shell"
	@echo "  tailscale - Start Tailscale daemon and authenticate"
	@echo "  onboard   - Run OpenClaw onboarding (interactive)"
	@echo "  logs      - View installation logs from host"
	@echo "  config    - View OpenClaw config from host"
	@echo "  status    - Show container status"

install: down up
	@echo "Starting container and running installation..."
	@echo "Waiting for systemd to be ready..."
	@sleep 15
	@echo "Running installation script (existing config will be preserved)..."
	docker compose exec -T ubuntu bash -c "cd /mnt && OPENCLAW_ENV=docker bash install.sh"

up:
	@mkdir -p ./.disk/{state,logs,home} || true
	docker compose build --quiet
	@docker rm -f openclaw-installer 2>/dev/null || true
	docker compose up -d

down:
	docker compose down

wipe: down
	@echo "Removing ALL persisted data (including OpenClaw config)..."
	@-rm -rf ./.disk/* 2>/dev/null || true
	@mkdir -p ./.disk/{state,logs,home} || true
	@echo "Wipe complete. Next 'make install' will be a fresh start."

shell:
	docker compose exec ubuntu bash -c "export XDG_RUNTIME_DIR=/run/user/0; su - openclaw"

tailscale:
	@echo "Starting Tailscale daemon in container..."
	@echo "You'll need to open the URL shown below in your browser to authenticate."
	@echo ""
	docker compose exec ubuntu bash -c '\
		mkdir -p /var/lib/tailscale /var/run/tailscale && \
		pkill tailscaled 2>/dev/null || true && \
		tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscale.sock >/dev/null 2>&1 & \
		sleep 2 && \
		tailscale --socket=/var/run/tailscale/tailscale.sock up'

onboard:
	@echo "Running OpenClaw onboarding (interactive)..."
	@echo "Tip: Use the Web UI option instead of TUI for better compatibility."
	docker compose exec --env XDG_RUNTIME_DIR=/run/user/0 ubuntu bash -c "cd /mnt && TERM=xterm-256color openclaw onboard --install-daemon"

webui:
	@echo "Starting OpenClaw gateway and opening shell..."
	@echo "The Web UI will be available inside the container at http://127.0.0.1:18792"
	@echo "Access it from within the container using: curl http://127.0.0.1:18792/"
	docker compose exec --env XDG_RUNTIME_DIR=/run/user/0 ubuntu bash -c "systemctl --user start openclaw-gateway && exec bash"


logs:
	@echo "=== Installation Log ==="
	@cat ./.disk/logs/openclaw_install.log 2>/dev/null || echo "No logs found. Run 'make install' first."
	@echo ""
	@echo "=== To view logs in container ==="
	@echo "docker compose exec ubuntu cat /var/log/openclaw_install.log"

config:
	@echo "=== OpenClaw Config ==="
	@cat ./.disk/home/.openclaw/openclaw.json 2>/dev/null || echo "No config found. Run 'make install' first."
	@echo ""
	@echo "=== To view config in container ==="
	@echo "docker compose exec ubuntu cat ~/.openclaw/openclaw.json"

reset: down up
	@echo "Container restarted (config preserved)."

status:
	@docker compose ps
	@echo ""
	@echo "=== Volumes ==="
	@ls -la ./.disk/ 2>/dev/null || echo "No volumes found."

ssh-address:
	@echo "Container IP: $$(docker compose exec ubuntu hostname -I | awk '{print $$1}')"
	@echo "Use this with: ssh -L 18789:127.0.0.1:18789 root@<IP-ABOVE>"

tunnel:
	@echo "Setting up SSH tunnel to OpenClaw gateway..."
	@echo "Gateway will be accessible at http://localhost:18789/"
	@echo "Press Ctrl+C to stop the tunnel"
	@sleep 2
	@docker compose exec ubuntu bash -c "systemctl start ssh >/dev/null 2>&1 || true"
	@sleep 1
	@ssh -L 18789:127.0.0.1:18789 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$$(docker compose exec ubuntu hostname -I | awk '{print $$1}')
