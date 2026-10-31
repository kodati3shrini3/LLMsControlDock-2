// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes builds a page in memory first.
	"bytes"
	// context carries the cancel signal of the background job.
	"context"
	// embed stores the page template inside the executable (the blank name means only the side effect is needed).
	_ "embed"
	// fmt builds the texts.
	"fmt"
	// html/template fills the page and escapes every value.
	"html/template"
	// log reports a template problem to the person running the program.
	"log"
	// net/http provides requests and status codes.
	"net/http"
	// strings tidies the form values.
	"strings"
	// sync protects the job that the background work and the pages share.
	"sync"
	// time gives the clock for the finishing time.
	"time"
) // end of imports

// retestTemplateText is the page of the group re-test, stored inside the executable at build time.
//
//go:embed web/retest.html
var retestTemplateText string

// maxRetestModels is the most models one group re-test may hold; a real group is far smaller.
const maxRetestModels = 40

// maxRetestTitle is the longest group title the forms accept; the title is only shown back, never used.
const maxRetestTitle = 200

// retestFormLimit is the most form data a re-test request may carry (40 names of up to 200 characters, and the rest).
const retestFormLimit = 16 * 1024

// testLock lets only one performance test run at a time: two would disturb each other's figures. The single test and the group re-test share it.
var testLock sync.Mutex

// retestRow is one model on the pages of the group re-test.
type retestRow struct {
	// Name is the model name.
	Name string
	// Last is the time of its latest saved test, or a note that there is none.
	Last string
	// CharsKnown says whether that test counted the characters of the answer (older tests did not).
	CharsKnown string
	// Will says, on the confirmation page, whether the model will be tested, with the reason when not.
	Will string
	// State is the progress word on the progress page: waiting, testing, done, failed, skipped or stopped.
	State string
	// Note is the reason for a skipped or failed model.
	Note string
	// Embedding is true for an embedding model (kept for the job).
	Embedding bool
	// Details are what Ollama reports about the model (kept for the job).
	Details modelDetails
} // end of retestRow

// retestJob is one group re-test: the models, how far it has got, and whether the person asked to stop after the current model.
type retestJob struct {
	// mu protects every field below, because the background work and the pages use them at the same time.
	mu sync.Mutex
	// Title is the group title, shown back to the person.
	Title string
	// Rows are the models in the order they are tested.
	Rows []retestRow
	// Running is true until the last model has been dealt with.
	Running bool
	// StopAsked is true after the person pressed the button to stop after the current model.
	StopAsked bool
	// Finished is when the job ended, in the person's time zone.
	Finished time.Time
} // end of retestJob

// retestPage is everything the re-test template needs.
type retestPage struct {
	// Theme is the colour scheme asked for in the address, or empty.
	Theme string
	// Size is the saved text size, or empty.
	Size string
	// Token is the page token for the forms.
	Token string
	// Kind picks the part of the template: ask, status, nothing or error.
	Kind string
	// Title is the group title.
	Title string
	// Rows are the models.
	Rows []retestRow
	// WillCount is how many models will be tested.
	WillCount int
	// Running is true while the job runs.
	Running bool
	// StopAsked is true after the stop request.
	StopAsked bool
	// Done is true when the job has ended.
	Done bool
	// Finished is the time the job ended.
	Finished string
	// Counts is the sentence that sums up the progress.
	Counts string
	// Detail is the plain reason of an error.
	Detail string
	// Models are the names that the confirmation form passes on.
	Models []string
	// SittingHours is the number of hours within which tests count as made in one sitting, as the comparison page uses it.
	SittingHours int
} // end of retestPage

// latestRunOf finds the newest saved test of a model with the current prompt, or reports that there is none.
func latestRunOf(store *perfStore, name, kind string) (perfRun, bool) {
	// Newest first.
	for _, r := range store.forModel(name, kind) {
		// Only tests with the current prompt can be compared.
		if r.PromptVersion == perfPromptVersion {
			// Found it.
			return r, true
		} // end of the prompt check
	} // end of the loop
	// None.
	return perfRun{}, false
} // end of latestRunOf

