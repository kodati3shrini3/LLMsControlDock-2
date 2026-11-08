#!/usr/bin/env bash
# Script 92d (Find LLM, change after slice 2): every version that fits gets Copy buttons for its install command, with the same Copy button, the same copy script and the same three ways to run it (directly, in Docker, in Kubernetes) as the restore page of a deleted model. Versions that do not fit get no button. The page only loads the copy script when there is a button. One new test.
# Run it from the project folder, on the branch feature/find-llm-page after scripts 92, 92b and 92c: cd ~/LLMsControlDock && bash scripts/92d-step55d-find-llm-copy-buttons.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of each file BEFORE the change (as left by script 92c) and AFTER it.
declare -A BEFORE AFTER
BEFORE["web/findllm.html"]="e7f5ee9c3c6d22ef96523e089c7d300958ba749adf118276a840fceee3530b7f"
BEFORE["web/app.css"]="c19a0530e09ff127eed0771559400bdcbba7d8f3b6e71a48b0d086893a2a8190"
BEFORE["findllm.go"]="ff6b6ba3d64bbae3a1bc2649fee62f7073830f8e2d0b117448741e2c3f0976f2"
BEFORE["findllm_test.go"]="660dfb42f56ffb2b8013aa3c7c2f3a68518f58f34546f7350f2352e1d290954c"
AFTER["web/findllm.html"]="52ecd375c90f9b27e833236d38bd97d020729e7caf00b832b656cf193eddbd49"
AFTER["web/app.css"]="e23f0d9ecae65643b81844ca611cc42b05ef8aef357ab41b9068ce086e5a89b5"
AFTER["findllm.go"]="ae5317b44fa1a291a66a6c30f5e2800a199e4b1073b9fd7222c993da4ffa3354"
AFTER["findllm_test.go"]="ebb5faa6a35d8e807fd490a46af4d31dfde32dd18911b12300ce6cc4f64d557b"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/find-llm-page"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Scripts 92 and 92c must have been applied: the page file exists and the button is in the panel.
[ -e findllm.go ] && grep -q 'panelactions' web/index.html || fail "scripts 92 to 92c must be applied first"
# Report it.
pass "scripts 92 to 92c are applied"

# Refuse to run twice: the copy script tag is in the page when this change was applied before.
if grep -q 'copy.js' web/findllm.html; then fail "web/findllm.html already has the copy buttons: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_92D_END'
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -68,7 +68,8 @@
 <h2>Models found</h2>
 {{if .Error}}<p class="warn" role="alert"><strong>&#9888;</strong> {{.Error}}</p>{{else}}
 <p class="muted" role="status">{{.Summary}}</p>
-{{range .Results}}
+{{/* The numbers $ri and $vi make every command on the page get its own name, so each Copy button finds its own command. */}}
+{{range $ri, $r := .Results}}
 <div class="findresult">
 <h3><a href="{{.URL}}" target="_blank" rel="noopener noreferrer">{{.Name}}<span class="sr-only"> (opens in a new window)</span></a></h3>
 <p>{{.Description}}</p>
@@ -76,7 +77,17 @@
 {{if .Unavailable}}<p class="warn">{{.Unavailable}}. Open the official page above for its versions.</p>{{else}}
 {{if eq .FitCount 0}}<p class="warn">None of its versions fit your choices. The versions are listed below with the reason.</p>{{end}}
 <ul class="findversions">
