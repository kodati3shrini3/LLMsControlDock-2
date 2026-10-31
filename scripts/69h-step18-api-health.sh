#!/usr/bin/env bash
# Script 69h: three changes in one branch. (1) .gitignore keeps stray comparison PDF and CSV files out of git. (2) The flaky gear test prints the server reply if it fails again. (3) F5: the API health panel shows failed checks in a row and in total, and the last successful check.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/ollama-status-counters" ] || { echo "FAIL  not on feature/ollama-status-counters"; exit 1; }
# Script 69g must be applied already (merged into main).
grep -q "func writeNoticeBlock" compreport.go && [ -e copy.go ] || { echo "FAIL  script 69g was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e health.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/.gitignore b/.gitignore
index 3d2c112..8ffe18f 100644
--- a/.gitignore
+++ b/.gitignore
@@ -33,3 +33,6 @@ settings.json
 .vscode/
 .idea/
 .DS_Store
+
+# Stray files from saving a comparison with the browser (PDF and CSV): they must never reach GitHub
+OllamaControlCenter-comparison*
diff --git a/gear_test.go b/gear_test.go
index a0b297b..f603dad 100644
--- a/gear_test.go
+++ b/gear_test.go
@@ -774,6 +774,17 @@ func TestGearNotInstalled(t *testing.T) {
 	} // end of the change check
 } // end of TestGearNotInstalled
 
+// briefBody shortens a reply to its first 400 characters, so a failing test prints what the server answered without flooding the screen.
+func briefBody(body string) string {
+	// A short reply is shown whole.
+	if len(body) <= 400 {
+		// Hand it back.
+		return body
+	} // end of the short check
+	// A long reply is cut and marked.
+	return body[:400] + " ...[cut]"
+} // end of briefBody
+
 // TestGearRejectsBadValues checks every bad value of every setting is refused on the review step and on the save step, shown back escaped with a reason, and never reaches Ollama.
 func TestGearRejectsBadValues(t *testing.T) {
 	// A fake where seed and num_ctx are saved too, so "emptying" would mean losing something.
@@ -816,17 +827,17 @@ func TestGearRejectsBadValues(t *testing.T) {
 				// The settings page comes back with the reason, and no confirm button.
 				if status != http.StatusOK || !strings.Contains(body, "Not saved.") || !strings.Contains(body, `role="alert"><strong>⚠</strong>`) || strings.Contains(body, "Yes, save them into the model") {
 					// Report the problem.
-					t.Errorf("%s %s %q: status %d", path, key, v, status)
+					t.Errorf("%s %s %q: status %d, reply: %s", path, key, v, status, briefBody(body))
 				} // end of the check
 				// An empty value of a saved setting gets its own, clear reason.
 				if strings.TrimSpace(v) == "" && !strings.Contains(body, "cannot be empty") {
 					// Report the problem.
-					t.Errorf("%s %s %q: no 'cannot be empty' reason", path, key, v)
+					t.Errorf("%s %s %q: no 'cannot be empty' reason, reply: %s", path, key, v, briefBody(body))
 				} // end of the empty check
 				// Markup must come back escaped.
 				if strings.Contains(body, "<script>alert") || strings.Contains(body, "<b>") {
 					// Report the problem.
-					t.Errorf("%s %s: unescaped markup in the page", path, key)
+					t.Errorf("%s %s: unescaped markup in the page, reply: %s", path, key, briefBody(body))
 				} // end of the escape check
 			} // end of the path loop
 		} // end of the value loop
