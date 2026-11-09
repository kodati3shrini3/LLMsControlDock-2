#!/usr/bin/env bash
# Script 100c (Find LLM, Sort by): the help bubble of Sort by is removed, because it did not work; Sort by is now plain text beside its list. The list, the order and everything else stay as they were. One test line follows.
# Run it from the project folder, on the branch feature/find-llm-installed-speed (after script 100b): cd ~/LLMsControlDock && bash scripts/100c-step63c-find-llm-sort-by-no-bubble.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 100b), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm_test.go"]="90cc880e600539e4932166550ebc8ee5c76a679bb3f4d4aab30c380faf20400a"
BEFORE["web/app.css"]="006f2882f83c1d34a3b01c533f42fa95711fb669502e8fca264a0527a4da6488"
BEFORE["web/findllm.html"]="365919d89c27fb5108b2014dd3b86cc1791055ad24bbef11ee2de64c311ffe11"
AFTER["findllm_test.go"]="5e29d708e54edb5fb9a6998a174e67192cb5f5faf8940bb5b312cdcf98f00d84"
AFTER["web/app.css"]="be813c41615b4882394c7b1f533c3bc2daeb0c318d47ee3d62696e26b39d0a03"
AFTER["web/findllm.html"]="fa60402eef612f594a47e81f0f23bc60025e5e8bbb16eee8b88741ac02402a61"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/find-llm-installed-speed"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 100b must have been applied: the bubble of Sort by exists.
grep -q 'id="tip-sortby"' web/findllm.html || fail "script 100b must be applied first"
# Report it.
pass "script 100b (Sort by bubble) is applied"

# Refuse to run twice: the bubble is gone when this change was applied before.
if ! grep -q 'id="tip-sortby"' web/findllm.html; then fail "the Sort by bubble is already removed: this script was already applied"; fi
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
index d4d1ac9..cafdf44 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -1827,7 +1827,7 @@ func TestFindSortChoice(t *testing.T) {
 	// The empty form page.
 	_, _, form := get(t, rig.h, http.MethodGet, "/findllm")
 	// The choice sits in the same paragraph as the button, with Most downloaded selected.
-	for _, want := range []string{`<p class="findaction"><button type="submit" class="btn-solid">Find LLM</button>`, `name="sort"`, `<option value="downloads" selected>Most downloaded</option>`, `<option value="name">Name A to Z</option>`, `class="tip tip-icon" role="tooltip" id="tip-sortby">Sorts the Ollama library list only, not Hugging Face. Models that fit this computer stay first.`} {
+	for _, want := range []string{`<p class="findaction"><button type="submit" class="btn-solid">Find LLM</button>`, `name="sort"`, `<option value="downloads" selected>Most downloaded</option>`, `<option value="name">Name A to Z</option>`, `Sort by <select class="keepselect" id="sortby" name="sort">`} {
 		// Look for it.
 		if !strings.Contains(form, want) {
 			// Report.
diff --git a/web/app.css b/web/app.css
index b03f0e2..2938dbe 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1120,7 +1120,7 @@ button.btn-plain {
 } /* end of rule */
 
 /* Every icon box is its own anchor: the name is private to each box, so a bubble finds only its own icon. */
-.gearform .tipbox, .findresult .tipbox, .comparebar .tipbox, .controls .tipbox, .lookstack .tipbox, .detailsbar .tipbox, .backtop, .brandwho .tipbox, .sortpick .tipbox {
+.gearform .tipbox, .findresult .tipbox, .comparebar .tipbox, .controls .tipbox, .lookstack .tipbox, .detailsbar .tipbox, .backtop, .brandwho .tipbox {
   /* The name the bubble uses to find this box. */
   anchor-name: --tipicon;
   /* Keep the name inside this box, so the boxes of other rows never get mixed up. */
@@ -2939,7 +2939,7 @@ html[data-size="medium"] svg[width="22"] {
   font-size: 1.05em;
 } /* end of rule */
 
-/* The button and the order choice on one line; plain inline layout, so the help bubble finds its place under the words. */
+/* The button and the order choice on one line; plain inline layout. */
 .findaction {
   /* Space above and below the line, as in a paragraph. */
   line-height: 2.6;
@@ -2952,9 +2952,3 @@ html[data-size="medium"] svg[width="22"] {
   /* Space between the button and the choice. */
   margin-left: 1rem;
 } /* end of rule */
-
-/* The help bubble of the order choice keeps normal line spacing, not the wide spacing of the line it sits in. */
-.findaction .tip {
-  /* Normal text spacing inside the bubble. */
-  line-height: 1.4;
-} /* end of rule */
diff --git a/web/findllm.html b/web/findllm.html
index a72c9da..ba53f0b 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -93,7 +93,7 @@
 </fieldset>
 {{/* The button: the first and only thing that reads the internet. */}}
 {{/* The button, with the order of the results beside it. */}}
-<p class="findaction"><button type="submit" class="btn-solid">Find LLM</button> <label class="sortpick" for="sortby"><span class="tipbox"><span class="help" tabindex="0" aria-describedby="tip-sortby">Sort by</span><span class="tip tip-icon" role="tooltip" id="tip-sortby">Sorts the Ollama library list only, not Hugging Face. Models that fit this computer stay first.</span></span> <select class="keepselect" id="sortby" name="sort"><option value="downloads"{{if not .SortName}} selected{{end}}>Most downloaded</option><option value="name"{{if .SortName}} selected{{end}}>Name A to Z</option></select></label></p>
+<p class="findaction"><button type="submit" class="btn-solid">Find LLM</button> <label class="sortpick" for="sortby">Sort by <select class="keepselect" id="sortby" name="sort"><option value="downloads"{{if not .SortName}} selected{{end}}>Most downloaded</option><option value="name"{{if .SortName}} selected{{end}}>Name A to Z</option></select></label></p>
 </form>
 {{/* The results appear only after the button was pressed. */}}
 {{if .Searched}}
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
echo "NEXT  start bin/LLMsControlDock and look at Sort by beside the Find LLM button (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
