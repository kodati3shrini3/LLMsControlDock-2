#!/usr/bin/env bash
# Script 12: Step 4b, adds the Installed-models fetch (models.go) with tests built from the user's real model data.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail

# Project folder; the PROJECT_DIR variable can override it (useful for testing).
PROJECT_DIR="${PROJECT_DIR:-/home/kodati/OllamaControlCenter}"

# Go into the project folder so file names resolve.
cd "$PROJECT_DIR"

# Write models.go; the quoted EOF_MODELS marker saves every character exactly as typed.
cat > models.go << 'EOF_MODELS'
// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context lets a request be cancelled or given a deadline.
	"context"
	// encoding/json decodes the JSON (JavaScript Object Notation) reply.
	"encoding/json"
	// errors creates simple error values.
	"errors"
	// fmt builds formatted text.
	"fmt"
	// io limits how much of a reply we read.
	"io"
	// net/http is the built-in web client.
	"net/http"
	// net/url holds the parsed address type.
	"net/url"
	// time provides the timestamp type and durations.
	"time"
) // end of imports

// maxListReply caps how many bytes of a model list we read (4 MiB, far more than any real list).
const maxListReply = 4 * 1024 * 1024

// modelDetails holds the "details" block of one installed model; fields we do not list (such as parent_model) are ignored.
type modelDetails struct {
	// Family is the model family exactly as Ollama reports it (for example gemma3).
	Family string `json:"family"`
	// ParameterSize is the size label Ollama reports (for example 27.4B).
	ParameterSize string `json:"parameter_size"`
	// QuantizationLevel is the compression level Ollama reports (for example Q4_K_M).
	QuantizationLevel string `json:"quantization_level"`
	// ContextLength is the largest context the model supports, in tokens.
	ContextLength int64 `json:"context_length"`
	// EmbeddingLength is the width of the model's internal vectors.
	EmbeddingLength int64 `json:"embedding_length"`
} // end of modelDetails

// installedModel is one row of the Installed table, as returned by /api/tags.
type installedModel struct {
	// Name is the model name including its tag (for example medgemma:latest).
	Name string `json:"name"`
	// ModifiedAt is when the model was last changed, in UTC.
	ModifiedAt time.Time `json:"modified_at"`
	// Size is the size on disk in bytes; int64 because large models exceed what a 32-bit number holds.
	Size int64 `json:"size"`
	// Digest is the model's fingerprint.
	Digest string `json:"digest"`
	// Capabilities lists what the model can do, as Ollama reports it (for example completion, vision, embedding).
	Capabilities []string `json:"capabilities"`
	// Details holds the family, sizes and lengths.
	Details modelDetails `json:"details"`
} // end of installedModel

// tagsReply is the shape of the JSON that /api/tags returns.
type tagsReply struct {
	// Models is the list of installed models.
	Models []installedModel `json:"models"`
} // end of tagsReply

// getJSON fetches base+path once and decodes the JSON reply into out; every error text is fixed and never contains the address.
func getJSON(ctx context.Context, base *url.URL, path string, timeout time.Duration, out any) error {
	// Build the full address by adding the path safely.
	target := base.JoinPath(path).String()
	// Create the request; the context allows cancelling it from outside.
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	// A failure here means the address could not form a request.
	if err != nil {
		// Return a fixed message.
		return errors.New("the address could not be used to build a request")
	} // end of the request check
	// Create a client that gives up after the timeout.
	client := &http.Client{Timeout: timeout}
	// Send the request and wait for the reply.
	resp, err := client.Do(req)
	// A failure here means no reply arrived at all.
	if err != nil {
		// Turn the technical error into a plain reason (reused from check.go).
		return errors.New(explainError(err))
	} // end of the send check
	// Always close the reply body when this function ends.
	defer resp.Body.Close()
	// Anything other than status 200 means this is not a healthy Ollama.
	if resp.StatusCode != http.StatusOK {
		// Report the status number; it contains no secrets.
		return fmt.Errorf("the server answered with status %d, not 200; it may not be Ollama", resp.StatusCode)
	} // end of the status check
	// Decode at most maxListReply bytes of the body into out.
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxListReply)).Decode(out); err != nil {
		// Not the expected JSON means something else answered.
		return errors.New("the reply was not the expected JSON, so it does not look like Ollama")
	} // end of the decode check
	// Everything worked.
	return nil
} // end of getJSON

