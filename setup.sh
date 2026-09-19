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
# DETECT CONTAINER ENVIRONMENT
#################################################

IS_CONTAINER=0
if systemd-detect-virt --container >/dev/null 2>&1 || [[ -f /.dockerenv ]]; then
    IS_CONTAINER=1
    echo "!!! CONTAINER ENVIRONMENT DETECTED !!!"
    echo "Systemd-services, GRUB, and kernel modules will be skipped."
    echo ""
fi

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

echo "====================================="
echo " Methu Arch Linux Setup (Hyprland)"
echo "====================================="
echo ""
echo "Script: $SCRIPT_DIR"
echo "User:   $REAL_USER"
echo "Home:   $USER_HOME"
echo ""

#################################################
# CHECK ARCH LINUX
#################################################

if [[ ! -f /etc/arch-release ]]; then
    echo "ERROR: This script is intended for Arch Linux."
    exit 1
fi

#################################################
# BASE PACKAGES
#################################################

echo "=== Installing base packages ==="

# Overwrite forhindrer at flatpak-filkonflikter krasjer skriptet i Distrobox
pacman -Syu --overwrite "*" --needed --noconfirm \
    git \
    base-devel \
    sudo \
    python \
    python-pip \
    flatpak

#################################################
# METHUREPOS
#################################################

echo "=== Configuring MethuRepo ==="

sed -i '/^[[:space:]]*\[methurepos\][[:space:]]*$/,/^[[:space:]]*Server[[:space:]]*=/d' \
    /etc/pacman.conf

if ! grep -q '^\[methurepos\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf <<'EOF'

[methurepos]
SigLevel = Optional
Server = https://github.com/Methusan105/archconfig/releases/download/mr
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
    vscodium-bin

#################################################
# YAY
#################################################

echo "=== Installing yay ==="

if ! command -v yay >/dev/null 2>&1; then

    rm -rf /tmp/yay

    git clone --depth=1 \
        https://archlinux.org \
        /tmp/yay

    chown -R "$REAL_USER:$REAL_USER" /tmp/yay

    sudo -u "$REAL_USER" bash -c '
        cd /tmp/yay
        makepkg -si --noconfirm
    '

    rm -rf /tmp/yay

else
    echo "yay is already installed."
fi

#################################################
# AUR PACKAGES & PRELOAD
#################################################

echo "=== Installing AUR packages ==="

sudo -u "$REAL_USER" yay -S --needed --noconfirm \
    brave-origin-bin \
    warp-cli \
    spotify \
    gotohp-bin \
    galaxybudsclient-bin \
    preload

if [[ $IS_CONTAINER -eq 0 ]]; then
    echo "=== Enabling Preload ==="
    systemctl enable --now preload.service
else
    echo "--- Skipping Preload service (Container) ---"
fi

#################################################
# IRQBALANCE
#################################################

echo "=== Installing irqbalance ==="

pacman -S --needed --noconfirm irqbalance

if [[ $IS_CONTAINER -eq 0 ]]; then
    echo "=== Enabling irqbalance ==="
    systemctl enable --now irqbalance.service
else
    echo "--- Skipping irqbalance service (Container) ---"
fi

#################################################
# SPOTX
#################################################

echo "=== Installing SpotX ==="

sudo -u "$REAL_USER" bash -c \
    'bash <(curl -sSL https://spotx-official.github.io/run.sh)'

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

if [[ $IS_CONTAINER -eq 0 ]]; then
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
else
    echo "--- Skipping RAM flush service (Container) ---"
fi

#################################################
# ZRAM
#################################################

if [[ $IS_CONTAINER -eq 0 ]]; then
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
else
    echo "--- Skipping ZRAM configuration (Container) ---"
fi

#################################################
# HYPRLAND & WAYLAND ENVIRONMENT
#################################################

echo "=== Installing Hyprland and Wayland Desktop utilities ==="

pacman -S --needed --noconfirm \
    hyprland \
    kitty \
    waybar \
    rofi-wayland \
    hyprpaper \
    blueman \
    pavucontrol

#################################################
# UNDERVOLT
#################################################

echo "=== Installing undervolt ==="

