#!/usr/bin/env bash

set -Eeuo pipefail

trap '
    echo ""
    echo "====================================="
    echo "ERROR on line $LINENO"
    echo "====================================="
    stty sane 2>/dev/null || true
    exit 1
' ERR

export MAKEFLAGS="-j$(nproc)"
export GIT_TERMINAL_PROMPT=0
export PIP_BREAK_SYSTEM_PACKAGES=1

#################################################
# SCRIPT LOCATION
#################################################

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

#################################################
# ROOT / USER SETUP
#################################################

if [[ $EUID -ne 0 ]]; then
    echo "=== Root privileges required ==="
    echo "Requesting sudo..."
    echo ""

    exec sudo -E bash "$SCRIPT_DIR/setup.sh" "$@"
fi

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$(logname 2>/dev/null || true)"

    if [[ -z "$REAL_USER" || "$REAL_USER" == "root" ]]; then
        REAL_USER="$(id -un 2>/dev/null || true)"
    fi
fi

if [[ -z "$REAL_USER" || "$REAL_USER" == "root" ]]; then
    echo "ERROR: Could not determine the normal user."
    echo "Run this script from your normal user account."
    exit 1
fi

if ! id "$REAL_USER" >/dev/null 2>&1; then
    echo "ERROR: User '$REAL_USER' does not exist."
    exit 1
fi

USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
    echo "ERROR: Could not determine home directory for $REAL_USER"
    exit 1
fi

USER_ID="$(id -u "$REAL_USER")"
USER_RUNTIME="/run/user/$USER_ID"

echo "====================================="
echo " Methu Arch Linux GNOME Setup"
echo "====================================="
echo ""
echo "Script:  $SCRIPT_DIR"
echo "User:    $REAL_USER"
echo "Home:    $USER_HOME"
echo ""

#################################################
# CHECK ARCH LINUX
#################################################

if [[ ! -f /etc/arch-release ]]; then
    echo "ERROR: This script is intended for Arch Linux."
    exit 1
fi

#################################################
# CHECK GNOME
#################################################

echo "=== Checking GNOME ==="

if pacman -Q gnome-shell >/dev/null 2>&1; then
    echo "GNOME is installed."
else
    echo "WARNING: GNOME Shell is not currently installed."
    echo ""
    echo "This script is GNOME-compatible, but it does not install the"
    echo "full GNOME desktop automatically."
    echo ""
fi

#################################################
# BASE PACKAGES
#################################################

echo "=== Installing base packages ==="

pacman -Syu --needed --noconfirm \
    git \
    base-devel \
    sudo \
    curl \
    wget \
    python \
    python-pip \
    flatpak \
    pavucontrol \
    ntfs-3g \
    cpupower

#################################################
# METHUREPOS
#################################################

echo "=== Configuring MethuRepo ==="

sed -i \
    '/^[[:space:]]*\[methurepos\][[:space:]]*$/,/^[[:space:]]*Server[[:space:]]*=/d' \
    /etc/pacman.conf

if ! grep -q '^\[methurepos\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf <<'EOF'

[methurepos]
SigLevel = Optional
Server = https://github.com/methusan105/archconfig/releases/download/mr
EOF
fi

echo "=== Refreshing package databases ==="

pacman -Sy --noconfirm

echo "=== Installing MethuRepo packages ==="

pacman -S --needed --noconfirm \
    process-lasso-linux \
    archconfig-cli \
    ffmpeg-gui-ver-methu \
    github-release-downloader \
    github-release-uploader \
    qemu-iso-disk-launcher \
    stremio \
    vscodium-bin \
    yay

#################################################
# AUR PACKAGES
#################################################

echo "=== Installing AUR packages ==="

sudo -u "$REAL_USER" yay -S --needed --noconfirm \
    brave-origin-bin \
    warp-cli \
    galaxybudsclient-bin \
    preload

#################################################
# PRELOAD
#################################################

echo "=== Enabling Preload ==="

systemctl enable --now preload.service

#################################################
# IRQBALANCE
#################################################

echo "=== Installing and enabling irqbalance ==="

pacman -S --needed --noconfirm irqbalance

systemctl enable --now irqbalance.service

