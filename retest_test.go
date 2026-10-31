// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// fmt builds names and texts.
	"fmt"
	// net/http provides the method names and status codes.
	"net/http"
	// net/url builds the forms.
	"net/url"
	// strings searches the pages.
	"strings"
	// testing is Go's test framework.
	"testing"
	// time sets the waiting limit.
	"time"
) // end of imports

// retestForm builds the form the button of a group sends.
func retestForm(rig themeRig, title string, models ...string) url.Values {
	// The token, the title and one field for each model.
	return url.Values{"token": {rig.token}, "title": {title}, "model": models}
} // end of retestForm

// waitForEnd polls the progress page until the re-test has ended, and returns that page.
func waitForEnd(t *testing.T, rig themeRig) string {
	// Mark this as a helper.
	t.Helper()
	// Give it ten seconds; the fake answers at once.
	deadline := time.Now().Add(10 * time.Second)
	// Ask again and again.
	for time.Now().Before(deadline) {
		// The page.
		_, _, body := get(t, rig.h, http.MethodGet, "/compare/retest/status")
		// It has ended.
		if strings.Contains(body, "has ended") {
			// Hand it back.
			return body
		} // end of the end check
		// A short pause.
		time.Sleep(20 * time.Millisecond)
	} // end of the loop
	// Never ended.
	t.Fatalf("the re-test did not end in time")
	// Not reached.
	return ""
} // end of waitForEnd

// TestCompareShowsTheRetestButton checks the button appears for a group of two or more models still installed, carries their names, and not for a group of one.
func TestCompareShowsTheRetestButton(t *testing.T) {
	// A fake and a rig.
	f := newPerfFake()
	// Build the rig.
	rig, _ := perfRig(t, f)
	// Test three models so the page has a group of two and a group of one.
	for _, m := range []string{"chat:1b", "think:1b", "embed:1b"} {
		// Run one test.
		if status, body, _ := perfPost(t, rig, "/performance/run", m); status != http.StatusOK {
			// Stop the test.
			t.Fatalf("test of %s: status %d %s", m, status, body)
		} // end of the status check
	} // end of the loop
	// The comparison page.
	res := post(t, rig.h, "/compare", url.Values{"token": {rig.token}}, fromThisPage)
	// Its text.
	body := bodyOf(res)
	// The two chat models share a group, so there is one button, for two models.
	if n := strings.Count(body, `action="/compare/retest"`); n != 1 {
		// Report the problem.
		t.Fatalf("%d re-test buttons, want 1", n)
	} // end of the count check
	// What the button must carry.
	for _, want := range []string{"Re-test this group (2 models)", `name="model" value="chat:1b"`, `name="model" value="think:1b"`, `name="token" value="` + rig.token + `"`} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("the compare page lacks %q", want)
		} // end of the check
	} // end of the loop
	// The lone embedding model gets no button.
	if strings.Contains(body, `name="model" value="embed:1b"`) {
		// Report the problem.
		t.Errorf("a group of one has a re-test button")
	} // end of the single check
	// The page still runs no script.
	if strings.Contains(body, "<script") {
		// Report the problem.
		t.Errorf("the compare page has a script")
	} // end of the script check
} // end of TestCompareShowsTheRetestButton

// TestRetestAskListsWhatWillHappen checks the confirmation page: it changes nothing, lists every model, and says why a loaded or missing model is left out.
func TestRetestAskListsWhatWillHappen(t *testing.T) {
	// A fake with one model already loaded.
	f := newPerfFake()
	// think:1b is in memory now.
	f.loaded["think:1b"] = true
	// Build the rig.
	rig, hist := perfRig(t, f)
	// Ask about three models, one of which is not installed.
	res := post(t, rig.h, "/compare/retest", retestForm(rig, `Chat <b>group</b>`, "chat:1b", "think:1b", "gone:1b"), fromThisPage)
	// Its text.
	body := bodyOf(res)
	// The page was shown.
	if res.StatusCode != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d: %s", res.StatusCode, body)
	} // end of the status check
	// What it must say.
	for _, want := range []string{"Re-test the group", "Yes, re-test 1 model</button>", "No: loaded in memory now", "No: no longer installed", `action="/compare/retest/run"`, `name="model" value="chat:1b"`, "Cancel, do not test", fmt.Sprintf("%d-hour limit", cmpSameSittingHours)} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("the page lacks %q", want)
		} // end of the check
	} // end of the loop
	// Only the model that will be tested is passed on.
	if strings.Contains(body, `name="model" value="think:1b"`) || strings.Contains(body, `name="model" value="gone:1b"`) {
		// Report the problem.
		t.Errorf("a model that will not be tested is passed on")
	} // end of the pass-on check
	// The title is shown escaped.
	if strings.Contains(body, "<b>group</b>") {
		// Report the problem.
		t.Errorf("the title was not escaped")
	} // end of the escape check
	// Nothing was tested and nothing saved.
	if f.calls() != 0 || len(savedRuns(t, hist)) != 0 {
		// Report the problem.
		t.Errorf("the confirmation page changed something")
	} // end of the change check
	// Only unusable models: a page that says so, without the button.
	res = post(t, rig.h, "/compare/retest", retestForm(rig, "x", "think:1b", "gone:1b"), fromThisPage)
	// Its text.
	body = bodyOf(res)
	// The notes.
	if !strings.Contains(body, "Nothing to re-test") || strings.Contains(body, `action="/compare/retest/run"`) {
		// Report the problem.
		t.Errorf("an empty re-test offers to start: %s", body)
	} // end of the empty check
} // end of TestRetestAskListsWhatWillHappen

