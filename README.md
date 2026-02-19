Bash script to install openclaw 2026.2.1 in a fresh Ubuntu 24.04 hosted (e.g. in DigitalOcean).

Copy the content of `install.sh` somewhere, e.g.:
```bash
nano install.sh
```
Paste the content and save. Or:

```bash
wget https://raw.githubusercontent.com/thiagomaf/Openclaw_server/refs/heads/main/install.sh
```

Then run:
```bash
bash install.sh
```

Install with root priviledge but run with the user indicated after the installation.

Don't be silly, openclaw is not safe and this script even less - all keys are being stored as plain text!
