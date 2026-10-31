// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds the fake Ollama's replies.
	"fmt"
	// net/http serves the fake Ollama.
	"net/http"
	// net/http/httptest runs the fake Ollama.
	"net/http/httptest"
	// regexp checks that the time carries a zone.
	"regexp"
	// strings searches the page.
	"strings"
	// sync keeps the counters test free of races.
	"sync"
	// sync/atomic switches the fake Ollama on and off.
	"sync/atomic"
	// testing is Go's test framework.
	"testing"
	// time gives fixed moments.
	"time"
) // end of imports

// timeWithZone matches the last successful check as the page writes it: day, month, year, clock time with seconds, and a zone name or offset.
var timeWithZone = regexp.MustCompile(`Last successful check: <strong>\d{1,2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} [A-Za-z0-9+\-]+</strong>`)

// TestAPIHealthCounts checks the rules: failures in a row restart at zero after a good check, the total only grows, and the last good check carries its time zone.
func TestAPIHealthCounts(t *testing.T) {
	// A fixed zone with a name, so the text can be checked.
	cet := time.FixedZone("CET", 3600)
	// The counters.
	h := &apiHealth{}
	// A first failure: nothing has succeeded yet.
	if v := h.record(false, time.Date(2026, 10, 31, 14, 0, 0, 0, cet)); v.FailedRow != 1 || v.FailedTotal != 1 || v.LastOK != healthNever {
		// Report it.
		t.Errorf("first failure: %+v", v)
	} // end of the first check
	// A second failure.
	if v := h.record(false, time.Date(2026, 10, 31, 14, 1, 0, 0, cet)); v.FailedRow != 2 || v.FailedTotal != 2 {
		// Report it.
		t.Errorf("second failure: %+v", v)
	} // end of the second check
	// A good check: the run ends, the total stays, the moment is written with its zone.
	if v := h.record(true, time.Date(2026, 10, 31, 14, 55, 12, 0, cet)); v.FailedRow != 0 || v.FailedTotal != 2 || v.LastOK != "31 Oct 2026 14:55:12 CET" {
		// Report it.
		t.Errorf("good check: %+v", v)
	} // end of the good check
	// Another failure: a new run of one, the total grows, the last good moment is kept.
	if v := h.record(false, time.Date(2026, 10, 31, 15, 0, 0, 0, cet)); v.FailedRow != 1 || v.FailedTotal != 3 || v.LastOK != "31 Oct 2026 14:55:12 CET" {
		// Report it.
		t.Errorf("failure after success: %+v", v)
	} // end of the last check
} // end of TestAPIHealthCounts

// TestAPIHealthIsSafeForManyRequests checks that many page requests at once lose no count.
func TestAPIHealthIsSafeForManyRequests(t *testing.T) {
	// The counters.
	h := &apiHealth{}
	// Wait for all the goroutines.
	var wg sync.WaitGroup
	// One hundred failing checks at once.
	for i := 0; i < 100; i++ {
		// Count the goroutine.
		wg.Add(1)
		// Start it.
		go func() {
			// Done at the end.
			defer wg.Done()
			// One failed check.
			h.record(false, time.Now())
		}() // end of the goroutine
	} // end of the loop
	// Wait.
	wg.Wait()
	// Nothing was lost.
	if v := h.record(false, time.Now()); v.FailedTotal != 101 || v.FailedRow != 101 {
		// Report it.
		t.Errorf("counts after 101 failures: %+v", v)
	} // end of the count check
} // end of TestAPIHealthIsSafeForManyRequests

// TestMainPageShowsTheCounters checks the page through the real handler: the heading with its bubble, the counters growing while Ollama is down, the run ending when it answers, and the last good check with its time zone.
func TestMainPageShowsTheCounters(t *testing.T) {
	// A fake Ollama that can be switched off.
	var up atomic.Bool
	// Start it down.
	up.Store(false)
	// The server.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Down: an error for everything.
		if !up.Load() {
			// A server error.
			http.Error(w, "down", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the down check
		// Up: the version, and empty lists for the rest.
		if r.URL.Path == "/api/version" {
			// The version.
			fmt.Fprint(w, `{"version":"0.34.4"}`)
			// Stop here.
			return
		} // end of the version check
		// Empty lists.
		fmt.Fprint(w, `{"models":[]}`)
	})) // end of the handler
	// Stop it at the end.
	t.Cleanup(srv.Close)
	// The monitor, built once so its counters live across requests.
	h := handlerFor(t, srv.URL)
	// Fetch the page.
	page := func() string {
		// Ask.
		_, _, body := get(t, h, http.MethodGet, "/")
		// The text.
		return body
	} // end of page
	// The first page while Ollama is down.
	body := page()
	// The heading, its bubble that names the Ollama status, and the first counters.
	for _, want := range []string{`>API health</span>`, "Ollama status: does Ollama answer", "Failed checks: <strong>1</strong> in a row, <strong>1</strong> in total since this monitor started", "Last successful check: <strong>none since this monitor started</strong>", "⚠"} {
		// Missing.
		if !strings.Contains(body, want) {
			// Report it.
			t.Errorf("first page lacks %q", want)
		} // end of the check
	} // end of the loop
	// A second page while still down.
	if body = page(); !strings.Contains(body, "<strong>2</strong> in a row, <strong>2</strong> in total") {
		// Report it.
		t.Errorf("second failure not counted")
	} // end of the second check
	// Ollama comes back.
	up.Store(true)
	// The next page.
	body = page()
	// The run ended, the total stayed, and the last good check has a time zone name.
	if !strings.Contains(body, "<strong>0</strong> in a row, <strong>2</strong> in total") || strings.Contains(body, "⚠ Failed checks") || strings.Contains(body, "none since this monitor started") {
		// Report it.
		t.Errorf("recovery not shown: %.400s", body)
	} // end of the recovery check
	// The time carries a zone: letters or a numeric offset after the clock time.
	if !timeWithZone.MatchString(body) {
		// Report it.
		t.Errorf("the last successful check shows no time zone")
	} // end of the zone check
} // end of TestMainPageShowsTheCounters
