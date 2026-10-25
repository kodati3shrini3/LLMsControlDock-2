#!/usr/bin/env bash
# Script 32: move the unload timer under the state words (own line, italic, in [square brackets], normal font); applied on the feature branch.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch from script 30.
[ "$(git branch --show-current)" = "feature/loaded-unload-countdown" ] || { echo "FAIL  not on feature/loaded-unload-countdown"; exit 1; }
# Script 31 (the italic and bracket style) must be applied first; the marker is its italic rule in the stylesheet.
if ! grep -q "font-style: italic" web/app.css; then
  # Say what is happening.
  echo "INFO  script 31 was not applied yet; applying it first"
  # Run it (it checks and tests by itself).
  bash scripts/31-step6g-timer-restyle.sh
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/timer_test.go b/timer_test.go
index 6caf392..a88a958 100644
--- a/timer_test.go
+++ b/timer_test.go
@@ -97,8 +97,8 @@ func TestTableViewTimersOnlyForLoaded(t *testing.T) {
 	} // end of the count check
 } // end of TestTableViewTimersOnlyForLoaded
 
-// TestPageShowsTimerBetweenStateAndButton checks the page markup: a bold timer with its seconds, placed after the state words and before the Unload button, and an empty slot for a row that is not loaded.
-func TestPageShowsTimerBetweenStateAndButton(t *testing.T) {
+// TestPageShowsTimerUnderState checks the page markup: a ticking timer on its own line after the state words and the Unload form, and no timer line for a row that is not loaded.
+func TestPageShowsTimerUnderState(t *testing.T) {
 	// A fake with one loaded model; its /api/ps entry has an unload time five minutes away.
 	f := &loadFake{loaded: []string{"alpha:1b"}}
 	// Build the rig.
@@ -110,27 +110,25 @@ func TestPageShowsTimerBetweenStateAndButton(t *testing.T) {
 		// Report the problem.
 		t.Fatalf("status %d", status)
 	} // end of the status check
-	// The timer markup: bold element with the timer class, ticking seconds and the role.
-	m := regexp.MustCompile(`<strong class="timer countdown" data-seconds="(\d+)" role="timer" aria-label="Time until Ollama unloads [^"]+">[^<]+</strong>`).FindStringSubmatch(body)
-	// It must exist.
-	if m == nil {
+	// The timer markup: its own line, the timer class, ticking seconds and the role.
+	if !regexp.MustCompile(`<span class="timerline"><span class="timer countdown" data-seconds="\d+" role="timer" aria-label="Time until Ollama unloads alpha:1b">[^<]+</span></span>`).MatchString(body) {
 		// Report the problem.
-		t.Fatalf("no ticking timer in the page")
+		t.Fatalf("no ticking timer line in the page")
 	} // end of the timer check
-	// The order inside the cell: state words, then the timer, then the Unload form.
+	// The order inside the cell: state words, then the Unload form, then the timer line.
 	iState := strings.Index(body, "Loaded</span>")
-	// Where the timer starts.
-	iTimer := strings.Index(body, `<span class="timerslot"><strong`)
 	// Where the Unload form starts.
 	iForm := strings.Index(body, `action="/unload"`)
+	// Where the timer line starts.
+	iTimer := strings.Index(body, `<span class="timerline">`)
 	// The three must come in this order.
-	if !(iState >= 0 && iState < iTimer && iTimer < iForm) {
+	if !(iState >= 0 && iState < iForm && iForm < iTimer) {
 		// Report the problem.
-		t.Errorf("wrong order: state %d, timer %d, unload form %d", iState, iTimer, iForm)
+		t.Errorf("wrong order: state %d, unload form %d, timer line %d", iState, iForm, iTimer)
 	} // end of the order check
-	// A row that is not loaded gets an empty slot so the buttons stay aligned.
-	if !strings.Contains(body, `<span class="timerslot" aria-hidden="true"></span>`) {
+	// Only the one loaded row has a timer line.
+	if n := strings.Count(body, `class="timerline"`); n != 1 {
 		// Report the problem.
-		t.Errorf("a row that is not loaded has no empty timer slot")
-	} // end of the slot check
-} // end of TestPageShowsTimerBetweenStateAndButton
+		t.Errorf("%d timer lines, want 1", n)
+	} // end of the count check
+} // end of TestPageShowsTimerUnderState
diff --git a/web/app.css b/web/app.css
index c713c37..2a44970 100644
--- a/web/app.css
+++ b/web/app.css
@@ -743,14 +743,14 @@ h2 {
   min-width: 8rem;
 } /* end of rule */
 
-/* The slot between the state words and the Load or Unload button; every row has one of the same width, so all the buttons stay in line. */
-.timerslot {
-  /* A box in the line, so it can have a width. */
-  display: inline-block;
-  /* Just wide enough for the longest timer text in square brackets. */
-  min-width: 6.8rem;
-  /* Keep the text in line with the words around it. */
-  vertical-align: baseline;
+/* The line under the state words that holds the unload timer; it is its own line, so it adds no width to the table. */
+.timerline {
+  /* A block, so it starts on a new line under the words. */
+  display: block;
+  /* A little air above it, not more. */
+  margin-top: 0.1rem;
+  /* Start under the dot of the state words. */
+  margin-left: 0;
 } /* end of rule */
 
 /* The unload timer itself: italic, in the same font and size as the text around it. */
diff --git a/web/index.html b/web/index.html
index 69a273c..0c1959c 100644
--- a/web/index.html
+++ b/web/index.html
@@ -139,8 +139,6 @@
 <td><span class="statelabel"><span class="dot {{if .Loaded}}dot-on{{else}}dot-off{{end}}" aria-hidden="true"></span> {{.StateWord}}</span>
 {{- /* Only a loaded model gets the Unload button; it opens a warning page first, so one click never unloads anything. */ -}}
 {{if .Loaded}}
-{{/* The unload timer sits between the words and the button; bold, with a title and a label so it is more than a bare number. */}}
-<span class="timerslot"><strong class="timer{{if .TimerSeconds}} countdown{{end}}"{{if .TimerSeconds}} data-seconds="{{.TimerSeconds}}"{{end}}{{if .TimerExpired}} data-expired="1"{{end}} role="timer" aria-label="Time until Ollama unloads {{.Name}}">{{.Timer}}</strong></span>
 {{/* A small form that sends the model name and the page token to the warning page. */}}
 <form class="unloadform" method="post" action="/unload">
 {{/* The page token proves the form comes from this monitor. */}}
@@ -152,8 +150,6 @@
 {{/* End of the form. */}}
 </form>
 {{else}}
-{{/* An empty slot of the same width keeps the Load buttons in line with the Unload buttons. */}}
-<span class="timerslot" aria-hidden="true"></span>
 {{/* A model that is not loaded gets the Load button; it opens a warning page about memory first, so one click never loads anything. */}}
 <form class="unloadform" method="post" action="/load">
 {{/* The page token proves the form comes from this monitor. */}}
@@ -166,6 +162,12 @@
 </form>
 {{/* End of the loaded check. */}}
 {{end -}}
+{{/* Only a loaded model gets the unload timer; it sits on its own line under the state words, so it takes no extra width. */}}
+{{if .Loaded}}
+{{/* The timer line; the stylesheet draws the square brackets and the italics. */}}
+<span class="timerline"><span class="timer{{if .TimerSeconds}} countdown{{end}}"{{if .TimerSeconds}} data-seconds="{{.TimerSeconds}}"{{end}}{{if .TimerExpired}} data-expired="1"{{end}} role="timer" aria-label="Time until Ollama unloads {{.Name}}">{{.Timer}}</span></span>
+{{/* End of the timer line. */}}
+{{end}}
 </td>
 {{/* The other eight cells; the first of the nine is the state text, which the cell above already shows. */}}
 {{range slice .Cells 1}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch to the working files.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the changed files must have after the patch.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
1852c7738397788f223cd6953629f6df431da74ee53d43551d76b96321fa4e64  timer_test.go
1b20439b6d6ef4e734bf290b4d7f19eea58a6afb4ba126916ee4687c01239fdc  web/app.css
6975fae30d1e1a8668166628afce09ce44851637c291c7fe72d6499c70b05a9c  web/index.html
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the 3 changed files match the tested versions"
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
