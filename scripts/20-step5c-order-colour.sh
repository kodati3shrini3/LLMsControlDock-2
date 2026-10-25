#!/usr/bin/env bash
# Script 20: Step 5c fix, new column order (Model, State, Size on disk, Family, Parameters, Quantization, Max context length, Embedding length, Last modified, Abilities) and a coloured category band, in the page and the terminal table.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"
# Address of the Ollama used for the real run; override it to test another server.
OLLAMA_TEST_URL="${OLLAMA_TEST_URL:-http://127.0.0.1:11434}"
# Spare port for the page check, so it never collides with a real monitor on 8765 or with scripts 05 and 19.
TEST_PORT="${TEST_PORT:-18767}"

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

# The ten column titles in the new order (tooltips.go).
replace_once("tooltips.go",
    '"Model", "Abilities", "Size on disk", "Family", "Parameters", "Quantization", "Last modified", "State", "Max context length", "Embedding length"}',
    '"Model", "State", "Size on disk", "Family", "Parameters", "Quantization", "Max context length", "Embedding length", "Last modified", "Abilities"}')

# The terminal table header in the new order (render.go).
replace_once("render.go",
    'Model\\tAbilities\\tSize on disk\\tFamily\\tParameters\\tQuantization\\tLast modified\\tState\\tMax context length\\tEmbedding length")',
    'Model\\tState\\tSize on disk\\tFamily\\tParameters\\tQuantization\\tMax context length\\tEmbedding length\\tLast modified\\tAbilities")')

# The terminal table cells in the new order (render.go): the old block, then the new block.
replace_once("render.go",
    "\t\t\t\t// Ollama's own words for the abilities.\n\t\t\t\torDash(strings.Join(m.Capabilities, \", \")),\n\t\t\t\t// Size on disk.\n\t\t\t\tformatSize(m.Size),\n\t\t\t\t// Family as reported.\n\t\t\t\torDash(m.Details.Family),\n\t\t\t\t// Parameter size as reported.\n\t\t\t\torDash(m.Details.ParameterSize),\n\t\t\t\t// Quantization level as reported.\n\t\t\t\torDash(m.Details.QuantizationLevel),\n\t\t\t\t// Last modified, in UTC.\n\t\t\t\tformatTime(m.ModifiedAt),\n\t\t\t\t// Loaded or not, symbol plus words.\n\t\t\t\tstateText(row.Loaded),\n\t\t\t\t// Largest context the model supports.\n\t\t\t\tformatCount(m.Details.ContextLength),\n\t\t\t\t// Width of the model's vectors.\n\t\t\t\tformatCount(m.Details.EmbeddingLength)) // end of the row",
    "\t\t\t\t// Loaded or not, symbol plus words.\n\t\t\t\tstateText(row.Loaded),\n\t\t\t\t// Size on disk.\n\t\t\t\tformatSize(m.Size),\n\t\t\t\t// Family as reported.\n\t\t\t\torDash(m.Details.Family),\n\t\t\t\t// Parameter size as reported.\n\t\t\t\torDash(m.Details.ParameterSize),\n\t\t\t\t// Quantization level as reported.\n\t\t\t\torDash(m.Details.QuantizationLevel),\n\t\t\t\t// Largest context the model supports.\n\t\t\t\tformatCount(m.Details.ContextLength),\n\t\t\t\t// Width of the model's vectors.\n\t\t\t\tformatCount(m.Details.EmbeddingLength),\n\t\t\t\t// Last modified, in UTC.\n\t\t\t\tformatTime(m.ModifiedAt),\n\t\t\t\t// Ollama's own words for the abilities.\n\t\t\t\torDash(strings.Join(m.Capabilities, \", \"))) // end of the row")

