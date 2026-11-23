#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# package.sh [build-name] [out-subdir]
#
# From a finished build in /build/<build-name>, produce under /out[/<sub>]:
#   vmlinuz-bonnell             bzImage
#   System.map-bonnell, config-bonnell
#   modroot/                    make modules_install (stripped, signed)
#   hdrroot/                    make headers_install (+ musl compile test)
#   initramfs-bonnell.cpio.gz   busybox/musl rescue initramfs (sky2, ath9k)
#   atom-bonnell-kernel.tar.gz  all of the above + SHA256SUMS
set -euo pipefail
. "$(dirname "$0")/env.sh"

name=${1:-bonnell}
sub=${2:-}
D=$OUT${sub:+/$sub}
CD=/out${sub:+/$sub}
mkdir -p "$D"
rm -rf "$D/modroot" "$D/hdrroot"

KW=0 bash "$BONNELL_SCRIPTS/kmake.sh" "$name" \
	INSTALL_MOD_PATH="$CD/modroot" INSTALL_MOD_STRIP=1 modules_install
KW=0 bash "$BONNELL_SCRIPTS/kmake.sh" "$name" \
	INSTALL_HDR_PATH="$CD/hdrroot" headers_install

incontainer bash -euo pipefail -c '
	O=/build/$1 D=$2
	cp $O/arch/x86/boot/bzImage $D/vmlinuz-bonnell
	cp $O/System.map $D/System.map-bonnell
	cp $O/.config $D/config-bonnell
	bash /src/bonnell/scripts/test-uapi-musl.sh $D/hdrroot/include
' _ "$name" "$CD"

bash "$BONNELL_SCRIPTS/mkinitramfs.sh" "$name" "$D/modroot" "$D/initramfs-bonnell.cpio.gz"

incontainer bash -euo pipefail -c '
	cd $1
	sha256sum vmlinuz-bonnell initramfs-bonnell.cpio.gz System.map-bonnell config-bonnell > SHA256SUMS
	tar --owner=0 --group=0 --numeric-owner --sort=name -czf atom-bonnell-kernel.tar.gz \
		vmlinuz-bonnell initramfs-bonnell.cpio.gz System.map-bonnell config-bonnell \
		SHA256SUMS modroot hdrroot
	sha256sum atom-bonnell-kernel.tar.gz > atom-bonnell-kernel.tar.gz.sha256
	ls -l vmlinuz-bonnell initramfs-bonnell.cpio.gz atom-bonnell-kernel.tar.gz
	du -sh modroot hdrroot
' _ "$CD"