// retestRows works out, for each wanted model, what the re-test would do now: the model must be installed, not loaded, and of a kind that can be tested; the second value is how many will be tested.
func retestRows(names []string, installed []installedModel, loaded []loadedModel, store *perfStore) ([]retestRow, int) {
	// The rows.
	rows := make([]retestRow, 0, len(names))
	// How many will be tested.
	will := 0
	// Go through the wanted models.
	for _, name := range names {
		// The row so far.
		row := retestRow{Name: name, Last: "not tested yet", CharsKnown: "no"}
		// Is it installed?
		m, found := findInstalled(installed, name)
		// Not installed: nothing to test.
		if !found {
			// The reason.
			row.Will = "No: no longer installed"
			// Keep the row.
			rows = append(rows, row)
			// Next model.
			continue
		} // end of the installed check
		// Which kind of test fits it.
		cat := categorize(m.Capabilities)
		// The kind name the store uses.
		kind := "generate"
		// An embedding model.
		if cat == categoryEmbedding {
			// Its kind.
			kind = "embedding"
			// It was kept for the job.
			row.Embedding = true
		} // end of the embedding check
		// Keep what Ollama reports for the test.
		row.Details = m.Details
		// What the last test says.
		if last, ok := latestRunOf(store, name, kind); ok {
			// Its time.
			row.Last = formatTime(last.Time)
			// Embedding tests have no answer text, so the count does not apply.
			if kind == "embedding" {
				// Say so.
				row.CharsKnown = "not applicable"
			} else if last.AnswerChars > 0 {
				// The count is there.
				row.CharsKnown = "yes"
			} // end of the count check
		} else if kind == "embedding" {
			// Nothing saved, and the count does not apply.
			row.CharsKnown = "not applicable"
		} // end of the last-test check
		// A loaded model may be in use, so it is left alone.
		if _, ok := findLoaded(loaded, name); ok {
			// The reason.
			row.Will = "No: loaded in memory now"
			// Keep the row.
			rows = append(rows, row)
			// Next model.
			continue
		} // end of the loaded check
		// Only text, multimodal and embedding models can be tested.
		if cat != categoryEmbedding && cat != categoryText && cat != categoryMultimodal {
			// The reason.
			row.Will = "No: this kind of model cannot be tested"
			// Keep the row.
			rows = append(rows, row)
			// Next model.
			continue
		} // end of the kind check
		// It will be tested.
		row.Will = "Yes"
		// Count it.
		will++
		// Keep the row.
		rows = append(rows, row)
	} // end of the loop
	// Hand them back.
	return rows, will
} // end of retestRows

// counts sums up the progress in one sentence; the caller holds the lock.
func (j *retestJob) counts() string {
	// The numbers.
	var done, failed, skipped, stopped, waiting int
	// Go through the rows.
	for _, r := range j.Rows {
		// Count by state.
		switch r.State {
		// Finished well.
		case "done":
			// One more.
			done++
		// Finished badly.
		case "failed":
			// One more.
			failed++
		// Left out.
		case "skipped":
			// One more.
			skipped++
		// Not started because of the stop request.
		case "stopped":
			// One more.
			stopped++
		// Still to do, or being tested.
		default:
			// One more.
			waiting++
		} // end of the state switch
	} // end of the loop
	// The sentence.
	return fmt.Sprintf("%d tested, %d failed, %d skipped, %d not started because you stopped, %d still to do.", done, failed, skipped, stopped, waiting)
} // end of counts

// snapshot copies the job into a page under the lock, so the template never races the background work.
func (j *retestJob) snapshot(p retestPage) retestPage {
	// One at a time.
	j.mu.Lock()
	// Release at the end.
	defer j.mu.Unlock()
	// Copy what the page shows.
	p.Title, p.Running, p.StopAsked, p.Done = j.Title, j.Running, j.StopAsked, !j.Running
	// A copy of the rows, so later changes cannot reach the template.
	p.Rows = append([]retestRow(nil), j.Rows...)
	// The sentence.
	p.Counts = j.counts()
	// When it ended.
	if !j.Finished.IsZero() {
		// The time with its zone.
		p.Finished = formatTime(j.Finished)
	} // end of the finished check
	// Hand it back.
	return p
} // end of snapshot

// setState changes one row under the lock.
func (j *retestJob) setState(i int, state, note string) {
	// One at a time.
	j.mu.Lock()
	// Release at the end.
	defer j.mu.Unlock()
	// Change it.
	j.Rows[i].State, j.Rows[i].Note = state, note
} // end of setState

// stopAsked tells whether the person asked to stop after the current model.
func (j *retestJob) stopAsked() bool {
	// One at a time.
	j.mu.Lock()
	// Release at the end.
	defer j.mu.Unlock()
	// The answer.
	return j.StopAsked
} // end of stopAsked

