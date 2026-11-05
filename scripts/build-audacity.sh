#!/bin/sh
# Fetches Audacity at its pinned commit, applies patches/, and configures and
# builds it against the sysroot from build-deps.sh and gfopenwx's SDK. The
# build tree is kept, so a build that runs out of time goes on from where it
# stopped next time (BUDGET seconds of make per run).
#   TOOLCHAIN=.../prefix WX_SDK=... WORK=build OUT=out scripts/build-audacity.sh
# Copyright (c) 2026 AmiCradle Team
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$HERE/audacity.lock"
WORK=${WORK:-$HERE/build}; OUT=${OUT:-$WORK/out}; JOBS=${JOBS:-12}; BUDGET=${BUDGET:-700}
SYS="$WORK/sysroot"; SRC="$WORK/audacity"; B="$WORK/abuild"
mkdir -p "$OUT"

# EXTRA_PATCHES: a directory of lab-only patches (diagnostics), applied last
EXTRA=""; [ -n "${EXTRA_PATCHES:-}" ] && EXTRA=$(ls "$EXTRA_PATCHES"/*.patch 2>/dev/null || true)
PSUM=$(cat "$HERE"/patches/*.patch $EXTRA | sha256sum | cut -c1-16)
if [ "$(cat "$SRC/.patched" 2>/dev/null)" != "$AUD_COMMIT-$PSUM" ]; then
    rm -rf "$SRC"; mkdir -p "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" fetch -q --depth 1 "$AUD_GIT" "$AUD_COMMIT"
    git -C "$SRC" checkout -q FETCH_HEAD
    [ "$(git -C "$SRC" rev-parse HEAD)" = "$AUD_COMMIT" ] || { echo "commit mismatch"; exit 1; }
    for p in "$HERE"/patches/*.patch $EXTRA; do
        patch -s -d "$SRC" -p1 < "$p" || { echo "patch failed: $p"; exit 1; }
    done
    echo "$AUD_COMMIT-$PSUM" > "$SRC/.patched"
    rm -rf "$B"
fi

# Theme headers: image-compiler would be an Amiga binary here, so the build
# host makes them with our own theme-compiler.py (same layout, same bytes in).
TR="$SRC/libraries/lib-theme-resources"
TSUM=$(cat "$HERE/scripts/theme-compiler.py" | sha256sum | cut -c1-16)
if [ "$(cat "$TR/.themes" 2>/dev/null)" != "$TSUM" ]; then
    python3 -I "$HERE/scripts/theme-compiler.py" "$TR" \
        "$SRC/libraries/lib-theme/AllThemeResources.h" \
        light dark classic high-contrast || { echo "theme-compiler failed"; exit 1; }
    echo "$TSUM" > "$TR/.themes"
fi

# SoundTouch is built from source by Audacity's own proxy when the deps
# step fetched it; without it the tempo/pitch effects cannot build.
if [ -d "$WORK/soundtouch/source" ]; then
    rm -rf "$SRC/lib-src/soundtouch"; cp -R "$WORK/soundtouch" "$SRC/lib-src/soundtouch"
    ST_OPT="-Daudacity_use_soundtouch=local"; st=""
else
    ST_OPT=""; st="soundtouch"
fi
off="libmpg123 libid3tag wavpack libogg libflac libopus opusfile libvorbis vamp lv2 sbsms $st twolame ffmpeg portmixer nyquist ladspa vst png jpeg"
OPTS="$ST_OPT"
for o in $off; do OPTS="$OPTS -Daudacity_use_$o=off"; done
CSUM=$( (cat "$0" "$HERE/cmake/toolchain-m68k-amigaos.cmake" "$HERE"/cmake/Platform/*.cmake; echo "$OPTS") | sha256sum | cut -c1-16)
if [ "$(cat "$B/.configured" 2>/dev/null)" != "$CSUM" ]; then
    rm -rf "$B"; mkdir -p "$B"
    # shellcheck disable=SC2086
    (cd "$B" && PKG_CONFIG_LIBDIR="$SYS/lib/pkgconfig" PKG_CONFIG_SYSROOT_DIR= cmake "$SRC" -G "Unix Makefiles" \
        -DCMAKE_TOOLCHAIN_FILE="$HERE/cmake/toolchain-m68k-amigaos.cmake" \
        -DAMIGA_TOOLCHAIN="$TOOLCHAIN" -DAMIGA_SYSROOT="$SYS" -DAMIGA_SPECS="$HERE/scripts/m68k-soft-m68040.specs" \
        -DCMAKE_PREFIX_PATH="$SYS" -DCMAKE_BUILD_TYPE=Release \
        -DwxWidgets_CONFIG_EXECUTABLE="$SYS/wx/bin/wx-config" \
        -DIMAGE_COMPILER_EXECUTABLE=/bin/true -DAUDACITY_BUILD_LEVEL=2 \
        -DCMAKE_THREAD_LIBS_INIT=-lpthread -DCMAKE_HAVE_PTHREADS_CREATE=0 -DCMAKE_HAVE_PTHREAD_CREATE=1 -DCMAKE_HAVE_THREADS_LIBRARY=1 -DCMAKE_USE_PTHREADS_INIT=1 \
        -DThreads_FOUND=TRUE \
        -Daudacity_conan_enabled=Off -Daudacity_lib_preference=system \
        -Daudacity_has_networking=Off -Daudacity_has_crashreports=Off -Daudacity_has_vst3=Off \
        -Daudacity_has_tests=Off -Daudacity_has_audiocom_upload=Off -Daudacity_has_updates_check=Off \
        -Daudacity_has_whats_new=Off -Daudacity_has_sentry_reporting=Off -Daudacity_has_url_schemes_support=Off \
        -Daudacity_use_libsndfile=system -Daudacity_use_zlib=system -Daudacity_use_expat=system \
        -Daudacity_use_wxwidgets=system -Daudacity_use_libmp3lame=system -Daudacity_use_portaudio=system \
        -Daudacity_use_rapidjson=system -Daudacity_use_midi=system $OPTS > cmake.log 2>&1) || { grep -B2 -A12 'CMake Error' "$B/cmake.log" | head -80; tail -20 "$B/cmake.log"; exit 1; }
    echo "$CSUM" > "$B/.configured"
fi

# the theme headers were made above by theme-compiler.py; Audacity's own
# image compiler (a program run at build time) is replaced by /bin/true.
# make for at most BUDGET seconds; -k so one bad file shows the rest
set +e
(cd "$B" && timeout "$BUDGET" nice -n 19 make -k -j"$JOBS" > make.log 2>&1)
rc=$?
set -e
echo "make rc=$rc"
grep -E 'error:|Error [0-9]|undefined reference' "$B/make.log" | sort -u | head -60
tail -5 "$B/make.log"
if [ -f "$B/Release/bin/audacity" ]; then
    "$TOOLCHAIN/bin/m68k-amigaos-strip" -o "$OUT/audacity" "$B/Release/bin/audacity" || cp "$B/Release/bin/audacity" "$OUT/audacity"
    ls -l "$OUT/audacity"
fi
