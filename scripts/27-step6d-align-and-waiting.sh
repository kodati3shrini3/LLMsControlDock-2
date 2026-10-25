#!/usr/bin/env bash
# Script 27: Step 6d, the Load and Unload buttons line up, and the load warning page shows a waiting message with a moving bar and the seconds passed once Yes is pressed.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"
# Address of the Ollama used for the real run; override it to test another server.
OLLAMA_TEST_URL="${OLLAMA_TEST_URL:-http://127.0.0.1:11434}"
# Spare port for the page check, so it never collides with a real monitor on 8765 or with the earlier scripts.
TEST_PORT="${TEST_PORT:-18773}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"

# Write loading.go (the route handler for the waiting script); the quoted marker saves every character exactly as typed.
cat > loading.go << 'EOF_LOADING'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// embed lets the script file be stored inside the executable (the blank name means we only need its side effect).
	_ "embed"
	// net/http provides requests and status codes.
	"net/http"
) // end of imports

// loadingJS is the small script that shows the waiting message while a model loads, stored inside the executable at build time (requirement T3).
//
//go:embed web/loading.js
var loadingJS []byte

// loadingHandler sends the script file.
func loadingHandler(w http.ResponseWriter, r *http.Request) {
	// Tell the browser this is JavaScript.
	w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
	// Send it.
	w.Write(loadingJS)
} // end of loadingHandler
EOF_LOADING

# Write web/loading.js (the small script that shows the waiting message).
cat > web/loading.js << 'EOF_LJS'
// Loading message: when the person confirms a load, hide the buttons, show the waiting box and count the seconds, because Ollama gives no percentage while it reads a model into memory.
(function () {
  // Find the confirm form of the load page (it is marked data-loading); other pages have none.
  var form = document.querySelector('form[data-loading]');
  // The box that holds the waiting message, and the buttons that it replaces.
  var box = document.getElementById('loading');
  // The row with the Yes and Cancel choices.
  var choices = document.getElementById('choices');
  // Nothing to do when this page has no such parts.
  if (!form || !box || !choices) {
    // Stop here.
    return;
  }
  // The place where the passed seconds are written.
  var elapsed = box.querySelector('.elapsed');
  // The repeating timer, kept so that it can be stopped.
  var timer = null;
  // Turn a number of seconds into wording: "45 s" or "2 min 5 s".
  function words(total) {
    // Whole minutes.
    var m = Math.floor(total / 60);
    // Seconds left over.
    var s = total % 60;
    // With minutes, show both.
    if (m > 0) {
      // Minutes and seconds.
      return m + ' min ' + s + ' s';
    }
    // Otherwise only seconds.
    return s + ' s';
  }
  // Put the page back as it was (used when the person comes back with the Back button and the browser kept the page in memory).
  function reset() {
    // Stop the timer.
    if (timer !== null) {
      // Cancel the repeat.
      clearInterval(timer);
      // Remember that it is stopped.
      timer = null;
    }
    // Hide the waiting message.
    box.hidden = true;
    // Show the buttons again.
    choices.hidden = false;
  }
  // When the form is sent, show the waiting message.
  form.addEventListener('submit', function () {
    // The steady clock, so a change of the computer clock does not matter.
    var start = performance.now();
    // Do the changes just after the browser has started sending the form, so the form data is certainly complete.
    setTimeout(function () {
      // Hide the buttons: this also stops a second click and a second load.
      choices.hidden = true;
      // Show the waiting message.
      box.hidden = false;
      // Write the first value at once.
      elapsed.textContent = words(0);
      // Then update every second.
      timer = setInterval(function () {
        // Whole seconds since the form was sent.
        elapsed.textContent = words(Math.floor((performance.now() - start) / 1000));
      }, 1000);
    }, 0);
  });
  // The page can come back from the browser's memory after Back; then the waiting state must not stay.
  window.addEventListener('pageshow', function (e) {
    // Only a page restored from memory needs the reset.
    if (e.persisted) {
      // Reset it.
      reset();
    }
  });
})();
EOF_LJS

# Write loading_test.go.
cat > loading_test.go << 'EOF_LOADTEST'
// Package main tells Go that this test file belongs to the same program as loading.go.
package main