// retestHandlers builds the four handlers of the group re-test: the confirmation page (changes nothing), the start, the progress page, and the request to stop after the current model.
func retestHandlers(addr ollamaAddress, token string, store *perfStore) (ask, start, status, stop http.HandlerFunc) {
	// Read the template once; Must stops the program at start-up if it is broken, which a test would catch first.
	page := template.Must(template.New("retest").Parse(retestTemplateText))
	// The latest job, or nil when none was started since the monitor started.
	var current *retestJob
	// Protects the pointer above.
	var currentMu sync.Mutex
	// show builds the page in memory first, so a template error gives a clean 500 and not a half page.
	show := func(w http.ResponseWriter, r *http.Request, code int, p retestPage) {
		// Add what every page needs.
		p.Theme, p.Token, p.Size = themeFromRequest(r), token, sizeFromRequest(r)
		// The sitting limit of the comparison page, so the two pages never disagree.
		p.SittingHours = cmpSameSittingHours
		// Build the page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, p); err != nil {
			// Log the real reason for the person running the program.
			log.Printf("re-test page error: %v", err)
			// Send a plain 500 without details.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// Tell the browser this is an HTML page.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the status line.
		w.WriteHeader(code)
		// Send the finished page.
		w.Write(buf.Bytes())
	} // end of show
	// readNames runs the shared form checks and returns the title and the model names; ok is false after a refusal was sent.
	readNames := func(w http.ResponseWriter, r *http.Request) (string, []string, bool) {
		// The checks every model form shares (same page, token); the single model field is not used here.
		r.Body = http.MaxBytesReader(w, r.Body, retestFormLimit)
		// Only the monitor's own page may ask.
		if !sameOrigin(r) {
			// Refuse.
			http.Error(w, "request did not come from this page", http.StatusForbidden)
			// Stop here.
			return "", nil, false
		} // end of the origin check
		// Read the form.
		if err := r.ParseForm(); err != nil {
			// Refuse.
			http.Error(w, "bad form", http.StatusBadRequest)
			// Stop here.
			return "", nil, false
		} // end of the form check
		// The token proves the form came from a page this monitor made.
		if !tokenValid(token, r.PostFormValue("token")) {
			// Refuse.
			http.Error(w, "bad token", http.StatusForbidden)
			// Stop here.
			return "", nil, false
		} // end of the token check
		// The title is only shown back; keep it short.
		title := strings.TrimSpace(r.PostFormValue("title"))
		// Too long.
		if len(title) > maxRetestTitle {
			// Refuse.
			http.Error(w, "bad title", http.StatusBadRequest)
			// Stop here.
			return "", nil, false
		} // end of the title check
		// The names, each only once.
		var names []string
		// Remember which were seen.
		seen := map[string]bool{}
		// Go through the fields.
		for _, n := range r.PostForm["model"] {
			// A bad name.
			if n == "" || len(n) > maxModelNameLen {
				// Refuse.
				http.Error(w, "bad model name", http.StatusBadRequest)
				// Stop here.
				return "", nil, false
			} // end of the name check
			// Keep each name once.
			if !seen[n] {
				// Remember it.
				seen[n] = true
				// Keep it.
				names = append(names, n)
			} // end of the duplicate check
		} // end of the loop
		// Nothing to test, or far too much.
		if len(names) == 0 || len(names) > maxRetestModels {
			// Refuse.
			http.Error(w, "bad number of models", http.StatusBadRequest)
			// Stop here.
			return "", nil, false
		} // end of the count check
		// All good.
		return title, names, true
	} // end of readNames
	// plan reads what Ollama has now and works out the rows; ok is false after an error page was shown.
	plan := func(w http.ResponseWriter, r *http.Request, title string, names []string) ([]retestRow, int, bool) {
		// What is installed now.
		installed, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, retestPage{Kind: "error", Title: title, Detail: err.Error()})
			// Stop here.
			return nil, 0, false
		} // end of the installed check
		// What is loaded now.
		loaded, err := fetchLoaded(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, retestPage{Kind: "error", Title: title, Detail: err.Error()})
			// Stop here.
			return nil, 0, false
		} // end of the loaded check
		// The rows.
		rows, will := retestRows(names, installed, loaded, store)
		// Hand them back.
		return rows, will, true
	} // end of plan
	// ask is the first step: it shows what would be tested and changes nothing.
	ask = func(w http.ResponseWriter, r *http.Request) {
		// The form checks.
		title, names, ok := readNames(w, r)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the checks
		// What would happen.
		rows, will, ok := plan(w, r, title, names)
		// An error page was already shown.
		if !ok {
			// Stop here.
			return
		} // end of the plan check
		// Nothing can be tested.
		if will == 0 {
			// Say so, with the reasons.
			show(w, r, http.StatusOK, retestPage{Kind: "nothing", Title: title, Rows: rows})
			// Stop here.
			return
		} // end of the empty check
		// Only the names that will be tested are passed on.
		var pass []string
		// Pick them.
		for _, row := range rows {
			// One that will be tested.
			if row.Will == "Yes" {
				// Pass it on.
				pass = append(pass, row.Name)
			} // end of the pick check
		} // end of the loop
		// Show the question.
		show(w, r, http.StatusOK, retestPage{Kind: "ask", Title: title, Rows: rows, WillCount: will, Models: pass})
	} // end of ask
	// start is the second step: it starts the background work and sends the browser to the progress page.
	start = func(w http.ResponseWriter, r *http.Request) {
		// The form checks.
		title, names, ok := readNames(w, r)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the checks
		// One job at a time.
		currentMu.Lock()
		// A job that is still running keeps going; the person is shown it instead of a second one.
		if current != nil {
			// Look at it.
			current.mu.Lock()
			// Is it running?
			busy := current.Running
			// Release it.
			current.mu.Unlock()
			// Running.
			if busy {
				// Release the pointer.
				currentMu.Unlock()
				// Show the running job.
				http.Redirect(w, r, "/compare/retest/status", http.StatusSeeOther)
				// Stop here.
				return
			} // end of the busy check
		} // end of the current check
		// What would happen now.
		rows, will, ok := plan(w, r, title, names)
		// An error page was already shown.
		if !ok {
			// Release the pointer.
			currentMu.Unlock()
			// Stop here.
			return
		} // end of the plan check
		// Nothing can be tested.
		if will == 0 {
			// Release the pointer.
			currentMu.Unlock()
			// Say so, with the reasons.
			show(w, r, http.StatusOK, retestPage{Kind: "nothing", Title: title, Rows: rows})
			// Stop here.
			return
		} // end of the empty check
		// The job: every model starts waiting or skipped.
		job := &retestJob{Title: title, Rows: rows, Running: true}
		// Set the starting states.
		for i := range job.Rows {
			// A model that will be tested waits; the others were left out already.
			if job.Rows[i].Will == "Yes" {
				// Waiting.
				job.Rows[i].State = "waiting"
			} else {
				// Skipped, with the reason.
				job.Rows[i].State, job.Rows[i].Note = "skipped", strings.TrimPrefix(job.Rows[i].Will, "No: ")
			} // end of the state choice
		} // end of the loop
		// It is the current job.
		current = job
		// Release the pointer.
		currentMu.Unlock()
		// The background work, which does not depend on this request.
		go runRetest(addr, store, job)
		// Show the progress page.
		http.Redirect(w, r, "/compare/retest/status", http.StatusSeeOther)
	} // end of start
	// status shows the progress; it only reads.
	status = func(w http.ResponseWriter, r *http.Request) {
		// The job.
		currentMu.Lock()
		// Copy the pointer.
		job := current
		// Release the pointer.
		currentMu.Unlock()
		// No job since the monitor started.
		if job == nil {
			// Say so.
			show(w, r, http.StatusOK, retestPage{Kind: "none"})
			// Stop here.
			return
		} // end of the none check
		// Show it.
		show(w, r, http.StatusOK, job.snapshot(retestPage{Kind: "status"}))
	} // end of status
	// stop asks the job to stop after the model that is being tested.
	stop = func(w http.ResponseWriter, r *http.Request) {
		// The same checks as every form (the model fields are not used).
		if !readStopForm(w, r, token) {
			// A refusal was already sent.
			return
		} // end of the checks
		// The job.
		currentMu.Lock()
		// Copy the pointer.
		job := current
		// Release the pointer.
		currentMu.Unlock()
		// A job that runs.
		if job != nil {
			// One at a time.
			job.mu.Lock()
			// Remember the request.
			job.StopAsked = job.Running
			// Release it.
			job.mu.Unlock()
		} // end of the job check
		// Back to the progress page.
		http.Redirect(w, r, "/compare/retest/status", http.StatusSeeOther)
	} // end of stop
	// Hand the four handlers back.
	return ask, start, status, stop
} // end of retestHandlers

