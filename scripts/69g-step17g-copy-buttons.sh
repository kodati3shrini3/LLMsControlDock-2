#!/usr/bin/env bash
# Script 69g: the restore page gets a Copy button next to each command (copies the text only; you paste it into the terminal yourself). Uses one small script file of this program; the security policy still allows scripts from this address only.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/compare-groups" ] || { echo "FAIL  not on feature/compare-groups"; exit 1; }
# Script 69f must be applied already.
grep -q "func writeNoticeBlock" compreport.go || { echo "FAIL  script 69f was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e copy.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/copy.go b/copy.go
new file mode 100644
index 0000000..f24806f
--- /dev/null
+++ b/copy.go
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
+// copyJS is the small script behind the copy buttons next to commands, stored inside the executable at build time.
+//
+//go:embed web/copy.js
+var copyJS []byte
+
+// copyHandler sends the script file.
+func copyHandler(w http.ResponseWriter, r *http.Request) {
+	// Tell the browser this is JavaScript.
+	w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
+	// Send it.
+	w.Write(copyJS)
+} // end of copyHandler
diff --git a/copy_test.go b/copy_test.go
new file mode 100644
index 0000000..6e2de90
--- /dev/null
+++ b/copy_test.go
@@ -0,0 +1,140 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// net/http gives the method and status names.
+	"net/http"
+	// net/url builds the form values.
+	"net/url"
+	// regexp finds the buttons and their targets.
+	"regexp"
+	// strings searches the page and the script.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// TestCopyScriptIsServedAndHarmless checks that the script is sent as JavaScript, only on GET, and that it cannot send anything anywhere or run anything: it may only copy text that is already on the page.
+func TestCopyScriptIsServedAndHarmless(t *testing.T) {
+	// A rig.
+	rig, _, _ := delRig(t)
+	// Fetch the script.
+	status, header, body := get(t, rig.h, http.MethodGet, "/copy.js")
+	// Found and typed as JavaScript, with both ways of copying.
+	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/javascript") || !strings.Contains(body, "navigator.clipboard") || !strings.Contains(body, "execCommand") {
+		// Report it.
+		t.Fatalf("status %d, type %q", status, header.Get("Content-Type"))
+	} // end of the check
+	// Only GET is allowed.
+	if res := post(t, rig.h, "/copy.js", url.Values{}, fromThisPage); res.StatusCode != http.StatusMethodNotAllowed {
+		// Report it.
+		t.Errorf("POST /copy.js = %d, want 405", res.StatusCode)
+	} // end of the method check
+	// Nothing that sends data away, runs text as code, writes markup or opens an address.
+	for _, bad := range []string{"fetch(", "XMLHttpRequest", "sendBeacon", "WebSocket", "eval(", "new Function", "innerHTML", "outerHTML", "document.write", "http://", "https://", "location", "import("} {
+		// Present.
+		if strings.Contains(body, bad) {
+			// Report it.
+			t.Errorf("the copy script must not contain %q", bad)
+		} // end of the check
+	} // end of the loop
+	// Every code line carries a comment on the line above it or ends a block: no bare statement.
+	lines := strings.Split(body, "\n")
+	// Check from the second line.
+	for i := 1; i < len(lines); i++ {
+		// The trimmed line.
+		l := strings.TrimSpace(lines[i])
+		// Blank lines, comments, and lines that close or continue a block (they start with a closing brace) need nothing.
+		if l == "" || strings.HasPrefix(l, "//") || strings.HasPrefix(l, "}") {
+			// Fine.
+			continue
+		} // end of the skip check
+		// The line above must be a comment.
+		if prev := strings.TrimSpace(lines[i-1]); !strings.HasPrefix(prev, "//") && !strings.HasSuffix(strings.TrimSpace(lines[i]), "// ok") {
+			// Allow the continuation of a statement that has a comment two lines up (a line inside a call).
+			if i < 2 || !strings.HasPrefix(strings.TrimSpace(lines[i-2]), "//") {
+				// Report it.
+				t.Errorf("copy.js line %d has no comment above it: %q", i+1, l)
+			} // end of the second check
+		} // end of the comment check
+	} // end of the line loop
+} // end of TestCopyScriptIsServedAndHarmless
+
+// TestRestorePageHasCopyButtons checks the restore page: a hidden Copy button for each of the five commands, each pointing at the element that holds that command, the script included once, and the security policy allowing scripts from this address only.
+func TestRestorePageHasCopyButtons(t *testing.T) {
+	// A rig with a deleted model that the library still has.
+	rig, f, _ := delRig(t)
+	// The library has the model.
+	f.reg.setReg(manifestPath("alpha", "1b"), 200, "m-alpha")
+	// Delete it.
+	post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
+	// The restore page.
+	res := post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
+	// Its text.
+	body := bodyOf(res)
+	// Five buttons, each starting hidden.
+	buttons := regexp.MustCompile(`<button type="button" class="copybtn" data-target="([a-z0-9-]+)" hidden aria-label="Copy command: [^"]+">`).FindAllStringSubmatch(body, -1)
+	// Count.
+	if len(buttons) != 5 {
+		// Stop the test.
+		t.Fatalf("%d copy buttons, want 5", len(buttons))
+	} // end of the count check
+	// Each target must be one element that holds the command it is meant for.
+	want := map[string]string{
+		// The direct command.
+		"cmd-local": "ollama pull alpha:1b",
+		// Docker.
+		"cmd-docker": "docker exec &lt;container-name&gt; ollama pull alpha:1b",
+		// Docker, finding the name.
+		"cmd-docker-find": "docker ps",
+		// Kubernetes.
+		"cmd-k8s": "kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull alpha:1b",
+		// Kubernetes, finding the pod.
+		"cmd-k8s-find": "kubectl get pods -n &lt;namespace&gt;",
+	} // end of the table
+	// Go through the buttons.
+	for _, b := range buttons {
+		// The text the button must copy.
+		text, ok := want[b[1]]
+		// An unknown target.
+		if !ok {
+			// Report it.
+			t.Errorf("unknown target %q", b[1])
+			// Next.
+			continue
+		} // end of the target check
+		// Exactly one element with that id, holding exactly that command.
+		if strings.Count(body, `id="`+b[1]+`"`) != 1 || !strings.Contains(body, `<code id="`+b[1]+`">`+text+`</code>`) {
+			// Report it.
+			t.Errorf("target %s does not hold %q", b[1], text)
+		} // end of the element check
+		// Mark it as seen.
+		delete(want, b[1])
+	} // end of the loop
+	// Every command had a button.
+	if len(want) != 0 {
+		// Report it.
+		t.Errorf("commands without a button: %v", want)
+	} // end of the coverage check
+	// The script once, the status line for screen readers, and a policy that allows this address's scripts only.
+	if strings.Count(body, `<script src="/copy.js" defer></script>`) != 1 || strings.Count(body, "<script") != 1 || !strings.Contains(body, `id="copystatus"`) {
+		// Report it.
+		t.Errorf("script or status line missing")
+	} // end of the script check
+	// The policy.
+	if csp := res.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe-inline") || strings.Contains(csp, "unsafe-eval") {
+		// Report it.
+		t.Errorf("policy %q", csp)
+	} // end of the policy check
+	// A restore page with no command (the library lacks the model) has no button, no script and the strict policy.
+	f.reg.setReg(manifestPath("alpha", "1b"), 404, "")
+	// Ask again.
+	res = post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
+	// The text.
+	body = bodyOf(res)
+	// Nothing to copy.
+	if strings.Contains(body, "copybtn") || strings.Contains(body, "<script") || strings.Contains(res.Header.Get("Content-Security-Policy"), "script-src") {
+		// Report it.
+		t.Errorf("a page without commands must carry no copy button, no script and the strict policy")
+	} // end of the check
+} // end of TestRestorePageHasCopyButtons
diff --git a/delete.go b/delete.go
index 4b9e9e7..d3e6adc 100644
--- a/delete.go
+++ b/delete.go
@@ -173,8 +173,8 @@ func deleteHandlers(addr ollamaAddress, token string, store *deletedStore, hist
 			// Stop here.
 			return
 		} // end of the template check
