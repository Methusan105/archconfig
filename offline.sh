#!/bin/bash

# Avbryt skriptet hvis en kommando feiler
set -e

echo "=== Velkommen til automatisk offline Arch-installasjon ==="

# 1. Finn partisjonen til ekstern-disken (ser etter NTFS/exFAT-enheter automatisk)
echo "Søker etter ekstern disk..."
TARGET_DEV=$(lsblk -no NAME,FSTYPE | grep -E "ntfs|exfat" | head -n1 | awk '{print $1}')

if [ -z "$TARGET_DEV" ]; then
    echo "FEIL: Fant ikke ekstern-disken din automatisk via lsblk. Skriv inn partisjonsnavn manuelt (f.eks. sdb1):"
    read -r MANUAL_DEV
    TARGET_DEV=$MANUAL_DEV
fi

echo "Bruker diskpartisjon: /dev/$TARGET_DEV"

# 2. Monter ekstern-disken til ISO-miljøet
echo "Monterer ekstern disk..."
mkdir -p /mnt/usb
mount -o ro "/dev/$TARGET_DEV" /mnt/usb

# 3. Installer archivemount i ISO-en (RAM-besparende mounter)
echo "Installerer archivemount i ISO-miljøet..."
pacman -Sy --noconfirm archivemount

# 4. Sjekk om vi bruker én stor eller oppdelte zip-filer, og monter
mkdir -p /offline-repo
if [ -f "/mnt/usb/arch-offline-packages.zip" ]; then
    echo "Fant komplett ZIP-fil. Monterer som virtuelt Linux-filsystem..."
    archivemount -o readonly /mnt/usb/arch-offline-packages.zip /offline-repo
elif [ -f "/mnt/usb/arch-offline-packages.zip.001" ]; then
    echo "Fant oppdelte ZIP-filer. Slår sammen midlertidig i /tmp og mounter..."
    cat /mnt/usb/arch-offline-packages.zip.* > /tmp/merged_packages.zip
    archivemount -o readonly /tmp/merged_packages.zip /offline-repo
else
    echo "FEIL: Fant ikke arch-offline-packages.zip på ekstern-disken!"
    exit 1
fi

# 5. Konfigurer pacman.conf med det nye lokale speilet
echo "Konfigurerer /etc/pacman.conf..."
if ! grep -q "\[custom\]" /etc/pacman.conf; then
    echo -e "\n[custom]\nSigLevel = Optional\nServer = file:///offline-repo/pkg" >> /etc/pacman.conf
fi

# Synkroniser databasen offline
pacman -Sy

# 6. Start archinstall med json-konfigurasjonen din
echo "Starter archinstall helt offline..."
if [ -f "/offline-repo/user_configuration.json" ]; then
    archinstall --config /offline-repo/user_configuration.json
else
    echo "ADVARSEL: Fant ikke user_configuration.json i zip-filen. Starter archinstall interaktivt..."
    archinstall
fi
