#!/usr/bin/env bash
#
# hyprland-post-setup.sh
#
# Kjøres ETTER at hovedskriptet (setup.sh) og alle programmer er installert,
# på en RENDYRKET Hyprland-installasjon (ingen KDE Plasma).
#
# Setter opp det som trengs for at Brave, VSCodium og de andre installerte
# programmene skal fungere skikkelig i en ren Hyprland-sesjon: portaler,
# polkit-agent, secret-service (passordlagring), Qt/Wayland-integrasjon og
# autostart av tray-apper.
#
# Kjøres som vanlig bruker eller med sudo - skriptet ber om sudo selv
# når det trengs til pacman.

set -Eeuo pipefail

trap '
    echo ""
    echo "====================================="
    echo "ERROR on line $LINENO"
    echo "====================================="
    exit 1
' ERR

#################################################
# ROOT / USER SETUP (samme mønster som setup.sh)
#################################################

if [[ $EUID -ne 0 ]]; then
    echo "=== Root privileges required for package install ==="
    exec sudo -E bash "$0" "$@"
fi

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$(logname 2>/dev/null || true)"
fi

if [[ -z "$REAL_USER" || "$REAL_USER" == "root" ]]; then
    echo "ERROR: Could not determine the normal user. Run via sudo from your user account."
    exit 1
fi

USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
    echo "ERROR: Could not determine home directory for $REAL_USER"
    exit 1
fi

run_as_user() {
    sudo -u "$REAL_USER" bash -c "$1"
}

echo "====================================="
echo " Hyprland post-setup (uten KDE)"
echo "====================================="
echo "User: $REAL_USER"
echo "Home: $USER_HOME"
echo ""

#################################################
# PACKAGES
#################################################

echo "=== Installing Hyprland/Wayland integration packages ==="

# xdg-desktop-portal-hyprland: skjermdeling/skjermbilder/skjermopptak
#   for Brave, Discord i nettleser osv.
# xdg-desktop-portal-gtk: filvelger-portal (siden KDE-portalen ikke
#   lenger er installert)
# qt5-wayland / qt6-wayland: native Wayland-rendering for Qt-apper
#   (Falkon, Transmission-Qt, PeaZip) i stedet for XWayland
# qt5ct / qt6ct: gir et sted å style Qt-appene når KDE ikke lenger
#   finnes til å levere temaet
# wl-clipboard, grim, slurp: utklippstavle og skjermbilder på Wayland
# gtk3: gir "gtk-launch", brukes lenger ned til å starte tray-apper
#   via deres .desktop-filer i stedet for å gjette binærnavn

pacman -S --needed --noconfirm \
    xdg-desktop-portal-hyprland \
    xdg-desktop-portal-gtk \
    qt5-wayland \
    qt6-wayland \
    qt5ct \
    qt6ct \
    gnome-keyring \
    wl-clipboard \
    grim \
    slurp \
    gtk3

echo "=== Installing Hyprland polkit agent (AUR) ==="

sudo -u "$REAL_USER" yay -S --needed --noconfirm hyprpolkitagent

#################################################
# XDG DESKTOP PORTAL CONFIG
#################################################

echo "=== Configuring xdg-desktop-portal ==="

run_as_user "mkdir -p '$USER_HOME/.config/xdg-desktop-portal'"

run_as_user "cat > '$USER_HOME/.config/xdg-desktop-portal/hyprland-portals.conf' <<'EOF'
[preferred]
default=hyprland
org.freedesktop.impl.portal.FileChooser=gtk
org.freedesktop.impl.portal.Screenshot=hyprland
org.freedesktop.impl.portal.ScreenCast=hyprland
EOF"

#################################################
# ENVIRONMENT VARIABLES (via environment.d, virker for hele Wayland-økten)
#################################################

echo "=== Writing session environment variables ==="

run_as_user "mkdir -p '$USER_HOME/.config/environment.d'"

run_as_user "cat > '$USER_HOME/.config/environment.d/hyprland-apps.conf' <<'EOF'
# Qt-apper kjører native på Wayland og styles via qt5ct/qt6ct
QT_QPA_PLATFORM=wayland;xcb
QT_QPA_PLATFORMTHEME=qt6ct
QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Riktig sesjonstype-hint for Electron/Chromium-apper
XDG_SESSION_TYPE=wayland
XDG_CURRENT_DESKTOP=Hyprland
XDG_SESSION_DESKTOP=Hyprland

# Mozilla/GTK Wayland-hint
MOZ_ENABLE_WAYLAND=1
GDK_BACKEND=wayland,x11
EOF"

#################################################
# BRAVE: TVING WAYLAND (OZONE)
#################################################

echo "=== Configuring Brave for native Wayland ==="

run_as_user "cat > '$USER_HOME/.config/brave-flags.conf' <<'EOF'
--ozone-platform-hint=auto
--enable-features=WaylandWindowDecorations
EOF"

