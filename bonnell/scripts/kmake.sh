#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# kmake.sh <build-name> [make args...]
#
# Runs kbuild inside the Alpine/musl container, out-of-tree in
# /build/<build-name>, with the project's warning policy:
#   W=1           -> kernel-curated -Wextra set (scripts/Makefile.warn)
#   CONFIG_WERROR -> -Werror for C, objtool and the linker (set in .config)
# The source tree itself is never written to by the build.
set -euo pipefail
. "$(dirname "$0")/env.sh"

name=${1:?usage: kmake.sh <build-name> [make args...]}
shift
mkdir -p "$BUILD_ROOT/$name"
# KCFLAGS (environment) is forwarded, e.g. KCFLAGS=-O3 for the global -O3
# evaluation build; KW=0 drops W=1 (only for install/packaging targets).
incontainer make -C /src O="/build/$name" ARCH=x86_64 W="${KW:-1}" \
	${KCFLAGS:+KCFLAGS="$KCFLAGS"} -j"$JOBS" "$@"
