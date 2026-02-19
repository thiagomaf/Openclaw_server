#!/bin/bash

# 🦞 OpenClaw 2.1 "Master" Installer (2026 Edition)
# Purpose: Converts a fresh Ubuntu Droplet into a secure, non-root OpenClaw 2.1 instance.
# Targeted for: Fresh Ubuntu 24.04 or 22.04 (Standard Image)

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

clear
echo -e "${CYAN}"
echo "  ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄"
echo "  ██░▄▄▄░██░▄▄░██░▄▄▄██░▀██░██░▄▄▀██░████░▄▄▀██░███░██"
echo "  ██░███░██░▀▀░██░▄▄▄██░█░█░██░█████░████░▀▀░██░█░█░██"
echo "  ██░▀▀▀░██░█████░▀▀▀██░██▄░██░▀▀▄██░▀▀░█░██░██▄▀▄▀▄██"
echo "  ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀"
echo -e "                 ${GREEN}MASTER INSTALLER v2.1 (2026) 'by' thiagomaf${NC}\n"

# 1. System Dependencies
log "1/7: Installing Docker and Node.js 22 (LTS)..."
apt-get update -y > /dev/null
apt-get install -y curl git sudo docker.io jq ufw openssl > /dev/null
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null
apt-get install -y nodejs > /dev/null
success "System dependencies ready."

# 2. Install Caddy Web Server
log "2/7: Installing Caddy reverse proxy..."
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https > /dev/null 2>&1
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
apt-get update -y > /dev/null
apt-get install -y caddy > /dev/null
success "Caddy installed."

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

# 5. Homebrew Installation
log "5/7: Installing Homebrew for user..."
USER_ID=$(id -u "$USER_NAME")
USER_HOME="/home/$USER_NAME"

# Install build dependencies for Homebrew
apt-get install -y build-essential procps file git > /dev/null 2>&1

# Check if Homebrew is already installed
if [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    success "Homebrew already installed, skipping."
else
    # Create Homebrew directory with correct ownership (requires root)
    mkdir -p /home/linuxbrew/.linuxbrew
    chown -R "$USER_NAME:$USER_NAME" /home/linuxbrew
    
    # Install Homebrew as the openclaw user (disable set -e temporarily)
    set +e
    sudo -u "$USER_NAME" NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    BREW_EXIT=$?
    set -e
    
    if [ $BREW_EXIT -eq 0 ] && [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
        success "Homebrew installed for user '$USER_NAME'."
    else
        warn "Homebrew installation had issues (exit code: $BREW_EXIT), continuing anyway..."
    fi
fi

# Add Homebrew to user's PATH
if [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    BREW_PATHS='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"'
    grep -qF "brew shellenv" "$USER_HOME/.bashrc" || { echo ""; echo "$BREW_PATHS"; } >> "$USER_HOME/.bashrc"
    
    # Pre-install gogcli (Google Suite CLI) - required by gog skill
    log "    Installing gogcli (Google Suite CLI)..."
    set +e
    sudo -u "$USER_NAME" /home/linuxbrew/.linuxbrew/bin/brew install steipete/tap/gogcli > /dev/null 2>&1
    GOG_EXIT=$?
    set -e
    if [ $GOG_EXIT -eq 0 ]; then
        success "    gogcli installed."
    else
        warn "    gogcli installation had issues, can be installed later with: brew install steipete/tap/gogcli"
    fi
fi

# Add ~/.local/bin to PATH (for manual binary installs)
mkdir -p "$USER_HOME/.local/bin"
chown "$USER_NAME:$USER_NAME" "$USER_HOME/.local/bin"
grep -qF ".local/bin" "$USER_HOME/.bashrc" || echo 'export PATH=~/.local/bin:$PATH' >> "$USER_HOME/.bashrc"

log "6/7: Initializing user-land configuration..."

sudo -u "$USER_NAME" bash <<EOF
export XDG_RUNTIME_DIR=/run/user/$USER_ID
mkdir -p ~/.openclaw/credentials
mkdir -p ~/.config/systemd/user/

# Configure npm to use user-local directory (avoids permission issues)
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'

# Generate synchronized security tokens (64 chars)
RAND_TOKEN=\$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)

# Create config with correct 2.1 schema
# - "bind": "lan" allows access from DigitalOcean's public IP
# - "allowInsecureAuth": true enables HTTP access without HTTPS
cat <<JSON > ~/.openclaw/openclaw.json
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
      "mode": "token",
      "token": "\$RAND_TOKEN"
    },
    "remote": {
      "token": "\$RAND_TOKEN"
    }
  }
}
JSON

