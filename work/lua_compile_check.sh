#!/usr/bin/env bash
# Compile every Lua file this package ships with a real Lua 5.1 compiler.
#
# GMod runs Lua 5.1, so `luac -p` is a genuine syntax check: it parses and
# compiles each chunk without executing it. No Lua toolchain is installed on
# this machine by default; build one with
#   curl -sSL -o /tmp/lua.tgz https://www.lua.org/ftp/lua-5.1.5.tar.gz
#   tar xzf /tmp/lua.tgz -C /tmp && make -C /tmp/lua-5.1.5/src luac CC=gcc
# or point LUAC at an existing binary.
set -uo pipefail
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
luac="${LUAC:-}"
if [ -z "$luac" ]; then
    for candidate in /tmp/lua-5.1.5/src/luac lua5.1 luac5.1 luac; do
        if command -v "$candidate" >/dev/null 2>&1; then luac="$candidate"; break; fi
    done
fi
if [ -z "$luac" ]; then
    echo "no luac found; set LUAC=/path/to/luac" >&2
    exit 127
fi
fail=0
while IFS= read -r file; do
    if "$luac" -p "$file" 2>/tmp/luac-err.$$; then
        echo "ok   ${file#"$root"/}"
    else
        echo "FAIL ${file#"$root"/}"
        sed 's/^/     /' /tmp/luac-err.$$
        fail=1
    fi
done < <(find "$root/work/gquest-ui" "$root/work/gquest-arcvr/content" -name '*.lua' | sort)
rm -f /tmp/luac-err.$$
exit "$fail"
