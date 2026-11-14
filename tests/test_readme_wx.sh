#!/bin/sh
# The README says what DECISION-WXWIDGETS-EXCEPTION-20261114-1543 asks: the exact wording about our wxWidgets port,
# its 3.2.12 pin and licence file, and never that it is a clean-room build.
#   sh tests/test_readme_wx.sh
# Team 2
set -eu
R="$(cd "$(dirname "$0")/.." && pwd)/README.md"
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
W='GFOpenWXToolkit is our AmigaOS port of wxWidgets, pinned to version 3.2.12. wxWidgets itself comes from the upstream project at build time and stays under its own licence; we link to the wxWidgets project (https://www.wxwidgets.org) and aim to stay compatible with it.'
check "the decision's wording, word for word" 'grep -qF "$W" "$R"'
check "the licence file named" 'grep -qF "LICENSE-wxWindows.txt" "$R"'
check "never called clean-room" '! grep -qiE "clean[- ]?room" "$R"'
[ "$fails" -eq 0 ] && echo PASS || { echo "FAILED ($fails)"; exit 1; }
