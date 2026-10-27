#!/usr/bin/env bash
# Script 67: the termGate Consulting logo (a 15 KB miniature, embedded in the program) appears in the footer bar and the About card; the security policy now allows images from this program only.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/about-and-text-size" ] || { echo "FAIL  not on feature/about-and-text-size"; exit 1; }
# Scripts 61 to 63 must be part of this branch already (merged into main).
[ -e web/termgate-logo.png ] || { echo "FAIL  script 67 was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e perfclear.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/history.go b/history.go
index fd3c281..531721a 100644
--- a/history.go
+++ b/history.go
@@ -154,14 +154,20 @@ func (h *historyStore) save(s paramSnapshot) (string, error) {
 	} // end of the encode check
 	// The first part of the name: time with its time zone offset (Z for UTC, otherwise such as +0100), then the model.
 	base := s.DeletedAt.Format("2006-01-02_15-04-05Z0700") + "_" + safeFilePart(s.Model)
+	// Write it under a name that is never used twice.
+	return h.writeUnique("snapshot", base, snapshotSuffix, data)
+} // end of save
+
+// writeUnique writes one file into the history folder under base + suffix, adding a number when the name is taken; a file is never overwritten, and only this user can read it. The word says what is being saved, for the error texts.
+func (h *historyStore) writeUnique(what, base, suffix string, data []byte) (string, error) {
 	// Try the plain name, then numbered ones.
 	for n := 0; n < 100; n++ {
 		// The file name.
-		name := base + snapshotSuffix
+		name := base + suffix
 		// A number from the second try on.
 		if n > 0 {
 			// Add it.
-			name = fmt.Sprintf("%s-%d%s", base, n+1, snapshotSuffix)
+			name = fmt.Sprintf("%s-%d%s", base, n+1, suffix)
 		} // end of the number
 		// Create the file, failing when it exists, so nothing is ever overwritten; only this user may read it.
 		f, err := os.OpenFile(filepath.Join(h.dir, name), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
@@ -173,26 +179,59 @@ func (h *historyStore) save(s paramSnapshot) (string, error) {
 		// Another problem.
 		if err != nil {
 			// Fixed wording with the system reason.
-			return "", fmt.Errorf("the snapshot file could not be created: %w", err)
+			return "", fmt.Errorf("the %s file could not be created: %w", what, err)
 		} // end of the create check
 		// Write the bytes.
 		if _, err := f.Write(data); err != nil {
 			// Close before returning.
 			f.Close()
 			// Fixed wording.
-			return "", fmt.Errorf("the snapshot file could not be written: %w", err)
+			return "", fmt.Errorf("the %s file could not be written: %w", what, err)
 		} // end of the write check
 		// Close to flush.
 		if err := f.Close(); err != nil {
 			// Fixed wording.
-			return "", fmt.Errorf("the snapshot file could not be written: %w", err)
+			return "", fmt.Errorf("the %s file could not be written: %w", what, err)
 		} // end of the close check
 		// Saved.
 		return name, nil
 	} // end of the loop
-	// Too many snapshots in one second.
-	return "", errors.New("the snapshot file name was already taken")
-} // end of save
+	// Too many files in one second.
+	return "", fmt.Errorf("the %s file name was already taken", what)
+} // end of writeUnique
+
+// removedSuffix ends the name of every safety copy of removed performance results; it differs from snapshotSuffix, so the parameter history never lists these.
+const removedSuffix = "_removed.json"
+
+// saveRemoved writes the safety copy of performance results that are about to be removed and returns its file name.
+func (h *historyStore) saveRemoved(r removedResults) (string, error) {
+	// No folder: nothing can be saved.
+	if h.dir == "" {
+		// Say why.
+		if h.note != "" {
+			// The stored reason.
+			return "", errors.New(h.note)
+		} // end of the note check
+		// A fixed reason.
+		return "", errors.New("there is no history folder")
+	} // end of the folder check
+	// The folder, readable only by this user.
+	if err := os.MkdirAll(h.dir, 0o700); err != nil {
+		// Fixed wording with the system reason.
+		return "", fmt.Errorf("the history folder could not be created: %w", err)
+	} // end of the folder check
+	// Encode with indentation so the person can read the file.
+	data, err := json.MarshalIndent(r, "", "  ")
+	// A bug, not a user problem.
+	if err != nil {
+		// Fixed wording.
+		return "", fmt.Errorf("the copy could not be encoded: %w", err)
+	} // end of the encode check
+	// The name: time with its zone offset, then what was removed.
+	base := r.RemovedAt.Format("2006-01-02_15-04-05Z0700") + "_performance-results_" + safeFilePart(r.Scope)
+	// Write it under a name that is never used twice.
+	return h.writeUnique("copy", base, removedSuffix, data)
+} // end of saveRemoved
 
 // list returns the snapshots of one model, newest first; files that are not ours, damaged, too large or from another model are skipped.
 func (h *historyStore) list(model string) []paramSnapshot {
diff --git a/perf_test.go b/perf_test.go
index 1df2446..3494246 100644
--- a/perf_test.go
+++ b/perf_test.go
@@ -751,7 +751,7 @@ func TestPerfComparisonAndHistory(t *testing.T) {
 	// The first step of clearing only asks.
 	_, ask, _ := perfPost(t, rig, "/performance/clear", "chat:1b")
 	// The question names the number.
-	if !strings.Contains(ask, "removes all 2 saved test results") || len(savedRuns(t, hist)) != 2 {
+	if !strings.Contains(ask, "permanently remove all 2 saved test results") || len(savedRuns(t, hist)) != 2 {
 		// Report the problem.
 		t.Errorf("the clear question removed something or is wrong")
 	} // end of the ask check
diff --git a/perfclear.go b/perfclear.go
new file mode 100644
index 0000000..2a2f067
--- /dev/null
+++ b/perfclear.go
@@ -0,0 +1,261 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// fmt builds the speed text.
+	"fmt"
+	// path/filepath joins the history folder and the file name.
+	"path/filepath"
+	// sort keeps the rows in a steady order.
+	"sort"
+	// time stamps the copy of removed results.
+	"time"
+) // end of imports
+
+// perfSummary is one line of the "what you lose" table: what is saved for one model.
+type perfSummary struct {
+	// Model is the model name.
+	Model string
+	// Tests is how many saved test results the model has.
+	Tests int
+	// First is the time of the oldest test, with the year and the time zone.
+	First string
+	// Latest is the time of the newest test, with the year and the time zone.
+	Latest string
+	// Speed is the newest test's speed in words.
+	Speed string
+	// This is true for the model whose page the person came from.
+	This bool
+} // end of perfSummary
+
+// perfTimeText shows a test time in the computer's own time zone, with the year and the zone name.
+func perfTimeText(t time.Time) string {
+	// Local time, day, month, year, clock, zone.
+	return t.Local().Format("2 Jan 2006 15:04 MST")
+} // end of perfTimeText
+
+// perfSpeedText says in words how fast a run was: tokens per second for a chat model, the embedding time for an embedding model.
+func perfSpeedText(r perfRun) string {
+	// A chat model.
+	if r.AnswerSpeed > 0 {
+		// Tokens per second.
+		return fmtSpeed(r.AnswerSpeed)
+	} // end of the chat check
+	// An embedding model.
+	if r.Kind == "embedding" && r.WarmTotalSec > 0 {
+		// The time one embedding took.
+		return fmt.Sprintf("%s per embedding", fmtSecs(r.WarmTotalSec))
+	} // end of the embedding check
+	// Nothing to show.
+	return "not available"
+} // end of perfSpeedText
+
+// summaries describes the saved results per model; with a model name it describes only that model; "this" marks the model the person came from.
+func (s *perfStore) summaries(only, this string) []perfSummary {
+	// One reader at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// One entry per model, with its newest and oldest run.
+	type acc struct {
+		// n counts the runs.
+		n int
+		// first is the oldest run.
+		first perfRun
+		// last is the newest run.
+		last perfRun
+	} // end of acc
+	// The entries by model name.
+	by := map[string]*acc{}
+	// Go through all runs.
+	for _, r := range s.runs {
+		// Only the wanted model, when one is given.
+		if only != "" && r.Model != only {
+			// Skip it.
+			continue
+		} // end of the model check
+		// The entry of this model.
+		a := by[r.Model]
+		// The first run of a model starts its entry.
+		if a == nil {
+			// Create it.
+			a = &acc{first: r, last: r}
+			// Keep it.
+			by[r.Model] = a
+		} // end of the new entry
+		// Count it.
+		a.n++
+		// An older run.
+		if r.Time.Before(a.first.Time) {
+			// It becomes the first.
+			a.first = r
+		} // end of the older check
+		// A newer run (or the same moment, later in the file).
+		if !r.Time.Before(a.last.Time) {
+			// It becomes the last.
+			a.last = r
+		} // end of the newer check
+	} // end of the loop
+	// The result.
+	var out []perfSummary
+	// Build the lines.
+	for model, a := range by {
+		// One line.
+		out = append(out, perfSummary{Model: model, Tests: a.n, First: perfTimeText(a.first.Time), Latest: perfTimeText(a.last.Time), Speed: perfSpeedText(a.last), This: model == this})
+	} // end of the loop
+	// A steady order: the model of this page first, then by name.
+	sort.Slice(out, func(i, j int) bool {
+		// This model first.
+		if out[i].This != out[j].This {
+			// The marked one goes up.
+			return out[i].This
+		} // end of the marked check
+		// Then by name.
+		return out[i].Model < out[j].Model
+	}) // end of the sort
+	// Hand back.
+	return out
+} // end of summaries
+
+// all returns a copy of every saved run, oldest first.
+func (s *perfStore) all() []perfRun {
+	// One reader at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// A copy, so the caller cannot change the store.
+	return append([]perfRun(nil), s.runs...)
+} // end of all
+
+// runsOf returns a copy of the saved runs of one model, oldest first.
+func (s *perfStore) runsOf(model string) []perfRun {
+	// One reader at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// The result.
+	var out []perfRun
+	// Go through all runs.
+	for _, r := range s.runs {
+		// A match.
+		if r.Model == model {
+			// Keep it.
+			out = append(out, r)
+		} // end of the match check
+	} // end of the loop
+	// Hand back.
+	return out
+} // end of runsOf
+
+// countModel says how many saved runs one model has.
+func (s *perfStore) countModel(model string) int {
+	// One reader at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// Count the matches.
+	n := 0
+	// Go through all runs.
+	for _, r := range s.runs {
+		// A match.
+		if r.Model == model {
+			// Count it.
+			n++
+		} // end of the match check
+	} // end of the loop
+	// The number.
+	return n
+} // end of countModel
+
+// inCompare says whether the model is in the list that "Compare tested models" shows now.
+func (s *perfStore) inCompare(model string) bool {
+	// The newest run of each model with the current prompt.
+	runs, _ := s.latestRuns(perfPromptVersion)
+	// Look for the model.
+	for _, r := range runs {
+		// A match.
+		if r.Model == model {
+			// It is in the list.
+			return true
+		} // end of the match check
+	} // end of the loop
+	// Not in the list.
+	return false
+} // end of inCompare
+
+// removeModel removes every saved run of one model, saves the rest, and says how many were removed.
+func (s *perfStore) removeModel(model string) (int, error) {
+	// One change at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// The runs that stay.
+	var keep []perfRun
+	// Go through all runs.
+	for _, r := range s.runs {
+		// Keep the other models' runs.
+		if r.Model != model {
+			// Keep it.
+			keep = append(keep, r)
+		} // end of the model check
+	} // end of the loop
+	// How many go away.
+	removed := len(s.runs) - len(keep)
+	// Replace the list.
+	s.runs = keep
+	// Save.
+	return removed, s.writeLocked()
+} // end of removeModel
+
+// removedResults is what is written to the safety copy when saved results are removed.
+type removedResults struct {
+	// Version is snapshotVersion, so a future version of the program can recognise the layout.
+	Version int `json:"version"`
+	// RemovedAt is the moment of removal.
+	RemovedAt time.Time `json:"removed_at"`
+	// Scope is "all models" or the model name.
+	Scope string `json:"scope"`
+	// Runs are the removed results.
+	Runs []perfRun `json:"runs"`
+} // end of removedResults
+
+// removalPlan tells, before anything is removed, whether a safety copy can be kept; the bool is true when it cannot.
+func removalPlan(h *historyStore) (string, bool) {
+	// No folder: nothing can be copied.
+	if h.dir == "" {
+		// The stored reason, or a fixed one.
+		if h.note != "" {
+			// Say why.
+			return h.note + " These results would be gone for good.", true
+		} // end of the note check
+		// A fixed reason.
+		return "There is no history folder, so these results would be gone for good.", true
+	} // end of the folder check
+	// All is well.
+	return "A copy of these results is saved first, in " + h.dir + ", so they can still be looked at by hand (numbers only).", false
+} // end of removalPlan
+
+// keepCopy saves the safety copy of results that are about to be removed; it returns the full path of the copy, or the reason there is none.
+func keepCopy(h *historyStore, scope string, runs []perfRun, at time.Time) (string, string) {
+	// Nothing to copy.
+	if len(runs) == 0 {
+		// No copy, no problem.
+		return "", ""
+	} // end of the empty check
+	// The label in the file name and in the file.
+	label := scope
+	// An empty scope means all models.
+	if label == "" {
+		// The words.
+		label = "all models"
+	} // end of the label check
+	// Save it.
+	name, err := h.saveRemoved(removedResults{Version: snapshotVersion, RemovedAt: at, Scope: label, Runs: runs})
+	// A failure is reported, not hidden.
+	if err != nil {
+		// The reason in words.
+		return "", err.Error()
+	} // end of the save check
+	// The full path.
+	return filepath.Join(h.dir, name), ""
+} // end of keepCopy
diff --git a/perfclear_test.go b/perfclear_test.go
new file mode 100644
index 0000000..9132b29
--- /dev/null
+++ b/perfclear_test.go
@@ -0,0 +1,401 @@
+// Package main tells Go that this test file belongs to the same program as perfclear.go.
+package main
+
+import ( // import lists the packages this test file uses.
+	// encoding/json reads the safety copy.
+	"encoding/json"
+	// net/http provides status codes.
+	"net/http"
+	// net/url builds form data.
+	"net/url"
+	// os reads the folder and the files.
+	"os"
+	// path/filepath builds paths.
+	"path/filepath"
+	// regexp checks that dates name their zone.
+	"regexp"
+	// strings searches text.
+	"strings"
+	// testing is Go's built-in test framework.
+	"testing"
+	// time builds run times.
+	"time"
+) // end of imports
+
+// clearRig holds the handlers of the clearing pages with a store and a history folder of this test.
+type clearRig struct {
+	// ask is the first step of clearing everything.
+	ask http.HandlerFunc
+	// do is the second step of clearing everything.
+	do http.HandlerFunc
+	// oneAsk is the first step of clearing one model.
+	oneAsk http.HandlerFunc
+	// oneDo is the second step of clearing one model.
+	oneDo http.HandlerFunc
+	// store holds the saved runs.
+	store *perfStore
+	// hist is the history folder that receives the safety copies.
+	hist *historyStore
+	// token is the page token the forms carry.
+	token string
+} // end of clearRig
+
+// newClearRig seeds three runs of alpha:1b and two of beta:1b, and builds the handlers.
+func newClearRig(t *testing.T, hist *historyStore) clearRig {
+	// Mark this as a helper.
+	t.Helper()
+	// Show times in UTC, so the zone name in the text is predictable.
+	old := time.Local
+	// Put it back at the end.
+	t.Cleanup(func() { time.Local = old })
+	// UTC.
+	time.Local = time.UTC
+	// The store writes into a file of this test.
+	store := &perfStore{path: filepath.Join(t.TempDir(), "performance.json")}
+	// A base time.
+	base := time.Date(2026, 10, 24, 21, 10, 0, 0, time.UTC)
+	// Three runs of alpha, the newest at 212 tokens per second.
+	for i, speed := range []float64{150, 180, 212} {
+		// Add it.
+		store.runs = append(store.runs, perfRun{Time: base.Add(time.Duration(i) * 24 * time.Hour), Model: "alpha:1b", Kind: "generate", PromptVersion: perfPromptVersion, AnswerSpeed: speed})
+	} // end of the alpha loop
+	// Two runs of beta.
+	for i, speed := range []float64{90, 96} {
+		// Add it.
+		store.runs = append(store.runs, perfRun{Time: base.Add(time.Duration(i) * 48 * time.Hour), Model: "beta:1b", Kind: "generate", PromptVersion: perfPromptVersion, AnswerSpeed: speed})
+	} // end of the beta loop
+	// The handlers; the Ollama address is not used by the clearing pages.
+	a, d, oa, od := func() (http.HandlerFunc, http.HandlerFunc, http.HandlerFunc, http.HandlerFunc) {
+		// Build the six and keep the four that clear.
+		_, _, ask, do, oneAsk, oneDo := perfHandlers(ollamaAddress{}, strings.Repeat("a", 32), store, hist)
+		// Hand back.
+		return ask, do, oneAsk, oneDo
+	}() // end of the call
+	// The rig.
+	return clearRig{ask: a, do: d, oneAsk: oa, oneDo: od, store: store, hist: hist, token: strings.Repeat("a", 32)}
+} // end of newClearRig
+
+// send posts the form of the clearing pages to one handler and returns the status and the page text.
+func (c clearRig) send(t *testing.T, h http.HandlerFunc, model string) (int, string) {
+	// Mark this as a helper.
+	t.Helper()
+	// The form, as the page's own form would send it.
+	res := post(t, h, "/x", url.Values{"token": {c.token}, "model": {model}}, fromThisPage)
+	// The status and the text.
+	return res.StatusCode, bodyOf(res)
+} // end of send
+
+// TestClearAskShowsTheImpact checks the first step shows every model with its dates and zone, and removes nothing.
+func TestClearAskShowsTheImpact(t *testing.T) {
+	// A rig with a history folder.
+	c := newClearRig(t, &historyStore{dir: t.TempDir()})
+	// Ask from the page of alpha.
+	status, page := c.send(t, c.ask, "alpha:1b")
+	// It must be a normal page.
+	if status != http.StatusOK {
+		// Stop the test.
+		t.Fatalf("status %d", status)
+	} // end of the status check
+	// What must be there.
+	for _, want := range []string{
+		// The red box with the total.
+		"permanently remove all 5 saved test results, for every model.",
+		// Both models, this one marked.
+		"<code>alpha:1b</code> <span class=\"muted\">(this model)</span>", "<code>beta:1b</code>",
+		// Counts, dates with year and zone, and the newest speed.
+		"<td>3</td>", "24 Oct 2026 21:10 UTC", "26 Oct 2026 21:10 UTC", "212.0 tokens/s", "96.0 tokens/s",
+		// The consequences and what is safe.
+		"becomes empty (now: 2 models)", "Not affected: the models themselves, their settings, and the delete history.",
+		// The copy plan.
+		"A copy of these results is saved first, in",
+		// The three choices.
+		"Cancel, keep them", "Remove only alpha:1b (3 results)", "Yes, remove all 5 results",
+	} { // end of the list
+		// Look for it.
+		if !strings.Contains(page, want) {
+			// Report the problem.
+			t.Errorf("page does not contain %q", want)
+		} // end of the check
+	} // end of the loop
+	// Nothing was removed.
+	if c.store.count() != 5 {
+		// Report the problem.
+		t.Errorf("the question removed something: %d left", c.store.count())
+	} // end of the count check
+	// The model of this page comes first.
+	if strings.Index(page, "<tr><td><code>alpha:1b</code>") > strings.Index(page, "<tr><td><code>beta:1b</code>") {
+		// Report the problem.
+		t.Errorf("this model is not listed first")
+	} // end of the order check
+	// From beta's page, beta comes first.
+	_, fromBeta := c.send(t, c.ask, "beta:1b")
+	// The order flips.
+	if strings.Index(fromBeta, "<tr><td><code>beta:1b</code>") > strings.Index(fromBeta, "<tr><td><code>alpha:1b</code>") {
+		// Report the problem.
+		t.Errorf("the marked model is not listed first from beta's page")
+	} // end of the flipped order check
+	// The destructive buttons are the filled red ones, and the safe choice is not.
+	if !strings.Contains(page, `class="btn-solid">Yes, remove all 5 results`) || !strings.Contains(page, `class="btn-load" href="/">Cancel, keep them`) {
+		// Report the problem.
+		t.Errorf("button styles are wrong")
+	} // end of the style check
+	// The same for one model.
+	_, one := c.send(t, c.oneAsk, "alpha:1b")
+	// The destructive button.
+	if !strings.Contains(one, `class="btn-solid">Yes, remove these 3 results`) {
+		// Report the problem.
+		t.Errorf("the single-model button is not the red one")
+	} // end of the single style check
+} // end of TestClearAskShowsTheImpact
+
+// TestEverySummaryDateNamesItsZone checks the dates in the table carry the year and a zone name.
+func TestEverySummaryDateNamesItsZone(t *testing.T) {
+	// A rig.
+	c := newClearRig(t, &historyStore{dir: t.TempDir()})
+	// A year, a clock time and a zone name.
+	re := regexp.MustCompile(`^\d{1,2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2} [A-Z]{3,5}$`)
+	// Check each line.
+	for _, s := range c.store.summaries("", "") {
+		// Both dates.
+		for _, d := range []string{s.First, s.Latest} {
+			// The shape.
+			if !re.MatchString(d) {
+				// Report the problem.
+				t.Errorf("%s: date %q has no year or zone", s.Model, d)
+			} // end of the shape check
+		} // end of the dates loop
+	} // end of the loop
+} // end of TestEverySummaryDateNamesItsZone
+
+// TestClearAllKeepsACopy checks the second step keeps a readable safety copy and then removes everything.
+func TestClearAllKeepsACopy(t *testing.T) {
+	// A history folder of this test.
+	dir := t.TempDir()
+	// A rig.
+	c := newClearRig(t, &historyStore{dir: dir})
+	// Confirm.
+	_, page := c.send(t, c.do, "alpha:1b")
+	// The wording.
+	if !strings.Contains(page, "All saved test results were removed") || !strings.Contains(page, "A copy of the removed results was saved as") {
+		// Report the problem.
+		t.Errorf("done page is wrong: %s", page)
+	} // end of the wording check
+	// Everything is gone.
+	if c.store.count() != 0 {
+		// Report the problem.
+		t.Errorf("%d runs left", c.store.count())
+	} // end of the count check
+	// One copy file.
+	files, _ := filepath.Glob(filepath.Join(dir, "*_performance-results_all-models"+removedSuffix))
+	// Exactly one.
+	if len(files) != 1 {
+		// Stop the test.
+		t.Fatalf("%d copy files, want 1", len(files))
+	} // end of the file count
+	// Read it.
+	data, err := os.ReadFile(files[0])
+	// It must be readable.
+	if err != nil {
+		// Stop the test.
+		t.Fatalf("cannot read the copy: %v", err)
+	} // end of the read check
+	// Decode it.
+	var got removedResults
+	// It must be valid.
+	if err := json.Unmarshal(data, &got); err != nil || got.Scope != "all models" || len(got.Runs) != 5 || got.Version != snapshotVersion {
+		// Report the problem.
+		t.Errorf("copy is wrong: %v %+v", err, got)
+	} // end of the content check
+	// Only this user may read it.
+	if st, _ := os.Stat(files[0]); st.Mode().Perm() != 0o600 {
+		// Report the problem.
+		t.Errorf("copy mode %v, want 0600", st.Mode().Perm())
+	} // end of the mode check
+	// The page names the full path.
+	if !strings.Contains(page, files[0]) {
+		// Report the problem.
+		t.Errorf("the page does not name the copy's path")
+	} // end of the path check
+} // end of TestClearAllKeepsACopy
+
+// TestClearOneKeepsTheOthers checks the single-model flow: it asks first with that model's row only, then removes only that model and keeps a copy of just those runs.
+func TestClearOneKeepsTheOthers(t *testing.T) {
+	// A history folder of this test.
+	dir := t.TempDir()
+	// A rig.
+	c := newClearRig(t, &historyStore{dir: dir})
+	// The question.
+	_, ask := c.send(t, c.oneAsk, "alpha:1b")
+	// What must be there, and what must not.
+	for _, want := range []string{"permanently remove the 3 saved test results of <code>alpha:1b</code>", "The 2 results of other models stay.", "Yes, remove these 3 results", "<code>alpha:1b</code>"} {
+		// Look for it.
+		if !strings.Contains(ask, want) {
+			// Report the problem.
+			t.Errorf("question lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// The other model must not be in the table.
+	if strings.Contains(ask, "<code>beta:1b</code>") {
+		// Report the problem.
+		t.Errorf("the question lists another model")
+	} // end of the other check
+	// The question removed nothing.
+	if c.store.count() != 5 {
+		// Report the problem.
+		t.Fatalf("the question removed something")
+	} // end of the count check
+	// Confirm.
+	_, done := c.send(t, c.oneDo, "alpha:1b")
+	// The wording.
+	if !strings.Contains(done, "The 3 saved test results of <code>alpha:1b</code> were removed.") {
+		// Report the problem.
+		t.Errorf("done page is wrong: %s", done)
+	} // end of the wording check
+	// Only beta is left.
+	if c.store.count() != 2 || c.store.countModel("beta:1b") != 2 || c.store.countModel("alpha:1b") != 0 {
+		// Report the problem.
+		t.Errorf("wrong runs left: %d", c.store.count())
+	} // end of the left check
+	// The change was saved to the file too.
+	reopened := openPerfStore(c.store.path, "")
+	// Two runs on disk.
+	if reopened.count() != 2 {
+		// Report the problem.
+		t.Errorf("file holds %d runs, want 2", reopened.count())
+	} // end of the file check
+	// The copy holds only alpha's runs.
+	files, _ := filepath.Glob(filepath.Join(dir, "*_performance-results_alpha-1b"+removedSuffix))
+	// Exactly one.
+	if len(files) != 1 {
+		// Stop the test.
+		t.Fatalf("%d copy files, want 1", len(files))
+	} // end of the file count
+	// Read it.
+	data, _ := os.ReadFile(files[0])
+	// Decode it.
+	var got removedResults
+	// It must be valid and hold three alpha runs.
+	if err := json.Unmarshal(data, &got); err != nil || got.Scope != "alpha:1b" || len(got.Runs) != 3 {
+		// Report the problem.
+		t.Errorf("copy is wrong: %v %+v", err, got)
+	} // end of the content check
+} // end of TestClearOneKeepsTheOthers
+
+// TestClearWithoutAHistoryFolderWarnsAndStillRemoves checks the person is told, before and after, that no copy exists.
+func TestClearWithoutAHistoryFolderWarnsAndStillRemoves(t *testing.T) {
+	// No folder, with a reason.
+	c := newClearRig(t, &historyStore{note: "No folder for the history was found, so no snapshots are kept."})
+	// The question warns.
+	_, ask := c.send(t, c.ask, "alpha:1b")
+	// The warning.
+	if !strings.Contains(ask, "No copy can be kept.") || !strings.Contains(ask, "would be gone for good") {
+		// Report the problem.
+		t.Errorf("no warning before removal: %s", ask)
+	} // end of the warning check
+	// The confirmed removal still happens.
+	_, done := c.send(t, c.do, "alpha:1b")
+	// The page says no copy was kept.
+	if !strings.Contains(done, "No copy was kept.") || c.store.count() != 0 {
+		// Report the problem.
+		t.Errorf("done page or removal wrong: %s", done)
+	} // end of the done check
+} // end of TestClearWithoutAHistoryFolderWarnsAndStillRemoves
+
+// TestClearEdgeCases checks an empty store and a model without results.
+func TestClearEdgeCases(t *testing.T) {
+	// A rig.
+	c := newClearRig(t, &historyStore{dir: t.TempDir()})
+	// A model with nothing saved.
+	_, none := c.send(t, c.oneAsk, "ghost:1b")
+	// The plain words.
+	if !strings.Contains(none, "There are no saved test results for <code>ghost:1b</code>.") {
+		// Report the problem.
+		t.Errorf("wrong page: %s", none)
+	} // end of the none check
+	// Empty the store.
+	c.store.clear()
+	// Ask to clear everything.
+	_, empty := c.send(t, c.ask, "alpha:1b")
+	// The plain words, and no destructive button.
+	if !strings.Contains(empty, "There are no saved test results to remove.") || strings.Contains(empty, "btn-solid") {
+		// Report the problem.
+		t.Errorf("wrong page: %s", empty)
+	} // end of the empty check
+} // end of TestClearEdgeCases
+
+// TestTwoCopiesInOneSecondDoNotOverwrite checks a second copy at the same moment gets a number.
+func TestTwoCopiesInOneSecondDoNotOverwrite(t *testing.T) {
+	// A folder.
+	h := &historyStore{dir: t.TempDir()}
+	// The same moment twice.
+	at := time.Date(2026, 10, 27, 20, 0, 0, 0, time.UTC)
+	// Save twice.
+	a, errA := h.saveRemoved(removedResults{Version: snapshotVersion, RemovedAt: at, Scope: "all models"})
+	// The second one.
+	b, errB := h.saveRemoved(removedResults{Version: snapshotVersion, RemovedAt: at, Scope: "all models"})
+	// Both must work and differ.
+	if errA != nil || errB != nil || a == b {
+		// Report the problem.
+		t.Errorf("names %q and %q, errors %v %v", a, b, errA, errB)
+	} // end of the check
+	// The name carries the zone offset (Z for UTC).
+	if !strings.Contains(a, "20-00-00Z_performance-results_all-models") {
+		// Report the problem.
+		t.Errorf("name %q lacks the zone", a)
+	} // end of the zone check
+} // end of TestTwoCopiesInOneSecondDoNotOverwrite
+
+// TestRemovedCopiesAreNotParameterSnapshots checks the parameter history of a model never lists a results copy.
+func TestRemovedCopiesAreNotParameterSnapshots(t *testing.T) {
+	// A folder.
+	h := &historyStore{dir: t.TempDir()}
+	// A copy whose scope is the model's own name.
+	if _, err := h.saveRemoved(removedResults{Version: snapshotVersion, RemovedAt: time.Now(), Scope: "alpha:1b"}); err != nil {
+		// Stop the test.
+		t.Fatalf("save: %v", err)
+	} // end of the save check
+	// The two kinds of file must end differently, so they can never be mixed up.
+	if removedSuffix == snapshotSuffix || !strings.HasSuffix(removedSuffix, "_removed.json") {
+		// Report the problem.
+		t.Errorf("suffixes: %q and %q", removedSuffix, snapshotSuffix)
+	} // end of the suffix check
+	// The file name ends with the removal suffix.
+	if files, _ := filepath.Glob(filepath.Join(h.dir, "*"+removedSuffix)); len(files) != 1 {
+		// Report the problem.
+		t.Errorf("%d files with the removal suffix, want 1", len(files))
+	} // end of the file check
+	// The parameter history must be empty.
+	if got := h.list("alpha:1b"); len(got) != 0 {
+		// Report the problem.
+		t.Errorf("a results copy was listed as a snapshot: %+v", got)
+	} // end of the list check
+} // end of TestRemovedCopiesAreNotParameterSnapshots
+
+// TestClearOneRoutesAreGuarded checks the two new routes refuse foreign, tokenless and wrong-method requests.
+func TestClearOneRoutesAreGuarded(t *testing.T) {
+	// Build the rig.
+	rig := newThemeRig(t)
+	// Both routes.
+	for _, path := range []string{"/performance/clear/model", "/performance/clear/model/confirm"} {
+		// Another site.
+		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"a"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
+			// Report the problem.
+			t.Errorf("%s cross-site = %d, want 403", path, res.StatusCode)
+		} // end of the origin check
+		// No token.
+		if res := post(t, rig.h, path, url.Values{"model": {"a"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
+			// Report the problem.
+			t.Errorf("%s without token = %d, want 403", path, res.StatusCode)
+		} // end of the token check
+		// No model name.
+		if res := post(t, rig.h, path, url.Values{"token": {rig.token}}, fromThisPage); res.StatusCode != http.StatusBadRequest {
+			// Report the problem.
+			t.Errorf("%s without model = %d, want 400", path, res.StatusCode)
+		} // end of the model check
+		// A GET.
+		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed {
+			// Report the problem.
+			t.Errorf("GET %s = %d, want 405", path, status)
+		} // end of the method check
+	} // end of the loop
+} // end of TestClearOneRoutesAreGuarded
diff --git a/perfpage.go b/perfpage.go
index d385f3d..fadc72b 100644
--- a/perfpage.go
+++ b/perfpage.go
@@ -22,6 +22,8 @@ import ( // import lists the standard-library packages this file uses.
 	"strings"
 	// sync keeps two tests from running at the same time.
 	"sync"
+	// time stamps the safety copy of removed results.
+	"time"
 ) // end of imports
 
 // performanceTemplateText holds the performance pages, stored inside the executable at build time.
@@ -85,6 +87,24 @@ type perfPage struct {
 	HistoryCount int
 	// Seconds is the rough time the test may take, in words.
 	Duration string
+	// Summaries are the lines of the "what you lose" table.
+	Summaries []perfSummary
+	// CompareNow is how many models "Compare tested models" lists now.
+	CompareNow int
+	// InCompare is true when the model is in that list now.
+	InCompare bool
+	// RemoveCount is how many results one removal takes away.
+	RemoveCount int
+	// OtherCount is how many results of other models would stay.
+	OtherCount int
+	// CopyPlan says, before removal, whether a safety copy will be kept.
+	CopyPlan string
+	// CopyPlanBad is true when no safety copy can be kept.
+	CopyPlanBad bool
+	// CopyFile is the full path of the safety copy that was kept, or empty.
+	CopyFile string
+	// CopyErr is why no safety copy was kept, or empty.
+	CopyErr string
 } // end of perfPage
 
 // fmtSecs shows a time in seconds with sensible decimals; zero means not available.
@@ -433,8 +453,8 @@ func historyTable(runs []perfRun, kind string) ([]string, [][]string) {
 	return cols, rows
 } // end of historyTable
 
-// perfHandlers builds the four handlers: the start page (changes nothing), the run, and the two steps of clearing the history.
-func perfHandlers(addr ollamaAddress, token string, store *perfStore) (http.HandlerFunc, http.HandlerFunc, http.HandlerFunc, http.HandlerFunc) {
+// perfHandlers builds the six handlers: the start page (changes nothing), the run, the two steps of clearing all saved results, and the two steps of clearing one model's results; the history folder receives a safety copy of whatever is removed.
+func perfHandlers(addr ollamaAddress, token string, store *perfStore, hist *historyStore) (http.HandlerFunc, http.HandlerFunc, http.HandlerFunc, http.HandlerFunc, http.HandlerFunc, http.HandlerFunc) {
 	// Read the template once, together with the shared help-bubble templates; Must stops the program at start-up if it is broken, which a test would catch first.
 	page := template.Must(template.New("performance").Parse(performanceTemplateText + tipsTemplateText))
 	// The help bubbles never change, so build them once, each with an element name that is unique on the page.
@@ -640,7 +660,7 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore) (http.Hand
 		// Show it.
 		show(w, r, http.StatusOK, p)
 	} // end of run
-	// clearAsk is the first step of clearing: it asks "are you sure?" and changes nothing.
+	// clearAsk is the first step of clearing everything: it shows what would be lost and changes nothing.
 	clearAsk := func(w http.ResponseWriter, r *http.Request) {
 		// The form checks.
 		name, ok := readModelForm(w, r, token)
@@ -649,10 +669,12 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore) (http.Hand
 			// Stop here.
 			return
 		} // end of the form checks
-		// Show the question.
-		show(w, r, http.StatusOK, perfPage{Kind: "clearask", Model: name, HistoryCount: store.count()})
+		// Whether a safety copy can be kept.
+		plan, bad := removalPlan(hist)
+		// Show the question with its consequences.
+		show(w, r, http.StatusOK, perfPage{Kind: "clearask", Model: name, HistoryCount: store.count(), Summaries: store.summaries("", name), CompareNow: store.testedModels(), RemoveCount: store.countModel(name), CopyPlan: plan, CopyPlanBad: bad})
 	} // end of clearAsk
-	// clearDo is the second step: it removes every saved run.
+	// clearDo is the second step: it keeps a copy, then removes every saved run.
 	clearDo := func(w http.ResponseWriter, r *http.Request) {
 		// The form checks.
 		name, ok := readModelForm(w, r, token)
@@ -661,6 +683,10 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore) (http.Hand
 			// Stop here.
 			return
 		} // end of the form checks
+		// Everything that is about to go.
+		runs := store.all()
+		// Keep a copy first; a failure is reported but does not stop the confirmed removal.
+		file, copyErr := keepCopy(hist, "", runs, time.Now())
 		// Remove everything.
 		if err := store.clear(); err != nil {
 			// Say why.
@@ -669,8 +695,54 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore) (http.Hand
 			return
 		} // end of the clear check
 		// Say it is done.
-		show(w, r, http.StatusOK, perfPage{Kind: "cleared", Model: name})
+		show(w, r, http.StatusOK, perfPage{Kind: "cleared", Model: name, RemoveCount: len(runs), CopyFile: file, CopyErr: copyErr})
 	} // end of clearDo
-	// Hand the four handlers back.
-	return start, run, clearAsk, clearDo
+	// clearOneAsk is the first step of clearing one model's results: it shows what would be lost and changes nothing.
+	clearOneAsk := func(w http.ResponseWriter, r *http.Request) {
+		// The form checks.
+		name, ok := readModelForm(w, r, token)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the form checks
+		// How many results this model has.
+		n := store.countModel(name)
+		// Nothing saved for it.
+		if n == 0 {
+			// Say so.
+			show(w, r, http.StatusOK, perfPage{Kind: "clearonenone", Model: name})
+			// Stop here.
+			return
+		} // end of the empty check
+		// Whether a safety copy can be kept.
+		plan, bad := removalPlan(hist)
+		// Show the question with its consequences.
+		show(w, r, http.StatusOK, perfPage{Kind: "clearoneask", Model: name, RemoveCount: n, OtherCount: store.count() - n, Summaries: store.summaries(name, name), InCompare: store.inCompare(name), CopyPlan: plan, CopyPlanBad: bad})
+	} // end of clearOneAsk
+	// clearOneDo is the second step: it keeps a copy, then removes the results of this model only.
+	clearOneDo := func(w http.ResponseWriter, r *http.Request) {
+		// The form checks.
+		name, ok := readModelForm(w, r, token)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the form checks
+		// Keep a copy first; a failure is reported but does not stop the confirmed removal.
+		file, copyErr := keepCopy(hist, name, store.runsOf(name), time.Now())
+		// Remove this model's results.
+		n, err := store.removeModel(name)
+		// A failure to save.
+		if err != nil {
+			// Say why.
+			show(w, r, http.StatusInternalServerError, perfPage{Kind: "error", Model: name, Detail: err.Error()})
+			// Stop here.
+			return
+		} // end of the remove check
+		// Say it is done.
+		show(w, r, http.StatusOK, perfPage{Kind: "clearonedone", Model: name, RemoveCount: n, CopyFile: file, CopyErr: copyErr})
+	} // end of clearOneDo
+	// Hand the six handlers back.
+	return start, run, clearAsk, clearDo, clearOneAsk, clearOneDo
 } // end of perfHandlers
diff --git a/web.go b/web.go
index 747d44c..d884447 100644
--- a/web.go
+++ b/web.go
@@ -156,7 +156,7 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	// The read-only list of parameter snapshots of a deleted model.
 	mux.HandleFunc("POST /restore/history", restoreHistory)
 	// The four handlers of the performance pages.
-	perfStart, perfRun, perfClearAsk, perfClearDo := perfHandlers(addr, token, perfHistory)
+	perfStart, perfRun, perfClearAsk, perfClearDo, perfClearOneAsk, perfClearOneDo := perfHandlers(addr, token, perfHistory, historyDir)
 	// Route: a POST request for "/performance" shows the performance page and changes nothing.
 	mux.HandleFunc("POST /performance", perfStart)
 	// Route: a POST request for "/performance/run" runs the test.
@@ -165,6 +165,10 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	mux.HandleFunc("POST /performance/clear", perfClearAsk)
 	// Route: a POST request for "/performance/clear/confirm" removes them.
 	mux.HandleFunc("POST /performance/clear/confirm", perfClearDo)
+	// Route: a POST request for "/performance/clear/model" shows what removing one model's saved results would lose, and changes nothing.
+	mux.HandleFunc("POST /performance/clear/model", perfClearOneAsk)
+	// Route: a POST request for "/performance/clear/model/confirm" removes one model's saved results (after keeping a copy).
+	mux.HandleFunc("POST /performance/clear/model/confirm", perfClearOneDo)
 	// Route: a POST request for "/compare" shows the comparison of the tested models and changes nothing.
 	mux.HandleFunc("POST /compare", compareHandler(addr, token, perfHistory))
 	// Route: a POST request for "/watch" pauses or resumes the automatic updates of the page.
diff --git a/web/performance.html b/web/performance.html
index 46d1a21..a4bca1d 100644
--- a/web/performance.html
+++ b/web/performance.html
@@ -25,6 +25,33 @@
 {{end}}
 {{/* End of the group. */}}
 {{end}}
+{{/* The table of what is saved, one line per model, with the year and the time zone in the dates. */}}
+{{define "impact"}}
+<table class="settingtable">
+<thead><tr><th>Model</th><th>Tests saved</th><th>First test</th><th>Latest test</th><th>Latest speed</th></tr></thead>
+<tbody>
+{{range .Summaries}}
+<tr><td><code>{{.Model}}</code>{{if .This}} <span class="muted">(this model)</span>{{end}}</td><td>{{.Tests}}</td><td>{{.First}}</td><td>{{.Latest}}</td><td>{{.Speed}}</td></tr>
+{{end}}
+</tbody>
+</table>
+{{end}}
+{{/* Before removal: whether a safety copy will be kept. */}}
+{{define "copyplan"}}
+{{if .CopyPlanBad}}
+<p class="warn" role="alert"><strong>⚠ No copy can be kept.</strong> {{.CopyPlan}}</p>
+{{else}}
+<p class="goodnote">{{.CopyPlan}}</p>
+{{end}}
+{{end}}
+{{/* After removal: where the safety copy is, or why there is none. */}}
+{{define "copydone"}}
+{{if .CopyFile}}
+<p class="goodnote">A copy of the removed results was saved as <code>{{.CopyFile}}</code>.</p>
+{{else if .CopyErr}}
+<p class="warn" role="alert"><strong>⚠ No copy was kept.</strong> {{.CopyErr}}</p>
+{{end}}
+{{end}}
 {{/* The history table of one model. */}}
 {{define "perfclear"}}
 {{if .HistoryCount}}
@@ -160,20 +187,90 @@
 {{else if eq .Kind "running"}}
 <p><strong>Another performance test is running.</strong> Two tests at once would disturb each other's figures. Wait until it has finished, then try again.</p>
 <p><a class="btn-plain" href="/">Back to the monitor</a></p>
-{{/* Version 7: ask before clearing. */}}
+{{/* Version 7: ask before clearing everything; it shows what would be lost. */}}
 {{else if eq .Kind "clearask"}}
-<p class="warn"><strong>⚠ This removes all {{.HistoryCount}} saved test results, for every model.</strong> It cannot be undone.</p>
+{{/* Nothing saved: nothing to remove. */}}
+{{if not .HistoryCount}}
+<p>There are no saved test results to remove.</p>
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Something is saved. */}}
+{{else}}
+{{/* The loss, in a red box. */}}
+<div class="lossbox"><strong>⚠ You are about to permanently remove all {{.HistoryCount}} saved test results, for every model.</strong> It cannot be undone.</div>
+{{/* What exactly is saved. */}}
+<h2>What you lose</h2>
+{{template "impact" .}}
+{{/* What stops working. */}}
+<h2>What stops working</h2>
+<ul>
+{{if .CompareNow}}
+<li><strong>Compare tested models</strong> becomes empty (now: {{.CompareNow}} {{if eq .CompareNow 1}}model{{else}}models{{end}}) until each model is tested again.</li>
+{{end}}
+<li>Every model needs a new performance test, which loads it into memory again.</li>
+</ul>
+{{/* What is safe. */}}
+<p class="muted">Not affected: the models themselves, their settings, and the delete history.</p>
+{{/* Whether a copy is kept. */}}
+{{template "copyplan" .}}
+{{/* The choices: the safe one first, the destructive one last. */}}
 <div class="choices">
+<a class="btn-load" href="/">Cancel, keep them</a>
+{{/* The smaller removal. */}}
+<form method="post" action="/performance/clear/model">
+<input type="hidden" name="token" value="{{.Token}}">
+<input type="hidden" name="model" value="{{.Model}}">
+{{if .RemoveCount}}<button type="submit" class="btn-plain">Remove only {{.Model}} ({{.RemoveCount}} {{if eq .RemoveCount 1}}result{{else}}results{{end}})</button>{{end}}
+</form>
+{{/* The removal of everything. */}}
 <form method="post" action="/performance/clear/confirm">
 <input type="hidden" name="token" value="{{.Token}}">
 <input type="hidden" name="model" value="{{.Model}}">
-<button type="submit" class="btn-load">Yes, remove them all</button>
+<button type="submit" class="btn-solid">Yes, remove all {{.HistoryCount}} results</button>
 </form>
-<a class="btn-plain" href="/">Cancel, keep them</a>
 </div>
-{{/* Version 8: cleared. */}}
+{{/* End of the saved check. */}}
+{{end}}
+{{/* Version 8: everything cleared. */}}
 {{else if eq .Kind "cleared"}}
 <p><strong>Done.</strong> All saved test results were removed.</p>
+{{template "copydone" .}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 7b: ask before clearing one model's results. */}}
+{{else if eq .Kind "clearoneask"}}
+{{/* The loss, in a red box. */}}
+<div class="lossbox"><strong>⚠ You are about to permanently remove the {{.RemoveCount}} saved test {{if eq .RemoveCount 1}}result{{else}}results{{end}} of <code>{{.Model}}</code>.</strong> It cannot be undone.{{if .OtherCount}} The {{.OtherCount}} {{if eq .OtherCount 1}}result{{else}}results{{end}} of other models stay.{{end}}</div>
+{{/* What exactly is saved for this model. */}}
+<h2>What you lose</h2>
+{{template "impact" .}}
+{{/* What stops working. */}}
+<h2>What stops working</h2>
+<ul>
+{{if .InCompare}}
+<li><code>{{.Model}}</code> leaves the list in <strong>Compare tested models</strong> until it is tested again.</li>
+{{end}}
+<li>Its saved test history shows empty until the model is tested again, which loads it into memory.</li>
+</ul>
+{{/* What is safe. */}}
+<p class="muted">Not affected: the model itself, its settings, the delete history and the results of other models.</p>
+{{/* Whether a copy is kept. */}}
+{{template "copyplan" .}}
+{{/* The choices: the safe one first. */}}
+<div class="choices">
+<a class="btn-load" href="/">Cancel, keep them</a>
+<form method="post" action="/performance/clear/model/confirm">
+<input type="hidden" name="token" value="{{.Token}}">
+<input type="hidden" name="model" value="{{.Model}}">
+<button type="submit" class="btn-solid">Yes, remove these {{.RemoveCount}} {{if eq .RemoveCount 1}}result{{else}}results{{end}}</button>
+</form>
+</div>
+{{/* Version 8b: one model's results were removed. */}}
+{{else if eq .Kind "clearonedone"}}
+<p><strong>Done.</strong> The {{.RemoveCount}} saved test {{if eq .RemoveCount 1}}result{{else}}results{{end}} of <code>{{.Model}}</code> {{if eq .RemoveCount 1}}was{{else}}were{{end}} removed.</p>
+{{template "copydone" .}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 8c: nothing saved for this model. */}}
+{{else if eq .Kind "clearonenone"}}
+<p>There are no saved test results for <code>{{.Model}}</code>.</p>
 <p><a class="btn-plain" href="/">Back to the monitor</a></p>
 {{/* Version 9: something went wrong. */}}
 {{else}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
75744bc58b6402cd3d1aec472b0e4ecb466369e81effc714185ea90ba4de8d42  perfclear.go
de5397dd70982abc5678a96a74209005b169a970aa7a6d441b8afc6c8a259edf  perfclear_test.go
c6a84720a2ee3069e11255ceca64841d959b4f3ab3703f4a5f4922365fcd829c  history.go
1dcdb8cfdb46baca477921898b72cf755b58cfb6e856d55cf267ba035fab39e8  perfpage.go
725b7839d44c1352f4707a072f27953f75ed53e26a10e1d54b018e5f92b74e29  perf_test.go
38966dcee52fe326d686b524430d35653bf826d9d97621273f3fcd5ef2b243ac  web.go
2909d46898601946fac6a26ee6f31f9474c15fe2bcfd96b325583c4fdb56a7af  web/performance.html
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the files are exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
# Check the formatting of the Go files (no output means all is well).
[ -z "$(gofmt -l .)" ] || { echo "FAIL  gofmt reports unformatted files"; gofmt -l .; exit 1; }
# Report the check.
echo "PASS  gofmt"
# Run Go's own checker for suspicious code.
go vet ./...
# Report the check.
echo "PASS  go vet"
# Run every test.
go test ./...
# Report the check.
echo "PASS  tests"
# Build the executable the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Stop any monitor that is still running the old build (a leftover one would keep showing the old page).
pkill -f "bin/OllamaControlCenter" || true
# Give it a moment to exit.
sleep 1
# Confirm that none is left.
if pgrep -f "bin/OllamaControlCenter" > /dev/null; then
  # Report it.
  echo "FAIL  an old monitor is still running"; exit 1
fi
# Report the check.
echo "PASS  no old monitor is running; start the new one with: ./bin/OllamaControlCenter"
# List the changed files; nothing is committed yet.
git status --short