import ( // import lists the packages this test file uses.
	// net/http provides requests and status codes.
	"net/http"
	// net/url builds form data.
	"net/url"
	// regexp counts and finds pieces of the page.
	"regexp"
	// strings searches the page text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// TestLoadWarningHasWaitingBox checks the warning page carries the hidden waiting box, the marked form and the script, and nothing that could run inline.
func TestLoadWarningHasWaitingBox(t *testing.T) {
	// Nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Ask to load.
	res := post(t, rig.h, "/load", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// Read the page.
	body := bodyOf(res)
	// Every part the script needs, and the honest wording.
	for _, want := range []string{`<form method="post" action="/load/confirm" data-loading>`, `id="choices"`, `id="loading" role="status" aria-live="polite" hidden`, `class="elapsed"`, `<script src="/loading.js" defer></script>`, "not a percentage"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("warning page lacks %q", want)
		} // end of the check
	} // end of the loop
	// Exactly one script tag, and it is the monitor's own file (no inline code).
	if n := len(regexp.MustCompile(`<script`).FindAllString(body, -1)); n != 1 || strings.Contains(body, "<script>") {
		// Report the problem.
		t.Errorf("unexpected script tags: %d", n)
	} // end of the script check
	// No style attributes either, because the policy forbids inline styles.
	if strings.Contains(body, ` style=`) {
		// Report the problem.
		t.Errorf("the page has an inline style")
	} // end of the style check
	// The policy allows the monitor's own script only.
	if csp := res.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe-inline") {
		// Report the problem.
		t.Errorf("unexpected policy: %s", csp)
	} // end of the policy check
	// Still nothing was sent to Ollama.
	if n := f.callCount(); n != 0 {
		// Report the problem.
		t.Errorf("the first step sent %d requests", n)
	} // end of the effect check
} // end of TestLoadWarningHasWaitingBox

// TestOtherLoadPagesHaveNoLoadingScript checks only the warning page gets the waiting script.
func TestOtherLoadPagesHaveNoLoadingScript(t *testing.T) {
	// One model loaded.
	f := &loadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Ask to load a model that is already loaded.
	res := post(t, rig.h, "/load", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// No loading script and the strict policy.
	if body := bodyOf(res); strings.Contains(body, "loading.js") || strings.Contains(res.Header.Get("Content-Security-Policy"), "script-src") {
		// Report the problem.
		t.Errorf("an ordinary message page allows or contains the loading script")
	} // end of the check
} // end of TestOtherLoadPagesHaveNoLoadingScript

// TestLoadingScriptIsServed checks the script file is sent as JavaScript and contains the pieces that matter.
func TestLoadingScriptIsServed(t *testing.T) {
	// Nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Fetch the script.
	status, header, body := get(t, rig.h, http.MethodGet, "/loading.js")
	// Found, typed as JavaScript, with the timer and the Back-button reset.
	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/javascript") || !strings.Contains(body, "setInterval") || !strings.Contains(body, "pageshow") {
		// Report the problem.
		t.Errorf("status %d, type %q", status, header.Get("Content-Type"))
	} // end of the check
	// The script file is read-only content: a POST must be refused.
	if res := post(t, rig.h, "/loading.js", url.Values{}, fromThisPage); res.StatusCode != http.StatusMethodNotAllowed {
		// Report the problem.
		t.Errorf("POST /loading.js = %d, want 405", res.StatusCode)
	} // end of the method check
} // end of TestLoadingScriptIsServed

// TestStateCellsAreAligned checks every state cell has the fixed-width label, so the buttons start at the same place.
func TestStateCellsAreAligned(t *testing.T) {
	// One model loaded, one not.
	f := &loadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Fetch the page.
	_, _, body := get(t, rig.h, http.MethodGet, "/")
	// Two models, so two labels.
	if n := strings.Count(body, `<span class="statelabel">`); n != 2 {
		// Report the difference.
		t.Errorf("state labels = %d, want 2", n)
	} // end of the count
} // end of TestStateCellsAreAligned

