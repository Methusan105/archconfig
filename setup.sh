#!/bin/bash
set -e

export MAKEFLAGS="-j$(nproc)"
export GIT_TERMINAL_PROMPT=0
export PIP_BREAK_SYSTEM_PACKAGES=1
export DEBIAN_FRONTEND=noninteractive

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


echo "=== Installing base packages ==="

pacman -S --needed --noconfirm \
git \
base-devel \
sudo \
python \
python-pip


echo "=== Installing zram ==="

pacman -S --needed --noconfirm zram-generator


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

yes | python3 -m pip install --break-system-packages undervolt


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


echo "=== Restarting PipeWire ==="

if [ -n "$SUDO_USER" ]; then

USER_ID=$(id -u "$SUDO_USER")

sudo -u "$SUDO_USER" \
XDG_RUNTIME_DIR=/run/user/$USER_ID \
systemctl --user restart pipewire wireplumber pipewire-pulse

fi
