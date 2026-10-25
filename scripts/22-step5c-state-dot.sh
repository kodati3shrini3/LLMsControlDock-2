#!/usr/bin/env bash
# Script 22: Step 5c look fix, the State column shows a solid green dot with a dark border for a loaded model and an empty grey ring for a model that is not loaded (the words stay, so colour is never the only signal).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"
# Address of the Ollama used for the real run; override it to test another server.
OLLAMA_TEST_URL="${OLLAMA_TEST_URL:-http://127.0.0.1:11434}"
# Spare port for the page check, so it never collides with a real monitor on 8765 or with scripts 05, 19 and 20.
TEST_PORT="${TEST_PORT:-18768}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"

# Edit the files with a small Python program; the quoted EOF_PY marker saves every character exactly as typed.
python3 - << 'EOF_PY'
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

# Two new fields in the row data: whether the model is loaded, and the state word (tableview.go).
replace_once("tableview.go",
    "\t// Cells are the other nine columns, in order.\n\tCells []string\n} // end of rowView\n",
    "\t// Cells are the other nine columns, in order.\n\tCells []string\n\t// Loaded is true when the model is in memory now; the page draws a green dot for it.\n\tLoaded bool\n\t// StateWord is \"Loaded\" or \"Not loaded\"; the page shows it next to the dot.\n\tStateWord string\n} // end of rowView\n")

# A small helper that gives the state word without the symbol (tableview.go).
replace_once("tableview.go",
    "// buildTableView turns the installed and loaded lists into the data the page template draws.\n",
    "// stateWord is the state in words only; the page draws the dot itself.\nfunc stateWord(loaded bool) string {\n\t// A loaded model.\n\tif loaded {\n\t\t// Say so.\n\t\treturn \"Loaded\"\n\t} // end of the loaded case\n\t// Everything else.\n\treturn \"Not loaded\"\n} // end of stateWord\n\n// buildTableView turns the installed and loaded lists into the data the page template draws.\n")

# Fill the two new fields when a row is built (tableview.go).
replace_once("tableview.go",
    "rowView{Name: m.Name, Cells: []string{",
    "rowView{Name: m.Name, Loaded: r.Loaded, StateWord: stateWord(r.Loaded), Cells: []string{")

# The page draws the state cell itself: dot plus words (web/index.html).
replace_once("web/index.html",
    "{{/* The other nine cells. */}}\n{{range .Cells}}\n",
    "{{/* The state cell: a dot (solid green when loaded, an empty ring when not) plus the words, so colour is never the only signal. */}}\n<td><span class=\"dot {{if .Loaded}}dot-on{{else}}dot-off{{end}}\" aria-hidden=\"true\"></span> {{.StateWord}}</td>\n{{/* The other eight cells; the first of the nine is the state text, which the cell above already shows. */}}\n{{range slice .Cells 1}}\n")

# Light colour of the dot (web/app.css).
replace_once("web/app.css",
    "  /* Category row background: a soft steel blue band",
    "  /* Colour of the dot for a loaded model (contrast 5:1 on the page). */\n  --dot-on: #1a7f37;\n  /* Category row background: a soft steel blue band")

# Dark colour of the dot (web/app.css).
replace_once("web/app.css",
    "    /* Category row background: a deep slate blue band",
    "    /* Colour of the dot for a loaded model (contrast 8:1 on the page). */\n    --dot-on: #3fb950;\n    /* Category row background: a deep slate blue band")

# The dot rules are added at the end of app.css once (they are recognised by the ".dot {" rule).
path = pathlib.Path("web/app.css")
# Read the file.
text = path.read_text()
# Only add the rules when they are not there yet.
if "\n.dot {" not in text:
    # Append the rules.
    text += """
/* The state dot: a round shape with a dark border, drawn in CSS so no picture is downloaded. */
.dot {
  /* Sits in the line of text like a letter. */
  display: inline-block;
  /* A small circle, sized with the text. */
  width: 0.85em;
  /* Same height as width, so it is round. */
  height: 0.85em;
  /* Make it a circle. */
  border-radius: 50%;
  /* A solid dark border so the dot is visible on both themes. */
  border: 2px solid var(--text);
  /* The border counts inside the size. */
  box-sizing: border-box;
  /* Line it up with the middle of the text. */
  vertical-align: -0.1em;
  /* A little room before the words. */
  margin-right: 0.4em;
} /* end of rule */

/* A loaded model: a solid green dot. */
.dot-on {
  /* The green from the variables. */
  background: var(--dot-on);
} /* end of rule */

/* A model that is not loaded: an empty ring with a softer border, a different shape as well as a different colour. */
.dot-off {
  /* Nothing inside the ring. */
  background: transparent;
  /* A softer border than the loaded dot. */
  border-color: var(--muted);
} /* end of rule */
"""
    # Save the file.
    path.write_text(text)
    # Say what happened.
    print("edited: web/app.css (added the dot rules)")

