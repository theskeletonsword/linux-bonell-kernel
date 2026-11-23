# Linux 7.3.4 for Intel Atom Bonnell (N450) — `perex`

> **ES** · Kernel Linux 7.3.4 compilado, endurecido y optimizado para la
> microarquitectura **Intel Atom Bonnell** (Atom N450 de la máquina `perex`,
> Ethernet Marvell `sky2`, Wi-Fi Qualcomm Atheros `ath9k`), construido de forma
> reproducible en un contenedor **Alpine Linux (musl)** con Podman y validado
> en QEMU contra triple faults.
>
> **EN** · Linux 7.3.4 built, hardened and tuned for the **Intel Atom Bonnell**
> micro-architecture (the Atom N450 of the machine `perex`, Marvell `sky2`
> Ethernet, Qualcomm Atheros `ath9k` Wi-Fi), reproducibly built in an
> **Alpine Linux (musl)** container with Podman and validated in QEMU against
> triple faults.

---

## Credits / Créditos

This is a small downstream tree of the **Linux kernel**. Virtually all of the
code is the work of **Linus Torvalds**, who created Linux and maintains the
mainline tree, and of the thousands of **upstream kernel developers and
maintainers** whose names are in `CREDITS`, `MAINTAINERS` and the git history
of the official repository, supported by **The Linux Foundation**. Atheros /
Qualcomm Atheros wrote and license the `ath`/`ath9k` drivers; Marvell and
Stephen Hemminger the `sky2` driver. Thank you.

Este árbol es un derivado pequeño del **kernel Linux**. Prácticamente todo el
código es obra de **Linus Torvalds**, creador de Linux y mantenedor de la rama
principal, y de los miles de **desarrolladores y mantenedores upstream**
(`CREDITS`, `MAINTAINERS`), con el apoyo de **The Linux Foundation**. Gracias.

Upstream: <https://kernel.org> · <https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git>

## License / Licencia

Distributed, like the upstream kernel, under the **GNU General Public License
version 2** — `SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note`
(see `COPYING`, `LICENSES/` and the full GPLv2 text in [`LICENSE`](LICENSE)).

* Every modified file keeps its original `SPDX-License-Identifier` line; no
  license line was added, removed or changed (`git diff 07b22d9 HEAD | grep
  SPDX` is empty).
* `drivers/net/wireless/ath/ath.h`, `ath9k/main.c` and `ath9k/Makefile` are
  **ISC**-licensed by their authors (a permissive, GPL-compatible license).
  Their headers are kept verbatim: relabelling them as GPL-2.0 would misstate
  their authors' license. The combined work is distributed under GPLv2.
* New files in `bonnell/` are `GPL-2.0`.

---

## Target hardware / Hardware objetivo

| | perex |
|---|---|
| CPU | Intel Atom N450 "Pineview", **Bonnell** core, family 6 model 0x1c, 1 core / 2 threads (HT), 1.66 GHz, in-order dual-issue |
| Caches | **32 KiB L1i + 24 KiB L1d** per core, 512 KiB L2, 64-byte lines (note: the L1 *data* cache of Bonnell is 24 KiB, not 32 KiB) |
| ISA | x86-64, SSE…SSSE3, **MOVBE**, CX16, LAHF/SAHF — **no** POPCNT, SSE4.x, AVX, AES-NI, VT-x |
| Ethernet | Marvell Yukon-2 (`sky2`) |
| Wi-Fi | Qualcomm Atheros AR9285-class PCI (`ath9k`, AR9002 family, non-EDMA) |
| Storage | ICH7-M/NM10 AHCI SATA, ext4 root |
| OS | Alpine Linux (musl); stock kernel was 6.18.63-lts (`bonnell/configs/perex-alpine-stock.config`) |

---

## Resumen en español

**Qué es.** Linux 7.3.4 upstream (primer commit, sin modificar) más una
docena de commits pequeños y revisables (`git log --oneline 07b22d9..`) para el Atom N450 de `perex`. La documentación
técnica detallada, en inglés, está en las secciones siguientes.

**Optimización para Bonnell.**
- Nueva opción `CONFIG_X86_MARCH_BONNELL`: `-march=bonnell -mtune=bonnell`.
  Linux 6.15 eliminó `MATOM` para 64-bit.
