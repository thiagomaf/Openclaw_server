#!/bin/bash

# 🦞 OpenClaw 2.1 "Master" Installer — Raspberry Pi 5 Edition (2026)
# Purpose: Converts a fresh Ubuntu Server 24.04 (ARM64) on Raspberry Pi 5
#          into a secure, non-root OpenClaw 2.1 instance.
# Targeted for: Ubuntu Server 24.04 LTS (64-bit) on Raspberry Pi 5
#
# Note: This script intentionally skips Homebrew.
#       Homebrew has no official ARM64 Linux support and will fail on RPi.
#       If you need gogcli, install it manually via a Go binary release.

set -e

# --- Visual Setup ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${CYAN}[OPENCLAW]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Pre-Flight Checks ---
if [ "$EUID" -ne 0 ]; then error "Please run as root (use sudo)."; fi

clear 2>/dev/null || true
echo -e "${CYAN}"
echo "  ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄"
echo "  ██░▄▄▄░██░▄▄░██░▄▄▄██░▀██░██░▄▄▀██░████░▄▄▀██░███░██"
echo "  ██░███░██░▀▀░██░▄▄▄██░█░█░██░█████░████░▀▀░██░█░█░██"
echo "  ██░▀▀▀░██░█████░▀▀▀██░██▄░██░▀▀▄██░▀▀░█░██░██▄▀▄▀▄██"
echo "  ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀"
echo -e "           ${GREEN}RASPBERRY PI 5 INSTALLER v2.1 (2026) 'by' thiagomaf${NC}\n"

# --- Options ---
echo -e "${YELLOW}Caddy${NC} is a reverse proxy that adds HTTP/HTTPS on ports 80/443."
echo -e "Useful for public servers. For LAN-only setups the gateway runs directly on port 18789."
echo -e ""
if [ -t 0 ]; then
    read -r -p "Install Caddy reverse proxy? [y/N]: " _caddy_ans
else
    _caddy_ans=""
fi
case "${_caddy_ans,,}" in
    y|yes) INSTALL_CADDY=true  ;;
    *)     INSTALL_CADDY=false ;;
esac

if [ "$INSTALL_CADDY" = true ]; then
    echo -e "${GREEN}Caddy will be installed.${NC}\n"
else
    echo -e "${YELLOW}Caddy skipped. Gateway will be accessible directly on port 18789.${NC}\n"
fi

# 1. System Dependencies
log "1/7: Installing Docker and Node.js 22 (LTS)..."
apt-get update -y > /dev/null
apt-get install -y curl git sudo docker.io jq ufw openssl > /dev/null
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null
apt-get install -y nodejs > /dev/null
success "System dependencies ready."

# 2. Install Caddy Web Server (optional)
if [ "$INSTALL_CADDY" = true ]; then
    log "2/7: Installing Caddy reverse proxy..."
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https > /dev/null 2>&1
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null || true
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
    apt-get update -y > /dev/null
    apt-get install -y caddy > /dev/null
    success "Caddy installed."
else
    log "2/7: Caddy installation skipped."
fi

# 3. User Virtualization
log "3/7: Creating 'openclaw' service user..."
USER_NAME="openclaw"
if ! id "$USER_NAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USER_NAME"
fi
usermod -aG docker "$USER_NAME"
loginctl enable-linger "$USER_NAME"
success "User '$USER_NAME' created with Docker permissions."

# 4. Global Package Installation
log "4/7: Fetching latest OpenClaw from NPM..."
npm install -g openclaw@latest > /dev/null
success "OpenClaw binary installed globally."

# 5. User-Land Configuration
USER_ID=$(id -u "$USER_NAME")
USER_HOME="/home/$USER_NAME"

# Add ~/.local/bin to PATH (for manual binary installs)
mkdir -p "$USER_HOME/.local/bin"
chown "$USER_NAME:$USER_NAME" "$USER_HOME/.local/bin"
grep -qF ".local/bin" "$USER_HOME/.bashrc" || echo 'export PATH=~/.local/bin:$PATH' >> "$USER_HOME/.bashrc"

log "5/7: Initializing user-land configuration..."

sudo -u "$USER_NAME" bash <<EOF
export XDG_RUNTIME_DIR=/run/user/$USER_ID
mkdir -p ~/.openclaw/credentials
mkdir -p ~/.config/systemd/user/
mkdir -p ~/.config/environment.d/

# Configure npm to use user-local directory (avoids permission issues)
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'

# Generate gateway token (64 chars)
RAND_TOKEN=\$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)

# --- Secrets stored as environment variables, NOT in JSON ---
# ~/.config/environment.d/openclaw.env is the single source of truth:
#   - Automatically loaded by systemd for all user services
#   - Sourced from .bashrc for interactive shells
cat > ~/.config/environment.d/openclaw.env << 'ENVFILE'
# OpenClaw secrets — do not share or commit this file
# Loaded automatically by systemd; sourced by ~/.bashrc
#
# Gateway token (auto-generated — do not edit manually)
ENVFILE
echo "OPENCLAW_GATEWAY_TOKEN=\$RAND_TOKEN" >> ~/.config/environment.d/openclaw.env
cat >> ~/.config/environment.d/openclaw.env << 'ENVFILE'
#
# AI Provider API Keys
# Uncomment and fill in your key(s), then restart the service:
#   systemctl --user restart openclaw-gateway
#
# ANTHROPIC_API_KEY=
# OPENAI_API_KEY=
# OPENAI_COMPATIBLE_KEY=
# OPENAI_COMPATIBLE_URL=
# GOOGLE_API_KEY=
ENVFILE
chmod 600 ~/.config/environment.d/openclaw.env