// readStopForm runs the checks of the stop request: same page, small form, valid token.
func readStopForm(w http.ResponseWriter, r *http.Request, token string) bool {
	// The request carries almost nothing.
	r.Body = http.MaxBytesReader(w, r.Body, 1024)
	// Only the monitor's own page may ask.
	if !sameOrigin(r) {
		// Refuse.
		http.Error(w, "request did not come from this page", http.StatusForbidden)
		// Stop here.
		return false
	} // end of the origin check
	// Read the form.
	if err := r.ParseForm(); err != nil {
		// Refuse.
		http.Error(w, "bad form", http.StatusBadRequest)
		// Stop here.
		return false
	} // end of the form check
	// The token proves the form came from a page this monitor made.
	if !tokenValid(token, r.PostFormValue("token")) {
		// Refuse.
		http.Error(w, "bad token", http.StatusForbidden)
		// Stop here.
		return false
	} // end of the token check
	// All good.
	return true
} // end of readStopForm

// runRetest tests the models of the job one after another; it runs in the background and ends the job when it is done.
func runRetest(addr ollamaAddress, store *perfStore, job *retestJob) {
	// The context of the whole job; the Stop page of the monitor can cancel it.
	ctx, cancel := context.WithCancel(context.Background())
	// Tell the Stop page that work is running, and how to undo it: cancel the job and unload the model it is testing.
	end := activeWork.begin("a re-test of the group "+job.Title+" (Stop cancels it and unloads the model first)", func(c context.Context) {
		// Cancel the model that is being tested.
		cancel()
		// Find the model being tested right now; the others are not loaded by this job.
		job.mu.Lock()
		// The name.
		current := ""
		// Look.
		for _, r := range job.Rows {
			// The one in progress.
			if r.State == "testing" {
				// Keep it.
				current = r.Name
			} // end of the state check
		} // end of the loop
		// Release it.
		job.mu.Unlock()
		// Ask Ollama to unload it; the answer does not matter here.
		if current != "" {
			// Unload.
			unloadModel(c, addr.URL, current, defaultCheckTimeout)
			// Wait until it is really gone, within the time limit.
			waitUntilGone(c, addr.URL, current, defaultCheckTimeout)
		} // end of the current check
	}) // end of begin
	// Whatever happens, the work ends and the job is marked finished.
	defer func() {
		// Release the context.
		cancel()
		// Forget the work.
		end()
		// One at a time.
		job.mu.Lock()
		// Not running any more.
		job.Running = false
		// The time.
		job.Finished = time.Now()
		// Release it.
		job.mu.Unlock()
	}() // end of the deferred function
	// Go through the models.
	for i := range job.Rows {
		// A model that was left out at the start.
		if job.Rows[i].State != "waiting" {
			// Next model.
			continue
		} // end of the skip check
		// The person asked to stop, or the monitor is stopping: the rest is not started.
		if job.stopAsked() || ctx.Err() != nil {
			// Mark it.
			job.setState(i, "stopped", "")
			// Next model.
			continue
		} // end of the stop check
		// Only one test at a time, also against a single test the person started by hand.
		testLock.Lock()
		// Test this one.
		testOne(ctx, addr, store, job, i)
		// Let the next test start.
		testLock.Unlock()
	} // end of the loop
} // end of runRetest

