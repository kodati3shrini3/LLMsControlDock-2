#!/usr/bin/env bash
# Script 125 (warning symbol for a model that needs a newer Ollama): a model that fits the disk and memory but needs a newer Ollama than the running one (script 124 shows the sentence) no longer shows the green check mark and "Fits:". It shows a red warning triangle instead of the check mark, "Fits, after you update Ollama:" instead of "Fits:" on each version that fits, and "fits (update Ollama first)" in the size table, so the page does not contradict its own warning. Models without such a sentence are unchanged. Program change, version 0.34.0 (same branch as 122, 123 and 124).
# Run it on the branch of scripts 122 to 124 (never main): cd ~/LLMsControlDock-2 && git switch feature/docker-it-flag && bash scripts/125-step87-warning-symbol-for-old-ollama.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the four files BEFORE the change (as after script 124) and AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm.go"]="9db951a39fc073f5d933143af0722b709e2fc08819479e0efb1cdb8dfa57962d"
BEFORE["findlabels_test.go"]="0990db1e496eb830333857f35f0cdc3824e48b5df44bf1aee314679f24e904d5"
BEFORE["web/app.css"]="23d882f1ab862ee0eb3664d18be15aab414b73922aeb2f66cb49875ceb4462bb"
BEFORE["web/findllm.html"]="d831bedc552200f464b078847ba1b680fd8f436a083e8e25cf82af4eb9cbc8a3"
AFTER["findllm.go"]="8398a24fe9af421689e4a7fce0e7dedce415ac0fee876407f6df6f8689b4d296"
AFTER["findlabels_test.go"]="ada3e1c67711d9f4bb5f4cffadb346610b6ff1c3c84ce506764a0453ee1c2d63"
AFTER["web/app.css"]="7686d68b38e797bf2f37d3f5fce5e76c5f29dee9f0bfc69bb3e7caedb4d604a9"
AFTER["web/findllm.html"]="d728d77623479592b86ecd40ab6c042eed432b84497ad5391c3af5809054e503"

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
[ "$BRANCH" != "main" ] || fail "you are on main; switch to the branch of scripts 122 to 124: git switch feature/docker-it-flag"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 124 must be in.
grep -q 'func sizeRows' findllm.go && grep -q 'func applyOllamaNeed' findllm.go || fail "script 124 is not in this branch; run it first"
# Report it.
pass "script 124 is in"

