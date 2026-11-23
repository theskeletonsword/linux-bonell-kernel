# SPDX-License-Identifier: GPL-2.0
"""
analyze-qemu-log.py <qemu-debug.log> <System.map> <serial.log> [vmlinux]

Classifies every event QEMU logged with "-d int,cpu_reset":
  CRITICAL  triple fault, #DF, kernel #UD, kernel #GP/#PF without an
            exception-table fixup, #NM/#MC/#XM, any CPU reset
  FAIL      user-mode #UD/#GP (a userland binary using an instruction the
            N450 lacks, for example), kernel panic/oops/WARN on the console
  BENIGN    user #PF (demand paging), kernel #PF on user addresses
            (copy_*_user, exec), faults whose RIP has an __ex_table fixup
            (rdmsr_safe-style probes), kernel #BP (text_poke int3 patching)
  INFO      hardware interrupts / IPIs per vector
RIPs are symbolised with System.map; with vmlinux, __ex_table is parsed so
that faults which the kernel fixes up by design are told apart from bugs.
Exit status: 0 = clean boot to the self test, 1 = problems found.
"""
import bisect
import collections
import re
import struct
import subprocess
import sys

USER_TOP = 0x0000800000000000
EXC = {0: "#DE", 1: "#DB", 2: "NMI", 3: "#BP", 4: "#OF", 5: "#BR", 6: "#UD",
       7: "#NM", 8: "#DF", 10: "#TS", 11: "#NP", 12: "#SS", 13: "#GP",
       14: "#PF", 16: "#MF", 17: "#AC", 18: "#MC", 19: "#XM"}
EV = re.compile(r"^\s*\d+: v=([0-9a-f]{2}) e=([0-9a-f]{4}) i=(\d) cpl=(\d) "
                r"IP=([0-9a-f]{4}):([0-9a-f]+) pc=([0-9a-f]+) SP=[0-9a-f]{4}:[0-9a-f]+"
                r"(?: CR2=([0-9a-f]+))?")


def load_map(path):
    addrs, names = [], []
    with open(path) as f:
        for line in f:
            p = line.split()
            if len(p) >= 3 and p[1] in "tTwW":
                addrs.append(int(p[0], 16))
                names.append(p[2])
    order = sorted(range(len(addrs)), key=addrs.__getitem__)
    return [addrs[i] for i in order], [names[i] for i in order]


TEXT = {}  # _stext/_etext/_sinittext/_einittext from System.map


def in_text(a):
    return TEXT.get("_stext", 0) <= a < TEXT.get("_etext", 1 << 64)


def in_inittext(a):
    return TEXT.get("_sinittext", 1 << 64) <= a < TEXT.get("_einittext", 0)


def sym(maps, a):
    addrs, names = maps
    i = bisect.bisect_right(addrs, a) - 1
    if i < 0 or not (in_text(a) or in_inittext(a)):
        return "<module/non-text 0x%x>" % a
    return "%s+0x%x%s" % (names[i], a - addrs[i], " [init]" if in_inittext(a) else "")