// fetchInstalled returns every installed model, whatever its current state.
func fetchInstalled(ctx context.Context, base *url.URL, timeout time.Duration) ([]installedModel, error) {
	// Prepare a place to hold the decoded JSON.
	var reply tagsReply
	// Fetch /api/tags and decode it.
	if err := getJSON(ctx, base, "api/tags", timeout, &reply); err != nil {
		// Pass the safe error on, with no models.
		return nil, err
	} // end of the fetch check
	// Return the list (it may be empty on a machine with no models).
	return reply.Models, nil
} // end of fetchInstalled
EOF_MODELS

# Write models_test.go; the quoted EOF_MT marker saves every character exactly as typed.
cat > models_test.go << 'EOF_MT'
// Package main tells Go that this test file belongs to the same program as models.go.
package main

import ( // import lists the packages this test file uses.
	// context supplies the (empty) context the fetch function needs.
	"context"
	// encoding/json builds the fake reply and re-encodes results.
	"encoding/json"
	// net opens and closes a port, to find one with nothing listening.
	"net"
	// net/http provides handler types and status codes for the fake Ollama.
	"net/http"
	// strings checks whether text contains other text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
	// time provides the timeouts.
	"time"
) // end of imports

// realRow is one installed model exactly as the user's Ollama 0.34.4 reported it.
type realRow struct {
	// name is the model name.
	name string
	// size is the size on disk in bytes.
	size int64
	// modified is the modified_at text, including the nine fractional digits.
	modified string
	// caps is the capabilities list.
	caps []string
	// family is the details.family value.
	family string
	// paramSize is the details.parameter_size value.
	paramSize string
	// quant is the details.quantization_level value.
	quant string
	// ctx is the details.context_length value.
	ctx int64
	// emb is the details.embedding_length value.
	emb int64
	// parent is the details.parent_model value (the app must never expose it).
	parent string
} // end of realRow

// realModels is the user's real data, copied from the Step 4a output.
var realModels = []realRow{
	// A 27-billion-parameter chat model that can also read images.
	{"medgemma:27b", 17397224125, "2026-10-24T17:40:34.693006337Z", []string{"completion", "vision"}, "gemma3", "27.4B", "Q4_K_M", 131072, 5376, ""},
	// The small chat model that can also read images.
	{"medgemma:latest", 3338942556, "2026-10-21T15:48:07.304566509Z", []string{"completion", "vision"}, "gemma3", "4.3B", "Q4_K_M", 131072, 2560, ""},
	// An embedding model whose parent_model is a local file path.
	{"rjmalagon/gte-qwen2-instruct:1.5b-f16", 3558626188, "2026-10-19T14:14:46.450862481Z", []string{"embedding"}, "qwen2", "1.8B", "F16", 131072, 1536, "/root/.ollama/models/blobs/sha256-8962c82636c31ae380040ed933bb2a3933723bdd34c2d95288c7bb9500f49a1b"},
	// A chat model with tools and thinking, whose parent_model is an internal name.
	{"qwen3.6:27b", 17769076933, "2026-09-27T17:53:53.183023002Z", []string{"completion", "vision", "tools", "thinking"}, "qwen35", "27.3B", "Q4_K_M", 262144, 5120, "qwen3.6-source:27b-mtp-q4_K_M-20260824"},
	// A second embedding model.
	{"hf.co/NeoRoth/nemotron-3-embed-1b-gguf:F16", 2289844637, "2026-09-20T21:32:28.731228222Z", []string{"embedding"}, "mistral3", "1.14B", "F16", 262144, 2048, ""},
	// A chat model with images, audio, tools and thinking.
	{"gemma4:e4b", 9608350718, "2026-05-08T07:44:06.37520257Z", []string{"completion", "vision", "audio", "tools", "thinking"}, "gemma4", "8.0B", "Q4_K_M", 131072, 2560, ""},
} // end of realModels

// tagsHandler builds a fake /api/tags handler that serves the given rows and rejects every other request.
func tagsHandler(t *testing.T, rows []realRow) http.HandlerFunc {
	// Return the handler function.
	return func(w http.ResponseWriter, r *http.Request) {
		// Only GET /api/tags is valid; anything else is a 404, so a wrong path fails the test.
		if r.Method != http.MethodGet || r.URL.Path != "/api/tags" {
			// Send the 404.
			http.NotFound(w, r)
			// Stop here.
			return
		} // end of the request check
		// Build the list of models as generic JSON objects, in the shape Ollama uses.
		list := make([]map[string]any, 0, len(rows))
		// Go through every row.
		for _, row := range rows {
			// Add one model object with the same field names Ollama uses.
			list = append(list, map[string]any{
				// Top-level fields.
				"name": row.name, "model": row.name, "modified_at": row.modified, "size": row.size, "digest": "test-digest", "capabilities": row.caps,
				// The details block, including parent_model.
				"details": map[string]any{"family": row.family, "parameter_size": row.paramSize, "quantization_level": row.quant, "context_length": row.ctx, "embedding_length": row.emb, "parent_model": row.parent, "format": "gguf"},
			}) // end of the append
		} // end of the row loop
		// Tell the client the body is JSON.
		w.Header().Set("Content-Type", "application/json")
		// Write the whole reply.
		if err := json.NewEncoder(w).Encode(map[string]any{"models": list}); err != nil {
			// A write failure means the test itself is broken.
			t.Errorf("fake server could not write: %v", err)
		} // end of the write check
	} // end of the handler
} // end of tagsHandler

