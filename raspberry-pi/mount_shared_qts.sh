#!/bin/bash
set -e

# === Config ===
NAS_IP="192.168.1.132"
NAS_USER="caranguejo"
CRED_FILE="/etc/nas-credentials"

# Shares: name:mount_point:access:extra_opts
# uid=1001 (openclaw), gid=1006 (nas_access) — both thiagomaf and openclaw are in nas_access
SHARES=(
  "Novonesis:/mnt/nas/Novonesis:ro:"
  "caranguejo_vault:/mnt/nas/caranguejo_vault:rw:uid=1001,gid=1006,dir_mode=0775,file_mode=0775"
)

# Step 1: Install SMB client
echo ">>> Installing cifs-utils..."
sudo apt update && sudo apt install cifs-utils -y

# Step 2: Prompt for password and store credentials securely
read -s -p "Enter NAS password for $NAS_USER: " NAS_PASS
echo

echo ">>> Writing credentials to $CRED_FILE..."
sudo bash -c "cat > $CRED_FILE" <<EOF
username=$NAS_USER
password=$NAS_PASS
EOF
sudo chown root:root "$CRED_FILE"
sudo chmod 600 "$CRED_FILE"

# Step 3: Ensure network-online.target is waited on at boot
echo ">>> Enabling systemd-networkd-wait-online..."
sudo systemctl enable systemd-networkd-wait-online.service 2>/dev/null || true

# Step 4: Mount each share
for ENTRY in "${SHARES[@]}"; do
  IFS=':' read -r SHARE_NAME MOUNT_POINT ACCESS EXTRA_OPTS <<< "$ENTRY"

  # Build options string
  OPTS="credentials=$CRED_FILE,vers=3.0,iocharset=utf8,$ACCESS"
  [ -n "$EXTRA_OPTS" ] && OPTS="$OPTS,$EXTRA_OPTS"

  echo ""
  echo "=== Configuring $SHARE_NAME ($ACCESS) ==="

  # Create mount point
  echo ">>> Creating mount point at $MOUNT_POINT..."
  sudo mkdir -p "$MOUNT_POINT"

  # Test mount
  echo ">>> Test-mounting //$NAS_IP/$SHARE_NAME..."
  sudo mount -t cifs "//$NAS_IP/$SHARE_NAME" "$MOUNT_POINT" -o "$OPTS"

  echo ">>> Contents of $MOUNT_POINT:"
  ls "$MOUNT_POINT"

  # Unmount so systemd automount can manage it
  sudo umount "$MOUNT_POINT"

  # Add/replace fstab entry
  FSTAB_LINE="//$NAS_IP/$SHARE_NAME  $MOUNT_POINT  cifs  $OPTS,_netdev,noauto,x-systemd.automount,x-systemd.after=network-online.target,x-systemd.mount-timeout=30  0  0"

  if grep -qF "$SHARE_NAME" /etc/fstab; then
    echo ">>> Replacing existing fstab entry for $SHARE_NAME..."
    sudo sed -i "\|$SHARE_NAME|c\\$FSTAB_LINE" /etc/fstab
  else
    echo ">>> Adding fstab entry for $SHARE_NAME..."
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab > /dev/null
  fi
done

# Step 5: Reload systemd and start the automount units
echo ""
echo ">>> Reloading systemd daemon..."
sudo systemctl daemon-reload

echo ">>> Starting automount units..."
for ENTRY in "${SHARES[@]}"; do
  IFS=':' read -r _ MOUNT_POINT _ <<< "$ENTRY"
  # Convert /mnt/nas/Foo to mnt-nas-Foo.automount
  UNIT_NAME=$(systemd-escape --path "$MOUNT_POINT").automount
  sudo systemctl start "$UNIT_NAME"
  echo "  Started $UNIT_NAME"
done

echo ""
echo "=== Done! ==="
for ENTRY in "${SHARES[@]}"; do
  IFS=':' read -r SHARE_NAME MOUNT_POINT ACCESS _ <<< "$ENTRY"
  echo "  $SHARE_NAME ($ACCESS) -> $MOUNT_POINT"
done
echo ""
echo "Shares will auto-mount on first access after boot."
echo "Test with: ls /mnt/nas/Novonesis && ls /mnt/nas/caranguejo_vault"