- El kernel sigue sin usar SSE/AVX/AVX2/AVX-512: los `-mno-*` de
  `arch/x86/Makefile` prevalecen sobre `-march`. Está verificado con una sonda
  vectorizable a `-O3`.
- GCC emite MOVBE con `-march=bonnell`, así que MOVBE pasa a ser obligatorio.
  En una CPU sin MOVBE el arranque se niega con un mensaje claro, sin `#UD` ni
  triple fault.
- `-O3` sólo en `net/`, `sky2` y `ath9k`, detrás de `CONFIG_X86_BONNELL_HOT_O3`.
  `arch/x86/boot` sigue en `-O2`. El `-O3` global se evaluó: arranca, pero
  añade un 10 % de código sin ganancia medible.

**Endurecimiento.**
- Activado: `-fstack-protector-strong`, `HARDENED_USERCOPY`, `FORTIFY_SOURCE`,
  `STRICT_KERNEL_RWX`/`STRICT_MODULE_RWX`, `SLAB_FREELIST_RANDOM`/`HARDENED`,
  `SHUFFLE_PAGE_ALLOCATOR`, KASLR y módulos firmados.
- Superficie de ataque eliminada: ABI de 32 bits, `modify_ldt`, vsyscall e
  `ioperm`.
- Auditoría TOCTOU de los ficheros modificados: no hay ninguna doble lectura
  de memoria de usuario.

**IDT/GDT.**
- Ya estaban alineadas a página, lo que cubre los 64 B. No se movieron; unos
  `static_assert` garantizan ese layout.
- En el arranque se verifica que #DF, NMI, #DB y #MC tienen su pila IST.
- El camino IRQ/syscall baja de 598 a 401 instrucciones (−33 %) y los stubs
  de IRQ ocupan la mitad.

> ⚠ **Mitigaciones de ejecución especulativa (incluido KPTI) compiladas
> fuera.** Es correcto sólo en Bonnell, que el propio kernel clasifica como
> `NO_SPECULATION`: las 19 vulnerabilidades salen "Not affected". **No uses
> este kernel en otra CPU.** Si arranca en una CPU especulativa, avisa y se
> marca con taint `S`.

**Código muerto.**
- Se pasó de 1811 a 1480 opciones built-in. Fuera: CPUs AMD/Centaur/Zhaoxin,
  invitado Xen/KVM, NUMA, IOMMU, buses legacy, depuración.
- Se mantienen ext4, tmpfs, devtmpfs, proc, sysfs, overlayfs y todo el
  hardware de perex.
- El build W=1 con `-Werror` demuestra que no quedan funciones ni variables
  estáticas sin usar.
- No se borró código fuente: lo que se compila lo decide la `.config`, y
  conservar el árbol completo permite rebasear sobre 7.3.y.

**Red.**
- `sky2`: sin `DIV` por trama, prefetch RX en 3 etapas y `napi_weight`
  ajustable (por defecto 64).
- `ath9k`: `ath_dbg()` ya no evalúa sus argumentos, lo que elimina una lectura
  PCI en cada pasada de TX.
- Regulatorio y cifrado hardware intactos.
- BBR + fq por defecto; netfilter sólo con nftables, como módulos.

**Avisos y musl.**
- Todo el kernel compila con 0 avisos con W=1 (el `-Wextra` curado del
  kernel) más `CONFIG_WERROR`.
- Se corrigieron 3 problemas upstream: `__printf` en bpf, truncado en
  elantech y `arch/x86/tools`, que no compilaba en musl.
- `headers_install`: 1025 cabeceras probadas contra musl.

**Validación.**
- En QEMU/TCG, con un modelo del N450 (familia 6, modelo 0x1c) y
  `-d int,cpu_reset`: 0 triple faults y 0 `#UD`/`#GP`/`#DF` del kernel, y el
  selftest pasa.
- Medidas con TCG y KVM: `bzImage` −32 %, `.text` −27 % y arranque hasta
  `/init` −22 % (KVM, sin contar el sondeo SATA).
- La latencia real hay que medirla en perex con `irqlat`, incluido en la
  initramfs.

