#!/bin/sh
# SQLite's amalgamation (lib-src/sqlite/sqlite3.c, one 9 MB file) is a single
# object. Inside a shared make -j run it starts late, does not finish before
# the run's time is up, and the killed compile is thrown away, run after run
# (GF-88: three runs in a row ended in it). So it is made on its own first,
# with the run's whole time, at -O1: the last -O on the line wins, and -O1
# compiles it several times faster than Release's -O3 with code that is
# still fine for a database Audacity opens once per project. The flags come
# from CMake's own flags.make, so defines and includes stay as configured;
# the object is then newer than flags.make and make leaves it alone.
#   B=.../abuild BUDGET=seconds sh scripts/sqlite-first.sh
# Does nothing when the tree is not configured yet or the object is made.
# Copyright (c) 2026 AmiCradle Team
set -eu
B=${B:?build tree}; BUDGET=${BUDGET:?seconds}; MAKE=${MAKE:-make}
D="$B/cmake-proxies/sqlite/CMakeFiles/sqlite.dir"
OBJ="$D/__/__/lib-src/sqlite/sqlite3.c.o"
[ -f "$B/.configured" ] && [ -f "$D/flags.make" ] || exit 0
[ -f "$OBJ" ] && exit 0
FLAGS=$(sed -n 's/^C_FLAGS = //p' "$D/flags.make")
echo "sqlite3.c on its own first, -O1, up to $BUDGET s"
set +e
(cd "$B" && timeout "$BUDGET" nice -n 19 $MAKE sqlite "C_FLAGS=$FLAGS -O1" > sqlite-make.log 2>&1)
rc=$?
set -e
if [ -f "$OBJ" ]; then
    echo "sqlite3.c: made"
else
    echo "sqlite3.c: not finished (make rc=$rc), run again to go on"
    tail -3 "$B/sqlite-make.log"
fi