# The page cells in the new order (tableview.go).
replace_once("tableview.go",
    "\t\t\t\t// Ollama's own words for the abilities.\n\t\t\t\torDash(strings.Join(m.Capabilities, \", \")),\n\t\t\t\t// Size on disk.\n\t\t\t\tformatSize(m.Size),\n\t\t\t\t// Family as reported.\n\t\t\t\torDash(m.Details.Family),\n\t\t\t\t// Parameter size as reported.\n\t\t\t\torDash(m.Details.ParameterSize),\n\t\t\t\t// Quantization level as reported.\n\t\t\t\torDash(m.Details.QuantizationLevel),\n\t\t\t\t// Last modified, in UTC.\n\t\t\t\tformatTime(m.ModifiedAt),\n\t\t\t\t// Loaded or not, symbol plus words.\n\t\t\t\tstateText(r.Loaded),\n\t\t\t\t// Largest context the model supports.\n\t\t\t\tformatCount(m.Details.ContextLength),\n\t\t\t\t// Width of the model's vectors.\n\t\t\t\tformatCount(m.Details.EmbeddingLength),\n",
    "\t\t\t\t// Loaded or not, symbol plus words.\n\t\t\t\tstateText(r.Loaded),\n\t\t\t\t// Size on disk.\n\t\t\t\tformatSize(m.Size),\n\t\t\t\t// Family as reported.\n\t\t\t\torDash(m.Details.Family),\n\t\t\t\t// Parameter size as reported.\n\t\t\t\torDash(m.Details.ParameterSize),\n\t\t\t\t// Quantization level as reported.\n\t\t\t\torDash(m.Details.QuantizationLevel),\n\t\t\t\t// Largest context the model supports.\n\t\t\t\tformatCount(m.Details.ContextLength),\n\t\t\t\t// Width of the model's vectors.\n\t\t\t\tformatCount(m.Details.EmbeddingLength),\n\t\t\t\t// Last modified, in UTC.\n\t\t\t\tformatTime(m.ModifiedAt),\n\t\t\t\t// Ollama's own words for the abilities.\n\t\t\t\torDash(strings.Join(m.Capabilities, \", \")),\n")

# The expected nine cells in the new order (tableview_test.go).
replace_once("tableview_test.go",
    '[]string{"completion, vision", "3.3 GB", "gemma3", "4.3B", "Q4_K_M", "2026-10-21 15:48 UTC", "● Loaded", "131072", "2560"}',
    '[]string{"● Loaded", "3.3 GB", "gemma3", "4.3B", "Q4_K_M", "131072", "2560", "2026-10-21 15:48 UTC", "completion, vision"}')

# Light colours for the category band (app.css).
replace_once("web/app.css",
    "  /* Tell the browser to draw its own controls in light colours. */\n  color-scheme: light;\n",
    "  /* Category row background: a soft steel blue band (text contrast 10.7:1). */\n  --cat-bg: #dbe7f5;\n  /* Category row text colour: deep navy. */\n  --cat-text: #12304f;\n  /* Category row accent bar on the left edge (contrast 6.4:1 on the page). */\n  --cat-accent: #1f5fa8;\n  /* Tell the browser to draw its own controls in light colours. */\n  color-scheme: light;\n")

# Dark colours for the category band (app.css).
replace_once("web/app.css",
    "    /* Tell the browser to draw its own controls in dark colours. */\n    color-scheme: dark;\n",
    "    /* Category row background: a deep slate blue band (text contrast 10.1:1). */\n    --cat-bg: #1f3550;\n    /* Category row text colour: pale blue. */\n    --cat-text: #dbe9fb;\n    /* Category row accent bar on the left edge (contrast 8.4:1 on the page). */\n    --cat-accent: #7fb2f0;\n    /* Tell the browser to draw its own controls in dark colours. */\n    color-scheme: dark;\n")

# The category row rule, now coloured (app.css).
replace_once("web/app.css",
    ".grouprow th {\n  /* A slightly different background so sections are clear. */\n  background: var(--panel);\n  /* Normal weight; the name inside is bold. */\n  font-weight: 400;\n  /* A heavier line above each section. */\n  border-top: 2px solid var(--border);\n} /* end of rule */\n",
    ".grouprow th {\n  /* A coloured band so each section stands out. */\n  background: var(--cat-bg);\n  /* Text colour that reads well on the band. */\n  color: var(--cat-text);\n  /* Normal weight; the name inside is bold. */\n  font-weight: 400;\n  /* A heavier line above each section. */\n  border-top: 2px solid var(--border);\n  /* A thick accent bar on the left edge, so the band is clear even without telling colours apart. */\n  border-left: 6px solid var(--cat-accent);\n} /* end of rule */\n\n/* The model count next to a category name uses the band's text colour, not the grey one. */\n.grouprow .muted {\n  /* Same colour as the category name. */\n  color: var(--cat-text);\n} /* end of rule */\n")

