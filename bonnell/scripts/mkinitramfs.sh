#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# mkinitramfs.sh <build-name> <modroot> <output.cpio.gz>
#   build-name  kbuild dir under /build (provides usr/gen_init_cpio, release)
#   modroot     INSTALL_MOD_PATH used for modules_install (host path)
#   output      host path of the gzip'ed newc archive
#
# Builds a musl/busybox rescue initramfs that loads sky2 and ath9k. Device
# nodes are emitted through gen_init_cpio, so no mknod/root is needed
# (rootless podman). Runs the assembly inside the hermetic container.
set -euo pipefail
. "$(dirname "$0")/env.sh"

name=${1:?build-name}
modroot=$(realpath "${2:?modroot}")
out=$(realpath -m "${3:?output}")
case "$modroot" in "$OUT"/*) cmod=/out/${modroot#"$OUT"/} ;; *) echo "modroot must be under $OUT" >&2; exit 1 ;; esac
case "$out" in "$OUT"/*) cout=/out/${out#"$OUT"/} ;; *) echo "output must be under $OUT" >&2; exit 1 ;; esac

incontainer bash -euo pipefail -c '
	O=/build/$1 MODROOT=$2 OUTPUT=$3 want=$4
	KREL=$(cat $O/include/config/kernel.release)
	S=/tmp/initramfs
	rm -rf $S; mkdir -p $S
	cd $S
	mkdir -p bin sbin usr/bin usr/sbin proc sys dev run tmp mnt newroot etc root lib/modules/$KREL

	# busybox (static, musl) and its applet links
	install -m 0755 /bin/busybox.static bin/busybox
	for a in $(/bin/busybox.static --list-full); do
		[ "$a" = bin/busybox ] && continue
		mkdir -p "$(dirname "$a")"
		ln -sf /bin/busybox "$a"
	done
	install -m 0755 /src/bonnell/initramfs/init init
	install -m 0755 /src/bonnell/initramfs/bonnell-selftest bin/bonnell-selftest
	gcc -O2 -static -pthread -Wall -Wextra -Werror -o usr/bin/irqlat /src/bonnell/tools/irqlat.c
	strip usr/bin/irqlat
	printf "root:x:0:0:root:/root:/bin/sh\n" > etc/passwd
	printf "root:x:0:\ntty:x:5:\n" > etc/group

	# Module closure of what /init and the self test load
	# (INITRAMFS_MODULES, default "sky2 ath9k overlay loop").
	# -a: without it modprobe treats every name after the first as a
	# module parameter of the first one.
	modprobe -a -d $MODROOT -S $KREL --show-depends $want |
	while read -r kind path _; do
		[ "$kind" = insmod ] || continue
		rel=${path#$MODROOT/}
		mkdir -p "$(dirname "$rel")"
		cp "$path" "$rel"
	done
	for f in modules.order modules.builtin modules.builtin.modinfo; do
		cp $MODROOT/lib/modules/$KREL/$f lib/modules/$KREL/
	done
	depmod -b $S $KREL
	echo "initramfs modules: $(find lib/modules -name "*.ko" -exec basename {} .ko \; | sort | tr "\n" " ")"
	for m in $want; do
		modprobe -d $S -S $KREL --show-depends $m >/dev/null ||
			{ echo "initramfs: $m missing" >&2; exit 1; }
	done

	cat > /tmp/nodes.spec <<-EOF
	nod /dev/console 0600 0 0 c 5 1
	nod /dev/null 0666 0 0 c 1 3
	EOF
	cd $O
	/src/usr/gen_initramfs.sh -o /tmp/initramfs.cpio -u 0 -g 0 $S /tmp/nodes.spec
	gzip -9 -n -c /tmp/initramfs.cpio > $OUTPUT
	ls -l $OUTPUT
' _ "$name" "$cmod" "$cout" "${INITRAMFS_MODULES:-sky2 ath9k overlay loop}"
