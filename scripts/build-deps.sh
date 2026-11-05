#!/bin/sh
# Builds what Audacity needs besides wx and PortAudio into one sysroot:
# LAME (MP3 export), libsndfile (WAV, AIFF and friends, no external codecs),
# RapidJSON's headers, our libuuid, and zlib and expat from wx's own copies.
#   TOOLCHAIN=.../prefix WX_SDK=... PA_SDK=... WORK=build scripts/build-deps.sh
# Copyright (c) 2026 AmiCradle Team
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$HERE/audacity.lock"
WORK=${WORK:-$HERE/build}; JOBS=${JOBS:-12}
PATH="$TOOLCHAIN/bin:$PATH"
SYS="$WORK/sysroot"; D="$WORK/dl"
mkdir -p "$SYS/include" "$SYS/lib/cmake" "$SYS/lib/pkgconfig" "$D"
HOSTB=$(gcc -dumpmachine)
CF="-noixemul -m68040 -O2"; NDKI=${NDK:+-I$NDK}
LF="-noixemul -m68040 -specs=$HERE/scripts/m68k-soft-m68040.specs"

fetch() { # url sha file
    if [ ! -f "$D/$3" ] || ! echo "$2  $D/$3" | sha256sum -c - >/dev/null 2>&1; then
        curl -fsSL -o "$D/$3.part" "$1"
        echo "$2  $D/$3.part" | sha256sum -c - >/dev/null || { echo "sha256 mismatch: $1"; exit 1; }
        mv "$D/$3.part" "$D/$3"
    fi
}
gitpin() { # url commit dir
    if [ "$(git -C "$3" rev-parse HEAD 2>/dev/null)" != "$2" ]; then
        rm -rf "$3"; mkdir -p "$3"
        git -C "$3" init -q
        git -C "$3" fetch -q --depth 1 "$1" "$2"
        git -C "$3" checkout -q FETCH_HEAD
        [ "$(git -C "$3" rev-parse HEAD)" = "$2" ] || { echo "commit mismatch: $1"; exit 1; }
    fi
}

# SoundTouch (Audacity's tempo/pitch effects): source only; Audacity's own
# cmake-proxies/soundtouch builds it from lib-src/soundtouch.
if [ -n "$ST_COMMIT" ]; then
    gitpin "$ST_GIT" "$ST_COMMIT" "$WORK/soundtouch"
elif [ ! -d "$WORK/soundtouch/source" ]; then
    rm -rf "$WORK/soundtouch"
    git clone -q --depth 1 --branch "$ST_TAG" "$ST_GIT" "$WORK/soundtouch" || rm -rf "$WORK/soundtouch"
fi
[ -d "$WORK/soundtouch/source" ] && echo "soundtouch $ST_TAG at $(git -C "$WORK/soundtouch" rev-parse HEAD)"

# LAME
if [ ! -f "$SYS/lib/libmp3lame.a" ] || [ "$(cat "$WORK/.lame" 2>/dev/null)" != "$LAME_SHA256" ]; then
    fetch "$LAME_URL" "$LAME_SHA256" lame.tar.gz
    rm -rf "$WORK/lame"; mkdir -p "$WORK/lame"; tar xzf "$D/lame.tar.gz" -C "$WORK/lame" --strip-components=1
    (cd "$WORK/lame" && CFLAGS="$CF" LDFLAGS="$LF" ./configure --host=m68k-amigaos --build="$HOSTB" \
        --prefix="$SYS" --disable-shared --enable-static --disable-frontend --disable-decoder --disable-gtktest \
        --disable-analyzer-hooks --disable-dependency-tracking > configure.log 2>&1 || { tail -30 configure.log; exit 1; }
     nice -n 19 make -j"$JOBS" -C libmp3lame > make.log 2>&1 || { grep -E 'error' make.log | head -30; exit 1; }
     make -C libmp3lame install > /dev/null && make -C include install > /dev/null)
    echo "$LAME_SHA256" > "$WORK/.lame"
fi

# libsndfile, no external libraries (FLAC, Ogg, Opus, MPEG are separate ports)
if [ ! -f "$SYS/lib/libsndfile.a" ] || [ "$(cat "$WORK/.sndfile" 2>/dev/null)" != "$SNDFILE_SHA256" ]; then
    fetch "$SNDFILE_URL" "$SNDFILE_SHA256" sndfile.tar.xz
    rm -rf "$WORK/sndfile"; mkdir -p "$WORK/sndfile"; tar xJf "$D/sndfile.tar.xz" -C "$WORK/sndfile" --strip-components=1
    # C17: its ALAC code names an enum constant false
    (cd "$WORK/sndfile" && CFLAGS="$CF -std=gnu17" LDFLAGS="$LF" ./configure --host=m68k-amigaos --build="$HOSTB" \
        --prefix="$SYS" --disable-shared --enable-static --disable-external-libs --disable-mpeg \
        --disable-sqlite --disable-alsa --disable-full-suite --disable-dependency-tracking > configure.log 2>&1 \
        || { tail -30 configure.log; exit 1; }
     nice -n 19 make -j"$JOBS" src/libsndfile.la > make.log 2>&1 || { grep -E 'error' make.log | head -30; exit 1; }
     cp src/.libs/libsndfile.a "$SYS/lib/" && cp include/sndfile.h include/sndfile.hh "$SYS/include/" \
     && sed "s|^prefix=.*|prefix=$SYS|" sndfile.pc > "$SYS/lib/pkgconfig/sndfile.pc")
    echo "$SNDFILE_SHA256" > "$WORK/.sndfile"
