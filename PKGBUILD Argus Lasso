# Maintainer: franzjeger
pkgname=argus-lasso-bin
pkgver=1.5.0
pkgrel=1
pkgdesc="Linux process manager with CPU affinity, ProBalance, Gaming Mode CPU parking, and HW monitoring (precompiled binary)"
arch=(x86_64)
url="https://github.com/franzjeger/argus-lasso"
license=(MIT)
depends=(gcc-libs libxkbcommon wayland)
makedepends=(librsvg)
optdepends=(
  'polkit: required for the privileged helpers (CPU parking, power profile, renice)'
  'zenity: file dialogs on GNOME'
  'kdialog: file dialogs on KDE'
)
provides=(argus-lasso)
conflicts=(argus-lasso)
source=("$pkgname-$pkgver.tar.gz::$url/releases/download/v$pkgver/argus-lasso-$pkgver-x86_64-linux.tar.gz")
sha256sums=('SKIP')

_srcdir="argus-lasso-$pkgver-x86_64-linux"

package() {
  cd "$_srcdir"

  # Install precompiled main binary
  install -Dm755 "argus-lasso" "$pkgdir/usr/bin/argus-lasso"

  # Install optional additional helpers if present in the release tarball
  if [ -f "argus-sensors" ]; then
    install -Dm755 "argus-sensors" "$pkgdir/usr/bin/argus-sensors"
  fi
  if [ -f "libargus_layer.so" ]; then
    install -Dm755 "libargus_layer.so" "$pkgdir/usr/lib/libargus_layer.so"
  fi

  # Desktop file
  install -Dm644 dist/argus-lasso.desktop "$pkgdir/usr/share/applications/argus-lasso.desktop"

  # Tiered icon masters
  install -Dm644 assets/icon.svg "$pkgdir/usr/share/icons/hicolor/scalable/apps/argus-lasso.svg"
  install -Dm644 assets/icon.png "$pkgdir/usr/share/icons/hicolor/256x256/apps/argus-lasso.png"

  for size in 16 22 24 32 48 64 128; do
    case $size in
      16|22|24|32) src=assets/icon-small.svg ;;
      48)          src=assets/icon-medium.svg ;;
      *)           src=assets/icon.svg ;;
    esac

    # Pre-create the directory structure so rsvg-convert can write to it
    install -d "$pkgdir/usr/share/icons/hicolor/${size}x${size}/apps"

    rsvg-convert -w $size -h $size "$src" \
      -o "$pkgdir/usr/share/icons/hicolor/${size}x${size}/apps/argus-lasso.png"
  done

  # Rewrite systemd user service path to system-wide binary location
  sed 's|^ExecStart=%h/.local/bin/argus-lasso|ExecStart=/usr/bin/argus-lasso|' \
    dist/argus-lasso.service > "$srcdir/argus-lasso.service"
  install -Dm644 "$srcdir/argus-lasso.service" \
    "$pkgdir/usr/lib/systemd/user/argus-lasso.service"

  # License
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
