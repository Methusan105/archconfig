#!/usr/bin/env bash

# Fix curl | bash stdin problems
if [ ! -t 0 ] && [ -e /dev/tty ]; then
    exec </dev/tty
fi

set -Eeuo pipefail

trap 'echo ""; echo "ERROR on line $LINENO"; stty sane 2>/dev/null || true; exit 1' ERR

export MAKEFLAGS="-j$(nproc)"
export GIT_TERMINAL_PROMPT=0
export PIP_BREAK_SYSTEM_PACKAGES=1


echo "=== Installing base packages ==="

pacman -S --needed --noconfirm \
git \
base-devel \
sudo \
python \
python-pip \
flatpak


#################################################
# FLATHUB
#################################################

echo "=== Adding Flathub ==="

flatpak remote-add --if-not-exists flathub \
https://flathub.org/repo/flathub.flatpakrepo



#################################################
# RAM FLUSH
#################################################

echo "=== Creating RAM flush timer ==="


cat > /etc/systemd/system/clear-ram.service <<'EOF'
[Unit]
Description=Flush RAM cache

[Service]
Type=oneshot
ExecStart=/bin/sh -c "sync && echo 3 > /proc/sys/vm/drop_caches"
EOF


cat > /etc/systemd/system/clear-ram.timer <<'EOF'
[Unit]
Description=Every 30 Minute RAM Flush

[Timer]
OnCalendar=*:0/30
Persistent=true

[Install]
WantedBy=timers.target
EOF


systemctl daemon-reload
systemctl enable --now clear-ram.timer



#################################################
# ZRAM
#################################################

echo "=== Installing ZRAM ==="


pacman -S --needed --noconfirm zram-generator


cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = 16384
compression-algorithm = zstd
EOF


systemctl daemon-reload

modprobe zram || true

systemctl start systemd-zram-setup@zram0.service 2>/dev/null || true


zramctl || true



#################################################
# MACTAHOE THEME
#################################################

echo "=== Installing MacTahoe themes ==="


cd /tmp


rm -rf MacTahoe-icon-theme

git clone --depth=1 \
https://github.com/vinceliuice/MacTahoe-icon-theme


cd MacTahoe-icon-theme

./install.sh

stty sane


cd /tmp


rm -rf MacTahoe-kde

git clone --depth=1 \
https://github.com/vinceliuice/MacTahoe-kde


cd MacTahoe-kde

./install.sh

stty sane


cd /tmp



#################################################
# UNDERVOLT
#################################################

echo "=== Installing undervolt ==="


python3 -m pip install --break-system-packages undervolt


UNDERVOLT="$(command -v undervolt || true)"


if [ -n "$UNDERVOLT" ]; then


cat > /etc/systemd/system/undervolt.service <<EOF
[Unit]
Description=Apply undervolt settings
After=multi-user.target
ConditionPathExists=$UNDERVOLT

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$UNDERVOLT --turbo 1

[Install]
WantedBy=multi-user.target
EOF


systemctl daemon-reload
systemctl enable undervolt.service

systemctl start undervolt.service || true

fi



#################################################
# AUDIO
#################################################

echo "=== Removing PulseAudio ==="


pacman -Rns --noconfirm \
pulseaudio \
pulseaudio-bluetooth \
2>/dev/null || true



echo "=== Installing PipeWire ==="


pacman -S --needed --noconfirm \
bluedevil \
plasma-pa \
pipewire \
pipewire-pulse \
wireplumber \
bluez \
bluez-utils


systemctl enable --now bluetooth.service



echo "=== Restarting PipeWire ==="


REAL_USER=$(logname 2>/dev/null || true)


if [ -n "$REAL_USER" ]; then

    USER_ID=$(id -u "$REAL_USER")


    sudo -u "$REAL_USER" \
    XDG_RUNTIME_DIR=/run/user/$USER_ID \
    systemctl --user restart \
    pipewire \
    pipewire-pulse \
    wireplumber \
    || true

