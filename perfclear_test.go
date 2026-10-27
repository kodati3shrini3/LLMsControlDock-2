// Package main tells Go that this test file belongs to the same program as perfclear.go.
package main

import ( // import lists the packages this test file uses.
	// encoding/json reads the safety copy.
	"encoding/json"
	// net/http provides status codes.
	"net/http"
	// net/url builds form data.
	"net/url"
	// os reads the folder and the files.
	"os"
	// path/filepath builds paths.
	"path/filepath"
	// regexp checks that dates name their zone.
	"regexp"
	// strings searches text.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
	// time builds run times.
	"time"
) // end of imports

// clearRig holds the handlers of the clearing pages with a store and a history folder of this test.
type clearRig struct {
	// ask is the first step of clearing everything.
	ask http.HandlerFunc
	// do is the second step of clearing everything.
	do http.HandlerFunc
	// oneAsk is the first step of clearing one model.
	oneAsk http.HandlerFunc
	// oneDo is the second step of clearing one model.
	oneDo http.HandlerFunc
	// store holds the saved runs.
	store *perfStore
	// hist is the history folder that receives the safety copies.
	hist *historyStore
	// token is the page token the forms carry.
	token string
} // end of clearRig

// newClearRig seeds three runs of alpha:1b and two of beta:1b, and builds the handlers.
func newClearRig(t *testing.T, hist *historyStore) clearRig {
	// Mark this as a helper.
	t.Helper()
	// Show times in UTC, so the zone name in the text is predictable.
	old := time.Local
	// Put it back at the end.
	t.Cleanup(func() { time.Local = old })
	// UTC.
	time.Local = time.UTC
	// The store writes into a file of this test.
	store := &perfStore{path: filepath.Join(t.TempDir(), "performance.json")}
	// A base time.
	base := time.Date(2026, 10, 24, 21, 10, 0, 0, time.UTC)
	// Three runs of alpha, the newest at 212 tokens per second.
	for i, speed := range []float64{150, 180, 212} {
		// Add it.
		store.runs = append(store.runs, perfRun{Time: base.Add(time.Duration(i) * 24 * time.Hour), Model: "alpha:1b", Kind: "generate", PromptVersion: perfPromptVersion, AnswerSpeed: speed})
	} // end of the alpha loop
	// Two runs of beta.
	for i, speed := range []float64{90, 96} {
		// Add it.
		store.runs = append(store.runs, perfRun{Time: base.Add(time.Duration(i) * 48 * time.Hour), Model: "beta:1b", Kind: "generate", PromptVersion: perfPromptVersion, AnswerSpeed: speed})
	} // end of the beta loop
	// The handlers; the Ollama address is not used by the clearing pages.
	a, d, oa, od := func() (http.HandlerFunc, http.HandlerFunc, http.HandlerFunc, http.HandlerFunc) {
		// Build the six and keep the four that clear.
		_, _, ask, do, oneAsk, oneDo := perfHandlers(ollamaAddress{}, strings.Repeat("a", 32), store, hist)
		// Hand back.
		return ask, do, oneAsk, oneDo
	}() // end of the call
	// The rig.
	return clearRig{ask: a, do: d, oneAsk: oa, oneDo: od, store: store, hist: hist, token: strings.Repeat("a", 32)}
} // end of newClearRig

// send posts the form of the clearing pages to one handler and returns the status and the page text.
func (c clearRig) send(t *testing.T, h http.HandlerFunc, model string) (int, string) {
	// Mark this as a helper.
	t.Helper()
	// The form, as the page's own form would send it.
	res := post(t, h, "/x", url.Values{"token": {c.token}, "model": {model}}, fromThisPage)
	// The status and the text.
	return res.StatusCode, bodyOf(res)
} // end of send

