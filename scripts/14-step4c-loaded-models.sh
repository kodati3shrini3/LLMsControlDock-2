#!/usr/bin/env bash
# Script 14: Step 4c, adds the Loaded-models fetch, the loaded/not-loaded state and the time-until-unload text, with tests from the user's real /api/ps entry.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"

# Write loaded.go; the quoted EOF_LOADED marker saves every character exactly as typed.
cat > loaded.go << 'EOF_LOADED'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context lets a request be cancelled or given a deadline.
	"context"
	// fmt builds formatted text.
	"fmt"
	// net/url holds the parsed address type.
	"net/url"
	// time provides the timestamp type and durations.
	"time"
) // end of imports

// loadedModel is one row of the Loaded table, as returned by /api/ps.
type loadedModel struct {
	// Name is the model name including its tag.
	Name string `json:"name"`
	// Size is the size in bytes that Ollama reports for the running model (it looked like the memory used on the test machine).
	Size int64 `json:"size"`
	// Digest is the model's fingerprint.
	Digest string `json:"digest"`
	// SizeVRAM is how many bytes sit in GPU memory (VRAM, video random-access memory).
	SizeVRAM int64 `json:"size_vram"`
	// ContextLength is the context window of the running model, which can differ from the model's maximum.
	ContextLength int64 `json:"context_length"`
	// ExpiresAt is kept as the original text, so an unexpected format cannot make the whole list fail to decode.
	ExpiresAt string `json:"expires_at"`
} // end of loadedModel

// psReply is the shape of the JSON that /api/ps returns.
type psReply struct {
	// Models is the list of loaded models.
	Models []loadedModel `json:"models"`
} // end of psReply

// installedRow is one row of the Installed table: the installed model plus whether it is loaded right now.
type installedRow struct {
	// Model is the installed model's data.
	Model installedModel
	// Loaded is true when the model is in the loaded list.
	Loaded bool
} // end of installedRow

// fetchLoaded returns the models that are loaded right now (an empty list when none are).
func fetchLoaded(ctx context.Context, base *url.URL, timeout time.Duration) ([]loadedModel, error) {
	// Prepare a place to hold the decoded JSON.
	var reply psReply
	// Fetch /api/ps and decode it (getJSON comes from models.go).
	if err := getJSON(ctx, base, "api/ps", timeout, &reply); err != nil {
		// Pass the safe error on, with no models.
		return nil, err
	} // end of the fetch check
	// Return the list.
	return reply.Models, nil
} // end of fetchLoaded

// expiresTime reads the unload time; the second result is false when the text is missing or in an unknown format.
func (m loadedModel) expiresTime() (time.Time, bool) {
	// An empty text means Ollama did not report a time.
	if m.ExpiresAt == "" {
		// Say "no usable time".
		return time.Time{}, false
	} // end of the empty check
	// Read the text in the standard RFC 3339 format (Request For Comments 3339), with or without fractional seconds.
	t, err := time.Parse(time.RFC3339Nano, m.ExpiresAt)
	// A parse failure means an unknown format.
	if err != nil {
		// Say "no usable time".
		return time.Time{}, false
	} // end of the parse check
	// Return the instant; an offset such as +02:00 or -07:00 is handled by the parser.
	return t, true
} // end of expiresTime

// combine marks every installed model as loaded or not, matching by name; a loaded name that is not installed adds no row.
func combine(installed []installedModel, loaded []loadedModel) []installedRow {
	// Build a lookup of loaded names; a map answers "is this name in there?" in one step.
	isLoaded := make(map[string]bool, len(loaded))
	// Go through every loaded model.
	for _, l := range loaded {
		// Remember its name.
		isLoaded[l.Name] = true
	} // end of the loaded loop
	// Prepare the result with room for every installed model.
	rows := make([]installedRow, 0, len(installed))
	// Go through every installed model, keeping the original order.
	for _, m := range installed {
		// Add a row with the model and its loaded flag.
		rows = append(rows, installedRow{Model: m, Loaded: isLoaded[m.Name]})
	} // end of the installed loop
	// Return the rows.
	return rows
} // end of combine

