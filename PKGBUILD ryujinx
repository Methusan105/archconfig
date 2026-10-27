# Maintainer:

_pkgname="ryujinx"
pkgname="$_pkgname-canary-bin"
pkgver=1.3.351
pkgrel=1
pkgdesc="Experimental Nintendo Switch Emulator written in C# (Prebuilt Binary)"
url="https://github.com/Methusan105/archconfig"
license=('MIT')
arch=('x86_64')

provides=("$_pkgname")
conflicts=("$_pkgname")

depends=(
  'alsa-lib'
  'fontconfig'
  'hicolor-icon-theme'
  'jack'
  'libpulse'
  'libx11'
  'wayland'
)
makedepends=(
  'desktop-file-utils'
)

options=('!strip' '!debug')

source=(
  "ryujinx-canary-${pkgver}-linux_x64.tar.gz::https://github.com/Methusan105/archconfig/releases/download/ob/ryujinx-canary-${pkgver}-linux_x64.tar.gz"
)
sha256sums=('SKIP')

package() {
  local _install_path="usr/lib"

  # 1. Install program binaries and libraries
  install -dm755 "$pkgdir/$_install_path/$_pkgname"
  find . -maxdepth 1 ! -name '.' ! -name 'PKGBUILD' -exec cp -a {} "$pkgdir/$_install_path/$_pkgname/" \;

  # 2. Symlink executable to /usr/bin (Fixed name to ryujinx-canary)
  install -dm755 "$pkgdir/usr/bin"
  ln -s "/$_install_path/$_pkgname/Ryujinx" "$pkgdir/usr/bin/ryujinx-canary"

  # 3. Desktop launcher
  local _launcher="$pkgdir/usr/share/applications/ryujinx-canary.desktop"
  install -Dm644 /dev/stdin "$_launcher" << 'EOF'
[Desktop Entry]
Type=Application
Name=Ryujinx Canary
Comment=Experimental Nintendo Switch Emulator
Exec=ryujinx-canary %f
Icon=ryujinx-canary
Terminal=false
Categories=Game;Emulator;
MimeType=application/x-nx-rom;
EOF

  # 4. Icon (checks if Logo.png is in the unpacked folder)
  if [ -f "$pkgdir/$_install_path/$_pkgname/Logo.png" ]; then
    install -Dm644 "$pkgdir/$_install_path/$_pkgname/Logo.png" "$pkgdir/usr/share/icons/hicolor/256x256/apps/ryujinx-canary.png"
  fi

  # 5. License
  if [ -f "$pkgdir/$_install_path/$_pkgname/LICENSE.txt" ]; then
    install -Dm644 "$pkgdir/$_install_path/$_pkgname/LICENSE.txt" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
  fi

  # 6. Permissions
  find "$pkgdir" -type d -exec chmod 755 {} \;
  find "$pkgdir" -type f -exec chmod 644 {} \;
  chmod 755 "$pkgdir/$_install_path/$_pkgname/Ryujinx"
  chmod 755 "$pkgdir/$_install_path/$_pkgname/Ryujinx.sh" 2>/dev/null || true
}
