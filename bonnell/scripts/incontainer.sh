#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# incontainer.sh <cmd> [args...]: run a command in the hermetic build container
# with /src, /build and /out mounted (see env.sh).
set -euo pipefail
. "$(dirname "$0")/env.sh"
incontainer "$@"