fi
mkdir -p "$SYS/lib/cmake/SndFile"
cat > "$SYS/lib/cmake/SndFile/SndFileConfig.cmake" <<CM
if(NOT TARGET SndFile::sndfile)
  add_library(SndFile::sndfile STATIC IMPORTED GLOBAL)
  set_target_properties(SndFile::sndfile PROPERTIES IMPORTED_LOCATION "$SYS/lib/libsndfile.a"
    INTERFACE_INCLUDE_DIRECTORIES "$SYS/include")
endif()
set(SndFile_FOUND TRUE)
CM

# RapidJSON: headers only
gitpin "$RJ_GIT" "$RJ_COMMIT" "$WORK/rapidjson"
rm -rf "$SYS/include/rapidjson"; cp -a "$WORK/rapidjson/include/rapidjson" "$SYS/include/"
mkdir -p "$SYS/lib/cmake/RapidJSON"
cat > "$SYS/lib/cmake/RapidJSON/RapidJSONConfig.cmake" <<CM
if(NOT TARGET rapidjson)
  add_library(rapidjson INTERFACE IMPORTED GLOBAL)
  set_target_properties(rapidjson PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "$SYS/include")
endif()
if(NOT TARGET RapidJSON::RapidJSON)
  add_library(RapidJSON::RapidJSON ALIAS rapidjson)
endif()
set(RapidJSON_FOUND TRUE)
set(RapidJSON_INCLUDE_DIRS "$SYS/include")
CM

# PortMidi: its common code with our system part (no devices yet)
gitpin "$PM_GIT" "$PM_COMMIT" "$WORK/portmidi"
PMI="-I$WORK/portmidi/pm_common -I$WORK/portmidi/porttime"
mkdir -p "$WORK/pmobj"
for f in "$WORK/portmidi/pm_common/portmidi.c" "$WORK/portmidi/pm_common/pmutil.c" \
         "$HERE/deps/portmidi/pm_amiga.c" "$HERE/deps/portmidi/pt_amiga.c"; do
    m68k-amigaos-gcc $CF -std=gnu17 $PMI -c "$f" -o "$WORK/pmobj/$(basename "$f" .c).o"
done
rm -f "$SYS/lib/libportmidi.a"; m68k-amigaos-ar rcs "$SYS/lib/libportmidi.a" "$WORK"/pmobj/*.o
cp "$WORK/portmidi/pm_common/portmidi.h" "$WORK/portmidi/pm_common/pmutil.h" "$WORK/portmidi/porttime/porttime.h" "$SYS/include/"

# our libuuid
m68k-amigaos-gcc $CF $NDKI -Wall -I"$HERE/deps/uuid" -c "$HERE/deps/uuid/uuid.c" -o "$WORK/uuid.o"
rm -f "$SYS/lib/libuuid.a"; m68k-amigaos-ar rcs "$SYS/lib/libuuid.a" "$WORK/uuid.o"

# the POSIX calls libnix lacks (deps/compat/amiga_posix.c says why each)
m68k-amigaos-gcc $CF -Wall -fno-builtin -c "$HERE/deps/compat/amiga_posix.c" -o "$WORK/amiga_posix.o"
rm -f "$SYS/lib/libamigaposix.a"; m68k-amigaos-ar rcs "$SYS/lib/libamigaposix.a" "$WORK/amiga_posix.o"
mkdir -p "$SYS/include/uuid"; cp "$HERE/deps/uuid/uuid/uuid.h" "$SYS/include/uuid/"

# zlib and expat: wx's own builds, under their usual names
WXT=$(ls -d "$WX_TREE")
cp "$WX_SDK/lib/libwxzlib-3.2.a" "$SYS/lib/libz.a"
cp "$WX_SDK/lib/libwxexpat-3.2.a" "$SYS/lib/libexpat.a"
cp "$WXT/src/zlib/zlib.h" "$WXT/src/zlib/zconf.h" "$SYS/include/"
cp "$WXT/src/expat/expat/lib/expat.h" "$WXT/src/expat/expat/lib/expat_external.h" "$SYS/include/"

# wx (gfopenwx's SDK) inside the sysroot, where a cross build's lookups go
rm -rf "$SYS/wx"; cp -a "$WX_SDK" "$SYS/wx"

# PortAudio, ours
cp "$PA_SDK/lib/libportaudio.a" "$SYS/lib/"; cp "$PA_SDK/include/portaudio.h" "$SYS/include/"
sed "s|^prefix=.*|prefix=$SYS|" "$PA_SDK/lib/pkgconfig/portaudio-2.0.pc" > "$SYS/lib/pkgconfig/portaudio-2.0.pc"
ls -l "$SYS/lib"