# Source the env file from .bashrc (set -a exports all vars to the shell)
grep -qF "environment.d/openclaw.env" ~/.bashrc || cat >> ~/.bashrc << 'BASHRC'
# OpenClaw environment (secrets loaded from env file, not JSON)
if [ -f ~/.config/environment.d/openclaw.env ]; then
    set -a; source ~/.config/environment.d/openclaw.env; set +a
fi
BASHRC

# Create openclaw.json with no secrets embedded
# Token is read from OPENCLAW_GATEWAY_TOKEN env var at runtime
cat > ~/.openclaw/openclaw.json << 'JSON'
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "lan",
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": true
    },
    "auth": {
      "mode": "token"
    }
  }
}
JSON

# Install the gateway service
# Pass token in the environment so openclaw can configure the service correctly.
# At runtime the token comes from ~/.config/environment.d/openclaw.env via systemd.
echo "Generating systemd service file..."
OPENCLAW_GATEWAY_TOKEN=\$RAND_TOKEN openclaw gateway install --force > /dev/null 2>&1 || true

# Link service file to the user systemd directory
if [ -f ~/.openclaw/openclaw-gateway.service ]; then
    ln -sf ~/.openclaw/openclaw-gateway.service ~/.config/systemd/user/openclaw-gateway.service
fi

# Register the unit with the user bus
systemctl --user daemon-reload
systemctl --user enable openclaw-gateway.service || true
EOF

# 6. Environment, Caddy (optional) & Firewall
log "6/7: Configuring environment and network..."

# Non-secret environment variables
grep -qxF "export XDG_RUNTIME_DIR=/run/user/$USER_ID" "$USER_HOME/.bashrc" || echo "export XDG_RUNTIME_DIR=/run/user/$USER_ID" >> "$USER_HOME/.bashrc"
grep -qxF "export OPENCLAW_UI_DIR=/usr/lib/node_modules/openclaw/dist/ui" "$USER_HOME/.bashrc" || echo "export OPENCLAW_UI_DIR=/usr/lib/node_modules/openclaw/dist/ui" >> "$USER_HOME/.bashrc"
grep -qF ".npm-global/bin" "$USER_HOME/.bashrc" || echo 'export PATH=~/.npm-global/bin:$PATH' >> "$USER_HOME/.bashrc"
grep -qF "NODE_OPTIONS" "$USER_HOME/.bashrc" || echo 'export NODE_OPTIONS="--no-deprecation"' >> "$USER_HOME/.bashrc"

