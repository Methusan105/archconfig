#!/usr/bin/env bash

set -Eeuo pipefail

trap 'echo ""; echo "ERROR on line $LINENO"; stty sane 2>/dev/null || true; exit 1' ERR

export MAKEFLAGS="-j$(nproc)"
export GIT_TERMINAL_PROMPT=0
export PIP_BREAK_SYSTEM_PACKAGES=1


#################################################
# BASE PACKAGES
#################################################

echo "=== Installing base packages ==="

pacman -S --needed --noconfirm \
git \
base-devel \
sudo \
python \
python-pip \
flatpak



#################################################
# USER DETECTION
#################################################

REAL_USER="${SUDO_USER:-$(logname)}"
USER_HOME=$(eval echo "~$REAL_USER")

echo "Running user installs as: $REAL_USER"



#################################################
# YAY
#################################################

echo "=== Installing yay ==="

cd /tmp

rm -rf yay

git clone https://aur.archlinux.org/yay.git

chown -R "$REAL_USER":"$REAL_USER" /tmp/yay


sudo -u "$REAL_USER" bash -c '
cd /tmp/yay
makepkg -si --noconfirm
'


cd /tmp
rm -rf yay



#################################################
# MYSTIQ
#################################################

echo "=== Installing MystiQ ==="

sudo -u "$REAL_USER" yay -S --noconfirm brave-bin warp-cli spotify



#################################################
# SPOTIFY + SPOTX
#################################################
echo "Waiting for Spotify installation..."


for i in {1..300}; do

    if find "$USER_HOME/.local/share/spotify-launcher" \
        -name spotify \
        -type f \
        -executable 2>/dev/null | grep -q .; then

        echo "Spotify installed."
        break

    fi

    sleep 1

done



if ! find "$USER_HOME/.local/share/spotify-launcher" \
    -name spotify \
    -type f \
    -executable 2>/dev/null | grep -q .; then

    echo "ERROR: Spotify installation timed out"
    exit 1

fi



echo "=== Installing SpotX ==="


sudo -u "$REAL_USER" bash -c \
"bash <(curl -sSL https://spotx-official.github.io/run.sh)"

#################################################
# FLATHUB
#################################################

echo "=== Adding Flathub ==="

flatpak remote-add --if-not-exists flathub \
https://flathub.org



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


# Replace this with the real MacTahoe icon repository
git clone --depth=1 \
https://github.com/vinceliuice/MacTahoe-icon-theme.git \
MacTahoe-icon-theme


cd MacTahoe-icon-theme

./install.sh || true

stty sane 2>/dev/null || true


cd /tmp


rm -rf MacTahoe-kde


# Replace this with the real MacTahoe KDE repository
git clone --depth=1 \
https://github.com/vinceliuice/MacTahoe-kde.git \
MacTahoe-kde


cd MacTahoe-kde

./install.sh || true

stty sane 2>/dev/null || true


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
# GRUB S3 DEEP SLEEP FIX
#################################################

echo "=== Configuring GRUB Deep Sleep ==="


if [ -f /etc/default/grub ]; then

    sed -i \
    's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="systemd.show_status=true mem_sleep_default=deep acpi_osi=Linux pcie_aspm=off ignore_loglevel systemd.log_level=debug systemd.log_target=kmsg log_buf_len=16M devkmsg=on"|' \
    /etc/default/grub

else

    echo "ERROR: /etc/default/grub not found"
    exit 1

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
    loopback loop (hd0,gpt7)$iso_path
    linux (loop)/arch/boot/x86_64/vmlinuz-linux img_dev=/dev/nvme0n1p7 img_loop=$iso_path
    initrd (loop)/arch/boot/x86_64/initramfs-linux.img
}


menuentry "Windows Installer" {
    insmod part_gpt
    insmod fat
    search --no-floppy --fs-uuid --set=root 02D4-2D14
    chainloader /efi/boot/bootx64.efi
}

EOF

fi


chmod +x /etc/grub.d/40_custom


grub-mkconfig -o /boot/grub/grub.cfg


#################################################
# INTEL VIDEO DRIVERS
#################################################

echo "=== Installing Intel video acceleration ==="


# Remove legacy Intel Xorg driver
pacman -R --noconfirm xf86-video-intel 2>/dev/null || true


pacman -S --needed --noconfirm \
intel-media-driver \
libva-utils \
intel-gpu-tools

#################################################
# STREMIO ARCH PACKAGE
#################################################

echo "=== Installing Stremio Arch package ==="

cd /tmp

rm -rf Stremio.Arch.Linux Stremio.Arch.Linux.zip

curl -L \
"https://github.com/Methusan105/archconfig/releases/download/SALP/Stremio.Arch.Linux.zip" \
-o Stremio.Arch.Linux.zip


unzip -q Stremio.Arch.Linux.zip \
-d Stremio.Arch.Linux


cd Stremio.Arch.Linux


echo "=== Installing Stremio packages ==="

pacman -U --noconfirm *.pkg.tar.zst


cd /tmp

rm -rf Stremio.Arch.Linux Stremio.Arch.Linux.zip


echo "=== Stremio Arch package installed ==="

#################################################
# JDOWNLOADER
#################################################

echo "=== Installing JDownloader ==="

cd /tmp

curl -L \
"https://github.com/Methusan105/archconfig/releases/download/jd/JDownloader2Setup_unix_nojre.sh" \
-o JDownloader2Setup_unix_nojre.sh

chmod +x JDownloader2Setup_unix_nojre.sh

sudo -u "$REAL_USER" ./JDownloader2Setup_unix_nojre.sh

#################################################
# BASHRC ALIASES
#################################################

echo "=== Adding Windows shortcuts to .bashrc ==="



add_aliases() {

    local target_rc="$1"


    if [ -f "$target_rc" ]; then


        if ! grep -q "# Windows shortcuts" "$target_rc"; then


cat >> "$target_rc" <<'EOF'

# Windows shortcuts
alias bootwin="sudo grub-reboot osprober-efi-BCD7-916D && reboot"
alias cleaninstall="sudo grub-reboot arch-installer && reboot"
alias mountwin="sudo mkdir -p /run/media/methu/Windows && sudo ntfs-3g /dev/nvme0n1p3 /run/media/methu/Windows"

EOF


        fi

    fi

}



# Root aliases
add_aliases "/root/.bashrc"



# User aliases
if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then


    USER_HOME=$(eval echo "~$REAL_USER")


    add_aliases "$USER_HOME/.bashrc"


    chown "$REAL_USER":"$REAL_USER" \
    "$USER_HOME/.bashrc" || true

fi



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



stty sane 2>/dev/null || true



#################################################
# COMPLETE
#################################################

echo ""
echo "====================================="
echo " Setup complete"
echo "====================================="
echo ""
echo "Installed:"
echo "- Brave (Flatpak)"
echo "- Stremio (Flatpak)"
echo "- Spotify Launcher (Arch)"
echo "- SpotX patch applied"
echo "- yay (AUR helper)"
echo "- MystiQ (AUR)"
echo "- PipeWire + WirePlumber"
echo "- ZRAM 16GB (zstd)"
echo "- RAM flush every 30 minutes"
echo "- Intel media drivers"
echo "- Stremio Arch Package"
echo "- GRUB deep sleep fix"
echo "- Windows shortcuts added"
echo ""
echo "AUR support enabled"
echo "System updated"
echo ""
echo "Reboot recommended"
echo "====================================="
