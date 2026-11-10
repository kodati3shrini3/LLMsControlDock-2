#!/usr/bin/env bash
# Smoke test and load test for the built LLMsControlDock program (read-only; it never loads, unloads, deletes or tunes a model).
# Usage: bash scripts/test-smoke-load.sh [path-to-program] [port]     (defaults: bin/LLMsControlDock and 8799)
# Optional settings in the environment: LCD_LOAD_SECONDS (default 20), LCD_LOAD_PARALLEL (default 10), LCD_P95_MS (default 1000).
#
# How it stays safe: it starts its OWN copy of the program on another port, with a throw-away HOME folder, so your real settings, saved results and your running monitor are not touched.
# The only requests that are not plain page reads are the ones a person's browser also makes on the very first start (Continue, and a theme choice), and they go to that throw-away copy.
#
# Stop at the first unset variable or failed step inside a pipe (not on every failed check: failed checks are counted and reported).
set -uo pipefail

# The program to test: the first argument, or the one the project builds.
BIN="${1:-bin/LLMsControlDock}"
# The port for the test copy: the second argument, or 8799 (the normal monitor uses 8765).
PORT="${2:-8799}"
# How long the load phase lasts, in seconds.
LOAD_SECONDS="${LCD_LOAD_SECONDS:-20}"
# How many requests run at the same time in the load phase.
LOAD_PARALLEL="${LCD_LOAD_PARALLEL:-10}"
# The slowest acceptable 95th percentile answer time under load, in milliseconds.
P95_LIMIT_MS="${LCD_P95_MS:-1000}"
# The address of the test copy; "127.0.0.1" is this computer only.
BASE="http://127.0.0.1:${PORT}"

