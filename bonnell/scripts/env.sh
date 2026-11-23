# SPDX-License-Identifier: GPL-2.0
# Common settings for the Bonnell kernel tooling (sourced, not executed).
#
# Host layout (override via environment):
#   SRC        kernel source tree (git repo), mounted at /src
#   BUILD_ROOT out-of-tree build directories, mounted at /build
#   OUT        deliverables, mounted at /out (git-ignored)
BONNELL_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC=${SRC:-$(cd "$BONNELL_SCRIPTS/../.." && pwd)}
BUILD_ROOT=${BUILD_ROOT:-$HOME/kbuild}
OUT=${OUT:-$SRC/out}
IMAGE=${IMAGE:-localhost/bonnell-kbuild:3.24.4}
# -j16: keeps peak RSS well under the 31 GiB of the build host even with
# -O3 translation units and W=1; raise to 24 at most.
JOBS=${JOBS:-16}
mkdir -p "$BUILD_ROOT" "$OUT"

# Run a command inside the hermetic container. Network is disabled: the
# build must not depend on anything outside the image and the mounts.
incontainer() {
	podman run --rm --network=none \
		-v "$SRC:/src" -v "$BUILD_ROOT:/build" -v "$OUT:/out" \
		-w /src "$IMAGE" "$@" 2> >(grep -v 'is not a shared mount' >&2)
}