// TestLoadingStyles checks the stylesheet has the new rules.
func TestLoadingStyles(t *testing.T) {
	// The stylesheet text.
	css := string(appCSS)
	// Each of these protects one behaviour.
	for name, want := range map[string]string{
		// The fixed-width label that aligns the buttons.
		"state label": ".statelabel {",
		// The label has a minimum width.
		"label width": "min-width: 8rem",
		// The moving bar.
		"bar": ".barfill {",
		// Its movement.
		"bar movement": "@keyframes slide",
		// People who ask for less motion get a still bar.
		"reduced motion": "prefers-reduced-motion: reduce",
		// The hidden attribute must win over every display rule.
		"hidden wins": "[hidden] {",
	} { // end of the map
		// Look for it.
		if !strings.Contains(css, want) {
			// Report the gap.
			t.Errorf("stylesheet lacks %s (%q)", name, want)
		} // end of the check
	} // end of the loop
} // end of TestLoadingStyles
EOF_LOADTEST

# Edit the existing files with a small Python program; the quoted EOF_PY27 marker saves every character exactly as typed.
python3 - << 'EOF_PY27'
# pathlib reads and writes the files.
import pathlib

# replace_once(file, old, new): swap text that must appear exactly once; stop with a message if it does not.
def replace_once(name, old, new):
    # Load the file.
    path = pathlib.Path(name)
    # Read its text.
    text = path.read_text()
    # Already changed earlier: the new text is in the file, so there is nothing to do (this keeps the script safe to run twice).
    if new in text:
        # Say so and leave the file alone.
        print("already done: " + name)
        # Stop this edit.
        return
    # The old text must be there exactly once, otherwise the file is not the one this script was made for.
    if text.count(old) != 1:
        # Stop with a clear message.
        raise SystemExit("cannot edit " + name + ": expected text found " + str(text.count(old)) + " times")
    # Write the changed text back.
    path.write_text(text.replace(old, new))
    # Say what happened.
    print("edited: " + name)

# The script route is added to the router (web.go).
replace_once("web.go",
    "\tmux.HandleFunc(\"GET /countdown.js\", countdownHandler)\n",
    "\tmux.HandleFunc(\"GET /countdown.js\", countdownHandler)\n\t// Route: a GET request for \"/loading.js\" sends the small script that shows the waiting message while a model loads (only the load warning page uses it).\n\tmux.HandleFunc(\"GET /loading.js\", loadingHandler)\n")
# The state words and the dot are wrapped in a label of fixed width, so the buttons line up (web/index.html).
replace_once("web/index.html",
    "<td><span class=\"dot {{if .Loaded}}dot-on{{else}}dot-off{{end}}\" aria-hidden=\"true\"></span> {{.StateWord}}\n",
    "<td><span class=\"statelabel\"><span class=\"dot {{if .Loaded}}dot-on{{else}}dot-off{{end}}\" aria-hidden=\"true\"></span> {{.StateWord}}</span>\n")
# The two table tests count the start of the state cell; it now starts with the label (webtable_test.go).
replace_once("webtable_test.go",
    "`<td><span class=\"dot dot-on\" aria-hidden=\"true\"></span> Loaded\n`",
    "`<td><span class=\"statelabel\"><span class=\"dot dot-on\" aria-hidden=\"true\"></span> Loaded</span>\n`")
# The same for the cell of a model that is not loaded (webtable_test.go).
replace_once("webtable_test.go",
    "`<td><span class=\"dot dot-off\" aria-hidden=\"true\"></span> Not loaded\n`",
    "`<td><span class=\"statelabel\"><span class=\"dot dot-off\" aria-hidden=\"true\"></span> Not loaded</span>\n`")
# The load warning page now runs the monitor's own script, so it gets the relaxed policy too (load.go).
replace_once("load.go",
    "\t\t// A page with a ticking timer may run the monitor's own script, and nothing else.\n\t\tif data.Seconds > 0 {",
    "\t\t// A page with a ticking timer, and the warning page with its waiting message, may run the monitor's own script, and nothing else.\n\t\tif data.Seconds > 0 || data.Kind == \"confirm\" {")
