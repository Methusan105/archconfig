#!/bin/bash
set -e

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

pacman -S --noconfirm zram-generator

cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = 16384
compression-algorithm = zstd
EOF

systemctl daemon-reload
systemctl start systemd-zram-setup@zram0.service

zramctl


echo "=== Installing MacTahoe themes ==="

pacman -S --needed --noconfirm git

git clone https://github.com/vinceliuice/MacTahoe-icon-theme
cd MacTahoe-icon-theme
./install.sh
cd ..

git clone https://github.com/vinceliuice/MacTahoe-kde
cd MacTahoe-kde
./install.sh
cd ..


echo "=== Installing undervolt ==="

pacman -S --needed --noconfirm python python-pip

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


echo "=== Installing Bluetooth and audio packages ==="

pacman -S --needed --noconfirm \
bluedevil \
plasma-pa \
pipewire-pulse \
wireplumber

systemctl enable --now bluetooth

systemctl --user restart pipewire wireplumber pipewire-pulse


echo "=== Updating GRUB ==="

pacman -S --needed --noconfirm grub os-prober

sed -i "s/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/" /etc/default/grub

mkdir -p /boot/grub

grub-install \
--target=x86_64-efi \
--efi-directory=/efi \
--bootloader-id=ArchGRUB

grub-mkconfig -o /boot/grub/grub.cfg


echo "=== Adding Arch ISO boot entry ==="

cat >> /etc/grub.d/40_custom <<'EOF'

menuentry "Arch Linux Installer ISO" {
    set iso_path="/archlinux-x86_64.iso"
    loopback loop (hd0,gpt6)$iso_path
    linux (loop)/arch/boot/x86_64/vmlinuz-linux img_dev=/dev/nvme0n1p6 img_loop=$iso_path
    initrd (loop)/arch/boot/x86_64/initramfs-linux.img
}
EOF

chmod +x /etc/grub.d/40_custom

grub-mkconfig -o /boot/grub/grub.cfg

echo "=== Done ==="
