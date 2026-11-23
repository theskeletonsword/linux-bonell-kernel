#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# bench.sh <runs> <label>:<build-name>:<out-subdir> ...
#
# For each kernel: static metrics (bzImage, vmlinux sections, modules, the
# IRQ entry/exit code path) and <runs> QEMU/TCG boots without -d logging
# (logging would distort timings) on the N450 model, collecting the
# self-test's boot time, memory and timer wake-up latency figures.
#
# TCG executes guest code with a JIT, so absolute times are not those of an
# N450; with identical QEMU settings the comparison between kernels is
# still meaningful, roughly tracking executed instruction counts.
set -euo pipefail
. "$(dirname "$0")/env.sh"
runs=${1:?runs}; shift
R=$OUT/logs/bench
mkdir -p "$R"
: > "$R/results-$ACCEL.tsv"

for spec in "$@"; do
	IFS=: read -r label name sub <<<"$spec"
	D=$OUT/$sub
	echo "== $label ($name, $D)"
	incontainer bash -euo pipefail -c '
		O=/build/$1 D=/out/$2 label=$3
		bz=$(stat -c %s $D/vmlinuz-bonnell)
		read -r text data bss _ < <(size $O/vmlinux | tail -1)
		mods=$(find $D/modroot -name "*.ko" -o -name "*.ko.*" | wc -l)
		modkb=$(du -sk $D/modroot/lib/modules | cut -f1)
		irq_path=0
		for s in asm_common_interrupt error_entry common_interrupt common_interrupt_return \
			 asm_sysvec_apic_timer_interrupt sysvec_apic_timer_interrupt \
			 entry_SYSCALL_64 do_syscall_64; do
			n=$(objdump -d --no-show-raw-insn --disassemble=$s $O/vmlinux | grep -cE "^\s*[0-9a-f]+:\s" || true)
			echo "  insns $s: $n"
			irq_path=$((irq_path + n))
		done
		stub=$(objdump -d --disassemble=irq_entries_start $O/vmlinux | grep -cE "^\s*[0-9a-f]+:\s" || true)
		stub_bytes=$(nm -S $O/vmlinux | awk "\$4==\"irq_entries_start\"{print strtonum(\"0x\"\$2)}")
		echo "  bzImage=$bz text=$text data=$data bss=$bss modules=$mods modroot_kb=$modkb entry_exit_insns=$irq_path irq_stub_insns=$stub irq_stubs_bytes=$stub_bytes"
		printf "%s\tstatic\tbzImage=%s\ttext=%s\tdata=%s\tbss=%s\tmodules=%s\tmodroot_kb=%s\tentry_exit_insns=%s\tirq_stubs_bytes=%s\n" \
			$label $bz $text $data $bss $mods $modkb $irq_path "$stub_bytes" >> /out/logs/bench/results-$4.tsv
	' _ "$name" "$sub" "$label" "$ACCEL"
	for i in $(seq 1 "$runs"); do
		bash "$BONNELL_SCRIPTS/qemu-test.sh" "bench-$ACCEL-$label-$i" "$D/vmlinuz-bonnell" \
			"$D/initramfs-bonnell.cpio.gz" "$BUILD_ROOT/$name/System.map" 0 >/dev/null 2>&1 || true
		S=$OUT/logs/bench-$ACCEL-$label-$i/serial.log
		v() { grep -m1 "^BT $1 " "$S" | cut -d' ' -f3- ; }
		init_s=$(v dmesg_run_init_s)
		ata_s=$(v dmesg_ata_probe_s)
		used=$(grep -m1 '^BT free Mem:' "$S" | awk '{print $5}')
		avail=$(grep -m1 '^BT meminfo' "$S" | sed -n 's/.*MemAvailable: \([0-9]*\).*/\1/p')
		lat=$(grep -m1 '^BT irqlat:' "$S" | sed 's/^BT irqlat: //')
		res=$(grep -m1 '^BT-RESULT' "$S" | cut -d' ' -f2)
		printf "%s\trun%d\tinit_s=%s\tata_probe_s=%s\tfree_used_mb=%s\tmemavail_kb=%s\tselftest=%s\t%s\n" \
			"$label" "$i" "$init_s" "$ata_s" "$used" "$avail" "${res:-none}" "$lat" | tee -a "$R/results-$ACCEL.tsv"
	done
done
