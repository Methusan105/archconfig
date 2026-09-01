#!/usr/bin/env bash
set -euo pipefail

# Ensure script is run with root permissions
if [ "$EUID" -ne 0 ]; then
  echo -e "\e[1;31mError: Please run this script with sudo.\e[0m"
  exit 1
fi

# Detect calling regular user (makepkg cannot run directly as root)
TARGET_USER="${SUDO_USER:-$USER}"
if [ "$TARGET_USER" = "root" ]; then
  echo -e "\e[1;31mError: Do not execute directly as root. Run as regular user via sudo.\e[0m"
  exit 1
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

echo -e "\e[1;34m[1/6] Enabling [multilib] repository...\e[0m"
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
  sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
fi

echo -e "\e[1;34m[2/6] Syncing repositories & installing Linux-Zen and Nvidia packages...\e[0m"
pacman -Sy --noconfirm
pacman -S --needed --noconfirm \
  linux-zen-headers nvidia-dkms \
  base-devel git linux-zen dkms \
  nvidia-utils lib32-nvidia-utils nvidia-settings \
  vulkan-icd-loader lib32-vulkan-icd-loader \
  steam lutris wine-staging giflib lib32-giflib \
  gamemode lib32-gamemode mangohud lib32-mangohud goverlay vkd3d lib32-vkd3d

echo -e "\e[1;34m[3/6] Setting up yay AUR helper and EnvyControl...\e[0m"
if ! command -v yay &> /dev/null; then
  BUILD_DIR=$(mktemp -d -p "$TARGET_HOME")
  chown -R "$TARGET_USER:$TARGET_USER" "$BUILD_DIR"
  sudo -u "$TARGET_USER" git clone https://aur.archlinux.org/yay.git "$BUILD_DIR/yay"
  sudo -u "$TARGET_USER" bash -c "cd '$BUILD_DIR/yay' && makepkg -si --noconfirm"
  rm -rf "$BUILD_DIR"
fi

sudo -u "$TARGET_USER" yay -S --needed --noconfirm envycontrol heroic-games-launcher-bin
envycontrol -s hybrid

echo -e "\e[1;34m[4/6] Configuring GRUB Kernel Parameters...\e[0m"
if [ -f /etc/default/grub ]; then
  for param in "nvidia-drm.modeset=1" "nvidia-drm.fbdev=1"; do
    if ! grep -q "$param" /etc/default/grub; then
      sed -i "s/^\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)\"/\1 $param\"/" /etc/default/grub
    fi
  done
  grub-mkconfig -o /boot/grub/grub.cfg
fi

echo -e "\e[1;34m[5/6] Forcing DKMS Nvidia Module Build & Installation...\e[0m"
dkms remove nvidia/610.57.04 --all || true
dkms install nvidia/610.57.04 -k "$(uname -r)" --force

echo -e "\e[1;34m[6/6] Early KMS (mkinitcpio) & Initramfs Rebuild...\e[0m"
if [ -f /etc/mkinitcpio.conf ]; then
  if ! grep -q "nvidia" /etc/mkinitcpio.conf; then
    sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
  fi
fi
mkinitcpio -P

echo -e "\n\e[1;32mSUCCESS! Force install finished perfectly.\e[0m"

# Interactive prompt reading from terminal directly (supports curl | bash)
read -p "Would you like to reboot the system now? [Y/n]: " -r RESPONSE < /dev/tty || RESPONSE="y"
case "$RESPONSE" in
    [nN][oO]|[nN])
        echo -e "\e[1;33mReboot skipped. Remember to reboot manually before gaming.\e[0m"
        ;;
    *)
        echo -e "\e[1;34mRebooting now...\e[0m"
        reboot
        ;;
esac
