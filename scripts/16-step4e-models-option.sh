#!/usr/bin/env bash
# Script 16: Step 4e, adds the -models option (render.go and main.go), tests it, and runs it against the real Ollama.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"
# Address of the Ollama used for the real run; override it to test another server.
OLLAMA_TEST_URL="${OLLAMA_TEST_URL:-http://127.0.0.1:11434}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"

# Write render.go; the quoted EOF_RENDER marker saves every character exactly as typed.
cat > render.go << 'EOF_RENDER'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes provides a text buffer the table is written into.
	"bytes"
	// fmt builds formatted text.
	"fmt"
	// strconv turns whole numbers into text.
	"strconv"
	// strings joins, repeats and trims text.
	"strings"
	// text/tabwriter lines up columns for us (standard library only, requirement T1).
	"text/tabwriter"
	// time provides the timestamp type.
	"time"
) // end of imports

// The size units Ollama's own "ollama list" uses: decimal, so 1 GB is 1,000,000,000 bytes.
const (
	// bytesPerMB is one megabyte in bytes.
	bytesPerMB = 1000 * 1000
	// bytesPerGB is one gigabyte in bytes.
	bytesPerGB = 1000 * bytesPerMB
) // end of the size units

// formatSize turns a number of bytes into text such as 17.4 GB, 500 MB or 12 B.
func formatSize(b int64) string {
	// Pick the unit by size.
	switch {
	// One gigabyte or more: one decimal.
	case b >= bytesPerGB:
		// Divide as a decimal number so the fraction is kept.
		return fmt.Sprintf("%.1f GB", float64(b)/bytesPerGB)
	// One megabyte or more: no decimal.
	case b >= bytesPerMB:
		// Divide as a decimal number and round to a whole megabyte.
		return fmt.Sprintf("%.0f MB", float64(b)/bytesPerMB)
	} // end of the switch
	// Anything smaller is shown in bytes.
	return fmt.Sprintf("%d B", b)
} // end of formatSize

// formatTime shows a moment in UTC with a label, such as 2026-10-24 17:40 UTC; a zero time becomes "unknown".
func formatTime(t time.Time) string {
	// A zero time means Ollama did not report one.
	if t.IsZero() {
		// Say so plainly.
		return "unknown"
	} // end of the zero check
	// Convert to UTC and format with the label; Go's layout uses the fixed example date 2006-01-02 15:04.
	return t.UTC().Format("2006-01-02 15:04") + " UTC"
} // end of formatTime

// formatCount shows a whole number exactly, or a dash when it is zero (not reported).
func formatCount(n int64) string {
	// Zero means the field was missing or empty.
	if n == 0 {
		// Show a dash.
		return "-"
	} // end of the zero check
	// Show the exact number.
	return strconv.FormatInt(n, 10)
} // end of formatCount

// orDash returns the text, or a dash when it is empty.
func orDash(s string) string {
	// An empty text becomes a dash.
	if s == "" {
		// Show a dash.
		return "-"
	} // end of the empty check
	// Otherwise keep the text.
	return s
} // end of orDash

// trimLines removes the spaces the column aligner leaves at the end of each line.
func trimLines(s string) string {
	// Split into lines.
	lines := strings.Split(s, "\n")
	// Go through every line.
	for i, l := range lines {
		// Remove trailing spaces.
		lines[i] = strings.TrimRight(l, " ")
	} // end of the line loop
	// Join the lines again.
	return strings.Join(lines, "\n")
} // end of trimLines

// renderInstalled draws the Installed table: one column header row, then a heading row and the models for each non-empty category.
func renderInstalled(groups []categoryGroup) string {
	// The buffer the table is written into.
	var buf bytes.Buffer
	// Create the column aligner: no minimum width, 2 spaces between columns, spaces as padding.
	w := tabwriter.NewWriter(&buf, 0, 0, 2, ' ', 0)
	// The ten column titles; tabs separate the columns.
	fmt.Fprintln(w, "Model\tAbilities\tSize on disk\tFamily\tParameters\tQuantization\tLast modified\tState\tMax context length\tEmbedding length")
	// Go through every non-empty category.
	for _, g := range groups {
		// A heading row: the title, then empty cells so the columns stay in one block and keep their alignment.
		fmt.Fprintf(w, "== %s ==%s\n", g.Category, strings.Repeat("\t", 9))
		// Go through the models of this category.
		for _, row := range g.Rows {
			// A short name for the model's data.
			m := row.Model
			// One row: ten cells separated by tabs.
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
				// The model name, never shortened.
				m.Name,
				// Ollama's own words for the abilities.
				orDash(strings.Join(m.Capabilities, ", ")),
				// Size on disk.
				formatSize(m.Size),
				// Family as reported.
				orDash(m.Details.Family),
				// Parameter size as reported.
				orDash(m.Details.ParameterSize),
				// Quantization level as reported.
				orDash(m.Details.QuantizationLevel),
				// Last modified, in UTC.
				formatTime(m.ModifiedAt),
				// Loaded or not, symbol plus words.
				stateText(row.Loaded),
				// Largest context the model supports.
				formatCount(m.Details.ContextLength),
				// Width of the model's vectors.
				formatCount(m.Details.EmbeddingLength)) // end of the row
		} // end of the model loop
	} // end of the group loop
	// Write everything out; Flush runs the alignment.
	w.Flush()
	// Return the table without trailing spaces.
	return trimLines(buf.String())
} // end of renderInstalled