#################################################
# SPOTX
#################################################

echo "=== Installing SpotX ==="

sudo -u "$REAL_USER" bash -c \
    'bash <(curl -fsSL https://github.io)'

#################################################
# FLATHUB
#################################################

echo "=== Adding Flathub ==="

flatpak remote-add --if-not-exists \
    flathub \
    https://flathub.org

#################################################
# RAM FLUSH
#################################################

echo "=== Creating RAM flush service ==="

cat > /etc/systemd/system/clear-ram.service <<'EOF'
[Unit]
Description=Flush RAM cache

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
EOF

cat > /etc/systemd/system/clear-ram.timer <<'EOF'
[Unit]
Description=Flush RAM cache every 30 minutes

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

echo "=== Configuring 16GB ZRAM ==="

pacman -S --needed --noconfirm zram-generator

cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = 16384
compression-algorithm = zstd
EOF

systemctl daemon-reload

modprobe zram || true

systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true

echo ""
echo "=== ZRAM status ==="
zramctl || true
echo ""

#################################################
# UNDERVOLT
#################################################

echo "=== Installing undervolt ==="

python3 -m pip install --break-system-packages undervolt

UNDERVOLT="$(command -v undervolt || true)"

if [[ -n "$UNDERVOLT" ]]; then
    echo "undervolt found at: $UNDERVOLT"

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
else
    echo "WARNING: undervolt command was not found."
fi

#################################################
# AUDIO / BLUETOOTH
#################################################

echo "=== Configuring PipeWire + Bluetooth for GNOME ==="

pacman -Rns --noconfirm \
    pulseaudio \
    pulseaudio-bluetooth \
    2>/dev/null || true

pacman -S --needed --noconfirm \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    bluez \
    bluez-utils \
    pavucontrol

systemctl enable --now bluetooth.service

#################################################
# WIREPLUMBER BLUETOOTH CODECS
#################################################

echo "=== Configuring WirePlumber Bluetooth codecs ==="

WIREPLUMBER_DIR="$USER_HOME/.config/wireplumber/wireplumber.conf.d"

mkdir -p "$WIREPLUMBER_DIR"

cat > "$WIREPLUMBER_DIR/50-bluetooth.conf" <<'EOF'
monitor.bluez.properties = {
    bluez5.a2dp.codecs = [ sbc_xq sbc aac ]
}
EOF

chown -R "$REAL_USER:$REAL_USER" \
    "$USER_HOME/.config/wireplumber"

#################################################
# GNOME USER AUDIO SERVICES
#################################################

echo "=== Restarting user PipeWire services ==="

if [[ -d "$USER_RUNTIME" ]]; then
    sudo -u "$REAL_USER" \
        XDG_RUNTIME_DIR="$USER_RUNTIME" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RUNTIME/bus" \
        systemctl --user daemon-reload \
        2>/dev/null || true

    sudo -u "$REAL_USER" \
        XDG_RUNTIME_DIR="$USER_RUNTIME" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RUNTIME/bus" \
        systemctl --user restart pipewire \
        pipewire-pulse \
        wireplumber \
        2>/dev/null || true
else
    echo "WARNING: User runtime directory does not exist."
fi

#################################################
# INTEL VIDEO
#################################################

echo "=== Installing Intel video acceleration ==="

pacman -R --noconfirm \
    xf86-video-intel \
    2>/dev/null || true

pacman -S --needed --noconfirm \
    intel-media-driver \
    libva-utils \
    intel-gpu-tools

#################################################
# GRUB DEEP SLEEP FIX & CONFIG
#################################################

echo "=== Configuring GRUB ==="

if [[ ! -f /etc/default/grub ]]; then
    echo "ERROR: /etc/default/grub not found."
    exit 1
fi

GRUB_CMDLINE="systemd.show_status=true mem_sleep_default=deep acpi_osi=Linux pcie_aspm=off ignore_loglevel systemd.log_level=debug systemd.log_target=kmsg log_buf_len=16M devkmsg=on"

if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_CMDLINE\"|" /etc/default/grub
else
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_CMDLINE\"" >> /etc/default/grub
fi

echo "=== Installing GRUB + os-prober ==="
pacman -S --needed --noconfirm grub os-prober

