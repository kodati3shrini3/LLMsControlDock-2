// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// net/http provides the method name.
	"net/http"
	// strings searches the text.
	"strings"
	// testing is Go's test framework.
	"testing"
	// time builds the moments.
	"time"
) // end of imports

// lm builds a loaded model with a size, a GPU share and an unload time.
func lm(name string, size, vram int64, expires string) loadedModel {
	// The model.
	return loadedModel{Name: name, Size: size, SizeVRAM: vram, ExpiresAt: expires}
} // end of lm

// TestMemoryMessages checks the three reasons for an empty list.
func TestMemoryMessages(t *testing.T) {
	// The cases.
	for name, tc := range map[string]struct {
		// online and listsOK are the inputs.
		online, listsOK bool
		// loaded is the list.
		loaded []loadedModel
		// want is the message.
		want string
	}{
		"offline":    {false, false, nil, "Ollama is not answering, so the loaded models are not known."},
		"unreadable": {true, false, nil, "The list of loaded models could not be read just now."},
		"none":       {true, true, nil, "No model is loaded."},
	} { // end of the cases
		// Build.
		v := buildMemory(tc.loaded, tc.online, tc.listsOK, chartNow())
		// Compare.
		if v.Message != tc.want || len(v.Rows) != 0 {
			// Report it.
			t.Errorf("%s: %q with %d rows", name, v.Message, len(v.Rows))
		} // end of the check
	} // end of the loop
} // end of TestMemoryMessages

// TestMemoryRows checks the order, the bar lengths, the sum and the texts.
func TestMemoryRows(t *testing.T) {
	// Now, and an unload time 4 min 12 s later.
	now := chartNow()
	// The time text.
	soon := now.Add(4*time.Minute + 12*time.Second).Format(time.RFC3339Nano)
	// The models, the largest in the middle.
	in := []loadedModel{
		lm("small:1b", 1_000_000_000, 1_000_000_000, "2318-01-01T00:00:00Z"),
		lm("big:27b", 20_000_000_000, 8_000_000_000, soon),
		lm("tiny:1b", 10_000_000, 0, ""),
	}
	// Build.
	v := buildMemory(in, true, true, now)
	// Three rows, largest first.
	if len(v.Rows) != 3 || v.Rows[0].Name != "big:27b" || v.Rows[1].Name != "small:1b" || v.Rows[2].Name != "tiny:1b" {
		// Report it.
		t.Fatalf("order wrong: %+v", v.Rows)
	} // end of the order check
	// The caller's list is untouched.
	if in[0].Name != "small:1b" {
		// Report it.
		t.Errorf("the caller's list was reordered")
	} // end of the copy check
	// The largest fills the bar; the small one is 5 %; the tiny one still shows a sliver of 1 %.
	if v.Rows[0].Percent != 100 || v.Rows[0].Fill != memBarWidth || v.Rows[1].Percent != 5 || v.Rows[1].Fill != 15 || v.Rows[2].Percent != 1 || v.Rows[2].Fill != 3 {
		// Report it.
		t.Errorf("bars wrong: %+v", v.Rows)
	} // end of the bar check
	// The sizes and the sum.
	if v.Rows[0].Size != "20.0 GB" || v.Rows[2].Size != "10 MB" || v.Total != "21.0 GB" {
		// Report it.
		t.Errorf("sizes wrong: %q %q total %q", v.Rows[0].Size, v.Rows[2].Size, v.Total)
	} // end of the size check
	// The GPU share: 40 percent, all, and none.
	if v.Rows[0].Where != "40 % in GPU memory, 60 % in processor memory" || v.Rows[1].Where != "all in GPU memory" || v.Rows[2].Where != "none in GPU memory (all in processor memory)" {
		// Report it.
		t.Errorf("where wrong: %q / %q / %q", v.Rows[0].Where, v.Rows[1].Where, v.Rows[2].Where)
	} // end of the where check
	// The timers: counting, set to stay loaded, and not reported.
	if v.Rows[0].Timer != "unloads in 4 min 12 s" || v.Rows[1].Timer != "stays loaded (no unload time)" || v.Rows[2].Timer != "unload time not reported" {
		// Report it.
		t.Errorf("timers wrong: %q / %q / %q", v.Rows[0].Timer, v.Rows[1].Timer, v.Rows[2].Timer)
	} // end of the timer check
} // end of TestMemoryRows

// TestMemoryUnknownSizeAndExpired checks a model without a size and a timer that has arrived.
func TestMemoryUnknownSizeAndExpired(t *testing.T) {
	// A model without a size and an expired one.
	v := buildMemory([]loadedModel{lm("nosize:1b", 0, 0, ""), lm("late:1b", 5_000_000_000, 5_000_000_000, chartNow().Add(-time.Minute).Format(time.RFC3339Nano))}, true, true, chartNow())
	// The sized one first.
	if v.Rows[0].Name != "late:1b" || v.Rows[0].Timer != "unloading now" {
		// Report it.
		t.Errorf("expired row wrong: %+v", v.Rows[0])
	} // end of the expired check
	// The unsized one has no bar and says so.
	if r := v.Rows[1]; r.Size != "size not reported" || r.Fill != 0 || r.Where != "memory split not reported" {
		// Report it.
		t.Errorf("unsized row wrong: %+v", r)
	} // end of the unsized check
	// The sum counts only the known size.
	if v.Total != "5.0 GB" {
		// Report it.
		t.Errorf("total %q", v.Total)
	} // end of the total check
} // end of TestMemoryUnknownSizeAndExpired

// TestMainPageShowsTheMemory checks the memory part on the page, with a hostile model name escaped.
func TestMainPageShowsTheMemory(t *testing.T) {
	// A fake and a rig.
	f := newPerfFake()
	// Build the rig.
	rig, _ := perfRig(t, f)
	// With nothing loaded.
	if page := pageWithCookie(t, rig, nil); !strings.Contains(page, "Memory of loaded models") || !strings.Contains(page, "No model is loaded.") {
		// Report it.
		t.Errorf("the empty memory part is missing")
	} // end of the empty check
	// A model with a hostile name is loaded.
	f.mu.Lock()
	// In memory.
	f.loaded["<b>x</b>:1b"] = true
	// Release the fake.
	f.mu.Unlock()
	// The page.
	page := pageWithCookie(t, rig, nil)
	// The parts.
	for _, w := range []string{"Memory of loaded models", `class="memlist"`, `class="membarsvg"`, "&lt;b&gt;x&lt;/b&gt;:1b", "4.0 GB", "Together 4.0 GB.", "Times left are as of"} {
		// Look for it.
		if !strings.Contains(page, w) {
			// Report the gap.
			t.Errorf("the page lacks %q", w)
		} // end of the check
	} // end of the loop
	// The name must be escaped everywhere in the memory part.
	if strings.Contains(page, "<b>x</b>") {
		// Report it.
		t.Errorf("a model name was not escaped")
	} // end of the escape check
	// Folded away with the rest of the Charts box.
	if folded := pageWithCookie(t, rig, &http.Cookie{Name: detailsCookieName, Value: "closed"}); strings.Contains(folded, "Memory of loaded models") {
		// Report it.
		t.Errorf("the memory part stays when the details are folded")
	} // end of the fold check
} // end of TestMainPageShowsTheMemory