// renderLoaded draws the Loaded table, or a plain note when nothing is loaded.
func renderLoaded(loaded []loadedModel, now time.Time) string {
	// Nothing loaded: say so.
	if len(loaded) == 0 {
		// Return the note.
		return "(none loaded)"
	} // end of the empty check
	// The buffer the table is written into.
	var buf bytes.Buffer
	// Create the column aligner.
	w := tabwriter.NewWriter(&buf, 0, 0, 2, ' ', 0)
	// The five column titles.
	fmt.Fprintln(w, "Model\tSize (as reported)\tMemory on GPU\tLoaded context length\tTime until unload")
	// Go through every loaded model.
	for _, l := range loaded {
		// Read the unload time; ok is false when it is missing or unreadable.
		expires, ok := l.expiresTime()
		// One row: five cells separated by tabs.
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\n",
			// The model name.
			l.Name,
			// Size as Ollama reports it.
			formatSize(l.Size),
			// How much of it sits in GPU memory.
			formatSize(l.SizeVRAM),
			// The context window of the running model.
			formatCount(l.ContextLength),
			// Time left, as text.
			formatRemaining(now, expires, ok)) // end of the row
	} // end of the loaded loop
	// Write everything out.
	w.Flush()
	// Return the table without trailing spaces.
	return trimLines(buf.String())
} // end of renderLoaded

// renderReport builds the whole -models output: the Installed table grouped by category, then the Loaded table.
func renderReport(installed []installedModel, loaded []loadedModel, now time.Time) string {
	// Mark each installed model as loaded or not.
	rows := combine(installed, loaded)
	// Sort the rows into categories.
	groups := groupRows(rows)
	// The installed section: a title with the count, then the table or a note.
	installedPart := fmt.Sprintf("INSTALLED MODELS (%d)\n", len(installed))
	// With no models installed, say so.
	if len(installed) == 0 {
		// Add the note.
		installedPart += "(none installed)"
	} else {
		// Add the table.
		installedPart += renderInstalled(groups)
	} // end of the installed table
	// The loaded section: a title with the count, then the table or a note.
	loadedPart := fmt.Sprintf("LOADED MODELS (%d)\n%s", len(loaded), renderLoaded(loaded, now))
	// Put the two sections together with a blank line between them.
	return installedPart + "\n\n" + loadedPart
} // end of renderReport
EOF_RENDER

# Write render_test.go; the quoted EOF_RT marker saves every character exactly as typed.
cat > render_test.go << 'EOF_RT'
// Package main tells Go that this test file belongs to the same program as render.go.
package main

import ( // import lists the packages this test file uses.
	// encoding/json decodes the real /api/ps reply.
	"encoding/json"
	// strings searches and splits the output.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
	// time provides the fixed clock and the timestamps.
	"time"
) // end of imports

// TestFormatSize checks the size text, including the user's real sizes.
func TestFormatSize(t *testing.T) {
	// A table of byte counts and the expected text.
	cases := []struct {
		// bytes is the input.
		bytes int64
		// want is the expected text.
		want string
	}{
		// The largest real model on disk.
		{17397224125, "17.4 GB"},
		// The smallest chat model on disk.
		{3338942556, "3.3 GB"},
		// The same model's size in memory.
		{3834631945, "3.8 GB"},
		// Exactly one gigabyte.
		{1000000000, "1.0 GB"},
		// Just under a gigabyte falls to megabytes.
		{999999999, "1000 MB"},
		// A plain megabyte count.
		{500000000, "500 MB"},
		// Under a megabyte shows bytes.
		{12345, "12345 B"},
		// Zero.
		{0, "0 B"},
	} // end of the table
	// Go through every case.
	for _, tc := range cases {
		// Compare the text.
		if got := formatSize(tc.bytes); got != tc.want {
			// Report the difference.
			t.Errorf("formatSize(%d) = %q, want %q", tc.bytes, got, tc.want)
		} // end of the check
	} // end of the loop
} // end of TestFormatSize

