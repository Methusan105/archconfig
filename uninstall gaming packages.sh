#!/usr/bin/env bash
set -euo pipefail

# Automatically re-run the script with sudo if not already root
if [ "$EUID" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

echo -e "\e[1;34mRemoving gaming tools and related packages...\e[0m"

# Gaming applications
GAMING_PACKAGES=(
    steam
    lutris
    heroic-games-launcher-bin
    wine-staging
    giflib
    lib32-giflib

    # Gaming/performance tools
    gamemode
    lib32-gamemode
    mangohud
    lib32-mangohud
    goverlay

    # Vulkan / DirectX translation packages installed by the original script
    vkd3d
    lib32-vkd3d
)

echo -e "\e[1;34mRemoving installed gaming packages...\e[0m"

# Only remove packages that are actually installed
INSTALLED_PACKAGES=()

for package in "${GAMING_PACKAGES[@]}"; do
    if pacman -Q "$package" >/dev/null 2>&1; then
        INSTALLED_PACKAGES+=("$package")
    fi
done

if [ "${#INSTALLED_PACKAGES[@]}" -gt 0 ]; then
    pacman -Rns --noconfirm "${INSTALLED_PACKAGES[@]}"
else
    echo "No gaming packages from the list are installed."
fi

echo
echo -e "\e[1;34mCleaning unused dependencies...\e[0m"

# Remove orphaned packages
ORPHANS=$(pacman -Qtdq 2>/dev/null || true)

if [ -n "$ORPHANS" ]; then
    pacman -Rns --noconfirm $ORPHANS
else
    echo "No orphaned packages found."
fi

echo
echo -e "\e[1;34mCleaning pacman cache...\e[0m"
pacman -Sc --noconfirm

echo
echo -e "\e[1;32mSUCCESS!\e[0m"
echo
echo "Gaming tools from the original installation have been removed."
echo
echo "The following were NOT removed:"
echo "  - NVIDIA drivers"
echo "  - NVIDIA utilities"
echo "  - NVIDIA settings"
echo "  - EnvyControl"
echo "  - DKMS"
echo "  - Linux kernel"
echo "  - Linux kernel headers"
echo
echo "No reboot is normally required."