// TestClearAskShowsTheImpact checks the first step shows every model with its dates and zone, and removes nothing.
func TestClearAskShowsTheImpact(t *testing.T) {
	// A rig with a history folder.
	c := newClearRig(t, &historyStore{dir: t.TempDir()})
	// Ask from the page of alpha.
	status, page := c.send(t, c.ask, "alpha:1b")
	// It must be a normal page.
	if status != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d", status)
	} // end of the status check
	// What must be there.
	for _, want := range []string{
		// The red box with the total.
		"permanently remove all 5 saved test results, for every model.",
		// Both models, this one marked.
		"<code>alpha:1b</code> <span class=\"muted\">(this model)</span>", "<code>beta:1b</code>",
		// Counts, dates with year and zone, and the newest speed.
		"<td>3</td>", "24 Oct 2026 21:10 UTC", "26 Oct 2026 21:10 UTC", "212.0 tokens/s", "96.0 tokens/s",
		// The consequences and what is safe.
		"becomes empty (now: 2 models)", "Not affected: the models themselves, their settings, and the delete history.",
		// The copy plan.
		"A copy of these results is saved first, in",
		// The three choices.
		"Cancel, keep them", "Remove only alpha:1b (3 results)", "Yes, remove all 5 results",
	} { // end of the list
		// Look for it.
		if !strings.Contains(page, want) {
			// Report the problem.
			t.Errorf("page does not contain %q", want)
		} // end of the check
	} // end of the loop
	// Nothing was removed.
	if c.store.count() != 5 {
		// Report the problem.
		t.Errorf("the question removed something: %d left", c.store.count())
	} // end of the count check
	// The model of this page comes first.
	if strings.Index(page, "<tr><td><code>alpha:1b</code>") > strings.Index(page, "<tr><td><code>beta:1b</code>") {
		// Report the problem.
		t.Errorf("this model is not listed first")
	} // end of the order check
	// From beta's page, beta comes first.
	_, fromBeta := c.send(t, c.ask, "beta:1b")
	// The order flips.
	if strings.Index(fromBeta, "<tr><td><code>beta:1b</code>") > strings.Index(fromBeta, "<tr><td><code>alpha:1b</code>") {
		// Report the problem.
		t.Errorf("the marked model is not listed first from beta's page")
	} // end of the flipped order check
	// The destructive buttons are the filled red ones, and the safe choice is not.
	if !strings.Contains(page, `class="btn-solid">Yes, remove all 5 results`) || !strings.Contains(page, `class="btn-load" href="/">Cancel, keep them`) {
		// Report the problem.
		t.Errorf("button styles are wrong")
	} // end of the style check
	// The same for one model.
	_, one := c.send(t, c.oneAsk, "alpha:1b")
	// The destructive button.
	if !strings.Contains(one, `class="btn-solid">Yes, remove these 3 results`) {
		// Report the problem.
		t.Errorf("the single-model button is not the red one")
	} // end of the single style check
} // end of TestClearAskShowsTheImpact

// TestEverySummaryDateNamesItsZone checks the dates in the table carry the year and a zone name.
func TestEverySummaryDateNamesItsZone(t *testing.T) {
	// A rig.
	c := newClearRig(t, &historyStore{dir: t.TempDir()})
	// A year, a clock time and a zone name.
	re := regexp.MustCompile(`^\d{1,2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2} [A-Z]{3,5}$`)
	// Check each line.
	for _, s := range c.store.summaries("", "") {
		// Both dates.
		for _, d := range []string{s.First, s.Latest} {
			// The shape.
			if !re.MatchString(d) {
				// Report the problem.
				t.Errorf("%s: date %q has no year or zone", s.Model, d)
			} // end of the shape check
		} // end of the dates loop
	} // end of the loop
} // end of TestEverySummaryDateNamesItsZone

// TestClearAllKeepsACopy checks the second step keeps a readable safety copy and then removes everything.
func TestClearAllKeepsACopy(t *testing.T) {
	// A history folder of this test.
	dir := t.TempDir()
	// A rig.
	c := newClearRig(t, &historyStore{dir: dir})
	// Confirm.
	_, page := c.send(t, c.do, "alpha:1b")
	// The wording.
	if !strings.Contains(page, "All saved test results were removed") || !strings.Contains(page, "A copy of the removed results was saved as") {
		// Report the problem.
		t.Errorf("done page is wrong: %s", page)
	} // end of the wording check
	// Everything is gone.
	if c.store.count() != 0 {
		// Report the problem.
		t.Errorf("%d runs left", c.store.count())
	} // end of the count check
	// One copy file.
	files, _ := filepath.Glob(filepath.Join(dir, "*_performance-results_all-models"+removedSuffix))
	// Exactly one.
	if len(files) != 1 {
		// Stop the test.
		t.Fatalf("%d copy files, want 1", len(files))
	} // end of the file count
	// Read it.
	data, err := os.ReadFile(files[0])
	// It must be readable.
	if err != nil {
		// Stop the test.
		t.Fatalf("cannot read the copy: %v", err)
	} // end of the read check
	// Decode it.
	var got removedResults
	// It must be valid.
	if err := json.Unmarshal(data, &got); err != nil || got.Scope != "all models" || len(got.Runs) != 5 || got.Version != snapshotVersion {
		// Report the problem.
		t.Errorf("copy is wrong: %v %+v", err, got)
	} // end of the content check
	// Only this user may read it.
	if st, _ := os.Stat(files[0]); st.Mode().Perm() != 0o600 {
		// Report the problem.
		t.Errorf("copy mode %v, want 0600", st.Mode().Perm())
	} // end of the mode check
	// The page names the full path.
	if !strings.Contains(page, files[0]) {
		// Report the problem.
		t.Errorf("the page does not name the copy's path")
	} // end of the path check
} // end of TestClearAllKeepsACopy