# Three new stylesheet checks in webtable_test.go.
replace_once("webtable_test.go",
    "\t\t// Headings with help carry a dotted underline.\n\t\t\"dotted cue\": \"underline dotted\",\n",
    "\t\t// Headings with help carry a dotted underline.\n\t\t\"dotted cue\": \"underline dotted\",\n\t\t// Category rows are drawn as a coloured band.\n\t\t\"category band colour\": \"background: var(--cat-bg)\",\n\t\t// The band has an accent bar, so it does not rely on colour alone.\n\t\t\"category accent bar\": \"border-left: 6px solid var(--cat-accent)\",\n\t\t// The dark theme redefines the band colours.\n\t\t\"dark band colour\": \"--cat-bg: #1f3550\",\n")

# The new column-order test is added to webtable_test.go once (it is recognised by its name).
path = pathlib.Path("webtable_test.go")
# Read the file.
text = path.read_text()
# Only add the test when it is not there yet.
if "func TestTableColumnOrder(" not in text:
    # Append the test at the end of the file.
    text += '''
// TestTableColumnOrder checks the headings appear on the page in the order the person asked for.
func TestTableColumnOrder(t *testing.T) {
	// Fake Ollama with the six real models.
	body := pageFor(t, fullOllama(t, realModels, realPsBody))
	// The wanted order.
	want := []string{"Model", "State", "Size on disk", "Family", "Parameters", "Quantization", "Max context length", "Embedding length", "Last modified", "Abilities"}
	// Start looking from the table head.
	pos := strings.Index(body, "<thead>")
	// Go through the titles in order.
	for _, col := range want {
		// Find the heading element after the previous one.
		i := strings.Index(body[pos:], ">"+col+"</span>")
		// A missing or early heading means the order is wrong.
		if i < 0 {
			// Report the problem.
			t.Fatalf("heading %q is missing or out of order", col)
		} // end of the find check
		// Continue after this heading.
		pos += i + len(col)
	} // end of the title loop
} // end of TestTableColumnOrder
'''
    # Save the file.
    path.write_text(text)
    # Say what happened.
    print("edited: webtable_test.go (added TestTableColumnOrder)")
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
# Take the column headings of the page in order: the text of every help span inside the table head (the part before the first category row).
HEADS="$(sed -n '1,/grouprow/p' <<< "$PAGE" | grep -oE 'class="help" tabindex="0" aria-describedby="tip-col-[0-9]+">[^<]*' | sed 's/.*>//' | paste -sd, -)"
# Take the first line of the terminal table header (the line after INSTALLED MODELS), with its runs of spaces turned into commas.
TERM="$(OCC_OLLAMA_URL="" ./bin/OllamaControlCenter -models -ollama-url "$OLLAMA_TEST_URL" 2> /dev/null | grep -A1 -m1 'INSTALLED MODELS' | tail -1 | sed -E 's/ {2,}/,/g')"

# Counters for passed and failed checks.
pass=0; fail=0
# check LABEL RESULT: prints PASS when the result is "yes".
check() {
  # Print the result and count it.
  if [ "$2" = "yes" ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi # end of the verdict
} # end of check

# Check 1: the page headings are in the requested order.
check "page column order is the requested one" "$([ "$HEADS" = "Model,State,Size on disk,Family,Parameters,Quantization,Max context length,Embedding length,Last modified,Abilities" ] && echo yes || echo no)"
# Check 2: the terminal table has the same order as the page.
check "terminal table has the same order as the page" "$([ "$TERM" = "$HEADS" ] && echo yes || echo no)"
# Check 3: the stylesheet carries the category colour.
check "stylesheet has the category band colour" "$(curl -s "http://127.0.0.1:$TEST_PORT/app.css" | grep -q 'background: var(--cat-bg)' && echo yes || echo no)"
# Check 4: the page still has no script, no style tag and no inline style.
check "page has no script or inline style" "$(grep -qiE '<script|<style| style=' <<< "$PAGE" && echo no || echo yes)"

# Print the totals.
echo "Result: $pass passed, $fail failed"
# Show what was read, so a difference is easy to see (read-only).
echo "Page headings:     $HEADS"
# Show the terminal header too.
echo "Terminal headings: $TERM"
# Exit with 0 only if nothing failed.
[ "$fail" -eq 0 ]
