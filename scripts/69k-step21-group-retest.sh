#!/usr/bin/env bash
# Script 69k: the comparison page gets a "Re-test this group" button in each group of two or more models. It asks first, then tests the models one after another in the background, with a progress page and a "Stop after this model" button. Models loaded in memory are left alone. Version 0.16.0.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/group-retest" ] || { echo "FAIL  not on feature/group-retest"; exit 1; }
# Script 69j (-check-links) must be applied already (merged into main).
[ -e checklinks.go ] || { echo "FAIL  script 69j was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e retest.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/about.go b/about.go
index 12df87e..2b43022 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.15.0"
+const appVersion = "0.16.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/compare.go b/compare.go
index b1e407d..2495773 100644
--- a/compare.go
+++ b/compare.go
@@ -62,6 +62,8 @@ type cmpGroupView struct {
 	Cols []tipView
 	// Rows are the models.
 	Rows []cmpRow
+	// Retest holds the names of the models of this group that Ollama still has, when there are at least two; the button of the group re-test passes them on.
+	Retest []string
 } // end of cmpGroupView
 
 // comparePage is everything the comparison template needs.
@@ -370,6 +372,11 @@ func buildCompare(runs []perfRun, skipped int, installed map[string]modelDetails
 		for _, m := range g.Models {
 			// One row.
 			v.Rows = append(v.Rows, cmpRow{Busy: m.Run.Busy, Cells: groupRowCells(g, m)})
+			// A model Ollama still has can be tested again; one that is gone cannot.
+			if _, still := installed[m.Run.Model]; known && still {
+				// Keep its real name (the shown name may carry a note).
+				v.Retest = append(v.Retest, m.Run.Model)
+			} // end of the installed check
 			// Count the busy tests.
 			if m.Run.Busy {
 				// One more.
@@ -391,6 +398,11 @@ func buildCompare(runs []perfRun, skipped int, installed map[string]modelDetails
 			// Say so.
 			p.Findings = append(p.Findings, g.Title+": no ranking yet, because fewer than two models can be compared like for like.")
 		} // end of the sentence switch
+		// The button needs at least two models to be worth a group run.
+		if len(v.Retest) < 2 {
+			// No button for this group.
+			v.Retest = nil
+		} // end of the count check
 		// Keep the group.
 		p.Groups = append(p.Groups, v)
 	} // end of the group loop
diff --git a/perfpage.go b/perfpage.go
index 33f9b1c..a768a9d 100644
--- a/perfpage.go
+++ b/perfpage.go
@@ -20,8 +20,6 @@ import ( // import lists the standard-library packages this file uses.
 	"net/http"
 	// strings joins and searches text.
 	"strings"
-	// sync keeps two tests from running at the same time.
-	"sync"
 	// time stamps the safety copy of removed results.
 	"time"
 ) // end of imports
@@ -464,8 +462,6 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore, hist *hist
 		// Build it.
 		tips[h] = makeTip(fmt.Sprintf("tip-perf-%d", i), h)
 	} // end of the loop
-	// Only one test may run at a time: two would disturb each other's figures.
-	var runLock sync.Mutex
 	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
 	show := func(w http.ResponseWriter, r *http.Request, status int, data perfPage) {
 		// Add what every version needs.
@@ -606,14 +602,14 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore, hist *hist
 			return
 		} // end of the checks
 		// Only one test at a time.
-		if !runLock.TryLock() {
+		if !testLock.TryLock() {
 			// Say so.
 			show(w, r, http.StatusOK, perfPage{Kind: "running", Model: name})
 			// Stop here.
 			return
 		} // end of the lock check
 		// Release it when done.
-		defer runLock.Unlock()
+		defer testLock.Unlock()
 		// Tell the Stop page that a test is running, and how to undo it: unload the model the test loaded.
 		defer activeWork.begin("a performance test of "+name+" (Stop cancels it and unloads the model first)", func(ctx context.Context) {
 			// Ask Ollama to unload the model; the answer does not matter here.
diff --git a/retest.go b/retest.go
new file mode 100644
index 0000000..8d232c3
--- /dev/null
+++ b/retest.go
@@ -0,0 +1,699 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes builds a page in memory first.
+	"bytes"
+	// context carries the cancel signal of the background job.
+	"context"
+	// embed stores the page template inside the executable (the blank name means only the side effect is needed).
+	_ "embed"
+	// fmt builds the texts.
+	"fmt"
+	// html/template fills the page and escapes every value.
+	"html/template"
+	// log reports a template problem to the person running the program.
+	"log"
+	// net/http provides requests and status codes.
+	"net/http"
+	// strings tidies the form values.
+	"strings"
+	// sync protects the job that the background work and the pages share.
+	"sync"
+	// time gives the clock for the finishing time.
+	"time"
+) // end of imports
+
+// retestTemplateText is the page of the group re-test, stored inside the executable at build time.
+//
+//go:embed web/retest.html
+var retestTemplateText string
+
+// maxRetestModels is the most models one group re-test may hold; a real group is far smaller.
+const maxRetestModels = 40
+
+// maxRetestTitle is the longest group title the forms accept; the title is only shown back, never used.
+const maxRetestTitle = 200
+
+// retestFormLimit is the most form data a re-test request may carry (40 names of up to 200 characters, and the rest).
+const retestFormLimit = 16 * 1024
+
+// testLock lets only one performance test run at a time: two would disturb each other's figures. The single test and the group re-test share it.
+var testLock sync.Mutex
+
+// retestRow is one model on the pages of the group re-test.
+type retestRow struct {
+	// Name is the model name.
+	Name string
+	// Last is the time of its latest saved test, or a note that there is none.
+	Last string
+	// CharsKnown says whether that test counted the characters of the answer (older tests did not).
+	CharsKnown string
+	// Will says, on the confirmation page, whether the model will be tested, with the reason when not.
+	Will string
+	// State is the progress word on the progress page: waiting, testing, done, failed, skipped or stopped.
+	State string
+	// Note is the reason for a skipped or failed model.
+	Note string
+	// Embedding is true for an embedding model (kept for the job).
+	Embedding bool
+	// Details are what Ollama reports about the model (kept for the job).
+	Details modelDetails
+} // end of retestRow
+
+// retestJob is one group re-test: the models, how far it has got, and whether the person asked to stop after the current model.
+type retestJob struct {
+	// mu protects every field below, because the background work and the pages use them at the same time.
+	mu sync.Mutex
+	// Title is the group title, shown back to the person.
+	Title string
+	// Rows are the models in the order they are tested.
+	Rows []retestRow
+	// Running is true until the last model has been dealt with.
+	Running bool
+	// StopAsked is true after the person pressed the button to stop after the current model.
+	StopAsked bool
+	// Finished is when the job ended, in the person's time zone.
+	Finished time.Time
+} // end of retestJob
+
+// retestPage is everything the re-test template needs.
+type retestPage struct {
+	// Theme is the colour scheme asked for in the address, or empty.
+	Theme string
+	// Size is the saved text size, or empty.
+	Size string
+	// Token is the page token for the forms.
+	Token string
+	// Kind picks the part of the template: ask, status, nothing or error.
+	Kind string
+	// Title is the group title.
+	Title string
+	// Rows are the models.
+	Rows []retestRow
+	// WillCount is how many models will be tested.
+	WillCount int
+	// Running is true while the job runs.
+	Running bool
+	// StopAsked is true after the stop request.
+	StopAsked bool
+	// Done is true when the job has ended.
+	Done bool
+	// Finished is the time the job ended.
+	Finished string
+	// Counts is the sentence that sums up the progress.
+	Counts string
+	// Detail is the plain reason of an error.
+	Detail string
+	// Models are the names that the confirmation form passes on.
+	Models []string
+	// SittingHours is the number of hours within which tests count as made in one sitting, as the comparison page uses it.
+	SittingHours int
+} // end of retestPage
+
+// latestRunOf finds the newest saved test of a model with the current prompt, or reports that there is none.
+func latestRunOf(store *perfStore, name, kind string) (perfRun, bool) {
+	// Newest first.
+	for _, r := range store.forModel(name, kind) {
+		// Only tests with the current prompt can be compared.
+		if r.PromptVersion == perfPromptVersion {
+			// Found it.
+			return r, true
+		} // end of the prompt check
+	} // end of the loop
+	// None.
+	return perfRun{}, false
+} // end of latestRunOf
+
+// retestRows works out, for each wanted model, what the re-test would do now: the model must be installed, not loaded, and of a kind that can be tested; the second value is how many will be tested.
+func retestRows(names []string, installed []installedModel, loaded []loadedModel, store *perfStore) ([]retestRow, int) {
+	// The rows.
+	rows := make([]retestRow, 0, len(names))
+	// How many will be tested.
+	will := 0
+	// Go through the wanted models.
+	for _, name := range names {
+		// The row so far.
+		row := retestRow{Name: name, Last: "not tested yet", CharsKnown: "no"}
+		// Is it installed?
+		m, found := findInstalled(installed, name)
+		// Not installed: nothing to test.
+		if !found {
+			// The reason.
+			row.Will = "No: no longer installed"
+			// Keep the row.
+			rows = append(rows, row)
+			// Next model.
+			continue
+		} // end of the installed check
+		// Which kind of test fits it.
+		cat := categorize(m.Capabilities)
+		// The kind name the store uses.
+		kind := "generate"
+		// An embedding model.
+		if cat == categoryEmbedding {
+			// Its kind.
+			kind = "embedding"
+			// It was kept for the job.
+			row.Embedding = true
+		} // end of the embedding check
+		// Keep what Ollama reports for the test.
+		row.Details = m.Details
+		// What the last test says.
+		if last, ok := latestRunOf(store, name, kind); ok {
+			// Its time.
+			row.Last = formatTime(last.Time)
+			// Embedding tests have no answer text, so the count does not apply.
+			if kind == "embedding" {
+				// Say so.
+				row.CharsKnown = "not applicable"
+			} else if last.AnswerChars > 0 {
+				// The count is there.
+				row.CharsKnown = "yes"
+			} // end of the count check
+		} else if kind == "embedding" {
+			// Nothing saved, and the count does not apply.
+			row.CharsKnown = "not applicable"
+		} // end of the last-test check
+		// A loaded model may be in use, so it is left alone.
+		if _, ok := findLoaded(loaded, name); ok {
+			// The reason.
+			row.Will = "No: loaded in memory now"
+			// Keep the row.
+			rows = append(rows, row)
+			// Next model.
+			continue
+		} // end of the loaded check
+		// Only text, multimodal and embedding models can be tested.
+		if cat != categoryEmbedding && cat != categoryText && cat != categoryMultimodal {
+			// The reason.
+			row.Will = "No: this kind of model cannot be tested"
+			// Keep the row.
+			rows = append(rows, row)
+			// Next model.
+			continue
+		} // end of the kind check
+		// It will be tested.
+		row.Will = "Yes"
+		// Count it.
+		will++
+		// Keep the row.
+		rows = append(rows, row)
+	} // end of the loop
+	// Hand them back.
+	return rows, will
+} // end of retestRows
+
+// counts sums up the progress in one sentence; the caller holds the lock.
+func (j *retestJob) counts() string {
+	// The numbers.
+	var done, failed, skipped, stopped, waiting int
+	// Go through the rows.
+	for _, r := range j.Rows {
+		// Count by state.
+		switch r.State {
+		// Finished well.
+		case "done":
+			// One more.
+			done++
+		// Finished badly.
+		case "failed":
+			// One more.
+			failed++
+		// Left out.
+		case "skipped":
+			// One more.
+			skipped++
+		// Not started because of the stop request.
+		case "stopped":
+			// One more.
+			stopped++
+		// Still to do, or being tested.
+		default:
+			// One more.
+			waiting++
+		} // end of the state switch
+	} // end of the loop
+	// The sentence.
+	return fmt.Sprintf("%d tested, %d failed, %d skipped, %d not started because you stopped, %d still to do.", done, failed, skipped, stopped, waiting)
+} // end of counts
+
+// snapshot copies the job into a page under the lock, so the template never races the background work.
+func (j *retestJob) snapshot(p retestPage) retestPage {
+	// One at a time.
+	j.mu.Lock()
+	// Release at the end.
+	defer j.mu.Unlock()
+	// Copy what the page shows.
+	p.Title, p.Running, p.StopAsked, p.Done = j.Title, j.Running, j.StopAsked, !j.Running
+	// A copy of the rows, so later changes cannot reach the template.
+	p.Rows = append([]retestRow(nil), j.Rows...)
+	// The sentence.
+	p.Counts = j.counts()
+	// When it ended.
+	if !j.Finished.IsZero() {
+		// The time with its zone.
+		p.Finished = formatTime(j.Finished)
+	} // end of the finished check
+	// Hand it back.
+	return p
+} // end of snapshot
+
+// setState changes one row under the lock.
+func (j *retestJob) setState(i int, state, note string) {
+	// One at a time.
+	j.mu.Lock()
+	// Release at the end.
+	defer j.mu.Unlock()
+	// Change it.
+	j.Rows[i].State, j.Rows[i].Note = state, note
+} // end of setState
+
+// stopAsked tells whether the person asked to stop after the current model.
+func (j *retestJob) stopAsked() bool {
+	// One at a time.
+	j.mu.Lock()
+	// Release at the end.
+	defer j.mu.Unlock()
+	// The answer.
+	return j.StopAsked
+} // end of stopAsked
+
+// retestHandlers builds the four handlers of the group re-test: the confirmation page (changes nothing), the start, the progress page, and the request to stop after the current model.
+func retestHandlers(addr ollamaAddress, token string, store *perfStore) (ask, start, status, stop http.HandlerFunc) {
+	// Read the template once; Must stops the program at start-up if it is broken, which a test would catch first.
+	page := template.Must(template.New("retest").Parse(retestTemplateText))
+	// The latest job, or nil when none was started since the monitor started.
+	var current *retestJob
+	// Protects the pointer above.
+	var currentMu sync.Mutex
+	// show builds the page in memory first, so a template error gives a clean 500 and not a half page.
+	show := func(w http.ResponseWriter, r *http.Request, code int, p retestPage) {
+		// Add what every page needs.
+		p.Theme, p.Token, p.Size = themeFromRequest(r), token, sizeFromRequest(r)
+		// The sitting limit of the comparison page, so the two pages never disagree.
+		p.SittingHours = cmpSameSittingHours
+		// Build the page.
+		var buf bytes.Buffer
+		// Run the template.
+		if err := page.Execute(&buf, p); err != nil {
+			// Log the real reason for the person running the program.
+			log.Printf("re-test page error: %v", err)
+			// Send a plain 500 without details.
+			http.Error(w, "internal error", http.StatusInternalServerError)
+			// Stop here.
+			return
+		} // end of the template check
+		// Tell the browser this is an HTML page.
+		w.Header().Set("Content-Type", "text/html; charset=utf-8")
+		// Send the status line.
+		w.WriteHeader(code)
+		// Send the finished page.
+		w.Write(buf.Bytes())
+	} // end of show
+	// readNames runs the shared form checks and returns the title and the model names; ok is false after a refusal was sent.
+	readNames := func(w http.ResponseWriter, r *http.Request) (string, []string, bool) {
+		// The checks every model form shares (same page, token); the single model field is not used here.
+		r.Body = http.MaxBytesReader(w, r.Body, retestFormLimit)
+		// Only the monitor's own page may ask.
+		if !sameOrigin(r) {
+			// Refuse.
+			http.Error(w, "request did not come from this page", http.StatusForbidden)
+			// Stop here.
+			return "", nil, false
+		} // end of the origin check
+		// Read the form.
+		if err := r.ParseForm(); err != nil {
+			// Refuse.
+			http.Error(w, "bad form", http.StatusBadRequest)
+			// Stop here.
+			return "", nil, false
+		} // end of the form check
+		// The token proves the form came from a page this monitor made.
+		if !tokenValid(token, r.PostFormValue("token")) {
+			// Refuse.
+			http.Error(w, "bad token", http.StatusForbidden)
+			// Stop here.
+			return "", nil, false
+		} // end of the token check
+		// The title is only shown back; keep it short.
+		title := strings.TrimSpace(r.PostFormValue("title"))
+		// Too long.
+		if len(title) > maxRetestTitle {
+			// Refuse.
+			http.Error(w, "bad title", http.StatusBadRequest)
+			// Stop here.
+			return "", nil, false
+		} // end of the title check
+		// The names, each only once.
+		var names []string
+		// Remember which were seen.
+		seen := map[string]bool{}
+		// Go through the fields.
+		for _, n := range r.PostForm["model"] {
+			// A bad name.
+			if n == "" || len(n) > maxModelNameLen {
+				// Refuse.
+				http.Error(w, "bad model name", http.StatusBadRequest)
+				// Stop here.
+				return "", nil, false
+			} // end of the name check
+			// Keep each name once.
+			if !seen[n] {
+				// Remember it.
+				seen[n] = true
+				// Keep it.
+				names = append(names, n)
+			} // end of the duplicate check
+		} // end of the loop
+		// Nothing to test, or far too much.
+		if len(names) == 0 || len(names) > maxRetestModels {
+			// Refuse.
+			http.Error(w, "bad number of models", http.StatusBadRequest)
+			// Stop here.
+			return "", nil, false
+		} // end of the count check
+		// All good.
+		return title, names, true
+	} // end of readNames
+	// plan reads what Ollama has now and works out the rows; ok is false after an error page was shown.
+	plan := func(w http.ResponseWriter, r *http.Request, title string, names []string) ([]retestRow, int, bool) {
+		// What is installed now.
+		installed, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
+		// Ollama could not be read.
+		if err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusBadGateway, retestPage{Kind: "error", Title: title, Detail: err.Error()})
+			// Stop here.
+			return nil, 0, false
+		} // end of the installed check
+		// What is loaded now.
+		loaded, err := fetchLoaded(r.Context(), addr.URL, defaultCheckTimeout)
+		// Ollama could not be read.
+		if err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusBadGateway, retestPage{Kind: "error", Title: title, Detail: err.Error()})
+			// Stop here.
+			return nil, 0, false
+		} // end of the loaded check
+		// The rows.
+		rows, will := retestRows(names, installed, loaded, store)
+		// Hand them back.
+		return rows, will, true
+	} // end of plan
+	// ask is the first step: it shows what would be tested and changes nothing.
+	ask = func(w http.ResponseWriter, r *http.Request) {
+		// The form checks.
+		title, names, ok := readNames(w, r)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the checks
+		// What would happen.
+		rows, will, ok := plan(w, r, title, names)
+		// An error page was already shown.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the plan check
+		// Nothing can be tested.
+		if will == 0 {
+			// Say so, with the reasons.
+			show(w, r, http.StatusOK, retestPage{Kind: "nothing", Title: title, Rows: rows})
+			// Stop here.
+			return
+		} // end of the empty check
+		// Only the names that will be tested are passed on.
+		var pass []string
+		// Pick them.
+		for _, row := range rows {
+			// One that will be tested.
+			if row.Will == "Yes" {
+				// Pass it on.
+				pass = append(pass, row.Name)
+			} // end of the pick check
+		} // end of the loop
+		// Show the question.
+		show(w, r, http.StatusOK, retestPage{Kind: "ask", Title: title, Rows: rows, WillCount: will, Models: pass})
+	} // end of ask
+	// start is the second step: it starts the background work and sends the browser to the progress page.
+	start = func(w http.ResponseWriter, r *http.Request) {
+		// The form checks.
+		title, names, ok := readNames(w, r)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the checks
+		// One job at a time.
+		currentMu.Lock()
+		// A job that is still running keeps going; the person is shown it instead of a second one.
+		if current != nil {
+			// Look at it.
+			current.mu.Lock()
+			// Is it running?
+			busy := current.Running
+			// Release it.
+			current.mu.Unlock()
+			// Running.
+			if busy {
+				// Release the pointer.
+				currentMu.Unlock()
+				// Show the running job.
+				http.Redirect(w, r, "/compare/retest/status", http.StatusSeeOther)
+				// Stop here.
+				return
+			} // end of the busy check
+		} // end of the current check
+		// What would happen now.
+		rows, will, ok := plan(w, r, title, names)
+		// An error page was already shown.
+		if !ok {
+			// Release the pointer.
+			currentMu.Unlock()
+			// Stop here.
+			return
+		} // end of the plan check
+		// Nothing can be tested.
+		if will == 0 {
+			// Release the pointer.
+			currentMu.Unlock()
+			// Say so, with the reasons.
+			show(w, r, http.StatusOK, retestPage{Kind: "nothing", Title: title, Rows: rows})
+			// Stop here.
+			return
+		} // end of the empty check
+		// The job: every model starts waiting or skipped.
+		job := &retestJob{Title: title, Rows: rows, Running: true}
+		// Set the starting states.
+		for i := range job.Rows {
+			// A model that will be tested waits; the others were left out already.
+			if job.Rows[i].Will == "Yes" {
+				// Waiting.
+				job.Rows[i].State = "waiting"
+			} else {
+				// Skipped, with the reason.
+				job.Rows[i].State, job.Rows[i].Note = "skipped", strings.TrimPrefix(job.Rows[i].Will, "No: ")
+			} // end of the state choice
+		} // end of the loop
+		// It is the current job.
+		current = job
+		// Release the pointer.
+		currentMu.Unlock()
+		// The background work, which does not depend on this request.
+		go runRetest(addr, store, job)
+		// Show the progress page.
+		http.Redirect(w, r, "/compare/retest/status", http.StatusSeeOther)
+	} // end of start
+	// status shows the progress; it only reads.
+	status = func(w http.ResponseWriter, r *http.Request) {
+		// The job.
+		currentMu.Lock()
+		// Copy the pointer.
+		job := current
+		// Release the pointer.
+		currentMu.Unlock()
+		// No job since the monitor started.
+		if job == nil {
+			// Say so.
+			show(w, r, http.StatusOK, retestPage{Kind: "none"})
+			// Stop here.
+			return
+		} // end of the none check
+		// Show it.
+		show(w, r, http.StatusOK, job.snapshot(retestPage{Kind: "status"}))
+	} // end of status
+	// stop asks the job to stop after the model that is being tested.
+	stop = func(w http.ResponseWriter, r *http.Request) {
+		// The same checks as every form (the model fields are not used).
+		if !readStopForm(w, r, token) {
+			// A refusal was already sent.
+			return
+		} // end of the checks
+		// The job.
+		currentMu.Lock()
+		// Copy the pointer.
+		job := current
+		// Release the pointer.
+		currentMu.Unlock()
+		// A job that runs.
+		if job != nil {
+			// One at a time.
+			job.mu.Lock()
+			// Remember the request.
+			job.StopAsked = job.Running
+			// Release it.
+			job.mu.Unlock()
+		} // end of the job check
+		// Back to the progress page.
+		http.Redirect(w, r, "/compare/retest/status", http.StatusSeeOther)
+	} // end of stop
+	// Hand the four handlers back.
+	return ask, start, status, stop
+} // end of retestHandlers
+
+// readStopForm runs the checks of the stop request: same page, small form, valid token.
+func readStopForm(w http.ResponseWriter, r *http.Request, token string) bool {
+	// The request carries almost nothing.
+	r.Body = http.MaxBytesReader(w, r.Body, 1024)
+	// Only the monitor's own page may ask.
+	if !sameOrigin(r) {
+		// Refuse.
+		http.Error(w, "request did not come from this page", http.StatusForbidden)
+		// Stop here.
+		return false
+	} // end of the origin check
+	// Read the form.
+	if err := r.ParseForm(); err != nil {
+		// Refuse.
+		http.Error(w, "bad form", http.StatusBadRequest)
+		// Stop here.
+		return false
+	} // end of the form check
+	// The token proves the form came from a page this monitor made.
+	if !tokenValid(token, r.PostFormValue("token")) {
+		// Refuse.
+		http.Error(w, "bad token", http.StatusForbidden)
+		// Stop here.
+		return false
+	} // end of the token check
+	// All good.
+	return true
+} // end of readStopForm
+
+// runRetest tests the models of the job one after another; it runs in the background and ends the job when it is done.
+func runRetest(addr ollamaAddress, store *perfStore, job *retestJob) {
+	// The context of the whole job; the Stop page of the monitor can cancel it.
+	ctx, cancel := context.WithCancel(context.Background())
+	// Tell the Stop page that work is running, and how to undo it: cancel the job and unload the model it is testing.
+	end := activeWork.begin("a re-test of the group "+job.Title+" (Stop cancels it and unloads the model first)", func(c context.Context) {
+		// Cancel the model that is being tested.
+		cancel()
+		// Find the model being tested right now; the others are not loaded by this job.
+		job.mu.Lock()
+		// The name.
+		current := ""
+		// Look.
+		for _, r := range job.Rows {
+			// The one in progress.
+			if r.State == "testing" {
+				// Keep it.
+				current = r.Name
+			} // end of the state check
+		} // end of the loop
+		// Release it.
+		job.mu.Unlock()
+		// Ask Ollama to unload it; the answer does not matter here.
+		if current != "" {
+			// Unload.
+			unloadModel(c, addr.URL, current, defaultCheckTimeout)
+			// Wait until it is really gone, within the time limit.
+			waitUntilGone(c, addr.URL, current, defaultCheckTimeout)
+		} // end of the current check
+	}) // end of begin
+	// Whatever happens, the work ends and the job is marked finished.
+	defer func() {
+		// Release the context.
+		cancel()
+		// Forget the work.
+		end()
+		// One at a time.
+		job.mu.Lock()
+		// Not running any more.
+		job.Running = false
+		// The time.
+		job.Finished = time.Now()
+		// Release it.
+		job.mu.Unlock()
+	}() // end of the deferred function
+	// Go through the models.
+	for i := range job.Rows {
+		// A model that was left out at the start.
+		if job.Rows[i].State != "waiting" {
+			// Next model.
+			continue
+		} // end of the skip check
+		// The person asked to stop, or the monitor is stopping: the rest is not started.
+		if job.stopAsked() || ctx.Err() != nil {
+			// Mark it.
+			job.setState(i, "stopped", "")
+			// Next model.
+			continue
+		} // end of the stop check
+		// Only one test at a time, also against a single test the person started by hand.
+		testLock.Lock()
+		// Test this one.
+		testOne(ctx, addr, store, job, i)
+		// Let the next test start.
+		testLock.Unlock()
+	} // end of the loop
+} // end of runRetest
+
+// testOne tests one model of the job and saves the result; the caller holds testLock.
+func testOne(ctx context.Context, addr ollamaAddress, store *perfStore, job *retestJob, i int) {
+	// The row as it is.
+	job.mu.Lock()
+	// A copy.
+	row := job.Rows[i]
+	// Release it.
+	job.mu.Unlock()
+	// It is being tested now.
+	job.setState(i, "testing", "")
+	// Look again at what is loaded, because time has passed since the question was answered.
+	loaded, err := fetchLoaded(ctx, addr.URL, defaultCheckTimeout)
+	// Ollama could not be read.
+	if err != nil {
+		// Report it.
+		job.setState(i, "failed", err.Error())
+		// Stop here.
+		return
+	} // end of the loaded check
+	// A model that is loaded now may be in use.
+	if _, ok := findLoaded(loaded, row.Name); ok {
+		// Leave it alone.
+		job.setState(i, "skipped", "loaded in memory now")
+		// Stop here.
+		return
+	} // end of the in-use check
+	// The Ollama version, for the record.
+	version := checkOllama(ctx, addr.URL, defaultCheckTimeout).Version
+	// Run the test.
+	res, err := performTest(ctx, addr.URL, row.Name, row.Embedding, version, row.Details)
+	// The test failed.
+	if err != nil {
+		// Report it with the plain reason.
+		job.setState(i, "failed", err.Error())
+		// Stop here.
+		return
+	} // end of the failure check
+	// Save the numbers; a save problem is reported on the row.
+	if saveErr := store.add(res); saveErr != nil {
+		// Say so.
+		job.setState(i, "done", "tested, but the result could not be saved: "+saveErr.Error())
+		// Stop here.
+		return
+	} // end of the save check
+	// Done.
+	job.setState(i, "done", "")
+} // end of testOne
diff --git a/retest_test.go b/retest_test.go
new file mode 100644
index 0000000..c400594
--- /dev/null
+++ b/retest_test.go
@@ -0,0 +1,434 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// fmt builds names and texts.
+	"fmt"
+	// net/http provides the method names and status codes.
+	"net/http"
+	// net/url builds the forms.
+	"net/url"
+	// strings searches the pages.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+	// time sets the waiting limit.
+	"time"
+) // end of imports
+
+// retestForm builds the form the button of a group sends.
+func retestForm(rig themeRig, title string, models ...string) url.Values {
+	// The token, the title and one field for each model.
+	return url.Values{"token": {rig.token}, "title": {title}, "model": models}
+} // end of retestForm
+
+// waitForEnd polls the progress page until the re-test has ended, and returns that page.
+func waitForEnd(t *testing.T, rig themeRig) string {
+	// Mark this as a helper.
+	t.Helper()
+	// Give it ten seconds; the fake answers at once.
+	deadline := time.Now().Add(10 * time.Second)
+	// Ask again and again.
+	for time.Now().Before(deadline) {
+		// The page.
+		_, _, body := get(t, rig.h, http.MethodGet, "/compare/retest/status")
+		// It has ended.
+		if strings.Contains(body, "has ended") {
+			// Hand it back.
+			return body
+		} // end of the end check
+		// A short pause.
+		time.Sleep(20 * time.Millisecond)
+	} // end of the loop
+	// Never ended.
+	t.Fatalf("the re-test did not end in time")
+	// Not reached.
+	return ""
+} // end of waitForEnd
+
+// TestCompareShowsTheRetestButton checks the button appears for a group of two or more models still installed, carries their names, and not for a group of one.
+func TestCompareShowsTheRetestButton(t *testing.T) {
+	// A fake and a rig.
+	f := newPerfFake()
+	// Build the rig.
+	rig, _ := perfRig(t, f)
+	// Test three models so the page has a group of two and a group of one.
+	for _, m := range []string{"chat:1b", "think:1b", "embed:1b"} {
+		// Run one test.
+		if status, body, _ := perfPost(t, rig, "/performance/run", m); status != http.StatusOK {
+			// Stop the test.
+			t.Fatalf("test of %s: status %d %s", m, status, body)
+		} // end of the status check
+	} // end of the loop
+	// The comparison page.
+	res := post(t, rig.h, "/compare", url.Values{"token": {rig.token}}, fromThisPage)
+	// Its text.
+	body := bodyOf(res)
+	// The two chat models share a group, so there is one button, for two models.
+	if n := strings.Count(body, `action="/compare/retest"`); n != 1 {
+		// Report the problem.
+		t.Fatalf("%d re-test buttons, want 1", n)
+	} // end of the count check
+	// What the button must carry.
+	for _, want := range []string{"Re-test this group (2 models)", `name="model" value="chat:1b"`, `name="model" value="think:1b"`, `name="token" value="` + rig.token + `"`} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("the compare page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// The lone embedding model gets no button.
+	if strings.Contains(body, `name="model" value="embed:1b"`) {
+		// Report the problem.
+		t.Errorf("a group of one has a re-test button")
+	} // end of the single check
+	// The page still runs no script.
+	if strings.Contains(body, "<script") {
+		// Report the problem.
+		t.Errorf("the compare page has a script")
+	} // end of the script check
+} // end of TestCompareShowsTheRetestButton
+
+// TestRetestAskListsWhatWillHappen checks the confirmation page: it changes nothing, lists every model, and says why a loaded or missing model is left out.
+func TestRetestAskListsWhatWillHappen(t *testing.T) {
+	// A fake with one model already loaded.
+	f := newPerfFake()
+	// think:1b is in memory now.
+	f.loaded["think:1b"] = true
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// Ask about three models, one of which is not installed.
+	res := post(t, rig.h, "/compare/retest", retestForm(rig, `Chat <b>group</b>`, "chat:1b", "think:1b", "gone:1b"), fromThisPage)
+	// Its text.
+	body := bodyOf(res)
+	// The page was shown.
+	if res.StatusCode != http.StatusOK {
+		// Stop the test.
+		t.Fatalf("status %d: %s", res.StatusCode, body)
+	} // end of the status check
+	// What it must say.
+	for _, want := range []string{"Re-test the group", "Yes, re-test 1 model</button>", "No: loaded in memory now", "No: no longer installed", `action="/compare/retest/run"`, `name="model" value="chat:1b"`, "Cancel, do not test", fmt.Sprintf("%d-hour limit", cmpSameSittingHours)} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("the page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// Only the model that will be tested is passed on.
+	if strings.Contains(body, `name="model" value="think:1b"`) || strings.Contains(body, `name="model" value="gone:1b"`) {
+		// Report the problem.
+		t.Errorf("a model that will not be tested is passed on")
+	} // end of the pass-on check
+	// The title is shown escaped.
+	if strings.Contains(body, "<b>group</b>") {
+		// Report the problem.
+		t.Errorf("the title was not escaped")
+	} // end of the escape check
+	// Nothing was tested and nothing saved.
+	if f.calls() != 0 || len(savedRuns(t, hist)) != 0 {
+		// Report the problem.
+		t.Errorf("the confirmation page changed something")
+	} // end of the change check
+	// Only unusable models: a page that says so, without the button.
+	res = post(t, rig.h, "/compare/retest", retestForm(rig, "x", "think:1b", "gone:1b"), fromThisPage)
+	// Its text.
+	body = bodyOf(res)
+	// The notes.
+	if !strings.Contains(body, "Nothing to re-test") || strings.Contains(body, `action="/compare/retest/run"`) {
+		// Report the problem.
+		t.Errorf("an empty re-test offers to start: %s", body)
+	} // end of the empty check
+} // end of TestRetestAskListsWhatWillHappen
+
+// TestRetestRunsEveryModelAndSaves checks the whole run: the redirect, the progress page, one new saved result for each model, nothing of the answers on a page, and a finished page without refresh.
+func TestRetestRunsEveryModelAndSaves(t *testing.T) {
+	// A fake.
+	f := newPerfFake()
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// Start the re-test of two models.
+	res := post(t, rig.h, "/compare/retest/run", retestForm(rig, "Chat", "chat:1b", "think:1b"), fromThisPage)
+	// The browser is sent to the progress page.
+	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/compare/retest/status" {
+		// Stop the test.
+		t.Fatalf("start: status %d, location %q", res.StatusCode, res.Header.Get("Location"))
+	} // end of the redirect check
+	// Wait for the end.
+	body := waitForEnd(t, rig)
+	// Both were tested.
+	if n := strings.Count(body, "Tested"); n < 2 || !strings.Contains(body, "2 tested, 0 failed, 0 skipped, 0 not started because you stopped, 0 still to do.") {
+		// Report the problem.
+		t.Errorf("the finished page is wrong: %s", body)
+	} // end of the result check
+	// The finished page does not refresh itself and offers the comparison.
+	if strings.Contains(body, `http-equiv="refresh"`) || !strings.Contains(body, `action="/compare"`) || strings.Contains(body, "Stop after this model") {
+		// Report the problem.
+		t.Errorf("the finished page has the wrong controls")
+	} // end of the controls check
+	// Two results were saved, one for each model.
+	runs := savedRuns(t, hist)
+	// Count them.
+	if len(runs) != 2 {
+		// Stop the test.
+		t.Fatalf("%d saved runs, want 2", len(runs))
+	} // end of the saved check
+	// They carry the answer length, which is the point of the re-test.
+	for _, r := range runs {
+		// A character count must be there.
+		if r.AnswerChars == 0 {
+			// Report the problem.
+			t.Errorf("%s has no answer length", r.Model)
+		} // end of the count check
+	} // end of the loop
+	// No answer text anywhere.
+	if strings.Contains(body, secretText) {
+		// Report the problem.
+		t.Errorf("answer text reached the page")
+	} // end of the secret check
+	// No model is left in memory.
+	if f.isLoaded("chat:1b") || f.isLoaded("think:1b") {
+		// Report the problem.
+		t.Errorf("a model was left loaded")
+	} // end of the loaded check
+	// The page runs no script.
+	if strings.Contains(body, "<script") {
+		// Report the problem.
+		t.Errorf("the progress page has a script")
+	} // end of the script check
+} // end of TestRetestRunsEveryModelAndSaves
+
+// TestRetestStopAfterThisModel checks the stop button: the model being tested finishes, the next one is not started, and the page says so.
+func TestRetestStopAfterThisModel(t *testing.T) {
+	// A fake that holds the first test request.
+	f := newPerfFake()
+	// Hold it.
+	f.hold, f.entered, f.release = true, make(chan struct{}, 1), make(chan struct{})
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// Start the re-test of two models.
+	post(t, rig.h, "/compare/retest/run", retestForm(rig, "Chat", "chat:1b", "think:1b"), fromThisPage)
+	// Wait until the first model is inside the request.
+	<-f.entered
+	// The progress page while it runs.
+	_, _, running := get(t, rig.h, http.MethodGet, "/compare/retest/status")
+	// It refreshes itself, shows the stop button and the state of the models.
+	for _, want := range []string{`http-equiv="refresh" content="5"`, "Stop after this model", "Testing now", "Waiting", "Re-testing the group"} {
+		// Look for it.
+		if !strings.Contains(running, want) {
+			// Report the gap.
+			t.Errorf("the running page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// A second start while one runs does not begin another job.
+	again := post(t, rig.h, "/compare/retest/run", retestForm(rig, "Chat", "chat:1b", "think:1b"), fromThisPage)
+	// It is sent to the running job.
+	if again.StatusCode != http.StatusSeeOther {
+		// Report the problem.
+		t.Errorf("second start: status %d", again.StatusCode)
+	} // end of the second start check
+	// Ask to stop.
+	stop := post(t, rig.h, "/compare/retest/stop", url.Values{"token": {rig.token}}, fromThisPage)
+	// Back to the progress page.
+	if stop.StatusCode != http.StatusSeeOther {
+		// Report the problem.
+		t.Errorf("stop: status %d", stop.StatusCode)
+	} // end of the stop check
+	// The page now says so, and the stop button is gone.
+	_, _, asked := get(t, rig.h, http.MethodGet, "/compare/retest/status")
+	// Check it.
+	if !strings.Contains(asked, "You asked to stop") || strings.Contains(asked, "Stop after this model") {
+		// Report the problem.
+		t.Errorf("the page after the stop request is wrong")
+	} // end of the asked check
+	// Let the first model finish.
+	close(f.release)
+	// Wait for the end.
+	body := waitForEnd(t, rig)
+	// One tested, one not started.
+	if !strings.Contains(body, "1 tested, 0 failed, 0 skipped, 1 not started because you stopped, 0 still to do.") || !strings.Contains(body, "Not started (you stopped)") {
+		// Report the problem.
+		t.Errorf("the ended page is wrong: %s", body)
+	} // end of the result check
+	// Only one result was saved.
+	if n := len(savedRuns(t, hist)); n != 1 {
+		// Report the problem.
+		t.Errorf("%d saved runs, want 1", n)
+	} // end of the saved check
+} // end of TestRetestStopAfterThisModel
+
+// TestRetestOneFailureDoesNotStopTheRest checks a failing test is reported on its row and the others go on.
+func TestRetestOneFailureDoesNotStopTheRest(t *testing.T) {
+	// A fake whose first test request fails.
+	f := newPerfFake()
+	// The first request fails.
+	f.failAt = 1
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// Start the re-test of two models.
+	post(t, rig.h, "/compare/retest/run", retestForm(rig, "Chat", "chat:1b", "think:1b"), fromThisPage)
+	// Wait for the end.
+	body := waitForEnd(t, rig)
+	// One failed, one tested.
+	if !strings.Contains(body, "1 tested, 1 failed, 0 skipped, 0 not started because you stopped, 0 still to do.") {
+		// Report the problem.
+		t.Errorf("the ended page is wrong: %s", body)
+	} // end of the result check
+	// Only the good one was saved.
+	if n := len(savedRuns(t, hist)); n != 1 {
+		// Report the problem.
+		t.Errorf("%d saved runs, want 1", n)
+	} // end of the saved check
+} // end of TestRetestOneFailureDoesNotStopTheRest
+
+// TestRetestFormsAreChecked checks the new forms refuse a wrong token, a form from another site, no models, too many models, a bad name and an over-long title; and that the progress page needs no form.
+func TestRetestFormsAreChecked(t *testing.T) {
+	// A fake and a rig.
+	f := newPerfFake()
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// Many names.
+	many := make([]string, maxRetestModels+1)
+	// Fill them.
+	for i := range many {
+		// A name.
+		many[i] = fmt.Sprintf("m%d:1b", i)
+	} // end of the loop
+	// The cases.
+	cases := map[string]struct {
+		form    url.Values
+		headers map[string]string
+		want    int
+	}{
+		// A wrong token.
+		"wrong token": {url.Values{"token": {"0123456789abcdef0123456789abcdef"}, "model": {"chat:1b"}}, fromThisPage, http.StatusForbidden},
+		// Another site.
+		"other site": {retestForm(rig, "x", "chat:1b"), map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
+		// No model.
+		"no model": {retestForm(rig, "x"), fromThisPage, http.StatusBadRequest},
+		// An empty name.
+		"empty name": {retestForm(rig, "x", ""), fromThisPage, http.StatusBadRequest},
+		// A very long name.
+		"long name": {retestForm(rig, "x", strings.Repeat("a", maxModelNameLen+1)), fromThisPage, http.StatusBadRequest},
+		// A very long title.
+		"long title": {retestForm(rig, strings.Repeat("t", maxRetestTitle+1), "chat:1b"), fromThisPage, http.StatusBadRequest},
+		// Too many models.
+		"too many": {retestForm(rig, "x", many...), fromThisPage, http.StatusBadRequest},
+	} // end of the cases
+	// Both POST routes that take models.
+	for _, path := range []string{"/compare/retest", "/compare/retest/run"} {
+		// Each case.
+		for name, c := range cases {
+			// Send it.
+			res := post(t, rig.h, path, c.form, c.headers)
+			// The answer.
+			if res.StatusCode != c.want {
+				// Report the problem.
+				t.Errorf("%s %s: status %d, want %d", path, name, res.StatusCode, c.want)
+			} // end of the status check
+		} // end of the case loop
+	} // end of the path loop
+	// The stop route checks token and origin too.
+	if res := post(t, rig.h, "/compare/retest/stop", url.Values{"token": {"0123456789abcdef0123456789abcdef"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
+		// Report the problem.
+		t.Errorf("stop with a wrong token: status %d", res.StatusCode)
+	} // end of the stop token check
+	// A page asked for with GET cannot start or stop anything.
+	for _, path := range []string{"/compare/retest", "/compare/retest/run", "/compare/retest/stop"} {
+		// Ask.
+		status, _, _ := get(t, rig.h, http.MethodGet, path)
+		// Only the progress route answers GET.
+		if status == http.StatusOK {
+			// Report the problem.
+			t.Errorf("GET %s answered 200", path)
+		} // end of the status check
+	} // end of the loop
+	// Nothing was tested by any refused request.
+	if f.calls() != 0 || len(savedRuns(t, hist)) != 0 {
+		// Report the problem.
+		t.Errorf("a refused request changed something")
+	} // end of the change check
+	// The progress page with no job says so.
+	_, _, none := get(t, rig.h, http.MethodGet, "/compare/retest/status")
+	// Check it.
+	if !strings.Contains(none, "No re-test has been started") {
+		// Report the problem.
+		t.Errorf("the empty progress page is wrong: %s", none)
+	} // end of the none check
+} // end of TestRetestFormsAreChecked
+
+// TestRetestSkipsAModelLoadedMeanwhile checks the loaded check is made again just before each model: a model that someone loaded after the question was answered is left alone.
+func TestRetestSkipsAModelLoadedMeanwhile(t *testing.T) {
+	// A fake that holds the first test request.
+	f := newPerfFake()
+	// Hold it.
+	f.hold, f.entered, f.release = true, make(chan struct{}, 1), make(chan struct{})
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// Start the re-test of two models; both are free now.
+	post(t, rig.h, "/compare/retest/run", retestForm(rig, "Chat", "chat:1b", "think:1b"), fromThisPage)
+	// Wait until the first model is inside the request.
+	<-f.entered
+	// Someone loads the second model meanwhile.
+	f.mu.Lock()
+	// It is in memory.
+	f.loaded["think:1b"] = true
+	// Release the fake.
+	f.mu.Unlock()
+	// Let the first model finish.
+	close(f.release)
+	// Wait for the end.
+	body := waitForEnd(t, rig)
+	// The second was skipped, with the reason.
+	if !strings.Contains(body, "1 tested, 0 failed, 1 skipped, 0 not started because you stopped, 0 still to do.") || !strings.Contains(body, "loaded in memory now") {
+		// Report the problem.
+		t.Errorf("the ended page is wrong: %s", body)
+	} // end of the result check
+	// Only the first was saved, and the loaded model was left in memory.
+	if n := len(savedRuns(t, hist)); n != 1 || !f.isLoaded("think:1b") {
+		// Report the problem.
+		t.Errorf("%d saved runs, think loaded %v", n, f.isLoaded("think:1b"))
+	} // end of the saved check
+} // end of TestRetestSkipsAModelLoadedMeanwhile
+
+// TestRetestWaitsForASingleTest checks the group re-test never runs at the same time as a single test the person started by hand.
+func TestRetestWaitsForASingleTest(t *testing.T) {
+	// A fake that holds the first test request.
+	f := newPerfFake()
+	// Hold it.
+	f.hold, f.entered, f.release = true, make(chan struct{}, 1), make(chan struct{})
+	// Build the rig.
+	rig, hist := perfRig(t, f)
+	// The single test runs in the background.
+	done := make(chan struct{})
+	// Start it.
+	go func() {
+		// Run.
+		perfPost(t, rig, "/performance/run", "chat:1b")
+		// Report.
+		close(done)
+	}() // end of the goroutine
+	// Wait until it is inside the model request.
+	<-f.entered
+	// Start the group re-test of the other model.
+	post(t, rig.h, "/compare/retest/run", retestForm(rig, "Chat", "think:1b"), fromThisPage)
+	// Give the job time to do something wrong.
+	time.Sleep(150 * time.Millisecond)
+	// It must be waiting, and must not have sent a request of its own.
+	_, _, waiting := get(t, rig.h, http.MethodGet, "/compare/retest/status")
+	// Check it.
+	if !strings.Contains(waiting, "Waiting") || strings.Contains(waiting, "Testing now") || f.calls() != 1 {
+		// Report the problem.
+		t.Errorf("the re-test did not wait (calls %d): %s", f.calls(), waiting)
+	} // end of the waiting check
+	// Let the single test finish.
+	close(f.release)
+	// Wait for it.
+	<-done
+	// The re-test then runs.
+	body := waitForEnd(t, rig)
+	// Both results are saved.
+	if !strings.Contains(body, "1 tested") || len(savedRuns(t, hist)) != 2 {
+		// Report the problem.
+		t.Errorf("the re-test did not finish after the single test: %s", body)
+	} // end of the result check
+} // end of TestRetestWaitsForASingleTest
diff --git a/web.go b/web.go
index 36490d2..a47f654 100644
--- a/web.go
+++ b/web.go
@@ -191,6 +191,16 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	mux.HandleFunc("POST /performance/clear/model/confirm", perfClearOneDo)
 	// Route: a POST request for "/compare" shows the comparison of the tested models and changes nothing.
 	mux.HandleFunc("POST /compare", compareHandler(addr, token, perfHistory))
+	// The four handlers of the group re-test (retest.go): ask, start, progress, stop.
+	retestAsk, retestStart, retestStatus, retestStop := retestHandlers(addr, token, perfHistory)
+	// Route: a POST request for "/compare/retest" shows which models of a group would be tested again, and changes nothing.
+	mux.HandleFunc("POST /compare/retest", retestAsk)
+	// Route: a POST request for "/compare/retest/run" starts the re-test of the group in the background.
+	mux.HandleFunc("POST /compare/retest/run", retestStart)
+	// Route: a GET request for "/compare/retest/status" shows how far the re-test has got; it only reads.
+	mux.HandleFunc("GET /compare/retest/status", retestStatus)
+	// Route: a POST request for "/compare/retest/stop" asks the re-test to stop after the model being tested.
+	mux.HandleFunc("POST /compare/retest/stop", retestStop)
 	// The two downloads of the comparison: a PDF report and the data as CSV (both carry the notice; the checks are in compreport.go).
 	comparePDF, compareCSV := compareDownloadHandlers(addr, token, perfHistory)
 	// Route: a POST request for "/compare/pdf" sends the comparison as a PDF file.
diff --git a/web/app.css b/web/app.css
index 5759cde..ee230ef 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2025,3 +2025,17 @@ html[data-size="medium"] svg[width="22"] {
   /* The muted colour of the page. */
   color: var(--muted);
 } /* end of rule */
+
+/* The form with the re-test button of a group: button and note side by side, wrapping on a narrow screen. */
+.cmpretest {
+  /* Space above and below. */
+  margin: 0.5rem 0 0.9rem;
+  /* The button and the note sit in a row. */
+  display: flex;
+  /* They wrap on a phone. */
+  flex-wrap: wrap;
+  /* Space between them. */
+  gap: 0.5rem 0.8rem;
+  /* Centre them vertically. */
+  align-items: center;
+} /* end of rule */
diff --git a/web/compare.html b/web/compare.html
index a6a3bd3..5f4388f 100644
--- a/web/compare.html
+++ b/web/compare.html
@@ -46,6 +46,10 @@
 {{if $g.Headline}}<p><strong>{{$g.Headline}}</strong></p>{{end}}
 {{/* Why there is no ranking, or that the model has no peer. */}}
 {{range $g.Notes}}<p class="muted">{{.}}</p>{{end}}
+{{/* The button that tests every model of this group again; it first asks, and changes nothing by itself. */}}
+{{if $g.Retest}}
+<form method="post" action="/compare/retest" class="cmpretest"><input type="hidden" name="token" value="{{$.Token}}"><input type="hidden" name="title" value="{{$g.Title}}">{{range $g.Retest}}<input type="hidden" name="model" value="{{.}}">{{end}}<button type="submit" class="btn-plain">Re-test this group ({{len $g.Retest}} models)</button> <span class="muted">Adds a new result for each model, with the answer length that older results lack.</span></form>
+{{end}}
 {{/* The scroll box, reachable with Tab so keyboard users can scroll the table sideways. */}}
 <div class="scrollbox" tabindex="0" role="region" aria-label="{{$g.Title}}, scrolls sideways">
 <table class="models comparetable">
diff --git a/web/retest.html b/web/retest.html
new file mode 100644
index 0000000..91aff72
--- /dev/null
+++ b/web/retest.html
@@ -0,0 +1,95 @@
+{{/* Re-test of a comparison group: the question before it starts, the progress while it runs, and the notes when nothing can be tested. The comments are template comments, so they never reach the browser. */}}
+<!DOCTYPE html>
+{{/* lang tells screen readers which language the page is written in. */}}
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
+<head>{{/* start of the head. */}}
+{{/* Text encoding. */}}
+<meta charset="utf-8">
+{{/* Fit the page to the width of the screen on phones. */}}
+<meta name="viewport" content="width=device-width, initial-scale=1">
+{{/* While the re-test runs, the page asks again every 5 seconds; when it ends, the page stays as it is. No script is needed. */}}
+{{if and (eq .Kind "status") .Running}}<meta http-equiv="refresh" content="5">{{end}}
+{{/* The title shown on the browser tab. */}}
+<title>Re-test a group - OllamaControlCenter</title>
+{{/* Our one stylesheet. */}}
+<link rel="stylesheet" href="/app.css">
+</head>{{/* end of the head. */}}
+<body>{{/* start of the visible page. */}}
+<main>
+{{/* A panel that holds the page. */}}
+<section class="panel" aria-live="polite">
+{{/* ---- The question before the re-test starts. ---- */}}
+{{if eq .Kind "ask"}}
+<h1>Re-test the group "{{.Title}}"?</h1>
+<p>The models marked Yes are tested one after another. Each one is loaded into memory, tested, and then unloaded. A test usually takes under a minute; a very large model can take several minutes to load. Nothing is tested until you press the button below.</p>
+<p class="muted">Every test adds a new result. The old results stay in the history. Tests made close together in time can be ranked together; a long group can run past the {{.SittingHours}}-hour limit that the comparison page uses.</p>
+{{template "retestrows" .}}
+{{/* The two choices; the second goes back to the monitor page. */}}
+<div class="cmpactions">
+<form method="post" action="/compare/retest/run"><input type="hidden" name="token" value="{{.Token}}"><input type="hidden" name="title" value="{{.Title}}">{{range .Models}}<input type="hidden" name="model" value="{{.}}">{{end}}<button type="submit" class="btn-plain">Yes, re-test {{.WillCount}} {{if eq .WillCount 1}}model{{else}}models{{end}}</button></form>
+<a class="btn-plain" href="/">Cancel, do not test</a>
+</div>
+{{/* ---- Nothing can be tested. ---- */}}
+{{else if eq .Kind "nothing"}}
+<h1>Nothing to re-test in "{{.Title}}"</h1>
+<p>None of these models can be tested right now. A model that is loaded in memory may be in use, so it is left alone; unload it first, then try again.</p>
+{{template "retestrows" .}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* ---- Ollama could not be read. ---- */}}
+{{else if eq .Kind "error"}}
+<h1>The re-test did not start</h1>
+<p role="alert"><span class="symbol" aria-hidden="true">⚠</span> Ollama could not be read: {{.Detail}}</p>
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* ---- No re-test since the monitor started. ---- */}}
+{{else if eq .Kind "none"}}
+<h1>No re-test has been started</h1>
+<p>Nothing has been re-tested since this monitor started. Open the comparison page and use the button of a group.</p>
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* ---- The progress. ---- */}}
+{{else}}
+<h1>{{if .Running}}Re-testing the group "{{.Title}}"{{else}}Re-test of the group "{{.Title}}" has ended{{end}}</h1>
+{{/* What is going on, in words. */}}
+{{if .Running}}
+<p>{{if .StopAsked}}<span class="symbol" aria-hidden="true">⏸</span> You asked to stop: the model being tested finishes, and the others are not started.{{else}}<span class="symbol" aria-hidden="true">▶</span> The models are tested one after another. This page updates itself every 5 seconds.{{end}}</p>
+{{else}}
+<p>Ended at {{.Finished}}. The new results are saved; open the comparison to see them.</p>
+{{end}}
+<p><strong>{{.Counts}}</strong></p>
+{{template "retestrows" .}}
+<div class="cmpactions">
+{{/* While it runs, the stop button; it never cuts a test in half. */}}
+{{if and .Running (not .StopAsked)}}
+<form method="post" action="/compare/retest/stop"><input type="hidden" name="token" value="{{.Token}}"><button type="submit" class="btn-plain">Stop after this model</button></form>
+{{end}}
+{{/* When it has ended, the way to the comparison, which is shown by a form because it is asked for with a page token. */}}
+{{if .Done}}
+<form method="post" action="/compare"><input type="hidden" name="token" value="{{.Token}}"><button type="submit" class="btn-plain">Show the comparison</button></form>
+{{end}}
+<a class="btn-plain" href="/">Back to the monitor</a>
+</div>
+{{end}}
+{{/* End of the panel. */}}
+</section>
+{{/* End of the content. */}}
+</main>
+</body>{{/* end of the visible page. */}}
+</html>{{/* end of the page. */}}
+{{/* The table of models, shared by the three pages; the columns depend on the page. */}}
+{{define "retestrows"}}
+<div class="scrollbox" tabindex="0" role="region" aria-label="Models of the group, scrolls sideways">
+<table class="models comparetable">
+<thead><tr><th scope="col">Model</th><th scope="col">{{if eq .Kind "status"}}Previous test{{else}}Last tested{{end}}</th><th scope="col">{{if eq .Kind "status"}}Answer length known before{{else}}Answer length known{{end}}</th>{{if eq .Kind "status"}}<th scope="col">Progress</th>{{else}}<th scope="col">Will be re-tested?</th>{{end}}</tr></thead>
+<tbody>
+{{range .Rows}}
+<tr><th scope="row">{{.Name}}</th><td>{{.Last}}</td><td>{{.CharsKnown}}</td>
+{{if eq $.Kind "status"}}
+<td>{{if eq .State "done"}}<span class="symbol" aria-hidden="true">✔</span> Tested{{else if eq .State "testing"}}<span class="symbol" aria-hidden="true">▶</span> Testing now{{else if eq .State "failed"}}<span class="symbol" aria-hidden="true">✖</span> Failed{{else if eq .State "skipped"}}<span class="symbol" aria-hidden="true">–</span> Skipped{{else if eq .State "stopped"}}<span class="symbol" aria-hidden="true">⏸</span> Not started (you stopped){{else}}<span class="symbol" aria-hidden="true">…</span> Waiting{{end}}{{if .Note}}: {{.Note}}{{end}}</td>
+{{else}}
+<td>{{.Will}}</td>
+{{end}}
+</tr>
+{{end}}
+</tbody>
+</table>
+</div>
+{{end}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
07a5fb01b7523dae8834e9f79e061ad3f00de93eabb57cfe81231f1a112282ed  about.go
f8b7752f542d3f5b5ddf91ac4d91ccef72664cc8e717ba3a58d34eccbea85197  compare.go
4642af08bc7fd32a61bcf1f80eafc6cc8597a8ef6faf7980d75facf2faedb79b  perfpage.go
d1567af35b277163ba8385dee3a34a8667aba978c9f0bdbdd042a4a194848c0c  web.go
805f05fb25d9d9c74e5fdbf7563171faf8493e46eb86f6020818b10436589a41  web/app.css
42a7ab6a759a3cf7753dee3690549e41ca6f6710079808cce348108299d6598f  web/compare.html
680e0b494310f354f4e3b748329066454cc9ded6ada607ec0bf347a627c7e0ae  retest.go
e546fd7bb6b0bf4ac0ac4854ab059f5d8cf10890d2c1f980d75b24cc2b9e7edb  retest_test.go
1e4f56ed96d567340207425ba0558c5febbf2abec7629021b634804bead863a6  web/retest.html
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
# Tell the person how to use the new command.
echo "NEXT  start ./bin/OllamaControlCenter, open the comparison page, and look for the Re-test this group button"
# List the changed files; nothing is committed yet.
git status --short
