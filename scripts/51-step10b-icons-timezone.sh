#!/usr/bin/env bash
# Script 51: replaces the emoji characters of the controls with drawn icons (same look on every computer) and adds the timezone to the page time.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run on main: this change belongs on its own feature branch.
[ "$(git branch --show-current)" = "feature/monitor-controls" ] || { echo "FAIL  not on feature/monitor-controls"; exit 1; }
# Script 50 must be applied first (it adds control.go).
[ -f control.go ] || { echo "FAIL  script 50 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q 'class="ico"' web/index.html; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/control_test.go b/control_test.go
index 8f878d4..c677e47 100644
--- a/control_test.go
+++ b/control_test.go
@@ -334,3 +334,41 @@ func TestStopWhileTestRuns(t *testing.T) {
 	// Wait for it.
 	<-done
 } // end of TestStopWhileTestRuns
+
+// TestControlIconsAndZone checks that the controls use drawn icons (never emoji characters, which each computer paints in its own colours) and that the page time carries its timezone.
+func TestControlIconsAndZone(t *testing.T) {
+	// A fake and a rig.
+	rig, _ := perfRig(t, newPerfFake())
+	// Both versions of the page: watching and paused.
+	for name, c := range map[string]*http.Cookie{"watching": nil, "paused": {Name: watchCookieName, Value: "paused"}} {
+		// The page.
+		page := pageWithCookie(t, rig, c)
+		// Characters that some systems paint as colour emoji.
+		for _, bad := range []string{"⏸", "⏹", "↻"} {
+			// None may appear.
+			if strings.Contains(page, bad) {
+				// Report it.
+				t.Errorf("%s page contains the emoji-like character %q", name, bad)
+			} // end of the character check
+		} // end of the loop
+		// The icons are drawn instead: at least the status line and three buttons.
+		if n := strings.Count(page, `<svg class="ico"`); n < 4 {
+			// Report it.
+			t.Errorf("%s page has %d icons, want at least 4", name, n)
+		} // end of the icon check
+		// The time ends with a timezone name or offset, for example "14:28:17 CET".
+		i := strings.Index(page, "Page made at ")
+		// It must be there.
+		if i < 0 {
+			// Report it.
+			t.Fatalf("%s page has no time line", name)
+		} // end of the presence check
+		// The sentence up to its full stop.
+		line := page[i : i+strings.Index(page[i:], ".")]
+		// Three parts: the words, the clock and the zone.
+		if f := strings.Fields(line); len(f) != 5 || len(f[3]) != 8 || f[4] == "" {
+			// Report it.
+			t.Errorf("%s time line has no timezone: %q", name, line)
+		} // end of the zone check
+	} // end of the loop
+} // end of TestControlIconsAndZone
diff --git a/web.go b/web.go
index a0e73fa..9aa9e8c 100644
--- a/web.go
+++ b/web.go
@@ -172,7 +172,7 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 			// The update interval.
 			RefreshSeconds: watchRefreshSeconds,
 			// When this page was made.
-			UpdatedAt: time.Now().Format("15:04:05"),
+			UpdatedAt: time.Now().Format("15:04:05 MST"),
 		} // end of the data
 		// Only an online Ollama can be asked for its model lists.
 		if res.Online {
diff --git a/web/app.css b/web/app.css
index bc2da42..096877e 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1290,3 +1290,11 @@ button.btn-plain {
     right: 0.5rem;
   } /* end of rule */
 } /* end of rule */
+
+/* The small icons inside the control buttons and the status line: they take the text colour, so every computer and both themes show them alike. */
+.ico {
+  /* Sit level with the letters. */
+  vertical-align: -2px;
+  /* A small gap before the words. */
+  margin-right: 0.15rem;
+} /* end of rule */
diff --git a/web/control.html b/web/control.html
index 6c356b6..4029188 100644
--- a/web/control.html
+++ b/web/control.html
@@ -35,7 +35,7 @@
 {{/* The confirm form sends the page token to the real stop. */}}
 <form method="post" action="/stop/confirm">
 <input type="hidden" name="token" value="{{.Token}}">
-<button type="submit" class="btn-solid">⏹ Yes, stop the monitor</button>
+<button type="submit" class="btn-solid"><svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><rect x="3" y="3" width="10" height="10" rx="1.5"/></svg> Yes, stop the monitor</button>
 </form>
 {{/* The safe choice goes back to the monitor and changes nothing. */}}
 <a class="btn-plain" href="/">No, keep it running</a>
