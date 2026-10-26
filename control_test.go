// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context is passed to the clean-up functions.
	"context"
	// net/http gives the status codes.
	"net/http"
	// net/http/httptest builds requests with cookies.
	"net/http/httptest"
	// net/url builds the form values.
	"net/url"
	// strings searches the page text.
	"strings"
	// sync/atomic counts calls from other goroutines.
	"sync/atomic"
	// testing is Go's test framework.
	"testing"
	// time bounds the waiting for the background stop.
	"time"
) // end of imports

// stopRecorder replaces the real shutdown for the length of a test and counts the requests.
func stopRecorder(t *testing.T) *atomic.Int32 {
	// Mark this as a helper.
	t.Helper()
	// Remember the real one.
	old := stopRequest
	// The counter.
	var n atomic.Int32
	// Count instead of stopping.
	stopRequest = func() { n.Add(1) }
	// Put the real one back at the end.
	t.Cleanup(func() { stopRequest = old })
	// Hand the counter back.
	return &n
} // end of stopRecorder

// pageWithCookie fetches the main page, sending the given cookie.
func pageWithCookie(t *testing.T, rig themeRig, cookie *http.Cookie) string {
	// Mark this as a helper.
	t.Helper()
	// Build the request.
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	// Add the cookie when there is one.
	if cookie != nil {
		// Send it.
		req.AddCookie(cookie)
	} // end of the cookie check
	// Run the handler.
	rec := httptest.NewRecorder()
	// Serve.
	rig.h.ServeHTTP(rec, req)
	// The page.
	return rec.Body.String()
} // end of pageWithCookie