# Count of passed checks.
PASS=0
# Count of failed checks.
FAIL=0
# ok prints one PASS line and counts it; it is only called after a real check succeeded.
ok() { printf 'PASS  %-58s %s\n' "$1" "${2:-}"; PASS=$((PASS + 1)); }
# bad prints one FAIL line and counts it; the test goes on so that one run shows every problem.
bad() { printf 'FAIL  %-58s %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

# The program file must exist and be runnable.
[ -x "$BIN" ] || { echo "FAIL  the program $BIN does not exist or is not executable (build it first: go build -o bin/LLMsControlDock .)"; exit 1; }
# curl is the only tool the test needs besides the shell and awk.
command -v curl >/dev/null || { echo "FAIL  curl is not installed"; exit 1; }
# awk calculates the answer-time figures.
command -v awk >/dev/null || { echo "FAIL  awk is not installed"; exit 1; }
# Nothing else may already answer on the test port, otherwise the test would measure something else.
if curl -s -o /dev/null --max-time 1 "$BASE/about"; then echo "FAIL  something already answers on port $PORT; choose another port as the second argument"; exit 1; fi

# A throw-away folder for the test copy's settings, saved results and notes.
WORK="$(mktemp -d)"
# The program's process number, filled in when it starts.
PID=""
# cleanup stops the test copy and removes the throw-away folder, whatever happens.
cleanup() {
  # Stop the program only if it was started.
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  # Remove the folder.
  rm -rf "$WORK"
}
# Run cleanup when the script ends, is interrupted or fails.
trap cleanup EXIT

# Say what is being tested.
echo "Program: $BIN ($(sha256sum "$BIN" | cut -c1-12)...)   test copy: $BASE   throw-away HOME: $WORK"
# Start the test copy: its own HOME, no XDG folders from the real session, so nothing real is read or written.
env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME HOME="$WORK" "$BIN" -listen "127.0.0.1:${PORT}" >"$WORK/program.log" 2>&1 &
# Remember its process number.
PID=$!

# Wait up to 10 seconds until the page answers.
UP=0
# Twenty tries, half a second apart.
for _ in $(seq 1 20); do
  # An answer means the program is up.
  if curl -s -o /dev/null --max-time 1 "$BASE/about"; then UP=1; break; fi
  # Wait a little.
  sleep 0.5
# End of the waiting loop.
done
# Without an answer nothing else can be tested.
[ "$UP" = 1 ] || { echo "FAIL  the test copy did not start; its log follows"; cat "$WORK/program.log"; exit 1; }
# Show which Ollama the test copy talks to (the first log line says it).
echo "Ollama:  $(grep -m1 'Ollama address' "$WORK/program.log" | sed 's/^[0-9/]* [0-9:]* //')"
# A blank line before the checks.
echo

# page_check label path want_status want_type_start want_text: one plain page read; the text may be empty when only the status matters.
page_check() {
  # The five arguments, named.
  local label="$1" path="$2" want_status="$3" want_type="$4" want_text="$5"
  # Fetch the page, keep the body in a file, print the status, type and time.
  local out; out="$(curl -s -o "$WORK/body" -w '%{http_code} %{content_type} %{time_total}' --max-time 15 "${BASE}${path}")"
  # The status is the first word.
  local status="${out%% *}"
  # The rest holds the type and the time.
  local rest="${out#* }"
  # The type is the next word (up to the semicolon of the charset).
  local ctype="${rest%% *}"; ctype="${ctype%;}"
  # The time is the last word.
  local secs="${out##* }"
  # The status must match.
  if [ "$status" != "$want_status" ]; then bad "$label" "status $status, wanted $want_status"; return; fi
  # The type must start as wanted (when one is wanted).
  if [ -n "$want_type" ] && [ "${ctype#"$want_type"}" = "$ctype" ]; then bad "$label" "type $ctype, wanted $want_type"; return; fi
  # The text must be in the body (when one is wanted).
  if [ -n "$want_text" ] && ! grep -qF -- "$want_text" "$WORK/body"; then bad "$label" "text \"$want_text\" is missing"; return; fi
  # Everything matched.
  ok "$label" "($status, ${secs}s)"
}

# post_check label path want_status extra-curl-arguments...: one form post, to the test copy only.
post_check() {
  # The label, the path and the wanted status.
  local label="$1" path="$2" want_status="$3"
  # Drop those three; the rest goes to curl.
  shift 3
  # Send the post; print the status and where it redirects to.
  local out; out="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 15 "$@" "${BASE}${path}")"
  # The status is the first word.
  local status="${out%% *}"
  # The status must match.
  if [ "$status" != "$want_status" ]; then bad "$label" "status $status, wanted $want_status"; return; fi
  # Matched.
  ok "$label" "($out)"
}

# header_check label path header-text: the page's answer must carry this header text (a name and part of its value).
header_check() {
  # The three arguments.
  local label="$1" path="$2" want="$3"
  # Fetch the page and keep only the headers.
  curl -s -D "$WORK/headers" -o /dev/null --max-time 15 "${BASE}${path}"
  # Look for the text, ignoring upper and lower case in the name.
  if grep -qiF -- "$want" "$WORK/headers"; then ok "$label"; else bad "$label" "header \"$want\" is missing"; fi
}

# ---------------------------------------------------------------- SMOKE TEST
# Title of the first part.
echo "== Smoke test (reads every page once; changes nothing real)"
# First start: the home page sends a new person to the System check.
OUT="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$BASE/")"
# It must be a redirect to the System check.
if [ "$OUT" = "303 ${BASE}/systemcheck" ]; then ok "first start: home page sends you to the System check" "($OUT)"; else bad "first start: home page sends you to the System check" "got: $OUT"; fi
# The System check itself; it measures the computer, so it may take a moment.
page_check "System check page" /systemcheck 200 text/html "System check"

# The form token is in the System check page; a browser would send it back.
TOKEN="$(curl -s "$BASE/systemcheck" | grep -o 'name="token" value="[0-9a-f]*"' | head -1 | sed 's/.*value="//; s/"//')"
# Without a token nothing below can work.
if [ -n "$TOKEN" ]; then ok "form token found in the System check page"; else bad "form token found in the System check page"; fi
# The address a browser page would announce as its origin.
ORIGIN="http://127.0.0.1:${PORT}"

