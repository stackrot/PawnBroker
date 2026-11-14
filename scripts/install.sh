#!/usr/bin/env bash
# Builds PawnBroker with the BigWigs packager, the same build CurseForge and
# Wago releases get, and installs that package into WoW's AddOns folder. Says
# whether the game needs a restart (new addon or a changed .toc) or a /reload.
#
# WOW_DIR overrides the client folder (the one holding Interface/AddOns).
set -euo pipefail

PACKAGER_TAG=v2.7.0
PACKAGER_SHA256=7790a5ff791ce307a0931b233a4ca0d53553c8583f1f49c19eeb43b95adc773c

root="$(cd "$(dirname "$0")/.." && pwd)"
release="$root/.release"
packager="$release/release.sh"
wow="${WOW_DIR:-$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_}"
dest="$wow/Interface/AddOns/PawnBroker"

if [ ! -d "$wow/Interface/AddOns" ]; then
	echo "no AddOns folder under $wow (set WOW_DIR)" >&2
	exit 1
fi

fetch_packager() {
	local url="https://raw.githubusercontent.com/BigWigsMods/packager"
	mkdir -p "$release"
	curl -fsSL -o "$packager.tmp" "$url/$PACKAGER_TAG/release.sh"
	if ! echo "$PACKAGER_SHA256  $packager.tmp" | sha256sum -c --quiet -; then
		rm -f "$packager.tmp"
		echo "packager checksum mismatch, not running it" >&2
		exit 1
	fi
	mv "$packager.tmp" "$packager"
}

if ! echo "$PACKAGER_SHA256  $packager" | sha256sum -c --status - 2>/dev/null
then
	fetch_packager
fi

# -d: no upload, -z: no zip. Output lands in .release/PawnBroker.
bash "$packager" -d -z -t "$root" -r "$release" >/dev/null
build="$release/PawnBroker"

if diff -rq "$build" "$dest" >/dev/null 2>&1; then
	echo "PawnBroker is up to date"
	exit 0
fi

# The packager stamps a version into the .toc on every build, which the
# game doesn't need a restart for, so that line is left out of the check,
# as are line endings (releases use CRLF).
toc() {
	tr -d '\r' <"$1/PawnBroker.toc" 2>/dev/null | grep -v '^## Version:'
}
restart=0
if [ ! -d "$dest" ] || ! cmp -s <(toc "$build") <(toc "$dest"); then
	restart=1
fi
# Mirror, so files dropped from the addon don't linger in the game.
rm -rf "$dest"
cp -r "$build" "$dest"

if [ "$restart" = 1 ]; then
	echo "PawnBroker installed: restart WoW to load it"
else
	echo "PawnBroker updated: /reload in game"
fi