diff --git a/web/index.html b/web/index.html
index b5ac2cb..07f363f 100644
--- a/web/index.html
+++ b/web/index.html
@@ -26,7 +26,7 @@
 {{/* Show which Ollama is being watched and which setting supplied the address; a password in it is already hidden. */}}
 <p class="muted">Watching Ollama at <code>{{.Address}}</code> (from {{.AddressSource}})</p>
 {{/* Says whether the page updates by itself, and how fresh it is; the symbol and the words carry the meaning. */}}
-<p class="muted" id="watchline">{{if .Paused}}<span aria-hidden="true">⏸</span> Paused: the page does not update by itself. Page made at {{.UpdatedAt}}.{{else}}<span aria-hidden="true">▶</span> Watching: the page updates itself every {{.RefreshSeconds}} seconds. Page made at {{.UpdatedAt}}.{{end}}</p>
+<p class="muted" id="watchline">{{if .Paused}}<svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><rect x="3" y="2" width="3.5" height="12" rx="1"/><rect x="9.5" y="2" width="3.5" height="12" rx="1"/></svg> Paused: the page does not update by itself. Page made at {{.UpdatedAt}}.{{else}}<svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><path d="M4 2.5v11l9-5.5z"/></svg> Watching: the page updates itself every {{.RefreshSeconds}} seconds. Page made at {{.UpdatedAt}}.{{end}}</p>
 {{/* End of the title block. */}}
 </div>
 {{/* The right side of the header: the monitor controls, then the theme switch. */}}
@@ -41,10 +41,10 @@
 <span class="tipbox">
 {{/* While watching the button pauses; while paused it resumes. */}}
 {{if .Paused}}
-<button type="submit" name="action" value="resume" class="btn-plain ctlbtn" aria-describedby="tipwatch"><span aria-hidden="true">▶</span> Resume</button>
+<button type="submit" name="action" value="resume" class="btn-plain ctlbtn" aria-describedby="tipwatch"><svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><path d="M4 2.5v11l9-5.5z"/></svg> Resume</button>
 <span class="tip tip-icon" role="tooltip" id="tipwatch">Make the page update itself every {{.RefreshSeconds}} seconds again</span>
 {{else}}
-<button type="submit" name="action" value="pause" class="btn-plain ctlbtn" aria-describedby="tipwatch"><span aria-hidden="true">⏸</span> Pause</button>
+<button type="submit" name="action" value="pause" class="btn-plain ctlbtn" aria-describedby="tipwatch"><svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><rect x="3" y="2" width="3.5" height="12" rx="1"/><rect x="9.5" y="2" width="3.5" height="12" rx="1"/></svg> Pause</button>
 <span class="tip tip-icon" role="tooltip" id="tipwatch">Stop the page from updating by itself; it keeps showing what it shows now until you resume or refresh</span>
 {{end}}
 {{/* End of the tip area. */}}
@@ -53,7 +53,7 @@
 </form>
 {{/* Refresh: a plain link to the page, which asks Ollama once, right now. */}}
 <span class="tipbox">
-<a class="btn-plain ctlbtn" href="/" aria-describedby="tiprefresh"><span aria-hidden="true">↻</span> Refresh</a>
+<a class="btn-plain ctlbtn" href="/" aria-describedby="tiprefresh"><svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 8a5 5 0 1 1-1.6-3.7"/><path d="M13 2.5V5h-2.5"/></svg> Refresh</a>
 <span class="tip tip-icon" role="tooltip" id="tiprefresh">Check Ollama once, right now</span>
 </span>
 {{/* Stop: a small form that goes to the question page; nothing is stopped yet. */}}
@@ -62,7 +62,7 @@
 <input type="hidden" name="token" value="{{.Token}}">
 {{/* The area that opens the tip. */}}
 <span class="tipbox">
-<button type="submit" class="unload ctlbtn" aria-describedby="tipstop"><span aria-hidden="true">⏹</span> Stop</button>
+<button type="submit" class="unload ctlbtn" aria-describedby="tipstop"><svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="currentColor"><rect x="3" y="3" width="10" height="10" rx="1.5"/></svg> Stop</button>
 <span class="tip tip-icon" role="tooltip" id="tipstop">Stop the monitor program (it asks first; Ollama and its models are not touched)</span>
 </span>
 {{/* End of the stop form. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
f9e4dc24e7168acebdc36931742515cac5cc2afed271f7355f85057ad0800311  control_test.go
24605500384c85fdcd7bec9cc9644e4f1159c30993ed4190f453c5261139072c  web.go
5f4c8431aebf6d23359b3a02a2a4902c22b9a355631360af4ac42cc910469c44  web/app.css
bc99686cebdd6bd4a0a0ea25c9d6616bc224ffa0866aea24de545d630bbd7579  web/control.html
34c0ef9d11a3b8f0ac600a652559eea5b5e20bfa4fad6c86c1c3ad02b240dc8c  web/index.html
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