# A request that claims another computer's name must be refused (this is what a web page on another site could try).
OUT="$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: evil.example' "$BASE/about")"
# Refused means 403.
if [ "$OUT" = "403" ]; then ok "a page asked for under a foreign Host name is refused" "($OUT)"; else bad "a page asked for under a foreign Host name is refused" "got $OUT, wanted 403"; fi
# A post with no Origin (not from a browser page) must be refused.
post_check "post without Origin is refused" /systemcheck/continue 403 -d "token=${TOKEN}"
# A post from another website must be refused.
post_check "post from a foreign Origin is refused" /systemcheck/continue 403 -H 'Origin: http://evil.example' -d "token=${TOKEN}"
# A post from the right page with a wrong token must be refused.
post_check "post with a wrong token is refused" /systemcheck/continue 403 -H "Origin: ${ORIGIN}" -d "token=wrong"
# A post from the right page with the right token: this is "Continue to the monitor" (it goes to the throw-away copy only).
post_check "Continue to the monitor is accepted" /systemcheck/continue 303 -H "Origin: ${ORIGIN}" -d "token=${TOKEN}"
# A theme choice, as the theme button sends it.
post_check "theme choice is accepted" /theme 303 -H "Origin: ${ORIGIN}" -d "theme=dark&token=${TOKEN}"

# Every page, now that the first start is done.
page_check "monitor (home) page" / 200 text/html "LLMsControlDock"
# The About page.
page_check "About page" /about 200 text/html "About LLMsControlDock"
# The Help page.
page_check "Help page" /help 200 text/html "Help"
# The Help page must carry all thirteen topics.
TOPICS="$(grep -o '<details class="helptopic"' "$WORK/body" | wc -l)"
# Count them.
if [ "$TOPICS" = "13" ]; then ok "Help page has 13 topics"; else bad "Help page has 13 topics" "found $TOPICS"; fi
# The Settings page.
page_check "Settings page" /settings 200 text/html "Settings"
# The Find LLM page (only the choices; this does not search the internet).
page_check "Find LLM page" /findllm 200 text/html "Find LLM"
# The Uninstall page only shows what would be removed.
page_check "Uninstall page (shows only, removes nothing)" /uninstall 200 text/html "Uninstall LLMsControlDock"
# The re-test status page.
page_check "re-test status page" /compare/retest/status 200 text/html ""
# The style sheet and the pictures.
page_check "style sheet" /app.css 200 text/css ""
# The program icon.
page_check "icon picture" /icon.png 200 image/png ""
# The company logo.
page_check "logo picture" /termgate-logo.png 200 image/png ""
# The six small script files.
for JS in countdown copy sortpick helpclose loading attention; do
  # Each must be sent as JavaScript.
  page_check "script file ${JS}.js" "/${JS}.js" 200 text/javascript ""
# End of the script list.
done
# A page that does not exist.
page_check "unknown address gives 404" /nothere 404 "" ""
# A change-only address asked with a plain read must be refused, not run.
page_check "reading a change-only address gives 405" /unload 405 "" ""
# The safety headers on a page.
header_check "page carries a Content-Security-Policy" /about "Content-Security-Policy: default-src 'none'"
# The browser may not guess types.
header_check "page carries X-Content-Type-Options: nosniff" /about "X-Content-Type-Options: nosniff"
# The page must not be cached.
header_check "page carries Cache-Control: no-store" /about "Cache-Control: no-store"
# The program must not have crashed while answering.
if grep -qi 'panic' "$WORK/program.log"; then bad "no panic in the program log"; else ok "no panic in the program log"; fi
# The program must still be running.
if kill -0 "$PID" 2>/dev/null; then ok "program is still running after the smoke test"; else bad "program is still running after the smoke test"; fi

