#!/usr/bin/env bash
# The agent's side of one review: one listener, no double notes, the reviewer leaving,
# replies from files, and the export report. Called by smoke.sh with its review open.
# Usage: smoke-agent.sh <show-me> <page> <base url> <key> <temp folder>
# Needs SHOW_ME_GRACE_SECONDS=3 on the daemon. Uses no `timeout` (macOS has none).
set -eu
X="$1"; page="$2"; base="$3"; key="$4"; dir="$5"
trap 'kill $(jobs -p) 2> /dev/null || true' EXIT
step() { echo "- $1"; }
fail() { echo "FAILED: $1"; exit 1; }
has() { grep -q -- "$2" "$1"; }
send() { curl -fsS -X POST -H "Origin: $base" -d "$1" "$base/send/$key" > /dev/null; }
# Starts one wait in the background, writing to $1. Sets $w to its process id.
bg_wait() { "$X" wait "$page" > "$1" 2>&1 & w=$!; }
running() { kill -0 "$1" 2> /dev/null; }

step "newer wait takes over, older wait stops"
bg_wait "$dir/w1.out"; w1=$w
sleep 1
bg_wait "$dir/w2.out"; w2=$w
sleep 1
send '{"kind":"message","note":"for the newer wait"}'
s1=0; wait "$w1" || s1=$?
wait "$w2"
test "$s1" != 0 || fail "the older wait exited with 0"
has "$dir/w1.out" "another wait" || fail "the older wait did not say why it stopped"
if has "$dir/w1.out" "for the newer wait"; then fail "the older wait printed the note"; fi
has "$dir/w2.out" "for the newer wait" || fail "the newer wait did not print the note"

step "one note sent twice arrives once, without its id"
body='[{"id":"5f2b8c1e-0000-4000-8000-000000000001","kind":"message","note":"only once"}]'
send "$body"; send "$body"
"$X" wait "$page" > "$dir/w3.out"
test "$(grep -c "only once" "$dir/w3.out")" = 1 || fail "the note arrived more than once"
if has "$dir/w3.out" '"id"'; then fail "the agent saw the note id"; fi

step "wait keeps waiting when no tab has shown the review yet"
bg_wait "$dir/w4.out"; sleep 10
running "$w" || fail "wait stopped before any tab showed the review: $(cat "$dir/w4.out")"
kill "$w"; wait "$w" 2> /dev/null || true

step "wait keeps waiting while one tab is open"
curl -sN "$base/events/$key" > /dev/null & tab=$!
sleep 1
bg_wait "$dir/w5.out"; sleep 10
running "$w" || fail "wait stopped while one tab was open: $(cat "$dir/w5.out")"

step "wait reports closed after the last tab closes"
kill "$tab"; wait "$tab" 2> /dev/null || true
for _ in $(seq 30); do running "$w" || break; sleep 1; done
if running "$w"; then fail "wait still waits 30 s after the last tab closed"; fi
has "$dir/w5.out" '"kind":"closed"' || fail "wait did not print the closed report: $(cat "$dir/w5.out")"

step "notes come before the closed report"
send '{"kind":"message","note":"left before closing"}'
"$X" wait "$page" > "$dir/w6.out"
has "$dir/w6.out" "left before closing" || fail "the note did not come first"

step "reply from one file keeps lines and accents"
printf 'Line one\nLine two: caf\xc3\xa9\n' > "$dir/reply.md"
"$X" reply "$page" --file "$dir/reply.md" > /dev/null
curl -fsS "$base/log/$key" | grep -q 'Line one\\nLine two: café' || fail "the reply lost its lines or accents"
"$X" wait "$page" --reply-file "$dir/reply.md" > /dev/null
test "$(curl -fsS "$base/log/$key" | grep -c 'Line one\\nLine two')" = 2 || fail "wait --reply-file sent no reply"

step "export names the files it could not include"
printf '<!doctype html><title>E</title><link rel="stylesheet" href="gone.css"><img src="https://x.example/a.png"><img src="nope.png">\n' > "$dir/e.html"
"$X" export "$dir/e.html" > "$dir/export.out"
head -1 "$dir/export.out" | grep -q "e.export.html" || fail "the first line is not the written file"
has "$dir/export.out" "gone.css" || fail "gone.css is not reported"
has "$dir/export.out" "nope.png" || fail "nope.png is not reported"
if has "$dir/export.out" "x.example"; then fail "one remote file was reported as missing"; fi
