#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# test-uapi-musl.sh <installed-headers-include-dir>
# Run INSIDE the container. Complements CONFIG_UAPI_HEADER_TEST (which
# compile-tests every exported header standalone against the host libc, i.e.
# musl, during the kernel build) with the mixes real userland uses.
#
# MUST cases fail the script. KNOWN cases document upstream/musl conflicts:
# include/uapi/linux/libc-compat.h only recognises glibc (__GLIBC__), and
# musl deliberately has no identifying macro, so libc and kernel definitions
# of the same type collide. Alpine's own linux-headers carry the same caveat.
set -uo pipefail
H=${1:?include dir}
fail=0
try() { # try STRICT|MIX|KNOWN <name> <headers...>
	# STRICT: kernel headers that pull in no libc header, -Wall -Wextra -Werror.
	# MIX:    libc + kernel headers as userland includes them; must have no
	#         hard error. musl and the kernel both define a few ioctl macros
	#         (_IOC*, SIOCGSTAMP...) with different text but equal values;
	#         GCC reports that as a (non-suppressible) "redefined" warning,
	#         listed here.
	# KNOWN:  hard type conflicts inherent to musl + libc-compat.h.
	kind=$1 name=$2; shift 2
	src=/tmp/uapi-$name.c
	: > "$src"
	for h in "$@"; do echo "#include <$h>" >> "$src"; done
	echo 'int main(void) { return 0; }' >> "$src"
	werror=""
	[ "$kind" = STRICT ] && werror=-Werror
	if err=$(gcc -std=gnu11 -Wall -Wextra $werror -I"$H" -c "$src" -o /tmp/uapi.o 2>&1); then
		w=$(echo "$err" | grep -o "'[A-Za-z0-9_]*' redefined" | sort -u | tr '\n' ' ')
		echo "  [OK]    $name${w:+ (musl/kernel macro overlap: $w)}"
	elif [ "$kind" = KNOWN ]; then
		echo "  [KNOWN] $name: $(echo "$err" | grep -m1 -E 'error' | sed 's/^[^ ]* //')"
	else
		echo "  [FAIL]  $name"; echo "$err" | grep -E 'error' | head -5 | sed 's/^/          /'; fail=1
	fi
}

echo "== UAPI headers from headers_install vs musl $(ldd 2>&1 | sed -n 's/^Version //p') =="
n=$(find "$H" -name '*.h' | wc -l)
echo "  $n headers installed; libc-compat glibc-only guards: $(grep -c '__GLIBC__' "$H/linux/libc-compat.h")"
grep -rl '#include <gnu/\|__GLIBC_PREREQ\|<bits/libc-header-start' "$H" >/tmp/glibc-only 2>/dev/null
[ -s /tmp/glibc-only ] && { echo "  [FAIL]  glibc-only includes in:"; sed 's/^/          /' /tmp/glibc-only; fail=1; } \
	|| echo "  [OK]    no glibc-private includes (<gnu/...>, __GLIBC_PREREQ)"

try STRICT kernel-only      linux/types.h linux/ethtool.h linux/if_ether.h linux/netlink.h \
                            linux/rtnetlink.h linux/nl80211.h linux/if_packet.h linux/tcp.h \
                            linux/pkt_sched.h linux/netfilter/nf_tables.h linux/ioctl.h
try MIX musl+netlink        sys/socket.h linux/netlink.h linux/rtnetlink.h linux/genetlink.h
try MIX musl+wifi           sys/socket.h sys/ioctl.h linux/nl80211.h linux/wireless.h
try MIX musl+input          stdint.h sys/ioctl.h linux/input.h linux/uinput.h
try MIX musl+v4l2           sys/ioctl.h sys/time.h linux/videodev2.h
try MIX musl+ethtool        stdint.h sys/ioctl.h net/if.h linux/ethtool.h linux/sockios.h
try KNOWN musl+sysinfo      sys/sysinfo.h linux/kernel.h
try MIX musl+netinet-in     netinet/in.h linux/in.h linux/in6.h
try KNOWN musl+net-if       net/if.h linux/if.h

[ $fail -eq 0 ] && echo "UAPI-MUSL: PASS" || echo "UAPI-MUSL: FAIL"
exit $fail
