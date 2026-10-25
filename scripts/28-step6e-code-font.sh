#!/usr/bin/env bash
# Script 28: Step 6e, model names (shown in code style) get the same size as the text around them.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"
# Address of the Ollama used for the real run; override it to test another server.
OLLAMA_TEST_URL="${OLLAMA_TEST_URL:-http://127.0.0.1:11434}"
# Spare port for the page check, so it never collides with a real monitor on 8765 or with the earlier scripts.
TEST_PORT="${TEST_PORT:-18774}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"

# Write codefont_test.go; the quoted marker saves every character exactly as typed.
cat > codefont_test.go << 'EOF_CFTEST'
// Package main tells Go that this test file belongs to the same program as the stylesheet.
package main

import ( // import lists the packages this test file uses.
	// regexp finds the rule in the stylesheet.
	"regexp"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// TestCodeFontMatchesText checks the stylesheet gives code (model names) the same size as the text around it and a font list that avoids the browser's shrinking of plain "monospace".
func TestCodeFontMatchesText(t *testing.T) {
	// Find the rule for code (the first line of the rule starts at the beginning of a line).
	m := regexp.MustCompile(`(?s)\ncode \{(.*?)\}`).FindStringSubmatch(string(appCSS))
	// The rule must exist.
	if m == nil {
		// Stop the test.
		t.Fatalf("the stylesheet has no rule for code")
	} // end of the existence check
	// The size must follow the surrounding text exactly.
	if !regexp.MustCompile(`font-size:\s*1em;`).MatchString(m[1]) {
		// Report the problem.
		t.Errorf("code does not take the size of its surroundings: %s", m[1])
	} // end of the size check
	// The font list must name a real monospace font first; a list of only "monospace" makes browsers shrink the text.
	if !regexp.MustCompile(`font-family:\s*ui-monospace,`).MatchString(m[1]) {
		// Report the problem.
		t.Errorf("code font list does not start with a named monospace font: %s", m[1])
	} // end of the family check
} // end of TestCodeFontMatchesText
EOF_CFTEST

# Add the rule at the end of app.css, once (recognised by the "code {" rule at the start of a line).
python3 - << 'EOF_PY28'
# pathlib reads and writes the files.
import pathlib

# The stylesheet.
path = pathlib.Path("web/app.css")
# Read its text.
text = path.read_text()
# Only add the rule when it is not there yet (this keeps the script safe to run twice).
if "\ncode {" in text:
    # Say so and leave the file alone.
    print("already done: web/app.css")
else:
    # Append the rule.
    text += """
/* Model names and other code: the same size as the text around them (browsers shrink plain "monospace" text to about 13px, so a named font list and an explicit 1em are used). */
code {
  /* A named monospace font first, then the common ones, then the generic one. */
  font-family: ui-monospace, "SFMono-Regular", Menlo, Consolas, "DejaVu Sans Mono", monospace;
  /* Exactly the size of the surrounding text, in headings too. */
  font-size: 1em;
} /* end of rule */
"""
    # Save the file.
    path.write_text(text)
    # Say what happened.
    print("edited: web/app.css (code font rule added)")
EOF_PY28

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

# Counters for passed and failed checks.
pass=0; fail=0
# check LABEL RESULT: prints PASS when the result is "yes".
check() {
  # Print the result and count it.
  if [ "$2" = "yes" ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi # end of the verdict
} # end of check
# Fetch the stylesheet the running monitor really serves.
CSS="$(curl -s "http://127.0.0.1:$TEST_PORT/app.css")"
# Check 1: the running monitor serves the new rule.
check "the running monitor serves the code font rule" "$(grep -q 'font-size: 1em;' <<< "$CSS" && grep -q 'ui-monospace' <<< "$CSS" && echo yes || echo no)"
# Check 2: the earlier rules are still there (nothing was lost).
check "the Load button and waiting bar rules are still served" "$(grep -q '^\.load {' <<< "$CSS" && grep -q '^\.barfill {' <<< "$CSS" && echo yes || echo no)"

# Print the totals.
echo "Result: $pass passed, $fail failed"
# Exit with 0 only if nothing failed.
[ "$fail" -eq 0 ]