# Refuse to run twice.
if grep -q 'tipModelOld' findllm.go; then fail "findllm.go already has tipModelOld: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# Every file must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the file is not the expected version.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} files are the expected versions before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_125_END'
diff --git a/findlabels_test.go b/findlabels_test.go
index 60e5a59..c8a1575 100644
--- a/findlabels_test.go
+++ b/findlabels_test.go
@@ -473,6 +473,10 @@ func TestFindSearchShowsReasonsVersionFlagAndSizeTable(t *testing.T) {
 		"Needs Ollama 0.30.0 or newer (the model page says so); yours (0.34.4) is new enough.",
 		// The size table, with the rows in size order.
 		"Compare sizes (2 versions)",
+		// The model that needs a newer Ollama gets the warning symbol and the changed wording, in the list and in the size table.
+		"stateicon state-warn", "Fits, after you update Ollama:", "fits (update Ollama first)",
+		// The other model keeps the normal wording and the check mark.
+		"<strong>Fits:</strong>", "stateicon state-fits",
 	} {
 		// Look for it.
 		if !strings.Contains(text, want) {
@@ -480,6 +484,11 @@ func TestFindSearchShowsReasonsVersionFlagAndSizeTable(t *testing.T) {
 			t.Errorf("the results lack %q", want)
 		} // end of the look
 	} // end of the loop
+	// The warning wording is only on the model that needs a newer Ollama: its listed versions (1b, 8b and latest give up to three) all carry it, and the normal model has none.
+	if n := strings.Count(text, "Fits, after you update Ollama:"); n < 1 || n > 3 {
+		// Report.
+		t.Errorf("the warning wording appears %d times, want 1 to 3", n)
+	} // end of the warning count
 	// The update help is shown once: only the model that needs a newer Ollama has it.
 	if n := strings.Count(text, "How to update Ollama"); n != 1 {
 		// Report.
diff --git a/findllm.go b/findllm.go
index c94bbb2..6c4d13a 100644
--- a/findllm.go
+++ b/findllm.go
@@ -56,11 +56,15 @@ const (
 	tipModelNoFit = "No version of this model can be installed here with your choices; the reasons are written under each version."
 	// tipVersionFits is for a version that fits.
 	tipVersionFits = "This version can be installed here: it fits your free disk space, memory and choices."
+	// tipModelOld is for a model that fits the disk and memory but needs a newer Ollama than the running one.
+	tipModelOld = "This model fits your disk and memory, but it needs a newer Ollama than yours. Update Ollama first (see the warning under the name); until then downloading it fails."
+	// tipVersionOld is the same for one version.
+	tipVersionOld = "This version fits your disk, memory and choices, but it needs a newer Ollama than yours. Update Ollama first."
 	// tipVersionNoFit is for a version that does not fit.
 	tipVersionNoFit = "This version cannot be installed here with your choices; the reason is written under it."
 )
 
-// iconView is a state icon with its tooltip: Kind is fits, nofit or cloud (empty means no icon), Label is the hidden name for screen readers, ID names the tooltip, Text is the tooltip.
+// iconView is a state icon with its tooltip: Kind is fits, nofit, warn or cloud (empty means no icon), Label is the hidden name for screen readers, ID names the tooltip, Text is the tooltip.
 type iconView struct {
 	// Kind picks the drawing and the colour.
 	Kind string
@@ -745,6 +749,8 @@ type versionView struct {
 	Age string
 	// ageHours and sizeBytes order the versions: newest first, then the smaller one first.
 	ageHours, sizeBytes int64
+	// NeedsUpdate is true when the version fits this computer but the model needs a newer Ollama than the running one.
+	NeedsUpdate bool
 	// Icon is the can-be-installed or cannot-be-installed symbol with its tooltip.
 	Icon iconView
 } // end of versionView
@@ -1076,6 +1082,16 @@ func applyOllamaNeed(r *resultView, need string, run checkResult) {
 		r.OllamaState = "old"
 		// The sentence.
 		r.OllamaNote = "Needs Ollama " + need + " or newer (the model page on ollama.com says so). Your Ollama is " + run.Version + ", so downloading it would fail with \"requires a newer version of Ollama\". Update Ollama first."
+		// The versions that fit the computer cannot be installed until Ollama is updated.
+		for i := range r.Versions {
+			// Only a version that fits is affected.
+			r.Versions[i].NeedsUpdate = r.Versions[i].Fits
+		} // end of the version loop
+		// The same in the size table.
+		for i := range r.SizeRows {
+			// Only a row that fits is affected.
+			r.SizeRows[i].NeedsUpdate = r.SizeRows[i].Fits
+		} // end of the row loop
 	// New enough.
 	default:
 		// Fine.
@@ -1432,10 +1448,20 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 		for ri := range data.Results {
 			// The model's icon.
 			data.Results[ri].Icon = modelIcon(data.Results[ri].State, fmt.Sprintf("tipstate-%d", ri))
+			// A model that fits but needs a newer Ollama gets the warning symbol instead of the check mark.
+			if data.Results[ri].State == "fits" && data.Results[ri].OllamaState == "old" {
+				// The triangle.
+				data.Results[ri].Icon = iconView{Kind: "warn", Label: "Needs a newer Ollama", ID: fmt.Sprintf("tipstate-%d", ri), Text: tipModelOld}
+			} // end of the model warning
 			// Each version's icon.
 			for vi := range data.Results[ri].Versions {
 				// One version.
 				data.Results[ri].Versions[vi].Icon = versionIcon(data.Results[ri].Versions[vi].Fits, fmt.Sprintf("tipver-%d-%d", ri, vi))
+				// A version that fits but needs a newer Ollama gets the warning symbol too.
+				if data.Results[ri].Versions[vi].NeedsUpdate {
+					// The triangle.
+					data.Results[ri].Versions[vi].Icon = iconView{Kind: "warn", Label: "Needs a newer Ollama", ID: fmt.Sprintf("tipver-%d-%d", ri, vi), Text: tipVersionOld}
+				} // end of the version warning
 			} // end of the version loop
 		} // end of the model loop
 		// The cloud section's icons.
diff --git a/web/app.css b/web/app.css
index ed724c1..6b15a43 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2787,6 +2787,12 @@ html[data-size="medium"] svg[width="22"] {
   color: var(--bad);
 } /* end of rule */
 
+/* Needs a newer Ollama: the same red as the warning line, drawn as a triangle. */
+.state-warn {
+  /* The problem colour, as the warning bar above the versions. */
+  color: var(--bad);
+} /* end of rule */
+
 /* A cloud model: soft blue. */
 .state-cloud {
   /* The cloud colour. */
diff --git a/web/findllm.html b/web/findllm.html
index 242d71a..6ae1ad9 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -128,7 +128,7 @@
 {{if .Unavailable}}<p class="warn">{{.Unavailable}}. Open the official page above for its versions.</p>{{else}}
 {{if eq .FitCount 0}}<p class="warn">None of its versions fit your choices. The versions are listed below with the reason.</p>{{end}}
 <ul class="findversions">
-{{range $vi, $v := .Versions}}<li{{if not .Fits}} class="nofit"{{end}}>{{template "stateicon" .Icon}} {{if .Fits}}<strong>Fits:</strong> <code id="cmd-{{$ri}}-{{$vi}}-local">{{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-local" hidden aria-label="Copy command: directly on the computer"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button>{{else}}<strong>Does not fit:</strong> <code>{{.Command}}</code>{{end}} &middot; {{if .Size}}{{.Size}}{{else}}size not shown{{end}}{{if .Context}} &middot; {{.Context}} context{{end}}{{if .Age}} &middot; updated {{.Age}}{{end}}{{if .Input}} &middot; {{.Input}}{{end}}{{if .Installed}} &middot; <span class="installedmark">{{.Note}}</span>{{end}}{{if .Reason}}<br><small>{{.Reason}}</small>{{end}}
+{{range $vi, $v := .Versions}}<li{{if not .Fits}} class="nofit"{{end}}>{{template "stateicon" .Icon}} {{if .Fits}}<strong>{{if .NeedsUpdate}}Fits, after you update Ollama:{{else}}Fits:{{end}}</strong> <code id="cmd-{{$ri}}-{{$vi}}-local">{{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-local" hidden aria-label="Copy command: directly on the computer"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button>{{else}}<strong>Does not fit:</strong> <code>{{.Command}}</code>{{end}} &middot; {{if .Size}}{{.Size}}{{else}}size not shown{{end}}{{if .Context}} &middot; {{.Context}} context{{end}}{{if .Age}} &middot; updated {{.Age}}{{end}}{{if .Input}} &middot; {{.Input}}{{end}}{{if .Installed}} &middot; <span class="installedmark">{{.Note}}</span>{{end}}{{if .Reason}}<br><small>{{.Reason}}</small>{{end}}
 {{if .Fits}}
 {{/* The command depends on where Ollama runs; the monitor cannot know that, so Docker and Kubernetes are offered too, folded away until wanted. */}}
 <details class="othercmds"><summary>Docker or Kubernetes</summary>
@@ -145,7 +145,7 @@
 {{/* A simple comparison of the plain size versions, smallest download first. */}}
 {{if .SizeRows}}<details class="othercmds"><summary>Compare sizes ({{len .SizeRows}} versions)</summary>
 <table class="cmds"><thead><tr><th scope="col">Version</th><th scope="col">Download</th><th scope="col">Context</th><th scope="col">On this computer</th></tr></thead><tbody>
-{{range .SizeRows}}<tr><td><code>{{.Tag}}</code>{{if .Installed}} <strong>Installed</strong>{{end}}</td><td>{{if .Size}}{{.Size}}{{else}}not shown{{end}}</td><td>{{if .Context}}{{.Context}}{{else}}not shown{{end}}</td><td>{{if .Fits}}fits{{else}}{{.Reason}}{{end}}</td></tr>
+{{range .SizeRows}}<tr><td><code>{{.Tag}}</code>{{if .Installed}} <strong>Installed</strong>{{end}}</td><td>{{if .Size}}{{.Size}}{{else}}not shown{{end}}</td><td>{{if .Context}}{{.Context}}{{else}}not shown{{end}}</td><td>{{if .Fits}}fits{{if .NeedsUpdate}} (update Ollama first){{end}}{{else}}{{.Reason}}{{end}}</td></tr>
 {{end}}</tbody></table></details>{{end}}
 {{end}}
 </div>
@@ -182,4 +182,4 @@
 </body>
 </html>
 {{/* A state icon with its tooltip: the check mark (can be installed), the cross (cannot be installed) or the cloud (runs on Ollama's servers). The words next to it say the same, so the symbol is never the only signal. */}}
-{{define "stateicon"}}{{if .Kind}}<span class="tipbox"><span class="stateicon state-{{.Kind}}" tabindex="0" role="img" aria-label="{{.Label}}" aria-describedby="{{.ID}}"><svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{{if eq .Kind "fits"}}<circle cx="12" cy="12" r="9"/><path d="M8 12.5l2.7 2.7L16 9.5"/>{{else if eq .Kind "nofit"}}<circle cx="12" cy="12" r="9"/><path d="M9 9l6 6"/><path d="M15 9l-6 6"/>{{else}}<path d="M7 18h10a4 4 0 0 0 .6-7.95A5.5 5.5 0 0 0 7.1 9.2 4.4 4.4 0 0 0 7 18z"/>{{end}}</svg></span><span class="tip tip-icon" role="tooltip" id="{{.ID}}">{{.Text}}</span></span>{{end}}{{end}}
+{{define "stateicon"}}{{if .Kind}}<span class="tipbox"><span class="stateicon state-{{.Kind}}" tabindex="0" role="img" aria-label="{{.Label}}" aria-describedby="{{.ID}}"><svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{{if eq .Kind "fits"}}<circle cx="12" cy="12" r="9"/><path d="M8 12.5l2.7 2.7L16 9.5"/>{{else if eq .Kind "nofit"}}<circle cx="12" cy="12" r="9"/><path d="M9 9l6 6"/><path d="M15 9l-6 6"/>{{else if eq .Kind "warn"}}<path d="M12 4l9 16H3z"/><path d="M12 10v4"/><path d="M12 17v.01"/>{{else}}<path d="M7 18h10a4 4 0 0 0 .6-7.95A5.5 5.5 0 0 0 7.1 9.2 4.4 4.4 0 0 0 7 18z"/>{{end}}</svg></span><span class="tip tip-icon" role="tooltip" id="{{.ID}}">{{.Text}}</span></span>{{end}}{{end}}
OCC_PATCH_125_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} changed files have the expected sha256"

# The key lines must be in the program, the page and the style sheet.
grep -q 'tipVersionOld' findllm.go && grep -q 'Fits, after you update Ollama' web/findllm.html && grep -q '^.state-warn' web/app.css || fail "a key line of the change is missing"
# Report it.
pass "warning symbol, new wording and style are in place"

# gofmt lists files whose layout differs from the standard.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code (and compiles the tests).
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once; the delete-confirm test failed once without a known cause, so a single failure of exactly that test is reported and not hidden.
go test -count=1 ./... || fail "go test failed (if only TestDeleteConfirmRefusesLoadedModel failed, tell Claude)"
# Report it.
pass "go test: all tests pass"

# Build the program for all six systems.
for TARGET in linux/amd64 linux/arm64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Build to nowhere (/dev/null) just to see that it compiles.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -o /dev/null . || fail "build for $TARGET failed"
  # Report it.
  pass "program builds for $TARGET"
# End of the loop over the systems.
done

# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  try the page by hand (instructions follow in the chat), then commit and push everything."
# Show what changed in the project folder.
git status --short
