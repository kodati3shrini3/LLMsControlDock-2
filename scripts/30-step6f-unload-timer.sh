#!/usr/bin/env bash
# Script 30: unload timer next to "Loaded" on the main page, delivered the pull-request way (new branch, nothing committed yet).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# The branch this change lives on.
BRANCH="feature/loaded-unload-countdown"
# Refuse to start anywhere but on main, so the branch grows from the right place.
[ "$(git branch --show-current)" = "main" ] || { echo "FAIL  not on main"; exit 1; }
# Refuse to start with other uncommitted changes (this script file itself is allowed).
[ -z "$(git status --porcelain | grep -v 'scripts/30-' || true)" ] || { echo "FAIL  uncommitted changes exist:"; git status --short; exit 1; }
# Refuse to start when the branch name is already taken.
! git rev-parse --verify --quiet "$BRANCH" > /dev/null || { echo "FAIL  branch $BRANCH already exists"; exit 1; }
# A temporary file that holds the change as a patch (a list of added and removed lines).
PATCH_FILE="$(mktemp)"
# Remove the temporary file when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/countdown.go b/countdown.go
index d8455e3..b591015 100644
--- a/countdown.go
+++ b/countdown.go
@@ -18,6 +18,9 @@ var countdownJS []byte
 // contentSecurityPolicyWithScript is the policy for the message pages that show a ticking timer: the same as the main page plus scripts from this same address only (no inline scripts, no other sites).
 const contentSecurityPolicyWithScript = "default-src 'none'; style-src 'self'; script-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
 
+// contentSecurityPolicyMainPage is the policy for the main page when it shows the table: the message-page policy plus connect-src 'self', so the script can ask this same address for fresh figures (still no inline scripts, no other sites).
+const contentSecurityPolicyMainPage = contentSecurityPolicyWithScript + "; connect-src 'self'"
+
 // countdownHandler sends the script file.
 func countdownHandler(w http.ResponseWriter, r *http.Request) {
 	// Tell the browser this is JavaScript.
diff --git a/load_test.go b/load_test.go
index f52bead..3934197 100644
--- a/load_test.go
+++ b/load_test.go
@@ -179,10 +179,10 @@ func TestLoadButtonOnlyOnNotLoadedRows(t *testing.T) {
 		// Report the problem.
 		t.Errorf("a loaded model has a Load button")
 	} // end of the other check
-	// The main page itself must stay free of scripts and keep the strict policy.
-	if strings.Contains(body, "<script") {
+	// The main page may load the monitor's own script file and nothing else: exactly one script tag, with no inline code.
+	if n := strings.Count(body, "<script"); n != 1 || !strings.Contains(body, `<script src="/countdown.js" defer></script>`) {
 		// Report the problem.
-		t.Errorf("the main page contains a script")
+		t.Errorf("the main page has %d script tags, want only the countdown.js one", n)
 	} // end of the script check
 } // end of TestLoadButtonOnlyOnNotLoadedRows
 
@@ -510,20 +510,33 @@ func TestUnloadWarningHasLiveTimer(t *testing.T) {
 	} // end of the policy check
 } // end of TestUnloadWarningHasLiveTimer
 