echo "=== Enabling os-prober ==="
if grep -q '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
    sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
else
    echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
fi

echo "=== Detecting EFI partition ==="
if mountpoint -q /efi; then
    EFI_DIR="/efi"
elif mountpoint -q /boot/efi; then
    EFI_DIR="/boot/efi"
else
    echo "ERROR: EFI partition is not mounted."
    exit 1
fi

echo "=== Installing GRUB ==="
grub-install \
    --target=x86_64-efi \
    --efi-directory="$EFI_DIR" \
    --bootloader-id=ArchGRUB \
    --recheck

#################################################
# ARCH ISO + WINDOWS INSTALLER CUSTOM GRUB
#################################################

echo "=== Configuring custom GRUB entries ==="
CUSTOM_FILE="/etc/grub.d/40_custom"
touch "$CUSTOM_FILE"

sed -i '/menuentry "Arch Linux Installer ISO"/,/^}/d' "$CUSTOM_FILE"
sed -i '/menuentry "Windows Installer"/,/^}/d' "$CUSTOM_FILE"

cat >> "$CUSTOM_FILE" <<'EOF'
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
chmod +x "$CUSTOM_FILE"

echo "=== Generating GRUB configuration ==="
grub-mkconfig -o /boot/grub/grub.cfg

#################################################
# BASHRC ALIASES
#################################################

echo "=== Configuring bash aliases ==="
add_aliases() {
    local target_rc="$1"
    touch "$target_rc"
    if ! grep -q '# Methu Windows shortcuts' "$target_rc"; then
        cat >> "$target_rc" <<'EOF'

# If not running interactively, don't do anything
[[ $- != i ]] && return

if command -v fastfetch >/dev/null 2>&1; then
    fastfetch
fi

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# Methu Windows shortcuts
alias bootwin='sudo grub-reboot "$(grep -i "menuentry.*Windows Boot Manager" /boot/grub/grub.cfg | sed -n "s/.*menuentry '\''\([^'\'']*\)'/'\''/\1/p" | head -n1)" && sudo reboot'
alias cleaninstall='sudo grub-reboot arch-installer && reboot'
alias mountwin='sudo mkdir -p /run/media/methu/Windows && sudo ntfs-3g /dev/nvme0n1p3 /run/media/methu/Windows'
alias enable_warp-svc='sudo systemctl unmask warp-svc && sudo systemctl start warp-svc'
alias disable_warp-svc='sudo systemctl stop warp-svc && sudo systemctl mask warp-svc'
alias disablecores='for cpu in {4..7}; do echo 0 | sudo tee /sys/devices/system/cpu/cpu$cpu/online >/dev/null; done'
alias enablecores='for cpu in {4..7}; do echo 1 | sudo tee /sys/devices/system/cpu/cpu$cpu/online >/dev/null; done'
alias cpu-cool='sudo cpupower frequency-set -u 800MHz'
alias cpu-normal='sudo cpupower frequency-set -u 1600MHz'
alias fixefi='read -rp "Enter partition (e.g. nvme0n1p1 or /dev/nvme0n1p1): " dev && dev="/dev/${dev#/dev/}" && if [ -b "$dev" ]; then command -v fsck.fat >/dev/null 2>&1 || sudo pacman -S --needed dosfstools; sudo umount "$dev" 2>/dev/null; sudo fsck.fat -r -w "$dev" && sudo fsck.fat -v "$dev"; else echo "Error: Block device $dev not found."; fi'
EOF
    fi
}

add_aliases "/root/.bashrc"
add_aliases "$USER_HOME/.bashrc"
chown "$REAL_USER:$REAL_USER" "$USER_HOME/.bashrc"

#################################################
# GNOME / USER DIRECTORIES
#################################################

echo "=== Configuring GNOME-friendly user directories ==="
sudo -u "$REAL_USER" mkdir -p "$USER_HOME/.config" "$USER_HOME/.local/share"

#################################################
# APPLE SAN FRANCISCO FONTS SETUP
#################################################
echo "=== Installing Apple San Francisco Fonts ==="

FONT_DIR="/usr/share/fonts/apple-fonts"
mkdir -p "$FONT_DIR"