// TestClearOneKeepsTheOthers checks the single-model flow: it asks first with that model's row only, then removes only that model and keeps a copy of just those runs.
func TestClearOneKeepsTheOthers(t *testing.T) {
	// A history folder of this test.
	dir := t.TempDir()
	// A rig.
	c := newClearRig(t, &historyStore{dir: dir})
	// The question.
	_, ask := c.send(t, c.oneAsk, "alpha:1b")
	// What must be there, and what must not.
	for _, want := range []string{"permanently remove the 3 saved test results of <code>alpha:1b</code>", "The 2 results of other models stay.", "Yes, remove these 3 results", "<code>alpha:1b</code>"} {
		// Look for it.
		if !strings.Contains(ask, want) {
			// Report the problem.
			t.Errorf("question lacks %q", want)
		} // end of the check
	} // end of the loop
	// The other model must not be in the table.
	if strings.Contains(ask, "<code>beta:1b</code>") {
		// Report the problem.
		t.Errorf("the question lists another model")
	} // end of the other check
	// The question removed nothing.
	if c.store.count() != 5 {
		// Report the problem.
		t.Fatalf("the question removed something")
	} // end of the count check
	// Confirm.
	_, done := c.send(t, c.oneDo, "alpha:1b")
	// The wording.
	if !strings.Contains(done, "The 3 saved test results of <code>alpha:1b</code> were removed.") {
		// Report the problem.
		t.Errorf("done page is wrong: %s", done)
	} // end of the wording check
	// Only beta is left.
	if c.store.count() != 2 || c.store.countModel("beta:1b") != 2 || c.store.countModel("alpha:1b") != 0 {
		// Report the problem.
		t.Errorf("wrong runs left: %d", c.store.count())
	} // end of the left check
	// The change was saved to the file too.
	reopened := openPerfStore(c.store.path, "")
	// Two runs on disk.
	if reopened.count() != 2 {
		// Report the problem.
		t.Errorf("file holds %d runs, want 2", reopened.count())
	} // end of the file check
	// The copy holds only alpha's runs.
	files, _ := filepath.Glob(filepath.Join(dir, "*_performance-results_alpha-1b"+removedSuffix))
	// Exactly one.
	if len(files) != 1 {
		// Stop the test.
		t.Fatalf("%d copy files, want 1", len(files))
	} // end of the file count
	// Read it.
	data, _ := os.ReadFile(files[0])
	// Decode it.
	var got removedResults
	// It must be valid and hold three alpha runs.
	if err := json.Unmarshal(data, &got); err != nil || got.Scope != "alpha:1b" || len(got.Runs) != 3 {
		// Report the problem.
		t.Errorf("copy is wrong: %v %+v", err, got)
	} // end of the content check
} // end of TestClearOneKeepsTheOthers

// TestClearWithoutAHistoryFolderWarnsAndStillRemoves checks the person is told, before and after, that no copy exists.
func TestClearWithoutAHistoryFolderWarnsAndStillRemoves(t *testing.T) {
	// No folder, with a reason.
	c := newClearRig(t, &historyStore{note: "No folder for the history was found, so no snapshots are kept."})
	// The question warns.
	_, ask := c.send(t, c.ask, "alpha:1b")
	// The warning.
	if !strings.Contains(ask, "No copy can be kept.") || !strings.Contains(ask, "would be gone for good") {
		// Report the problem.
		t.Errorf("no warning before removal: %s", ask)
	} // end of the warning check
	// The confirmed removal still happens.
	_, done := c.send(t, c.do, "alpha:1b")
	// The page says no copy was kept.
	if !strings.Contains(done, "No copy was kept.") || c.store.count() != 0 {
		// Report the problem.
		t.Errorf("done page or removal wrong: %s", done)
	} // end of the done check
} // end of TestClearWithoutAHistoryFolderWarnsAndStillRemoves

