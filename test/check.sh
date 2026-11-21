#!/usr/bin/env bash
# Every check that must pass before one commit, in one command: test/check.sh
# Builds show-me, runs the unit tests, checks each browser script, enforces the size
# rules in AGENTS.md, finds element ids used twice, then runs the smoke test.
# Needs zig 0.17.1 (on PATH or in ZIG), node, bash and curl.
set -eu
cd "$(dirname "$0")/.."
ZIG="${ZIG:-zig}"
exe="zig-out/show-me"
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) exe="$exe.exe" ;; esac

echo "== build"
"$ZIG" build-exe src/main.zig -O ReleaseSafe -femit-bin="$exe"

echo "== unit tests"
for f in src/*.zig; do
    if grep -q '^test "' "$f"; then "$ZIG" test "$f" 2>&1 | tail -1; fi
done

echo "== browser scripts parse"
for f in src/*.js; do node --check "$f"; done

echo "== files under 200 lines"
long="$(wc -l src/*.zig src/*.js src/*.css src/*.html src/skill/* test/*.sh | awk '$2 != "total" && $1 >= 200')"
if [ -n "$long" ]; then echo "$long"; echo "split these files"; exit 1; fi

echo "== each element id used once"
# Ids in the panel page, plus ids that panel scripts give to elements they make.
dupes="$(grep -ohE 'id="[A-Za-z][A-Za-z0-9_-]*"|\.id = "[A-Za-z][A-Za-z0-9_-]*"' src/ui.html src/ui*.js |
    sed -E 's/.*"(.*)"/\1/' | sort | uniq -d)"
if [ -n "$dupes" ]; then echo "used twice: $dupes"; exit 1; fi

echo "== smoke test"
bash test/smoke.sh "$exe"
echo "all checks passed"