python3 -m pip install --break-system-packages undervolt

UNDERVOLT="$(command -v undervolt || true)"

if [[ -n "$UNDERVOLT" ]]; then

    echo "undervolt found at: $UNDERVOLT"

    if [[ $IS_CONTAINER -eq 0 ]]; then
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
        echo "--- Skipping undervolt systemd service (Container) ---"
    fi

else
    echo "WARNING: undervolt command was not found."
fi

#################################################
# AUDIO & BLUETOOTH
#################################################

echo "=== Removing PulseAudio ==="

pacman -Rns --noconfirm \
    pulseaudio \
    pulseaudio-bluetooth \
    2>/dev/null || true

echo "=== Installing PipeWire + Bluetooth ==="

pacman -S --needed --noconfirm \
    pipewire \
    pipewire-pulse \
    wireplumber \
    bluez \
    bluez-utils

if [[ $IS_CONTAINER -eq 0 ]]; then
    systemctl enable --now bluetooth.service
else
    echo "--- Skipping Bluetooth service activation (Container) ---"
fi

#################################################
# FORCE SBC-XQ CODEC ON HEADPHONES
#################################################

echo "=== Configuring WirePlumber for SBC-XQ ==="

mkdir -p "$USER_HOME/.config/wireplumber/wireplumber.conf.d"

cat > "$USER_HOME/.config/wireplumber/wireplumber.conf.d/50-bluetooth.conf" <<'EOF'
monitor.bluez.properties = {
    bluez5.a2dp.codecs = [ sbc_xq aac sbc ]
}
EOF

chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config/wireplumber"

#################################################
# RESTART USER AUDIO
#################################################

if [[ $IS_CONTAINER -eq 0 ]]; then
    echo "=== Restarting PipeWire ==="

    USER_ID="$(id -u "$REAL_USER")"

    sudo -u "$REAL_USER" \
        XDG_RUNTIME_DIR="/run/user/$USER_ID" \
        systemctl --user restart pipewire pipewire-pulse wireplumber \
        2>/dev/null || true
else
    echo "--- Skipping user audio restart (Container) ---"
fi

#################################################
# GRUB DEEP SLEEP FIX
#################################################

if [[ $IS_CONTAINER -eq 0 ]]; then
    echo "=== Configuring GRUB ==="

    if [[ ! -f /etc/default/grub ]]; then
        echo "ERROR: /etc/default/grub not found."
        exit 1
    fi

    GRUB_CMDLINE='systemd.show_status=true mem_sleep_default=deep acpi_osi=Linux pcie_aspm=off ignore_loglevel systemd.log_level=debug systemd.log_target=kmsg log_buf_len=16M devkmsg=on'

    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_CMDLINE\"|" /etc/default/grub
    else
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_CMDLINE\"" >> /etc/default/grub
    fi

    #################################################
    # GRUB PACKAGES
    #################################################

    echo "=== Installing GRUB + os-prober ==="

    pacman -S --needed --noconfirm grub os-prober

    #################################################
    # OS PROBER
    #################################################

    echo "=== Enabling os-prober ==="

    if grep -q '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
        sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    else
        echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
    fi

    #################################################
    # EFI LOCATION
    #################################################

    echo "=== Detecting EFI partition ==="

    if mountpoint -q /efi; then
        EFI_DIR="/efi"
    elif mountpoint -q /boot/efi; then
        EFI_DIR="/boot/efi"
    else
        echo "ERROR: EFI partition is not mounted."
        echo ""
        echo "Expected either:"
        echo "  /efi"
        echo "  /boot/efi"
        echo ""
        exit 1
    fi

    echo "EFI directory: $EFI_DIR"

    #################################################
    # GRUB INSTALL
    #################################################

    echo "=== Installing GRUB ==="

    grub-install --target=x86_64-efi --efi-directory="$EFI_DIR" --bootloader-id=ArchGRUB --recheck

    #################################################
    # ARCH ISO + WINDOWS INSTALLER
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

    #################################################
    # GRUB CONFIG
    #################################################

    echo "=== Generating GRUB configuration ==="

    grub-mkconfig -o /boot/grub/grub.cfg