# The old load test said the warning page has no script; it now has exactly the monitor's own one (load_test.go).
replace_once("load_test.go",
    "\t// This page has no timer to tick, so no script and the strict policy.\n\tif strings.Contains(body, \"<script\") || strings.Contains(res.Header.Get(\"Content-Security-Policy\"), \"script-src\") {\n\t\t// Report the problem.\n\t\tt.Errorf(\"the load warning page allows or contains a script\")\n\t} // end of the script check\n",
    "\t// This page runs only the monitor's own waiting script: no inline code and no unsafe-inline rule (the new loading tests check the rest).\n\tif strings.Contains(body, \"<script>\") || strings.Contains(res.Header.Get(\"Content-Security-Policy\"), \"unsafe-inline\") {\n\t\t// Report the problem.\n\t\tt.Errorf(\"the load warning page allows or contains inline script\")\n\t} // end of the script check\n")
# The Yes form is marked so the script can find it (web/load.html).
replace_once("web/load.html",
    "<form method=\"post\" action=\"/load/confirm\">",
    "<form method=\"post\" action=\"/load/confirm\" data-loading>")
# The row with the two choices gets a name the script can find (web/load.html).
replace_once("web/load.html",
    "<div class=\"choices\">",
    "<div class=\"choices\" id=\"choices\">")
# The waiting box follows the choices; it stays hidden until the script shows it (web/load.html).
replace_once("web/load.html",
    "{{/* Version 2: the model is loaded already. */}}",
    "{{/* The waiting box: hidden at first; the script shows it when Yes is pressed. Without the script the browser's own spinner is all there is. */}}\n<div id=\"loading\" role=\"status\" aria-live=\"polite\" hidden>\n{{/* The message, with the seconds passed. */}}\n<p><strong>Loading, please wait.</strong> Ollama is reading <code>{{.Model}}</code> into memory. Time passed: <span class=\"elapsed\">0 s</span></p>\n{{/* The moving bar; it is hidden from screen readers because the text says the same. */}}\n<div class=\"bar\" aria-hidden=\"true\"><span class=\"barfill\"></span></div>\n{{/* The honest note. */}}\n<p class=\"muted\">The bar only shows that work is going on. It is not a percentage: Ollama does not report how far the loading has got. Please do not close this page.</p>\n{{/* End of the waiting box. */}}\n</div>\n{{/* Version 2: the model is loaded already. */}}")
# The script is included on the warning page only (web/load.html).
replace_once("web/load.html",
    "{{if .Seconds}}<script src=\"/countdown.js\" defer></script>{{end}}\n",
    "{{if .Seconds}}<script src=\"/countdown.js\" defer></script>{{end}}\n{{/* The waiting message needs the monitor's own script too, on the warning page only. */}}\n{{if eq .Kind \"confirm\"}}<script src=\"/loading.js\" defer></script>{{end}}\n")

# The new style rules go at the end of app.css, once (recognised by the ".statelabel {" rule).
path = pathlib.Path("web/app.css")
# Read the file.
text = path.read_text()
# Only add the rules when they are not there yet.
if "\n.statelabel {" not in text:
    # Append the rules.
    text += """
/* The state words with their dot get a fixed minimum width, so the Load and Unload buttons all start at the same place. */
.statelabel {
  /* A box in the line, so it can have a width. */
  display: inline-block;
  /* Wide enough for the dot and the words "Not loaded". */
  min-width: 8rem;
} /* end of rule */

/* The hidden attribute must always win over any display rule. */
[hidden] {
  /* Not drawn at all. */
  display: none !important;
} /* end of rule */

/* The track of the moving bar on the load page. */
.bar {
  /* The fill is placed inside this box. */
  position: relative;
  /* A thin bar. */
  height: 0.7rem;
  /* Never wider than a comfortable reading width. */
  max-width: 24rem;
  /* Room above and below. */
  margin: 0.6rem 0;
  /* An outline in the Load colour, visible without relying on fill. */
  border: 2px solid var(--load);
  /* Rounded ends. */
  border-radius: 999px;
  /* The fill must not stick out. */
  overflow: hidden;
} /* end of rule */

/* The part of the bar that moves back and forth. */
.barfill {
  /* Placed inside the track. */
  position: absolute;
  /* From the top... */
  top: 0;
  /* ...to the bottom of the track. */
  bottom: 0;
  /* A little less than half of the track. */
  width: 30%;
  /* Rounded ends. */
  border-radius: 999px;
  /* The Load colour. */
  background: var(--load);
  /* Slide to and fro for as long as the page waits. */
  animation: slide 1.4s ease-in-out infinite alternate;
} /* end of rule */

/* The movement: from the left end to the right end of the track. */
@keyframes slide {
  /* Start at the left. */
  from { left: 0; }
  /* End at the right (the bar is 30% wide, so 70% is the far end). */
  to { left: 70%; }
} /* end of rule */

/* People who asked their computer for less motion get a still, full bar instead. */
@media (prefers-reduced-motion: reduce) {
  /* The fill stops moving and fills the track. */
  .barfill {
    /* No movement. */
    animation: none;
    /* The whole track. */
    width: 100%;
  } /* end of rule */
} /* end of rule */
"""
    # Save the file.
    path.write_text(text)
    # Say what happened.
    print("edited: web/app.css (added the alignment and waiting bar rules)")