-{{range .Versions}}<li{{if not .Fits}} class="nofit"{{end}}>{{if .Fits}}<strong>Fits:</strong>{{else}}<strong>Does not fit:</strong>{{end}} <code>{{.Command}}</code> &middot; {{if .Size}}{{.Size}}{{else}}size not shown{{end}}{{if .Context}} &middot; {{.Context}} context{{end}}{{if .Input}} &middot; {{.Input}}{{end}}{{if .Reason}}<br><small>{{.Reason}}</small>{{end}}</li>
+{{range $vi, $v := .Versions}}<li{{if not .Fits}} class="nofit"{{end}}>{{if .Fits}}<strong>Fits:</strong> <code id="cmd-{{$ri}}-{{$vi}}-local">{{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-local" hidden aria-label="Copy command: directly on the computer"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button>{{else}}<strong>Does not fit:</strong> <code>{{.Command}}</code>{{end}} &middot; {{if .Size}}{{.Size}}{{else}}size not shown{{end}}{{if .Context}} &middot; {{.Context}} context{{end}}{{if .Input}} &middot; {{.Input}}{{end}}{{if .Reason}}<br><small>{{.Reason}}</small>{{end}}
+{{if .Fits}}
+{{/* The command depends on where Ollama runs; the monitor cannot know that, so Docker and Kubernetes are offered too, folded away until wanted. */}}
+<details class="othercmds"><summary>Docker or Kubernetes</summary>
+<table class="cmds"><tbody>
+<tr><th scope="row">In Docker</th><td><code id="cmd-{{$ri}}-{{$vi}}-docker">docker exec &lt;container-name&gt; {{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-docker" hidden aria-label="Copy command: in Docker"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button><br><span class="muted">find the name with: <code id="cmd-{{$ri}}-{{$vi}}-dockerfind">docker ps</code></span> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-dockerfind" hidden aria-label="Copy command: find the Docker container name"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button></td></tr>
+<tr><th scope="row">In Kubernetes</th><td><code id="cmd-{{$ri}}-{{$vi}}-k8s">kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- {{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-k8s" hidden aria-label="Copy command: in Kubernetes"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button><br><span class="muted">find the pod with: <code id="cmd-{{$ri}}-{{$vi}}-k8sfind">kubectl get pods -n &lt;namespace&gt;</code></span> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-k8sfind" hidden aria-label="Copy command: find the Kubernetes pod name"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button></td></tr>
+</tbody></table>
+</details>
+{{end}}
+</li>
 {{end}}
 </ul>
 {{if .More}}<p class="muted"><small>{{.More}} more versions are on the official page.</small></p>{{end}}
@@ -85,7 +96,13 @@
 {{end}}
 {{end}}
 {{end}}
+{{if .ShowCopy}}
+{{/* Copy buttons only copy text already on the page; the announcement for screen readers after a copy. */}}
+<p class="muted"><small>The command must run where Ollama runs, because the model is stored there. The Copy button only copies the text; you paste it into the terminal yourself. The Kubernetes line has not been tested on a real cluster.</small></p>
+<p id="copystatus" class="sr-only" role="status" aria-live="polite"></p>
+{{end}}
 </section>
 </main>
+{{if .ShowCopy}}<script src="/copy.js" defer></script>{{end}}
 </body>
 </html>
--- a/web/app.css
+++ b/web/app.css
@@ -2590,3 +2590,17 @@
   /* The secondary colour. */
   color: var(--muted);
 } /* end of rule */
+
+/* The folded-away Docker and Kubernetes commands under a version that fits. */
+.othercmds {
+  /* A little room above. */
+  margin-top: 0.3rem;
+} /* end of rule */
+
+/* The words that open and close the fold are small and look clickable. */
+.othercmds summary {
+  /* A hand cursor. */
+  cursor: pointer;
+  /* Smaller than the text beside it. */
+  font-size: 0.9rem;
+} /* end of rule */
--- a/findllm.go
+++ b/findllm.go
@@ -606,6 +606,8 @@
 	Results []resultView
 	// Summary is the sentence above the results: how many models match, which are shown, when the list was read, and what was left out.
 	Summary string
+	// ShowCopy is true when at least one version fits, so the page carries Copy buttons and the monitor's own copy script.
+	ShowCopy bool
 } // end of findPage
 
 // findTick is one tick box.
@@ -701,6 +703,17 @@
 			// Say so.
 			data.GPU = "Not found by the graphics tool; models would run on the processor"
 		} // end of the graphics note
+		// Copy buttons are offered only next to versions that fit.
+		for _, res := range data.Results {
+			// Look at each version.
+			for _, v := range res.Versions {
+				// One that fits is enough.
+				if v.Fits {
+					// Show the buttons.
+					data.ShowCopy = true
+				} // end of the fit check
+			} // end of the version loop
+		} // end of the model loop
 		// Build the page in memory first, so a template error gives a clean 500.
 		var buf bytes.Buffer
 		// Fill the template.
@@ -712,6 +725,11 @@
 			// Stop.
 			return
 		} // end of the template check
+		// A page with Copy buttons may run the monitor's own script file, and nothing else.
+		if data.ShowCopy {
+			// Replace the strict policy by the one that allows the script file.
+			w.Header().Set("Content-Security-Policy", contentSecurityPolicyWithScript)
+		} // end of the script policy
 		// Tell the browser this is an HTML page.
 		w.Header().Set("Content-Type", "text/html; charset=utf-8")
 		// The status.
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -1,7 +1,8 @@
 // Package main tells Go that this test file belongs to the same program as findllm.go.
 package main
 
-import ( // import lists the standard-library packages this test file uses.
+import (
+	"regexp" // import lists the standard-library packages this test file uses.
 	// io reads a reply body.
 	"io"
 	// net/http gives the status codes.
@@ -511,3 +512,72 @@
 		} // end of the phrase loop
 	} // end of the case loop
 } // end of TestFindSummaryWording
+
+// TestFindResultsHaveCopyButtons checks that a version that fits has Copy buttons for its three commands, that a version that does not fit has none, and that the script policy is only on when there is a button.
+func TestFindResultsHaveCopyButtons(t *testing.T) {
+	// Start with an empty saved list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// A fake library.
+	fakeSite(t, findTestPages())
+	// The rig.
+	rig := newThemeRig(t)
+	// A search where one version fits and one does not.
+	res := post(t, rig.h, "/findllm/search", url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"2"}, "mem_gb": {"8"}}, fromThisPage)
+	// Close the body at the end.
+	defer res.Body.Close()
+	// Read it.
+	raw, err := io.ReadAll(res.Body)
+	// A failure means the test is broken.
+	if err != nil {
+		// Stop.
+		t.Fatalf("read body: %v", err)
+	} // end of the read check
+	// The page text.
+	body := string(raw)
+	// Every button names a command that is on the page, and the five of the fitting version are there.
+	buttons := regexp.MustCompile(`<button type="button" class="copybtn" data-target="([a-z0-9-]+)" hidden aria-label="Copy command: [^"]+">`).FindAllStringSubmatch(body, -1)
+	// Five commands: local, Docker, Docker name, Kubernetes, Kubernetes pod.
+	if len(buttons) != 5 {
+		// Stop.
+		t.Fatalf("%d copy buttons, want 5", len(buttons))
+	} // end of the count check
+	// Each target exists exactly once as a command.
+	for _, b := range buttons {
+		// The command element.
+		if strings.Count(body, `<code id="`+b[1]+`">`) != 1 {
+			// Report.
+			t.Errorf("button %q has no single command to copy", b[1])
+		} // end of the target check
+	} // end of the loop
+	// The three ways of running the pull, for the version that fits.
+	for _, want := range []string{">ollama pull alpha:0.6b</code>", ">docker exec &lt;container-name&gt; ollama pull alpha:0.6b</code>", ">kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull alpha:0.6b</code>"} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report.
+			t.Errorf("the results lack %q", want)
+		} // end of the look
+	} // end of the loop
+	// The script once, the status line for screen readers, and a policy that allows this address's scripts only.
+	if strings.Count(body, `<script src="/copy.js" defer></script>`) != 1 || strings.Count(body, "<script") != 1 || !strings.Contains(body, `id="copystatus"`) {
+		// Report.
+		t.Errorf("script or status line missing")
+	} // end of the script check
+	// The policy.
+	if csp := res.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe-inline") || strings.Contains(csp, "unsafe-eval") {
+		// Report.
+		t.Errorf("policy %q", csp)
+	} // end of the policy check
+	// A search where nothing fits (no disk space at all) has no button, no script and the strict policy.
+	res2 := post(t, rig.h, "/findllm/search", url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"0.1"}, "mem_gb": {"0.1"}}, fromThisPage)
+	// Close it at the end.
+	defer res2.Body.Close()
+	// Read it.
+	raw2, _ := io.ReadAll(res2.Body)
+	// Nothing to copy.
+	if strings.Contains(string(raw2), "copybtn") || strings.Contains(string(raw2), "<script") || strings.Contains(res2.Header.Get("Content-Security-Policy"), "script-src") {
+		// Report.
+		t.Errorf("a page without a fitting version must carry no copy button, no script and the strict policy")
+	} // end of the check
+} // end of TestFindResultsHaveCopyButtons
OCC_PATCH_92D_END
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
echo "NEXT  start bin/LLMsControlDock, press Find LLM and look at the Copy buttons (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
