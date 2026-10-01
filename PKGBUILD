pkgname=opennow
_pkgname=OpenNOW
pkgver=1.0.1
_pkgver=$pkgver
pkgrel=1
pkgdesc="custom GeForce Now client"
url="https://opennow.zortos.me/"
license=('MIT')
depends=('gtk3' 'cairo' 'pango' 'mesa' 'dbus' 'libx11' 'at-spi2-core' 'hicolor-icon-theme' 'nss' 'nspr' 'alsa-lib'
	'electron43>=43.3.0' 'gstreamer' 'gst-plugins-base-libs' 'gst-plugins-bad-libs' 'gst-libav' 'gst-plugins-good' 'gst-plugins-bad' 'gst-plugins-ugly'
	'qt6-base' 'qt6-declarative' 'vulkan-icd-loader' 'wayland')
makedepends=('npm' 'imagemagick' 'libxcrypt-compat' 'cargo' 'cmake' 'clang' 'llvm' 'nasm' 'vulkan-headers' 'wayland-protocols')
options=(!strip !debug)
provides=('opennow')
conflicts=('opennow-appimage')
arch=('x86_64')

source=(opennow-${pkgver}.tar.gz::https://github.com/OpenCloudGaming/OpenNOW/archive/refs/tags/v${_pkgver}.tar.gz
	opennow.desktop opennow)

sha256sums=('SKIP'
            'SKIP'
            'SKIP')

prepare() {
	cd "$_pkgname-$_pkgver"
	export ELECTRON_SKIP_BINARY_DOWNLOAD=1
	sed -i -e '/ensure-electron-installed.mjs/d' package.json
	npm install --cache "${srcdir}/npm/cache"
}

build() {
	cd "$_pkgname-$_pkgver"

	export ELECTRON_SKIP_BINARY_DOWNLOAD=1
	export CC=clang
	export CXX=clang++
	export CFLAGS=""
	export LDFLAGS=""

	npm run build
	npm run native:build

	# Generate icons
	mkdir -p hicolor
	for i in 8x8 16x16 20x20 22x22 24x24 32x32 36x36 40x40 42x42 48x48 64x64 72x72 80x80 96x96 128x128 192x192 256x256 384x384 512x512 1024x1024; do
		_dir="hicolor/${i}/apps"
		mkdir -p "${_dir}"
		magick logo.png -resize "${i}" "${_dir}/opennow.png" 2>/dev/null || true
	done
}

package() {
	cd "$_pkgname-$_pkgver"

	# Opprett korrekt katalogstruktur i pakken
	mkdir -p "${pkgdir}/usr/lib/opennow"
	mkdir -p "${pkgdir}/usr/lib/opennow/bin"
	mkdir -p "${pkgdir}/usr/bin"

	# 1. Kopier kun de reelle kjørebare hovedfilene fra build/opennow-qt
	local _build_dir="build/opennow-qt"

	if [ -d "$_build_dir" ]; then
		# Hovedbinærer
		cp -a "$_build_dir/opennow-qt" "${pkgdir}/usr/lib/opennow/bin/" 2>/dev/null || true
		cp -a "$_build_dir/opennow-core" "${pkgdir}/usr/lib/opennow/bin/" 2>/dev/null || true
		cp -a "$_build_dir/opennow-streamer" "${pkgdir}/usr/lib/opennow/bin/" 2>/dev/null || true
		cp -a "$_build_dir/opennow-update-helper" "${pkgdir}/usr/lib/opennow/bin/" 2>/dev/null || true
		cp -a "$_build_dir/libopennow_streamer_ffi.so" "${pkgdir}/usr/lib/opennow/bin/" 2>/dev/null || true

		# Nødvendige ressurser/QML dersom de finnes
		for _folder in OpenNOW qmltypes hdr-protocols input-protocols; do
			if [ -d "$_build_dir/$_folder" ]; then
				cp -a "$_build_dir/$_folder" "${pkgdir}/usr/lib/opennow/"
			fi
		done
	fi

	# 2. Strip binærfilene manuell for å redusere filstørrelsen drastisk
	strip --strip-unneeded "${pkgdir}/usr/lib/opennow/bin/"* 2>/dev/null || true

	# 3. Lag en ren wrapper i /usr/bin/opennow
	cat << 'EOF' > "${pkgdir}/usr/bin/opennow"
#!/bin/sh
export LD_LIBRARY_PATH="/usr/lib/opennow/bin:$LD_LIBRARY_PATH"
exec /usr/lib/opennow/bin/opennow-qt "$@"
EOF
	chmod +x "${pkgdir}/usr/bin/opennow"

	# 4. Lisens, skrivebordsfil og ikoner
	install -m644 -D -t "${pkgdir}/usr/share/licenses/${pkgname}/" LICENSE
	install -m644 -D -t "${pkgdir}/usr/share/applications/" "${srcdir}/opennow.desktop"

	mkdir -p "${pkgdir}/usr/share/icons"
	cp -a hicolor "${pkgdir}/usr/share/icons"
}
