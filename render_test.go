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