// stateText is the text for the state column; the symbol and the words always appear together so colour is never the only signal.
func stateText(loaded bool) string {
	// A loaded model gets a filled circle and the word Loaded.
	if loaded {
		// Return the loaded text.
		return "● Loaded"
	} // end of the loaded case
	// Everything else gets an empty circle and the words Not loaded.
	return "○ Not loaded"
} // end of stateText

// formatRemaining turns the time left before unload into readable text; ok is false when no time was reported.
func formatRemaining(now time.Time, expires time.Time, ok bool) string {
	// Without a usable time we say so instead of guessing.
	if !ok {
		// Return the neutral text.
		return "not reported"
	} // end of the no-time case
	// Work out how long is left, rounded to whole seconds.
	left := expires.Sub(now).Round(time.Second)
	// Zero or negative means the unload time has arrived.
	if left <= 0 {
		// Return the text for "now".
		return "unloading now"
	} // end of the past case
	// Count the whole seconds left.
	secs := int(left.Seconds())
	// Split them into hours, minutes and seconds.
	h, m, s := secs/3600, (secs%3600)/60, secs%60
	// With hours, show hours and minutes.
	if h > 0 {
		// Return hours and minutes.
		return fmt.Sprintf("%d h %d min", h, m)
	} // end of the hours case
	// With minutes, show minutes and seconds.
	if m > 0 {
		// Return minutes and seconds.
		return fmt.Sprintf("%d min %d s", m, s)
	} // end of the minutes case
	// Otherwise show only seconds.
	return fmt.Sprintf("%d s", s)
} // end of formatRemaining
EOF_LOADED

# Write loaded_test.go; the quoted EOF_LT marker saves every character exactly as typed.
cat > loaded_test.go << 'EOF_LT'
// Package main tells Go that this test file belongs to the same program as loaded.go.
package main

import ( // import lists the packages this test file uses.
	// context supplies the (empty) context the fetch function needs.
	"context"
	// net opens and closes a port, to find one with nothing listening.
	"net"
	// net/http provides handler types and status codes for the fake Ollama.
	"net/http"
	// strings checks whether text contains other text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
	// time provides the timeouts and the fixed clock.
	"time"
) // end of imports

// realPsBody is the real /api/ps reply from the user's Ollama 0.34.4 (medgemma:latest loaded with keep_alive 5m), on one line.
const realPsBody = `{"models":[{"name":"medgemma:latest","model":"medgemma:latest","size":3834631945,"digest":"9fe4e9a6c9bda2d007bb595515550eafbc8e226622adff9257f3241eba334c4d","details":{"parent_model":"","format":"gguf","family":"gemma3","families":["gemma3"],"parameter_size":"4.3B","quantization_level":"Q4_K_M"},"expires_at":"2026-10-25T00:16:27.255306668Z","size_vram":3834631945,"context_length":131072}]}`

// docsPsBody is the example from the official Ollama documentation, which uses a -07:00 time zone offset, on one line.
const docsPsBody = `{"models":[{"name":"gemma4","model":"gemma4","size":6591830464,"digest":"c6eb396dbd5992bbe3f5cdb947e8bbc0ee413d7c17e2beaae69f5d569cf982eb","details":{"parent_model":"","format":"gguf","family":"gemma4","families":["gemma4"],"parameter_size":"8.0B","quantization_level":"Q4_K_M"},"expires_at":"2025-10-17T16:47:07.93355-07:00","size_vram":5333539264,"context_length":4096}]}`