// TestRetestRunsEveryModelAndSaves checks the whole run: the redirect, the progress page, one new saved result for each model, nothing of the answers on a page, and a finished page without refresh.
func TestRetestRunsEveryModelAndSaves(t *testing.T) {
	// A fake.
	f := newPerfFake()
	// Build the rig.
	rig, hist := perfRig(t, f)
	// Start the re-test of two models.
	res := post(t, rig.h, "/compare/retest/run", retestForm(rig, "Chat", "chat:1b", "think:1b"), fromThisPage)
	// The browser is sent to the progress page.
	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/compare/retest/status" {
		// Stop the test.
		t.Fatalf("start: status %d, location %q", res.StatusCode, res.Header.Get("Location"))
	} // end of the redirect check
	// Wait for the end.
	body := waitForEnd(t, rig)
	// Both were tested.
	if n := strings.Count(body, "Tested"); n < 2 || !strings.Contains(body, "2 tested, 0 failed, 0 skipped, 0 not started because you stopped, 0 still to do.") {
		// Report the problem.
		t.Errorf("the finished page is wrong: %s", body)
	} // end of the result check
	// The finished page does not refresh itself and offers the comparison.
	if strings.Contains(body, `http-equiv="refresh"`) || !strings.Contains(body, `action="/compare"`) || strings.Contains(body, "Stop after this model") {
		// Report the problem.
		t.Errorf("the finished page has the wrong controls")
	} // end of the controls check
	// Two results were saved, one for each model.
	runs := savedRuns(t, hist)
	// Count them.
	if len(runs) != 2 {
		// Stop the test.
		t.Fatalf("%d saved runs, want 2", len(runs))
	} // end of the saved check
	// They carry the answer length, which is the point of the re-test.
	for _, r := range runs {
		// A character count must be there.
		if r.AnswerChars == 0 {
			// Report the problem.
			t.Errorf("%s has no answer length", r.Model)
		} // end of the count check
	} // end of the loop
	// No answer text anywhere.
	if strings.Contains(body, secretText) {
		// Report the problem.
		t.Errorf("answer text reached the page")
	} // end of the secret check
	// No model is left in memory.
	if f.isLoaded("chat:1b") || f.isLoaded("think:1b") {
		// Report the problem.
		t.Errorf("a model was left loaded")
	} // end of the loaded check
	// The page runs no script.
	if strings.Contains(body, "<script") {
		// Report the problem.
		t.Errorf("the progress page has a script")
	} // end of the script check
} // end of TestRetestRunsEveryModelAndSaves

