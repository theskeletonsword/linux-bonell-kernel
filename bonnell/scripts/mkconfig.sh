#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# [PROFILE=generic|perex] mkconfig.sh [build-name] [extra-fragment...]
#
# Reproducibly derives a Bonnell .config in /build/<build-name>, starting
# from Alpine's stock config (bonnell/configs/perex-alpine-stock.config):
#
#   PROFILE=generic (default): any 64-bit Bonnell/Saltwell machine.
#     stock -> olddefconfig -> bonnell.config. Every module Alpine ships
#     stays available; only the CPU, hardening, mitigation, virtualisation
#     and debug choices of bonnell.config change.
#   PROFILE=perex: the N450 machine perex.
#     stock -> olddefconfig -> localmodconfig(perex.lsmod) -> bonnell.config
#     -> perex.config. Only the modules perex loads survive.
#
# Then olddefconfig and verify-config.sh: every requested symbol must land.
# Default build-name: "bonnell" for generic, "perex" for perex.
set -euo pipefail
. "$(dirname "$0")/env.sh"

profile=${PROFILE:-generic}
case "$profile" in
generic) frags=(bonnell/configs/bonnell.config); def=bonnell; localmod=0 ;;
perex)   frags=(bonnell/configs/bonnell.config bonnell/configs/perex.config); def=perex; localmod=1 ;;
*) echo "PROFILE must be generic or perex" >&2; exit 2 ;;
esac
name=${1:-$def}
shift || true
frags+=("$@")

mkdir -p "$BUILD_ROOT/$name"
cp "$SRC/bonnell/configs/perex-alpine-stock.config" "$BUILD_ROOT/$name/.config"

incontainer bash -euo pipefail -c '
	name=$1 stop=$2 localmod=$3; shift 3
	O=/build/$name
	m() { make -s -C /src O=$O ARCH=x86_64 "$@"; }
	m olddefconfig
	if [ "$localmod" = 1 ]; then
		# localmodconfig may ask about symbols it cannot resolve: take
		# defaults (yes(1) dies of SIGPIPE when conf exits: hide it from
		# pipefail).
		(set +o pipefail; yes "" | m LSMOD=/src/bonnell/configs/perex.lsmod localmodconfig >/dev/null)
	fi
	cp $O/.config $O/.config.stock
	[ "$stop" = 1 ] && exit 0
	/src/scripts/kconfig/merge_config.sh -m -O $O $O/.config "${@/#/\/src\/}" >/dev/null
	m olddefconfig
	bash /src/bonnell/scripts/verify-config.sh $O/.config "${@/#/\/src\/}"
' _ "$name" "${STOP_AFTER_LOCALMOD:-0}" "$localmod" "${frags[@]}"