EOF_PY27

# Fail if any Go file is not formatted the standard way (gofmt -l lists offenders).
unformatted="$(gofmt -l .)"
# An empty list means everything is formatted.
if [ -n "$unformatted" ]; then
  # Show the offenders and stop.
  echo "NOT FORMATTED: $unformatted"; exit 1
fi # end of the format check
# Ask Go to look for suspicious constructs in the program and the tests.
go vet ./...
# Run every test quietly; a failure stops the script and shows Go's own message (-count=1 forces a fresh run).
go test -count=1 ./... 2>&1 | grep -v 'TLS handshake'
# Make sure the output folder exists.
mkdir -p bin
# Build the native executable (CGO_ENABLED=0 = no C libraries; -trimpath removes local paths).
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Say the build and tests worked.
echo "PASS  tests and build"

# Refuse to run if something on this machine already listens on the page-check port (-H hides the header, so any output means in use).
if [ -n "$(ss -ltnH "sport = :$TEST_PORT")" ]; then
  # Explain the problem and stop.
  echo "IN USE: something is already listening on port $TEST_PORT; set TEST_PORT to another port" >&2; exit 1
fi # end of the host port check
# Read the ports published by Docker containers, running and stopped (|| true: carry on if Docker is not available to this user).
DOCKER_PORTS="$(docker ps -a --format '{{.Ports}}' 2> /dev/null || true)"
# Look for the test port in that list (a here-string, not a pipe, so there is no early-exit problem).
if grep -q ":$TEST_PORT->" <<< "$DOCKER_PORTS"; then
  # Explain the problem and stop.
  echo "IN USE: a Docker container publishes port $TEST_PORT; set TEST_PORT to another port" >&2; exit 1
fi # end of the Docker port check
# Start the monitor in the background on the spare port, watching the chosen Ollama; its messages are discarded.
OCC_OLLAMA_URL="" ./bin/OllamaControlCenter -listen "127.0.0.1:$TEST_PORT" -ollama-url "$OLLAMA_TEST_URL" > /dev/null 2>&1 &
# Remember the background process so it can be stopped.
PID=$!
# Stop the monitor when the script ends for any reason.
trap 'kill "$PID" 2> /dev/null || true' EXIT
# Wait up to 5 seconds for the page to answer.
for _ in $(seq 1 50); do
  # Any answer at all means it is up.
  if curl -s -o /dev/null "http://127.0.0.1:$TEST_PORT/"; then break; fi # end of the answer check
  # Wait a moment before asking again.
  sleep 0.1
done # end of the waiting loop