// TestRetestStopAfterThisModel checks the stop button: the model being tested finishes, the next one is not started, and the page says so.
func TestRetestStopAfterThisModel(t *testing.T) {
	// A fake that holds the first test request.
	f := newPerfFake()
	// Hold it.
	f.hold, f.entered, f.release = true, make(chan struct{}, 1), make(chan struct{})
	// Build the rig.
	rig, hist := perfRig(t, f)
	// Start the re-test of two models.
	post(t, rig.h, "/compare/retest/run", retestForm(rig, "Chat", "chat:1b", "think:1b"), fromThisPage)
	// Wait until the first model is inside the request.
	<-f.entered
	// The progress page while it runs.
	_, _, running := get(t, rig.h, http.MethodGet, "/compare/retest/status")
	// It refreshes itself, shows the stop button and the state of the models.
	for _, want := range []string{`http-equiv="refresh" content="5"`, "Stop after this model", "Testing now", "Waiting", "Re-testing the group"} {
		// Look for it.
		if !strings.Contains(running, want) {
			// Report the gap.
			t.Errorf("the running page lacks %q", want)
		} // end of the check
	} // end of the loop
	// A second start while one runs does not begin another job.
	again := post(t, rig.h, "/compare/retest/run", retestForm(rig, "Chat", "chat:1b", "think:1b"), fromThisPage)
	// It is sent to the running job.
	if again.StatusCode != http.StatusSeeOther {
		// Report the problem.
		t.Errorf("second start: status %d", again.StatusCode)
	} // end of the second start check
	// Ask to stop.
	stop := post(t, rig.h, "/compare/retest/stop", url.Values{"token": {rig.token}}, fromThisPage)
	// Back to the progress page.
	if stop.StatusCode != http.StatusSeeOther {
		// Report the problem.
		t.Errorf("stop: status %d", stop.StatusCode)
	} // end of the stop check
	// The page now says so, and the stop button is gone.
	_, _, asked := get(t, rig.h, http.MethodGet, "/compare/retest/status")
	// Check it.
	if !strings.Contains(asked, "You asked to stop") || strings.Contains(asked, "Stop after this model") {
		// Report the problem.
		t.Errorf("the page after the stop request is wrong")
	} // end of the asked check
	// Let the first model finish.
	close(f.release)
	// Wait for the end.
	body := waitForEnd(t, rig)
	// One tested, one not started.
	if !strings.Contains(body, "1 tested, 0 failed, 0 skipped, 1 not started because you stopped, 0 still to do.") || !strings.Contains(body, "Not started (you stopped)") {
		// Report the problem.
		t.Errorf("the ended page is wrong: %s", body)
	} // end of the result check
	// Only one result was saved.
	if n := len(savedRuns(t, hist)); n != 1 {
		// Report the problem.
		t.Errorf("%d saved runs, want 1", n)
	} // end of the saved check
} // end of TestRetestStopAfterThisModel

// TestRetestOneFailureDoesNotStopTheRest checks a failing test is reported on its row and the others go on.
func TestRetestOneFailureDoesNotStopTheRest(t *testing.T) {
	// A fake whose first test request fails.
	f := newPerfFake()
	// The first request fails.
	f.failAt = 1
	// Build the rig.
	rig, hist := perfRig(t, f)
	// Start the re-test of two models.
	post(t, rig.h, "/compare/retest/run", retestForm(rig, "Chat", "chat:1b", "think:1b"), fromThisPage)
	// Wait for the end.
	body := waitForEnd(t, rig)
	// One failed, one tested.
	if !strings.Contains(body, "1 tested, 1 failed, 0 skipped, 0 not started because you stopped, 0 still to do.") {
		// Report the problem.
		t.Errorf("the ended page is wrong: %s", body)
	} // end of the result check
	// Only the good one was saved.
	if n := len(savedRuns(t, hist)); n != 1 {
		// Report the problem.
		t.Errorf("%d saved runs, want 1", n)
	} // end of the saved check
} // end of TestRetestOneFailureDoesNotStopTheRest

