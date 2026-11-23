#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# verify-config.sh <.config> <fragment...>
# Every CONFIG_ symbol requested by the fragments must have the requested
# value in the final .config (Kconfig silently drops values whose
# dependencies are not met). Exit 1 and list offenders otherwise.
set -uo pipefail
cfg=$1; shift
bad=0 n=0
while IFS= read -r line; do
	case "$line" in
	CONFIG_*=*) sym=${line%%=*}; want=$line ;;
	"# CONFIG_"*" is not set") sym=${line#\# }; sym=${sym%% *}; want="n" ;;
	*) continue ;;
	esac
	n=$((n + 1))
	got=$(grep -E "^(# )?$sym[= ]" "$cfg" | head -1)
	if [ "$want" = n ]; then
		case "$got" in ""|"# $sym is not set") ;; *) echo "  MISMATCH $sym: want n, got '$got'"; bad=1 ;; esac
	else
		[ "$got" = "$want" ] || { echo "  MISMATCH $sym: want '${want#*=}', got '${got:-<absent>}'"; bad=1; }
	fi
done < <(cat "$@")
if [ $bad -eq 0 ]; then
	echo "verify-config: all $n requested symbols applied"
else
	echo "verify-config: FAILED (see mismatches above; $n symbols checked)"
fi
exit $bad