// psHandler builds a fake /api/ps handler that serves the given body and rejects every other request.
func psHandler(body string) http.HandlerFunc {
	// Return the handler function.
	return func(w http.ResponseWriter, r *http.Request) {
		// Only GET /api/ps is valid; anything else is a 404, so a wrong path fails the test.
		if r.Method != http.MethodGet || r.URL.Path != "/api/ps" {
			// Send the 404.
			http.NotFound(w, r)
			// Stop here.
			return
		} // end of the request check
		// Tell the client the body is JSON.
		w.Header().Set("Content-Type", "application/json")
		// Write the reply.
		w.Write([]byte(body))
	} // end of the handler
} // end of psHandler

// TestFetchLoadedReal checks the real entry from the user's server field by field.
func TestFetchLoadedReal(t *testing.T) {
	// Start a fake Ollama serving the real reply.
	srv := fakeOllama(t, psHandler(realPsBody))
	// Call the function under test.
	got, err := fetchLoaded(context.Background(), mustParse(t, srv.URL), time.Second)
	// An error here is a failure; Fatalf stops the test.
	if err != nil {
		// Report the unexpected error.
		t.Fatalf("unexpected error: %v", err)
	} // end of the error check
	// Exactly one model must arrive.
	if len(got) != 1 {
		// Stop the test.
		t.Fatalf("got %d models, want 1", len(got))
	} // end of the count check
	// Take the one model.
	m := got[0]
	// Compare the name, size and GPU size.
	if m.Name != "medgemma:latest" || m.Size != 3834631945 || m.SizeVRAM != 3834631945 {
		// Report the difference.
		t.Errorf("unexpected model: %+v", m)
	} // end of the basic check
	// Compare the loaded context length.
	if m.ContextLength != 131072 {
		// Report the difference.
		t.Errorf("context_length = %d, want 131072", m.ContextLength)
	} // end of the context check
	// The unload time must parse.
	exp, ok := m.expiresTime()
	// A parse failure is a test failure.
	if !ok {
		// Stop the test.
		t.Fatalf("expires_at %q did not parse", m.ExpiresAt)
	} // end of the parse check
	// The instant must equal 00:16:27 UTC, which is 02:16:27 at +02:00.
	if !exp.Equal(time.Date(2026, 10, 25, 0, 16, 27, 255306668, time.UTC)) {
		// Report the difference.
		t.Errorf("expires_at = %v, want 2026-10-25 00:16:27.255306668 UTC", exp)
	} // end of the instant check
} // end of TestFetchLoadedReal

// TestFetchLoadedDocsExample checks the documentation's example, which uses a -07:00 offset.
func TestFetchLoadedDocsExample(t *testing.T) {
	// Start a fake Ollama serving the documentation's reply.
	srv := fakeOllama(t, psHandler(docsPsBody))
	// Call the function under test.
	got, err := fetchLoaded(context.Background(), mustParse(t, srv.URL), time.Second)
	// An error here is a failure.
	if err != nil || len(got) != 1 {
		// Stop the test.
		t.Fatalf("got %d models and error %v, want 1 model and no error", len(got), err)
	} // end of the basic check
	// The unload time must parse.
	exp, ok := got[0].expiresTime()
	// A parse failure is a test failure.
	if !ok {
		// Stop the test.
		t.Fatalf("expires_at %q did not parse", got[0].ExpiresAt)
	} // end of the parse check
	// 16:47:07.93355 at -07:00 is 23:47:07.93355 UTC.
	if !exp.Equal(time.Date(2025, 10, 17, 23, 47, 7, 933550000, time.UTC)) {
		// Report the difference.
		t.Errorf("expires_at = %v, want 2025-10-17 23:47:07.93355 UTC", exp)
	} // end of the instant check
} // end of TestFetchLoadedDocsExample

// TestFetchLoadedEmpty checks that nothing loaded gives an empty list and no error.
func TestFetchLoadedEmpty(t *testing.T) {
	// Start a fake Ollama with nothing loaded.
	srv := fakeOllama(t, psHandler(`{"models":[]}`))
	// Call the function under test.
	got, err := fetchLoaded(context.Background(), mustParse(t, srv.URL), time.Second)
	// No error is expected.
	if err != nil {
		// Report the unexpected error.
		t.Fatalf("unexpected error: %v", err)
	} // end of the error check
	// The list must be empty.
	if len(got) != 0 {
		// Report the difference.
		t.Errorf("got %d models, want 0", len(got))
	} // end of the count check
} // end of TestFetchLoadedEmpty

