#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Step 1 audit: run INSIDE the container (bonnell/scripts/incontainer.sh).
# Verifies the toolchain, musl, and that -march=bonnell combined with the
# kernel's mandatory -mno-<simd> flags emits Bonnell-legal, SIMD-free code.
set -uo pipefail
fail=0
ok()  { printf '  [OK]   %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; fail=1; }

echo "== Tools =="
for t in gcc ld make bc flex bison perl cpio openssl depmod busybox.static \
	 qemu-system-x86_64 gawk bash pkg-config rsync zstd python3; do
	if p=$(command -v "$t"); then ok "$t -> $p"; else bad "$t missing"; fi
done
gcc --version | head -1
ld --version | head -1
make --version | head -1
qemu-system-x86_64 --version | head -1
printf 'bc %s | flex %s | bison %s | perl %s\n' \
	"$(bc --version | head -1 | awk '{print $2}')" "$(flex --version | awk '{print $2}')" \
	"$(bison --version | head -1 | awk '{print $NF}')" "$(perl -e 'print $^V')"

echo "== libc / dev libraries =="
libc_id=$(ldd 2>&1 || true)   # musl's ldd prints its banner and exits 1
case "$libc_id" in
	*musl*) ok "libc is musl: $(printf '%s' "$libc_id" | tr '\n' ' ')" ;;
	*) bad "libc is not musl" ;;
esac
if ! grep -rqs '__GLIBC__' /usr/include/features.h; then ok "no glibc headers in /usr/include"; else bad "glibc headers present"; fi
for pc in libelf libcrypto; do
	if v=$(pkg-config --modversion "$pc" 2>/dev/null); then ok "$pc $v"; else bad "$pc (pkg-config)"; fi
done
for h in gelf.h libelf.h openssl/evp.h; do
	if echo "#include <$h>" | gcc -E -x c - >/dev/null 2>&1; then ok "<$h>"; else bad "<$h>"; fi
done
# objtool, resolve_btfids and sign-file link against these; make sure no
# glibc-only symbol sneaks in (would show up as a link error here).
cat >/tmp/libchk.c <<'EOF'
#include <gelf.h>
#include <openssl/evp.h>
int main(void) { elf_version(EV_CURRENT); return EVP_MD_get_size(EVP_sha256()) != 32; }
EOF
if gcc -Wall -Wextra -Werror /tmp/libchk.c -o /tmp/libchk -lelf -lcrypto && /tmp/libchk; then
	ok "libelf + libcrypto link and run on musl"
else
	bad "libelf/libcrypto link test"
fi

echo "== GCC plugin build support (GCC_PLUGIN_LATENT_ENTROPY) =="
pdir=$(gcc -print-file-name=plugin)
if [ -e "$pdir/include/plugin-version.h" ] &&
   echo '#include "gcc-plugin.h"' | g++ -I"$pdir/include" -fsyntax-only -x c++ - 2>/dev/null; then
	ok "gcc-plugin.h compiles (gmp/mpc/mpfr headers present)"
else
	bad "cannot build GCC plugins (need gmp-dev mpc1-dev mpfr-dev)"
fi

echo "== -march=bonnell support =="
# Same order as arch/x86/Makefile: -mno-<simd> first, -march later. GCC keeps
# explicitly disabled ISA bits regardless of a later -march.
KFLAGS="-m64 -fno-pie -fno-pic -mno-sse -mno-mmx -mno-sse2 -mno-3dnow -mno-avx -mno-sse4a -march=bonnell -mtune=bonnell -mno-red-zone -mcmodel=kernel"
if gcc -march=bonnell -mtune=bonnell -E -x c /dev/null >/dev/null 2>&1; then
	ok "gcc accepts -march=bonnell -mtune=bonnell"
else
	bad "gcc rejects -march=bonnell"
fi
echo "  ISA implied by plain -march=bonnell:"
gcc -march=bonnell -Q --help=target 2>/dev/null |
	grep -E '^\s+-m(sse|sse2|sse3|ssse3|sse4\.1|sse4\.2|avx|avx2|avx512f|movbe|popcnt|cx16|sahf|fxsr|mmx)\s' |
	sed 's/^/    /'
echo "  ISA with the kernel's flag set ($KFLAGS):"
# shellcheck disable=SC2086
gcc $KFLAGS -Q --help=target 2>/dev/null |
	grep -E '^\s+-m(sse|sse2|ssse3|avx|avx2|avx512f|movbe)\s' | sed 's/^/    /'
# shellcheck disable=SC2086
en=$(gcc $KFLAGS -Q --help=target 2>/dev/null |
	awk '$2=="[enabled]"{print $1}' | grep -E '^-m(sse|sse2|sse3|ssse3|sse4|avx|avx2|avx512)' || true)
[ -z "$en" ] && ok "no SSE/AVX family enabled under kernel flags" || bad "SIMD still enabled: $en"

cat >/tmp/cg.c <<'EOF'
typedef unsigned int u32;
u32 load_be32(const u32 *p) { return __builtin_bswap32(*p); }
void vadd(u32 *restrict a, const u32 *restrict b, int n)
{ for (int i = 0; i < n; i++) a[i] += b[i] * 3u; }
u32 cnt(unsigned long x) { return __builtin_popcountl(x); }
EOF
rm -f /tmp/cg.s
# shellcheck disable=SC2086
if ! gcc $KFLAGS -O3 -Wall -Wextra -Werror -S -o /tmp/cg.s /tmp/cg.c || [ ! -s /tmp/cg.s ]; then
	bad "codegen probe did not compile"; echo; echo "AUDIT: FAIL"; exit 1
fi
grep -q movbe /tmp/cg.s && ok "MOVBE emitted for be32 loads (Bonnell has MOVBE)" || bad "no MOVBE"
grep -Eq '%[xyz]mm[0-9]' /tmp/cg.s && bad "vector registers used at -O3" || ok "no xmm/ymm/zmm at -O3 (vectorizer neutralised)"
grep -q 'popcnt' /tmp/cg.s && bad "POPCNT emitted (N450 lacks it -> #UD)" || ok "no POPCNT (N450 lacks it)"
grep -Eq '\b(vmov|vpadd|vzeroupper)' /tmp/cg.s && bad "VEX/AVX encodings found" || ok "no VEX/AVX encodings"

echo
[ $fail -eq 0 ] && echo "AUDIT: PASS" || echo "AUDIT: FAIL"
exit $fail