// TestClearEdgeCases checks an empty store and a model without results.
func TestClearEdgeCases(t *testing.T) {
	// A rig.
	c := newClearRig(t, &historyStore{dir: t.TempDir()})
	// A model with nothing saved.
	_, none := c.send(t, c.oneAsk, "ghost:1b")
	// The plain words.
	if !strings.Contains(none, "There are no saved test results for <code>ghost:1b</code>.") {
		// Report the problem.
		t.Errorf("wrong page: %s", none)
	} // end of the none check
	// Empty the store.
	c.store.clear()
	// Ask to clear everything.
	_, empty := c.send(t, c.ask, "alpha:1b")
	// The plain words, and no destructive button.
	if !strings.Contains(empty, "There are no saved test results to remove.") || strings.Contains(empty, "btn-solid") {
		// Report the problem.
		t.Errorf("wrong page: %s", empty)
	} // end of the empty check
} // end of TestClearEdgeCases

// TestTwoCopiesInOneSecondDoNotOverwrite checks a second copy at the same moment gets a number.
func TestTwoCopiesInOneSecondDoNotOverwrite(t *testing.T) {
	// A folder.
	h := &historyStore{dir: t.TempDir()}
	// The same moment twice.
	at := time.Date(2026, 10, 27, 20, 0, 0, 0, time.UTC)
	// Save twice.
	a, errA := h.saveRemoved(removedResults{Version: snapshotVersion, RemovedAt: at, Scope: "all models"})
	// The second one.
	b, errB := h.saveRemoved(removedResults{Version: snapshotVersion, RemovedAt: at, Scope: "all models"})
	// Both must work and differ.
	if errA != nil || errB != nil || a == b {
		// Report the problem.
		t.Errorf("names %q and %q, errors %v %v", a, b, errA, errB)
	} // end of the check
	// The name carries the zone offset (Z for UTC).
	if !strings.Contains(a, "20-00-00Z_performance-results_all-models") {
		// Report the problem.
		t.Errorf("name %q lacks the zone", a)
	} // end of the zone check
} // end of TestTwoCopiesInOneSecondDoNotOverwrite

// TestRemovedCopiesAreNotParameterSnapshots checks the parameter history of a model never lists a results copy.
func TestRemovedCopiesAreNotParameterSnapshots(t *testing.T) {
	// A folder.
	h := &historyStore{dir: t.TempDir()}
	// A copy whose scope is the model's own name.
	if _, err := h.saveRemoved(removedResults{Version: snapshotVersion, RemovedAt: time.Now(), Scope: "alpha:1b"}); err != nil {
		// Stop the test.
		t.Fatalf("save: %v", err)
	} // end of the save check
	// The two kinds of file must end differently, so they can never be mixed up.
	if removedSuffix == snapshotSuffix || !strings.HasSuffix(removedSuffix, "_removed.json") {
		// Report the problem.
		t.Errorf("suffixes: %q and %q", removedSuffix, snapshotSuffix)
	} // end of the suffix check
	// The file name ends with the removal suffix.
	if files, _ := filepath.Glob(filepath.Join(h.dir, "*"+removedSuffix)); len(files) != 1 {
		// Report the problem.
		t.Errorf("%d files with the removal suffix, want 1", len(files))
	} // end of the file check
	// The parameter history must be empty.
	if got := h.list("alpha:1b"); len(got) != 0 {
		// Report the problem.
		t.Errorf("a results copy was listed as a snapshot: %+v", got)
	} // end of the list check
} // end of TestRemovedCopiesAreNotParameterSnapshots

// TestClearOneRoutesAreGuarded checks the two new routes refuse foreign, tokenless and wrong-method requests.
func TestClearOneRoutesAreGuarded(t *testing.T) {
	// Build the rig.
	rig := newThemeRig(t)
	// Both routes.
	for _, path := range []string{"/performance/clear/model", "/performance/clear/model/confirm"} {
		// Another site.
		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"a"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
			// Report the problem.
			t.Errorf("%s cross-site = %d, want 403", path, res.StatusCode)
		} // end of the origin check
		// No token.
		if res := post(t, rig.h, path, url.Values{"model": {"a"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
			// Report the problem.
			t.Errorf("%s without token = %d, want 403", path, res.StatusCode)
		} // end of the token check
		// No model name.
		if res := post(t, rig.h, path, url.Values{"token": {rig.token}}, fromThisPage); res.StatusCode != http.StatusBadRequest {
			// Report the problem.
			t.Errorf("%s without model = %d, want 400", path, res.StatusCode)
		} // end of the model check
		// A GET.
		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed {
			// Report the problem.
			t.Errorf("GET %s = %d, want 405", path, status)
		} // end of the method check
	} // end of the loop
} // end of TestClearOneRoutesAreGuarded
