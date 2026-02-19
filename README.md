# OpenClaw Server — Install Scripts

Automated installer scripts that turn a fresh server into a running [OpenClaw](https://www.npmjs.com/package/openclaw) 2.1 instance.

The scripts install Node.js, Docker, Caddy (reverse proxy), create a dedicated `openclaw` service user, configure a systemd service, and set up a custom login MOTD with your access token and URL.

---

## ⚠️ Security Warning

**OpenClaw is not hardened for production use.** These scripts store API keys as plain text in `~/.openclaw/openclaw.json`. Use only on machines you control and trust. Do not expose the service to the public internet without a firewall and a proper domain + TLS certificate.

---

## Supported Platforms

| Platform | Script | OS | Status |
|---|---|---|---|
| DigitalOcean Droplet | [`digitalocean/install.sh`](digitalocean/install.sh) | Ubuntu 24.04 x86_64 | ✅ Tested |
| Raspberry Pi 5 | [`raspberry-pi/install.sh`](raspberry-pi/install.sh) | Ubuntu Server 24.04 ARM64 | ✅ Tested |

> **Note:** The DigitalOcean script will not work on Raspberry Pi 5 because it installs Homebrew, which has no official ARM64 Linux support. Use the platform-specific script for each target.

---

## DigitalOcean

### Prerequisites

- Fresh Ubuntu 24.04 Droplet
- Root or `sudo` access
- A domain name is optional (the script uses a self-signed certificate by default)

### Install

```bash
wget https://raw.githubusercontent.com/thiagomaf/Openclaw_server/refs/heads/main/digitalocean/install.sh
sudo bash install.sh
```

Or copy the file contents manually into `nano install.sh`, then `sudo bash install.sh`.

---

## Raspberry Pi 5

### Prerequisites

- Raspberry Pi 5 running **Ubuntu Server 24.04 LTS (64-bit)**
- Root or `sudo` access (connect via SSH or directly)
- Internet connection

### Install

```bash
wget https://raw.githubusercontent.com/thiagomaf/Openclaw_server/refs/heads/main/raspberry-pi/install.sh
sudo bash install.sh
```

> **Homebrew / gogcli:** The Pi script skips Homebrew entirely (unsupported on ARM64). If you need `gogcli` for the Google Suite skill, install it manually from source or via a Go binary release.

---

## Post-Installation

After the script finishes, follow the 3-step prompt printed at the end:

```bash
# 1. Switch to the openclaw user
su - openclaw

# 2. Add your AI provider API keys
openclaw onboard
# (choose 'restart' when prompted)

# 3. Start the gateway service
systemctl --user start openclaw-gateway
```

Check service status:
```bash
systemctl --user status openclaw-gateway
```

Run the built-in diagnostics:
```bash
openclaw doctor
```

Open the chat TUI:
```bash
openclaw tui
```

---

## Access

Once the service is running, the access token and URL are printed at install time and shown every time you SSH in (via the MOTD).

| Method | URL |
|---|---|
| HTTP | `http://<server-ip>/?token=<your-token>` |
| HTTPS (self-signed) | `https://<server-ip>/?token=<your-token>` |

For Raspberry Pi, `<server-ip>` is the **local network IP** (e.g. `192.168.1.x`).
For DigitalOcean, it is the **public IP** of your Droplet.

Accept the browser warning for self-signed HTTPS, or point a domain at the server and update `/etc/caddy/Caddyfile` for automatic Let's Encrypt certificates.
