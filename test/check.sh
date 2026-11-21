#!/usr/bin/env bash
# Every check that must pass before one commit, in one command: test/check.sh
# Builds show-me, runs the unit tests, checks each browser script, enforces the size
# rules in AGENTS.md, finds element ids used twice, then runs the smoke test.
# Needs zig 0.17.1 (on PATH or in ZIG), node, bash, curl and GNU awk. Pandoc is optional.
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

echo "== named functions under 50 lines"
# From one "function name" or "fn name" line to the closing brace at the same indent.
# One script's outer (function () { ... })() wrapper is its scope, not one function.
long_fns="$(for f in src/*.js src/*.zig; do awk -v F="$f" '
    match($0, /^( *)(export )?(pub )?(async )?(function|fn) ([A-Za-z_][A-Za-z0-9_]*)/, m) { if (!open) { ind = m[1]; name = m[6]; start = NR; open = 1; next } }
    open && $0 ~ "^" ind "}" { if (NR - start + 1 > 50) printf "%s:%d %s is %d lines\n", F, start, name, NR - start + 1; open = 0 }
' "$f"; done)"
if [ -n "$long_fns" ]; then echo "$long_fns"; exit 1; fi

echo "== each element id used once"
# Ids in the panel page, plus ids that panel scripts give to elements they make.
dupes="$(grep -ohE 'id="[A-Za-z][A-Za-z0-9_-]*"|\.id = "[A-Za-z][A-Za-z0-9_-]*"' src/ui.html src/ui*.js |
    sed -E 's/.*"(.*)"/\1/' | sort | uniq -d)"
if [ -n "$dupes" ]; then echo "used twice: $dupes"; exit 1; fi

echo "== frame sandbox matches the page header"
# The frame attribute (ui.html) and the CSP header on each page (pages.zig) must allow the same.
words() { tr ' ' '\n' | sort | tr '\n' ' '; }
frame_sb="$(grep -o 'sandbox="[^"]*"' src/ui.html | sed 's/sandbox="//; s/"$//' | words)"
header_sb="$(grep -o 'value = "sandbox [^"]*"' src/pages.zig | sed 's/value = "sandbox //; s/"$//' | words)"
if [ -z "$frame_sb" ] || [ "$frame_sb" != "$header_sb" ]; then echo "frame: $frame_sb"; echo "header: $header_sb"; exit 1; fi

echo "== no indefinite articles in the README and the skill"
# The owner's writing rule. The DOT examples hold no "a" or "an" as one word.
arts="$(grep -nwiE 'a|an' README.md src/skill/SKILL.md || true)"
if [ -n "$arts" ]; then echo "$arts"; exit 1; fi

echo "== README and skill follow the owner's writing rules (needs pandoc)"
# The same rules show-me check applies to pages, run on the two documents people read.
if command -v pandoc > /dev/null 2>&1; then
    mkdir -p zig-out/prose
    for f in README.md src/skill/SKILL.md; do
        pandoc "$f" -o zig-out/prose/doc.html --standalone --metadata title=doc 2> /dev/null
        printf 'no-indefinite-articles\nno-em-dash\nno-contractions\nmax-sentence-words 25\n' > zig-out/prose/rules
        SHOW_ME_STATE_DIR=zig-out/prose "$exe" check zig-out/prose/doc.html > /dev/null || { echo "$f breaks one writing rule"; SHOW_ME_STATE_DIR=zig-out/prose "$exe" check zig-out/prose/doc.html; exit 1; }
    done
fi

echo "== smoke test"
bash test/smoke.sh "$exe"
echo "all checks passed"