# ---------------------------------------------------------------- LOAD TEST
# A blank line, then the title of the second part.
echo
echo "== Load test (${LOAD_PARALLEL} parallel readers for ${LOAD_SECONDS} s; the monitor page also reads Ollama's light status endpoints)"
# The memory the program uses before the load, in kilobytes (Linux only; other systems show n/a).
rss_kb() { if [ -r "/proc/$PID/status" ]; then awk '/^VmRSS:/ {print $2}' "/proc/$PID/status"; else echo ""; fi; }
# Before the load.
RSS_BEFORE="$(rss_kb)"
# The pages the readers ask for, one after the other.
LOAD_PATHS=(/ /help /about /settings /findllm /app.css)
# worker N: ask for the pages again and again until the time is up; every answer is one line "status seconds" in the worker's own file.
worker() {
  # The worker's number.
  local n="$1"
  # The time (in shell seconds) at which to stop.
  local end=$((SECONDS + LOAD_SECONDS))
  # Keep going until then.
  while [ "$SECONDS" -lt "$end" ]; do
    # One round through the pages.
    for P in "${LOAD_PATHS[@]}"; do
      # Ask once; record the status and the time; a timeout shows as status 000.
      curl -s -o /dev/null -w '%{http_code} %{time_total}\n' --max-time 10 "${BASE}${P}" >>"$WORK/w${n}.txt" || true
    # End of one round.
    done
  # End of the loop.
  done
}
# Remember when the load started, for the requests-per-second figure.
T0=$SECONDS
# The readers' process numbers, to wait for exactly these (not for the program).
WPIDS=()
# Start all readers at once.
for N in $(seq 1 "$LOAD_PARALLEL"); do worker "$N" & WPIDS+=("$!"); done
# Wait for all the readers.
wait "${WPIDS[@]}"
# How long the load really lasted.
ELAPSED=$((SECONDS - T0))
# Never divide by zero.
[ "$ELAPSED" -ge 1 ] || ELAPSED=1
# Put all answers together.
cat "$WORK"/w*.txt > "$WORK/all.txt"
# The number of requests.
TOTAL="$(wc -l < "$WORK/all.txt")"
# The number of answers that were not "200".
ERRORS="$(awk '$1 != 200' "$WORK/all.txt" | wc -l)"
# The answer-time figures in milliseconds: median, 95th percentile, slowest.
read -r P50 P95 PMAX < <(awk '{print $2*1000}' "$WORK/all.txt" | sort -n | awk '{a[NR]=$1} END {if (NR==0) {print 0, 0, 0} else {printf "%d %d %d\n", a[int((NR+1)/2)], a[int(NR*0.95 > 1 ? NR*0.95 : 1)], a[NR]}}')
# The memory after the load.
RSS_AFTER="$(rss_kb)"
# Show the figures as a small table.
printf '\n%-34s %s\n' "Requests answered" "$TOTAL in ${ELAPSED} s ($((TOTAL / ELAPSED)) per second)"
# Answers that were not 200.
printf '%-34s %s\n' "Answers that were not 200" "$ERRORS"
# The times.
printf '%-34s %s\n' "Answer time median / 95th / slowest" "${P50} ms / ${P95} ms / ${PMAX} ms"
# The memory figures.
if [ -n "$RSS_BEFORE" ] && [ -n "$RSS_AFTER" ]; then printf '%-34s %s\n' "Program memory before / after" "$((RSS_BEFORE / 1024)) MB / $((RSS_AFTER / 1024)) MB"; else printf '%-34s %s\n' "Program memory before / after" "n/a on this system"; fi
# A blank line.
echo
# Checks on the load.
if [ "$TOTAL" -gt 0 ]; then ok "load: requests were answered" "($TOTAL)"; else bad "load: requests were answered" "none"; fi
# No errors allowed.
if [ "$ERRORS" = "0" ]; then ok "load: every answer was 200"; else bad "load: every answer was 200" "$ERRORS were not"; fi
# The 95th percentile must stay under the limit.
if [ "$P95" -le "$P95_LIMIT_MS" ]; then ok "load: 95th percentile within ${P95_LIMIT_MS} ms" "(${P95} ms)"; else bad "load: 95th percentile within ${P95_LIMIT_MS} ms" "${P95} ms"; fi
# The program must have survived.
if kill -0 "$PID" 2>/dev/null; then ok "load: program is still running"; else bad "load: program is still running"; fi
# And it must still answer normally after the load.
page_check "load: About page still answers afterwards" /about 200 text/html "About LLMsControlDock"
# And it must not have crashed with a panic.
if grep -qi 'panic' "$WORK/program.log"; then bad "load: no panic in the program log"; else ok "load: no panic in the program log"; fi

# ---------------------------------------------------------------- RESULT
# The summary line.
echo
echo "Result: $PASS passed, $FAIL failed"
# The exit status: 0 when everything passed.
[ "$FAIL" = 0 ]
