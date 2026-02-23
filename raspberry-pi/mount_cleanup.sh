#!/bin/bash
# Removes all NAS mounts, fstab entries, credentials, and automount units.
# Safe to re-run.

MOUNT_POINTS=("/mnt/nas/Novonesis" "/mnt/nas/caranguejo_vault" "/mnt/nas/AgentVault")

echo ">>> Stopping automount units and unmounting..."
for MP in "${MOUNT_POINTS[@]}"; do
  UNIT=$(systemd-escape --path "$MP" 2>/dev/null) || UNIT=""
  [ -n "$UNIT" ] && sudo systemctl stop "${UNIT}.automount" 2>/dev/null || true
  sudo umount "$MP" 2>/dev/null || true
done

echo ">>> Removing fstab entries..."
sudo sed -i '/Novonesis/d; /caranguejo_vault/d; /AgentVault/d' /etc/fstab

echo ">>> Reloading systemd..."
sudo systemctl daemon-reload

echo ">>> Removing credentials file..."
sudo rm -f /etc/nas-credentials

echo ">>> Removing mount points..."
sudo rm -rf /mnt/nas

echo ""
echo "=== Cleanup done! ==="
echo "All NAS mounts have been removed."