-		// A page with a ticking timer may run the monitor's own script, and nothing else.
-		if data.Seconds > 0 {
+		// A page with a ticking timer, or with copy buttons next to commands, may run the monitor's own script, and nothing else.
+		if data.Seconds > 0 || data.ShowPull {
 			// Replace the strict policy by the one that allows the script file.
 			w.Header().Set("Content-Security-Policy", contentSecurityPolicyWithScript)
 		} // end of the script policy
diff --git a/web.go b/web.go
index 79e02b8..8a534da 100644
--- a/web.go
+++ b/web.go
@@ -197,6 +197,8 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	mux.HandleFunc("POST /stop/confirm", stopConfirm)
 	// Route: a GET request for "/countdown.js" sends the small script that makes the timers tick (only the message pages use it).
 	mux.HandleFunc("GET /countdown.js", countdownHandler)
+	// Route: a GET request for "/copy.js" sends the small script behind the copy buttons next to commands (only the restore page uses it).
+	mux.HandleFunc("GET /copy.js", copyHandler)
 	// Route: a GET request for "/loading.js" sends the small script that shows the waiting message while a model loads (only the load warning page uses it).
 	mux.HandleFunc("GET /loading.js", loadingHandler)
 	// Route: a GET request for exactly "/" shows the page; other paths get 404 and other methods get 405 from the router.
diff --git a/web/app.css b/web/app.css
index 6e8aa52..9973b26 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1485,6 +1485,72 @@ a.btn-load {
   overflow-wrap: anywhere;
 } /* end of rule */
 
+/* The small Copy button next to a command: an outlined pill, as large as the text beside it. */
+.copybtn {
+  /* Icon and word side by side. */
+  display: inline-flex;
+  /* Centre them on one line. */
+  align-items: center;
+  /* Space between the icon and the word. */
+  gap: 0.3rem;
+  /* Room from the command. */
+  margin-left: 0.4rem;
+  /* Room inside. */
+  padding: 0.1rem 0.6rem;
+  /* Outline in the border colour. */
+  border: 1px solid var(--border);
+  /* Pill shape. */
+  border-radius: 999px;
+  /* The page's own colours. */
+  background: transparent;
+  /* Text colour. */
+  color: var(--text);
+  /* The same font as the page. */
+  font: inherit;
+  /* A little smaller than the text. */
+  font-size: 0.85em;
+  /* A hand to show it can be pressed. */
+  cursor: pointer;
+} /* end of rule */
+
+/* A hidden Copy button stays hidden (the display rule above would otherwise show it). */
+.copybtn[hidden] {
+  /* Not shown. */
+  display: none;
+} /* end of rule */
+
+/* The icon follows the text size, in every size setting. */
+.copybtn .copyicon {
+  /* Width. */
+  width: 0.9rem;
+  /* Height. */
+  height: 0.9rem;
+} /* end of rule */
+
+/* Pointing at it or reaching it with the keyboard: a filled outline. */
+.copybtn:hover, .copybtn:focus-visible {
+  /* A stronger outline. */
+  border-color: var(--text);
+} /* end of rule */
+
+/* A keyboard ring that does not depend on colour alone. */
+.copybtn:focus-visible {
+  /* The ring. */
+  outline: 3px solid var(--text);
+  /* A gap between button and ring. */
+  outline-offset: 2px;
+} /* end of rule */
+
+/* The hidden box used by the old way of copying: far outside the visible page. */
+.copybox {
+  /* Out of the flow. */
+  position: fixed;
+  /* Far above the page. */
+  top: -1000px;
+  /* Far to the left. */
+  left: -1000px;
+} /* end of rule */
+
 /* Text size Medium: the whole page is 81 percent of the browser's own text size; every size in this stylesheet is in rem, so everything follows. */
 html[data-size="medium"] {
   /* Percent of the browser's own size works in every browser and keeps the person's own browser setting as the base. */
diff --git a/web/copy.js b/web/copy.js
new file mode 100644
index 0000000..6715f90
--- /dev/null
+++ b/web/copy.js
@@ -0,0 +1,113 @@
+// Copy buttons: each button with class "copybtn" copies the text of the element named in its data-target attribute (a command shown on the page) to the clipboard, so the person can paste it into a terminal. The script sends nothing anywhere and runs nothing; it only copies text that is already on the page.
+(function () {
+  // Find every copy button on the page.
+  var buttons = document.querySelectorAll('button.copybtn[data-target]');
+  // Nothing to do on a page without copy buttons.
+  if (buttons.length === 0) {
+    // Stop here.
+    return;
+  }
+  // The invisible message that screen readers announce after a click.
+  var live = document.getElementById('copystatus');
+  // How long the button shows its answer ("Copied"), in milliseconds.
+  var SHOW_MS = 2000;
+  // Copy the old way: select the text in a hidden box and use the browser's copy command; this also works when the page is opened from another computer, where the newer clipboard function is not offered.
+  function oldWay(text) {
+    // A hidden text box that holds the text.
+    var box = document.createElement('textarea');
+    // Put the text in it.
+    box.value = text;
+    // The person cannot type into it.
+    box.setAttribute('readonly', '');
+    // The style sheet puts it outside the visible page (a script may not write inline styles under this page's security policy).
+    box.className = 'copybox';
+    // Add it to the page so that it can be selected.
+    document.body.appendChild(box);
+    // Select all of its text.
+    box.select();
+    // Whether the browser copied it.
+    var ok = false;
+    // Some browsers refuse the command with an error.
+    try {
+      // Ask the browser to copy the selected text.
+      ok = document.execCommand('copy');
+    } catch (e) {
+      // A refusal counts as a failure.
+      ok = false;
+    }
+    // Remove the box again.
+    document.body.removeChild(box);
+    // Tell the caller.
+    return ok;
+  }
+  // Copy a text; the answer is a promise that says true when the text was copied.
+  function copyText(text) {
+    // The newer way works only on pages that the browser treats as secure (this computer's own address counts).
+    if (navigator.clipboard && window.isSecureContext) {
+      // Try it, and fall back to the old way when the browser refuses.
+      return navigator.clipboard.writeText(text).then(function () {
+        // Copied.
+        return true;
+      }, function () {
+        // Refused: use the old way.
+        return oldWay(text);
+      });
+    }
+    // Otherwise use the old way straight away.
+    return Promise.resolve(oldWay(text));
+  }
+  // Set up one button.
+  function setUp(button) {
+    // The word inside the button.
+    var label = button.querySelector('.copylabel');
+    // The word it normally shows.
+    var normal = label ? label.textContent : '';
+    // The timer that puts the normal word back.
+    var timer = null;
+    // The buttons are hidden in the page itself, so that without this script there is no button that does nothing.
+    button.hidden = false;
+    // What happens on a click.
+    button.addEventListener('click', function () {
+      // The element that holds the command.
+      var source = document.getElementById(button.getAttribute('data-target'));
+      // A missing element means a mistake in the page; do nothing.
+      if (!source) {
+        // Stop here.
+        return;
+      }
+      // The command, without spaces at the ends.
+      var text = source.textContent.trim();
+      // Copy it.
+      copyText(text).then(function (ok) {
+        // Show the answer inside the button.
+        if (label) {
+          // Copied, or a short failure word.
+          label.textContent = ok ? 'Copied' : 'Copy failed';
+        }
+        // Tell screen readers.
+        if (live) {
+          // The sentence.
+          live.textContent = ok ? 'Command copied.' : 'Could not copy. Select the command and press Ctrl+C.';
+        }
+        // A second click starts the timer again.
+        if (timer) {
+          // Stop the old timer.
+          clearTimeout(timer);
+        }
+        // Put the normal word back after a moment.
+        timer = setTimeout(function () {
+          // The normal word.
+          if (label) {
+            // Restore it.
+            label.textContent = normal;
+          }
+        }, SHOW_MS);
+      });
+    });
+  }
+  // Set up every button.
+  for (var i = 0; i < buttons.length; i++) {
+    // One button.
+    setUp(buttons[i]);
+  }
+})();
diff --git a/web/delete.html b/web/delete.html
index 4555601..2839e52 100644
--- a/web/delete.html
+++ b/web/delete.html
@@ -144,12 +144,14 @@
 <table class="cmds">
 <thead><tr><th scope="col">Where Ollama runs</th><th scope="col">Command</th></tr></thead>
 <tbody>
-<tr><th scope="row">Directly on the computer</th><td><code>ollama pull {{.Model}}</code></td></tr>
-<tr><th scope="row">In Docker</th><td><code>docker exec &lt;container-name&gt; ollama pull {{.Model}}</code><br><span class="muted">find the name with: <code>docker ps</code></span></td></tr>
-<tr><th scope="row">In Kubernetes</th><td><code>kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull {{.Model}}</code><br><span class="muted">find the pod with: <code>kubectl get pods -n &lt;namespace&gt;</code></span></td></tr>
+<tr><th scope="row">Directly on the computer</th><td><code id="cmd-local">ollama pull {{.Model}}</code> <button type="button" class="copybtn" data-target="cmd-local" hidden aria-label="Copy command: directly on the computer"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button></td></tr>
+<tr><th scope="row">In Docker</th><td><code id="cmd-docker">docker exec &lt;container-name&gt; ollama pull {{.Model}}</code> <button type="button" class="copybtn" data-target="cmd-docker" hidden aria-label="Copy command: in Docker"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button><br><span class="muted">find the name with: <code id="cmd-docker-find">docker ps</code></span> <button type="button" class="copybtn" data-target="cmd-docker-find" hidden aria-label="Copy command: find the Docker container name"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button></td></tr>
+<tr><th scope="row">In Kubernetes</th><td><code id="cmd-k8s">kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull {{.Model}}</code> <button type="button" class="copybtn" data-target="cmd-k8s" hidden aria-label="Copy command: in Kubernetes"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button><br><span class="muted">find the pod with: <code id="cmd-k8s-find">kubectl get pods -n &lt;namespace&gt;</code></span> <button type="button" class="copybtn" data-target="cmd-k8s-find" hidden aria-label="Copy command: find the Kubernetes pod name"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button></td></tr>
 </tbody>
 </table>
-<p class="muted">The command must run where Ollama runs, because the model is stored there. The Kubernetes line has not been tested on a real cluster.</p>
+<p class="muted">The command must run where Ollama runs, because the model is stored there. The Kubernetes line has not been tested on a real cluster. The Copy button only copies the text; you paste it into the terminal yourself.</p>
+{{/* The announcement for screen readers after a copy. */}}
+<p id="copystatus" class="sr-only" role="status" aria-live="polite"></p>
 {{end}}
 {{/* What happens afterwards. */}}
 <p class="muted">When the download is finished, this model appears in the table again and the greyed row disappears.</p>
@@ -237,5 +239,7 @@
 </main>
 {{/* The ticking timer needs the monitor's own script; it is included only when there is a timer to tick. */}}
 {{if .Seconds}}<script src="/countdown.js" defer></script>{{end}}
+{{/* The script behind the copy buttons, only where there are commands. */}}
+{{if .ShowPull}}<script src="/copy.js" defer></script>{{end}}
 </body>{{/* end of the visible page. */}}
 </html>{{/* end of the page. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
51f76d0d3b862e9b0fa90298eb4b38e4490607c3c0dc9ed4f3d3feeba8b6ec46  delete.go
0259b31cf9ea1b97632fc0705bc0f6dde93e5a74bb85063321abeab4a1135bd2  web.go
0db0cd764c1b1886323dc5424131dd6cfddfd8ec93242df7bc640f455b29f9e0  web/delete.html
317ba046913cf6a87923eb3958274d40fdc9cbdcf9d4e2e790d484775bb43f8e  web/app.css
41a6e38ecdded26e9202699dc2d8f47b7f3facfd5e3c2d435784443638e22b56  copy.go
4be514e0e8ef368bf42398688e9e7d80dccbf87eb143982d5869f61fa033c2ab  copy_test.go
2b5102a42a1df174f825bb3cf918512775b9e5e04b0349cd98244ed5cd8629e3  web/copy.js
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