// TestFetchLoadedBadTime checks that an unreadable expires_at does not break the list.
func TestFetchLoadedBadTime(t *testing.T) {
	// Start a fake Ollama whose time text is not a date.
	srv := fakeOllama(t, psHandler(`{"models":[{"name":"x","expires_at":"soon"},{"name":"y"}]}`))
	// Call the function under test.
	got, err := fetchLoaded(context.Background(), mustParse(t, srv.URL), time.Second)
	// The list must still decode.
	if err != nil || len(got) != 2 {
		// Stop the test.
		t.Fatalf("got %d models and error %v, want 2 models and no error", len(got), err)
	} // end of the basic check
	// Neither model has a usable time.
	for _, m := range got {
		// Ask for the time.
		if _, ok := m.expiresTime(); ok {
			// Report the difference.
			t.Errorf("model %q: expected no usable time", m.Name)
		} // end of the usable check
	} // end of the model loop
} // end of TestFetchLoadedBadTime

// TestFetchLoadedFailures checks the failure messages and that a password never leaks.
func TestFetchLoadedFailures(t *testing.T) {
	// Find a port with nothing listening: open one, note it, close it.
	l, err := net.Listen("tcp", "127.0.0.1:0")
	// Failing to open a port means the test machine cannot run this test.
	if err != nil {
		// Stop the test.
		t.Fatalf("cannot open a test port: %v", err)
	} // end of the listen check
	// Remember the address.
	closedAddr := l.Addr().String()
	// Close it, so connections to it are refused.
	l.Close()
	// A server that answers HTML instead of JSON.
	html := fakeOllama(t, replyWith(http.StatusOK, "<html>hello</html>"))
	// A server that answers 404.
	notFound := fakeOllama(t, replyWith(http.StatusNotFound, "nope"))
	// A table of cases: address and the text the error must contain.
	cases := []struct {
		// name labels the case.
		name string
		// address is what we ask.
		address string
		// wantErr is text the error must contain.
		wantErr string
	}{
		// HTML instead of JSON.
		{"not json", html.URL, "not the expected JSON"},
		// Wrong status code.
		{"status 404", notFound.URL, "status 404"},
		// Nothing listening, with a password in the address that must not leak.
		{"connection refused", "http://me:secret@" + closedAddr, "connection refused"},
	} // end of the case table
	// Go through every case.
	for _, tc := range cases {
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Call the function under test.
			got, err := fetchLoaded(context.Background(), mustParse(t, tc.address), time.Second)
			// An error is required.
			if err == nil {
				// Stop this subtest.
				t.Fatal("expected an error, got none")
			} // end of the nil check
			// No models may be returned alongside an error.
			if got != nil {
				// Report the difference.
				t.Errorf("got %d models with an error, want none", len(got))
			} // end of the models check
			// The message must say what went wrong.
			if !strings.Contains(err.Error(), tc.wantErr) {
				// Report the difference.
				t.Errorf("error = %q, want it to contain %q", err.Error(), tc.wantErr)
			} // end of the message check
			// The message must never contain the password.
			if strings.Contains(err.Error(), "secret") {
				// Report the leak.
				t.Errorf("error leaks the password: %q", err.Error())
			} // end of the leak check
		}) // end of the subtest
	} // end of the case loop
} // end of TestFetchLoadedFailures