def load_extable(vmlinux):
    """Return the set of instruction addresses that have a fixup."""
    try:
        out = subprocess.run(["objdump", "-h", vmlinux], capture_output=True,
                             text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    for line in out.splitlines():
        p = line.split()
        if len(p) >= 6 and p[1] == "__ex_table":
            size, vma, off = int(p[2], 16), int(p[3], 16), int(p[5], 16)
            break
    else:
        return None
    with open(vmlinux, "rb") as f:
        f.seek(off)
        data = f.read(size)
    insns = set()
    for i in range(0, size - size % 12, 12):  # struct exception_table_entry
        rel, = struct.unpack_from("<i", data, i)
        insns.add((vma + i + rel) & 0xffffffffffffffff)
    return insns


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    log, mapf, serialf = sys.argv[1:4]
    vmlinux = sys.argv[4] if len(sys.argv) > 4 else None
    maps = load_map(mapf)
    for s in ("_stext", "_etext", "_sinittext", "_einittext"):
        if s in maps[1]:
            TEXT[s] = maps[0][maps[1].index(s)]
    extable = load_extable(vmlinux) if vmlinux else None

    crit, fail, benign = [], [], collections.Counter()
    hw = collections.Counter()
    resets = triple = check_exc = 0
    seen_irq = False
    with open(log, errors="replace") as f:
        for line in f:
            if line.startswith("Triple fault"):
                triple += 1
                crit.append("TRIPLE FAULT")
                continue
            if line.startswith("CPU Reset"):
                resets += 1
                continue
            if line.startswith("check_exception"):
                # QEMU logs every exception as "old: X new Y"; X=0xffffffff
                # means nothing was pending. Anything else is an exception
                # raised while delivering another one (the #DF/#TF path).
                if "old: 0xffffffff" not in line:
                    check_exc += 1
                    crit.append("nested exception: " + line.strip())
                continue
            m = EV.match(line)
            if not m:
                continue
            v, err, soft, cpl = int(m[1], 16), int(m[2], 16), m[3] == "1", int(m[4])
            rip, cr2 = int(m[6], 16), (int(m[8], 16) if m[8] else None)
            if v >= 0x20:
                hw["vector 0x%02x%s" % (v, " (soft int)" if soft else "")] += 1
                if not soft:
                    seen_irq = True
                continue
            name = EXC.get(v, "vec%d" % v)
            where = sym(maps, rip) if cpl == 0 else "user 0x%x" % rip
            fixup = extable is not None and rip in extable
            desc = "%s cpl=%d err=0x%x at %s%s" % (
                name, cpl, err, where, " CR2=0x%x" % cr2 if cr2 is not None else "")
            if cpl == 3:
                if v == 14:
                    benign["user #PF (demand paging)"] += 1
                elif v in (3, 1):
                    benign["user %s" % name] += 1
                else:
                    fail.append(desc)
            elif v == 14:
                if cr2 is not None and cr2 < USER_TOP:
                    benign["kernel #PF on user address (uaccess/exec)"] += 1
                elif fixup:
                    benign["kernel #PF with __ex_table fixup"] += 1
                elif (in_inittext(rip) or not seen_irq) and not err & 1:
                    # Not-present fault in __init code or before the first
                    # hardware interrupt: the early IDT
                    # (early_idt_handler_array -> early_make_pgtable) maps
                    # the direct map on demand until the real #PF handler
                    # is installed.
                    benign["early-boot kernel #PF (early_make_pgtable): %s" % where] += 1
                else:
                    crit.append(desc)
            elif v == 3:
                benign["kernel #BP (text_poke/static_call patching)"] += 1
            elif v == 13 and fixup:
                benign["kernel #GP with __ex_table fixup (e.g. rdmsr_safe probe): %s" % where] += 1
            elif v == 6 and fixup:
                benign["kernel #UD with __ex_table fixup: %s" % where] += 1
            else:
                crit.append(desc)

    with open(serialf, errors="replace") as f:
        serial = f.read()
    console_bad = [l for l in serial.splitlines() if re.search(
        r"Kernel panic|Oops|BUG:|WARNING:|invalid opcode|general protection|"
        r"Call Trace|requires the following features|IDT: vector|traps:", l)]
    result = re.search(r"^BT-RESULT (\w+)", serial, re.M)

    print("== QEMU -d int,cpu_reset analysis ==")
    print("exception table: %s" % ("%d fixup sites parsed" % len(extable) if extable else "not available"))
    print("cpu resets logged: %d (power-on reset of each vCPU plus the INIT of"
          " the AP during SMP bring-up)  triple faults: %d  nested exceptions: %d"
          % (resets, triple, check_exc))
    print("-- BENIGN --")
    for k, n in benign.most_common():
        print("  %7d  %s" % (n, k))
    print("-- HW interrupts / IPIs (top) --")
    for k, n in hw.most_common(12):
        print("  %7d  %s" % (n, k))
    print("-- FAIL (user-mode faults) --")
    for d in fail[:40] or ["none"]:
        print("  " + d)
    print("-- CRITICAL --")
    for d in crit[:40] or ["none"]:
        print("  " + d)
    print("-- console problems --")
    for d in console_bad[:40] or ["none"]:
        print("  " + d)
    print("self test: %s" % (result[1] if result else "NOT REACHED"))
    ok = not crit and not fail and not console_bad and result and result[1] == "PASS"
    print("VERDICT: %s" % ("CLEAN" if ok else "PROBLEMS"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
