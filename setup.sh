#!/usr/bin/env bash
set -Eeuo pipefail

#############################################
# Arch NUC10 KDE Optimization Setup
#############################################

if [ "$EUID" -ne 0 ]; then
    echo "Run with sudo"
    exit 1
fi


export MAKEFLAGS="-j$(nproc)"
export GIT_TERMINAL_PROMPT=0


REAL_USER="${SUDO_USER:-$(whoami)}"


#############################################
# CONFIG
#############################################

ISO_PATH="/archlinux-x86_64.iso"
ISO_DEVICE="/dev/nvme0n1p6"


WORKDIR="/tmp/archconfig"

mkdir -p "$WORKDIR"


#############################################
# PACKAGES
#############################################

echo "== Installing packages =="

pacman -S --needed --noconfirm \
git \
base-devel \
python \
python-pip \
reflector \
thermald \
power-profiles-daemon \
systemd-zram-generator \
pipewire \
pipewire-pulse \
wireplumber \
bluedevil \
plasma-pa \
mesa \
intel-media-driver \
intel-ucode \
fastfetch \
btop \
eza \
bat \
fd \
ripgrep \
fzf \
zoxide \
ark \
gwenview \
spectacle \
filelight \
partitionmanager \
plasma-systemmonitor \
grub \
os-prober


#############################################
# PACMAN
#############################################

echo "== Optimizing pacman =="

sed -i 's/^#Color/Color/' /etc/pacman.conf

grep -q "ILoveCandy" /etc/pacman.conf || \
sed -i '/Color/a ILoveCandy' /etc/pacman.conf

sed -i \
's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' \
/etc/pacman.conf


#############################################
# MIRRORS
#############################################

echo "== Updating mirrors =="

reflector \
--country Norway,Sweden,Denmark,Finland \
--latest 20 \
--protocol https \
--sort rate \
--save /etc/pacman.d/mirrorlist


systemctl enable reflector.timer


#############################################
# ZRAM
#############################################

echo "== Configuring ZRAM =="

cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = 8192
compression-algorithm = zstd
swap-priority = 100
EOF


systemctl daemon-reload


#############################################
# SERVICES
#############################################

echo "== Enabling services =="

systemctl enable --now \
bluetooth \
fstrim.timer \
thermald \
power-profiles-daemon \
systemd-resolved


#############################################
# INTEL GRAPHICS
#############################################

echo "== Intel graphics =="

cat > /etc/environment <<EOF
LIBVA_DRIVER_NAME=iHD
EOF


if grep -q "^MODULES=" /etc/mkinitcpio.conf; then

    sed -i \
    's/^MODULES=.*/MODULES=(i915)/' \
    /etc/mkinitcpio.conf

else

    echo "MODULES=(i915)" >> /etc/mkinitcpio.conf

fi


mkinitcpio -P


#############################################
# MEMORY TUNING
#############################################

echo "== Kernel tuning =="

cat > /etc/sysctl.d/99-performance.conf <<EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5
EOF


sysctl --system


#############################################
# UNDERVOLT
#############################################

echo "== Installing undervolt =="

python3 -m pip install --break-system-packages undervolt || true


UNDERVOLT_BIN="$(command -v undervolt || true)"


if [ -n "$UNDERVOLT_BIN" ]; then

cat > /etc/systemd/system/undervolt.service <<EOF
[Unit]
Description=Intel undervolt
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$UNDERVOLT_BIN --turbo 1

[Install]
WantedBy=multi-user.target
EOF


systemctl daemon-reload
systemctl enable undervolt.service

fi


#############################################
# GRUB WINDOWS + ISO
#############################################

echo "== Configuring GRUB =="


sed -i \
's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' \
/etc/default/grub


sed -i \
's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' \
/etc/default/grub


grub-install \
--target=x86_64-efi \
--efi-directory=/efi \
--bootloader-id=ArchGRUB \
--recheck



#############################################
# ARCH ISO ENTRY
#############################################

if ! grep -q "Arch Linux Installer ISO" /etc/grub.d/40_custom; then

cat >> /etc/grub.d/40_custom <<EOF

menuentry "Arch Linux Installer ISO" {
    set iso_path="$ISO_PATH"
    loopback loop ($ISO_DEVICE)\$iso_path
    linux (loop)/arch/boot/x86_64/vmlinuz-linux img_dev=$ISO_DEVICE img_loop=\$iso_path
    initrd (loop)/arch/boot/x86_64/initramfs-linux.img
}

EOF

fi


chmod +x /etc/grub.d/40_custom


grub-mkconfig -o /boot/grub/grub.cfg


#############################################
# MAC TAHOE
#############################################

echo "== Installing MacTahoe =="

cd "$WORKDIR"


rm -rf MacTahoe-icon-theme

git clone https://github.com/vinceliuice/MacTahoe-icon-theme

cd MacTahoe-icon-theme

./install.sh



cd "$WORKDIR"


rm -rf MacTahoe-kde

git clone https://github.com/vinceliuice/MacTahoe-kde

cd MacTahoe-kde

./install.sh



#############################################
# YAY + AUR
#############################################

echo "== Installing yay =="


sudo -u "$REAL_USER" bash <<EOF

cd $WORKDIR

rm -rf yay

git clone https://aur.archlinux.org/yay.git

cd yay

makepkg -si --noconfirm --needed


yay -S --noconfirm --needed \
brave-bin \
visual-studio-code-bin


flatpak install -y flathub com.stremio.Stremio

EOF



#############################################
# CLEANUP
#############################################

echo "== Cleaning =="

rm -rf "$WORKDIR"



#############################################
# UPDATE
#############################################

echo "== Final update =="

pacman -Syu --noconfirm



#############################################
# CHECKS
#############################################

echo ""

if uname -r | grep -q zen; then
    echo "Kernel: linux-zen active"
else
    echo "WARNING: linux-zen is not active"
fi


echo ""
echo "======================================"
echo " Setup completed"
echo ""
echo " Intel NUC10 profile applied"
echo " ZRAM: 8GB zstd"
echo " PipeWire enabled"
echo " Intel VAAPI enabled"
echo " Undervolt enabled if supported"
echo " Windows GRUB detection enabled"
echo " Arch ISO GRUB entry enabled"
echo " GRUB timeout: 5 seconds"
echo ""
echo "Reboot recommended"
echo "======================================"
