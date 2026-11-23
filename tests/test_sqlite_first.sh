#!/bin/sh
# Unit test for scripts/sqlite-first.sh with a stand-in make: no stove needed.
#   sh tests/test_sqlite_first.sh
# Copyright (c) 2026 AmiCradle Team
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok: $1"; }
no() { fail=$((fail + 1)); echo "FAIL: $1"; }
D="$T/b/cmake-proxies/sqlite/CMakeFiles/sqlite.dir"
OBJ="$D/__/__/lib-src/sqlite/sqlite3.c.o"
# the stand-in make: writes its arguments, makes the object unless told to hang
cat > "$T/make" <<'M'
#!/bin/sh
printf '%s\n' "$@" > "$CALLS"
[ -n "${HANG:-}" ] && sleep 5
mkdir -p "$(dirname "$OBJ")"; : > "$OBJ"
M
chmod +x "$T/make"
run() { CALLS="$T/calls" OBJ="$OBJ" MAKE="$T/make" B="$T/b" BUDGET=${BUDGET:-30} sh "$HERE/scripts/sqlite-first.sh"; }

mkdir -p "$T/b"; rm -f "$T/calls"
run > "$T/out" 2>&1; [ $? -eq 0 ] && [ ! -f "$T/calls" ] && ok "not configured: no make" || no "not configured: no make"

: > "$T/b/.configured"; mkdir -p "$D"
printf 'C_DEFINES = -DSQLITE_OMIT_WAL\nC_FLAGS = -m68040 -O3 -DNDEBUG\n' > "$D/flags.make"
run > "$T/out" 2>&1
[ -f "$OBJ" ] && ok "configured: object made" || no "configured: object made"
grep -qx sqlite "$T/calls" && ok "make target is sqlite" || no "make target is sqlite"
grep -qx 'C_FLAGS=-m68040 -O3 -DNDEBUG -O1' "$T/calls" && ok "CMake's flags kept, -O1 last" || no "CMake's flags kept, -O1 last"
grep -q 'sqlite3.c: made' "$T/out" && ok "says made" || no "says made"

rm -f "$T/calls"; run > "$T/out" 2>&1
[ ! -f "$T/calls" ] && ok "object there: no make" || no "object there: no make"

rm -f "$OBJ" "$T/calls"
HANG=1 BUDGET=1 CALLS="$T/calls" OBJ="$OBJ" MAKE="$T/make" B="$T/b" sh "$HERE/scripts/sqlite-first.sh" > "$T/out" 2>&1; rc=$?
[ $rc -eq 0 ] && ok "out of time: exit 0" || no "out of time: exit 0 (rc $rc)"
grep -q 'run again' "$T/out" && ok "out of time: says run again" || no "out of time: says run again"
[ ! -f "$OBJ" ] && ok "out of time: no object" || no "out of time: no object"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
