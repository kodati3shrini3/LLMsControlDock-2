#!/usr/bin/env bash
# Script 50: adds the monitor controls at the top right: Pause/Resume (F11), Refresh (F11) and Stop with a confirm page (F6); the page updates itself every 10 seconds while watching.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run on main: this change belongs on its own feature branch.
[ "$(git branch --show-current)" = "feature/monitor-controls" ] || { echo "FAIL  not on feature/monitor-controls"; exit 1; }
# Script 49 must be applied first (it adds the results folder name).
grep -q 'historyFolderName' perfstore.go || { echo "FAIL  script 49 was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -f control.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/control.go b/control.go
new file mode 100644
index 0000000..f5b1822
--- /dev/null
+++ b/control.go
@@ -0,0 +1,305 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes builds a page in memory before it is sent.
+	"bytes"
+	// context carries the time limit of the clean-up before stopping.
+	"context"
+	// embed lets the page template be stored inside the executable.
+	_ "embed"
+	// html/template builds the page and escapes every value.
+	"html/template"
+	// log records a real failure for the person running the program.
+	"log"
+	// net/http serves the pages and sets the cookie.
+	"net/http"
+	// sort keeps the list of running work in the order it started.
+	"sort"
+	// sync protects the list of running work and makes the stop happen once.
+	"sync"
+	// time gives the time limit of the clean-up.
+	"time"
+) // end of imports
+
+// controlTemplateText is the template of the Stop pages, stored inside the executable at build time.
+//
+//go:embed web/control.html
+var controlTemplateText string
+
+// watchCookieName is the cookie that remembers that the person paused the page.
+const watchCookieName = "occ_watch"
+
+// watchRefreshSeconds is how often the page updates itself while it is being watched.
+const watchRefreshSeconds = 10
+
+// stopCleanupLimit is how long the clean-up of running work may take before the monitor stops anyway.
+const stopCleanupLimit = 20 * time.Second
+
+// workItem is one piece of work that is running right now.
+type workItem struct {
+	// id orders the items by start time.
+	id int
+	// text says in plain words what is running and what Stop would do to it.
+	text string
+	// cleanup undoes what the work changed (for example unloads the model a test loaded); it may be nil.
+	cleanup func(ctx context.Context)
+} // end of workItem
+
+// workTracker remembers the work that is running right now, so the Stop page can warn about it.
+type workTracker struct {
+	// mu protects the fields below.
+	mu sync.Mutex
+	// next is the id of the next item.
+	next int
+	// items are the running pieces of work.
+	items map[int]workItem
+} // end of workTracker
+
+// activeWork is the one tracker of this program.
+var activeWork = &workTracker{items: map[int]workItem{}}
+
+// stopRequest shuts the program down; main replaces it, and the tests replace it with a recorder.
+var stopRequest = func() {}
+
+// begin records the start of some work and returns the function that records its end.
+func (t *workTracker) begin(text string, cleanup func(ctx context.Context)) func() {
+	// One writer at a time.
+	t.mu.Lock()
+	// Release at the end.
+	defer t.mu.Unlock()
+	// The id of this item.
+	id := t.next
+	// The next one gets a higher id.
+	t.next++
+	// Remember it.
+	t.items[id] = workItem{id: id, text: text, cleanup: cleanup}
+	// The function that ends it.
+	return func() {
+		// One writer at a time.
+		t.mu.Lock()
+		// Release at the end.
+		defer t.mu.Unlock()
+		// Forget it.
+		delete(t.items, id)
+	} // end of the end function
+} // end of begin
+
+// list returns the running items, oldest first.
+func (t *workTracker) list() []workItem {
+	// One reader at a time.
+	t.mu.Lock()
+	// Release at the end.
+	defer t.mu.Unlock()
+	// The copy.
+	out := make([]workItem, 0, len(t.items))
+	// Fill it.
+	for _, it := range t.items {
+		// One item.
+		out = append(out, it)
+	} // end of the loop
+	// Oldest first.
+	sort.Slice(out, func(i, j int) bool { return out[i].id < out[j].id })
+	// Hand it back.
+	return out
+} // end of list
+
+// texts returns the plain descriptions of the running work.
+func (t *workTracker) texts() []string {
+	// The descriptions.
+	var out []string
+	// Fill them.
+	for _, it := range t.list() {
+		// One description.
+		out = append(out, it.text)
+	} // end of the loop
+	// Hand them back.
+	return out
+} // end of texts
+
+// runCleanups undoes what the running work changed, one after the other, within the time limit.
+func (t *workTracker) runCleanups(ctx context.Context) {
+	// Each item with a clean-up.
+	for _, it := range t.list() {
+		// Nothing to undo.
+		if it.cleanup == nil {
+			// Next item.
+			continue
+		} // end of the nil check
+		// Undo it.
+		it.cleanup(ctx)
+	} // end of the loop
+} // end of runCleanups
+
+// watchPaused says whether the request carries the cookie of a paused page.
+func watchPaused(r *http.Request) bool {
+	// Look for the cookie.
+	c, err := r.Cookie(watchCookieName)
+	// No cookie means the page is being watched.
+	if err != nil {
+		// Watching.
+		return false
+	} // end of the cookie check
+	// Only the exact word counts.
+	return c.Value == "paused"
+} // end of watchPaused
+
+// watchHandler pauses or resumes the automatic updates; it only sets a cookie and goes back to the page.
+func watchHandler(token string) http.HandlerFunc {
+	// The handler.
+	return func(w http.ResponseWriter, r *http.Request) {
+		// Never read more than 1 KB of form data.
+		r.Body = http.MaxBytesReader(w, r.Body, 1024)
+		// Only a form on this very page may send this request.
+		if !sameOrigin(r) {
+			// Refuse.
+			http.Error(w, "request did not come from this page", http.StatusForbidden)
+			// Stop here.
+			return
+		} // end of the origin check
+		// Read the form.
+		if err := r.ParseForm(); err != nil {
+			// Refuse.
+			http.Error(w, "bad form", http.StatusBadRequest)
+			// Stop here.
+			return
+		} // end of the form check
+		// The page token must match.
+		if !tokenValid(token, r.PostFormValue("token")) {
+			// Refuse.
+			http.Error(w, "bad token", http.StatusForbidden)
+			// Stop here.
+			return
+		} // end of the token check
+		// Which action.
+		switch r.PostFormValue("action") {
+		// Pause: remember it in the browser for a year.
+		case "pause":
+			// Set the cookie.
+			http.SetCookie(w, &http.Cookie{Name: watchCookieName, Value: "paused", Path: "/", MaxAge: themeCookieMaxAge, HttpOnly: true, SameSite: http.SameSiteStrictMode})
+		// Resume: delete the cookie.
+		case "resume":
+			// Delete it.
+			http.SetCookie(w, &http.Cookie{Name: watchCookieName, Value: "", Path: "/", MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteStrictMode})
+		// Anything else is refused.
+		default:
+			// Refuse.
+			http.Error(w, "unknown action", http.StatusBadRequest)
+			// Stop here.
+			return
+		} // end of the action choice
+		// Back to the page.
+		http.Redirect(w, r, "/", http.StatusSeeOther)
+	} // end of the handler
+} // end of watchHandler
+
+// controlPage is what the Stop template shows.
+type controlPage struct {
+	// Theme is the colour scheme asked for in the cookie, or empty.
+	Theme string
+	// Token is the page token for the confirm form.
+	Token string
+	// Kind is stopask (the question) or stopped (the last page).
+	Kind string
+	// Work describes what is running right now.
+	Work []string
+} // end of controlPage
+
+// stopHandlers returns the two steps of stopping: the question, and the real stop.
+func stopHandlers(token string) (http.HandlerFunc, http.HandlerFunc) {
+	// Read the template once.
+	page := template.Must(template.New("control").Parse(controlTemplateText))
+	// Stop only once, however many times the button is pressed.
+	var once sync.Once
+	// check runs the shared form checks; ok is false when a refusal was already sent.
+	check := func(w http.ResponseWriter, r *http.Request) bool {
+		// Never read more than 1 KB of form data.
+		r.Body = http.MaxBytesReader(w, r.Body, 1024)
+		// Only a form on this very page may send this request (requirement S2).
+		if !sameOrigin(r) {
+			// Refuse.
+			http.Error(w, "request did not come from this page", http.StatusForbidden)
+			// Stop here.
+			return false
+		} // end of the origin check
+		// Read the form.
+		if err := r.ParseForm(); err != nil {
+			// Refuse.
+			http.Error(w, "bad form", http.StatusBadRequest)
+			// Stop here.
+			return false
+		} // end of the form check
+		// The page token must match.
+		if !tokenValid(token, r.PostFormValue("token")) {
+			// Refuse.
+			http.Error(w, "bad token", http.StatusForbidden)
+			// Stop here.
+			return false
+		} // end of the token check
+		// All good.
+		return true
+	} // end of check
+	// show builds a page in memory first, so a template error gives a clean 500.
+	show := func(w http.ResponseWriter, r *http.Request, data controlPage) {
+		// What every version needs.
+		data.Theme, data.Token = themeFromRequest(r), token
+		// Build the page.
+		var buf bytes.Buffer
+		// Run the template.
+		if err := page.Execute(&buf, data); err != nil {
+			// Log the real reason.
+			log.Printf("stop page error: %v", err)
+			// Send a plain 500.
+			http.Error(w, "internal error", http.StatusInternalServerError)
+			// Stop here.
+			return
+		} // end of the template check
+		// Tell the browser this is an HTML page.
+		w.Header().Set("Content-Type", "text/html; charset=utf-8")
+		// Send the page.
+		w.Write(buf.Bytes())
+	} // end of show
+	// ask is the first step: the question, with a warning about running work; it changes nothing.
+	ask := func(w http.ResponseWriter, r *http.Request) {
+		// The checks.
+		if !check(w, r) {
+			// A refusal was already sent.
+			return
+		} // end of the checks
+		// Show the question.
+		show(w, r, controlPage{Kind: "stopask", Work: activeWork.texts()})
+	} // end of ask
+	// confirm is the second step: the last page is sent first, then the clean-up and the stop follow.
+	confirm := func(w http.ResponseWriter, r *http.Request) {
+		// The checks.
+		if !check(w, r) {
+			// A refusal was already sent.
+			return
+		} // end of the checks
+		// The last page.
+		show(w, r, controlPage{Kind: "stopped"})
+		// Send it now, so it reaches the browser before the program ends.
+		if f, ok := w.(http.Flusher); ok {
+			// Flush.
+			f.Flush()
+		} // end of the flush check
+		// Clean up and stop in the background, once.
+		once.Do(func() {
+			// A goroutine, so this handler can finish.
+			go func() {
+				// A short moment for the page to arrive.
+				time.Sleep(200 * time.Millisecond)
+				// Undo what running work changed, within a time limit.
+				ctx, cancel := context.WithTimeout(context.Background(), stopCleanupLimit)
+				// Run the clean-ups.
+				activeWork.runCleanups(ctx)
+				// Release the timer.
+				cancel()
+				// Shut the program down.
+				stopRequest()
+			}() // end of the goroutine
+		}) // end of once
+	} // end of confirm
+	// Hand both back.
+	return ask, confirm
+} // end of stopHandlers
diff --git a/control_test.go b/control_test.go
new file mode 100644
index 0000000..8f878d4
--- /dev/null
+++ b/control_test.go
@@ -0,0 +1,336 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// context is passed to the clean-up functions.
+	"context"
+	// net/http gives the status codes.
+	"net/http"
+	// net/http/httptest builds requests with cookies.
+	"net/http/httptest"
+	// net/url builds the form values.
+	"net/url"
+	// strings searches the page text.
+	"strings"
+	// sync/atomic counts calls from other goroutines.
+	"sync/atomic"
+	// testing is Go's test framework.
+	"testing"
+	// time bounds the waiting for the background stop.
+	"time"
+) // end of imports
+
+// stopRecorder replaces the real shutdown for the length of a test and counts the requests.
+func stopRecorder(t *testing.T) *atomic.Int32 {
+	// Mark this as a helper.
+	t.Helper()
+	// Remember the real one.
+	old := stopRequest
+	// The counter.
+	var n atomic.Int32
+	// Count instead of stopping.
+	stopRequest = func() { n.Add(1) }
+	// Put the real one back at the end.
+	t.Cleanup(func() { stopRequest = old })
+	// Hand the counter back.
+	return &n
+} // end of stopRecorder
+
+// pageWithCookie fetches the main page, sending the given cookie.
+func pageWithCookie(t *testing.T, rig themeRig, cookie *http.Cookie) string {
+	// Mark this as a helper.
+	t.Helper()
+	// Build the request.
+	req := httptest.NewRequest(http.MethodGet, "/", nil)
+	// Add the cookie when there is one.
+	if cookie != nil {
+		// Send it.
+		req.AddCookie(cookie)
+	} // end of the cookie check
+	// Run the handler.
+	rec := httptest.NewRecorder()
+	// Serve.
+	rig.h.ServeHTTP(rec, req)
+	// The page.
+	return rec.Body.String()
+} // end of pageWithCookie
+
+// TestWatchPauseResume checks the automatic updates: on by default, off while paused, and the form rules.
+func TestWatchPauseResume(t *testing.T) {
+	// A fake and a rig.
+	rig, _ := perfRig(t, newPerfFake())
+	// By default the page updates itself every 10 seconds and offers Pause.
+	page := pageWithCookie(t, rig, nil)
+	// Look for the parts.
+	for _, w := range []string{`<meta http-equiv="refresh" content="10">`, `name="action" value="pause"`, "Watching: the page updates itself every 10 seconds", `id="tipwatch"`, `id="tiprefresh"`, `id="tipstop"`, `action="/stop"`, `href="/"`} {
+		// Look for it.
+		if !strings.Contains(page, w) {
+			// Report the gap.
+			t.Errorf("the watching page lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// Pausing sets the cookie and goes back to the page.
+	res := post(t, rig.h, "/watch", url.Values{"token": {rig.token}, "action": {"pause"}}, fromThisPage)
+	// A redirect to the page.
+	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/" {
+		// Report it.
+		t.Errorf("pause: %d to %q", res.StatusCode, res.Header.Get("Location"))
+	} // end of the redirect check
+	// The cookie.
+	var paused *http.Cookie
+	// Find it.
+	for _, c := range res.Cookies() {
+		// The right one.
+		if c.Name == watchCookieName {
+			// Keep it.
+			paused = c
+		} // end of the name check
+	} // end of the loop
+	// It says paused, and it is not readable by scripts.
+	if paused == nil || paused.Value != "paused" || !paused.HttpOnly {
+		// Report it.
+		t.Fatalf("pause cookie wrong: %+v", paused)
+	} // end of the cookie check
+	// With the cookie the page does not refresh itself and offers Resume.
+	page = pageWithCookie(t, rig, &http.Cookie{Name: watchCookieName, Value: "paused"})
+	// No refresh line.
+	if strings.Contains(page, `http-equiv="refresh"`) {
+		// Report it.
+		t.Errorf("a paused page still refreshes itself")
+	} // end of the refresh check
+	// The paused parts.
+	for _, w := range []string{`name="action" value="resume"`, "Paused: the page does not update by itself", "Make the page update itself every 10 seconds again"} {
+		// Look for it.
+		if !strings.Contains(page, w) {
+			// Report the gap.
+			t.Errorf("the paused page lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// A cookie with another value does not pause.
+	if strings.Contains(pageWithCookie(t, rig, &http.Cookie{Name: watchCookieName, Value: "yes"}), "Paused:") {
+		// Report it.
+		t.Errorf("a wrong cookie value paused the page")
+	} // end of the value check
+	// Resuming deletes the cookie.
+	res = post(t, rig.h, "/watch", url.Values{"token": {rig.token}, "action": {"resume"}}, fromThisPage)
+	// A deleting cookie has a negative age.
+	gone := false
+	// Look at the cookies.
+	for _, c := range res.Cookies() {
+		// The right one, deleted.
+		if c.Name == watchCookieName && c.MaxAge < 0 {
+			// Found.
+			gone = true
+		} // end of the check
+	} // end of the loop
+	// It must be deleted.
+	if res.StatusCode != http.StatusSeeOther || !gone {
+		// Report it.
+		t.Errorf("resume: %d, deleted=%v", res.StatusCode, gone)
+	} // end of the resume check
+	// The rules: a wrong token, another site, a bad action and a plain GET are all refused.
+	for name, tc := range map[string]struct {
+		// form is what is sent.
+		form url.Values
+		// headers are the request headers.
+		headers map[string]string
+		// want is the expected status.
+		want int
+	}{
+		"wrong token": {url.Values{"token": {"0123456789abcdef0123456789abcdef"}, "action": {"pause"}}, fromThisPage, http.StatusForbidden},
+		"other site":  {url.Values{"token": {rig.token}, "action": {"pause"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
+		"bad action":  {url.Values{"token": {rig.token}, "action": {"explode"}}, fromThisPage, http.StatusBadRequest},
+	} { // end of the cases
+		// Send it.
+		if res := post(t, rig.h, "/watch", tc.form, tc.headers); res.StatusCode != tc.want || len(res.Cookies()) != 0 {
+			// Report it.
+			t.Errorf("%s: %d (cookies %d), want %d without cookies", name, res.StatusCode, len(res.Cookies()), tc.want)
+		} // end of the check
+	} // end of the loop
+	// A GET is not a route.
+	if status, _, _ := get(t, rig.h, http.MethodGet, "/watch"); status != http.StatusMethodNotAllowed && status != http.StatusNotFound {
+		// Report it.
+		t.Errorf("GET /watch = %d", status)
+	} // end of the GET check
+} // end of TestWatchPauseResume
+
+// TestStopTwoSteps checks that the first step only asks, the second stops once, and the form rules hold.
+func TestStopTwoSteps(t *testing.T) {
+	// A recorder for the shutdown.
+	stops := stopRecorder(t)
+	// A fake and a rig.
+	rig, _ := perfRig(t, newPerfFake())
+	// The question.
+	res := post(t, rig.h, "/stop", url.Values{"token": {rig.token}}, fromThisPage)
+	// Its text.
+	ask := bodyOf(res)
+	// The parts.
+	for _, w := range []string{"Stop the monitor?", "Ollama and its models are not touched", `action="/stop/confirm"`, "No, keep it running"} {
+		// Look for it.
+		if !strings.Contains(ask, w) {
+			// Report the gap.
+			t.Errorf("the question lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// Nothing is running, so there is no warning.
+	if strings.Contains(ask, "Something is running") {
+		// Report it.
+		t.Errorf("a warning without any work")
+	} // end of the warning check
+	// Asking changes nothing.
+	time.Sleep(400 * time.Millisecond)
+	// No stop yet.
+	if stops.Load() != 0 {
+		// Report it.
+		t.Fatalf("the question stopped the monitor")
+	} // end of the ask check
+	// The rules for both steps: a wrong token and another site are refused, and nothing stops.
+	for _, path := range []string{"/stop", "/stop/confirm"} {
+		// A wrong token.
+		if res := post(t, rig.h, path, url.Values{"token": {"0123456789abcdef0123456789abcdef"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
+			// Report it.
+			t.Errorf("%s wrong token = %d", path, res.StatusCode)
+		} // end of the token check
+		// Another site.
+		if res := post(t, rig.h, path, url.Values{"token": {rig.token}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
+			// Report it.
+			t.Errorf("%s cross-site = %d", path, res.StatusCode)
+		} // end of the origin check
+		// No headers at all (a script, not a page).
+		if res := post(t, rig.h, path, url.Values{"token": {rig.token}}, nil); res.StatusCode != http.StatusForbidden {
+			// Report it.
+			t.Errorf("%s without origin = %d", path, res.StatusCode)
+		} // end of the header check
+		// A plain GET is not a route.
+		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed && status != http.StatusNotFound {
+			// Report it.
+			t.Errorf("GET %s = %d", path, status)
+		} // end of the GET check
+	} // end of the loop
+	// Wait a moment: still nothing stopped.
+	time.Sleep(400 * time.Millisecond)
+	// Check.
+	if stops.Load() != 0 {
+		// Report it.
+		t.Fatalf("a refused request stopped the monitor")
+	} // end of the refusal check
+	// The real stop: the last page comes back at once.
+	res = post(t, rig.h, "/stop/confirm", url.Values{"token": {rig.token}}, fromThisPage)
+	// Its text.
+	last := bodyOf(res)
+	// The last page.
+	if res.StatusCode != http.StatusOK || !strings.Contains(last, "The monitor has stopped") || strings.Contains(last, `http-equiv="refresh"`) {
+		// Report it.
+		t.Errorf("last page wrong: %d", res.StatusCode)
+	} // end of the last page check
+	// The stop follows in the background; pressing the button again does not stop twice.
+	post(t, rig.h, "/stop/confirm", url.Values{"token": {rig.token}}, fromThisPage)
+	// Wait for it, at most 3 seconds.
+	for i := 0; i < 30 && stops.Load() == 0; i++ {
+		// A short wait.
+		time.Sleep(100 * time.Millisecond)
+	} // end of the wait loop
+	// Give a second press time to show up if it were going to.
+	time.Sleep(500 * time.Millisecond)
+	// Exactly one stop.
+	if n := stops.Load(); n != 1 {
+		// Report it.
+		t.Errorf("stop requested %d times, want 1", n)
+	} // end of the count check
+} // end of TestStopTwoSteps
+
+// TestWorkTracker checks the list of running work and that the clean-ups run.
+func TestWorkTracker(t *testing.T) {
+	// A tracker of its own.
+	w := &workTracker{items: map[int]workItem{}}
+	// Nothing at first.
+	if len(w.texts()) != 0 {
+		// Report it.
+		t.Fatalf("a new tracker has work")
+	} // end of the empty check
+	// How many clean-ups ran.
+	var ran atomic.Int32
+	// Two pieces of work, one with a clean-up.
+	endA := w.begin("first", func(ctx context.Context) { ran.Add(1) })
+	// The second has none.
+	endB := w.begin("second", nil)
+	// Both are listed, oldest first.
+	if got := strings.Join(w.texts(), ","); got != "first,second" {
+		// Report it.
+		t.Errorf("texts = %q", got)
+	} // end of the list check
+	// The clean-ups run for the work that has one.
+	w.runCleanups(context.Background())
+	// Once.
+	if ran.Load() != 1 {
+		// Report it.
+		t.Errorf("clean-ups ran %d times, want 1", ran.Load())
+	} // end of the clean-up check
+	// Ending the first leaves the second.
+	endA()
+	// Check.
+	if got := strings.Join(w.texts(), ","); got != "second" {
+		// Report it.
+		t.Errorf("after the first ended: %q", got)
+	} // end of the end check
+	// Ending twice is harmless.
+	endA()
+	// Ending the second empties the list.
+	endB()
+	// Check.
+	if len(w.texts()) != 0 {
+		// Report it.
+		t.Errorf("work left after both ended")
+	} // end of the empty check
+} // end of TestWorkTracker
+
+// TestStopWhileTestRuns checks the warning on the question page, and that stopping unloads the model that the running test loaded.
+func TestStopWhileTestRuns(t *testing.T) {
+	// A recorder for the shutdown.
+	stops := stopRecorder(t)
+	// A fake that holds the first test request.
+	f := newPerfFake()
+	// Hold it.
+	f.hold, f.entered, f.release = true, make(chan struct{}, 1), make(chan struct{})
+	// Build the rig.
+	rig, _ := perfRig(t, f)
+	// The test in the background.
+	done := make(chan struct{})
+	// Start it.
+	go func() {
+		// Run.
+		perfPost(t, rig, "/performance/run", "chat:1b")
+		// Report.
+		close(done)
+	}() // end of the goroutine
+	// Wait until the test is inside the model request.
+	<-f.entered
+	// The question names the running test.
+	ask := bodyOf(post(t, rig.h, "/stop", url.Values{"token": {rig.token}}, fromThisPage))
+	// The warning.
+	for _, w := range []string{"Something is running right now", "a performance test of chat:1b", "Stop cancels it and unloads the model first"} {
+		// Look for it.
+		if !strings.Contains(ask, w) {
+			// Report the gap.
+			t.Errorf("the question lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// Before the stop, nothing was unloaded by it.
+	before := f.unloadCount()
+	// Stop for real.
+	post(t, rig.h, "/stop/confirm", url.Values{"token": {rig.token}}, fromThisPage)
+	// Wait for the stop, at most 3 seconds.
+	for i := 0; i < 30 && stops.Load() == 0; i++ {
+		// A short wait.
+		time.Sleep(100 * time.Millisecond)
+	} // end of the wait loop
+	// The stop was requested, and the model was asked to unload first.
+	if stops.Load() != 1 || f.unloadCount() <= before {
+		// Report it.
+		t.Errorf("stops %d, unloads %d (before %d)", stops.Load(), f.unloadCount(), before)
+	} // end of the stop check
+	// Let the held test finish so the test ends cleanly.
+	close(f.release)
+	// Wait for it.
+	<-done
+} // end of TestStopWhileTestRuns
diff --git a/load.go b/load.go
index 2ed82ff..58b56c4 100644
--- a/load.go
+++ b/load.go
@@ -374,6 +374,8 @@ func loadHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.Hand
 			// A page was already shown.
 			return
 		} // end of the model checks
+		// Tell the Stop page that a load is running; Ollama finishes it by itself, so nothing needs undoing.
+		defer activeWork.begin("loading of "+name+" (Ollama finishes the load by itself)", nil)()
 		// Ask Ollama to load it; this call returns when loading is finished, which can take a while.
 		if _, err := loadModelKeep(r.Context(), addr.URL, name, keep, loadTimeout); err != nil {
 			// Show the plain reason.
diff --git a/main.go b/main.go
index 6e8d25c..b264f0b 100644
--- a/main.go
+++ b/main.go
@@ -4,6 +4,8 @@ package main
 import ( // import lists the standard-library packages this file uses.
 	// context supplies the (empty) context the fetch functions need.
 	"context"
+	// errors tells a normal shutdown from a real failure.
+	"errors"
 	// flag reads command-line options such as -listen.
 	"flag"
 	// fmt writes formatted text to the terminal.
@@ -116,8 +118,36 @@ func main() {
 
 	// Tell the person which address we are about to serve on.
 	log.Printf("OllamaControlCenter listening on http://%s (press Ctrl+C to stop)", *listen)
+	// Closed when the shutdown that the Stop button started has finished.
+	stopped := make(chan struct{})
+	// The Stop button's last step: shut the web server down, waiting at most 5 seconds for requests that are still running.
+	stopRequest = func() {
+		// In the background, so the request that asked for it can finish.
+		go func() {
+			// A time limit for the polite shutdown.
+			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
+			// Release the timer at the end.
+			defer cancel()
+			// Ask politely first.
+			if err := server.Shutdown(ctx); err != nil {
+				// Requests that would not finish are cut off.
+				server.Close()
+			} // end of the shutdown check
+			// Tell main that it can leave.
+			close(stopped)
+		}() // end of the goroutine
+	} // end of stopRequest
 	// Start serving; this call blocks (waits) until the server stops or fails, for example if the port is taken.
 	err = server.ListenAndServe()
-	// If we get here the server has stopped; log.Fatal prints the reason and exits with an error code.
+	// A shutdown asked for by the Stop button is a normal end, not an error.
+	if errors.Is(err, http.ErrServerClosed) {
+		// Wait until the shutdown has finished.
+		<-stopped
+		// Say why the program ends.
+		log.Printf("OllamaControlCenter stopped from its page")
+		// Leave with the success code.
+		return
+	} // end of the normal stop
+	// If we get here the server has stopped for another reason; log.Fatal prints it and exits with an error code.
 	log.Fatal(err)
 } // end of main
diff --git a/perfpage.go b/perfpage.go
index c5195f6..3f8f1ec 100644
--- a/perfpage.go
+++ b/perfpage.go
@@ -2,6 +2,8 @@
 package main
 
 import ( // import lists the standard-library packages this file uses.
+	// context carries the time limit of the clean-up.
+	"context"
 	// bytes builds the page in memory before it is sent.
 	"bytes"
 	// embed stores the page template inside the executable.
@@ -588,6 +590,13 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore) (http.Hand
 		} // end of the lock check
 		// Release it when done.
 		defer runLock.Unlock()
+		// Tell the Stop page that a test is running, and how to undo it: unload the model the test loaded.
+		defer activeWork.begin("a performance test of "+name+" (Stop cancels it and unloads the model first)", func(ctx context.Context) {
+			// Ask Ollama to unload the model; the answer does not matter here.
+			unloadModel(ctx, addr.URL, name, defaultCheckTimeout)
+			// Wait until it is really gone, within the time limit.
+			waitUntilGone(ctx, addr.URL, name, defaultCheckTimeout)
+		})()
 		// The Ollama version, for the record.
 		version := checkOllama(r.Context(), addr.URL, defaultCheckTimeout).Version
 		// Run the test.
diff --git a/web.go b/web.go
index b0ce63f..a0e73fa 100644
--- a/web.go
+++ b/web.go
@@ -55,6 +55,12 @@ type pageData struct {
 	Token string
 	// CompareCount is how many models have a saved performance test that can be compared.
 	CompareCount int
+	// Paused is true when the person paused the automatic updates (a cookie remembers it).
+	Paused bool
+	// RefreshSeconds is how often the page updates itself while it is being watched.
+	RefreshSeconds int
+	// UpdatedAt is the time of day this page was made, so a person can see how fresh it is.
+	UpdatedAt string
 } // end of pageData
 
 // secureHeaders wraps a handler so every reply, including errors, carries the same safety headers.
@@ -125,6 +131,14 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	mux.HandleFunc("POST /performance/clear/confirm", perfClearDo)
 	// Route: a POST request for "/compare" shows the comparison of the tested models and changes nothing.
 	mux.HandleFunc("POST /compare", compareHandler(addr, token, perfHistory))
+	// Route: a POST request for "/watch" pauses or resumes the automatic updates of the page.
+	mux.HandleFunc("POST /watch", watchHandler(token))
+	// The two steps of stopping the monitor.
+	stopAsk, stopConfirm := stopHandlers(token)
+	// Route: a POST request for "/stop" asks whether to stop the monitor and changes nothing.
+	mux.HandleFunc("POST /stop", stopAsk)
+	// Route: a POST request for "/stop/confirm" sends the last page and stops the monitor.
+	mux.HandleFunc("POST /stop/confirm", stopConfirm)
 	// Route: a GET request for "/countdown.js" sends the small script that makes the timers tick (only the message pages use it).
 	mux.HandleFunc("GET /countdown.js", countdownHandler)
 	// Route: a GET request for "/loading.js" sends the small script that shows the waiting message while a model loads (only the load warning page uses it).
@@ -153,6 +167,12 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 			Token: token,
 			// How many models can be compared.
 			CompareCount: perfHistory.testedModels(),
+			// Whether the automatic updates are paused.
+			Paused: watchPaused(r),
+			// The update interval.
+			RefreshSeconds: watchRefreshSeconds,
+			// When this page was made.
+			UpdatedAt: time.Now().Format("15:04:05"),
 		} // end of the data
 		// Only an online Ollama can be asked for its model lists.
 		if res.Online {
diff --git a/web/app.css b/web/app.css
index 75c1279..bc2da42 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1084,7 +1084,7 @@ button.btn-plain {
 } /* end of rule */
 
 /* Every icon box is its own anchor: the name is private to each box, so a bubble finds only its own icon. */
-.gearform .tipbox, .comparebar .tipbox {
+.gearform .tipbox, .comparebar .tipbox, .controls .tipbox {
   /* The name the bubble uses to find this box. */
   anchor-name: --tipicon;
   /* Keep the name inside this box, so the boxes of other rows never get mixed up. */
@@ -1221,3 +1221,72 @@ button.btn-plain {
     right: 0.5rem;
   } /* end of rule */
 } /* end of rule */
+
+/* The right side of the header: the controls and the theme switch side by side, wrapping on a narrow window. */
+.headright {
+  /* Side by side. */
+  display: flex;
+  /* Wrap when the window is narrow. */
+  flex-wrap: wrap;
+  /* Level with each other. */
+  align-items: center;
+  /* Push them to the right edge. */
+  justify-content: flex-end;
+  /* Space between them. */
+  gap: 0.5rem 1rem;
+} /* end of rule */
+
+/* The monitor controls in one row. */
+.controls {
+  /* Side by side. */
+  display: flex;
+  /* Wrap when the window is narrow. */
+  flex-wrap: wrap;
+  /* Level with each other. */
+  align-items: center;
+  /* Space between the buttons. */
+  gap: 0.5rem;
+} /* end of rule */
+
+/* The forms inside the controls take no space of their own. */
+.controls form {
+  /* No outer space. */
+  margin: 0;
+} /* end of rule */
+
+/* The control buttons are small, in the page font. */
+.ctlbtn {
+  /* Same font as the page. */
+  font: inherit;
+  /* A little smaller than body text. */
+  font-size: 0.9rem;
+  /* A hand cursor. */
+  cursor: pointer;
+  /* A link and a button share one box model. */
+  display: inline-block;
+  /* Same box rule. */
+  box-sizing: border-box;
+  /* Same line height. */
+  line-height: 1.4;
+  /* Room inside. */
+  padding: 0.25rem 0.8rem;
+} /* end of rule */
+
+/* The tips of the controls are at the right edge of the window, so each bubble is lined up with its button's right edge and opens towards the left. */
+.controls .tip-icon {
+  /* No left edge: the right edge decides. */
+  left: auto;
+  /* The bubble's right edge sits on the button's right edge. */
+  right: anchor(right);
+} /* end of rule */
+
+/* On a narrow window the bubbles span the window again. */
+@media (max-width: 40rem) {
+  /* The control bubbles. */
+  .controls .tip-icon {
+    /* Near the left edge. */
+    left: 0.5rem;
+    /* Near the right edge. */
+    right: 0.5rem;
+  } /* end of rule */
+} /* end of rule */
diff --git a/web/control.html b/web/control.html
new file mode 100644
index 0000000..6c356b6
--- /dev/null
+++ b/web/control.html
@@ -0,0 +1,54 @@
+{{/* Stop pages: the question and the last page. The comments are template comments, so they never reach the browser. */}}
+<!DOCTYPE html>
+{{/* lang tells screen readers which language the page is written in. */}}
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<head>{{/* start of the head. */}}
+{{/* Text encoding. */}}
+<meta charset="utf-8">
+{{/* Fit the page to the width of the screen on phones. */}}
+<meta name="viewport" content="width=device-width, initial-scale=1">
+{{/* Both colour schemes are supported. */}}
+<meta name="color-scheme" content="light dark">
+{{/* The title shown on the browser tab. */}}
+<title>{{if eq .Kind "stopped"}}Stopped{{else}}Stop the monitor{{end}} - OllamaControlCenter</title>
+{{/* Our one stylesheet. */}}
+<link rel="stylesheet" href="/app.css">
+</head>{{/* end of the head. */}}
+<body>{{/* start of the visible page. */}}
+<main>
+{{/* A panel that holds the message. */}}
+<section class="panel">
+{{/* Version 1: the question. */}}
+{{if eq .Kind "stopask"}}
+<h1>Stop the monitor?</h1>
+<p>This closes OllamaControlCenter. Ollama and its models are not touched: whatever is loaded stays loaded.</p>
+{{/* What is running right now, with the symbol and words so colour is never the only signal. */}}
+{{if .Work}}
+<p class="warn" role="alert"><strong>⚠ Something is running right now:</strong></p>
+<ul>
+{{range .Work}}<li>{{.}}</li>{{end}}
+</ul>
+{{end}}
+<p class="muted">You can start it again with <code>./bin/OllamaControlCenter</code>.</p>
+{{/* The two choices side by side. */}}
+<div class="choices">
+{{/* The confirm form sends the page token to the real stop. */}}
+<form method="post" action="/stop/confirm">
+<input type="hidden" name="token" value="{{.Token}}">
+<button type="submit" class="btn-solid">⏹ Yes, stop the monitor</button>
+</form>
+{{/* The safe choice goes back to the monitor and changes nothing. */}}
+<a class="btn-plain" href="/">No, keep it running</a>
+</div>
+{{/* Version 2: the last page. */}}
+{{else}}
+<h1>The monitor has stopped</h1>
+<p>Nothing is running any more. Ollama and its models were not touched.</p>
+<p class="muted">Start it again with <code>./bin/OllamaControlCenter</code> and reload this page.</p>
+{{end}}
+{{/* End of the panel. */}}
+</section>
+{{/* End of the content. */}}
+</main>
+</body>{{/* end of the visible page. */}}
+</html>{{/* end of the page. */}}
diff --git a/web/index.html b/web/index.html
index 7315f8c..b5ac2cb 100644
--- a/web/index.html
+++ b/web/index.html
@@ -13,6 +13,8 @@
 <title>OllamaControlCenter</title>
 {{/* Load our own stylesheet; the safety policy allows only styles from this same address. */}}
 <link rel="stylesheet" href="/app.css">
+{{/* While the page is being watched it reloads itself; Pause removes this line. It needs no script. */}}
+{{if not .Paused}}<meta http-equiv="refresh" content="{{.RefreshSeconds}}">{{end}}
 </head>{{/* end of the head. */}}
 <body>{{/* start of the visible page. */}}
 {{/* The page header. */}}
@@ -23,8 +25,50 @@
 <h1>OllamaControlCenter</h1>
 {{/* Show which Ollama is being watched and which setting supplied the address; a password in it is already hidden. */}}
 <p class="muted">Watching Ollama at <code>{{.Address}}</code> (from {{.AddressSource}})</p>
+{{/* Says whether the page updates by itself, and how fresh it is; the symbol and the words carry the meaning. */}}
+<p class="muted" id="watchline">{{if .Paused}}<span aria-hidden="true">⏸</span> Paused: the page does not update by itself. Page made at {{.UpdatedAt}}.{{else}}<span aria-hidden="true">▶</span> Watching: the page updates itself every {{.RefreshSeconds}} seconds. Page made at {{.UpdatedAt}}.{{end}}</p>
 {{/* End of the title block. */}}
 </div>
+{{/* The right side of the header: the monitor controls, then the theme switch. */}}
+<div class="headright">
+{{/* The monitor controls: pause or resume, refresh, and stop. */}}
+<div class="controls" role="group" aria-label="Monitor controls">
+{{/* Pause or Resume: one small form that sends the page token and the wanted action. */}}
+<form method="post" action="/watch">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* The area that opens the tip. */}}
+<span class="tipbox">
+{{/* While watching the button pauses; while paused it resumes. */}}
+{{if .Paused}}
+<button type="submit" name="action" value="resume" class="btn-plain ctlbtn" aria-describedby="tipwatch"><span aria-hidden="true">▶</span> Resume</button>
+<span class="tip tip-icon" role="tooltip" id="tipwatch">Make the page update itself every {{.RefreshSeconds}} seconds again</span>
+{{else}}
+<button type="submit" name="action" value="pause" class="btn-plain ctlbtn" aria-describedby="tipwatch"><span aria-hidden="true">⏸</span> Pause</button>
+<span class="tip tip-icon" role="tooltip" id="tipwatch">Stop the page from updating by itself; it keeps showing what it shows now until you resume or refresh</span>
+{{end}}
+{{/* End of the tip area. */}}
+</span>
+{{/* End of the pause form. */}}
+</form>
+{{/* Refresh: a plain link to the page, which asks Ollama once, right now. */}}
+<span class="tipbox">
+<a class="btn-plain ctlbtn" href="/" aria-describedby="tiprefresh"><span aria-hidden="true">↻</span> Refresh</a>
+<span class="tip tip-icon" role="tooltip" id="tiprefresh">Check Ollama once, right now</span>
+</span>
+{{/* Stop: a small form that goes to the question page; nothing is stopped yet. */}}
+<form method="post" action="/stop">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* The area that opens the tip. */}}
+<span class="tipbox">
+<button type="submit" class="unload ctlbtn" aria-describedby="tipstop"><span aria-hidden="true">⏹</span> Stop</button>
+<span class="tip tip-icon" role="tooltip" id="tipstop">Stop the monitor program (it asks first; Ollama and its models are not touched)</span>
+</span>
+{{/* End of the stop form. */}}
+</form>
+{{/* End of the controls. */}}
+</div>
 {{/* The theme form on the right: it sends the choice to the monitor, which saves it in a cookie. */}}
 <form class="themeform" method="post" action="/theme">
 {{/* The page token proves the form comes from this page. */}}
@@ -41,6 +85,8 @@
 <button type="submit" name="theme" value="light" class="switch to-light" aria-label="Switch to light theme"><span class="knob" aria-hidden="true">☾</span></button>
 {{/* End of the theme form. */}}
 </form>
+{{/* End of the right side of the header. */}}
+</div>
 </header>{{/* end of the header. */}}
 {{/* The main content area. */}}
 <main>
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
d45a1018ca1a4a31b62b0e579d32164fa48e27424a6d9d878c7efc76b6172036  control.go
a56a801b9d579f3f2d56e6728b24f84d94cc770d5234b70318fa5135fb74fa3d  control_test.go
ff09d6d26bdcd8a75bfe52a530924000e1cf602c93168fb0b95f5730e1a67653  load.go
b771f7775228f8e5bfa3dbb928d3be58959ec74f10308bcd875a78dd5587e3eb  main.go
e7cfe58827bc9f90bbee4e7df5f1f82b1eead8a02cb0c6a66a82cd81297e8fcf  perfpage.go
ba7520de1c643546ad7f14a0909e4eba0050e23800330abefe2e6cfb59aba4ee  web.go
8d8dfa296e7c6687f48639311e7fab35b647a607eb19530cf91828006744a205  web/app.css
4aff3890e8013548df9c0eca86a8a0420a3040c20932f83b0f9700edc1a7f355  web/control.html
09e5d3199bd9ea31bfa58bbd9bd616690263a6ee9f1fd8dc0146ba956c2b888d  web/index.html
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
