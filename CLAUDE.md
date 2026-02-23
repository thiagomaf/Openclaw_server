# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A collection of bash installer scripts that turn a fresh Ubuntu Server 24.04 into a running [OpenClaw](https://www.npmjs.com/package/openclaw) instance. There is no build system, no tests, and no package.json — just shell scripts.

## Scripts

| Script | Target | Notes |
|---|---|---|
| `digitalocean/install.sh` | Ubuntu 24.04 x86_64 | Caddy default ON; includes Homebrew; fetches public IP via `ifconfig.me` |
| `raspberry-pi/install.sh` | Ubuntu Server 24.04 ARM64 | Caddy default OFF; **no Homebrew** (unsupported on ARM64); uses `hostname -I` for LAN IP |

Both scripts are idempotent (safe to re-run) and must be run as root.

## Architecture: What the Scripts Do

Both scripts follow the same structure:

1. **Create `openclaw` service user** — dedicated non-root user, added to `docker` group, `loginctl enable-linger` enabled so systemd user services persist across logouts.

2. **Install `openclaw` globally** — `npm install -g openclaw@latest`. The binary ends up at `/usr/lib/node_modules/openclaw/`.

3. **Token storage — two separate concerns**:
   - **Gateway token** (`gateway.auth.token` in `~/.openclaw/openclaw.json`): Written by `openclaw onboard` / `openclaw gateway install`. This is what the running gateway enforces. MOTD and final summary read from JSON first, fall back to env file.
   - **AI provider keys** (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.) stay in `~/.config/environment.d/openclaw.env` (chmod 600), auto-loaded by systemd and sourced from `.bashrc`.
   - `OPENCLAW_GATEWAY_TOKEN` in the env file is the initial token set at install time. After `openclaw onboard` runs, the JSON token takes precedence — keep them in sync manually if needed.

4. **Gateway systemd user service** — `openclaw gateway install --force` generates the service file at `~/.openclaw/openclaw-gateway.service`, which is then symlinked to `~/.config/systemd/user/`. Gateway runs on port 18789 with `bind: lan`.

5. **Optional Caddy reverse proxy** — proxies ports 80 and 443 to `127.0.0.1:18789` using a self-signed cert at `/etc/caddy/certs/`. Firewall rules (UFW) open either 80/443 (Caddy) or 18789 (direct) accordingly.

6. **MOTD** — `/etc/update-motd.d/99-openclaw` reads the gateway token from `openclaw.json` (with env file fallback) and displays the access URL and quick-reference commands on SSH login.

## Key Design Constraints

- **Gateway token lives in JSON** — `openclaw onboard` writes `.gateway.auth.token` into `openclaw.json`. This is the authoritative token. Do not try to keep it out of JSON; `openclaw` itself manages it there. AI provider keys stay in the env file only.
- **ARM64 vs x86_64** — Never add Homebrew to the Raspberry Pi script. It has no ARM64 Linux support.
- **Step numbering** — DigitalOcean script has 8 steps (includes Homebrew as step 3); Raspberry Pi script has 7 steps (no Homebrew). Update the `X/N:` prefixes in `log` calls when adding/removing steps.
- **Non-interactive mode** — Both scripts check `[ -t 0 ]` before prompting. When stdin is not a TTY (e.g., piped install via `bash <(curl ...)`), the Caddy prompt defaults silently (DO: yes, RPi: no).