**Compilar e instalar:** ver [Build](#build--compilación-podman--alpine-musl)
e [Install](#install-on-perex-alpine--instalación-en-perex).

### Commits

```
07b22d94b Import Linux 7.3.4 (upstream release, unmodified)
d3da9f4be x86/cpu: Add CONFIG_X86_MARCH_BONNELL for Intel Atom Bonnell (N450)
de6b74803 x86/idt, x86/cpu: Lock in IDT/GDT cache-line layout, verify IST gates
e762d0425 bpf: Add __printf() to bpf_diag_source()
bb92a288e Input: elantech - size tp_phys for the longest serio phys string
5a6d42662 net: sky2: Remove per-frame division, pipeline Rx prefetch, napi_weight
a309c9ce7 wifi: ath: Do not evaluate ath_dbg() arguments when ATH_DEBUG=n
5a0e37788 wifi: ath9k: Mark fatal/watchdog/reset interrupt paths unlikely()
6ca495dce net, sky2, ath9k: Build the packet paths at -O3 (X86_BONNELL_HOT_O3)
658bd6990 x86/tools: Fix insn_sanity/insn_decoder_test build on musl
fcbb35e1a bonnell: Add reproducible Alpine/musl build, packaging and QEMU test tooling
a4924b192 Add README.md, LICENSE (GPLv2 text) and ignore local outputs
15699a25f bonnell: Add KVM measurement mode, fix self-test false positives
```

---

## What was changed / Qué se cambió

`git log --oneline 07b22d9..` — the first commit is the **unmodified**
upstream 7.3.4 import, so every change is reviewable on its own.

### 1. Compiler flags for Bonnell (`arch/x86`)

* **`CONFIG_X86_MARCH_BONNELL`** (new, `arch/x86/Kconfig.cpu`): Linux 6.15
  removed `MATOM` for 64-bit builds, so this adds `-march=bonnell
  -mtune=bonnell` back for x86_64 (`arch/x86/Makefile`).
* **No SIMD in the kernel:** GCC keeps ISA bits that were disabled explicitly
  (`-mno-sse -mno-mmx -mno-sse2 -mno-avx …`) even though `-march=bonnell` comes
  later, so neither SSE nor AVX/AVX2/AVX-512 can be emitted. Verified by
  `bonnell/scripts/audit-toolchain.sh` (`-Q --help=target` and an
  auto-vectorisable probe at `-O3`: no `%xmm/%ymm/%zmm`, no VEX, no POPCNT).
* **MOVBE becomes a required CPU feature** (`Kconfig.cpufeatures`), because
  `-march=bonnell` emits it. A CPU without MOVBE is refused cleanly by the boot
  code instead of crashing on a `#UD` later — tested:
  `This kernel requires the following features not present on the CPU: movbe`.
* Module vermagic is tagged **`BONNELL`**, so these modules cannot be loaded
  into a generic kernel (which might be running on a CPU without MOVBE).

### 2. `-O3`: evaluated, applied selectively

* **`CONFIG_X86_BONNELL_HOT_O3`** (default y) builds `net/` (every
  subdirectory), `drivers/net/ethernet/marvell/sky2.c` and
  `drivers/net/wireless/ath/ath9k/` with `-O3`. Everything else, **including
  `arch/x86/boot` and the decompressor, stays at `-O2`** (they reset
  `KBUILD_CFLAGS` and never see `-O3`).
* All `-O3` objects are clean under W=1 + `-Werror` (no per-object fallback
  was needed).
* Cost: text grows (sky2.o +29 %, `net/core/dev.o` +15 %, `skbuff.o` +14 %,
  `tcp_input.o` +15 %, ath9k.o +11 %). Bonnell's L1i is 32 KiB, so the gain must
  be measured on the real machine; build with `HOT_O3=n` to compare.
* Global `-O3`: see [Measurements](#measurements--mediciones).

### 3. Memory / usercopy hardening (`.config`, verified by `verify-config.sh`)

`STACKPROTECTOR_STRONG` (`-fstack-protector-strong`), `HARDENED_USERCOPY`,
`FORTIFY_SOURCE`, `STRICT_KERNEL_RWX`, `STRICT_MODULE_RWX`,
`SLAB_FREELIST_RANDOM`, `SLAB_FREELIST_HARDENED`, `SHUFFLE_PAGE_ALLOCATOR`,
`LIST_HARDENED` + `BUG_ON_DATA_CORRUPTION`, `VMAP_STACK`, KASLR
(`RANDOMIZE_BASE`, `RANDOMIZE_MEMORY`), signed modules (SHA-256). Kept from
Alpine's config: `INIT_STACK_ALL_ZERO`, `INIT_ON_ALLOC_DEFAULT_ON`
(`init_on_alloc=0` turns it off at boot), `ZERO_CALL_USED_REGS`,
`RANDOMIZE_KSTACK_OFFSET`, GCC latent-entropy plugin, Landlock/Yama/lockdown.
Attack surface removed: 32-bit compat ABI (`IA32_EMULATION`), `modify_ldt`
and 16-bit segments, the vsyscall page, `ioperm`/`iopl`, `TIOCSTI`, uevent
helper, ACPI table upgrade from initrd.

**TOCTOU / double fetch:** every `copy_from_user`/`get_user`/… in the files
touched was audited. `sky2.c` has none (`sky2_ioctl()` works on the kernel
copy of `ifreq` that `dev_ioctl()` already made); the `ath9k` functions that
were modified have none either; the 52 user-access sites elsewhere in ath9k
(debugfs, compiled out here) read each user buffer once.

### 4. IDT / GDT and the interrupt path

* **Alignment was already optimal** and is now *enforced* rather than
  changed: the IDT (`idt_table`, page-aligned and mapped read-only in the CPU
  entry area) and the per-CPU GDT are page-aligned, so no 16-byte gate
  straddles a 64-byte line, the IRQ stubs (`IDT_ALIGN` bytes) never straddle a
  line, and every descriptor the CPU reads on interrupt delivery and IRET
  (kernel CS/DS, user CS/DS, compat CS) is in the first GDT line.
  `static_assert`s in `idt.c` and `common.c` break the build if this ever
  regresses. Moving descriptors would only have added triple-fault risk.
* **IST stacks untouched** (#DF, NMI, #DB, #MC) and now *verified* at boot by
  `idt_check_ist_gates()`: a #DF without IST on an overflowed stack is a triple
  fault.
* **IRQ fast path:** what is removed at compile time on this kernel: KPTI CR3
  switches, IBRS/UNRET/IBPB entry code, retpoline and return thunks, SLS
  padding and call-depth tracking (`CPU_MITIGATIONS=n`), the ESPFIX64 test on
  every IRET to user mode (`X86_16BIT=n`), ENDBR64 at every entry and the
  16-byte stubs (IBT off → 8-byte `IDT_ALIGN` stubs, twice as many per line),
  FRED alternatives, the compat `int $0x80` gate, nohz_full context tracking
  and per-IRQ `sched_clock()` reads (IRQ time accounting), `PARAVIRT`
  indirections (bare metal only). The runtime-patched `VERW`/BHB/`lfence`
  alternatives are left alone: on Bonnell they are already NOPs and removing
  them would make sysfs lie on other CPUs.

> ### ⚠ Speculative-execution mitigations are compiled out
> `CONFIG_CPU_MITIGATIONS=n`. This is **safe on Bonnell only**: it is an
> in-order core and the kernel's own `cpu_vuln_whitelist` lists
> `INTEL_ATOM_BONNELL` as `NO_SPECULATION`, so a stock kernel would report
> every issue as *Not affected* and patch the mitigations out at boot anyway
> (QEMU `n270` model: 19/19 *Not affected*). Compiling them out removes the
> code and the `-fno-jump-tables` penalty.
> **Do not run this kernel on another CPU.** If it boots on a speculative CPU
> it prints `Bonnell kernel without CPU mitigations on a speculative CPU …
> NOT mitigated` and taints itself (`S`), tested with QEMU `Nehalem,+movbe`.
> KPTI in particular was disabled on purpose, for this controlled target.

### 5. Dead code / Código muerto

* `.config`: from Alpine's stock config, `localmodconfig` with perex's
  `lsmod`, then a documented fragment (`bonnell/configs/bonnell.config`):
  **1811 → 1480 built-in options**. Purged: AMD/Hygon/Centaur/Zhaoxin CPU
  support, Xen/KVM/Hyper-V guest code, NUMA, IOMMUs, x2APIC, Bay Trail/Cherry
  Trail SoC drivers, ISA DMA, MD RAID, SPI, legacy partition tables, TV/radio
  media, MPTCP/MPLS/CAN/DCB, xtables, debug options (`DEBUG_LIST`,
  `DYNAMIC_DEBUG`, function tracer, kmemleak, mmiotrace).
  Kept: `ext4` (built in, also serves ext2), `tmpfs`, `devtmpfs`, `proc`,
  `sysfs`, `overlayfs`, and everything perex loads (`bonnell/configs/perex.lsmod`):
  i915, HDA audio, uvcvideo, ath9k, sky2, AHCI, USB, iTCO, coretemp…
* Code: the W=1 `-Werror` build (which includes `-Wunused-function`,
  `-Wunused-but-set-variable`, `-Wunused-const-variable`) proves there is no
  unused static function or variable left in this configuration. No exported
  symbol (`EXPORT_SYMBOL*`) was removed. Dead *work* removed in hot paths:
  `ath_dbg()` arguments (MMIO reads) are no longer evaluated with
  `ATH_DEBUG=n`, and sky2 no longer divides per frame.

### 6. Network drivers and stack

* **sky2:** per-frame `% rx_pending` (a 32-bit `DIV`) replaced by
  compare-and-wrap; software-pipelined RX prefetch (ring info of slot n+3,
  `sk_buff` lines of n+2, packet data of n+1, never dereferencing a line that
  was not prefetched one frame earlier, which an in-order core requires);
  NAPI weight kept at 64 by design (amortises the uncached MMIO reads of each
  poll, keeps the stack hot in L1i) and exposed as the read-only module
  parameter `napi_weight=8..64`; per-frame debug tests marked `unlikely()`.
* **ath9k:** `ath_dbg()` no longer evaluates its arguments when
  `ATH_DEBUG=n`, which removes an uncached PCI read
  (`ath9k_hw_gettxbuf()`) from every TX completion pass; `unlikely()` on the
  fatal/watchdog/reset interrupt paths. **Regulatory** (`regd.c`, `regd.h`,
  `regd_common.h`) and **hardware crypto / key cache** (`key.c`, keycache
  helpers) were not touched.
* **Stack:** `TCP_CONG_BBR` + `DEFAULT_TCP_CONG="bbr"`, `NET_SCH_FQ` as default
  qdisc (pacing for BBR), `FQ_CODEL`, GRO/GSO (always on), RPS/XPS, BQL, busy
  polling. Netfilter reduced to **nftables only, as modules** (stateful
  firewall/NAT still available); no legacy xtables/iptables/ebtables, no
  netdev ingress/egress hooks. With no ruleset loaded, the remaining hooks are
  static keys.

### 7. `-Wall -Wextra -Werror`

The whole kernel (1480 built-ins + 112 modules) builds with **0 warnings**
under `W=1` + `CONFIG_WERROR=y` (`-Werror` for C, objtool and the linker;
section mismatches are errors too). `W=1` *is* the kernel's curated
`-Wextra` (`scripts/Makefile.warn`). A raw `KCFLAGS=-Wextra` is not used
because it enables `-Wunused-parameter`, `-Wsign-compare` and
`-Wmissing-field-initializers`, which the kernel deliberately disables (callback
signatures, designated initialisers), and would bury real problems under
thousands of false positives. Two upstream issues surfaced and were fixed:
`bpf_diag_source()` lacked `__printf()`, and elantech's `tp_phys` could
truncate (a third, musl-only, is in the next section).

### 8. musl compatibility

The whole build runs on musl: host tools (`fixdep`, `kconfig`, `modpost`,
`objtool` with libelf, `sign-file` with OpenSSL 3, GCC plugins) build and run
there. One real glibc dependency was found and fixed: with
`CONFIG_X86_DECODER_SELFTEST=y` (enabled in Alpine's own config), upstream
7.3.4 does **not** build on musl, because `arch/x86/tools/insn_sanity` and
`insn_decoder_test` pull raw `include/uapi` headers that use
`__attribute_const__`, which glibc happens to define and musl does not. The fix
includes `tools/include/linux/compiler.h`. Afterwards the decoder self test
checks 3 205 109 instructions of the `-march=bonnell` vmlinux, and
`insn_sanity` 1 000 000 random instructions, both without errors.
`make headers_install` (which needs `rsync`) produces 1025 headers with no glibc-private
dependency, and `CONFIG_UAPI_HEADER_TEST` compile-tests every one of them
against musl during the build. `bonnell/scripts/test-uapi-musl.sh` also
checks the mixes real userland uses (netlink, nl80211/wireless, input, v4l2,
ethtool, netinet): all compile. Known and inherent: `<sys/sysinfo.h>` +
`<linux/kernel.h>` redefine `struct sysinfo` (`libc-compat.h` only recognises
glibc; Alpine patches this in its own `linux-headers` package); a few ioctl
macros (`_IOC*`, `SIOCGSTAMP`) are defined by both with different text and the
same value (a GCC warning, not an error).

---

## Build / Compilación (Podman + Alpine musl)

Host: any Linux with Podman (developed on WSL2 Debian, 32 threads, 31 GiB).

```sh
git clone <this repo> linux-bonnell && cd linux-bonnell
# 1. hermetic toolchain (Alpine 3.24.4 pinned by digest: GCC 15.2, musl 1.2.6)
podman build -t localhost/bonnell-kbuild:3.24.4 -f bonnell/container/Containerfile bonnell/container
bash bonnell/scripts/incontainer.sh bash bonnell/scripts/audit-toolchain.sh   # AUDIT: PASS
# 2. .config: perex stock -> localmodconfig(perex.lsmod) -> bonnell.config -> verify
bash bonnell/scripts/mkconfig.sh bonnell      # "all N requested symbols applied"
#    (or: cp arch/x86/configs/bonnell_defconfig ~/kbuild/bonnell/.config + olddefconfig)
# 3. build out of tree in ~/kbuild/bonnell, W=1 + -Werror, -j16 (JOBS=24 max)
bash bonnell/scripts/kmake.sh bonnell all
# 4. deliverables in ./out (vmlinuz, modroot, hdrroot, initramfs, tarball)
bash bonnell/scripts/package.sh bonnell
# 5. QEMU validation and benchmark
bash bonnell/scripts/qemu-test.sh final out/vmlinuz-bonnell out/initramfs-bonnell.cpio.gz ~/kbuild/bonnell/System.map 1
cat out/logs/final/analysis.txt
# measurements: TCG (default) or KVM (needs the user in group kvm:
#   sudo usermod -aG kvm $USER; then wsl --shutdown / log in again)
bash bonnell/scripts/bench.sh 3 base:base:base bonnell:bonnell:
ACCEL=kvm bash bonnell/scripts/bench.sh 5 bonnell:bonnell:
```

The container runs with `--network=none`; the build never writes to the
source tree (`O=` builds), so several builds can share it.

### Deliverables in `out/` (git-ignored)

| file | content |
|---|---|
| `vmlinuz-bonnell` | bzImage (zstd) |
| `modroot/lib/modules/7.3.4-bonnell/` | `make modules_install` (stripped, signed) |
| `hdrroot/include/` | `make headers_install` |
| `initramfs-bonnell.cpio.gz` | static musl busybox; loads `sky2` + `ath9k`; `root=` → `switch_root`, otherwise / on error a rescue `/bin/sh`; `bonnell.autotest=1` runs the self test |
| `System.map-bonnell`, `config-bonnell`, `SHA256SUMS` | |
| `atom-bonnell-kernel.tar.gz` (+ `.sha256`) | everything above |

### Install on perex (Alpine) / Instalación en perex

```sh
sha256sum -c atom-bonnell-kernel.tar.gz.sha256
tar -xzf atom-bonnell-kernel.tar.gz && sha256sum -c SHA256SUMS
cp vmlinuz-bonnell initramfs-bonnell.cpio.gz /boot/
# "build" is a symlink to the build directory of the build host: drop it
rm -f modroot/lib/modules/7.3.4-bonnell/build
cp -a modroot/lib/modules/7.3.4-bonnell /lib/modules/
# Keep the stock Alpine entry as a fallback and add one for this kernel,
# e.g. in /boot/extlinux.conf (syslinux) or a GRUB menuentry:
#   LABEL bonnell
#     KERNEL /boot/vmlinuz-bonnell
#     INITRD /boot/initramfs-bonnell.cpio.gz
#     APPEND root=UUID=<root-uuid> rw quiet
# bonnell.rescue  -> rescue /bin/sh instead of switch_root
```

ES: conserva la entrada del kernel de Alpine como respaldo. El initramfs carga
`sky2` y `ath9k`, monta `root=` (dispositivo, `UUID=` o `LABEL=`) y hace
`switch_root`; si falla, o con `bonnell.rescue`, abre `/bin/sh` en la consola.

---

## Validation in QEMU / Validación en QEMU

`qemu-system-x86_64 -accel tcg -cpu n270,+lm,+nx,+syscall,+cx16,+lahf-lm,+pse,+vme -smp
2,threads=2 -m 1024` — QEMU's `n270` is family 6 model 0x1c, the same Bonnell
identity as the N450. TCG only decodes instructions whose CPUID bit is exposed,
so anything the N450 lacks raises `#UD` here as on hardware. Kernel command
line `console=ttyS0 nokaslr earlyprintk=serial,ttyS0,115200`, `-d
int,cpu_reset -D /tmp/qemu-debug.log`, `-no-reboot`, an ext4 disk on AHCI.
`analyze-qemu-log.py` classifies every logged event by vector and CPL,
symbolises RIPs with `System.map` and parses `__ex_table` to separate faults
fixed up by design from bugs.

### Results / Resultados

| test | result |
|---|---|
| `7.3.4-bonnell` on the N450 model | **CLEAN**: 0 triple faults, 0 nested exceptions, 0 kernel `#UD`/`#GP`/`#DF`, self test **PASS** |
| kernel exceptions seen | only benign: user `#PF` (demand paging), kernel `#PF` on user addresses (uaccess/exec), 3 early-boot `#PF` resolved by `early_make_pgtable`, 1 `#PF` with an `__ex_table` fixup, `#BP` from text patching |
| CPU vulnerabilities (sysfs) | 19/19 *Not affected* on Bonnell; taint 0 |
| self test | sky2 + ath9k load, vermagic `… BONNELL`, ext4 on AHCI (built-in path) mount/read/write/verify after `drop_caches`, ext4 via loop, overlayfs copy-up, tmpfs/devtmpfs/proc/sysfs, BBR + fq defaults, loopback ping, IST gates OK |
| no-MOVBE CPU (`-cpu qemu64`) | refused cleanly in real mode: `This kernel requires … movbe` — no `#UD`, no triple fault |
| speculative CPU (`-cpu Nehalem,+movbe`) | boots, warns `Bonnell kernel without CPU mitigations on a speculative CPU … NOT mitigated`, taint `S` |
| global `-O3` kernel | also CLEAN / PASS |
| x86 decoder self test (musl) | `insn_decoder_test`: 3 205 109 instructions of the `-march=bonnell` vmlinux decoded and checked; `insn_sanity`: 1 000 000 random, 0 errors |

## Measurements / Mediciones

Base = **pristine upstream 7.3.4** with perex's stock Alpine config after
`localmodconfig` (generic x86-64, mitigations, IBT, 1000 Hz, Xen/NUMA…;
`X86_DECODER_SELFTEST` disabled only because it does not build on musl
upstream, see commit `x86/tools`). 3 boots each, QEMU TCG on the N450 model.

| metric | base | **bonnell** (`-O3` hot paths) | global `-O3` |
|---|---:|---:|---:|
| bzImage | 13 140 992 B | **8 877 056 B (−32 %)** | 9 643 008 B |
| vmlinux `.text` | 26.45 MB | **19.25 MB (−27 %)** | 21.24 MB (+10.4 % vs bonnell) |
| vmlinux `.data` / `.bss` | 7.80 / 4.00 MB | **5.50 / 0.83 MB** | 5.55 / 0.86 MB |
| `MemTotal` seen by the system | 991 260 kB | **1 003 460 kB (+12 MB)** | — |
| memory used after boot (`free -m`) | 28–32 MB | 33–39 MB | 34–47 MB |
| IRQ/syscall entry-exit code (static instructions¹) | 598 | **401 (−33 %)** | 402 |
| external-vector IRQ stubs (`irq_entries_start`) | 3 248 B | **1 624 B (−50 %)** | 1 624 B |
| kernel boot to `/init` (TCG) | 0.99–1.26 s | 1.01–1.20 s | 1.02–1.22 s |
| timer wake-up latency avg / p99 (TCG, `irqlat`) | ~109 / ~260 µs | ~132 / ~350 µs | ~124 / ~310 µs |

¹ `asm_common_interrupt`, `error_entry`, `common_interrupt`,
`common_interrupt_return`, the APIC timer entry, `entry_SYSCALL_64`,
`do_syscall_64`, before runtime alternatives patching.

### KVM (`ACCEL=kvm`, 5 boots each, same N450 CPUID model, host CPU executes)

| metric | base | **bonnell** | global `-O3` |
|---|---:|---:|---:|
| kernel boot to `/init` | 0.36–0.44 s | 0.57–0.70 s | 0.57–0.69 s |
| … of which SATA port probing (built-in AHCI) | 0 (AHCI is a module: no disk found) | 0.32 s | 0.32 s |
| **boot to `/init` without the SATA probe** | **0.39 s** | **~0.30 s (−22 %)** | ~0.31 s |
| wake-up latency avg / p50 / p99, default idle | 45 / 31 / 194 µs | 81 / 60 / 286 µs | 87 / 66 / 280 µs |
| wake-up latency min / p50, `idle=poll` | 7.0 / 10 µs | 12.1 / 14.7 µs | — |
| wake-up latency min / p50, `idle=poll nopv` (base) | 12.0 / 14 µs | — | — |
| self test | FAIL (no overlay, ext4/AHCI modular) | **5/5 PASS** | 5/5 PASS |

KVM numbers have to be read as **virtual-machine** numbers:

* The Bonnell kernel probes the SATA ports before `/init` because AHCI is built
  in (perex's root path). The stock kernel defers that to its initramfs, so the
  fair comparison excludes it: **−22 % boot time to `/init`**.
* The stock kernel looks better on wake-up latency **only because it is a
  paravirtualised KVM guest**: `KVM_GUEST` gives it PV EOI (no VM exit to
  acknowledge each interrupt) and `cpuidle-haltpoll`. With those disabled
  (`nopv`, `idle=poll`) both kernels measure the same (min 12.0 vs 12.1 µs).
  The Bonnell kernel is bare-metal only by design (`HYPERVISOR_GUEST=n`), and
  none of this exists on the physical N450.
* Validation against triple faults and `#UD` stays on TCG: under KVM the host
  CPU executes instructions the N450 lacks without faulting, and `-d int`
  logs nothing.

**Reading the numbers honestly / Lectura honesta:**

* Size, `.text`, IRQ path length and stub density are deterministic and are
  what matters most on an in-order core with a 32 KiB L1i.
* Boot time and wake-up latency under TCG are dominated by the emulator (JIT,
  host scheduling): the boot difference is within noise and the latency
  figures do **not** show an improvement — they cannot be trusted either way.
  Real latency must be measured on perex (`irqlat` ships in the initramfs);
  see the KVM table above for a less noisy, but still virtual, comparison.
* `MemAvailable` is ~55–65 MB lower for bonnell **only in QEMU**: the `n270`
  model does not expose PSE (neither under TCG nor KVM, even with `+pse`). The
  base kernel does not require PSE (Xen's `PARAVIRT_XXL`), so it disables
  THP. The Bonnell kernel assumes PSE, like every non-Xen x86-64 kernel, so it
  enables THP and khugepaged raises `min_free_kbytes` from 3.9 to 44 MB. The
  real N450 has PSE, so both kernels reserve the same there. Used memory is ~5 MB higher because
  ext4/AHCI/SCSI are built in instead of modular.
* Global `-O3` boots fine and needs only one `-Wno-error` (a
  `-Wformat-overflow` false positive in `kernel/trace/trace_kprobe.c` created
  by -O3 path isolation), but costs +10 % `.text` for no measurable gain, so
  the shipped kernel keeps `-O3` to the packet paths.

## Limitations / Limitaciones

* Not yet booted on the physical N450: validation is QEMU/TCG on a Bonnell
  model. The sky2/ath9k changes are build- and review-verified; the devices
  themselves are not emulated (the modules load and bind nothing in QEMU).
* `napi_weight`, the RX prefetch and `-O3` gains are reasoned, not measured on
  hardware.
* Commits carry no `Signed-off-by:`; add your own (DCO) before sending
  anything upstream.

---

## Repository layout / Estructura

```
bonnell/container/Containerfile   pinned Alpine/musl toolchain
bonnell/configs/                  perex stock config + lsmod, bonnell.config fragment
bonnell/scripts/                  audit, mkconfig, kmake, package, mkinitramfs,
                                  qemu-test, analyze-qemu-log.py, bench, test-uapi-musl
bonnell/initramfs/                /init and the self test
bonnell/tools/irqlat.c            cyclictest-like timer wake-up latency probe
arch/x86/configs/bonnell_defconfig
```
