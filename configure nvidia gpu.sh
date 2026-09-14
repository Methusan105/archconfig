#!/usr/bin/env bash
set -euo pipefail

# Automatically re-run the script with sudo if not already root
if [ "$EUID" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

# Detect the original regular user
TARGET_USER="${SUDO_USER:-$USER}"

if [ "$TARGET_USER" = "root" ]; then
    echo -e "\e[1;31mError: Do not execute this script directly as root.\e[0m"
    echo "Run it as a normal user so EnvyControl can be configured correctly."
    exit 1
fi

echo -e "\e[1;34m[1/4] Updating package databases...\e[0m"
pacman -Sy --noconfirm

echo -e "\e[1;34m[2/4] Installing NVIDIA driver and required packages...\e[0m"

pacman -S --needed --noconfirm \
    nvidia-dkms \
    nvidia-utils \
    nvidia-settings \
    dkms \
    linux-headers

echo -e "\e[1;34m[3/4] Installing EnvyControl...\e[0m"

if ! command -v envycontrol >/dev/null 2>&1; then
    echo "EnvyControl is not installed."

    # Install yay temporarily if necessary
    if ! command -v yay >/dev/null 2>&1; then
        echo "Installing yay temporarily to obtain EnvyControl..."

        BUILD_DIR=$(mktemp -d)

        chown "$TARGET_USER:$TARGET_USER" "$BUILD_DIR"

        sudo -u "$TARGET_USER" git clone \
            https://aur.archlinux.org/yay.git \
            "$BUILD_DIR/yay"

        sudo -u "$TARGET_USER" bash -c \
            "cd '$BUILD_DIR/yay' && makepkg -si --noconfirm"

        rm -rf "$BUILD_DIR"
    fi

    sudo -u "$TARGET_USER" yay -S --needed --noconfirm envycontrol
fi

echo -e "\e[1;34m[4/4] Configuring NVIDIA hybrid graphics mode...\e[0m"

envycontrol -s hybrid

echo
echo -e "\e[1;32mSUCCESS!\e[0m"
echo
echo "NVIDIA drivers have been installed."
echo "EnvyControl has been configured for hybrid graphics mode."
echo
echo "A reboot is required for the changes to take effect."

# Interactive prompt reading directly from terminal
read -p "Would you like to reboot the system now? [Y/n]: " -r RESPONSE < /dev/tty || RESPONSE="y"

case "$RESPONSE" in
    [nN][oO]|[nN])
        echo
        echo -e "\e[1;33mReboot skipped.\e[0m"
        echo "Please reboot manually when convenient."
        ;;
    *)
        echo
        echo -e "\e[1;34mRebooting now...\e[0m"
        reboot
        ;;
esac
