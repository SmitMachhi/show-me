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
# Waits up to $2 seconds for process $1 and returns its exit code. Never blocks forever:
# a process still running then is stopped, and the step fails with $3.
finish() {
    for _ in $(seq "$2"); do
        if ! running "$1"; then wait "$1"; return $?; fi
        sleep 1
    done
    kill "$1"; fail "$3"
}
# Runs one wait that must return within 20 s, writing to $1. Extra arguments go to wait.
wait_once() { out="$1"; shift; "$X" wait "$page" "$@" > "$out" 2>&1 & finish $! 20 "wait did not return within 20 s"; }

step "newer wait takes over, older wait stops"
bg_wait "$dir/w1.out"; w1=$w
sleep 1
bg_wait "$dir/w2.out"; w2=$w
# The older wait stops as soon as the newer one owns the review. Send after that.
s1=0; finish "$w1" 20 "the older wait did not stop" || s1=$?
send '{"kind":"message","note":"for the newer wait"}'
finish "$w2" 20 "the newer wait did not print the note"
test "$s1" != 0 || fail "the older wait exited with 0"
has "$dir/w1.out" "another wait" || fail "the older wait did not say why it stopped"
if has "$dir/w1.out" "for the newer wait"; then fail "the older wait printed the note"; fi
has "$dir/w2.out" "for the newer wait" || fail "the newer wait did not print the note"

step "one note sent twice arrives once, without its id"
body='[{"id":"5f2b8c1e-0000-4000-8000-000000000001","kind":"message","note":"only once"}]'
send "$body"; send "$body"
wait_once "$dir/w3.out"
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
wait_once "$dir/w6.out"
has "$dir/w6.out" "left before closing" || fail "the note did not come first"

step "reply from one file keeps lines and accents"
printf 'Line one\nLine two: caf\xc3\xa9\n' > "$dir/reply.md"
"$X" reply "$page" --file "$dir/reply.md" > /dev/null
curl -fsS "$base/log/$key" | grep -q 'Line one\\nLine two: café' || fail "the reply lost its lines or accents"
wait_once "$dir/w7.out" --reply-file "$dir/reply.md"
test "$(curl -fsS "$base/log/$key" | grep -c 'Line one\\nLine two')" = 2 || fail "wait --reply-file sent no reply"

step "export names the files it could not include"
printf '<!doctype html><title>E</title><link rel="stylesheet" href="gone.css"><img src="https://x.example/a.png"><img src="nope.png">\n' > "$dir/e.html"
"$X" export "$dir/e.html" > "$dir/export.out"
head -1 "$dir/export.out" | grep -q "e.export.html" || fail "the first line is not the written file"
has "$dir/export.out" "gone.css" || fail "gone.css is not reported"
has "$dir/export.out" "nope.png" || fail "nope.png is not reported"
if has "$dir/export.out" "x.example"; then fail "one remote file was reported as missing"; fi

step "one file edit after delivery writes one working line, even with two tabs"
curl -sN "$base/events/$key" > /dev/null & t1=$!
curl -sN "$base/events/$key" > /dev/null & t2=$!
send '{"kind":"message","note":"edit the title"}'
wait_once "$dir/w8.out"
sleep 1
printf '<!doctype html><title>Plan</title><body><h1 id="t">Plan, edited</h1></body>\n' > "$page"
sleep 2
log="$(curl -fsS "$base/log/$key")"
test "$(printf '%s\n' "$log" | grep -c '"t":"working"')" = 1 || fail "expected one working line: $log"
"$X" reply "$page" "done" > /dev/null
printf '<!doctype html><title>Plan</title><body><h1 id="t">Plan, edited again</h1></body>\n' > "$page"
sleep 2
test "$(curl -fsS "$base/log/$key" | grep -c '"t":"working"')" = 1 || fail "one edit after the reply wrote one more working line"
kill "$t1" "$t2"; wait "$t1" "$t2" 2> /dev/null || true

step "notes, acks and replies carry their time"
curl -fsS "$base/log/$key" | grep -q '"t":"at","ms":[0-9]' || fail "no time lines in the log"
head -1 "$dir/state/$key.jsonl" | grep -q '"t":"open"' || fail "the open line is not first"

step "one file the page loads for the first time is not one change"
printf 'h1 { color: red; }\n' > "$dir/extra.css"
curl -sN "$base/events/$key" > "$dir/events.out" & t3=$!
sleep 1
working_before="$(curl -fsS "$base/log/$key" | grep -c '"t":"working"' || true)"
send '{"kind":"message","note":"one more"}'
wait_once "$dir/w9.out"
curl -fsS "$base/a/$key/extra.css" > /dev/null
sleep 1.5
if grep -q "data: reload" "$dir/events.out"; then fail "fetching one new file reloaded the page"; fi
test "$(curl -fsS "$base/log/$key" | grep -c '"t":"working"')" = "$working_before" || fail "fetching one new file wrote one working line"
printf 'h1 { color: blue; }\n' > "$dir/extra.css"
sleep 1.5
test "$(grep -c "data: reload" "$dir/events.out")" = 1 || fail "one edit of one loaded file did not reload the page once"
kill "$t3"; wait "$t3" 2> /dev/null || true

step "the frame names one missing page file"
mv "$page" "$page.gone"
body="$(curl -s "$base/a/$key/")"
mv "$page.gone" "$page"
echo "$body" | grep -q "missing" || fail "no missing-file message: $body"
echo "$body" | grep -q "plan.html" || fail "the message does not name the file"

step "one browser request cannot wait"
code="$(curl -s -o /dev/null -w '%{http_code}' -H 'Sec-Fetch-Site: same-origin' "$base/wait/$key")"
test "$code" = 403 || fail "one browser request to /wait got $code"
