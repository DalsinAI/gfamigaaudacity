#!/bin/sh
# Builds Audacity 3.7.9 for AmigaOS 3, 68040 soft float, with a stove: the
# GFOpenWX Toolkit SDK and GFOpenPortAudio first, then the libraries
# (scripts/build-deps.sh), then Audacity (scripts/build-audacity.sh) for
# BUDGET seconds of make; the build tree is kept, so the next run goes on.
#   STOVE=.../stoves/os32-gcc16-open6 OUT=out ./build-amiga.sh
#   (WXT_SRC=... PA_SRC=... to use trees already on disk)
# Audacity and the libraries are fetched at the versions audacity.lock
# gives; nothing third-party is kept here. OUT gets audacity when linked.
# Copyright (c) 2026 AmiCradle Team
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/audacity.lock"
STOVE=${STOVE:-"$HOME/AmiCradle/stoves/os32-gcc16-open6"}
# the build tree lives outside the checkout, so a checkout that is cleaned
# between runs (Cradle's stove jobs run git clean -ffdx) still goes on
WORK="${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/gfamigaaudacity/build}"
OUT="${OUT:-$HERE/build/out}"; JOBS=${JOBS:-12}
TC="$STOVE/prefix"
command -v cmake >/dev/null || { echo "no cmake on this stove"; exit 1; }
mkdir -p "$WORK/deps" "$OUT"
t0=$(date +%s)

fetch() {
    d="$WORK/deps/$1"
    if [ "$(git -C "$d" rev-parse HEAD 2>/dev/null)" != "$3" ]; then
        rm -rf "${d:?}"; mkdir -p "$d"
        git -C "$d" init -q
        git -C "$d" fetch -q --depth 1 "$2" "$3"
        git -C "$d" checkout -q FETCH_HEAD
    fi
}
if [ -z "${WXT_SRC:-}" ]; then fetch gfopenwxtoolkit "$WXT_REPO" "$WXT_COMMIT"; WXT_SRC="$WORK/deps/gfopenwxtoolkit"; fi
if [ -z "${PA_SRC:-}" ]; then
    [ -n "$PA_COMMIT" ] || { echo "PA_SRC: GFOpenPortAudio's tree (no repository pinned yet)"; exit 1; }
    fetch gfopenportaudio "$PA_REPO" "$PA_COMMIT"; PA_SRC="$WORK/deps/gfopenportaudio"
fi

# the toolkit again only when its tree changed since its SDK was made (a
# no-change run still links its samples)
WXB="$WORK/gfopenwx"
WXREV=$( (git -C "$WXT_SRC" rev-parse HEAD 2>/dev/null; git -C "$WXT_SRC" diff HEAD 2>/dev/null) | sha256sum | cut -c1-16)
if [ ! -x "$WXB/out/sdk/bin/wx-config" ] || [ "$(cat "$WXB/out/.rev" 2>/dev/null)" != "$WXREV" ]; then
    STOVE="$STOVE" WORK="$WXB" OUT="$WXB/out" JOBS=$JOBS sh "$WXT_SRC/build-amiga.sh" > "$WORK.wx.log" 2>&1 || { tail -30 "$WORK.wx.log"; exit 1; }
    echo "$WXREV" > "$WXB/out/.rev"
    echo "toolkit: $(( $(date +%s) - t0 )) s"
fi
[ -x "$WXB/out/sdk/bin/wx-config" ] || { tail -30 "$WORK.wx.log"; echo "no toolkit SDK"; exit 1; }
PAB="$WORK/gfopenportaudio"
TOOLCHAIN="$TC" WORK="$PAB" OUT="$PAB/out" sh "$PA_SRC/scripts/build-amiga.sh" > "$WORK.pa.log" 2>&1 || { tail -30 "$WORK.pa.log"; exit 1; }
echo "toolkit and PortAudio: $(( $(date +%s) - t0 )) s"

. "$WXT_SRC/wx.lock"
TOOLCHAIN="$TC" WORK="$WORK" JOBS=$JOBS WX_SDK="$WXB/out/sdk" WX_TREE="$WXB/wxWidgets-$WX_VERSION" \
    PA_SDK="$PAB/out/sdk" sh "$HERE/scripts/build-deps.sh" > "$WORK.deps.log" 2>&1 || { tail -40 "$WORK.deps.log"; exit 1; }
echo "libraries: $(( $(date +%s) - t0 )) s"
left=$(( ${BUDGET_TOTAL:-840} - ($(date +%s) - t0) ))
[ "$left" -gt 60 ] || { echo "no time left for Audacity this run"; exit 0; }
TOOLCHAIN="$TC" WORK="$WORK" OUT="$OUT" JOBS=$JOBS WX_SDK="$WXB/out/sdk" BUDGET=$left \
    sh "$HERE/scripts/build-audacity.sh"
echo "total: $(( $(date +%s) - t0 )) s"
