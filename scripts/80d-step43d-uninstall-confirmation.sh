#!/usr/bin/env bash
# Script 80d (uninstall confirmation, last part of this branch): the Uninstall question now ends with OK and Cancel. After the tool has been in use (once Continue was pressed) it lists the impact in words and asks the person to type the word uninstall; the browser and the program both check it, and a wrong word removes nothing. On the very first start, before Continue, a plain OK / Cancel is shown. It must be run on the branch where scripts 80, 80b and 80c were already applied.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ -e syscheck.go ] && [ "$(git branch --show-current)" = "feature/system-check" ] || { echo "FAIL  scripts 80, 80b and 80c are not applied here, or this is not feature/system-check"; exit 1; }
# Refuse to run twice.
if grep -q uninstallWord syscheck.go 2>/dev/null; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/syscheck.go b/syscheck.go
index eef70f0..9cea680 100644
--- a/syscheck.go
+++ b/syscheck.go
@@ -120,6 +120,8 @@ type sysPage struct {
 	Theme, Size string
 	// Token is the page token for the forms.
 	Token string
+	// WordWrong is true when the uninstall form came back without the typed word.
+	WordWrong bool
 	// First is true on the very first start: the monitor can only be reached through Continue, so the page has no back arrow.
 	First bool
 	// Rows is the table "This computer".
@@ -142,6 +144,9 @@ type sysPage struct {
 	Program string
 } // end of sysPage
 
+// uninstallWord is the word the person types to confirm an uninstall after the tool has been in use.
+const uninstallWord = "uninstall"
+
 // notReported is the word for a figure the system did not give.
 const notReported = "not reported"
 
@@ -417,6 +422,15 @@ func systemCheckHandlers(addr ollamaAddress, mon *monitor, token string, desktop
 			// A refusal was already sent.
 			return
 		} // end of the checks
+		// After the tool has been in use, the person must type the word; capital letters do not matter. The check is made here as well as in the browser, so a hand-made request cannot skip it.
+		if !firstStart(r) && !strings.EqualFold(strings.TrimSpace(r.PostFormValue("confirm")), uninstallWord) {
+			// Show the question again with a note; nothing is removed.
+			exe, _ := executablePath()
+			// The page.
+			send(w, r, sysPage{Kind: "uninstall", Items: uninstallPlan(desktop), Program: exe, WordWrong: true})
+			// Stop here.
+			return
+		} // end of the word check
 		// Do the removal once.
 		var items []uninstallItem
 		// The program file.
diff --git a/syscheck_test.go b/syscheck_test.go
index d5d025d..4c962fa 100644
--- a/syscheck_test.go
+++ b/syscheck_test.go
@@ -293,7 +293,7 @@ func TestUninstallQuestion(t *testing.T) {
 		t.Fatalf("status = %d", code)
 	} // end of the status check
 	// The paths and words.
-	for _, want := range []string{"Desktop icon", r.cfg, r.data, r.state, "Yes, remove these files", "No, go back", "This cannot be undone", "Nothing is removed"} {
+	for _, want := range []string{"Desktop icon", r.cfg, r.data, r.state, "OK, uninstall", "Cancel", "This cannot be undone", "Nothing is removed", "Type <code>uninstall</code> to confirm", `pattern=`} {
 		// Each must be there.
 		if !strings.Contains(body, want) {
 			// Report it.
@@ -337,7 +337,7 @@ func TestUninstallConfirm(t *testing.T) {
 		t.Fatalf("a refused form removed the folder")
 	} // end of the safe check
 	// The real request.
-	res := post(t, r.h, "/uninstall/confirm", url.Values{"token": {r.token}}, fromThisPage)
+	res := post(t, r.h, "/uninstall/confirm", url.Values{"token": {r.token}, "confirm": {"UNINSTALL "}}, fromThisPage)
 	// Read the page.
 	b, _ := io.ReadAll(res.Body)
 	// The result page.
@@ -484,3 +484,87 @@ func TestNoBackArrowOnFirstStart(t *testing.T) {
 		} // end of the check
 	} // end of the loop
 } // end of TestNoBackArrowOnFirstStart
+
+// TestUninstallNeedsTheTypedWord checks that after Continue the removal needs the word, and that a wrong word removes nothing and does not use up the one-time stop.
+func TestUninstallNeedsTheTypedWord(t *testing.T) {
+	// The rig, and the first-start answer given.
+	r := newSysRig(t, true, false)
+	// Press Continue.
+	post(t, r.h, "/systemcheck/continue", url.Values{"token": {r.token}}, fromThisPage)
+	// The cookie of Continue is needed too, so use the saved answer only: the file exists now.
+	for _, bad := range []url.Values{{"token": {r.token}}, {"token": {r.token}, "confirm": {""}}, {"token": {r.token}, "confirm": {"uninstal"}}, {"token": {r.token}, "confirm": {"yes"}}} {
+		// Send it.
+		res := post(t, r.h, "/uninstall/confirm", bad, fromThisPage)
+		// Read the page.
+		b, _ := io.ReadAll(res.Body)
+		// It asks again.
+		if !strings.Contains(string(b), "The word was not") {
+			// Report it.
+			t.Errorf("form %v was not refused", bad)
+		} // end of the refusal check
+	} // end of the loop
+	// Nothing was removed and nothing stopped.
+	for _, d := range []string{r.cfg, r.data, r.state} {
+		// Still there.
+		if _, err := os.Stat(d); err != nil {
+			// Report it.
+			t.Fatalf("%s was removed without the word", d)
+		} // end of the check
+	} // end of the loop
+	// No stop yet.
+	time.Sleep(500 * time.Millisecond)
+	// Zero.
+	if n := r.stops.Load(); n != 0 {
+		// Report it.
+		t.Errorf("stops = %d, want 0", n)
+	} // end of the stop check
+	// The question page has the typed word box after Continue.
+	if _, _, body := get(t, r.h, http.MethodGet, "/uninstall"); !strings.Contains(body, `name="confirm"`) {
+		// Report it.
+		t.Errorf("no word box after Continue")
+	} // end of the box check
+	// The right word, in capitals and with spaces, removes.
+	post(t, r.h, "/uninstall/confirm", url.Values{"token": {r.token}, "confirm": {"  UnInstall "}}, fromThisPage)
+	// Gone.
+	if _, err := os.Stat(r.cfg); err == nil {
+		// Report it.
+		t.Errorf("the right word did not remove")
+	} // end of the removal check
+	// Let the scheduled stop happen inside this test.
+	waitForStop(t, r)
+} // end of TestUninstallNeedsTheTypedWord
+
+// TestUninstallOnFirstStartHasNoWordBox checks that before Continue the plain OK / Cancel is shown and OK works without a word.
+func TestUninstallOnFirstStartHasNoWordBox(t *testing.T) {
+	// The first-start check is on and Continue was not pressed.
+	r := newSysRig(t, true, false)
+	// The question page.
+	_, _, body := get(t, r.h, http.MethodGet, "/uninstall")
+	// No word box, but the OK and Cancel buttons.
+	if strings.Contains(body, `name="confirm"`) || !strings.Contains(body, "OK, uninstall") || !strings.Contains(body, "Cancel") {
+		// Report it.
+		t.Errorf("first-start question is wrong")
+	} // end of the check
+	// OK works without a word.
+	post(t, r.h, "/uninstall/confirm", url.Values{"token": {r.token}}, fromThisPage)
+	// Gone.
+	if _, err := os.Stat(r.cfg); err == nil {
+		// Report it.
+		t.Errorf("OK without a word did not remove on the first start")
+	} // end of the removal check
+	// Let the scheduled stop happen inside this test.
+	waitForStop(t, r)
+} // end of TestUninstallOnFirstStartHasNoWordBox
+
+// waitForStop waits until the rig has seen its one stop request, so that the stop scheduled by a test cannot fire inside the next test.
+func waitForStop(t *testing.T, r *sysRig) {
+	// Mark this as a helper.
+	t.Helper()
+	// Wait at most three seconds.
+	deadline := time.Now().Add(3 * time.Second)
+	// Poll.
+	for r.stops.Load() == 0 && time.Now().Before(deadline) {
+		// A short sleep.
+		time.Sleep(20 * time.Millisecond)
+	} // end of the wait
+} // end of waitForStop
diff --git a/web/app.css b/web/app.css
index 96452ce..6ae5e19 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2424,3 +2424,25 @@ html[data-size="medium"] svg[width="22"] {
   /* Sit in the line like a button. */
   display: inline-block;
 } /* end of rule */
+
+/* The box where the word "uninstall" is typed. */
+.wordbox {
+  /* Use the page font. */
+  font: inherit;
+  /* Room inside. */
+  padding: 0.4rem 0.6rem;
+  /* A visible outline. */
+  border: 2px solid var(--border);
+  /* Rounded corners. */
+  border-radius: 8px;
+  /* Colours follow the theme. */
+  background: var(--bg);
+  /* Text colour. */
+  color: var(--text);
+  /* A comfortable width. */
+  width: 14rem;
+  /* Never wider than the panel. */
+  max-width: 100%;
+  /* Room above. */
+  margin-top: 0.3rem;
+} /* end of rule */
diff --git a/web/systemcheck.html b/web/systemcheck.html
index 72af781..d99f13a 100644
--- a/web/systemcheck.html
+++ b/web/systemcheck.html
@@ -60,24 +60,44 @@
 {{/* Version 2: the uninstall question. */}}
 {{else if eq .Kind "uninstall"}}
 <h1>Uninstall OllamaControlCenter</h1>
+{{/* After the tool has been in use: the impact, in words, before anything else. */}}
+{{if not .First}}
+<p class="warn" role="alert"><strong>&#9888; This cannot be undone.</strong> Uninstalling permanently deletes what this tool has collected on this computer:</p>
+<ul>
+<li>your settings (Ollama address, intervals, theme),</li>
+<li>the performance test results and the comparison copies you saved,</li>
+<li>the list of deleted models, and the check history behind the charts,</li>
+<li>the desktop icon.</li>
+</ul>
+<p>Not touched: Ollama and your models, and the program file itself. The monitor stops when you confirm.</p>
+{{else}}
+<p>Nothing has been collected yet. Nothing is deleted until you press OK.</p>
+<p class="muted">Not touched: Ollama and your models, and the program file itself.</p>
+{{end}}
 {{if .Items}}
-<p>This removes the following. Nothing is deleted until you press the button.</p>
 <table class="settingtable"><thead><tr><th scope="col">What</th><th scope="col">Where</th></tr></thead><tbody>
 {{range .Items}}<tr><th scope="row">{{.What}}</th><td>{{.Where}}</td></tr>
 {{end}}</tbody></table>
 {{else}}
 <p>There is nothing to remove: no desktop icon and no saved folders were found. You can still stop the monitor here and see which program file to delete.</p>
 {{end}}
-<p class="muted">Not touched: Ollama and your models, and the program file itself.</p>
-<div class="choices">
-{{/* Confirm: the real removal, then the monitor stops. */}}
+{{/* The word did not match last time. */}}
+{{if .WordWrong}}<p class="warn" role="alert"><strong>&#9888;</strong> The word was not <code>uninstall</code>, so nothing was removed. Type it exactly, or press Cancel.</p>{{end}}
 <form method="post" action="/uninstall/confirm">
 <input type="hidden" name="token" value="{{.Token}}">
-{{if .Items}}<span class="tipbox"><button type="submit" class="btn-solid btn-danger" aria-describedby="tipyes">Yes, remove these files</button><span class="tip" role="tooltip" id="tipyes">Deletes the items above and stops the monitor. This cannot be undone.</span></span>{{else}}<span class="tipbox"><button type="submit" class="btn-solid btn-danger" aria-describedby="tipyes">Stop the monitor</button><span class="tip" role="tooltip" id="tipyes">Nothing is deleted. The monitor stops and the program file to delete is shown.</span></span>{{end}}
-</form>
+{{/* After use: the typed word; the browser checks it first, and the program checks it again. */}}
+{{if not .First}}
+<p><label for="confirmword"><strong>Type <code>uninstall</code> to confirm</strong></label><br>
+<input id="confirmword" class="wordbox" name="confirm" type="text" required pattern="[Uu][Nn][Ii][Nn][Ss][Tt][Aa][Ll][Ll]" title="Type the word uninstall" autocomplete="off" autocapitalize="off" spellcheck="false" aria-describedby="tipword"></p>
+<span class="muted" id="tipword">OK works only when this word is typed exactly (capital letters do not matter).</span>
+{{end}}
+<div class="choices">
+{{/* OK: the real removal, then the monitor stops. */}}
+{{if .Items}}<span class="tipbox"><button type="submit" class="btn-solid btn-danger" aria-describedby="tipyes">OK, uninstall</button><span class="tip" role="tooltip" id="tipyes">Deletes the items above and stops the monitor. This cannot be undone.</span></span>{{else}}<span class="tipbox"><button type="submit" class="btn-solid btn-danger" aria-describedby="tipyes">OK, stop the monitor</button><span class="tip" role="tooltip" id="tipyes">Nothing is deleted. The monitor stops and the program file to delete is shown.</span></span>{{end}}
 {{/* The safe choice goes back to the report and changes nothing. */}}
-<span class="tipbox"><a class="btn-plain" href="/systemcheck" aria-describedby="tipno">No, go back</a><span class="tip" role="tooltip" id="tipno">Nothing is removed. You return to the System check.</span></span>
+<span class="tipbox"><a class="btn-plain" href="/systemcheck" aria-describedby="tipno">Cancel</a><span class="tip" role="tooltip" id="tipno">Nothing is removed. You return to the System check.</span></span>
 </div>
+</form>
 {{/* Version 3: the result. */}}
 {{else}}
 <h1>The monitor has stopped</h1>
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
346afec2bcce8a16a813d780a794a544d2d77e528f0fa429d1abd104e2b34a03  syscheck.go
06f7812374ed13ecb604bbaaa2b6b20102fb4d592429e06dfd53277f004236db  syscheck_test.go
4570ea2e8e7c30e902b094bc71814ef9928c998364cdd2dc5d87801836d609fc  web/app.css
a0242e2f06adba3feab83ce0484f6c9b749564def96eedc9309b1eec7a19d571  web/systemcheck.html
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
# Build for this computer the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Check that the program also compiles for Windows and macOS (nothing is kept).
for target in windows/amd64 darwin/arm64 darwin/amd64; do
  # Build for one target and throw the file away.
  GOOS="${target%/*}" GOARCH="${target#*/}" CGO_ENABLED=0 go build -trimpath -o /dev/null . || { echo "FAIL  build for $target"; exit 1; }
  # Report it.
  echo "PASS  compiles for $target"
done
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
# Tell the person what to look at.
echo "NEXT  start ./bin/OllamaControlCenter, open http://127.0.0.1:8765/ and use the System check link then Uninstall this tool: the page must show the impact list and the box for the word uninstall; try a wrong word (nothing is removed) and then press Cancel; then commit, push and merge"
# List the changed files; nothing is committed yet.
git status --short