// TestFormatTime checks the UTC text, an offset input, and the zero time.
func TestFormatTime(t *testing.T) {
	// A real timestamp from the user's server, with nine fractional digits.
	real, err := time.Parse(time.RFC3339Nano, "2026-10-24T17:40:34.693006337Z")
	// A parse failure means the test itself is wrong.
	if err != nil {
		// Stop the test.
		t.Fatalf("bad test time: %v", err)
	} // end of the parse check
	// The expected text.
	if got := formatTime(real); got != "2026-10-24 17:40 UTC" {
		// Report the difference.
		t.Errorf("formatTime(real) = %q", got)
	} // end of the real check
	// The same moment written with a +02:00 offset must give the same UTC text.
	offset := real.In(time.FixedZone("CEST", 2*3600))
	// Compare.
	if got := formatTime(offset); got != "2026-10-24 17:40 UTC" {
		// Report the difference.
		t.Errorf("formatTime(offset) = %q", got)
	} // end of the offset check
	// A zero time means unknown.
	if got := formatTime(time.Time{}); got != "unknown" {
		// Report the difference.
		t.Errorf("formatTime(zero) = %q", got)
	} // end of the zero check
} // end of TestFormatTime

// realInstalled builds the installed list from the user's real data (realModels comes from models_test.go).
func realInstalled(t *testing.T) []installedModel {
	// Mark this as a helper.
	t.Helper()
	// The result.
	var out []installedModel
	// Go through the real rows.
	for _, r := range realModels {
		// Parse the real timestamp.
		mt, err := time.Parse(time.RFC3339Nano, r.modified)
		// A parse failure means the test data is wrong.
		if err != nil {
			// Stop the test.
			t.Fatalf("bad time %q: %v", r.modified, err)
		} // end of the parse check
		// Add the model with all fields the table uses.
		out = append(out, installedModel{
			// Name, size and time.
			Name: r.name, Size: r.size, ModifiedAt: mt,
			// Abilities.
			Capabilities: r.caps,
			// Details.
			Details: modelDetails{Family: r.family, ParameterSize: r.paramSize, QuantizationLevel: r.quant, ContextLength: r.ctx, EmbeddingLength: r.emb},
		}) // end of the append
	} // end of the loop
	// Return the list.
	return out
} // end of realInstalled

