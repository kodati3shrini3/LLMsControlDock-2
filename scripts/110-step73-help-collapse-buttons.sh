#!/usr/bin/env bash
# Script 110 (Help page, collapse buttons): the opening sentence of the Help page is reworded; the list of topic links at the top is removed; and in each open topic the round back arrow is replaced by a round collapse button of the same look (a chevron), at the top and at the bottom of the topic. A click closes the topic and brings its title back into view. The button needs a small script file (helpclose.js) and stays hidden without it; the page's own back arrow at the top and the Back to the monitor button at the bottom stay. Tests follow.
# Run it from the branch feature/help-topics-open-close (after script 109): cd ~/LLMsControlDock && bash scripts/110-step73-help-collapse-buttons.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 109), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["help.go"]="a5cd05c3e84a5f46fc41f28508b6368a6f07d89fa2cf3581071fcb7b4cd03d19"
BEFORE["help_test.go"]="1f2174fe0af00f9bd66049ba995bf13ccf9b09b12402da4c0650b85d8504d682"
BEFORE["web.go"]="a5018cdb39d400f97d6effb701de70eb0edf52f794f3fc10ec7be68f2ccec05d"
BEFORE["web/help.html"]="b528233151596ee80c0b35906ad7221549f147771d82129623362b64de7f1bd6"
BEFORE["web/app.css"]="63884d33aaf880b8476219b7fae6ef43c9b0f1f052e6fd2e434764a3f1a4a83f"
AFTER["help.go"]="36d8c2b6bd2d37f7efdd921a31e84f60ec7492832fd9150f03331b9a5e2d7d1f"
AFTER["help_test.go"]="fd87192e825142ec5691d6008bebcff6d3aa43b3828f34a2135cae9ca9753687"
AFTER["web.go"]="4baabafbf27e87f716a63c9cda53e79508c1275e53b43aad4faef2be7ae67ffd"
AFTER["web/help.html"]="fc0057fc03971e3adbacaa69b804dfc8808879ab3dfe045d218fbd140c82232c"
AFTER["web/app.css"]="5848f24471badf8631f2fcee1510acf7878cafeea9336b477d3829d6a24fc030"
AFTER["helpclose.go"]="adb518ca31a1a3b4db4093dc1e5544cd89318440b6dcbb55f32c36a649fa1208"
AFTER["web/helpclose.js"]="3df6c12ad6696b4ef770030e21d8015372781aab89f08a66a178b235a196273e"

# Count of passed checks.
PASS=0
# Count of failed checks (the script stops at the first one).
FAIL=0
# pass prints one PASS line and counts it; it is only called after a real check succeeded.
pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
# fail prints one FAIL line, counts it, and stops the script at once.
fail() { echo "FAIL  $1"; FAIL=$((FAIL + 1)); echo "Result: $PASS passed, $FAIL failed"; exit 1; }
# sha prints the sha256 of one file.
sha() { sha256sum "$1" | cut -d' ' -f1; }

# Go to the top folder of the git project this script was started in.
cd "$(git rev-parse --show-toplevel)"
# The project must be the right one: its main.go and go.mod must be here.
[ -f main.go ] && [ -f go.mod ] || fail "this is not the project folder (main.go or go.mod missing)"
# Say where we are.
echo "Project folder: $(pwd)"

# The branch we are on.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# Never change main directly: every change goes through a branch and a pull request.
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/help-topics-open-close (git switch feature/help-topics-open-close)"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 109 must have been applied: the last help topic exists.
grep -q 'ID:    "uninstall"' help.go || fail "script 109 must be applied first"
# Report it.
pass "script 109 is applied"

# Refuse to run twice: the new file exists when this change was applied before.
if [ -e helpclose.go ]; then fail "helpclose.go already exists: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# Every file to change must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the project is in another state than expected.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} files to change are the expected versions before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_94_END'
diff --git a/help.go b/help.go
index 6ebafa3..50db500 100644
--- a/help.go
+++ b/help.go
@@ -411,7 +411,9 @@ func helpHandler() http.HandlerFunc {
 			// Stop here.
 			return
 		} // end of the template check
