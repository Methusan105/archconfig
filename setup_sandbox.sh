#!/bin/bash

# Hvis skriptet startes med sudo via archconfig-cli, start på nytt som vanlig bruker
if [ -n "$SUDO_USER" ] && [ "$EUID" -eq 0 ]; then
    echo "[!] Oppdaget sudo. Bytter tilbake til vanlig bruker ($SUDO_USER)..."
    exec sudo -u "$SUDO_USER" env HOME="/home/$SUDO_USER" "$0" "$@"
fi

# Avbryt skriptet hvis en kommando feiler
set -e

echo "=== HVA VIL DU GJØRE? ==="
echo "1) Opprett og installer ny sandbox"
echo "2) Avinstaller og slett sandbox"
read -p "Velg alternativ (1 eller 2): " MAIN_CHOICE

case "$MAIN_CHOICE" in
  1)
    echo ""
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

    # Oppretter den rene distribusjonen med isolert home og unshare-all for disk/system-isolering
    distrobox create --name "$CONTAINER_NAME" --image "$CONTAINER_IMG" --home "$CONTAINER_HOME" --unshare-all --yes

    echo ""
    echo "========================================================="
    echo "[✓] DISTROBOX-CONTAINER ER OPPRETTET!"
    echo "========================================================="
    echo "Distribusjonen er installert og helt isolert fra din ekte hjemmemappe og vertssystemet."
    echo ""
    echo "For å gå inn i den nye sandkassen, kjør denne kommandoen:"
    echo "   distrobox enter $CONTAINER_NAME"
    echo "========================================================="
    ;;

  2)
    echo ""
    echo "=== AVINSTALLER OG SLETT SANDBOX ==="
    
    if ! command -v distrobox &> /dev/null; then
        echo "[!] Distrobox er ikke installert på systemet."
        exit 1
    fi

    echo "Eksisterende Distrobox-containere:"
    distrobox list
    echo ""

    read -p "Skriv inn navnet på containeren du vil slette (f.eks. clean-arch-sandbox): " DEL_NAME

    if [ -z "$DEL_NAME" ]; then
        echo "[!] Ingen navn oppgitt. Avbryter."
        exit 1
    fi

    if ! distrobox list | grep -q "$DEL_NAME"; then
        echo "[!] Fant ingen container med navnet '$DEL_NAME'."
        exit 1
    fi

    # Bekreftelse for å slette selve containeren
    read -p "Er du sikker på at du vil slette containeren '$DEL_NAME'? (y/N): " CONFIRM_RM
    if [[ "$CONFIRM_RM" =~ ^[Yy]$ ]]; then
        echo "Sletter container '$DEL_NAME'..."
        distrobox rm -f "$DEL_NAME"
        echo "[✓] Container slettet."
    else
        echo "Sletting av container avbrutt."
    fi

    # Spør eksplisitt om sletting av isolert hjemmemappe
    TARGET_HOME="$HOME/.local/share/$DEL_NAME-home"
    if [ -d "$TARGET_HOME" ]; then
        echo ""
        read -p "Vil du også slette den isolerte hjemmemappen ($TARGET_HOME)? (y/N): " CONFIRM_HOME
        if [[ "$CONFIRM_HOME" =~ ^[Yy]$ ]]; then
            echo "Fjerner mappen $TARGET_HOME..."
            rm -rf "$TARGET_HOME"
            echo "[✓] Hjemmemappe slettet."
        else
            echo "Hjemmemappen ble bevart."
        fi
    fi

    # Spør eksplisitt om Podman system prune
    if command -v podman &> /dev/null; then
        echo ""
        read -p "Vil du rydde opp i ubenyttede Podman-bilder, containere og volum (podman system prune -a --volumes)? (y/N): " CONFIRM_PRUNE
        if [[ "$CONFIRM_PRUNE" =~ ^[Yy]$ ]]; then
            echo "Kjører Podman system prune..."
            podman system prune -a --volumes --force
            echo "[✓] Podman-systemrydding fullført."
        else
            echo "Podman-rydding hoppet over."
        fi
    fi

    echo ""
    echo "[✓] Opprydding fullført."
    ;;

  *)
    echo "[!] Ugyldig valg. Avbryter."
    exit 1
    ;;
esac