// TestRenderReportReal checks the whole output for the user's real models with medgemma:latest loaded.
func TestRenderReportReal(t *testing.T) {
	// Decode the real /api/ps reply from models and loaded tests.
	var ps psReply
	// A decode failure means the test data is wrong.
	if err := json.Unmarshal([]byte(realPsBody), &ps); err != nil {
		// Stop the test.
		t.Fatalf("cannot decode the real reply: %v", err)
	} // end of the decode check
	// A fixed clock: 5 minutes before the real unload time.
	now := time.Date(2026, 10, 25, 0, 11, 27, 255306668, time.UTC)
	// Build the whole report.
	out := renderReport(realInstalled(t), ps.Models, now)
	// The headings must appear in the fixed order.
	iSearch := strings.Index(out, "== Search and similarity (embedding) ==")
	// The multimodal heading.
	iMulti := strings.Index(out, "== Chat with images or audio (multimodal) ==")
	// Both must exist, search first.
	if iSearch < 0 || iMulti < 0 || iSearch > iMulti {
		// Report the difference.
		t.Errorf("headings missing or out of order (search at %d, multimodal at %d)", iSearch, iMulti)
	} // end of the heading check
	// Empty categories must be hidden.
	if strings.Contains(out, "Chat and writing") || strings.Contains(out, "Not yet classified") {
		// Report the difference.
		t.Errorf("an empty category is shown")
	} // end of the hidden check
	// Exactly one model is loaded and five are not.
	if n := strings.Count(out, "● Loaded"); n != 1 {
		// Report the difference.
		t.Errorf("found %d loaded rows, want 1", n)
	} // end of the loaded count
	// The not-loaded count.
	if n := strings.Count(out, "○ Not loaded"); n != 5 {
		// Report the difference.
		t.Errorf("found %d not-loaded rows, want 5", n)
	} // end of the not-loaded count
	// The loaded flag must sit on the medgemma:latest row; this remembers whether that row was found.
	foundRow := false
	// Go through every line.
	for _, line := range strings.Split(out, "\n") {
		// Only look at installed-table lines (they list abilities) that start with that exact model name followed by a space.
		if strings.HasPrefix(line, "medgemma:latest ") && strings.Contains(line, "completion") {
			// Remember that the row exists.
			foundRow = true
			// It must carry the loaded marker.
			if !strings.Contains(line, "● Loaded") {
				// Report the difference.
				t.Errorf("medgemma:latest row is not marked loaded: %q", line)
			} // end of the marker check
		} // end of the row check
	} // end of the line loop
	// The row must exist, otherwise the check above proved nothing.
	if !foundRow {
		// Report the difference.
		t.Errorf("no installed-table row found for medgemma:latest")
	} // end of the found check
	// Every expected piece of text must appear.
	for _, want := range []string{
		// Counts in the section titles.
		"INSTALLED MODELS (6)", "LOADED MODELS (1)",
		// Sizes on disk.
		"17.4 GB", "3.3 GB",
		// A real modified time.
		"2026-10-24 17:40 UTC",
		// Real lengths.
		"131072", "5376",
		// The loaded table: memory, loaded context, and time left.
		"3.8 GB", "5 min 0 s",
		// Ollama's own ability words.
		"completion, vision, audio, tools, thinking",
	} { // end of the list
		// Look for it.
		if !strings.Contains(out, want) {
			// Report the difference.
			t.Errorf("output does not contain %q", want)
		} // end of the check
	} // end of the loop
	// The state column must start at the same position on all six installed rows.
	pos := -1
	// Go through every line.
	for _, line := range strings.Split(out, "\n") {
		// Find the state text on this line, if any.
		i := strings.Index(line, "○ Not loaded")
		// A loaded row uses the other symbol.
		if j := strings.Index(line, "● Loaded"); j >= 0 {
			// Use that position instead.
			i = j
		} // end of the loaded position
		// Skip lines without a state.
		if i < 0 {
			// Move on to the next line.
			continue
		} // end of the skip
		// Remember the first position.
		if pos < 0 {
			// Store it.
			pos = i
		} // end of the first position
		// Every later row must match.
		if i != pos {
			// Report the difference.
			t.Errorf("state column at %d on a row, expected %d: %q", i, pos, line)
		} // end of the alignment check
	} // end of the line loop
	// No line may end with a space.
	for _, line := range strings.Split(out, "\n") {
		// Check the end of the line.
		if strings.HasSuffix(line, " ") {
			// Report the difference.
			t.Errorf("line ends with a space: %q", line)
		} // end of the space check
	} // end of the line loop
} // end of TestRenderReportReal

// TestRenderReportEmpty checks the notes for a machine with nothing installed and nothing loaded.
func TestRenderReportEmpty(t *testing.T) {
	// Build the report from nothing.
	out := renderReport(nil, nil, time.Now())
	// Both notes and both counts must appear.
	for _, want := range []string{"INSTALLED MODELS (0)", "(none installed)", "LOADED MODELS (0)", "(none loaded)"} {
		// Look for it.
		if !strings.Contains(out, want) {
			// Report the difference.
			t.Errorf("output does not contain %q", want)
		} // end of the check
	} // end of the loop
} // end of TestRenderReportEmpty

// TestRenderLoadedMissingFields checks that missing values show dashes and "not reported" instead of breaking the table.
func TestRenderLoadedMissingFields(t *testing.T) {
	// A loaded model with nothing but a name.
	out := renderLoaded([]loadedModel{{Name: "bare:1b"}}, time.Now())
	// The row must show a dash for the context length and "not reported" for the time.
	if !strings.Contains(out, "bare:1b") || !strings.Contains(out, "not reported") || !strings.Contains(out, "-") {
		// Report the difference.
		t.Errorf("unexpected output: %q", out)
	} // end of the check
} // end of TestRenderLoadedMissingFields
EOF_RT

# Write main.go; the quoted EOF_MAIN marker saves every character exactly as typed.
cat > main.go << 'EOF_MAIN'
// Package main tells Go that this folder builds into a runnable program, not a library.
package main

