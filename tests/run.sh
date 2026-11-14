#!/usr/bin/env bash
# Runs every scenario against the addon in the repo root with mocked
# game APIs and real scan data. -v shows chat output.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
addon="$here/.."
verbose=""
[ "${1:-}" = "-v" ] && verbose="VERBOSE=true"

failed=0
for scenario in "$here"/scenarios/*.lua; do
	name="$(basename "$scenario" .lua)"
	ok=1
	out=$(cd "$here" && luajit -e "$verbose" harness.lua mockdata.lua \
		gear.lua "$addon" "$scenario" 2>&1) || ok=0
	if [ "$ok" = 1 ]; then
		echo "ok   $name"
	else
		echo "FAIL $name"
		failed=1
	fi
	if [ "$ok" = 0 ] || [ -n "$verbose" ]; then
		echo "$out" | sed 's/^/     /'
	fi
done
exit "$failed"