if [ "$INSTALL_CADDY" = true ]; then
    # Generate self-signed certificates for HTTPS
    mkdir -p /etc/caddy/certs
    openssl req -x509 -newkey rsa:4096 -keyout /etc/caddy/certs/key.pem -out /etc/caddy/certs/cert.pem -days 365 -nodes -subj "/CN=openclaw" 2>/dev/null
    chown caddy:caddy /etc/caddy/certs/*
    chmod 644 /etc/caddy/certs/cert.pem
    chmod 600 /etc/caddy/certs/key.pem

    # Configure Caddy as reverse proxy (HTTP + HTTPS)
    cat <<'CADDYFILE' > /etc/caddy/Caddyfile
:443 {
    tls /etc/caddy/certs/cert.pem /etc/caddy/certs/key.pem
    reverse_proxy 127.0.0.1:18789
}
:80 {
    reverse_proxy 127.0.0.1:18789
}
CADDYFILE

    systemctl restart caddy
    systemctl enable caddy > /dev/null 2>&1
fi

# Firewall
if command -v ufw > /dev/null; then
    ufw default deny incoming > /dev/null 2>&1 || true
    ufw default allow outgoing > /dev/null 2>&1 || true
    ufw allow 22/tcp > /dev/null 2>&1 || true          # SSH
    if [ "$INSTALL_CADDY" = true ]; then
        ufw allow 80/tcp > /dev/null 2>&1 || true      # HTTP  (Caddy)
        ufw allow 443/tcp > /dev/null 2>&1 || true     # HTTPS (Caddy)
    else
        ufw allow 18789/tcp > /dev/null 2>&1 || true   # OpenClaw gateway (direct)
    fi
    ufw --force enable > /dev/null 2>&1 || true
fi

success "Environment and network configured."

# 7. Setup MOTD
log "7/7: Configuring Message of the Day (MOTD)..."
cat <<'MOTD_SCRIPT' > /etc/update-motd.d/99-openclaw
#!/bin/bash

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

USER_NAME="openclaw"
ENV_FILE="/home/${USER_NAME}/.config/environment.d/openclaw.env"

# Read token from env file (not from JSON)
if [ -f "$ENV_FILE" ]; then
    TOKEN=$(grep -E '^OPENCLAW_GATEWAY_TOKEN=' "$ENV_FILE" | cut -d'=' -f2)
fi
[ -z "$TOKEN" ] && TOKEN="<not-configured>"

# Get local network IP
IP_ADDR=$(hostname -I | awk '{print $1}')
[ -z "$IP_ADDR" ] && IP_ADDR="<ip-address>"

echo -e "${CYAN}"
echo "  ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄"
echo "  ██░▄▄▄░██░▄▄░██░▄▄▄██░▀██░██░▄▄▀██░████░▄▄▀██░███░██"
echo "  ██░███░██░▀▀░██░▄▄▄██░█░█░██░█████░████░▀▀░██░█░█░██"
echo "  ██░▀▀▀░██░█████░▀▀▀██░██▄░██░▀▀▄██░▀▀░█░██░██▄▀▄▀▄██"
echo "  ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀"
echo -e "                 ${GREEN}OPENCLAW SERVER — Raspberry Pi 5${NC}\n"

echo -e "${YELLOW}System Status:${NC}"
echo -e "  User:             ${USER_NAME}"
echo -e "  Service:          openclaw-gateway (systemctl --user status openclaw-gateway)"
echo -e ""
echo -e "${YELLOW}Access Info:${NC}"
echo -e "  Token:            ${CYAN}${TOKEN}${NC}"
if systemctl is-active --quiet caddy 2>/dev/null; then
    echo -e "  Web UI (HTTP):    ${CYAN}http://${IP_ADDR}/?token=${TOKEN}${NC}"
    echo -e "  Web UI (HTTPS):   ${CYAN}https://${IP_ADDR}/?token=${TOKEN}${NC}"
else
    echo -e "  Web UI:           ${CYAN}http://${IP_ADDR}:18789/?token=${TOKEN}${NC}"
fi
echo -e ""
echo -e "${YELLOW}Commands:${NC}"
echo -e "  Switch User:      ${GREEN}su - ${USER_NAME}${NC}"
echo -e "  Add AI keys:      ${GREEN}nano ~/.config/environment.d/openclaw.env${NC}"
echo -e "  Start Service:    ${GREEN}systemctl --user start openclaw-gateway${NC}"
echo -e "  TUI Chat:         ${GREEN}openclaw tui${NC}"
echo -e "  System Check:     ${GREEN}openclaw doctor${NC}"
echo -e ""
MOTD_SCRIPT

chmod +x /etc/update-motd.d/99-openclaw
success "MOTD configured."

# Final Summary
ENV_FILE="$USER_HOME/.config/environment.d/openclaw.env"
TOKEN=$(grep -E '^OPENCLAW_GATEWAY_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "check ~/.config/environment.d/openclaw.env")
IP_ADDR=$(hostname -I | awk '{print $1}')
[ -z "$IP_ADDR" ] && IP_ADDR="<raspberry-pi-ip>"

echo -e "\n${GREEN}-------------------------------------------------------${NC}"
echo -e "${YELLOW}        OPENCLAW 2.1 SETUP COMPLETE! (Raspberry Pi 5)${NC}"
echo -e "-------------------------------------------------------"
echo -e "Access Token:     ${CYAN}${TOKEN}${NC}"
if [ "$INSTALL_CADDY" = true ]; then
    echo -e "Web Dashboard:    ${CYAN}http://${IP_ADDR}/?token=${TOKEN}${NC}"
    echo -e "HTTPS (self-signed): ${CYAN}https://${IP_ADDR}/?token=${TOKEN}${NC}"
else
    echo -e "Web Dashboard:    ${CYAN}http://${IP_ADDR}:18789/?token=${TOKEN}${NC}"
fi
echo -e "-------------------------------------------------------"
echo -e "Secrets are stored in: ${YELLOW}~openclaw/.config/environment.d/openclaw.env${NC}"
echo -e "-------------------------------------------------------"
echo -e "Finalize your setup in 3 quick steps:"
echo -e ""
echo -e " 1. Login to user:  ${YELLOW}su - ${USER_NAME}${NC}"
echo -e " 2. Add AI Keys:    ${YELLOW}nano ~/.config/environment.d/openclaw.env${NC}"
echo -e "                    (then: systemctl --user restart openclaw-gateway)"
echo -e " 3. Start the Bot:  ${YELLOW}systemctl --user start openclaw-gateway${NC}"
echo -e "-------------------------------------------------------"
echo -e "Then run ${CYAN}openclaw tui${NC} to start chatting!"
echo -e ""
if [ "$INSTALL_CADDY" = true ]; then
    echo -e "${YELLOW}Note:${NC} HTTPS uses a self-signed certificate. Accept the"
    echo -e "browser warning or add a domain to /etc/caddy/Caddyfile"
    echo -e "for automatic Let's Encrypt certificates."
    echo -e ""
fi
echo -e "${YELLOW}Note:${NC} Homebrew is NOT installed (unsupported on ARM64)."
echo -e "To install gogcli manually: https://github.com/steipete/gogcli"
