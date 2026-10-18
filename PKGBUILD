# Maintainer: Your Name <youremail@domain.com>
pkgname=frame-bin
pkgver=1.0.0
pkgrel=1
pkgdesc="Native media conversion utility built in Rust for FFmpeg operations"
arch=('x86_64')
url="https://github.com/66HEX/frame"
license=('Custom')
depends=('glibc' 'ffmpeg' 'libxau' 'libxdmcp' 'brotli' 'expat' 'fontconfig' 'freetype2' 'libpng' 'libxcb' 'libxkbcommon' 'libxkbcommon-x11' 'zlib')
provides=('frame')
conflicts=('frame')
source=("/home/methu/Nedlastinger/frame-linux-x86_64.tar.gz")
sha256sums=('SKIP')

package() {
    cd "$srcdir"

    # Find the extracted folder dynamically
    local ext_dir
    ext_dir=$(find . -maxdepth 1 -type d ! -name '.' ! -name '..')

    if [ -n "$ext_dir" ]; then
        cd "$ext_dir"
    fi

    # Create destination directories (excluding lib)
    install -dm755 "$pkgdir/usr/bin"
    install -dm755 "$pkgdir/usr/share"

    # Copy only binaries and shared assets (skipping bundled system libraries)
    [ -d "bin" ] && cp -av bin/* "$pkgdir/usr/bin/"
    [ -d "share" ] && cp -av share/* "$pkgdir/usr/share/"

    # Install license if it exists
    if [ -f "licenses.md" ]; then
        install -Dm644 "licenses.md" "$pkgdir/usr/share/licenses/$pkgname/licenses.md"
    fi
}
