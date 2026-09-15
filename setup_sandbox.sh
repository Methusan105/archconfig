#!/bin/bash

# Avbryt skriptet hvis en kommando feiler
set -e

echo "=== 1. SJEKKER VERTSMASKIN (ARCH LINUX) ==="

# Sjekk Podman
if ! command -v podman &> /dev/null; then
    echo "[+] Podman ble ikke funnet. Installerer..."
    sudo pacman -S --noconfirm podman
else
    echo "[✓] Podman er allerede installert."
fi

# Sjekk Distrobox
if ! command -v distrobox &> /dev/null; then
    echo "[+] Distrobox ble ikke funnet. Installerer..."
    sudo pacman -S --noconfirm distrobox
else
    echo "[✓] Distrobox er allerede installert."
fi

echo ""
echo "=== 2. KONFIGURASJON AV ISOLERT CONTAINER ==="

# Velg distribusjon
echo "Hvilken Linux-distribusjon vil du installere?"
echo "1) archlinux:latest"
echo "2) ubuntu:latest"
read -p "Velg alternativ (1 eller 2): " DISTRO_CHOICE

if [ "$DISTRO_CHOICE" = "2" ]; then
    CONTAINER_IMG="ubuntu:latest"
    CONTAINER_NAME="clean-ubuntu-sandbox"
else
    CONTAINER_IMG="archlinux:latest"
    CONTAINER_NAME="clean-arch-sandbox"
fi

# Velg isolert hjemmemappe
DEFAULT_HOME="$HOME/.local/share/$CONTAINER_NAME-home"
echo ""
echo "Hvor vil du plassere den isolerte hjemmemappen?"
echo "Dette hindrer containeren i å se dine ekte private filer."
read -p "Trykk ENTER for standard [$DEFAULT_HOME]: " USER_HOME
CONTAINER_HOME=${USER_HOME:-$DEFAULT_HOME}

echo ""
echo "=== 3. OPPRETTER CONTAINER ==="
echo "Oppretter container '$CONTAINER_NAME'..."
mkdir -p "$CONTAINER_HOME"

# Slett gammel container hvis den eksisterer med samme navn
if distrobox list | grep -q "$CONTAINER_NAME"; then
    echo "En container med dette navnet eksisterer allerede. Erstatter den..."
    distrobox rm -f "$CONTAINER_NAME"
fi

# Oppretter den rene distribusjonen med isolert home
distrobox create --name "$CONTAINER_NAME" --image "$CONTAINER_IMG" --home "$CONTAINER_HOME" --yes

echo ""
echo "========================================================="
echo "[✓] DISTROBOX-CONTAINER ER OPPRETTET!"
echo "========================================================="
echo "Distribusjonen er installert og helt isolert fra din ekte hjemmemappe."
echo ""
echo "For å gå inn i den nye sandkassen, kjør denne kommandoen:"
echo "   distrobox enter $CONTAINER_NAME"
echo "========================================================="
