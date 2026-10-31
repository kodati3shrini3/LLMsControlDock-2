// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context stops the background check.
	"context"
	// net/http provides the method name and the cookie type.
	"net/http"
	// net/http/httptest builds a request with a query.
	"net/http/httptest"
	// net/url parses the fake address.
	"net/url"
	// strings searches the page text.
	"strings"
	// testing is Go's test framework.
	"testing"
	// time builds the moments and the waits.
	"time"
) // end of imports

// TestHistoryForgetsOldChecks checks that checks older than the window plus a minute are dropped.
func TestHistoryForgetsOldChecks(t *testing.T) {
	// An empty history.
	h := &sampleHistory{}
	// An old check and a new one.
	h.add(sample{At: chartNow().Add(-40 * time.Minute), Online: true})
	// The new one pushes the old one out.
	h.add(sample{At: chartNow(), Online: true})
	// Only one is left.
	if got := h.since(chartNow().Add(-time.Hour)); len(got) != 1 || !got[0].At.Equal(chartNow()) {
		// Report it.
		t.Errorf("history holds %d checks", len(got))
	} // end of the check
} // end of TestHistoryForgetsOldChecks

// TestHistoryHasACeiling checks that memory use is bounded even when checks arrive faster than expected.
func TestHistoryHasACeiling(t *testing.T) {
	// An empty history.
	h := &sampleHistory{}
	// Many checks within one second.
	for i := 0; i < maxSamples*3; i++ {
		// One check.
		h.add(sample{At: chartNow().Add(time.Duration(i) * time.Millisecond), Online: true, Ms: int64(i)})
	} // end of the loop
	// The ceiling holds, and the newest are the ones kept.
	got := h.since(chartNow().Add(-time.Hour))
	// Check the count and the newest.
	if len(got) != maxSamples || got[len(got)-1].Ms != int64(maxSamples*3-1) {
		// Report it.
		t.Errorf("%d checks kept", len(got))
	} // end of the check
} // end of TestHistoryHasACeiling

// TestPageCheckCountsOnlyWithoutBackground checks who counts: the page when no background check runs, nobody else when one does.
func TestPageCheckCountsOnlyWithoutBackground(t *testing.T) {
	// A monitor without a background check.
	m := newMonitor()
	// A failed check.
	bad := checkResult{Online: false, Reason: "x"}
	// The page counts its own check.
	if v := m.pageCheck(bad, chartNow()); v.FailedTotal != 1 || len(m.hist.since(chartNow().Add(-time.Hour))) != 1 {
		// Report it.
		t.Errorf("page check was not counted: %+v", v)
	} // end of the check
	// A background check is switched on.
	m.background.Store(true)
	// The page no longer counts.
	if v := m.pageCheck(bad, chartNow()); v.FailedTotal != 1 || len(m.hist.since(chartNow().Add(-time.Hour))) != 1 {
		// Report it.
		t.Errorf("page check was counted during a background check: %+v", v)
	} // end of the check
} // end of TestPageCheckCountsOnlyWithoutBackground

// TestBackgroundChecksRun checks that the background loop measures by itself and the page then only reads.
func TestBackgroundChecksRun(t *testing.T) {
	// A fake Ollama that answers.
	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.34.4"}`))
	// Its address.
	base, err := url.Parse(srv.URL)
	// It must parse.
	if err != nil {
		// Stop.
		t.Fatalf("bad address: %v", err)
	} // end of the check
	// A monitor.
	m := newMonitor()
	// Stop the loop at the end of the test.
	ctx, cancel := context.WithCancel(context.Background())
	// Cancel at the end.
	defer cancel()
	// Check every 5 milliseconds.
	m.start(ctx, base, time.Second, 5*time.Millisecond)
	// The page now only reads.
	if !m.background.Load() {
		// Report it.
		t.Fatalf("the background flag is not set")
	} // end of the check
	// Wait until a few checks arrived, at most 3 seconds.
	deadline := time.Now().Add(3 * time.Second)
	// Poll.
	for time.Now().Before(deadline) && len(m.hist.since(time.Now().Add(-time.Hour))) < 3 {
		// A short wait.
		time.Sleep(5 * time.Millisecond)
	} // end of the loop
	// At least three answered checks.
	got := m.hist.since(time.Now().Add(-time.Hour))
	// Check them.
	if len(got) < 3 || !got[0].Online {
		// Report it.
		t.Fatalf("%d background checks", len(got))
	} // end of the check
	// Stop the loop and wait for it to settle.
	cancel()
	// A moment for a check in flight to end.
	time.Sleep(50 * time.Millisecond)
	// The count must stop growing.
	n := len(m.hist.since(time.Now().Add(-time.Hour)))
	// Wait again.
	time.Sleep(50 * time.Millisecond)
	// Still the same.
	if n2 := len(m.hist.since(time.Now().Add(-time.Hour))); n2 != n {
		// Report it.
		t.Errorf("checks kept running after the stop: %d then %d", n, n2)
	} // end of the check
} // end of TestBackgroundChecksRun

// TestMainPageShowsTheCharts checks the Charts box on the page: shown by default, folded with the other two, and the table of numbers behind its own link.
func TestMainPageShowsTheCharts(t *testing.T) {
	// A fake and a rig; the rig already asked once, so one check is in the history.
	rig, _ := perfRig(t, newPerfFake())
	// The default page.
	page := pageWithCookie(t, rig, nil)
	// The parts.
	for _, w := range []string{`aria-labelledby="charts-title"`, ">Charts</span>", "Ollama&#39;s answers over the last 30 minutes", "State of Ollama", "Answer time", "Ollama answered 100 % of", `<svg class="chartsvg"`, `id="hatch"`, `class="cell cell-ok"`, "each time this page loads", `href="/?numbers=open#numbers"`, `<meta http-equiv="refresh"`} {
		// Look for it.
		if !strings.Contains(page, w) {
			// Report the gap.
			t.Errorf("the page lacks %q", w)
		} // end of the check
	} // end of the loop
	// The table is closed by default.
	if strings.Contains(page, "The newest checks, scrolls sideways") {
		// Report it.
		t.Errorf("the table of numbers is open by default")
	} // end of the check
	// Folded with the other two boxes.
	if folded := pageWithCookie(t, rig, &http.Cookie{Name: detailsCookieName, Value: "closed"}); strings.Contains(folded, "charts-title") {
		// Report it.
		t.Errorf("the charts stay when the details are folded")
	} // end of the check
	// The open table pauses the refresh and lists the checks.
	req, rec := httptest.NewRequest(http.MethodGet, "/?numbers=open", nil), httptest.NewRecorder()
	// Serve it.
	rig.h.ServeHTTP(rec, req)
	// The page.
	open := rec.Body.String()
	// The parts.
	for _, w := range []string{"The newest checks, scrolls sideways", "<th scope=\"col\">Answer time</th>", "Answered", "Paused while the numbers of the charts are open", `href="/#numbers"`} {
		// Look for it.
		if !strings.Contains(open, w) {
			// Report the gap.
			t.Errorf("the page with the numbers lacks %q", w)
		} // end of the check
	} // end of the loop
	// No refresh while the numbers are open.
	if strings.Contains(open, `http-equiv="refresh"`) {
		// Report it.
		t.Errorf("the page refreshes while the numbers are open")
	} // end of the check
} // end of TestMainPageShowsTheCharts