# The table tests now look for the dot markup instead of the symbol (webtable_test.go).
replace_once("webtable_test.go",
    "strings.Count(body, \"<td>● Loaded</td>\")",
    "strings.Count(body, `<td><span class=\"dot dot-on\" aria-hidden=\"true\"></span> Loaded</td>`)")
# The same for the not-loaded cells.
replace_once("webtable_test.go",
    "strings.Count(body, \"<td>○ Not loaded</td>\")",
    "strings.Count(body, `<td><span class=\"dot dot-off\" aria-hidden=\"true\"></span> Not loaded</td>`)")
# Two new stylesheet checks (webtable_test.go).
replace_once("webtable_test.go",
    "\t\t// The dark theme redefines the band colours.\n\t\t\"dark band colour\": \"--cat-bg: #1f3550\",\n",
    "\t\t// The dark theme redefines the band colours.\n\t\t\"dark band colour\": \"--cat-bg: #1f3550\",\n\t\t// The loaded dot is green.\n\t\t\"loaded dot colour\": \"background: var(--dot-on)\",\n\t\t// The dot is round.\n\t\t\"round dot\": \"border-radius: 50%\",\n")
EOF_PY

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

# Fetch the page once (-s hides the progress bar).
PAGE="$(curl -s "http://127.0.0.1:$TEST_PORT/")"
# Read the terminal table once, so both numbers below come from the same moment.
TERMINAL="$(OCC_OLLAMA_URL="" ./bin/OllamaControlCenter -models -ollama-url "$OLLAMA_TEST_URL" 2> /dev/null)"
# Count the loaded rows in the terminal table (grep -o prints each match on its own line, wc -l counts the lines; when nothing matches grep reports an error, so || true keeps the script going and the count stays 0).
T_ON="$(grep -o '● Loaded' <<< "$TERMINAL" | wc -l || true)"
# Count the not-loaded rows in the terminal table.
T_OFF="$(grep -o '○ Not loaded' <<< "$TERMINAL" | wc -l || true)"
# Count the solid dots on the page.
P_ON="$(grep -o 'class="dot dot-on"' <<< "$PAGE" | wc -l || true)"
# Count the empty rings on the page.
P_OFF="$(grep -o 'class="dot dot-off"' <<< "$PAGE" | wc -l || true)"

# Counters for passed and failed checks.
pass=0; fail=0
# check LABEL RESULT: prints PASS when the result is "yes".
check() {
  # Print the result and count it.
  if [ "$2" = "yes" ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi # end of the verdict
} # end of check

# Check 1: the page has as many solid dots as the terminal has loaded rows.
check "$P_ON solid dots on the page = $T_ON loaded rows in -models" "$([ "$P_ON" = "$T_ON" ] && echo yes || echo no)"
# Check 2: the page has as many empty rings as the terminal has not-loaded rows.
check "$P_OFF empty rings on the page = $T_OFF not-loaded rows in -models" "$([ "$P_OFF" = "$T_OFF" ] && echo yes || echo no)"
# Check 3: every dot has its words next to it (words are the second signal besides colour).
check "words next to the dots" "$([ "$(grep -o '</span> Loaded</td>\|</span> Not loaded</td>' <<< "$PAGE" | wc -l)" = "$((P_ON + P_OFF))" ] && echo yes || echo no)"
# Check 4: the stylesheet carries the dot rules.
check "stylesheet has the dot rules" "$(curl -s "http://127.0.0.1:$TEST_PORT/app.css" | grep -q 'background: var(--dot-on)' && echo yes || echo no)"
# Check 5: the page still has no script, no style tag and no inline style.
check "page has no script or inline style" "$(grep -qiE '<script|<style| style=' <<< "$PAGE" && echo no || echo yes)"

# Print the totals.
echo "Result: $pass passed, $fail failed"
# Exit with 0 only if nothing failed.
[ "$fail" -eq 0 ]