# Install the gateway service
echo "Generating systemd service file..."
openclaw gateway install --force > /dev/null 2>&1 || true

# The service file is named openclaw-gateway.service in 2.1
# Link it to the user systemd directory
if [ -f ~/.openclaw/openclaw-gateway.service ]; then
    ln -sf ~/.openclaw/openclaw-gateway.service ~/.config/systemd/user/openclaw-gateway.service
fi

# Register the unit with the user bus
systemctl --user daemon-reload
systemctl --user enable openclaw-gateway.service || true
EOF

# 7. Caddy Configuration, Environment & Firewall
log "7/7: Configuring Caddy, network and environment..."

# Environment variables
grep -qxF "export XDG_RUNTIME_DIR=/run/user/$USER_ID" "$USER_HOME/.bashrc" || echo "export XDG_RUNTIME_DIR=/run/user/$USER_ID" >> "$USER_HOME/.bashrc"
grep -qxF "export OPENCLAW_UI_DIR=/usr/lib/node_modules/openclaw/dist/ui" "$USER_HOME/.bashrc" || echo "export OPENCLAW_UI_DIR=/usr/lib/node_modules/openclaw/dist/ui" >> "$USER_HOME/.bashrc"
grep -qF ".npm-global/bin" "$USER_HOME/.bashrc" || echo 'export PATH=~/.npm-global/bin:$PATH' >> "$USER_HOME/.bashrc"
grep -qF "NODE_OPTIONS" "$USER_HOME/.bashrc" || echo 'export NODE_OPTIONS="--no-deprecation"' >> "$USER_HOME/.bashrc"

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

# Configure and enable firewall
if command -v ufw > /dev/null; then
    ufw default deny incoming > /dev/null 2>&1 || true
    ufw default allow outgoing > /dev/null 2>&1 || true
    ufw allow 22/tcp > /dev/null 2>&1 || true      # SSH
    ufw allow 80/tcp > /dev/null 2>&1 || true      # HTTP (Caddy)
    ufw allow 443/tcp > /dev/null 2>&1 || true     # HTTPS (Caddy)
    ufw --force enable > /dev/null 2>&1 || true
fi

success "Caddy, network and environment configured."

# Final Summary
# Read token from config file directly as fallback
TOKEN=$(sudo -u "$USER_NAME" openclaw config get gateway.auth.token 2>/dev/null || \
        jq -r '.gateway.auth.token' "$USER_HOME/.openclaw/openclaw.json" 2>/dev/null || \
        echo "check-config-file")
IP_ADDR=$(curl -s ifconfig.me || echo "your-droplet-ip")

echo -e "\n${GREEN}-------------------------------------------------------${NC}"
echo -e "${YELLOW}           OPENCLAW 2.1 SETUP COMPLETE!${NC}"
echo -e "-------------------------------------------------------"
echo -e "Access Token:     ${CYAN}${TOKEN}${NC}"
echo -e "Web Dashboard:    ${CYAN}http://${IP_ADDR}/?token=${TOKEN}${NC}"
echo -e "HTTPS (self-signed): ${CYAN}https://${IP_ADDR}/?token=${TOKEN}${NC}"
echo -e "-------------------------------------------------------"
echo -e "Finalize your setup in 3 quick steps:"
echo -e ""
echo -e " 1. Login to user:  ${YELLOW}su - ${USER_NAME}${NC}"
echo -e " 2. Add AI Keys:    ${YELLOW}openclaw onboard${NC} (choose 'restart' when asked)"
echo -e " 3. Start the Bot:  ${YELLOW}systemctl --user start openclaw-gateway${NC}"
echo -e "-------------------------------------------------------"
echo -e "Homebrew is available: ${CYAN}brew install <package>${NC}"
echo -e "Then run ${CYAN}openclaw tui${NC} to start chatting!"
echo -e ""
echo -e "${YELLOW}Note:${NC} HTTPS uses a self-signed certificate. Accept the"
echo -e "browser warning or add a domain to /etc/caddy/Caddyfile"
echo -e "for automatic Let's Encrypt certificates."
