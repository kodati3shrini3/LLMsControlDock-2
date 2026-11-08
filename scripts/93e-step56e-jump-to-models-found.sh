#!/usr/bin/env bash
# Script 93e (Find LLM, change after slice 3): after Find LLM is pressed on the Find LLM page, the browser jumps straight to the answer: the Models found heading, or the box that lists what to correct. The form now sends to /findllm/search#found and the heading (or the problem box) carries the id found. No wording changes. One new test, and two older tests now look for the heading with its id.
# Run it from the project folder, on the branch feature/find-llm-tags after script 93d: cd ~/LLMsControlDock && bash scripts/93e-step56e-jump-to-models-found.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 93d), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["web/findllm.html"]="98aea299b888a44b53dc72c5b4d09e3fa89f3c76949a7a312bf5b6945cc9a6ee"
BEFORE["findllm_test.go"]="c84ead807c8928155bf56da3413f24144dfd055697d32fa9552c49fed3999b59"
AFTER["web/findllm.html"]="591f5413a391a06e195ab255751ea3a7793081b119db07f91b2f4e9a8fecb2fd"
AFTER["findllm_test.go"]="bba01d9deaea0071f5f5a9ee348b6258597246a2131a01d4adb7aae4267e71ca"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/find-llm-tags"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 93d must have been applied: the restore icon rule exists.
grep -q 'ghostrow .iconstack' web/app.css || fail "script 93d must be applied first"
# Report it.
pass "script 93d (restore icon aligned) is applied"

# Refuse to run twice: the form address with the jump mark exists when this change was applied before.
if grep -q 'findllm/search#found' web/findllm.html; then fail "web/findllm.html already has the jump mark: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_93E_END'
diff --git a/findllm_test.go b/findllm_test.go
index 793228a..11f07d8 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -396,7 +396,7 @@ func TestFindPageShowsTheChoicesAndAsksNothing(t *testing.T) {
 		} // end of the look
 	} // end of the loop
 	// No results block, and no request to the library.
-	if strings.Contains(body, "<h2>Models found</h2>") || atomic.LoadInt32(hits) != 0 {
+	if strings.Contains(body, ">Models found</h2>") || atomic.LoadInt32(hits) != 0 {
 		// Report.
 		t.Errorf("results shown or library asked before the button (hits=%d)", atomic.LoadInt32(hits))
 	} // end of the check
@@ -422,7 +422,7 @@ func TestFindSearchShowsFitAndNoFit(t *testing.T) {
 		t.Fatalf("status %d: %s", status, body)
 	} // end of the status check
 	// The model, its official link, the small version that fits with its command, and the large one with the reason.
-	for _, want := range []string{"<h2>Models found</h2>", ollamaSite + "/library/alpha", "ollama pull alpha:0.6b", "<strong>Fits:</strong>", "<strong>Does not fit:</strong>", "needs 5.2 GB of disk space; you have 2.0 GB free", "1 model matches your choices", "1 cloud model (it runs on Ollama"} {
+	for _, want := range []string{`<h2 id="found">Models found</h2>`, ollamaSite + "/library/alpha", "ollama pull alpha:0.6b", "<strong>Fits:</strong>", "<strong>Does not fit:</strong>", "needs 5.2 GB of disk space; you have 2.0 GB free", "1 model matches your choices", "1 cloud model (it runs on Ollama"} {
 		// Look for it.
 		if !strings.Contains(body, want) {
 			// Report.
@@ -958,3 +958,43 @@ func TestIconColours(t *testing.T) {
 		} // end of the value loop
 	} // end of the colour loop
 } // end of TestIconColours
+
+// TestFindSearchJumpsToTheAnswer checks that after the button is pressed the browser scrolls to the answer: the form sends to the address with #found, and the answer page (the models found, or the list of problems) has exactly one element with that id.
+func TestFindSearchJumpsToTheAnswer(t *testing.T) {
+	// The saved library list goes to a throw-away folder, never to the real data folder.
+	isolateFindData(t)
+	// Start with an empty saved list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// A fake library.
+	fakeSite(t, findTestPages())
+	// The rig.
+	rig := newThemeRig(t)
+	// The empty form page.
+	_, _, form := get(t, rig.h, http.MethodGet, "/findllm")
+	// The form must send to the address with the jump mark.
+	if !strings.Contains(form, `action="/findllm/search#found"`) {
+		// Report.
+		t.Error("the form does not send to /findllm/search#found")
+	} // end of the form check
+	// No answer yet, so nothing to jump to.
+	if strings.Count(form, `id="found"`) != 0 {
+		// Report.
+		t.Error("the empty form page already has the jump target")
+	} // end of the empty page check
+	// A search that works: the heading Models found is the target.
+	_, ok := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"2"}, "mem_gb": {"8"}})
+	// Exactly one target, and it is the heading.
+	if strings.Count(ok, `id="found"`) != 1 || !strings.Contains(ok, `<h2 id="found">Models found</h2>`) {
+		// Report.
+		t.Error("the answer page has no single jump target on the Models found heading")
+	} // end of the answer check
+	// A search with a bad number: the problem box is the target.
+	_, bad := postFind(t, rig, url.Values{"token": {rig.token}, "disk_gb": {"lots"}})
+	// Exactly one target, and it is the problem box.
+	if strings.Count(bad, `id="found"`) != 1 || !strings.Contains(bad, `<div class="warn" id="found" role="alert">`) {
+		// Report.
+		t.Error("the problem page has no single jump target on the problem box")
+	} // end of the problem check
+} // end of TestFindSearchJumpsToTheAnswer
diff --git a/web/findllm.html b/web/findllm.html
index 83c1f3b..3677579 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -23,9 +23,9 @@
 <p>Tick what the model must do and press <strong>Find LLM</strong>. Only models of the official Ollama library are listed, and each comes with the command that installs it. This page installs nothing.</p>
 <p class="muted">Pressing the button reads the public list at ollama.com/library and, for the first ten models, their version lists. Your choices are not sent: the list is filtered on this computer.</p>
 {{/* Problems with what was typed; nothing was searched. */}}
-{{if .Problems}}<div class="warn" role="alert"><p><strong>&#9888; Not searched.</strong> Please correct:</p><ul>{{range .Problems}}<li>{{.}}</li>{{end}}</ul></div>{{end}}
+{{if .Problems}}<div class="warn" id="found" role="alert"><p><strong>&#9888; Not searched.</strong> Please correct:</p><ul>{{range .Problems}}<li>{{.}}</li>{{end}}</ul></div>{{end}}
 {{/* The form: it sends the page token and the choices. */}}
-<form method="post" action="/findllm/search">
+<form method="post" action="/findllm/search#found">
 {{/* The page token proves the form comes from this monitor. */}}
 <input type="hidden" name="token" value="{{.Token}}">
 {{/* The required facts about this computer, highlighted. */}}
@@ -65,7 +65,7 @@
 </form>
 {{/* The results appear only after the button was pressed. */}}
 {{if .Searched}}
-<h2>Models found</h2>
+<h2 id="found">Models found</h2>
 {{if .Error}}<p class="warn" role="alert"><strong>&#9888;</strong> {{.Error}}</p>{{else}}
 {{if .CopyNote}}<p class="warn" role="alert"><strong>&#9888;</strong> {{.CopyNote}}</p>{{end}}
 <p class="muted" role="status">{{.Summary}}</p>
OCC_PATCH_93E_END
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
echo "NEXT  start bin/LLMsControlDock and press Find LLM and check that the page jumps to Models found (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