import ( // import lists the standard-library packages this file uses.
	// context supplies the (empty) context the fetch functions need.
	"context"
	// flag reads command-line options such as -listen.
	"flag"
	// fmt writes formatted text, here into the web reply and the terminal output.
	"fmt"
	// log prints timestamped messages to the terminal.
	"log"
	// net/http is Go's built-in web server (standard library only, requirement T1).
	"net/http"
	// os reads environment variables and ends the program with an exit code.
	"os"
	// time provides durations such as the request-header timeout.
	"time"
) // end of imports

// defaultListen is where the page is served unless the user chooses otherwise: this machine only (requirement S1).
const defaultListen = "127.0.0.1:8765"

// helloHandler answers one kind of request; w is where we write the reply and r describes the incoming request.
func helloHandler(w http.ResponseWriter, r *http.Request) {
	// Tell the browser the reply is plain text, not a web page.
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	// Write the one-line reply; Fprintln adds a newline at the end.
	fmt.Fprintln(w, "OllamaControlCenter is running")
} // end of helloHandler

// formatCheck turns one check result into the single status line the -check option prints.
func formatCheck(res checkResult) string {
	// A successful check says ONLINE, the version and the time taken.
	if res.Online {
		// Build the online line; %s is text and %d is a whole number.
		return fmt.Sprintf("ONLINE  version %s  %d ms", res.Version, res.Elapsed.Milliseconds())
	} // end of the online case
	// A failed check says OFFLINE, the reason and the time taken.
	return fmt.Sprintf("OFFLINE  %s  %d ms", res.Reason, res.Elapsed.Milliseconds())
} // end of formatCheck

// runModels fetches both lists, prints the report, and returns the exit code (0 = printed, 1 = Ollama could not be read).
func runModels(addr ollamaAddress) int {
	// An empty context with no deadline; each request has its own timeout.
	ctx := context.Background()
	// Fetch the installed models.
	installed, err := fetchInstalled(ctx, addr.URL, defaultCheckTimeout)
	// A failure here means Ollama could not be read.
	if err != nil {
		// Print one OFFLINE line with the plain reason, like -check does.
		fmt.Println("OFFLINE  " + err.Error())
		// Exit code 1 means failure.
		return 1
	} // end of the installed check
	// Fetch the loaded models.
	loaded, err := fetchLoaded(ctx, addr.URL, defaultCheckTimeout)
	// A failure here also means Ollama could not be read.
	if err != nil {
		// Print one OFFLINE line with the plain reason.
		fmt.Println("OFFLINE  " + err.Error())
		// Exit code 1 means failure.
		return 1
	} // end of the loaded check
	// Print the whole report; time.Now() is the clock used for the "time until unload" column.
	fmt.Println(renderReport(installed, loaded, time.Now()))
	// Exit code 0 means success.
	return 0
} // end of runModels

// main is where every Go program starts running.
func main() {
	// Define a -listen option: its name, its default value, and the help text shown by -h.
	listen := flag.String("listen", defaultListen, "address and port for the monitor page, as host:port")
	// Define an -ollama-url option; empty means "not given", so the environment variable or the default is used.
	ollamaFlag := flag.String("ollama-url", "", "address of the Ollama server; overrides the OCC_OLLAMA_URL environment variable (default http://127.0.0.1:11434)")
	// Define a -check switch: false unless given on the command line.
	checkFlag := flag.Bool("check", false, "check Ollama once, print one status line, and exit (0 = online, 1 = offline)")
	// Define a -models switch: false unless given on the command line.
	modelsFlag := flag.Bool("models", false, "print the installed and loaded models as tables, and exit (0 = printed, 1 = Ollama not reachable)")
	// Read the command line now, so the variables above receive their values.
	flag.Parse()

	// The two one-shot modes cannot be combined; ask the person to choose one.
	if *checkFlag && *modelsFlag {
		// log.Fatal prints the message and exits with code 1.
		log.Fatal("use either -check or -models, not both")
	} // end of the combination check

	// Choose the Ollama address by precedence: option, then environment variable, then default.
	addr, err := resolve(*ollamaFlag, os.Getenv(envOllamaURL))
	// If the address is unusable, stop with a clear message and a failure exit code.
	if err != nil {
		// log.Fatalf prints the message and exits with code 1.
		log.Fatalf("%v", err)
	} // end of the address check
	// Print the address (any password shown as xxxxx) and which layer supplied it.
	log.Printf("Ollama address: %s (from %s)", addr.URL.Redacted(), addr.Source)

	// In -models mode, print both tables and leave without starting the web page.
	if *modelsFlag {
		// Run it and leave with its exit code.
		os.Exit(runModels(addr))
	} // end of the models mode

	// In -check mode, knock once, print the result, and leave without starting the web page.
	if *checkFlag {
		// Ask Ollama once, waiting at most the default timeout.
		res := checkOllama(context.Background(), addr.URL, defaultCheckTimeout)
		// Print the single status line.
		fmt.Println(formatCheck(res))
		// Exit with 0 when online, so scripts can tell it worked.
		if res.Online {
			// Leave with the success code.
			os.Exit(0)
		} // end of the online exit
		// Leave with the failure code.
		os.Exit(1)
	} // end of the check mode

	// Create a router, which decides which function answers which URL.
	mux := http.NewServeMux()
	// Route: a GET request for exactly "/" is answered by helloHandler; any other path gets a 404.
	mux.HandleFunc("GET /{$}", helloHandler)

	// Describe the web server: Addr is where to listen (the star reads the flag's value), Handler is the router,
	// and ReadHeaderTimeout drops clients that take more than 5 seconds to send their request headers.
	server := &http.Server{Addr: *listen, Handler: mux, ReadHeaderTimeout: 5 * time.Second}

	// Tell the person which address we are about to serve on.
	log.Printf("OllamaControlCenter listening on http://%s (press Ctrl+C to stop)", *listen)
	// Start serving; this call blocks (waits) until the server stops or fails, for example if the port is taken.
	err = server.ListenAndServe()
	// If we get here the server has stopped; log.Fatal prints the reason and exits with an error code.
	log.Fatal(err)
} // end of main
EOF_MAIN

