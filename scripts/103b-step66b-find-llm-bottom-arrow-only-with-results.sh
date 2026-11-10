#!/usr/bin/env bash
# Script 103b (Find LLM page, back arrows): the back arrow at the bottom of the page is shown only when models are listed; before a search, and when no model matches, only the arrow in the button row (and the one at the top) is shown, so two arrows no longer sit one above the other. The arrow tests follow.
# Run it from the project folder, on the branch feature/find-llm-green-arrows-kept-results (after script 103): cd ~/LLMsControlDock && bash scripts/103b-step66b-find-llm-bottom-arrow-only-with-results.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 103), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm_test.go"]="ee433ac3b76d9403adc166ab57d1738d753ef50004ab34cfc435d873b08d4220"
BEFORE["web/findllm.html"]="ec4a7a6414df1f403e01b274ef448a0871654c4f145c90f39457fa9ef41bc127"
AFTER["findllm_test.go"]="593d60fd57ae4fca0de6bf229af973090e175730cfde0311ffa7d7ba15271c43"
AFTER["web/findllm.html"]="1120893ee9823c48f259f06288f88849c60059a758b9268a5957a4ecec16fe83"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/find-llm-green-arrows-kept-results"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 103 must have been applied: the bottom arrow exists.
grep -q 'class="backbottom"' web/findllm.html || fail "script 103 must be applied first"
# Report it.
pass "script 103 is applied"

# Refuse to run twice: the new comment exists when this change was applied before.
if grep -q 'only when models are listed' web/findllm.html; then fail "web/findllm.html already has the new rule: this script was already applied"; fi
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
diff --git a/findllm_test.go b/findllm_test.go
index 815efb1..d1c80c7 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -1954,26 +1954,38 @@ func TestFindPageHeadingsButtonAndArrows(t *testing.T) {
 		// Report.
 		t.Error("the Find LLM button does not use the green button classes")
 	} // end of the button check
-	// Three back arrows: top, button row, bottom.
-	if n := strings.Count(form, `aria-label="Back to the monitor"`); n != 3 {
+	// Before any search there is nothing to scroll past: two back arrows (top and button row), no bottom one.
+	if n := strings.Count(form, `aria-label="Back to the monitor"`); n != 2 || strings.Contains(form, `class="backbottom"`) {
 		// Report.
-		t.Errorf("%d back arrows, want 3", n)
-	} // end of the count check
+		t.Errorf("the empty page has %d back arrows or a bottom arrow, want 2 and none", n)
+	} // end of the empty-page check
 	// Their bubbles have different ids.
-	for _, id := range []string{`id="tipback"`, `id="tipback-row"`, `id="tipback-bottom"`} {
+	for _, id := range []string{`id="tipback"`, `id="tipback-row"`} {
 		// Look for it.
 		if !strings.Contains(form, id) {
 			// Report.
 			t.Errorf("the page lacks %s", id)
 		} // end of the look
 	} // end of the loop
-	// The row arrow is inside the button row, after the order choice; the bottom one is after the last block of the page.
-	row := strings.Index(form, `<p class="findaction">`)
-	// Where the row arrow is, and where the bottom arrow is.
-	rowArrow, bottom := strings.Index(form, `id="tipback-row"`), strings.Index(form, `<p class="backbottom">`)
+	// The row arrow is inside the button row, after the order choice.
+	row, rowArrow := strings.Index(form, `<p class="findaction">`), strings.Index(form, `id="tipback-row"`)
 	// Order.
-	if row < 0 || rowArrow < row || bottom < rowArrow {
+	if row < 0 || rowArrow < row {
 		// Report.
-		t.Errorf("the arrows are in the wrong places (row %d, row arrow %d, bottom %d)", row, rowArrow, bottom)
+		t.Errorf("the row arrow is in the wrong place (row %d, row arrow %d)", row, rowArrow)
 	} // end of the order check
+	// A search that lists models: the third arrow appears at the bottom, after the row arrow.
+	_, listed := postFind(t, rig, url.Values{"token": {rig.token}, "disk_gb": {"100"}, "mem_gb": {"64"}})
+	// Three arrows, the bottom one last.
+	if n := strings.Count(listed, `aria-label="Back to the monitor"`); n != 3 || strings.Index(listed, `id="tipback-bottom"`) < strings.Index(listed, `id="tipback-row"`) {
+		// Report.
+		t.Errorf("the page with results has %d back arrows, want 3 with the bottom one last", n)
+	} // end of the listed check
+	// A search that lists nothing: only two arrows, no bottom one.
+	_, empty := postFind(t, rig, url.Values{"token": {rig.token}, "ab_embedding": {"on"}, "ab_tools": {"on"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
+	// Nothing found, and no bottom arrow.
+	if !strings.Contains(empty, "No model matches") || strings.Contains(empty, `class="backbottom"`) || strings.Count(empty, `aria-label="Back to the monitor"`) != 2 {
+		// Report.
+		t.Errorf("the page with no match is wrong: has the words %v, %d arrows", strings.Contains(empty, "No model matches"), strings.Count(empty, `aria-label="Back to the monitor"`))
+	} // end of the empty-result check
 } // end of TestFindPageHeadingsButtonAndArrows
diff --git a/web/findllm.html b/web/findllm.html
index dec5460..c161c2d 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -154,8 +154,10 @@
 <p class="muted"><small>The command must run where Ollama runs, because the model is stored there. The Copy button only copies the text; you paste it into the terminal yourself. The Kubernetes line has not been tested on a real cluster.</small></p>
 <p id="copystatus" class="sr-only" role="status" aria-live="polite"></p>
 {{end}}
-{{/* The back arrow again at the bottom of the page. */}}
+{{/* The back arrow again at the bottom of the page, only when models are listed (a long page); with nothing listed the arrow in the button row is enough. */}}
+{{if or .Results .CloudResults}}
 <p class="backbottom"><span class="tipbox backhere"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback-bottom"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback-bottom">Back to the monitor</span></span></p>
+{{end}}
 </section>
 </main>
 {{if .ShowCopy}}<script src="/copy.js" defer></script>{{end}}
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
echo "NEXT  start bin/LLMsControlDock and look at Find LLM before and after a search (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
