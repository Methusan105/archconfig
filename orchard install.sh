#!/bin/bash
set -e

INSTALL_DIR="$HOME/.local/share/orchard"
TAR_URL="https://github.com/Methusan105/archconfig/releases/download/ob/orchard-backup.tar.gz"

echo "Setter opp Orchard for brukeren $USER..."

# Opprett nødvendige mapper
mkdir -p "$INSTALL_DIR"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share/applications"
mkdir -p "$HOME/.local/share/pixmaps"

# Last ned og pakk ut samtidig direkte til ~/.local/share/
echo "-> Laster ned og pakker ut Orchard fra GitHub..."
curl -L "$TAR_URL" | tar -xzv -C "$HOME/.local/share/"

# Lag symlink slik at du kan skrive 'orchard' i terminalen
if [ -f "$INSTALL_DIR/orchard" ]; then
    ln -sf "$INSTALL_DIR/orchard" "$HOME/.local/bin/orchard"
    echo "-> Laget terminal-kommando: orchard"
fi

# Kopier app-ikonet til pixmaps hvis det finnes
ICON_PATH="$INSTALL_DIR/versions/1.0.0-canary.10/orchard.png"
if [ -f "$ICON_PATH" ]; then
    cp "$ICON_PATH" "$HOME/.local/share/pixmaps/orchard.png"
    echo "-> Kopiert app-ikon"
fi

# Opprett skrivebordslenke (app-meny)
cat << EOF > "$HOME/.local/share/applications/orchard.desktop"
[Desktop Entry]
Name=Orchard
Comment=Orchard Native Desktop Client
Exec=$INSTALL_DIR/orchard %U
Icon=$HOME/.local/share/pixmaps/orchard.png
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Player;
EOF

echo "-> Laget skrivebordsveksel i app-menyen"
echo "Ferdig! Orchard er nå installert og klar til bruk."