// TestWatchPauseResume checks the automatic updates: on by default, off while paused, and the form rules.
func TestWatchPauseResume(t *testing.T) {
	// A fake and a rig.
	rig, _ := perfRig(t, newPerfFake())
	// By default the page updates itself every 10 seconds and offers Pause.
	page := pageWithCookie(t, rig, nil)
	// Look for the parts.
	for _, w := range []string{`<meta http-equiv="refresh" content="10">`, `name="action" value="pause"`, "Watching: the page updates itself every 10 seconds", `id="tipwatch"`, `id="tiprefresh"`, `id="tipstop"`, `action="/stop"`, `href="/"`} {
		// Look for it.
		if !strings.Contains(page, w) {
			// Report the gap.
			t.Errorf("the watching page lacks %q", w)
		} // end of the check
	} // end of the loop
	// Pausing sets the cookie and goes back to the page.
	res := post(t, rig.h, "/watch", url.Values{"token": {rig.token}, "action": {"pause"}}, fromThisPage)
	// A redirect to the page.
	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/" {
		// Report it.
		t.Errorf("pause: %d to %q", res.StatusCode, res.Header.Get("Location"))
	} // end of the redirect check
	// The cookie.
	var paused *http.Cookie
	// Find it.
	for _, c := range res.Cookies() {
		// The right one.
		if c.Name == watchCookieName {
			// Keep it.
			paused = c
		} // end of the name check
	} // end of the loop
	// It says paused, and it is not readable by scripts.
	if paused == nil || paused.Value != "paused" || !paused.HttpOnly {
		// Report it.
		t.Fatalf("pause cookie wrong: %+v", paused)
	} // end of the cookie check
	// With the cookie the page does not refresh itself and offers Resume.
	page = pageWithCookie(t, rig, &http.Cookie{Name: watchCookieName, Value: "paused"})
	// No refresh line.
	if strings.Contains(page, `http-equiv="refresh"`) {
		// Report it.
		t.Errorf("a paused page still refreshes itself")
	} // end of the refresh check
	// The paused parts.
	for _, w := range []string{`name="action" value="resume"`, "Paused: the page does not update by itself", "Make the page update itself every 10 seconds again"} {
		// Look for it.
		if !strings.Contains(page, w) {
			// Report the gap.
			t.Errorf("the paused page lacks %q", w)
		} // end of the check
	} // end of the loop
	// A cookie with another value does not pause.
	if strings.Contains(pageWithCookie(t, rig, &http.Cookie{Name: watchCookieName, Value: "yes"}), "Paused:") {
		// Report it.
		t.Errorf("a wrong cookie value paused the page")
	} // end of the value check
	// Resuming deletes the cookie.
	res = post(t, rig.h, "/watch", url.Values{"token": {rig.token}, "action": {"resume"}}, fromThisPage)
	// A deleting cookie has a negative age.
	gone := false
	// Look at the cookies.
	for _, c := range res.Cookies() {
		// The right one, deleted.
		if c.Name == watchCookieName && c.MaxAge < 0 {
			// Found.
			gone = true
		} // end of the check
	} // end of the loop
	// It must be deleted.
	if res.StatusCode != http.StatusSeeOther || !gone {
		// Report it.
		t.Errorf("resume: %d, deleted=%v", res.StatusCode, gone)
	} // end of the resume check
	// The rules: a wrong token, another site, a bad action and a plain GET are all refused.
	for name, tc := range map[string]struct {
		// form is what is sent.
		form url.Values
		// headers are the request headers.
		headers map[string]string
		// want is the expected status.
		want int
	}{
		"wrong token": {url.Values{"token": {"0123456789abcdef0123456789abcdef"}, "action": {"pause"}}, fromThisPage, http.StatusForbidden},
		"other site":  {url.Values{"token": {rig.token}, "action": {"pause"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
		"bad action":  {url.Values{"token": {rig.token}, "action": {"explode"}}, fromThisPage, http.StatusBadRequest},
	} { // end of the cases
		// Send it.
		if res := post(t, rig.h, "/watch", tc.form, tc.headers); res.StatusCode != tc.want || len(res.Cookies()) != 0 {
			// Report it.
			t.Errorf("%s: %d (cookies %d), want %d without cookies", name, res.StatusCode, len(res.Cookies()), tc.want)
		} // end of the check
	} // end of the loop
	// A GET is not a route.
	if status, _, _ := get(t, rig.h, http.MethodGet, "/watch"); status != http.StatusMethodNotAllowed && status != http.StatusNotFound {
		// Report it.
		t.Errorf("GET /watch = %d", status)
	} // end of the GET check
} // end of TestWatchPauseResume

// TestStopTwoSteps checks that the first step only asks, the second stops once, and the form rules hold.
func TestStopTwoSteps(t *testing.T) {
	// A recorder for the shutdown.
	stops := stopRecorder(t)
	// A fake and a rig.
	rig, _ := perfRig(t, newPerfFake())
	// The question.
	res := post(t, rig.h, "/stop", url.Values{"token": {rig.token}}, fromThisPage)
	// Its text.
	ask := bodyOf(res)
	// The parts.
	for _, w := range []string{"Stop the monitor?", "Ollama and its models are not touched", `action="/stop/confirm"`, "No, keep it running"} {
		// Look for it.
		if !strings.Contains(ask, w) {
			// Report the gap.
			t.Errorf("the question lacks %q", w)
		} // end of the check
	} // end of the loop
	// Nothing is running, so there is no warning.
	if strings.Contains(ask, "Something is running") {
		// Report it.
		t.Errorf("a warning without any work")
	} // end of the warning check
	// Asking changes nothing.
	time.Sleep(400 * time.Millisecond)
	// No stop yet.
	if stops.Load() != 0 {
		// Report it.
		t.Fatalf("the question stopped the monitor")
	} // end of the ask check
	// The rules for both steps: a wrong token and another site are refused, and nothing stops.
	for _, path := range []string{"/stop", "/stop/confirm"} {
		// A wrong token.
		if res := post(t, rig.h, path, url.Values{"token": {"0123456789abcdef0123456789abcdef"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
			// Report it.
			t.Errorf("%s wrong token = %d", path, res.StatusCode)
		} // end of the token check
		// Another site.
		if res := post(t, rig.h, path, url.Values{"token": {rig.token}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
			// Report it.
			t.Errorf("%s cross-site = %d", path, res.StatusCode)
		} // end of the origin check
		// No headers at all (a script, not a page).
		if res := post(t, rig.h, path, url.Values{"token": {rig.token}}, nil); res.StatusCode != http.StatusForbidden {
			// Report it.
			t.Errorf("%s without origin = %d", path, res.StatusCode)
		} // end of the header check
		// A plain GET is not a route.
		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed && status != http.StatusNotFound {
			// Report it.
			t.Errorf("GET %s = %d", path, status)
		} // end of the GET check
	} // end of the loop
	// Wait a moment: still nothing stopped.
	time.Sleep(400 * time.Millisecond)
	// Check.
	if stops.Load() != 0 {
		// Report it.
		t.Fatalf("a refused request stopped the monitor")
	} // end of the refusal check
	// The real stop: the last page comes back at once.
	res = post(t, rig.h, "/stop/confirm", url.Values{"token": {rig.token}}, fromThisPage)
	// Its text.
	last := bodyOf(res)
	// The last page.
	if res.StatusCode != http.StatusOK || !strings.Contains(last, "The monitor has stopped") || strings.Contains(last, `http-equiv="refresh"`) {
		// Report it.
		t.Errorf("last page wrong: %d", res.StatusCode)
	} // end of the last page check
	// The stop follows in the background; pressing the button again does not stop twice.
	post(t, rig.h, "/stop/confirm", url.Values{"token": {rig.token}}, fromThisPage)
	// Wait for it, at most 3 seconds.
	for i := 0; i < 30 && stops.Load() == 0; i++ {
		// A short wait.
		time.Sleep(100 * time.Millisecond)
	} // end of the wait loop
	// Give a second press time to show up if it were going to.
	time.Sleep(500 * time.Millisecond)
	// Exactly one stop.
	if n := stops.Load(); n != 1 {
		// Report it.
		t.Errorf("stop requested %d times, want 1", n)
	} // end of the count check
} // end of TestStopTwoSteps

// TestWorkTracker checks the list of running work and that the clean-ups run.
func TestWorkTracker(t *testing.T) {
	// A tracker of its own.
	w := &workTracker{items: map[int]workItem{}}
	// Nothing at first.
	if len(w.texts()) != 0 {
		// Report it.
		t.Fatalf("a new tracker has work")
	} // end of the empty check
	// How many clean-ups ran.
	var ran atomic.Int32
	// Two pieces of work, one with a clean-up.
	endA := w.begin("first", func(ctx context.Context) { ran.Add(1) })
	// The second has none.
	endB := w.begin("second", nil)
	// Both are listed, oldest first.
	if got := strings.Join(w.texts(), ","); got != "first,second" {
		// Report it.
		t.Errorf("texts = %q", got)
	} // end of the list check
	// The clean-ups run for the work that has one.
	w.runCleanups(context.Background())
	// Once.
	if ran.Load() != 1 {
		// Report it.
		t.Errorf("clean-ups ran %d times, want 1", ran.Load())
	} // end of the clean-up check
	// Ending the first leaves the second.
	endA()
	// Check.
	if got := strings.Join(w.texts(), ","); got != "second" {
		// Report it.
		t.Errorf("after the first ended: %q", got)
	} // end of the end check
	// Ending twice is harmless.
	endA()
	// Ending the second empties the list.
	endB()
	// Check.
	if len(w.texts()) != 0 {
		// Report it.
		t.Errorf("work left after both ended")
	} // end of the empty check
} // end of TestWorkTracker

// TestStopWhileTestRuns checks the warning on the question page, and that stopping unloads the model that the running test loaded.
func TestStopWhileTestRuns(t *testing.T) {
	// A recorder for the shutdown.
	stops := stopRecorder(t)
	// A fake that holds the first test request.
	f := newPerfFake()
	// Hold it.
	f.hold, f.entered, f.release = true, make(chan struct{}, 1), make(chan struct{})
	// Build the rig.
	rig, _ := perfRig(t, f)
	// The test in the background.
	done := make(chan struct{})
	// Start it.
	go func() {
		// Run.
		perfPost(t, rig, "/performance/run", "chat:1b")
		// Report.
		close(done)
	}() // end of the goroutine
	// Wait until the test is inside the model request.
	<-f.entered
	// The question names the running test.
	ask := bodyOf(post(t, rig.h, "/stop", url.Values{"token": {rig.token}}, fromThisPage))
	// The warning.
	for _, w := range []string{"Something is running right now", "a performance test of chat:1b", "Stop cancels it and unloads the model first"} {
		// Look for it.
		if !strings.Contains(ask, w) {
			// Report the gap.
			t.Errorf("the question lacks %q", w)
		} // end of the check
	} // end of the loop
	// Before the stop, nothing was unloaded by it.
	before := f.unloadCount()
	// Stop for real.
	post(t, rig.h, "/stop/confirm", url.Values{"token": {rig.token}}, fromThisPage)
	// Wait for the stop, at most 3 seconds.
	for i := 0; i < 30 && stops.Load() == 0; i++ {
		// A short wait.
		time.Sleep(100 * time.Millisecond)
	} // end of the wait loop
	// The stop was requested, and the model was asked to unload first.
	if stops.Load() != 1 || f.unloadCount() <= before {
		// Report it.
		t.Errorf("stops %d, unloads %d (before %d)", stops.Load(), f.unloadCount(), before)
	} // end of the stop check
	// Let the held test finish so the test ends cleanly.
	close(f.release)
	// Wait for it.
	<-done
} // end of TestStopWhileTestRuns

// TestControlIconsAndZone checks that the controls use drawn icons (never emoji characters, which each computer paints in its own colours) and that the page time carries its timezone.
func TestControlIconsAndZone(t *testing.T) {
	// A fake and a rig.
	rig, _ := perfRig(t, newPerfFake())
	// Both versions of the page: watching and paused.
	for name, c := range map[string]*http.Cookie{"watching": nil, "paused": {Name: watchCookieName, Value: "paused"}} {
		// The page.
		page := pageWithCookie(t, rig, c)
		// Characters that some systems paint as colour emoji.
		for _, bad := range []string{"⏸", "⏹", "↻"} {
			// None may appear.
			if strings.Contains(page, bad) {
				// Report it.
				t.Errorf("%s page contains the emoji-like character %q", name, bad)
			} // end of the character check
		} // end of the loop
		// The icons are drawn instead: at least the status line and three buttons.
		if n := strings.Count(page, `<svg class="ico"`); n < 4 {
			// Report it.
			t.Errorf("%s page has %d icons, want at least 4", name, n)
		} // end of the icon check
		// The time ends with a timezone name or offset, for example "14:28:17 CET".
		i := strings.Index(page, "Page made at ")
		// It must be there.
		if i < 0 {
			// Report it.
			t.Fatalf("%s page has no time line", name)
		} // end of the presence check
		// The sentence up to its full stop.
		line := page[i : i+strings.Index(page[i:], ".")]
		// Three parts: the words, the clock and the zone.
		if f := strings.Fields(line); len(f) != 5 || len(f[3]) != 8 || f[4] == "" {
			// Report it.
			t.Errorf("%s time line has no timezone: %q", name, line)
		} // end of the zone check
	} // end of the loop
} // end of TestControlIconsAndZone

// TestKeyAndDrawnIcons checks the key above the models table and that the table icons are drawn, not emoji characters.
func TestKeyAndDrawnIcons(t *testing.T) {
	// A fake and a rig.
	rig, _ := perfRig(t, newPerfFake())
	// The main page.
	_, _, body := get(t, rig.h, http.MethodGet, "/")
	// None of the old emoji-like characters may remain on the page.
	for _, bad := range []string{"📄", "⚙", "📈", "⚖"} {
		// Look for it.
		if strings.Contains(body, bad) {
			// Report it.
			t.Errorf("the page still contains %q", bad)
		} // end of the character check
	} // end of the loop
	// The key names all six things.
	for _, want := range []string{"Modelfile</strong>", "Inference parameters</strong>", "Performance</strong>", "Compare tested models</strong>", "Dotted headings</strong>", "Sideways scroll</strong>", `class="legend muted"`} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("the key lacks %q", want)
		} // end of the check
	} // end of the loop
	// Six entries in the key.
	if n := strings.Count(body, `<li><span class="sym">`); n != 6 {
		// Report it.
		t.Errorf("the key has %d entries, want 6", n)
	} // end of the count check
	// The two reading hints come first in the key, then the four icon explanations.
	order := []string{"Dotted headings</strong>", "Sideways scroll</strong>", "Modelfile</strong>", "Inference parameters</strong>", "Performance</strong>", "Compare tested models</strong>"}
	// Walk the list and make sure each entry comes after the one before.
	last := -1
	// Each entry.
	for _, o := range order {
		// Where it is.
		at := strings.Index(body, o)
		// It must come after the previous one.
		if at <= last {
			// Report it.
			t.Errorf("the key entry %q is out of order", o)
		} // end of the order check
		// Remember the place.
		last = at
	} // end of the loop
	// The compare button has the bigger drawn scale.
	if !strings.Contains(body, `<svg class="ico ico-big"`) {
		// Report it.
		t.Errorf("the compare button has no big drawn icon")
	} // end of the compare check
	// The three row icons (modelfile, parameters, performance) are drawn buttons of the table.
	if n := strings.Count(body, `class="gear" aria-label=`); n < 3 {
		// Report it.
		t.Errorf("only %d icon buttons in the table", n)
	} // end of the row check
} // end of TestKeyAndDrawnIcons