# Fail if any Go file is not formatted the standard way (gofmt -l lists offenders).
unformatted="$(gofmt -l .)"
# An empty list means everything is formatted.
if [ -n "$unformatted" ]; then
  # Show the offenders and stop.
  echo "NOT FORMATTED: $unformatted"; exit 1
fi # end of the format check
# Ask Go to look for suspicious constructs in the program and the tests.
go vet ./...
# Run every test quietly; a failure stops the script and shows Go's own message.
go test -count=1 ./...
# Make sure the output folder exists.
mkdir -p bin
# Build the native executable (CGO_ENABLED=0 = no C libraries; -trimpath removes local paths).
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Say the build and tests worked.
echo "PASS  tests and build"

# Counters for passed and failed checks.
pass=1; fail=0

# run_case LABEL EXPECTED_EXIT_CODE EXPECTED_TEXT [options...]: runs the program and checks its exit code and output.
run_case() {
  # Name the three fixed arguments.
  local label="$1" want_rc="$2" want_text="$3"
  # Drop them so only the program's options remain.
  shift 3
  # Run it, capture all output, and record the exit code (the || keeps set -e from stopping the script).
  rc=0; out="$(OCC_OLLAMA_URL="" ./bin/OllamaControlCenter "$@" 2>&1)" || rc=$?
  # Both the exit code and the text must match.
  if [ "$rc" -eq "$want_rc" ] && printf '%s' "$out" | grep -qF -- "$want_text"; then
    # Report success and count it.
    echo "PASS  $label (exit $rc)"; pass=$((pass+1))
  else
    # Report failure, show what happened, and count it.
    echo "FAIL  $label -> exit $rc, output: $out"; fail=$((fail+1))
  fi # end of the match check
} # end of run_case

# Case 1: the real (or chosen) Ollama prints both tables and exits 0.
run_case "-models against Ollama" 0 "INSTALLED MODELS" -models -ollama-url "$OLLAMA_TEST_URL"
# Case 2: port 1 has nothing listening, so one OFFLINE line and exit 1.
run_case "-models offline" 1 "OFFLINE  connection refused" -models -ollama-url http://127.0.0.1:1
# Case 3: the two one-shot modes cannot be combined.
run_case "-check with -models rejected" 1 "use either -check or -models" -check -models
# Case 4: the new option appears in the help text.
run_case "-h lists -models" 0 "-models" -h
# Case 5: -check still works as before.
run_case "-check still works" 0 "ONLINE  version" -check -ollama-url "$OLLAMA_TEST_URL"

# Print the totals.
echo "Result: $pass passed, $fail failed"
# Show the real output, so the tables can be read here (read-only against Ollama).
echo
# Run -models once more against the chosen Ollama and show everything it prints.
OCC_OLLAMA_URL="" ./bin/OllamaControlCenter -models -ollama-url "$OLLAMA_TEST_URL" || true
# Exit with 0 only if nothing failed.
[ "$fail" -eq 0 ]
