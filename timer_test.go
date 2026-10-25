// Package main tells Go that this test file belongs to the same program as tableview.go.
package main

import ( // import lists the packages this test file uses.
	// net/http provides the request method name and status codes.
	"net/http"
	// regexp finds the timer markup in the page.
	"regexp"
	// strings searches the page text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
	// time provides the fixed clock the tests use.
	"time"
) // end of imports

// timerNow is the fixed "now" every timer test uses, so the results never depend on the real clock.
var timerNow = time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)

// TestTimerFor checks the text and ticking seconds for each kind of unload time Ollama can report.
func TestTimerFor(t *testing.T) {
	// The cases: the reported time, the expected text and the expected seconds.
	cases := []struct {
		// A name for the report.
		name string
		// The expires_at text Ollama sent.
		expires string
		// The expected timer text.
		text string
		// The expected ticking seconds.
		secs int
		// Whether the time has arrived.
		expired bool
	}{
		// Five minutes away, the usual Ollama default.
		{"five minutes", "2026-10-25T12:05:00Z", "5 min 0 s", 300, false},
		// Under a minute.
		{"seconds", "2026-10-25T12:00:20Z", "20 s", 20, false},
		// Over an hour, with an offset in the text.
		{"hours", "2026-10-25T15:05:00+02:00", "1 h 5 min", 3900, false},
		// The time has passed.
		{"past", "2026-10-25T11:59:00Z", "unloading now", 0, true},
		// Exactly now.
		{"now", "2026-10-25T12:00:00Z", "unloading now", 0, true},
		// Ollama keeps the model loaded forever: a time centuries away.
		{"forever", "2318-01-01T00:00:00Z", "stays loaded", 0, false},
		// Ollama sent nothing.
		{"missing", "", "not reported", 0, false},
		// Ollama sent something unreadable.
		{"garbage", "tomorrow", "not reported", 0, false},
	} // end of the case table
	// Go through the cases.
	for _, c := range cases {
		// Work out the timer.
		text, secs, expired := timerFor(loadedModel{Name: "m", ExpiresAt: c.expires}, timerNow)
		// Compare.
		if text != c.text || secs != c.secs || expired != c.expired {
			// Report the difference.
			t.Errorf("%s: got (%q, %d, %v), want (%q, %d, %v)", c.name, text, secs, expired, c.text, c.secs, c.expired)
		} // end of the compare
	} // end of the case loop
} // end of TestTimerFor

// TestTableViewTimersOnlyForLoaded checks that only a loaded row has a timer, and that it comes from that model's own unload time.
func TestTableViewTimersOnlyForLoaded(t *testing.T) {
	// Two loaded models with different unload times (one more than the other is not installed and must be ignored).
	loaded := []loadedModel{
		// The first loaded model: five minutes left.
		{Name: "medgemma:latest", ExpiresAt: "2026-10-25T12:05:00Z"},
		// A model that is loaded but not installed: no row.
		{Name: "ghost:1b", ExpiresAt: "2026-10-25T12:01:00Z"},
	} // end of the loaded list
	// Build the view with the fixed clock.
	v := buildTableViewAt(realInstalled(t), loaded, timerNow)
	// Count the rows with a timer.
	withTimer := 0
	// Go through every row.
	for _, g := range v.Groups {
		// Go through the rows of this section.
		for _, r := range g.Rows {
			// A row with a timer text.
			if r.Timer != "" {
				// Count it.
				withTimer++
				// It must be the loaded one, with its own figures.
				if r.Name != "medgemma:latest" || r.TimerSeconds != 300 || r.Timer != "5 min 0 s" {
					// Report the problem.
					t.Errorf("unexpected timer on %q: %q (%d)", r.Name, r.Timer, r.TimerSeconds)
				} // end of the check
			} // end of the timer check
		} // end of the row loop
	} // end of the group loop
	// Exactly one row has a timer.
	if withTimer != 1 {
		// Report the problem.
		t.Errorf("%d rows have a timer, want 1", withTimer)
	} // end of the count check
} // end of TestTableViewTimersOnlyForLoaded

// TestPageShowsTimerUnderState checks the page markup: a ticking timer on its own line after the state words and the Unload form, and no timer line for a row that is not loaded.
func TestPageShowsTimerUnderState(t *testing.T) {
	// A fake with one loaded model; its /api/ps entry has an unload time five minutes away.
	f := &loadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Fetch the page.
	status, _, body := get(t, rig.h, http.MethodGet, "/")
	// The page must load.
	if status != http.StatusOK {
		// Report the problem.
		t.Fatalf("status %d", status)
	} // end of the status check
	// The timer markup: its own line, the timer class, ticking seconds and the role.
	if !regexp.MustCompile(`<span class="timerline"><span class="timer countdown" data-seconds="\d+" role="timer" aria-label="Time until Ollama unloads alpha:1b">[^<]+</span></span>`).MatchString(body) {
		// Report the problem.
		t.Fatalf("no ticking timer line in the page")
	} // end of the timer check
	// The order inside the cell: state words, then the Unload form, then the timer line.
	iState := strings.Index(body, "Loaded</span>")
	// Where the Unload form starts.
	iForm := strings.Index(body, `action="/unload"`)
	// Where the timer line starts.
	iTimer := strings.Index(body, `<span class="timerline">`)
	// The three must come in this order.
	if !(iState >= 0 && iState < iForm && iForm < iTimer) {
		// Report the problem.
		t.Errorf("wrong order: state %d, unload form %d, timer line %d", iState, iForm, iTimer)
	} // end of the order check
	// Only the one loaded row has a timer line.
	if n := strings.Count(body, `class="timerline"`); n != 1 {
		// Report the problem.
		t.Errorf("%d timer lines, want 1", n)
	} // end of the count check
} // end of TestPageShowsTimerUnderState
