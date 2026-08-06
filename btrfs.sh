#!/usr/bin/env bash
set -euo pipefail

echo "==> Optimizing BTRFS fstab mount flags for NVMe..."
# Replaces default mount flags with optimized flags:
# - noatime: eliminates unneeded writes when reading files
# - compress=zstd:3: provides optimal compression and speed balance
# - discard=async: groups trim commands to maximize NVMe performance
# - space_cache=v2: standard performance cache for modern drives
sed -i 's/defaults/noatime,compress=zstd:3,discard=async,space_cache=v2/g' /etc/fstab

echo "==> Installing system snapshot and rollback utilities..."
pacman -S --needed --noconfirm snapper snap-pac grub-btrfs btrfs-assistant

echo "==> Configuring Snapper for the root (/) partition..."
# Unmount and delete default placeholder if it exists
if [ -d /.snapshots ]; then
    umount /.snapshots 2>/dev/null || true
    rmdir /.snapshots 2>/dev/null || true
fi

# Create a fresh snapper config for root
snapper -c root create-config /

# Delete the subvolume snapper blindly created so we can link it correctly
btrfs subvolume delete /.snapshots || rmdir /.snapshots

# Recreate directory and link it to the top-level @snapshots subvolume
mkdir /.snapshots
# Note: Ensure your fstab has a mapping for your snapshots subvolume here if doing a manual layout.
# If you used 'archinstall', it maps subvolumes automatically.

echo "==> Tuning snapshot retention timeline (preventing disk bloat)..."
sed -i 's/TIMELINE_LIMIT_HOURLY="10"/TIMELINE_LIMIT_HOURLY="4"/g' /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_DAILY="10"/TIMELINE_LIMIT_DAILY="3"/g' /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_WEEKLY="0"/TIMELINE_LIMIT_WEEKLY="1"/g' /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_MONTHLY="10"/TIMELINE_LIMIT_MONTHLY="0"/g' /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_YEARLY="10"/TIMELINE_LIMIT_YEARLY="0"/g' /etc/snapper/configs/root

echo "==> Enabling systemd maintenance and snapshot timers..."
systemctl daemon-reload
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer
systemctl enable --now grub-btrfs.path

echo "==> BTRFS NVMe optimization complete! Please reboot your system."
