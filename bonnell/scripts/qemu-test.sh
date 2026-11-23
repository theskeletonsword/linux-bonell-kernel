#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# qemu-test.sh <label> <kernel> <initrd> <System.map> [debug=1|0] [cpu] [extra cmdline]
#
# Boots kernel+initramfs under QEMU/TCG (inside the container) on a model of
# perex's Atom N450: QEMU "n270" is family 6 model 0x1c (Bonnell) with SSSE3
# and MOVBE; add the bits the N450 has (lm, nx, syscall, cx16, lahf_lm,
# pse, vme).
# TCG only decodes instructions whose CPUID bit is exposed, so anything the
# N450 lacks (POPCNT, SSE4, AVX...) raises #UD here exactly as on hardware.
#
# Kernel cmdline: console=ttyS0 nokaslr earlyprintk=serial,ttyS0,115200
# panic=-1 bonnell.autotest=1; -no-reboot turns a panic or triple fault into
# a QEMU exit. With debug=1, "-d int,cpu_reset -D /tmp/qemu-debug.log" is
# captured and analysed (analyze-qemu-log.py).
#
# Paths are host paths under $OUT or $BUILD_ROOT. Results: $OUT/logs/<label>/
set -euo pipefail
. "$(dirname "$0")/env.sh"

label=${1:?label} kernel=$(realpath "${2:?kernel}") initrd=$(realpath "${3:?initrd}")
sysmap=$(realpath "${4:?System.map}") debug=${5:-1}
# QEMU's n270 model also lacks PSE and VME, which the N450 has (without PSE
# no THP, which skews memory figures between kernels).
cpu=${6:-n270,+lm,+nx,+syscall,+cx16,+lahf-lm,+pse,+vme}
extra=${7:-}

c() { # host path -> container path
	case "$1" in
	"$OUT"/*) echo "/out/${1#"$OUT"/}" ;;
	"$BUILD_ROOT"/*) echo "/build/${1#"$BUILD_ROOT"/}" ;;
	"$SRC"/*) echo "/src/${1#"$SRC"/}" ;;
	*) echo "path not visible in container: $1" >&2; exit 1 ;;
	esac
}
mkdir -p "$OUT/logs/$label"

incontainer bash -uo pipefail -c '
	label=$1 K=$2 I=$3 MAP=$4 debug=$5 cpu=$6 extra=$7 tmo=$8
	L=/out/logs/$label
	rm -f $L/serial.log /tmp/qemu-debug.log
	dbg=()
	[ "$debug" = 1 ] && dbg=(-d int,cpu_reset -D /tmp/qemu-debug.log)
	# ext4 test disk on an AHCI controller: exercises perex root path
	# (ahci -> libata -> sd -> ext4, all built in).
	mkdir -p /tmp/e4root && echo bonnell-ext4-marker > /tmp/e4root/marker
	mkfs.ext4 -q -F -L bonnell-test -d /tmp/e4root /tmp/e4.img 64M
	t0=$(date +%s.%N)
	timeout $tmo qemu-system-x86_64 -machine pc -accel tcg,thread=multi \
		-cpu "$cpu" -smp 2,sockets=1,cores=1,threads=2 -m 1024 \
		-nodefaults -no-reboot -display none -monitor none \
		-serial file:$L/serial.log \
		-device ahci,id=ahci0 -drive id=d0,file=/tmp/e4.img,if=none,format=raw \
		-device ide-hd,drive=d0,bus=ahci0.0 \
		-kernel $K -initrd $I \
		-append "console=ttyS0,115200 nokaslr earlyprintk=serial,ttyS0,115200 panic=-1 bonnell.autotest=1 $extra" \
		"${dbg[@]}"
	rc=$?
	t1=$(date +%s.%N)
	echo "qemu_exit=$rc wall_s=$(echo "$t1 - $t0" | bc)" > $L/run.txt
	if [ "$debug" = 1 ]; then
		VM=$(dirname $MAP)/vmlinux; [ -f $VM ] || VM=
		python3 -I /src/bonnell/scripts/analyze-qemu-log.py /tmp/qemu-debug.log $MAP $L/serial.log $VM > $L/analysis.txt
		arc=$?
		ls -l /tmp/qemu-debug.log | awk "{print \"qemu_debug_log_bytes=\" \$5}" >> $L/run.txt
		zstd -q -f -19 -T0 /tmp/qemu-debug.log -o $L/qemu-debug.log.zst
		echo "analysis_exit=$arc" >> $L/run.txt
	fi
	cat $L/run.txt
	grep -E "^BT-RESULT" $L/serial.log || echo "BT-RESULT MISSING (did not reach the self test)"
' _ "$label" "$(c "$kernel")" "$(c "$initrd")" "$(c "$sysmap")" "$debug" "$cpu" "$extra" \
	"${QEMU_TIMEOUT:-900}"
