#!/usr/bin/env bash
# Script 69o: a twistie called Monitoring details folds the API health and Event log boxes away to save space. It is open by default; folding is remembered in a cookie (occ_details) for a year, and the event log keeps recording while it is folded. Version 0.18.0.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/monitoring-details" ] || { echo "FAIL  not on feature/monitoring-details"; exit 1; }
# Script 69n (event log) must be applied already (merged into main).
[ -e events.go ] || { echo "FAIL  script 69n was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e details.go ]; then
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
index 5c52473..f40bccc 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.17.0"
+const appVersion = "0.18.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/details.go b/details.go
new file mode 100644
index 0000000..580a48d
--- /dev/null
+++ b/details.go
@@ -0,0 +1,72 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// net/http serves the route and sets the cookie.
+	"net/http"
+) // end of imports
+
+// detailsCookieName is the cookie that remembers that the person folded the monitoring details away.
+const detailsCookieName = "occ_details"
+
+// detailsClosed says whether the request carries the cookie of a folded "Monitoring details" twistie.
+func detailsClosed(r *http.Request) bool {
+	// Look for the cookie.
+	c, err := r.Cookie(detailsCookieName)
+	// No cookie means the twistie is open, which is the default.
+	if err != nil {
+		// Open.
+		return false
+	} // end of the cookie check
+	// Only the exact word counts.
+	return c.Value == "closed"
+} // end of detailsClosed
+
+// detailsHandler folds or unfolds the monitoring details; it only sets a cookie and goes back to the page.
+func detailsHandler(token string) http.HandlerFunc {
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
+		// Close: remember it in the browser for a year.
+		case "close":
+			// Set the cookie.
+			http.SetCookie(w, &http.Cookie{Name: detailsCookieName, Value: "closed", Path: "/", MaxAge: themeCookieMaxAge, HttpOnly: true, SameSite: http.SameSiteStrictMode})
+		// Open: delete the cookie, because open is the default.
+		case "open":
+			// Delete it.
+			http.SetCookie(w, &http.Cookie{Name: detailsCookieName, Value: "", Path: "/", MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteStrictMode})
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
+} // end of detailsHandler
diff --git a/details_test.go b/details_test.go
new file mode 100644
index 0000000..8bc1feb
--- /dev/null
+++ b/details_test.go
@@ -0,0 +1,144 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// net/http provides the method names and the cookie type.
+	"net/http"
+	// net/url builds the form values.
+	"net/url"
+	// strings searches the page text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// TestDetailsTwistieDefaultsOpen checks that a person with no cookie sees both boxes and the hide button.
+func TestDetailsTwistieDefaultsOpen(t *testing.T) {
+	// A fake and a rig.
+	rig, _ := perfRig(t, newPerfFake())
+	// The page with no cookie.
+	page := pageWithCookie(t, rig, nil)
+	// The open state: the twistie, both boxes, the bubble and the hide button.
+	for _, w := range []string{`action="/details"`, `name="action" value="close"`, `aria-expanded="true"`, "Monitoring details", "click to hide", `aria-label="API health"`, `aria-labelledby="events-title"`, `id="tip-details"`, "Folds the API health and Event log boxes away"} {
+		// Look for it.
+		if !strings.Contains(page, w) {
+			// Report the gap.
+			t.Errorf("the open page lacks %q", w)
+		} // end of the check
+	} // end of the loop
+} // end of TestDetailsTwistieDefaultsOpen
+
+// TestDetailsTwistieFolded checks that the cookie hides both boxes but keeps the twistie, the models and the log running.
+func TestDetailsTwistieFolded(t *testing.T) {
+	// A fake and a rig.
+	f := newPerfFake()
+	// Build the rig.
+	rig, _ := perfRig(t, f)
+	// The folded page.
+	folded := &http.Cookie{Name: detailsCookieName, Value: "closed"}
+	// Ask for it.
+	page := pageWithCookie(t, rig, folded)
+	// Both boxes are gone.
+	for _, w := range []string{`aria-label="API health"`, `aria-labelledby="events-title"`, "Failed checks:", "Changes seen between two checks"} {
+		// It must be absent.
+		if strings.Contains(page, w) {
+			// Report it.
+			t.Errorf("the folded page still shows %q", w)
+		} // end of the check
+	} // end of the loop
+	// The twistie stays, offers to show, and the models box is still there.
+	for _, w := range []string{`name="action" value="open"`, `aria-expanded="false"`, "click to show", `aria-labelledby="installed-title"`} {
+		// Look for it.
+		if !strings.Contains(page, w) {
+			// Report the gap.
+			t.Errorf("the folded page lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// A model is loaded while the boxes are folded.
+	f.mu.Lock()
+	// In memory.
+	f.loaded["seen-while-folded:1b"] = true
+	// Release the fake.
+	f.mu.Unlock()
+	// The folded page is asked again, so the log sees the change.
+	pageWithCookie(t, rig, folded)
+	// Unfolded, the line is there: folding hides the log, it does not stop it.
+	if open := pageWithCookie(t, rig, nil); !strings.Contains(open, "Model loaded: seen-while-folded:1b") {
+		// Report the problem.
+		t.Errorf("the event log missed a change while it was folded")
+	} // end of the log check
+	// A cookie with another value does not fold.
+	if strings.Contains(pageWithCookie(t, rig, &http.Cookie{Name: detailsCookieName, Value: "yes"}), `value="open"`) {
+		// Report it.
+		t.Errorf("a wrong cookie value folded the details")
+	} // end of the value check
+} // end of TestDetailsTwistieFolded
+
+// TestDetailsHandler checks the cookie set by closing and opening, and the form rules.
+func TestDetailsHandler(t *testing.T) {
+	// A fake and a rig.
+	rig, _ := perfRig(t, newPerfFake())
+	// Closing sets the cookie and goes back to the page.
+	res := post(t, rig.h, "/details", url.Values{"token": {rig.token}, "action": {"close"}}, fromThisPage)
+	// A redirect to the page.
+	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/" {
+		// Report it.
+		t.Errorf("close: %d to %q", res.StatusCode, res.Header.Get("Location"))
+	} // end of the redirect check
+	// The cookie.
+	var closed *http.Cookie
+	// Find it.
+	for _, c := range res.Cookies() {
+		// The right one.
+		if c.Name == detailsCookieName {
+			// Keep it.
+			closed = c
+		} // end of the name check
+	} // end of the loop
+	// It says closed, lasts a year, is not readable by scripts and is not sent from other sites.
+	if closed == nil || closed.Value != "closed" || !closed.HttpOnly || closed.MaxAge != themeCookieMaxAge || closed.SameSite != http.SameSiteStrictMode {
+		// Report it.
+		t.Fatalf("close cookie wrong: %+v", closed)
+	} // end of the cookie check
+	// Opening deletes the cookie.
+	res = post(t, rig.h, "/details", url.Values{"token": {rig.token}, "action": {"open"}}, fromThisPage)
+	// A deleting cookie has a negative age.
+	gone := false
+	// Look at the cookies.
+	for _, c := range res.Cookies() {
+		// The right one, deleted.
+		if c.Name == detailsCookieName && c.MaxAge < 0 {
+			// Found.
+			gone = true
+		} // end of the check
+	} // end of the loop
+	// It must be deleted.
+	if res.StatusCode != http.StatusSeeOther || !gone {
+		// Report it.
+		t.Errorf("open: %d, deleted=%v", res.StatusCode, gone)
+	} // end of the open check
+	// The rules: a wrong token, another site and a bad action are refused without a cookie.
+	for name, tc := range map[string]struct {
+		// form is what is sent.
+		form url.Values
+		// headers are the request headers.
+		headers map[string]string
+		// want is the expected status.
+		want int
+	}{
+		"wrong token": {url.Values{"token": {"0123456789abcdef0123456789abcdef"}, "action": {"close"}}, fromThisPage, http.StatusForbidden},
+		"other site":  {url.Values{"token": {rig.token}, "action": {"close"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
+		"bad action":  {url.Values{"token": {rig.token}, "action": {"explode"}}, fromThisPage, http.StatusBadRequest},
+	} { // end of the cases
+		// Send it.
+		if res := post(t, rig.h, "/details", tc.form, tc.headers); res.StatusCode != tc.want || len(res.Cookies()) != 0 {
+			// Report it.
+			t.Errorf("%s: %d (cookies %d), want %d without cookies", name, res.StatusCode, len(res.Cookies()), tc.want)
+		} // end of the check
+	} // end of the loop
+	// A GET is not a route.
+	if status, _, _ := get(t, rig.h, http.MethodGet, "/details"); status != http.StatusMethodNotAllowed && status != http.StatusNotFound {
+		// Report it.
+		t.Errorf("GET /details = %d", status)
+	} // end of the GET check
+} // end of TestDetailsHandler
diff --git a/tooltips.go b/tooltips.go
index 69138fd..20a4d1a 100644
--- a/tooltips.go
+++ b/tooltips.go
@@ -23,7 +23,7 @@ var loadedColumns = []string{"Model", "Size (as reported)", "Memory on GPU", "Lo
 var gearHeadings = []string{"Set in the model", "Ollama's default", "Allowed values", "Context size", "Temperature", "Top-k", "Top-p", "Min-p", "Repeat penalty", "Repeat window", "Seed", "Answer length limit", "Stop words", "Keep-alive time"}
 
 // healthHeadings are the headings of the Ollama status panel on the main page that have a help bubble; a test checks each has a text.
-var healthHeadings = []string{"API health", "Event log"}
+var healthHeadings = []string{"Monitoring details", "API health", "Event log"}
 
 // perfHeadings are the indicator names on the performance page that have a help bubble; a test checks each has a text.
 var perfHeadings = []string{"Answer speed", "Prompt reading speed", "Load time", "Total time", "Time to first word", "Tokens counted", "Embedding time", "Vector length", "Processor split", "Memory used", "Change since the previous run", "CPU cores", "CPU load", "Memory free", "Swap in use", "Other models loaded", "GPU"}
@@ -31,6 +31,15 @@ var perfHeadings = []string{"Answer speed", "Prompt reading speed", "Load time",
 // helpTexts holds every tooltip, keyed by the exact heading text it belongs to.
 // The wording was checked against Ollama's documentation; "Max context length" and "Embedding length" are not described there.
 var helpTexts = map[string]tooltip{
+	// The twistie that folds the status panel and the event log away.
+	"Monitoring details": {
+		// What it means.
+		Plain: "Folds the API health and Event log boxes away to save space; this browser remembers your choice.",
+		// A real case.
+		Example: "Folded, one line stays and the Installed models box moves up.",
+		// What it helps with.
+		Decide: "Whether you want the status in view or more room for the models.",
+	}, // end of Monitoring details
 	// The Ollama status panel on the main page.
 	"API health": {
 		// What it means.
diff --git a/web.go b/web.go
index 9685169..5e022af 100644
--- a/web.go
+++ b/web.go
@@ -77,6 +77,10 @@ type pageData struct {
 	CompareCount int
 	// Paused is true when the person paused the automatic updates (a cookie remembers it).
 	Paused bool
+	// DetailsClosed is true when the person folded the monitoring details (API health and Event log) away; a cookie remembers it.
+	DetailsClosed bool
+	// DetailsTip is the help bubble of the twistie "Monitoring details".
+	DetailsTip tipView
 	// KeyOpen is true when the person opened the key to the symbols (the address then ends in ?key=open); the page does not update by itself meanwhile.
 	KeyOpen bool
 	// RefreshSeconds is how often the page updates itself while it is being watched.
@@ -116,6 +120,8 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	events := &eventLog{}
 	// The help bubble of its heading never changes either.
 	eventsTip := makeTip("tip-events", "Event log")
+	// The help bubble of the twistie that folds both away.
+	detailsTip := makeTip("tip-details", "Monitoring details")
 	// Create the page token: an unguessable value that every form on the page carries, so only this page can send a form (requirement S2).
 	token := mustToken()
 	// Create a router for the routes.
@@ -217,6 +223,8 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	mux.HandleFunc("POST /compare/csv", compareCSV)
 	// Route: a POST request for "/watch" pauses or resumes the automatic updates of the page.
 	mux.HandleFunc("POST /watch", watchHandler(token))
+	// Route: a POST request for "/details" folds or unfolds the monitoring details (API health and Event log).
+	mux.HandleFunc("POST /details", detailsHandler(token))
 	// The two steps of stopping the monitor.
 	stopAsk, stopConfirm := stopHandlers(token)
 	// Route: a POST request for "/stop" asks whether to stop the monitor and changes nothing.
@@ -263,6 +271,9 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 			CompareCount: perfHistory.testedModels(),
 			// Whether the automatic updates are paused.
 			Paused: watchPaused(r),
+			// Whether the monitoring details are folded away, and their help bubble.
+			DetailsClosed: detailsClosed(r),
+			DetailsTip:    detailsTip,
 			// Whether the key to the symbols is open.
 			KeyOpen: r.URL.Query().Get("key") == "open",
 			// The update interval.
diff --git a/web/app.css b/web/app.css
index cce1e0c..1e3a03b 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1084,7 +1084,7 @@ button.btn-plain {
 } /* end of rule */
 
 /* Every icon box is its own anchor: the name is private to each box, so a bubble finds only its own icon. */
-.gearform .tipbox, .comparebar .tipbox, .controls .tipbox, .lookstack .tipbox {
+.gearform .tipbox, .comparebar .tipbox, .controls .tipbox, .lookstack .tipbox, .detailsbar .tipbox {
   /* The name the bubble uses to find this box. */
   anchor-name: --tipicon;
   /* Keep the name inside this box, so the boxes of other rows never get mixed up. */
@@ -2039,3 +2039,23 @@ html[data-size="medium"] svg[width="22"] {
   /* Centre them vertically. */
   align-items: center;
 } /* end of rule */
+
+/* The twistie bar above API health and Event log: the fold button and its help mark side by side. */
+.detailsbar {
+  /* Button and help mark on one line. */
+  display: flex;
+  /* Centred on the same line. */
+  align-items: center;
+  /* A little space between them. */
+  gap: 0.5rem;
+  /* Wrap on a narrow screen. */
+  flex-wrap: wrap;
+  /* The same gap above as between the boxes; nothing below, because the next box leaves its own gap. */
+  margin: 1rem 0 0;
+} /* end of rule */
+
+/* The fold button reads like a heading of the folded part. */
+.detailsbtn {
+  /* Bold, like the key twistie. */
+  font-weight: 600;
+} /* end of rule */
diff --git a/web/index.html b/web/index.html
index 749fbcc..4246a5d 100644
--- a/web/index.html
+++ b/web/index.html
@@ -133,6 +133,23 @@
 </header>{{/* end of the header. */}}
 {{/* The main content area. */}}
 <main>
+{{/* The twistie bar: one small form that folds or unfolds the two boxes below; the arrow is decoration, the words carry the meaning. */}}
+<div class="detailsbar">
+<form method="post" action="/details">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* Open: the button folds; folded: the button unfolds. */}}
+{{if .DetailsClosed}}
+<button type="submit" name="action" value="open" class="btn-plain detailsbtn" aria-expanded="false"><span aria-hidden="true">&#9656;</span> Monitoring details <span class="keyhint">(API health, Event log; click to show)</span></button>
+{{else}}
+<button type="submit" name="action" value="close" class="btn-plain detailsbtn" aria-expanded="true"><span aria-hidden="true">&#9662;</span> Monitoring details <span class="keyhint">(click to hide)</span></button>
+{{end}}
+</form>
+{{/* The help bubble of the twistie. */}}
+<span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.DetailsTip.ID}}">?</span><span class="tip" role="tooltip" id="{{.DetailsTip.ID}}">{{template "tip" .DetailsTip}}</span></span>
+</div>
+{{/* The two boxes are drawn only while the twistie is open. */}}
+{{if not .DetailsClosed}}
 {{/* The status panel; aria-live asks screen readers to announce changes. */}}
 <section class="panel" aria-label="API health" aria-live="polite">
 {{/* The panel heading, with its help bubble; the bubble says that this is the Ollama status. */}}
@@ -173,6 +190,8 @@
 <p>Nothing seen yet.</p>
 {{end}}
 </section>
+{{/* End of the folded part. */}}
+{{end}}
 {{/* The Installed models panel. */}}
 <section class="panel" aria-labelledby="installed-title">
 {{/* The panel heading, with the number of models when known. */}}
diff --git a/webtable_test.go b/webtable_test.go
index 1d498a0..bf17963 100644
--- a/webtable_test.go
+++ b/webtable_test.go
@@ -135,9 +135,9 @@ func TestTableHelpForEveryHeading(t *testing.T) {
 	// Fake Ollama with the six real models.
 	body := pageFor(t, fullOllama(t, realModels, realPsBody))
 	// Ten column bubbles, two category bubbles and the bubbles of the API health and Event log headings; the short tips of the row icons are counted apart.
-	if n := strings.Count(body, `role="tooltip"`) - strings.Count(body, `class="tip tip-icon"`); n != 14 {
+	if n := strings.Count(body, `role="tooltip"`) - strings.Count(body, `class="tip tip-icon"`); n != 15 {
 		// Report the difference.
-		t.Errorf("%d bubbles, want 14", n)
+		t.Errorf("%d bubbles, want 15", n)
 	} // end of the bubble count
 	// Every column title must be a focusable heading.
 	for _, col := range installedColumns {
@@ -155,9 +155,9 @@ func TestTableHelpForEveryHeading(t *testing.T) {
 	// Find every aria-describedby value.
 	refs := regexp.MustCompile(`aria-describedby="([^"]+)"`).FindAllStringSubmatch(body, -1)
 	// There must be one per bubble (the row icons have their own, counted apart).
-	if n := len(refs) - strings.Count(body, `class="tip tip-icon"`); n != 14 {
+	if n := len(refs) - strings.Count(body, `class="tip tip-icon"`); n != 15 {
 		// Report the difference.
-		t.Errorf("%d aria-describedby attributes, want 14", n)
+		t.Errorf("%d aria-describedby attributes, want 15", n)
 	} // end of the reference count
 	// Each one must point at an element that exists.
 	for _, m := range refs {
@@ -189,7 +189,7 @@ func TestTableAccessibility(t *testing.T) {
 		// The scroll box is a labelled region that the keyboard can reach.
 		{`role="region"`, 2},
 		// Fourteen headings (ten columns, two categories, API health and Event log) plus the two scroll boxes (models and event log) can take the focus.
-		{`tabindex="0"`, 16},
+		{`tabindex="0"`, 17},
 	} { // end of the list
 		// Count it.
 		if n := strings.Count(body, c.text); n != c.want {
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
5d6d6f24881dbada8b115956f8a023dab91228c0f9279a23afa87c4b2b665aff  about.go
e997879344d080e71eece95d20c967954374f7a05f745fdedb1f7f6e682e50a6  tooltips.go
28d663eddd0ac7ac3ce67162e157f686bccb7788b332169101b16680198ee0f4  web.go
43c8af409c04c6c3d2d6b343dffa6380e72f108f96e5786f36d8c526ad0ac362  web/index.html
8a99f48555fb69ef6646ddacb473af44e41932fdddf07e5d83fdb30c89d03304  web/app.css
0279674522f45bf8e8c14d4ce47a0ad9b3478345a69d3059aa463b18c2d9ab62  webtable_test.go
e887bede4a87ff718fa8b0a6628d38f64ae382655116469668bd5b2b27162451  details.go
e5a5fb75c60b8dd3e17c9eb6c1380aee6c0470933785560e50ad77c3620daa69  details_test.go
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
echo "NEXT  start ./bin/OllamaControlCenter and look for the Monitoring details twistie above API health, click it to fold and unfold"
# List the changed files; nothing is committed yet.
git status --short