else
    echo "--- Skipping GRUB / Bootloader configuration (Container) ---"
fi

#################################################
# INTEL VIDEO
#################################################

echo "=== Installing Intel video acceleration ==="

pacman -R --noconfirm xf86-video-intel 2>/dev/null || true
pacman -S --needed --noconfirm intel-media-driver libva-utils intel-gpu-tools

#################################################
# BASHRC ALIASES
#################################################

echo "=== Configuring bash aliases ==="

add_aliases() {
    local target_rc="$1"
    touch "$target_rc"

    if ! grep -q '# Methu Windows shortcuts' "$target_rc"; then
        cat >> "$target_rc" <<'RCEOF'

# ~/.bashrc

# If not running interactively, don't do anything
[[ $- != i ]] && return

fastfetch

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# Methu Windows shortcuts
alias bootwin='sudo grub-reboot "$(grep -i "menuentry .*Windows Boot Manager" /boot/grub/grub.cfg | sed -n "s/.*'"'"'\(.*\)'"'"'.*/\1/p" | head -n1)" && sudo reboot'
alias cleaninstall="sudo grub-reboot arch-installer && reboot"
alias mountwin="sudo mkdir -p /run/media/methu/Windows && sudo ntfs-3g /dev/nvme0n1p3 /run/media/methu/Windows"
alias enable_warp-svc="sudo systemctl unmask warp-svc && sudo systemctl start warp-svc"
alias disable_warp-svc="sudo systemctl stop warp-svc && sudo systemctl mask warp-svc"
alias disablecores='for cpu in {4..7}; do echo 0 | sudo tee /sys/devices/system/cpu/cpu$cpu/online >/dev/null; done'
alias enablecores='for cpu in {4..7}; do echo 1 | sudo tee /sys/devices/system/cpu/cpu$cpu/online >/dev/null; done'
alias cpu-cool='sudo cpupower frequency-set -u 800MHz'
alias cpu-normal='sudo cpupower frequency-set -u 1600MHz'
alias fixefi='read -rp "Enter partition (e.g. nvme0n1p1 or /dev/nvme0n1p1): " dev && dev="/dev/${dev#/dev/}" && if [ -b "$dev" ]; then command -v fsck.fat >/dev/null 2>&1 || sudo pacman -S --needed dosfstools; sudo umount "$dev" 2>/dev/null; sudo fsck.fat -r -w "$dev" && sudo fsck.fat -v "$dev"; else echo "Error: Block device $dev not found."; fi'
RCEOF
    fi
}

add_aliases "/root/.bashrc"
add_aliases "$USER_HOME/.bashrc"

chown "$REAL_USER:$REAL_USER" "$USER_HOME/.bashrc"

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
echo "       METHU SETUP COMPLETE"
echo "====================================="
echo ""
echo "Installed/configured:"
echo ""
echo "- MethuRepo"
echo "- MethuRepo packages"
echo "- yay"
echo "- Brave"
echo "- Spotify"
echo "- SpotX"
echo "- Cloudflare WARP"
echo "- Preload (Package only)"
echo "- irqbalance (Package only)"
echo "- PipeWire + WirePlumber"
echo "- Bluetooth (Package only)"
echo "- Hyprland, Waybar, Rofi, Kitty"
echo "- Blueman & Pavucontrol"
echo "- Intel media drivers"
echo "- Stremio"
echo "- VSCodium"

if [[ $IS_CONTAINER -eq 0 ]]; then
    echo "- ZRAM 16GB (zstd)"
    echo "- RAM flush every 30 minutes"
    echo "- GRUB & custom boot entries"
else
    echo "- (Skipped system configurations for container safety)"
fi

echo "- Windows aliases"
echo ""
echo "User: $REAL_USER"
echo ""
echo "AUR support enabled."
echo "System updated."
echo ""

if [[ $IS_CONTAINER -eq 0 ]]; then
    echo "A reboot is recommended. Launch Hyprland by typing 'Hyprland' in the TTY."
else
    echo "Container test successful! No reboot needed for container environment."
fi

echo ""
echo "====================================="