// TestRetestFormsAreChecked checks the new forms refuse a wrong token, a form from another site, no models, too many models, a bad name and an over-long title; and that the progress page needs no form.
func TestRetestFormsAreChecked(t *testing.T) {
	// A fake and a rig.
	f := newPerfFake()
	// Build the rig.
	rig, hist := perfRig(t, f)
	// Many names.
	many := make([]string, maxRetestModels+1)
	// Fill them.
	for i := range many {
		// A name.
		many[i] = fmt.Sprintf("m%d:1b", i)
	} // end of the loop
	// The cases.
	cases := map[string]struct {
		form    url.Values
		headers map[string]string
		want    int
	}{
		// A wrong token.
		"wrong token": {url.Values{"token": {"0123456789abcdef0123456789abcdef"}, "model": {"chat:1b"}}, fromThisPage, http.StatusForbidden},
		// Another site.
		"other site": {retestForm(rig, "x", "chat:1b"), map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
		// No model.
		"no model": {retestForm(rig, "x"), fromThisPage, http.StatusBadRequest},
		// An empty name.
		"empty name": {retestForm(rig, "x", ""), fromThisPage, http.StatusBadRequest},
		// A very long name.
		"long name": {retestForm(rig, "x", strings.Repeat("a", maxModelNameLen+1)), fromThisPage, http.StatusBadRequest},
		// A very long title.
		"long title": {retestForm(rig, strings.Repeat("t", maxRetestTitle+1), "chat:1b"), fromThisPage, http.StatusBadRequest},
		// Too many models.
		"too many": {retestForm(rig, "x", many...), fromThisPage, http.StatusBadRequest},
	} // end of the cases
	// Both POST routes that take models.
	for _, path := range []string{"/compare/retest", "/compare/retest/run"} {
		// Each case.
		for name, c := range cases {
			// Send it.
			res := post(t, rig.h, path, c.form, c.headers)
			// The answer.
			if res.StatusCode != c.want {
				// Report the problem.
				t.Errorf("%s %s: status %d, want %d", path, name, res.StatusCode, c.want)
			} // end of the status check
		} // end of the case loop
	} // end of the path loop
	// The stop route checks token and origin too.
	if res := post(t, rig.h, "/compare/retest/stop", url.Values{"token": {"0123456789abcdef0123456789abcdef"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
		// Report the problem.
		t.Errorf("stop with a wrong token: status %d", res.StatusCode)
	} // end of the stop token check
	// A page asked for with GET cannot start or stop anything.
	for _, path := range []string{"/compare/retest", "/compare/retest/run", "/compare/retest/stop"} {
		// Ask.
		status, _, _ := get(t, rig.h, http.MethodGet, path)
		// Only the progress route answers GET.
		if status == http.StatusOK {
			// Report the problem.
			t.Errorf("GET %s answered 200", path)
		} // end of the status check
	} // end of the loop
	// Nothing was tested by any refused request.
	if f.calls() != 0 || len(savedRuns(t, hist)) != 0 {
		// Report the problem.
		t.Errorf("a refused request changed something")
	} // end of the change check
	// The progress page with no job says so.
	_, _, none := get(t, rig.h, http.MethodGet, "/compare/retest/status")
	// Check it.
	if !strings.Contains(none, "No re-test has been started") {
		// Report the problem.
		t.Errorf("the empty progress page is wrong: %s", none)
	} // end of the none check
} // end of TestRetestFormsAreChecked

// TestRetestSkipsAModelLoadedMeanwhile checks the loaded check is made again just before each model: a model that someone loaded after the question was answered is left alone.
func TestRetestSkipsAModelLoadedMeanwhile(t *testing.T) {
	// A fake that holds the first test request.
	f := newPerfFake()
	// Hold it.
	f.hold, f.entered, f.release = true, make(chan struct{}, 1), make(chan struct{})
	// Build the rig.
	rig, hist := perfRig(t, f)
	// Start the re-test of two models; both are free now.
	post(t, rig.h, "/compare/retest/run", retestForm(rig, "Chat", "chat:1b", "think:1b"), fromThisPage)
	// Wait until the first model is inside the request.
	<-f.entered
	// Someone loads the second model meanwhile.
	f.mu.Lock()
	// It is in memory.
	f.loaded["think:1b"] = true
	// Release the fake.
	f.mu.Unlock()
	// Let the first model finish.
	close(f.release)
	// Wait for the end.
	body := waitForEnd(t, rig)
	// The second was skipped, with the reason.
	if !strings.Contains(body, "1 tested, 0 failed, 1 skipped, 0 not started because you stopped, 0 still to do.") || !strings.Contains(body, "loaded in memory now") {
		// Report the problem.
		t.Errorf("the ended page is wrong: %s", body)
	} // end of the result check
	// Only the first was saved, and the loaded model was left in memory.
	if n := len(savedRuns(t, hist)); n != 1 || !f.isLoaded("think:1b") {
		// Report the problem.
		t.Errorf("%d saved runs, think loaded %v", n, f.isLoaded("think:1b"))
	} // end of the saved check
} // end of TestRetestSkipsAModelLoadedMeanwhile

// TestRetestWaitsForASingleTest checks the group re-test never runs at the same time as a single test the person started by hand.
func TestRetestWaitsForASingleTest(t *testing.T) {
	// A fake that holds the first test request.
	f := newPerfFake()
	// Hold it.
	f.hold, f.entered, f.release = true, make(chan struct{}, 1), make(chan struct{})
	// Build the rig.
	rig, hist := perfRig(t, f)
	// The single test runs in the background.
	done := make(chan struct{})
	// Start it.
	go func() {
		// Run.
		perfPost(t, rig, "/performance/run", "chat:1b")
		// Report.
		close(done)
	}() // end of the goroutine
	// Wait until it is inside the model request.
	<-f.entered
	// Start the group re-test of the other model.
	post(t, rig.h, "/compare/retest/run", retestForm(rig, "Chat", "think:1b"), fromThisPage)
	// Give the job time to do something wrong.
	time.Sleep(150 * time.Millisecond)
	// It must be waiting, and must not have sent a request of its own.
	_, _, waiting := get(t, rig.h, http.MethodGet, "/compare/retest/status")
	// Check it.
	if !strings.Contains(waiting, "Waiting") || strings.Contains(waiting, "Testing now") || f.calls() != 1 {
		// Report the problem.
		t.Errorf("the re-test did not wait (calls %d): %s", f.calls(), waiting)
	} // end of the waiting check
	// Let the single test finish.
	close(f.release)
	// Wait for it.
	<-done
	// The re-test then runs.
	body := waitForEnd(t, rig)
	// Both results are saved.
	if !strings.Contains(body, "1 tested") || len(savedRuns(t, hist)) != 2 {
		// Report the problem.
		t.Errorf("the re-test did not finish after the single test: %s", body)
	} // end of the result check
} // end of TestRetestWaitsForASingleTest
