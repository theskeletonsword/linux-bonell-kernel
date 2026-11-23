#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# mkconfig.sh [build-name] [fragment...]
#
# Reproducibly derives the Bonnell .config in /build/<build-name>:
#   1. perex's stock Alpine config (bonnell/configs/perex-alpine-stock.config)
#   2. olddefconfig for 7.3.4
#   3. localmodconfig with perex's lsmod (bonnell/configs/perex.lsmod):
#      only modules perex actually loads survive
#   4. merge the fragment(s) (default bonnell/configs/bonnell.config)
#   5. olddefconfig, then verify every requested symbol landed
set -euo pipefail
. "$(dirname "$0")/env.sh"

name=${1:-bonnell}
shift || true
frags=("$@")
[ ${#frags[@]} -gt 0 ] || frags=(bonnell/configs/bonnell.config)

mkdir -p "$BUILD_ROOT/$name"
cp "$SRC/bonnell/configs/perex-alpine-stock.config" "$BUILD_ROOT/$name/.config"

incontainer bash -euo pipefail -c '
	name=$1 stop=$2; shift 2
	O=/build/$name
	m() { make -s -C /src O=$O ARCH=x86_64 "$@"; }
	m olddefconfig
	# localmodconfig may ask about symbols it cannot resolve: take defaults.
	# (yes(1) dies of SIGPIPE when conf exits: do not let pipefail see it.)
	(set +o pipefail; yes "" | m LSMOD=/src/bonnell/configs/perex.lsmod localmodconfig >/dev/null)
	cp $O/.config $O/.config.localmod
	[ "$stop" = 1 ] && exit 0
	/src/scripts/kconfig/merge_config.sh -m -O $O $O/.config "${@/#/\/src\/}" >/dev/null
	m olddefconfig
	bash /src/bonnell/scripts/verify-config.sh $O/.config "${@/#/\/src\/}"
' _ "$name" "${STOP_AFTER_LOCALMOD:-0}" "${frags[@]}"