-// TestMainPolicyStaysStrict checks the main page keeps the policy without scripts.
-func TestMainPolicyStaysStrict(t *testing.T) {
+// TestMainPolicyAllowsOnlyOwnScript checks the main page policy allows the monitor's own script and requests to its own address, and nothing inline or from elsewhere.
+func TestMainPolicyAllowsOnlyOwnScript(t *testing.T) {
 	// A fake with nothing loaded.
 	f := &loadFake{}
 	// Build the rig.
 	rig := loadRig(t, f, 16e9)
 	// Fetch the page and its headers.
 	_, header, _ := get(t, rig.h, http.MethodGet, "/")
-	// No script rule at all.
-	if csp := header.Get("Content-Security-Policy"); strings.Contains(csp, "script-src") {
-		// Report the problem.
-		t.Errorf("the main page policy allows scripts: %s", csp)
-	} // end of the policy check
-} // end of TestMainPolicyStaysStrict
+	// The policy as sent.
+	csp := header.Get("Content-Security-Policy")
+	// It must allow scripts and requests from this address only.
+	for _, want := range []string{"default-src 'none'", "script-src 'self'", "connect-src 'self'"} {
+		// Look for it.
+		if !strings.Contains(csp, want) {
+			// Report the problem.
+			t.Errorf("the main page policy lacks %q: %s", want, csp)
+		} // end of the check
+	} // end of the loop
+	// It must never allow inline code or code from other sites.
+	for _, bad := range []string{"unsafe-inline", "unsafe-eval", "http:", "https:", "*"} {
+		// Look for it.
+		if strings.Contains(csp, bad) {
+			// Report the problem.
+			t.Errorf("the main page policy contains %q: %s", bad, csp)
+		} // end of the check
+	} // end of the loop
+} // end of TestMainPolicyAllowsOnlyOwnScript
 
 // TestCountdownScriptIsServed checks the script file is sent as JavaScript.
 func TestCountdownScriptIsServed(t *testing.T) {
diff --git a/tableview.go b/tableview.go
index 2c5e97a..bfd7781 100644
--- a/tableview.go
+++ b/tableview.go
@@ -6,6 +6,8 @@ import ( // import lists the standard-library packages this file uses.
 	"fmt"
 	// strings joins the abilities into one cell.
 	"strings"
+	// time provides the clock reading the unload timer is worked out from.
+	"time"
 ) // end of imports
 
 // tipView is one help bubble as the page template needs it.
@@ -34,6 +36,12 @@ type rowView struct {
 	Loaded bool
 	// StateWord is "Loaded" or "Not loaded"; the page shows it next to the dot.
 	StateWord string
+	// Timer is the text of the unload timer for a loaded model (empty for a model that is not loaded).
+	Timer string
+	// TimerSeconds is the whole seconds left when the timer should tick (0 means a fixed text such as "stays loaded").
+	TimerSeconds int
+	// TimerExpired is true when the unload time has arrived but Ollama still lists the model; the page asks again soon.
+	TimerExpired bool
 } // end of rowView
 
 // groupView is one category section.
@@ -88,8 +96,51 @@ func stateWord(loaded bool) string {
 	return "Not loaded"
 } // end of stateWord
 
-// buildTableView turns the installed and loaded lists into the data the page template draws.
+// longKeepText is shown for a model that Ollama keeps loaded indefinitely (its keep-alive is set to never unload).
+const longKeepText = "stays loaded"
+
+// timerFor works out the text, the ticking seconds and the "time has arrived" flag of the unload timer for one loaded model.
+func timerFor(l loadedModel, now time.Time) (string, int, bool) {
+	// Read the unload time; ok is false when it is missing or unreadable.
+	expires, ok := l.expiresTime()
+	// No usable time: say so, and do not tick.
+	if !ok {
+		// The same wording as the terminal table.
+		return formatRemaining(now, expires, ok), 0, false
+	} // end of the no-time case
+	// How long is left.
+	left := expires.Sub(now)
+	// So far away that the model is set to stay loaded: a fixed text, no ticking.
+	if left > 30*24*time.Hour {
+		// Say it stays loaded.
+		return longKeepText, 0, false
+	} // end of the far-away case
+	// The ticking seconds; 0 here means the time has arrived or passed.
+	secs := remainingSeconds(now, expires, ok)
+	// Time has arrived: the text says so, and the page asks Ollama again soon.
+	if secs == 0 {
+		// The same wording as the terminal table, flagged as arrived.
+		return formatRemaining(now, expires, ok), 0, true
+	} // end of the arrived case
+	// A normal countdown: the text and the seconds the script ticks from.
+	return formatRemaining(now, expires, ok), secs, false
+} // end of timerFor
+
+// buildTableView builds the page data using the current clock.
 func buildTableView(installed []installedModel, loaded []loadedModel) tableView {
+	// Delegate with the real time; tests call buildTableViewAt with a fixed time.
+	return buildTableViewAt(installed, loaded, time.Now())
+} // end of buildTableView
+
+// buildTableViewAt turns the installed and loaded lists into the data the page template draws, using the given moment for the unload timers.
+func buildTableViewAt(installed []installedModel, loaded []loadedModel, now time.Time) tableView {
+	// Remember each loaded model by name, so a row can find its unload time.
+	byName := make(map[string]loadedModel, len(loaded))
+	// Go through the loaded models.
+	for _, l := range loaded {
+		// Store it.
+		byName[l.Name] = l
+	} // end of the loaded loop
 	// Mark each model as loaded or not, then sort into category sections (both from the terminal version).
 	groups := groupRows(combine(installed, loaded))
 	// Start the view with the total.
@@ -107,8 +158,19 @@ func buildTableView(installed []installedModel, loaded []loadedModel) tableView
 		for _, r := range g.Rows {
 			// A short name for the model's data.
 			m := r.Model
+			// The unload timer exists only for a loaded model.
+			var timer string
+			// The seconds the timer ticks from.
+			var timerSecs int
+			// True when the unload time has arrived.
+			var timerExpired bool
+			// Look the model up in the loaded list.
+			if r.Loaded {
+				// Work out the timer text and seconds.
+				timer, timerSecs, timerExpired = timerFor(byName[m.Name], now)
+			} // end of the timer
 			// Add the row: the name first, then the nine cells in the same order and formats as the terminal table.
-			gv.Rows = append(gv.Rows, rowView{Name: m.Name, Loaded: r.Loaded, StateWord: stateWord(r.Loaded), Cells: []string{
+			gv.Rows = append(gv.Rows, rowView{Name: m.Name, Loaded: r.Loaded, StateWord: stateWord(r.Loaded), Timer: timer, TimerSeconds: timerSecs, TimerExpired: timerExpired, Cells: []string{
 				// Loaded or not, symbol plus words.
 				stateText(r.Loaded),
 				// Size on disk.
@@ -134,4 +196,4 @@ func buildTableView(installed []installedModel, loaded []loadedModel) tableView
 	} // end of the group loop
 	// Return the view.
 	return view
-} // end of buildTableView
+} // end of buildTableViewAt
diff --git a/timer_test.go b/timer_test.go
new file mode 100644
index 0000000..6caf392
--- /dev/null
+++ b/timer_test.go
@@ -0,0 +1,136 @@
+// Package main tells Go that this test file belongs to the same program as tableview.go.
+package main
+
+import ( // import lists the packages this test file uses.
+	// net/http provides the request method name and status codes.
+	"net/http"
+	// regexp finds the timer markup in the page.
+	"regexp"
+	// strings searches the page text.
+	"strings"
+	// testing is Go's built-in test framework.
+	"testing"
+	// time provides the fixed clock the tests use.
+	"time"
+) // end of imports
+
+// timerNow is the fixed "now" every timer test uses, so the results never depend on the real clock.
+var timerNow = time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)
+
+// TestTimerFor checks the text and ticking seconds for each kind of unload time Ollama can report.
+func TestTimerFor(t *testing.T) {
+	// The cases: the reported time, the expected text and the expected seconds.
+	cases := []struct {
+		// A name for the report.
+		name string
+		// The expires_at text Ollama sent.
+		expires string
+		// The expected timer text.
+		text string
+		// The expected ticking seconds.
+		secs int
+		// Whether the time has arrived.
+		expired bool
+	}{
+		// Five minutes away, the usual Ollama default.
+		{"five minutes", "2026-10-25T12:05:00Z", "5 min 0 s", 300, false},
+		// Under a minute.
+		{"seconds", "2026-10-25T12:00:20Z", "20 s", 20, false},
+		// Over an hour, with an offset in the text.
+		{"hours", "2026-10-25T15:05:00+02:00", "1 h 5 min", 3900, false},
+		// The time has passed.
+		{"past", "2026-10-25T11:59:00Z", "unloading now", 0, true},
+		// Exactly now.
+		{"now", "2026-10-25T12:00:00Z", "unloading now", 0, true},
+		// Ollama keeps the model loaded forever: a time centuries away.
+		{"forever", "2318-01-01T00:00:00Z", "stays loaded", 0, false},
+		// Ollama sent nothing.
+		{"missing", "", "not reported", 0, false},
+		// Ollama sent something unreadable.
+		{"garbage", "tomorrow", "not reported", 0, false},
+	} // end of the case table
+	// Go through the cases.
+	for _, c := range cases {
+		// Work out the timer.
+		text, secs, expired := timerFor(loadedModel{Name: "m", ExpiresAt: c.expires}, timerNow)
+		// Compare.
+		if text != c.text || secs != c.secs || expired != c.expired {
+			// Report the difference.
+			t.Errorf("%s: got (%q, %d, %v), want (%q, %d, %v)", c.name, text, secs, expired, c.text, c.secs, c.expired)
+		} // end of the compare
+	} // end of the case loop
+} // end of TestTimerFor
+
+// TestTableViewTimersOnlyForLoaded checks that only a loaded row has a timer, and that it comes from that model's own unload time.
+func TestTableViewTimersOnlyForLoaded(t *testing.T) {
+	// Two loaded models with different unload times (one more than the other is not installed and must be ignored).
+	loaded := []loadedModel{
+		// The first loaded model: five minutes left.
+		{Name: "medgemma:latest", ExpiresAt: "2026-10-25T12:05:00Z"},
+		// A model that is loaded but not installed: no row.
+		{Name: "ghost:1b", ExpiresAt: "2026-10-25T12:01:00Z"},
+	} // end of the loaded list
+	// Build the view with the fixed clock.
+	v := buildTableViewAt(realInstalled(t), loaded, timerNow)
+	// Count the rows with a timer.
+	withTimer := 0
+	// Go through every row.
+	for _, g := range v.Groups {
+		// Go through the rows of this section.
+		for _, r := range g.Rows {
+			// A row with a timer text.
+			if r.Timer != "" {
+				// Count it.
+				withTimer++
+				// It must be the loaded one, with its own figures.
+				if r.Name != "medgemma:latest" || r.TimerSeconds != 300 || r.Timer != "5 min 0 s" {
+					// Report the problem.
+					t.Errorf("unexpected timer on %q: %q (%d)", r.Name, r.Timer, r.TimerSeconds)
+				} // end of the check
+			} // end of the timer check
+		} // end of the row loop
+	} // end of the group loop
+	// Exactly one row has a timer.
+	if withTimer != 1 {
+		// Report the problem.
+		t.Errorf("%d rows have a timer, want 1", withTimer)
+	} // end of the count check
+} // end of TestTableViewTimersOnlyForLoaded
+
+// TestPageShowsTimerBetweenStateAndButton checks the page markup: a bold timer with its seconds, placed after the state words and before the Unload button, and an empty slot for a row that is not loaded.
+func TestPageShowsTimerBetweenStateAndButton(t *testing.T) {
+	// A fake with one loaded model; its /api/ps entry has an unload time five minutes away.
+	f := &loadFake{loaded: []string{"alpha:1b"}}
+	// Build the rig.
+	rig := loadRig(t, f, 16e9)
+	// Fetch the page.
+	status, _, body := get(t, rig.h, http.MethodGet, "/")
+	// The page must load.
+	if status != http.StatusOK {
+		// Report the problem.
+		t.Fatalf("status %d", status)
+	} // end of the status check
+	// The timer markup: bold element with the timer class, ticking seconds and the role.
+	m := regexp.MustCompile(`<strong class="timer countdown" data-seconds="(\d+)" role="timer" aria-label="Time until Ollama unloads [^"]+">[^<]+</strong>`).FindStringSubmatch(body)
+	// It must exist.
+	if m == nil {
+		// Report the problem.
+		t.Fatalf("no ticking timer in the page")
+	} // end of the timer check
+	// The order inside the cell: state words, then the timer, then the Unload form.
+	iState := strings.Index(body, "Loaded</span>")
+	// Where the timer starts.
+	iTimer := strings.Index(body, `<span class="timerslot"><strong`)
+	// Where the Unload form starts.
+	iForm := strings.Index(body, `action="/unload"`)
+	// The three must come in this order.
+	if !(iState >= 0 && iState < iTimer && iTimer < iForm) {
+		// Report the problem.
+		t.Errorf("wrong order: state %d, timer %d, unload form %d", iState, iTimer, iForm)
+	} // end of the order check
+	// A row that is not loaded gets an empty slot so the buttons stay aligned.
+	if !strings.Contains(body, `<span class="timerslot" aria-hidden="true"></span>`) {
+		// Report the problem.
+		t.Errorf("a row that is not loaded has no empty timer slot")
+	} // end of the slot check
+} // end of TestPageShowsTimerBetweenStateAndButton
diff --git a/tooltips.go b/tooltips.go
index 19f8494..eb98faa 100644
--- a/tooltips.go
+++ b/tooltips.go
@@ -88,7 +88,7 @@ var helpTexts = map[string]tooltip{
 	// The loaded or not-loaded state.
 	"State": {
 		// What it means.
-		Plain: "Whether the model is in memory now (● Loaded) or only stored on disk (○ Not loaded).",
+		Plain: "In memory now (● Loaded, with a bold timer until Ollama unloads it) or only on disk (○ Not loaded).",
 		// A real case.
 		Example: "A ○ Not loaded model needs a moment to load before it answers.",
 		// What it helps with.
diff --git a/web.go b/web.go
index 049d578..84defba 100644
--- a/web.go
+++ b/web.go
@@ -156,6 +156,11 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 			// Stop here.
 			return
 		} // end of the template check
+		// With a table the page runs the monitor's own script, so it gets the policy that also lets the script ask this same address for fresh figures.
+		if data.HasTable {
+			// Replace the strict policy.
+			w.Header().Set("Content-Security-Policy", contentSecurityPolicyMainPage)
+		} // end of the script policy
 		// Tell the browser this is an HTML page.
 		w.Header().Set("Content-Type", "text/html; charset=utf-8")
 		// Send the finished page.
diff --git a/web/app.css b/web/app.css
index c89a023..56f6792 100644
--- a/web/app.css
+++ b/web/app.css
@@ -743,6 +743,24 @@ h2 {
   min-width: 8rem;
 } /* end of rule */
 
+/* The slot between the state words and the Load or Unload button; every row has one of the same width, so all the buttons stay in line. */
+.timerslot {
+  /* A box in the line, so it can have a width. */
+  display: inline-block;
+  /* Wide enough for "11 min 59 s", "unloading now" and "stays loaded" in bold. */
+  min-width: 8.5rem;
+  /* Keep the digits in line with the words around them. */
+  vertical-align: baseline;
+} /* end of rule */
+
+/* The unload timer itself: bold, with digits of equal width so the text does not jitter every second. */
+.timer {
+  /* Bold, as asked. */
+  font-weight: 700;
+  /* Digits of equal width. */
+  font-variant-numeric: tabular-nums;
+} /* end of rule */
+
 /* The hidden attribute must always win over any display rule. */
 [hidden] {
   /* Not drawn at all. */
diff --git a/web/countdown.js b/web/countdown.js
index 319b07d..ea0c681 100644
--- a/web/countdown.js
+++ b/web/countdown.js
@@ -1,14 +1,24 @@
-// Countdown: makes every element marked class="countdown" and data-seconds="N" count down once a second, starting from the number the monitor wrote into the page.
+// Countdown: makes every element marked class="countdown" and data-seconds="N" count down once a second, starting from the number the monitor wrote into the page. On the main page it also asks the monitor for fresh figures every few seconds, so each timer follows what Ollama really reports.
 (function () {
   // Remember when this page was opened, using the browser's steady clock (it ignores clock changes and any clock difference with Ollama).
   var start = performance.now();
   // Find every timer on the page.
   var items = document.querySelectorAll('.countdown[data-seconds]');
-  // Nothing to do when there is no timer.
-  if (items.length === 0) {
+  // The main page is the one that has the models table; the message pages do not.
+  var onMain = document.querySelector('table.models') !== null;
+  // Nothing to do when there is no timer and no table to keep fresh.
+  if (items.length === 0 && !onMain) {
     // Stop here.
     return;
   }
+  // How often the main page asks the monitor for fresh figures, in milliseconds.
+  var POLL_MS = 10000;
+  // How soon after the last request a timer that reached zero may ask again, in milliseconds.
+  var QUICK_MS = 3000;
+  // When the last request started, on the same steady clock.
+  var lastPoll = performance.now();
+  // True while a request is on its way, so two never overlap.
+  var busy = false;
   // Turn a number of seconds into the same wording the monitor uses: "4 min 30 s", "1 h 5 min" or "20 s".
   function words(total) {
     // Whole hours.
@@ -30,20 +40,143 @@
     // Otherwise only seconds.
     return s + ' s';
   }
-  // Update every timer once.
+  // Update every timer once; returns true when at least one timer has reached zero.
   function tick() {
-    // Seconds since the page opened.
-    var elapsed = (performance.now() - start) / 1000;
+    // Becomes true when a timer is at zero.
+    var atZero = false;
     // Go through the timers.
     items.forEach(function (el) {
+      // Seconds since this timer's number was written (the page opening, or the last fresh figures).
+      var elapsed = (performance.now() - (el._t0 || start)) / 1000;
       // Seconds left: the number the monitor wrote minus the time passed, rounded up so 0 appears only at the end.
       var left = Math.ceil(Number(el.getAttribute('data-seconds')) - elapsed);
       // Show the time, or say the unload time has arrived.
       el.textContent = left > 0 ? words(left) : 'unloading now';
+      // Remember that a timer reached zero.
+      if (left <= 0) {
+        // Flag it.
+        atZero = true;
+      }
     });
+    // A timer that already says "unloading now" (the page was loaded after the time had passed) also counts as zero.
+    if (document.querySelector('.timer[data-expired]')) {
+      // Flag it.
+      atZero = true;
+    }
+    // Tell the caller.
+    return atZero;
+  }
+  // Describe the table in one text: each model, whether it is loaded, and whether its timer ticks; a change means the page itself must be redrawn.
+  function signature(doc) {
+    // One part per model row.
+    var parts = [];
+    // Go through the rows.
+    doc.querySelectorAll('tr[data-model]').forEach(function (row) {
+      // Name, loaded flag, and t when a ticking timer is present.
+      parts.push(row.getAttribute('data-model') + '|' + row.getAttribute('data-loaded') + '|' + (row.querySelector('.countdown[data-seconds]') ? 't' : '-'));
+    });
+    // One text for the whole table.
+    return parts.join('\n');
+  }
+  // Take the fresh figures from a freshly fetched copy of the page.
+  function applyFresh(doc) {
+    // The rows now on the page and the rows in the fresh copy; the signatures match, so they line up one to one.
+    var now = document.querySelectorAll('tr[data-model]');
+    // The fresh rows.
+    var fresh = doc.querySelectorAll('tr[data-model]');
+    // The moment the fresh figures arrived.
+    var arrived = performance.now();
+    // Go through the rows.
+    for (var i = 0; i < now.length; i++) {
+      // The timer element on the page and in the fresh copy (a row that is not loaded has none).
+      var a = now[i].querySelector('.timer');
+      // The fresh one.
+      var b = fresh[i].querySelector('.timer');
+      // Nothing to update for a row without a timer.
+      if (!a || !b) {
+        // Next row.
+        continue;
+      }
+      // A ticking timer: take the new seconds and start counting from now.
+      if (b.hasAttribute('data-seconds')) {
+        // The new number.
+        a.setAttribute('data-seconds', b.getAttribute('data-seconds'));
+        // Restart this timer's clock.
+        a._t0 = arrived;
+      } else {
+        // A fixed text such as "stays loaded": copy it.
+        a.textContent = b.textContent;
+      }
+    }
+    // Show the new values at once.
+    tick();
+  }
+  // Ask the monitor for a fresh copy of the main page and compare it with what is shown.
+  function poll() {
+    // Skip while a request is running or the tab is hidden (no point asking when nobody looks).
+    if (busy || document.hidden) {
+      // Stop here.
+      return;
+    }
+    // Mark the request as running and note the time.
+    busy = true;
+    // Note the time.
+    lastPoll = performance.now();
+    // Ask for the same page again, never from a cache, with the same cookies.
+    fetch('/', { cache: 'no-store', credentials: 'same-origin' })
+      .then(function (res) {
+        // Anything but a normal answer is ignored until the next try.
+        if (!res.ok) {
+          // Throw to reach the catch below.
+          throw new Error('bad status');
+        }
+        // Read the page text.
+        return res.text();
+      })
+      .then(function (text) {
+        // Turn the text into a page we can look into (nothing in it runs).
+        var doc = new DOMParser().parseFromString(text, 'text/html');
+        // A different set of models, loaded flags or timers (or no table at all) means the page must be redrawn: reload it.
+        if (!doc.querySelector('table.models') || signature(doc) !== signature(document)) {
+          // Reload the page from the monitor.
+          location.reload();
+          // Stop here.
+          return;
+        }
+        // Nothing structural changed: take the fresh seconds.
+        applyFresh(doc);
+      })
+      .catch(function () {
+        // A failed request is not an error to show; the next try comes soon.
+      })
+      .then(function () {
+        // Allow the next request.
+        busy = false;
+      });
   }
   // Show the first value at once, then every second.
   tick();
-  // Repeat once a second.
-  setInterval(tick, 1000);
+  // Repeat once a second; a timer at zero asks for fresh figures soon, so the row changes quickly after Ollama unloads the model.
+  setInterval(function () {
+    // Update the timers and see whether one is at zero.
+    var atZero = tick();
+    // On the main page, a timer at zero may ask again after a few seconds.
+    if (onMain && atZero && performance.now() - lastPoll > QUICK_MS) {
+      // Ask now.
+      poll();
+    }
+  }, 1000);
+  // The main page also asks regularly, and at once when its tab becomes visible again.
+  if (onMain) {
+    // Regular requests.
+    setInterval(poll, POLL_MS);
+    // Catch up after the tab was hidden.
+    document.addEventListener('visibilitychange', function () {
+      // Only when the tab has just become visible.
+      if (!document.hidden) {
+        // Ask now.
+        poll();
+      }
+    });
+  }
 })();
diff --git a/web/index.html b/web/index.html
index cdb322a..69a273c 100644
--- a/web/index.html
+++ b/web/index.html
@@ -131,14 +131,16 @@
 </tr>
 {{/* One row per model in this category. */}}
 {{range $g.Rows}}
-{{/* A model row. */}}
-<tr>{{/* start of a table row. */}}
+{{/* A model row; the name and loaded flag let the script compare this page with a fresh copy. */}}
+<tr data-model="{{.Name}}" data-loaded="{{if .Loaded}}1{{else}}0{{end}}">{{/* start of a table row. */}}
 {{/* The model name is the row heading and stays visible while scrolling. */}}
 <th scope="row" class="stickycol">{{.Name}}</th>
 {{/* The state cell: a dot (solid green when loaded, an empty ring when not) plus the words, so colour is never the only signal. */}}
 <td><span class="statelabel"><span class="dot {{if .Loaded}}dot-on{{else}}dot-off{{end}}" aria-hidden="true"></span> {{.StateWord}}</span>
 {{- /* Only a loaded model gets the Unload button; it opens a warning page first, so one click never unloads anything. */ -}}
 {{if .Loaded}}
+{{/* The unload timer sits between the words and the button; bold, with a title and a label so it is more than a bare number. */}}
+<span class="timerslot"><strong class="timer{{if .TimerSeconds}} countdown{{end}}"{{if .TimerSeconds}} data-seconds="{{.TimerSeconds}}"{{end}}{{if .TimerExpired}} data-expired="1"{{end}} role="timer" aria-label="Time until Ollama unloads {{.Name}}">{{.Timer}}</strong></span>
 {{/* A small form that sends the model name and the page token to the warning page. */}}
 <form class="unloadform" method="post" action="/unload">
 {{/* The page token proves the form comes from this monitor. */}}
@@ -150,6 +152,8 @@
 {{/* End of the form. */}}
 </form>
 {{else}}
+{{/* An empty slot of the same width keeps the Load buttons in line with the Unload buttons. */}}
+<span class="timerslot" aria-hidden="true"></span>
 {{/* A model that is not loaded gets the Load button; it opens a warning page about memory first, so one click never loads anything. */}}
 <form class="unloadform" method="post" action="/load">
 {{/* The page token proves the form comes from this monitor. */}}
@@ -187,6 +191,8 @@
 </section>
 {{/* End of the main content. */}}
 </main>
+{{/* The monitor's own script ticks the timers and asks the monitor for fresh figures every few seconds; it is loaded only when a table is shown. */}}
+{{if .HasTable}}<script src="/countdown.js" defer></script>{{end}}
 </body>{{/* end of the visible page. */}}
 </html>{{/* end of the page. */}}
 {{/* The help bubble content: three labelled parts, and the task names when there are any. */}}
diff --git a/web_test.go b/web_test.go
index 4636a63..551f6bf 100644
--- a/web_test.go
+++ b/web_test.go
@@ -157,20 +157,25 @@ func TestPageEscapesUntrustedText(t *testing.T) {
 	} // end of the escaped check
 } // end of TestPageEscapesUntrustedText
 
-// TestPageHasNoInlineCode checks the page works under the safety policy: no scripts, no style tags, no style attributes.
+// TestPageHasNoInlineCode checks the page works under the safety policy: no inline scripts (only the monitor's own script file), no style tags, no style attributes.
 func TestPageHasNoInlineCode(t *testing.T) {
 	// A fake Ollama that is online.
 	srv := fakeOllama(t, replyWith(http.StatusOK, `{"version":"0.34.4"}`))
 	// Ask the page.
 	_, _, body := get(t, handlerFor(t, srv.URL), http.MethodGet, "/")
 	// None of these may appear.
-	for _, bad := range []string{"<script", "<style", " style=", " onclick=", " onload="} {
+	for _, bad := range []string{"<script>", "<style", " style=", " onclick=", " onload="} {
 		// Look for it.
 		if strings.Contains(body, bad) {
 			// Report the problem.
 			t.Errorf("page contains %q, which the safety policy would block", bad)
 		} // end of the check
 	} // end of the loop
+	// Every script tag must load the monitor's own file; the policy blocks everything else.
+	if n, ok := strings.Count(body, "<script"), strings.Count(body, `<script src="/countdown.js" defer></script>`); n != ok {
+		// Report the problem.
+		t.Errorf("page has %d script tags but only %d load /countdown.js", n, ok)
+	} // end of the script check
 	// Comments written in the template must not reach the browser.
 	if strings.Contains(body, "template comments") || strings.Contains(body, "{{") {
 		// Report the problem.
@@ -201,8 +206,20 @@ func TestSecurityHeaders(t *testing.T) {
 	for _, path := range []string{"/", "/app.css", "/nothing-here"} {
 		// Ask for it.
 		_, hdr, _ := get(t, h, http.MethodGet, path)
+		// The page that shows the table is the only one that may run the monitor's own script; every other reply keeps the strict policy.
+		wantNow := map[string]string{}
+		// Copy the table.
+		for k, v := range want {
+			// Copy one entry.
+			wantNow[k] = v
+		} // end of the copy
+		// The fake Ollama answers every address, so the page shows a table and gets the script policy.
+		if path == "/" {
+			// Swap the policy.
+			wantNow["Content-Security-Policy"] = contentSecurityPolicyMainPage
+		} // end of the page case
 		// Check every header.
-		for name, value := range want {
+		for name, value := range wantNow {
 			// Compare.
 			if got := hdr.Get(name); got != value {
 				// Report the difference.
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Create the branch and move onto it.
git switch -c "$BRANCH"
# Apply the patch to the working files.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the changed files must have after the patch.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
7d6c8f351ef30b38db545c68898ad55a6685ac1b7f695488a0649b6b288d7bd0  countdown.go
c20e496b9aafd786503d1fb5761632ff12b21291ffcd9e8fe995bfcc6437f749  load_test.go
d444eb3accbb277fd9dff7d7a4ccfb39a8decccabdd8b059153089d3939035c7  tableview.go
6723408173525b1de2b246d0175cfa4d43d05a49ad880a470a4d9d90d41e3aed  timer_test.go
e8e7c75b385ea3b06a1a87c41b5ff38f683e0f73abedd253bc6c3f828c35dd14  tooltips.go
9b38981a31ef80211614c2061c24b653286b9c214193f800fe51d63b86be9214  web.go
6399c7aed0cba3609e878244b7598f4054b4e7ad2e479899db667d28bb67fc49  web/app.css
7b546b048a65edc221bdc8fc8e903bbd8ad755690e5b21a8c7ce1b0d2d3c80bc  web/countdown.js
354f0ff7def6dc2fe354a4cd409d15e60381a41b1cdd515ef4878563c5b50225  web/index.html
e3cc8a388ee60b071e9012613eff890a73e1c2a11ccda9f6e80947e90ce21799  web_test.go
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # All ten files are exactly as tested.
  echo "PASS  all 10 changed files match the tested versions"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; rm -f "$PATCH_FILE.sums"; exit 1
fi
# Remove the fingerprint list.
rm -f "$PATCH_FILE.sums"
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
# Build the executable the same way as before (one file, nothing to install).
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Show where things stand.
echo "Branch: $(git branch --show-current)"
# List the changed files; nothing is committed yet.
git status --short