-		// Tell the browser this is an HTML page; the strict policy without scripts stays in place.
+		// The page runs the monitor's own small script file, and nothing else.
+		w.Header().Set("Content-Security-Policy", contentSecurityPolicyWithScript)
+		// Tell the browser this is an HTML page.
 		w.Header().Set("Content-Type", "text/html; charset=utf-8")
 		// Send the finished page.
 		w.Write(buf.Bytes())
diff --git a/help_test.go b/help_test.go
index 92532ac..46eb836 100644
--- a/help_test.go
+++ b/help_test.go
@@ -69,15 +69,15 @@ func TestHelpPage(t *testing.T) {
 	rig := newThemeRig(t)
 	// Fetch the page.
 	status, header, body := get(t, rig.h, http.MethodGet, "/help")
-	// Found, as HTML, under the strict policy.
-	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/html") || strings.Contains(header.Get("Content-Security-Policy"), "script-src") {
+	// Found, as HTML, under the policy that allows this program's own script file and nothing inline.
+	if csp := header.Get("Content-Security-Policy"); status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/html") || !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe-inline") || strings.Contains(csp, "unsafe-eval") {
 		// Stop.
 		t.Fatalf("status %d, type %q, policy %q", status, header.Get("Content-Type"), header.Get("Content-Security-Policy"))
 	} // end of the check