fi



#################################################
# GRUB
#################################################

echo "=== Installing GRUB ==="


pacman -S --needed --noconfirm \
grub \
os-prober


sed -i \
's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' \
/etc/default/grub



if mountpoint -q /efi; then

    EFI_DIR="/efi"

elif mountpoint -q /boot/efi; then

    EFI_DIR="/boot/efi"

else

    echo "ERROR: EFI partition not mounted"
    exit 1

fi



grub-install \
--target=x86_64-efi \
--efi-directory="$EFI_DIR" \
--bootloader-id=ArchGRUB \
--recheck


grub-mkconfig -o /boot/grub/grub.cfg



#################################################
# ARCH ISO GRUB ENTRY
#################################################

echo "=== Adding Arch ISO entry ==="


if ! grep -q "Arch Linux Installer ISO" /etc/grub.d/40_custom; then


cat >> /etc/grub.d/40_custom <<'EOF'

menuentry "Arch Linux Installer ISO" --id arch-installer {

    set iso_path="/archlinux-x86_64.iso"

    loopback loop (hd0,gpt6)$iso_path

    linux (loop)/arch/boot/x86_64/vmlinuz-linux img_dev=/dev/nvme0n1p6 img_loop=$iso_path

    initrd (loop)/arch/boot/x86_64/initramfs-linux.img

}

EOF

fi


chmod +x /etc/grub.d/40_custom


grub-mkconfig -o /boot/grub/grub.cfg



#################################################
# FLATPAK APPS
#################################################

echo "=== Installing Flatpak apps ==="


flatpak install --noninteractive flathub \
com.brave.Browser \
com.visualstudio.code \
com.stremio.Stremio



#################################################
# INTEL VIDEO DRIVERS
#################################################

echo "=== Installing Intel video acceleration ==="

# Remove legacy Intel Xorg driver (not needed on Wayland)
pacman -R --noconfirm xf86-video-intel 2>/dev/null || true

# Install modern Intel media drivers
pacman -S --needed --noconfirm \
intel-media-driver \
libva-utils \
intel-gpu-tools



#################################################
# STREMIO OPTIMIZATION
#################################################

echo "=== Optimizing Stremio for Wayland ==="

# Native Wayland socket access
flatpak override --system --socket=wayland com.stremio.Stremio

# Force Qt to use Wayland natively
flatpak override --system --env=QT_QPA_PLATFORM=wayland com.stremio.Stremio

# Force Electron/Ozone to use Wayland
flatpak override --system --env=ELECTRON_OZONE_PLATFORM_HINT=wayland com.stremio.Stremio

# Direct GPU device access for hardware acceleration
flatpak override --system --device=dri com.stremio.Stremio

# Force correct Intel iHD driver for Comet Lake
flatpak override --system --env=LIBVA_DRIVER_NAME=iHD com.stremio.Stremio

echo "=== Stremio optimization complete ==="
echo "Remember to enable 'Hardware-accelerated decoding' in Stremio settings"



#################################################
# CLEANUP
#################################################

echo "=== Cleaning ==="


rm -rf /tmp/MacTahoe-icon-theme
rm -rf /tmp/MacTahoe-kde


pacman -Sc --noconfirm || true

flatpak uninstall --unused -y || true



#################################################
# UPDATE
#################################################

echo "=== Updating system ==="


pacman -Syu --noconfirm



stty sane


echo ""
echo "====================================="
echo " Setup complete"
echo ""
echo "Installed:"
echo "- Brave (Flatpak)"
echo "- VS Code (Flatpak)"
echo "- Stremio (Flatpak)"
echo "- PipeWire"
echo "- ZRAM 16GB"
echo "- RAM flush every 30 minutes"
echo "- Intel media drivers"
echo "- Stremio Wayland optimized"
echo ""
echo "No yay installed"
echo "No AUR packages used"
echo "Reboot recommended"
echo "====================================="