# The page address used by every check below.
BASE="http://127.0.0.1:$TEST_PORT"
# Fetch the page once (-s hides the progress bar).
PAGE="$(curl -s "$BASE/")"
# Read the page token (|| true so a missing token is reported by the checks, not by stopping here).
TOKEN="$(grep -o 'name="token" value="[0-9a-f]*"' <<< "$PAGE" | head -n 1 | sed 's/.*value="//; s/"//' || true)"
# Ask Ollama itself for its installed and loaded models (|| true: an unreachable Ollama is reported by the checks).
TAGS="$(curl -s "$OLLAMA_TEST_URL/api/tags" || true)"
# The loaded list.
PS="$(curl -s "$OLLAMA_TEST_URL/api/ps" || true)"
# All installed names, one per line.
INSTALLED_NAMES="$(grep -o '"name":"[^"]*"' <<< "$TAGS" | sed 's/"name":"//; s/"//' || true)"
# How many models are installed.
INSTALLED_COUNT="$(grep -c . <<< "$INSTALLED_NAMES" || true)"
# The name of the first installed model that is not loaded (the loop keeps the first one that is missing from the loaded list).
FREE_NAME=""
# Go through the installed names.
while IFS= read -r n; do
  # Skip empty lines.
  [ -n "$n" ] || continue
  # A name that is not in the loaded list.
  if ! grep -qF "\"name\":\"$n\"" <<< "$PS"; then FREE_NAME="$n"; break; fi # end of the check
done <<< "$INSTALLED_NAMES"
# How many state labels the page shows.
LABELS="$(grep -o 'class="statelabel"' <<< "$PAGE" | wc -l || true)"

# Counters for passed and failed checks.
pass=0; fail=0
# check LABEL RESULT: prints PASS when the result is "yes".
check() {
  # Print the result and count it.
  if [ "$2" = "yes" ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi # end of the verdict
} # end of check
# status ARGS...: prints only the HTTP status number of a request made with the given curl arguments.
status() {
  # -s hides the progress bar, -o drops the body, -w prints the status number.
  curl -s -o /dev/null -w '%{http_code}' "$@"
} # end of status

# Say what Ollama has, so the checks can be read in context.
echo "info  installed: $INSTALLED_COUNT, state labels on the page: $LABELS"
# Check 1: every model row has the fixed-width state label.
check "every model row has a state label (buttons line up)" "$([ "$LABELS" = "$INSTALLED_COUNT" ] && echo yes || echo no)"
# Check 2: the waiting script is served as JavaScript.
check "the loading script is served as JavaScript" "$(curl -s -D - -o /dev/null "$BASE/loading.js" | grep -qi '^content-type: text/javascript' && echo yes || echo no)"
# Check 3: the script file accepts GET only.
check "POST to /loading.js is refused (405)" "$([ "$(status -d x=1 "$BASE/loading.js")" = "405" ] && echo yes || echo no)"
# Ask for the safety headers of the main page (-D - prints the headers; -o /dev/null drops the body).
HEADERS="$(curl -s -D - -o /dev/null "$BASE/")"
# Check 4: the main page still has no script and no script rule in its policy.
check "main page has no script and its policy has no script-src" "$(! grep -qi 'script-src' <<< "$HEADERS" && ! grep -qiE '<script|<style| style=' <<< "$PAGE" && echo yes || echo no)"
# Check 5: the load warning page for a not-loaded model has the waiting box and the script, and loads nothing.
if [ -n "$FREE_NAME" ]; then
  # Open the warning page for the first model that is not loaded, keeping its headers.
  ASK="$(curl -s -D - -H 'Sec-Fetch-Site: same-origin' --data-urlencode "token=$TOKEN" --data-urlencode "model=$FREE_NAME" "$BASE/load")"
  # Ask Ollama again.
  PS_AFTER="$(curl -s "$OLLAMA_TEST_URL/api/ps" || true)"
  # The box, the marked form, the script, the strict-but-own-script policy, and the model must still be not loaded.
  check "load warning for $FREE_NAME has the waiting box and script, and loads nothing" "$(grep -q 'id="loading"' <<< "$ASK" && grep -q 'data-loading' <<< "$ASK" && grep -q '/loading.js' <<< "$ASK" && grep -qi "script-src 'self'" <<< "$ASK" && ! grep -qi 'unsafe-inline' <<< "$ASK" && ! grep -qF "\"name\":\"$FREE_NAME\"" <<< "$PS_AFTER" && echo yes || echo no)"
else
  # Everything is loaded, so this check cannot run; say so instead of pretending.
  echo "skip  load warning check: every installed model is already loaded"
fi # end of the not-loaded check

# Print the totals.
echo "Result: $pass passed, $fail failed"
# Exit with 0 only if nothing failed.
[ "$fail" -eq 0 ]