// TestCombine checks that only the loaded installed model is marked, and that a loaded name that is not installed adds no row.
func TestCombine(t *testing.T) {
	// Build the installed list from the six real models' names.
	var installed []installedModel
	// Go through the real rows from models_test.go.
	for _, r := range realModels {
		// Add an installed model with just the name.
		installed = append(installed, installedModel{Name: r.name})
	} // end of the row loop
	// Two models are loaded: one installed, and one the installed list does not know.
	loaded := []loadedModel{{Name: "medgemma:latest"}, {Name: "ghost:1b"}}
	// Combine them.
	rows := combine(installed, loaded)
	// There must be exactly one row per installed model.
	if len(rows) != len(installed) {
		// Stop the test.
		t.Fatalf("got %d rows, want %d", len(rows), len(installed))
	} // end of the count check
	// Check every row.
	for i, row := range rows {
		// Only medgemma:latest may be loaded.
		want := row.Model.Name == "medgemma:latest"
		// Compare the flag.
		if row.Loaded != want {
			// Report the difference.
			t.Errorf("row %d (%s): Loaded = %v, want %v", i, row.Model.Name, row.Loaded, want)
		} // end of the flag check
		// The original order must be kept.
		if row.Model.Name != installed[i].Name {
			// Report the difference.
			t.Errorf("row %d is %s, want %s", i, row.Model.Name, installed[i].Name)
		} // end of the order check
	} // end of the row loop
} // end of TestCombine

// TestStateText checks that the state text always has both a symbol and words.
func TestStateText(t *testing.T) {
	// A loaded model.
	if got := stateText(true); got != "● Loaded" {
		// Report the difference.
		t.Errorf("stateText(true) = %q", got)
	} // end of the loaded check
	// A model that is not loaded.
	if got := stateText(false); got != "○ Not loaded" {
		// Report the difference.
		t.Errorf("stateText(false) = %q", got)
	} // end of the not-loaded check
} // end of TestStateText

// TestFormatRemaining checks the time-left text with a fixed clock.
func TestFormatRemaining(t *testing.T) {
	// A fixed "now" makes every case repeatable.
	now := time.Date(2026, 10, 25, 0, 11, 27, 0, time.UTC)
	// A table of cases: how much time is left, whether a time was reported, and the expected text.
	cases := []struct {
		// name labels the case.
		name string
		// left is how long after now the unload happens.
		left time.Duration
		// ok says whether a usable time was reported.
		ok bool
		// want is the expected text.
		want string
	}{
		// Exactly five minutes, as in the real entry.
		{"five minutes", 5 * time.Minute, true, "5 min 0 s"},
		// A minute and a half.
		{"ninety seconds", 90 * time.Second, true, "1 min 30 s"},
		// Under a minute.
		{"forty-five seconds", 45 * time.Second, true, "45 s"},
		// Hours and minutes.
		{"three hours five minutes", 3*time.Hour + 5*time.Minute, true, "3 h 5 min"},
		// Exactly now.
		{"now", 0, true, "unloading now"},
		// Already past.
		{"past", -10 * time.Second, true, "unloading now"},
		// No usable time.
		{"not reported", 0, false, "not reported"},
	} // end of the case table
	// Go through every case.
	for _, tc := range cases {
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Call the function under test.
			if got := formatRemaining(now, now.Add(tc.left), tc.ok); got != tc.want {
				// Report the difference.
				t.Errorf("got %q, want %q", got, tc.want)
			} // end of the text check
		}) // end of the subtest
	} // end of the case loop
} // end of TestFormatRemaining
EOF_LT

# Fail if any Go file is not formatted the standard way (gofmt -l lists offenders).
unformatted="$(gofmt -l .)"
# An empty list means everything is formatted.
if [ -n "$unformatted" ]; then
  # Show the offenders and stop.
  echo "NOT FORMATTED: $unformatted"; exit 1
fi # end of the format check
# Ask Go to look for suspicious constructs in the program and the tests.
go vet ./...
# Run every test; -v lists each one, -count=1 forbids cached results so the tests really run.
go test -v -count=1 ./...
# Build the native executable to prove the whole program still compiles.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Say the build worked.
echo "PASS  build"
