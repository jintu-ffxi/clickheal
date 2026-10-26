#!/usr/bin/env sh
# Runs every ClickHeal test. From anywhere:  sh tools/test.sh
# Needs a Lua interpreter (lua, luajit, lua5.4 or texlua).
cd "$(dirname "$0")/.." || exit 2

# LUA=<interpreter> picks one; otherwise the first of these found is used.
if [ -z "$LUA" ]; then
    for c in lua luajit lua5.4 lua54 lua5.3 texlua; do
        if command -v "$c" >/dev/null 2>&1; then LUA="$c"; break; fi
    done
fi
[ -n "$LUA" ] || { echo "No Lua interpreter found on PATH." >&2; exit 2; }

echo "Using $LUA"
status=0
for t in tests/run.lua tests/smoke_ashita.lua tests/config_layout.lua; do
    echo "== $t"
    "$LUA" "$t" || status=1
done
exit $status
