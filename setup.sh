#!/user/bin/env bash
set -e

export MAKEFLAGS="-j$(nproc)"
export GIT_TERMINAL_PROMPT=0
export PIP_BREAK_SYSTEM_PACKAGES=1

echo "=== Installing base packages ==="

pacman -S --needed --noconfirm --ask=4 \
git \
base-devel \
sudo \
python \
python-pip


echo "=== Creating RAM flush service ==="

cat > /etc/systemd/system/clear-ram.service <<EOF
[Unit]
Description=Flush RAM

[Service]
Type=oneshot
ExecStart=/bin/sh -c "sync && echo 3 > /proc/sys/vm/drop_caches"
EOF


cat > /etc/systemd/system/clear-ram.timer <<EOF
[Unit]
Description=Every 2 Hour RAM Flush

[Timer]
OnCalendar=*-*-* 0/2:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF


systemctl daemon-reload
systemctl enable --now clear-ram.timer


echo "=== Installing zram ==="

pacman -S --needed --noconfirm --ask=4 zram-generator


cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = 16384
compression-algorithm = zstd
EOF


systemctl daemon-reload
systemctl restart systemd-zram-setup@zram0.service

zramctl


echo "=== Installing MacTahoe themes ==="

cd /tmp


rm -rf MacTahoe-icon-theme

git clone https://github.com/vinceliuice/MacTahoe-icon-theme

cd MacTahoe-icon-theme

yes | ./install.sh

cd ..


rm -rf MacTahoe-kde

git clone https://github.com/vinceliuice/MacTahoe-kde

cd MacTahoe-kde

yes | ./install.sh

cd ..


echo "=== Installing undervolt ==="

python3 -m pip install --break-system-packages undervolt


UNDERVOLT="$(command -v undervolt)"


cat > /etc/systemd/system/undervolt.service <<EOF
[Unit]
Description=Apply undervolt settings at boot
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
systemctl enable --now undervolt.service

echo "=== Removing PulseAudio ==="

pacman -Rdd --noconfirm pulseaudio pulseaudio-bluetooth || true


echo "=== Installing PipeWire audio stack ==="

pacman -S --needed --noconfirm --ask=4 \
bluedevil \
plasma-pa \
pipewire \
pipewire-pulse \
wireplumber


systemctl enable --now bluetooth


echo "=== Restarting PipeWire ==="

REAL_USER=$(logname 2>/dev/null || true)

if [ -n "$REAL_USER" ]; then

    USER_ID=$(id -u "$REAL_USER")

    sudo -u "$REAL_USER" \
    XDG_RUNTIME_DIR=/run/user/$USER_ID \
    systemctl --user restart pipewire wireplumber pipewire-pulse || true

fi


echo "=== Updating GRUB ==="

pacman -S --needed --noconfirm --ask=4 \
grub \
os-prober


sed -i \
"s/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/" \
/etc/default/grub


mkdir -p /boot/grub


yes | grub-install \
--target=x86_64-efi \
--efi-directory=/efi \
--bootloader-id=ArchGRUB \
--recheck


grub-mkconfig -o /boot/grub/grub.cfg


echo "=== Adding Arch ISO boot entry ==="


if ! grep -q "Arch Linux Installer ISO" /etc/grub.d/40_custom; then

cat >> /etc/grub.d/40_custom <<'EOF'

menuentry "Arch Linux Installer ISO" {
    set iso_path="/archlinux-x86_64.iso"
    loopback loop (hd0,gpt6)$iso_path
    linux (loop)/arch/boot/x86_64/vmlinuz-linux img_dev=/dev/nvme0n1p6 img_loop=$iso_path
    initrd (loop)/arch/boot/x86_64/initramfs-linux.img
}

EOF

fi


chmod +x /etc/grub.d/40_custom


grub-mkconfig -o /boot/grub/grub.cfg

echo "=== Installing yay and AUR packages ==="


REAL_USER=$(logname 2>/dev/null || true)


if [ -z "$REAL_USER" ]; then
    echo "ERROR: Could not detect logged in user"
    exit 1
fi


sudo -u "$REAL_USER" bash <<EOF

cd /tmp

rm -rf yay

git clone https://aur.archlinux.org/yay.git

cd yay

makepkg -si --noconfirm --needed

yay -S --noconfirm --needed \
brave-bin \
stremio

EOF


echo "=== Cleaning temporary files ==="

rm -rf /tmp/yay


echo "=== Final system update ==="

pacman -Syu --noconfirm --ask=4


echo "=== Setup complete ==="

echo ""
echo "====================================="
echo " Finished!"
echo " Reboot recommended."
echo "====================================="