// TestFetchInstalledRealShape checks that all six real models are decoded correctly.
func TestFetchInstalledRealShape(t *testing.T) {
	// Start a fake Ollama serving the real data.
	srv := fakeOllama(t, tagsHandler(t, realModels))
	// Call the function under test.
	got, err := fetchInstalled(context.Background(), mustParse(t, srv.URL), time.Second)
	// An error here is a failure; Fatalf stops the test.
	if err != nil {
		// Report the unexpected error.
		t.Fatalf("unexpected error: %v", err)
	} // end of the error check
	// All six models must arrive.
	if len(got) != len(realModels) {
		// Stop the test; the comparisons below would be meaningless.
		t.Fatalf("got %d models, want %d", len(got), len(realModels))
	} // end of the count check
	// Compare every model with its source row.
	for i, want := range realModels {
		// Run each model as a named subtest.
		t.Run(want.name, func(t *testing.T) {
			// Take the decoded model at the same position.
			m := got[i]
			// Compare the name.
			if m.Name != want.name {
				// Report the difference.
				t.Errorf("name = %q, want %q", m.Name, want.name)
			} // end of the name check
			// Compare the size on disk.
			if m.Size != want.size {
				// Report the difference.
				t.Errorf("size = %d, want %d", m.Size, want.size)
			} // end of the size check
			// Compare the capabilities as one text.
			if strings.Join(m.Capabilities, ",") != strings.Join(want.caps, ",") {
				// Report the difference.
				t.Errorf("capabilities = %v, want %v", m.Capabilities, want.caps)
			} // end of the capabilities check
			// Compare the family, parameter size and quantization level.
			if m.Details.Family != want.family || m.Details.ParameterSize != want.paramSize || m.Details.QuantizationLevel != want.quant {
				// Report the difference.
				t.Errorf("details = %+v", m.Details)
			} // end of the details check
			// Compare the two length fields.
			if m.Details.ContextLength != want.ctx || m.Details.EmbeddingLength != want.emb {
				// Report the difference.
				t.Errorf("lengths = %d and %d, want %d and %d", m.Details.ContextLength, m.Details.EmbeddingLength, want.ctx, want.emb)
			} // end of the lengths check
			// The timestamp must parse and be in UTC.
			if m.ModifiedAt.IsZero() || m.ModifiedAt.Location() != time.UTC {
				// Report the difference.
				t.Errorf("modified_at = %v, want a non-zero UTC time", m.ModifiedAt)
			} // end of the timestamp check
		}) // end of the subtest
	} // end of the model loop
	// Re-encode everything we decoded, to prove the local file path and the internal name never survive.
	out, err := json.Marshal(got)
	// An encoding failure means the test itself is broken.
	if err != nil {
		// Stop the test.
		t.Fatalf("cannot re-encode: %v", err)
	} // end of the encode check
	// Neither the blob path nor the internal source name may appear.
	if strings.Contains(string(out), "/root/.ollama") || strings.Contains(string(out), "qwen3.6-source") {
		// Report the leak.
		t.Errorf("parent_model data leaked into the result")
	} // end of the leak check
} // end of TestFetchInstalledRealShape

// TestFetchInstalledEmpty checks that a machine with no models gives an empty list and no error.
func TestFetchInstalledEmpty(t *testing.T) {
	// Start a fake Ollama with no models.
	srv := fakeOllama(t, tagsHandler(t, nil))
	// Call the function under test.
	got, err := fetchInstalled(context.Background(), mustParse(t, srv.URL), time.Second)
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
} // end of TestFetchInstalledEmpty

// TestFetchInstalledFailures checks the failure messages and that a password never leaks.
func TestFetchInstalledFailures(t *testing.T) {
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
			got, err := fetchInstalled(context.Background(), mustParse(t, tc.address), time.Second)
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
} // end of TestFetchInstalledFailures
EOF_MT

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