-	// No script, and only reading.
-	if strings.Contains(body, "<script") {
+	// Exactly one script: the monitor's own small file for the collapse buttons.
+	if strings.Count(body, "<script") != 1 || strings.Count(body, `<script src="/helpclose.js" defer></script>`) != 1 {
 		// Report.
-		t.Error("the Help page carries a script")
+		t.Error("the Help page must carry only the helpclose.js script")
 	} // end of the script check
 	// Only GET is allowed.
 	if res := post(t, rig.h, "/help", url.Values{}, fromThisPage); res.StatusCode != http.StatusMethodNotAllowed {
@@ -147,22 +147,17 @@ func TestHelpPage(t *testing.T) {
 			// Report.
 			t.Errorf("topic %s is not a closed section", tp.ID)
 		} // end of the section check
-		// The contents link.
-		if !strings.Contains(body, `<li><a href="#`+tp.ID+`">`+html.EscapeString(tp.Title)+`</a></li>`) {
-			// Report.
-			t.Errorf("the contents list lacks a link to %s", tp.ID)
-		} // end of the link check
 		// The title is the clickable row.
 		if !strings.Contains(body, `<summary class="helpsum"><h2 id="`+tp.ID+`-title">`) {
 			// Report.
 			t.Errorf("topic %s has no clickable title", tp.ID)
 		} // end of the title check
-		// An arrow at the top of the open topic (before the picture) and one at the bottom (after the list).
+		// A collapse button at the top of the open topic (before the picture) and one at the bottom (after the list).
 		start := strings.Index(body, `<details class="helptopic" id="`+tp.ID+`">`)
 		// The topic's own section.
 		sec := body[start : start+strings.Index(body[start:], `</details>`)]
 		// The arrows, the picture and the list inside it.
-		top, bottom := strings.Index(sec, `id="tipback-`+tp.ID+`-top"`), strings.Index(sec, `id="tipback-`+tp.ID+`-bottom"`)
+		top, bottom := strings.Index(sec, `id="tipclose-`+tp.ID+`-top"`), strings.Index(sec, `id="tipclose-`+tp.ID+`-bottom"`)
 		// The picture and the list.
 		svg, list := strings.Index(sec, `<svg class="swimlane"`), strings.Index(sec, `<ol class="helpsteps">`)
 		// Check the order.
@@ -171,11 +166,21 @@ func TestHelpPage(t *testing.T) {
 			t.Errorf("topic %s: arrows at %d and %d, picture at %d, list at %d", tp.ID, top, bottom, svg, list)
 		} // end of the arrow check
 	} // end of the topic loop
-	// The page's own arrow plus two for every topic.
-	if n := strings.Count(body, `aria-label="Back to the monitor"`); n != 1+2*len(helpTopics) {
+	// Only the page's own back arrow; the topics carry collapse buttons, which start hidden.
+	if n := strings.Count(body, `aria-label="Back to the monitor"`); n != 1 {
 		// Report.
-		t.Errorf("%d back arrows, want %d", n, 1+2*len(helpTopics))
+		t.Errorf("%d back arrows, want 1", n)
 	} // end of the arrow count
+	// Two collapse buttons for every topic, each hidden until the script shows it.
+	if n := strings.Count(body, `class="backcircle helpclose" hidden aria-label="Collapse this topic"`); n != 2*len(helpTopics) {
+		// Report.
+		t.Errorf("%d collapse buttons, want %d", n, 2*len(helpTopics))
+	} // end of the collapse count
+	// The old contents list is gone.
+	if strings.Contains(body, `class="helptoc"`) || strings.Contains(body, "This is the first topic") {
+		// Report.
+		t.Error("the contents list or the old sentence is still on the page")
+	} // end of the old-text check
 	// The monitor links to the Help page.
 	if _, _, main := get(t, rig.h, http.MethodGet, "/"); !strings.Contains(main, `<a class="brandbtn" href="/help">Help</a>`) {
 		// Report.
@@ -202,3 +207,46 @@ func itoa(n int) string {
 	// The text.
 	return s
 } // end of itoa
+
+// TestHelpCloseScriptIsServedAndHarmless checks the script is sent as JavaScript, only on GET, and only closes a topic: nothing is sent anywhere.
+func TestHelpCloseScriptIsServedAndHarmless(t *testing.T) {
+	// A rig.
+	rig := newThemeRig(t)
+	// Fetch the script.
+	status, header, body := get(t, rig.h, http.MethodGet, "/helpclose.js")
+	// Found and typed as JavaScript.
+	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/javascript") || !strings.Contains(body, "helpclose") {
+		// Report.
+		t.Fatalf("status %d, type %q", status, header.Get("Content-Type"))
+	} // end of the check
+	// Only GET is allowed.
+	if res := post(t, rig.h, "/helpclose.js", url.Values{}, fromThisPage); res.StatusCode != http.StatusMethodNotAllowed {
+		// Report.
+		t.Errorf("POST /helpclose.js = %d, want 405", res.StatusCode)
+	} // end of the method check
+	// Nothing that sends data away, runs text as code, writes markup or opens an address.
+	for _, bad := range []string{"fetch(", "XMLHttpRequest", "sendBeacon", "WebSocket", "eval(", "new Function", "innerHTML", "outerHTML", "document.write", "http://", "https://", "location", "import("} {
+		// Present.
+		if strings.Contains(body, bad) {
+			// Report.
+			t.Errorf("the help script must not contain %q", bad)
+		} // end of the check
+	} // end of the loop
+	// Every code line carries a comment on the line above it or ends a block.
+	lines := strings.Split(body, "\n")
+	// Check from the second line.
+	for i := 1; i < len(lines); i++ {
+		// The trimmed line.
+		l := strings.TrimSpace(lines[i])
+		// Blank lines, comments and lines that close a block need nothing.
+		if l == "" || strings.HasPrefix(l, "//") || strings.HasPrefix(l, "}") {
+			// Fine.
+			continue
+		} // end of the skip check
+		// The line above must be a comment.
+		if !strings.HasPrefix(strings.TrimSpace(lines[i-1]), "//") {
+			// Report.
+			t.Errorf("helpclose.js line %d has no comment above it: %q", i+1, l)
+		} // end of the comment check
+	} // end of the line loop
+} // end of TestHelpCloseScriptIsServedAndHarmless
diff --git a/helpclose.go b/helpclose.go
new file mode 100644
index 0000000..d6b9634
--- /dev/null
+++ b/helpclose.go
@@ -0,0 +1,22 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// embed lets the script file be stored inside the executable (the blank name means we only need its side effect).
+	_ "embed"
+	// net/http provides requests and status codes.
+	"net/http"
+) // end of imports
+
+// helpCloseJS is the small script behind the collapse buttons of the Help page, stored inside the executable at build time.
+//
+//go:embed web/helpclose.js
+var helpCloseJS []byte
+
+// helpCloseHandler sends the script file.
+func helpCloseHandler(w http.ResponseWriter, r *http.Request) {
+	// Tell the browser this is JavaScript.
+	w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
+	// Send it.
+	w.Write(helpCloseJS)
+} // end of helpCloseHandler
diff --git a/web/app.css b/web/app.css
index a3b4d1e..4faefb3 100644
--- a/web/app.css
+++ b/web/app.css
@@ -3129,12 +3129,6 @@ html[data-size="medium"] svg[width="22"] {
   padding-left: 1.5rem;
 } /* end of rule */
 
-/* The list of topic links at the top of the Help page. */
-.helptoc {
-  /* Room for the bullets. */
-  padding-left: 1.5rem;
-} /* end of rule */
-
 /* The clickable title row of a closed or open topic. */
 .helpsum {
   /* Shows the pointing hand over the title. */
@@ -3158,3 +3152,19 @@ html[data-size="medium"] svg[width="22"] {
   /* Space above and below. */
   margin: 0.6rem 0;
 } /* end of rule */
+
+/* The collapse button of the Help page is a real button: same round look as the back arrow, with no extra padding and a pointing hand. */
+button.helpclose {
+  /* No padding of a normal button. */
+  padding: 0;
+  /* The pointing hand. */
+  cursor: pointer;
+  /* The same font as the page. */
+  font: inherit;
+} /* end of rule */
+
+/* The collapse button is hidden until the script shows it. */
+button.helpclose[hidden] {
+  /* Really hidden, even though the circle sets its own display. */
+  display: none;
+} /* end of rule */
diff --git a/web/help.html b/web/help.html
index 45a3fea..e554152 100644
--- a/web/help.html
+++ b/web/help.html
@@ -22,21 +22,15 @@
 {{/* The name of the page. */}}
 <h1>Help</h1>
 {{/* What the page is. */}}
-<p class="muted">Each topic shows who does what, in lanes, from the top down. Click a topic's title to open it. This is the first topic; more follow.</p>
-{{/* The contents: a link to every topic's title. */}}
-<nav aria-label="Help topics">
-<ul class="helptoc">
-{{range .Topics}}<li><a href="#{{.ID}}">{{.Title}}</a></li>
-{{end}}</ul>
-</nav>
+<p class="muted">Click a topic to open a diagram of what happens, step by step. It has one lane for each of you, LLMsControlDock, Ollama and ollama.com, and it reads from the top down.</p>
 {{/* The topics; each one starts closed and opens when its title is clicked (no script is needed). */}}
 {{range $t := .Topics}}
 {{/* One topic. */}}
 <details class="helptopic" id="{{.ID}}">
 {{/* Its heading, which is also the button that opens it. */}}
 <summary class="helpsum"><h2 id="{{.ID}}-title">{{.Title}}</h2></summary>
-{{/* A way back to the monitor at the top of the open topic. */}}
-<p class="helpback"><span class="tipbox backhere"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback-{{$t.ID}}-top"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback-{{$t.ID}}-top">Back to the monitor</span></span></p>
+{{/* A button that collapses the open topic again; it is hidden until the small script file shows it, because it does nothing without the script. */}}
+<p class="helpback"><span class="tipbox backhere"><button type="button" class="backcircle helpclose" hidden aria-label="Collapse this topic" aria-describedby="tipclose-{{$t.ID}}-top"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 15l6-6 6 6"/></svg></button><span class="tip tip-icon" role="tooltip" id="tipclose-{{$t.ID}}-top">Collapse this topic</span></span></p>
 {{/* The plain introduction. */}}
 <p>{{.Intro}}</p>
 {{/* The picture; its name and description are read by screen readers, and the numbered list below says the same in words. */}}
@@ -64,8 +58,8 @@
 <ol class="helpsteps">
 {{range .List}}<li><strong>{{.Lane}}:</strong> {{.Text}}</li>
 {{end}}</ol>
-{{/* A way back to the monitor at the bottom of the open topic, because the pictures are long. */}}
-<p class="helpback"><span class="tipbox backhere"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback-{{$t.ID}}-bottom"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback-{{$t.ID}}-bottom">Back to the monitor</span></span></p>
+{{/* The same button at the bottom of the open topic, because the pictures are long. */}}
+<p class="helpback"><span class="tipbox backhere"><button type="button" class="backcircle helpclose" hidden aria-label="Collapse this topic" aria-describedby="tipclose-{{$t.ID}}-bottom"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 15l6-6 6 6"/></svg></button><span class="tip tip-icon" role="tooltip" id="tipclose-{{$t.ID}}-bottom">Collapse this topic</span></span></p>
 {{/* End of the topic. */}}
 </details>
 {{end}}
@@ -75,5 +69,7 @@
 </section>
 {{/* End of the main content. */}}
 </main>
+{{/* The small script that makes the collapse buttons work. */}}
+<script src="/helpclose.js" defer></script>
 </body>{{/* end of the visible page. */}}
 </html>{{/* end of the page. */}}
diff --git a/web/helpclose.js b/web/helpclose.js
new file mode 100644
index 0000000..ca32dcc
--- /dev/null
+++ b/web/helpclose.js
@@ -0,0 +1,24 @@
+// Help page: each open topic has a round collapse button; a click closes that topic and brings its title back into view. The buttons are hidden in the page and shown here, because they do nothing without this script.
+(function () {
+  // Every collapse button on the page.
+  var buttons = document.querySelectorAll('button.helpclose');
+  // Go through them.
+  buttons.forEach(function (btn) {
+    // Show the button: the script is running.
+    btn.hidden = false;
+    // When the person clicks it.
+    btn.addEventListener('click', function () {
+      // The topic that holds the button.
+      var topic = btn.closest('details');
+      // Nothing to close without one.
+      if (!topic) {
+        // Stop here.
+        return;
+      }
+      // Close the topic.
+      topic.open = false;
+      // Bring the title back into view, because the bottom button leaves the person far down the page.
+      topic.scrollIntoView({ block: 'start' });
+    });
+  });
+})();
diff --git a/web.go b/web.go
index 8a2c9dd..f9cc9d1 100644
--- a/web.go
+++ b/web.go
@@ -311,6 +311,8 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	mux.HandleFunc("GET /copy.js", copyHandler)
 	// Route: a GET request for "/sortpick.js" sends the small script that re-sorts the Find LLM results when the Sort by choice changes.
 	mux.HandleFunc("GET /sortpick.js", sortPickHandler)
+	// Route: a GET request for "/helpclose.js" sends the small script that makes the collapse buttons of the Help page work.
+	mux.HandleFunc("GET /helpclose.js", helpCloseHandler)
 	// Route: a GET request for "/loading.js" sends the small script that shows the waiting message while a model loads (only the load warning page uses it).
 	mux.HandleFunc("GET /loading.js", loadingHandler)
 	// Route: a GET request for "/attention.js" sends the small script that opens the problem dialog (only the System check page uses it, and only when it found a problem).
OCC_PATCH_94_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched and new files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} changed or new files have the expected sha256"

# gofmt lists files whose layout differs from the standard.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code.
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once.
go test -count=1 ./... || fail "go test failed"
# Report it.
pass "go test: all tests pass"

# Build the program for this computer, as the project always does (no C compiler: CGO_ENABLED=0; -trimpath removes folder names).
CGO_ENABLED=0 go build -trimpath -o bin/LLMsControlDock . || fail "go build failed"
# Report it.
pass "build for this computer: bin/LLMsControlDock"

# Compile (without keeping the result) for all six systems; nothing here uses GitHub Actions.
for TARGET in linux/arm64 linux/amd64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Compile; the output goes to /dev/null because only errors matter.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -trimpath -o /dev/null . || fail "compile for $TARGET failed"
  # Report it.
  pass "compile for $TARGET"
# End of the loop over the systems.
done


# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  start bin/LLMsControlDock and open the Help page, open a topic and use the collapse buttons (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