@@ -836,12 +847,12 @@ func TestGearRejectsBadValues(t *testing.T) {
 	// Nothing is saved.
 	if !strings.Contains(body, "Not saved.") {
 		// Report the problem.
-		t.Errorf("a good value was saved next to a bad one")
+		t.Errorf("a good value was saved next to a bad one, reply: %s", briefBody(body))
 	} // end of the mixed check
 	// Nothing reached Ollama.
 	if f.createCount() != 0 {
 		// Report the problem.
-		t.Errorf("a bad value was sent to Ollama")
+		t.Errorf("a bad value was sent to Ollama, create requests: %v", f.creates)
 	} // end of the change check
 	// The saved values are untouched.
 	if got := f.saved("num_ctx"); len(got) != 1 || got[0] != "4096" {
diff --git a/health.go b/health.go
new file mode 100644
index 0000000..813e0d1
--- /dev/null
+++ b/health.go
@@ -0,0 +1,66 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// sync keeps two page requests from changing the counters at the same moment.
+	"sync"
+	// time holds the moment of the last good check.
+	"time"
+) // end of imports
+
+// healthTimeLayout is how the moment of the last successful check is written; it always carries the time zone name, as every time on every page does.
+const healthTimeLayout = "2 Jan 2006 15:04:05 MST"
+
+// healthNever is shown when no check has succeeded since the monitor started.
+const healthNever = "none since this monitor started"
+
+// apiHealth counts the checks of Ollama's API (the check that asks for its version). It lives in memory only: it starts again from zero when the monitor program starts, and it never stores any text of prompts or answers.
+type apiHealth struct {
+	// mu protects the counters below.
+	mu sync.Mutex
+	// failedRow is the number of failed checks since the last successful one.
+	failedRow int
+	// failedTotal is the number of failed checks since the monitor started.
+	failedTotal int
+	// lastOK is the moment of the last successful check (zero when there was none).
+	lastOK time.Time
+} // end of apiHealth
+
+// healthView is what the page shows.
+type healthView struct {
+	// FailedRow is the number of failed checks in a row.
+	FailedRow int
+	// FailedTotal is the number of failed checks in total since the monitor started.
+	FailedTotal int
+	// LastOK is the last successful check, with its time zone, or healthNever.
+	LastOK string
+} // end of healthView
+
+// record counts one check made at the given moment and returns what the page shows afterwards.
+func (h *apiHealth) record(online bool, now time.Time) healthView {
+	// One request at a time.
+	h.mu.Lock()
+	// Release at the end.
+	defer h.mu.Unlock()
+	// A good check ends the run of failures and remembers the moment.
+	if online {
+		// The run of failures is over.
+		h.failedRow = 0
+		// Remember when.
+		h.lastOK = now
+	} else {
+		// One more failure in a row.
+		h.failedRow++
+		// One more in total.
+		h.failedTotal++
+	} // end of the online check
+	// The text for the last good check.
+	last := healthNever
+	// There was one.
+	if !h.lastOK.IsZero() {
+		// Write it with its time zone.
+		last = h.lastOK.Format(healthTimeLayout)
+	} // end of the last-check text
+	// What the page shows.
+	return healthView{FailedRow: h.failedRow, FailedTotal: h.failedTotal, LastOK: last}
+} // end of record
diff --git a/health_test.go b/health_test.go
new file mode 100644
index 0000000..fe7fe97
--- /dev/null
+++ b/health_test.go
@@ -0,0 +1,148 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// fmt builds the fake Ollama's replies.
+	"fmt"
+	// net/http serves the fake Ollama.
+	"net/http"
+	// net/http/httptest runs the fake Ollama.
+	"net/http/httptest"
+	// regexp checks that the time carries a zone.
+	"regexp"
+	// strings searches the page.
+	"strings"
+	// sync keeps the counters test free of races.
+	"sync"
+	// sync/atomic switches the fake Ollama on and off.
+	"sync/atomic"
+	// testing is Go's test framework.
+	"testing"
+	// time gives fixed moments.
+	"time"
+) // end of imports
+
+// timeWithZone matches the last successful check as the page writes it: day, month, year, clock time with seconds, and a zone name or offset.
+var timeWithZone = regexp.MustCompile(`Last successful check: <strong>\d{1,2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} [A-Za-z0-9+\-]+</strong>`)
+
+// TestAPIHealthCounts checks the rules: failures in a row restart at zero after a good check, the total only grows, and the last good check carries its time zone.
+func TestAPIHealthCounts(t *testing.T) {
+	// A fixed zone with a name, so the text can be checked.
+	cet := time.FixedZone("CET", 3600)
+	// The counters.
+	h := &apiHealth{}
+	// A first failure: nothing has succeeded yet.
+	if v := h.record(false, time.Date(2026, 10, 31, 14, 0, 0, 0, cet)); v.FailedRow != 1 || v.FailedTotal != 1 || v.LastOK != healthNever {
+		// Report it.
+		t.Errorf("first failure: %+v", v)
+	} // end of the first check
+	// A second failure.
+	if v := h.record(false, time.Date(2026, 10, 31, 14, 1, 0, 0, cet)); v.FailedRow != 2 || v.FailedTotal != 2 {
+		// Report it.
+		t.Errorf("second failure: %+v", v)
+	} // end of the second check
+	// A good check: the run ends, the total stays, the moment is written with its zone.
+	if v := h.record(true, time.Date(2026, 10, 31, 14, 55, 12, 0, cet)); v.FailedRow != 0 || v.FailedTotal != 2 || v.LastOK != "31 Oct 2026 14:55:12 CET" {
+		// Report it.
+		t.Errorf("good check: %+v", v)
+	} // end of the good check
+	// Another failure: a new run of one, the total grows, the last good moment is kept.
+	if v := h.record(false, time.Date(2026, 10, 31, 15, 0, 0, 0, cet)); v.FailedRow != 1 || v.FailedTotal != 3 || v.LastOK != "31 Oct 2026 14:55:12 CET" {
+		// Report it.
+		t.Errorf("failure after success: %+v", v)
+	} // end of the last check
+} // end of TestAPIHealthCounts
+
+// TestAPIHealthIsSafeForManyRequests checks that many page requests at once lose no count.
+func TestAPIHealthIsSafeForManyRequests(t *testing.T) {
+	// The counters.
+	h := &apiHealth{}
+	// Wait for all the goroutines.
+	var wg sync.WaitGroup
+	// One hundred failing checks at once.
+	for i := 0; i < 100; i++ {
+		// Count the goroutine.
+		wg.Add(1)
+		// Start it.
+		go func() {
+			// Done at the end.
+			defer wg.Done()
+			// One failed check.
+			h.record(false, time.Now())
+		}() // end of the goroutine
+	} // end of the loop
+	// Wait.
+	wg.Wait()
+	// Nothing was lost.
+	if v := h.record(false, time.Now()); v.FailedTotal != 101 || v.FailedRow != 101 {
+		// Report it.
+		t.Errorf("counts after 101 failures: %+v", v)
+	} // end of the count check
+} // end of TestAPIHealthIsSafeForManyRequests
+
+// TestMainPageShowsTheCounters checks the page through the real handler: the heading with its bubble, the counters growing while Ollama is down, the run ending when it answers, and the last good check with its time zone.
+func TestMainPageShowsTheCounters(t *testing.T) {
+	// A fake Ollama that can be switched off.
+	var up atomic.Bool
+	// Start it down.
+	up.Store(false)
+	// The server.
+	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
+		// Down: an error for everything.
+		if !up.Load() {
+			// A server error.
+			http.Error(w, "down", http.StatusInternalServerError)
+			// Stop here.
+			return
+		} // end of the down check
+		// Up: the version, and empty lists for the rest.
+		if r.URL.Path == "/api/version" {
+			// The version.
+			fmt.Fprint(w, `{"version":"0.34.4"}`)
+			// Stop here.
+			return
+		} // end of the version check
+		// Empty lists.
+		fmt.Fprint(w, `{"models":[]}`)
+	})) // end of the handler
+	// Stop it at the end.
+	t.Cleanup(srv.Close)
+	// The monitor, built once so its counters live across requests.
+	h := handlerFor(t, srv.URL)
+	// Fetch the page.
+	page := func() string {
+		// Ask.
+		_, _, body := get(t, h, http.MethodGet, "/")
+		// The text.
+		return body
+	} // end of page
+	// The first page while Ollama is down.
+	body := page()
+	// The heading, its bubble that names the Ollama status, and the first counters.
+	for _, want := range []string{`>API health</span>`, "Ollama status: does Ollama answer", "Failed checks: <strong>1</strong> in a row, <strong>1</strong> in total since this monitor started", "Last successful check: <strong>none since this monitor started</strong>", "⚠"} {
+		// Missing.
+		if !strings.Contains(body, want) {
+			// Report it.
+			t.Errorf("first page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// A second page while still down.
+	if body = page(); !strings.Contains(body, "<strong>2</strong> in a row, <strong>2</strong> in total") {
+		// Report it.
+		t.Errorf("second failure not counted")
+	} // end of the second check
+	// Ollama comes back.
+	up.Store(true)
+	// The next page.
+	body = page()
+	// The run ended, the total stayed, and the last good check has a time zone name.
+	if !strings.Contains(body, "<strong>0</strong> in a row, <strong>2</strong> in total") || strings.Contains(body, "⚠ Failed checks") || strings.Contains(body, "none since this monitor started") {
+		// Report it.
+		t.Errorf("recovery not shown: %.400s", body)
+	} // end of the recovery check
+	// The time carries a zone: letters or a numeric offset after the clock time.
+	if !timeWithZone.MatchString(body) {
+		// Report it.
+		t.Errorf("the last successful check shows no time zone")
+	} // end of the zone check
+} // end of TestMainPageShowsTheCounters
diff --git a/tooltips.go b/tooltips.go
index 587b87e..595d153 100644
--- a/tooltips.go
+++ b/tooltips.go
@@ -22,12 +22,24 @@ var loadedColumns = []string{"Model", "Size (as reported)", "Memory on GPU", "Lo
 // gearHeadings are the headings on the settings page and the Load page that have a help bubble, in the order they appear; a test checks each has a text.
 var gearHeadings = []string{"Set in the model", "Ollama's default", "Allowed values", "Context size", "Temperature", "Top-k", "Top-p", "Min-p", "Repeat penalty", "Repeat window", "Seed", "Answer length limit", "Stop words", "Keep-alive time"}
 
+// healthHeadings are the headings of the Ollama status panel on the main page that have a help bubble; a test checks each has a text.
+var healthHeadings = []string{"API health"}
+
 // perfHeadings are the indicator names on the performance page that have a help bubble; a test checks each has a text.
 var perfHeadings = []string{"Answer speed", "Prompt reading speed", "Load time", "Total time", "Time to first word", "Tokens counted", "Embedding time", "Vector length", "Processor split", "Memory used", "Change since the previous run", "CPU cores", "CPU load", "Memory free", "Swap in use", "Other models loaded", "GPU"}
 
 // helpTexts holds every tooltip, keyed by the exact heading text it belongs to.
 // The wording was checked against Ollama's documentation; "Max context length" and "Embedding length" are not described there.
 var helpTexts = map[string]tooltip{
+	// The Ollama status panel on the main page.
+	"API health": {
+		// What it means.
+		Plain: "Ollama status: does Ollama answer, how many checks failed, and when it last answered correctly.",
+		// A real case.
+		Example: "3 failed in a row means Ollama has not answered the last 3 checks.",
+		// What it helps with.
+		Decide: "Whether Ollama is steady enough to rely on right now.",
+	}, // end of API health
 	// The model name, shared by both tables.
 	"Model": {
 		// What it means.
diff --git a/tooltips_test.go b/tooltips_test.go
index 96ed4f1..1b41ac5 100644
--- a/tooltips_test.go
+++ b/tooltips_test.go
@@ -30,6 +30,8 @@ func allHeadings() []string {
 	} // end of the column loop
 	// Then the headings of the settings page and the Load page.
 	out = append(out, gearHeadings...)
+	// The Ollama status panel heading on the main page.
+	out = append(out, healthHeadings...)
 	// The performance page headings.
 	out = append(out, perfHeadings...)
 	// The comparison page headings that are not shared with other pages.
diff --git a/web.go b/web.go
index 8a534da..f09910c 100644
--- a/web.go
+++ b/web.go
@@ -63,6 +63,10 @@ type pageData struct {
 	HeaderURL string
 	// FooterURL is the company website address for the footer bar.
 	FooterURL string
+	// Health holds the counters of failed checks and the last successful check.
+	Health healthView
+	// HealthTip is the help bubble of the panel heading "API health".
+	HealthTip tipView
 	// Token is the page token that every form on the page carries.
 	Token string
 	// CompareCount is how many models have a saved performance test that can be compared.
@@ -98,6 +102,10 @@ func secureHeaders(next http.Handler) http.Handler {
 func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	// Read the template once; Must stops the program at start-up if the template is broken, which a test would catch first.
 	page := template.Must(template.New("index").Parse(indexTemplateText))
+	// The counters of failed checks live as long as the monitor runs.
+	health := &apiHealth{}
+	// The help bubble of the panel heading never changes, so build it once.
+	healthTip := makeTip("tip-health", "API health")
 	// Create the page token: an unguessable value that every form on the page carries, so only this page can send a form (requirement S2).
 	token := mustToken()
 	// Create a router for the routes.
@@ -217,6 +225,8 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 			Version: res.Version,
 			// The time taken.
 			ElapsedMs: res.Elapsed.Milliseconds(),
+			// The counters after this check, and the bubble of the heading.
+			Health: health.record(res.Online, time.Now()), HealthTip: healthTip,
 			// The reason, if offline.
 			Reason: res.Reason,
 			// The saved theme choice, from the cookie; empty means follow the system.
diff --git a/web/index.html b/web/index.html
index af2ff94..3e3e429 100644
--- a/web/index.html
+++ b/web/index.html
@@ -133,9 +133,9 @@
 {{/* The main content area. */}}
 <main>
 {{/* The status panel; aria-live asks screen readers to announce changes. */}}
-<section class="panel" aria-labelledby="status-title" aria-live="polite">
-{{/* The panel heading. */}}
-<h2 id="status-title">Ollama status</h2>
+<section class="panel" aria-label="API health" aria-live="polite">
+{{/* The panel heading, with its help bubble; the bubble says that this is the Ollama status. */}}
+<h2 id="status-title"><span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.HealthTip.ID}}">{{.HealthTip.Title}}</span><span class="tip" role="tooltip" id="{{.HealthTip.ID}}">{{template "tip" .HealthTip}}</span></span></h2>
 {{/* Online: a tick, the word Online, the version and the reply time. */}}
 {{if .Online}}
 {{/* The class ok colours the line, but the tick and the word carry the meaning. */}}
@@ -146,6 +146,8 @@
 <p class="status bad"><span class="symbol" aria-hidden="true">✖</span> <strong>Offline</strong> <span class="muted">{{.Reason}} ({{.ElapsedMs}} ms)</span></p>
 {{/* End of the online check. */}}
 {{end}}
+{{/* The counters: failed checks in a row and in total, and the last successful check with its time zone; the warning sign and the words both show a problem. */}}
+<p class="muted healthline">{{if .Health.FailedRow}}<span class="symbol" aria-hidden="true">⚠</span> {{end}}Failed checks: <strong>{{.Health.FailedRow}}</strong> in a row, <strong>{{.Health.FailedTotal}}</strong> in total since this monitor started. Last successful check: <strong>{{.Health.LastOK}}</strong>.</p>
 {{/* End of the status panel. */}}
 </section>
 {{/* The Installed models panel. */}}
diff --git a/webtable_test.go b/webtable_test.go
index efd6d72..3a1447e 100644
--- a/webtable_test.go
+++ b/webtable_test.go
@@ -134,10 +134,10 @@ func TestTablePageRealModels(t *testing.T) {
 func TestTableHelpForEveryHeading(t *testing.T) {
 	// Fake Ollama with the six real models.
 	body := pageFor(t, fullOllama(t, realModels, realPsBody))
-	// Ten column bubbles plus two category bubbles; the short tips of the row icons are counted apart.
-	if n := strings.Count(body, `role="tooltip"`) - strings.Count(body, `class="tip tip-icon"`); n != 12 {
+	// Ten column bubbles, two category bubbles and the bubble of the API health heading; the short tips of the row icons are counted apart.
+	if n := strings.Count(body, `role="tooltip"`) - strings.Count(body, `class="tip tip-icon"`); n != 13 {
 		// Report the difference.
-		t.Errorf("%d bubbles, want 12", n)
+		t.Errorf("%d bubbles, want 13", n)
 	} // end of the bubble count
 	// Every column title must be a focusable heading.
 	for _, col := range installedColumns {
@@ -155,9 +155,9 @@ func TestTableHelpForEveryHeading(t *testing.T) {
 	// Find every aria-describedby value.
 	refs := regexp.MustCompile(`aria-describedby="([^"]+)"`).FindAllStringSubmatch(body, -1)
 	// There must be one per bubble (the row icons have their own, counted apart).
-	if n := len(refs) - strings.Count(body, `class="tip tip-icon"`); n != 12 {
+	if n := len(refs) - strings.Count(body, `class="tip tip-icon"`); n != 13 {
 		// Report the difference.
-		t.Errorf("%d aria-describedby attributes, want 12", n)
+		t.Errorf("%d aria-describedby attributes, want 13", n)
 	} // end of the reference count
 	// Each one must point at an element that exists.
 	for _, m := range refs {
@@ -188,8 +188,8 @@ func TestTableAccessibility(t *testing.T) {
 		{`scope="colgroup"`, 2},
 		// The scroll box is a labelled region that the keyboard can reach.
 		{`role="region"`, 1},
-		// Twelve headings plus the scroll box can take the focus.
-		{`tabindex="0"`, 13},
+		// Thirteen headings (ten columns, two categories and API health) plus the scroll box can take the focus.
+		{`tabindex="0"`, 14},
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
0d7954d3778904b48fdf2ddb2ef2e91ced806d5d8b607e19505c410853ae6203  .gitignore
aff410686aa226329adc11f45499d081f5737f3569b8a641b233e52ff9350894  gear_test.go
24757519047721a5d6b5f3b0022ac4c2eb0250fd4c759fe7394246d987b5bb10  tooltips.go
31d44f937b1c8b098ee91f64e65575fbe53fb0e467b01d0f632f7f8db0def101  tooltips_test.go
17440d97c86dd6c5e86b3f885e7671f79858ae181411f3907cad52c95cf8e51e  web.go
9ba1a0edf59e32af7ac406fe82e30202d7ace2e90c26b559d456a681e0c63961  web/index.html
8841d9dab9da64bb8a48bfcd28c67fffe6cb4b58b75a4abbfe968478412a32d1  webtable_test.go
960cdfb639571b855a32de4e87153c1246fb1599317f28850b949028b4eb9420  health.go
5f5a927767e7d0432087b2a13404cdfc4cadbcba17d9ac8d3e89dce8bd067dc4  health_test.go
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
