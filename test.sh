#!/usr/bin/env bash
# Run the test suite.
#
# The game embeds Lua 5.2.2, so 5.2 is the version that matters and the one
# this script requires. A newer Lua is also run when available because it is
# stricter in useful ways - notably string.format("%d", x) errors on a
# non-integer float in 5.3+ where 5.2 silently truncates - so a 5.4 failure
# on a 5.2-green suite is usually a real latent bug, not a false alarm.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

status=0

if command -v lua5.2 >/dev/null 2>&1; then
    if lua5.2 tests/main_tests.lua >/dev/null 2>&1; then
        echo "  ok    lua5.2  (the version the game runs)"
    else
        echo "  FAIL  lua5.2  (the version the game runs)"
        lua5.2 tests/main_tests.lua 2>&1 | tail -20
        status=1
    fi
else
    echo "  MISSING lua5.2 - install it (pacman -S lua52); this is the target version"
    status=1
fi

for newer in lua5.4 lua5.3; do
    if command -v "$newer" >/dev/null 2>&1; then
        if "$newer" tests/main_tests.lua >/dev/null 2>&1; then
            echo "  ok    $newer  (stricter cross-check)"
        else
            echo "  FAIL  $newer  (stricter cross-check)"
            "$newer" tests/main_tests.lua 2>&1 | tail -20
            status=1
        fi
        break
    fi
done

exit $status