echo "Cloning and installing SF Pro..."
rm -rf /tmp/SF-Pro
git clone --depth=1 https://github.com/sahibjotsaggu/San-Francisco-Pro-Fonts /tmp/SF-Pro
cp -r /tmp/SF-Pro/*.otf /tmp/SF-Pro/*.ttf "$FONT_DIR/" 2>/dev/null || true
rm -rf /tmp/SF-Pro

echo "Cloning and installing SF Mono..."
rm -rf /tmp/SF-Mono
git clone --depth=1 https://github.com/shaunsingh/SFMono-Nerd-Font-Ligaturized /tmp/SF-Mono
cp -r /tmp/SF-Mono/*.otf "$FONT_DIR/" 2>/dev/null || true
rm -rf /tmp/SF-Mono

chmod 644 "$FONT_DIR"/*
fc-cache -f -v

if [[ -d "$USER_RUNTIME" ]]; then
    echo "Activating fonts and disabling animations for $REAL_USER..."
    
    sudo -u "$REAL_USER" \
        XDG_RUNTIME_DIR="$USER_RUNTIME" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RUNTIME/bus" \
        gsettings set org.gnome.desktop.interface enable-animations false

    sudo -u "$REAL_USER" \
        XDG_RUNTIME_DIR="$USER_RUNTIME" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RUNTIME/bus" \
        gsettings set org.gnome.desktop.interface font-name 'SF Pro Display Regular 11'

    sudo -u "$REAL_USER" \
        XDG_RUNTIME_DIR="$USER_RUNTIME" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RUNTIME/bus" \
        gsettings set org.gnome.desktop.interface document-font-name 'SF Pro Text Regular 11'

    sudo -u "$REAL_USER" \
        XDG_RUNTIME_DIR="$USER_RUNTIME" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RUNTIME/bus" \
        gsettings set org.gnome.desktop.interface monospace-font-name 'SF Mono Regular 11'
fi

#################################################
# MACTAHOE GTK THEME SETUP
#################################################
echo "=== Installing MacTahoe GTK Theme & Dependencies ==="

pacman -S --needed --noconfirm \
    sassc \
    imagemagick \
    dialog \
    optipng \
    inkscape

echo "Cloning and installing MacTahoe-gtk-theme..."
rm -rf /tmp/MacTahoe-gtk-theme
git clone https://github.com/vinceliuice/MacTahoe-gtk-theme.git --depth=1 /tmp/MacTahoe-gtk-theme

sudo -u "$REAL_USER" bash -c '
    cd /tmp/MacTahoe-gtk-theme
    ./install.sh -b -l
'

rm -rf /tmp/MacTahoe-gtk-theme

#################################################
# GNOME DEBLOAT
#################################################

echo "=== Removing unwanted GNOME applications ==="

DEBLOAT_LIST=(
    epiphany
    gnome-weather
    simple-scan
    snapshot
    loupe
    papers
    gnome-calculator
    yelp
    malcontent
    orca
    rygel
    gnome-connections
)

TO_REMOVE=()
for pkg in "${DEBLOAT_LIST[@]}"; do
    if pacman -Qq "$pkg" >/dev/null 2>&1; then
        TO_REMOVE+=("$pkg")
    fi
done

if [ ${#TO_REMOVE[@]} -gt 0 ]; then
    echo "Removing: ${TO_REMOVE[*]}"
    pacman -Rsn --noconfirm "${TO_REMOVE[@]}"
fi

if [ -n "$(pacman -Qdtq)" ]; then
    echo "Cleaning up orphaned dependencies..."
    pacman -Rns --noconfirm $(pacman -Qdtq)
fi

#################################################
# CLEANUP
#################################################

echo "=== Cleaning temporary files ==="
pacman -Sc --noconfirm || true
flatpak uninstall --unused -y || true

#################################################
# FINAL SYSTEM UPDATE
#################################################

echo "=== Final system update ==="
pacman -Syu --noconfirm

#################################################
# FINISH
#################################################

stty sane 2>/dev/null || true
echo ""
echo "====================================="
echo "       METHU GNOME SETUP COMPLETE"
echo "====================================="
echo ""
echo "A reboot is recommended."
echo ""
echo "====================================="
