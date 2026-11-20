#!/usr/bin/env bash
# One full review round against the real program, with no browser.
# Usage: test/smoke.sh <path to show-me>. Runs the same on Windows, Linux and macOS.
# Needs bash and curl. Uses its own state folder and port, so it never touches real reviews.
set -eu
X="$1"
dir="$(mktemp -d)"
# Git Bash on Windows hands out /tmp paths that a native program cannot read.
if command -v cygpath >/dev/null 2>&1; then dir="$(cygpath -m "$dir")"; fi
export SHOW_ME_STATE_DIR="$dir/state" SHOW_ME_PORT=4399 SHOW_ME_IDLE_MINUTES=0
page="$dir/plan.html"
printf '<!doctype html><title>Plan</title><body><h1 id="t">Plan</h1></body>\n' > "$page"

step() { echo "- $1"; }

step "version";            "$X" --version
step "check";              "$X" check "$page"
step "open";               url="$("$X" open "$page" --no-open)"
key="${url##*/}"; base="${url%/r/*}"
step "health";             curl -fsS "$base/health"; echo
step "review page";        curl -fsS "$base/r/$key" | grep -q "show-me"
step "page gets scripts";  curl -fsS "$base/a/$key/" | grep -q "inject.js"
step "foreign site is refused"
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Origin: http://evil.example' -d '{}' "$base/send/$key")"
test "$code" = "403"
step "send one note";      curl -fsS -X POST -H "Origin: $base" -d '{"kind":"message","note":"hello"}' "$base/send/$key"
step "wait prints it";     "$X" wait "$page" | grep -q '"note":"hello"'
step "reply";              "$X" reply "$page" "ok"
step "export";             "$X" export "$page" > /dev/null; test -f "$dir/plan.export.html"
step "setup writes skill"; "$X" setup "$dir/skill" > /dev/null; test -f "$dir/skill/SKILL.md"
if command -v dot >/dev/null 2>&1; then
    step "diagram is drawn"
    printf '<!doctype html><title>G</title><body><script type="text/vnd.graphviz">digraph { a -> b }</script></body>\n' > "$dir/g.html"
    "$X" check "$dir/g.html"
    gurl="$("$X" open "$dir/g.html" --no-open)"
    curl -fsS "${gurl%/r/*}/a/${gurl##*/}/" | grep -q "<svg"
fi
step "end";                "$X" end "$page"
step "list shows ended";   "$X" | grep -q "ended"
step "restart keeps log";  "$X" stop; "$X" open "$page" --no-open > /dev/null; "$X" | grep -q "plan.html"
step "stop";               "$X" stop
echo "smoke test passed"