#################################################
# VSCODIUM: TVING WAYLAND (OZONE)
#################################################

echo "=== Configuring VSCodium for native Wayland ==="

run_as_user "cat > '$USER_HOME/.config/vscodium-flags.conf' <<'EOF'
--ozone-platform-hint=auto
--enable-features=WaylandWindowDecorations
EOF"

#################################################
# HYPRLAND CONFIG: AUTOSTART AV NØDVENDIGE TJENESTER + TRAY-APPER
#################################################

echo "=== Adding autostart entries to hyprland.conf ==="

HYPR_DIR="$USER_HOME/.config/hypr"
HYPR_CONF="$HYPR_DIR/hyprland.conf"

run_as_user "mkdir -p '$HYPR_DIR'"

if [[ ! -f "$HYPR_CONF" ]]; then
    echo "No existing hyprland.conf found, creating a minimal one."
    run_as_user "touch '$HYPR_CONF'"
fi

START_MARK="# >>> methu hyprland-post-setup autostart >>>"
END_MARK="# <<< methu hyprland-post-setup autostart <<<"

if ! grep -qF "$START_MARK" "$HYPR_CONF" 2>/dev/null; then

    run_as_user "cat >> '$HYPR_CONF' <<EOF

$START_MARK
# Miljøvariabler for dbus/portal-aktivering skal se riktig ut
exec-once = dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP

# Polkit-agent (Hyprlands egen, siden KDE ikke lenger er installert)
exec-once = hyprpolkitagent

# Secret-service / nøkkelring (trengs for at Brave, gh (GitHub CLI) o.l.
# skal kunne lagre passord/tokens via libsecret)
exec-once = gnome-keyring-daemon --start --components=pkcs11,secrets,ssh

# Systray-apper (krever at waybar har modulen \"tray\" aktivert,
# se waybar-config lenger ned i dette skriptet)
exec-once = nm-applet --indicator
exec-once = gtk-launch com.cloudflare.WarpTaskbar
exec-once = gtk-launch galaxybudsclient
exec-once = solaar --window=hide
exec-once = gtk-launch bluetooth-bitrate-manager
$END_MARK
EOF"

else
    echo "Autostart-block already present in hyprland.conf, skipping."
fi

chown -R "$REAL_USER:$REAL_USER" "$HYPR_DIR"

#################################################
# WAYBAR: SØRG FOR AT TRAY-MODULEN ER PÅ
#################################################

echo "=== Checking waybar config for tray module ==="

WAYBAR_DIR="$USER_HOME/.config/waybar"
WAYBAR_CONF="$WAYBAR_DIR/config"

run_as_user "mkdir -p '$WAYBAR_DIR'"

if [[ -f "$WAYBAR_CONF" ]]; then
    if grep -q '"tray"' "$WAYBAR_CONF"; then
        echo "Waybar already has a tray module configured."
    else
        echo "NOTE: Waybar config exists but has no \"tray\" module."
        echo "Legg \"tray\" til i modules-right i: $WAYBAR_CONF"
        echo "og legg til en \"tray\": { \"icon-size\": 18, \"spacing\": 8 } seksjon."
    fi
else
    echo "No waybar config found, creating a minimal one with tray enabled."
    run_as_user "cat > '$WAYBAR_CONF' <<'EOF'
{
    \"layer\": \"top\",
    \"position\": \"top\",
    \"modules-left\": [\"hyprland/workspaces\"],
    \"modules-center\": [\"clock\"],
    \"modules-right\": [\"tray\", \"pulseaudio\", \"network\", \"battery\"],
    \"tray\": {
        \"icon-size\": 18,
        \"spacing\": 8
    }
}
EOF"
    chown "$REAL_USER:$REAL_USER" "$WAYBAR_CONF"
fi

#################################################
# FERDIG
#################################################

echo ""
echo "====================================="
echo " Hyprland post-setup ferdig"
echo "====================================="
echo ""
echo "Konfigurert:"
echo "- xdg-desktop-portal-hyprland + xdg-desktop-portal-gtk"
echo "- Filvelger-portal satt til GTK (ingen KDE-portal lenger)"
echo "- Qt/Wayland-støtte (qt5-wayland, qt6-wayland, qt5ct, qt6ct)"
echo "- gnome-keyring som secret-service (erstatter KWallet)"
echo "- Brave og VSCodium tvinges til native Wayland (ozone)"
echo "- hyprpolkitagent og gnome-keyring autostartes"
echo "- Tray-apper (nm-applet, Warp, GalaxyBudsClient, Solaar,"
echo "  Bluetooth Bitrate Manager) lagt til i hyprland.conf"
echo "- Waybar sjekket/opprettet med tray-modul"
echo ""
echo "Restart Hyprland-sesjonen (logg ut/inn) for at alt skal tre i kraft."
echo "Kjør 'qt6ct' en gang for å velge Qt-stil/tema som matcher GTK-temaet ditt."
echo "====================================="