// testOne tests one model of the job and saves the result; the caller holds testLock.
func testOne(ctx context.Context, addr ollamaAddress, store *perfStore, job *retestJob, i int) {
	// The row as it is.
	job.mu.Lock()
	// A copy.
	row := job.Rows[i]
	// Release it.
	job.mu.Unlock()
	// It is being tested now.
	job.setState(i, "testing", "")
	// Look again at what is loaded, because time has passed since the question was answered.
	loaded, err := fetchLoaded(ctx, addr.URL, defaultCheckTimeout)
	// Ollama could not be read.
	if err != nil {
		// Report it.
		job.setState(i, "failed", err.Error())
		// Stop here.
		return
	} // end of the loaded check
	// A model that is loaded now may be in use.
	if _, ok := findLoaded(loaded, row.Name); ok {
		// Leave it alone.
		job.setState(i, "skipped", "loaded in memory now")
		// Stop here.
		return
	} // end of the in-use check
	// The Ollama version, for the record.
	version := checkOllama(ctx, addr.URL, defaultCheckTimeout).Version
	// Run the test.
	res, err := performTest(ctx, addr.URL, row.Name, row.Embedding, version, row.Details)
	// The test failed.
	if err != nil {
		// Report it with the plain reason.
		job.setState(i, "failed", err.Error())
		// Stop here.
		return
	} // end of the failure check
	// Save the numbers; a save problem is reported on the row.
	if saveErr := store.add(res); saveErr != nil {
		// Say so.
		job.setState(i, "done", "tested, but the result could not be saved: "+saveErr.Error())
		// Stop here.
		return
	} // end of the save check
	// Done.
	job.setState(i, "done", "")
} // end of testOne
