#!/usr/bin/env bash
# Script 131 (Help sort sentence and two new smoke checks): adds one sentence about the sort order to the Find LLM Help topic (help.go), makes the Help test require it (help_test.go), and adds two checks on the Find LLM sort choice to the smoke and load test (scripts/test-smoke-load.sh, 39 checks become 41).
# Run it on your branch for release 0.34.0 (never main): cd ~/LLMsControlDock-2 && git branch --show-current && bash scripts/131-step93-help-sort-and-smoke-checks.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the three files BEFORE the change and AFTER it.
declare -A BEFORE AFTER
BEFORE["help.go"]="604e484f4022cb1e65ca22aa56f82b26b9a8b85723f939cb7290648be8a0be95"
BEFORE["help_test.go"]="aa733d2572cbf8db0fe1a3b1e9feb7025b8745abf7f260b2f0c965d577b9b5b9"
BEFORE["scripts/test-smoke-load.sh"]="53315f32178b0ae3dda464fe3231e5862b65f5cd013a384f6e8d903e4e52f17c"
AFTER["help.go"]="672099db7e0d054b2bcad36d0fdeb8bdb4a6deb4f7a83b914f5437d25cad8dbb"
AFTER["help_test.go"]="422e1b9cf6cb5233917a48254f2d6ada5ffee017f3ab101f12271b525e69ea59"
AFTER["scripts/test-smoke-load.sh"]="667066491e6e551277f107105a67f473e8e08d147903655080bbe583b59771cf"

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
[ "$BRANCH" != "main" ] || fail "you are on main; switch to your release branch first: git switch feature/release-0.34.0-preparation"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 130 must be applied (the 0.34.0 release notes are its sign).
[ -f RELEASE-NOTES-0.34.0.md ] && grep -q '^const appVersion = "0.34.0"$' about.go || fail "script 130 is not applied in this branch (RELEASE-NOTES-0.34.0.md or appVersion 0.34.0 missing)"
# Report it.
pass "script 130 (release 0.34.0 preparation) is applied"

# Refuse to run twice: the new Help sentence is the sign.
if grep -q 'newest first' help.go; then fail "help.go already has the sort sentence: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# Every existing file must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the file is not the expected version.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} existing files are the expected version"

# The files that are already changed (script 130 is not committed yet); kept to compare afterwards.
CHANGED_BEFORE="$(git diff --name-only | LC_ALL=C sort)"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_131_END'
diff --git a/help.go b/help.go
--- a/help.go
+++ b/help.go
@@ -142,7 +142,7 @@
 	{
 		ID:    "find-llm",
 		Title: "Find LLM: from your needs to a model you can install",
-		Intro: "Find LLM lists the models of the official Ollama library that fit what you tick and what this computer has. Each result says which of your choices it matched, has a table to compare its sizes, and warns you, with the steps to update, when it needs a newer Ollama than yours. Decision models, which classify or score text and do not chat, have their own tick. A label that ollama.com shows and this program does not know yet is named in a notice. It never installs anything: you copy a command and run it yourself. If ollama.com cannot be reached, a saved copy of the list is shown with its date and without versions.",
+		Intro: "Find LLM lists the models of the official Ollama library that fit what you tick and what this computer has. Each result says which of your choices it matched, has a table to compare its sizes, and warns you, with the steps to update, when it needs a newer Ollama than yours. Decision models, which classify or score text and do not chat, have their own tick. A label that ollama.com shows and this program does not know yet is named in a notice. The results are sorted by the day ollama.com last updated each model, newest first (shown as rounded words such as 6 days ago); the Sort by choice switches to most downloaded or name A to Z without a new search. It never installs anything: you copy a command and run it yourself. If ollama.com cannot be reached, a saved copy of the list is shown with its date and without versions.",
 		Steps: []helpStep{
 			{0, "Open Find LLM from the monitor."},
 			{1, "Shows the choices, with free disk and memory filled in."},
diff --git a/help_test.go b/help_test.go
--- a/help_test.go
+++ b/help_test.go
@@ -410,7 +410,7 @@
 	} // end of the template loop
 } // end of TestHelpPerformanceGuide
 
-// TestHelpFindLLMIntroNamesTheNewBehaviour keeps the Find LLM introduction in step with the page: matched choices, the size table, the newer-Ollama warning, decision models and the notice for unknown labels.
+// TestHelpFindLLMIntroNamesTheNewBehaviour keeps the Find LLM introduction in step with the page: matched choices, the size table, the newer-Ollama warning, decision models, the sort order and the notice for unknown labels.
 func TestHelpFindLLMIntroNamesTheNewBehaviour(t *testing.T) {
 	// The Find LLM topic, found by its id.
 	var intro string
@@ -428,7 +428,7 @@
 		t.Fatal("the find-llm help topic is missing")
 	} // end of the existence check
 	// Each phrase stands for one behaviour of the page; the introduction must name it.
-	for _, want := range []string{"which of your choices it matched", "compare its sizes", "newer Ollama", "Decision models", "does not know yet"} {
+	for _, want := range []string{"which of your choices it matched", "compare its sizes", "newer Ollama", "Decision models", "does not know yet", "newest first", "Sort by"} {
 		// A missing phrase means the Help text no longer matches the page.
 		if !strings.Contains(intro, want) {
 			// Report.
diff --git a/scripts/test-smoke-load.sh b/scripts/test-smoke-load.sh
--- a/scripts/test-smoke-load.sh
+++ b/scripts/test-smoke-load.sh
@@ -174,6 +174,10 @@
 page_check "Settings page" /settings 200 text/html "Settings"
 # The Find LLM page (only the choices; this does not search the internet).
 page_check "Find LLM page" /findllm 200 text/html "Find LLM"
+# The sort choice must start on "Updated: new to old" (the default since 0.34.0).
+page_check "Find LLM sort defaults to Updated: new to old" /findllm 200 text/html '<option value="updated" selected>Updated: new to old</option>'
+# The other two sort choices must still be offered.
+page_check "Find LLM sort offers Most downloaded and Name A to Z" /findllm 200 text/html 'Most downloaded</option><option value="name"'
 # The Uninstall page only shows what would be removed.
 page_check "Uninstall page (shows only, removes nothing)" /uninstall 200 text/html "Uninstall LLMsControlDock"
 # The re-test status page.
OCC_PATCH_131_END
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

# Only the three files of this script may be newly changed (the earlier changes of script 130 stay).
CHANGED_AFTER="$(git diff --name-only | LC_ALL=C sort)"
# The expected list is the earlier list plus the three files, sorted and without doubles.
EXPECTED="$( { echo "$CHANGED_BEFORE"; echo help.go; echo help_test.go; echo scripts/test-smoke-load.sh; } | sed '/^$/d' | LC_ALL=C sort -u)"
# Anything else is a failure.
[ "$CHANGED_AFTER" = "$EXPECTED" ] || fail "other files changed than expected: $CHANGED_AFTER"
# Report it.
pass "only help.go, help_test.go and scripts/test-smoke-load.sh were newly changed"

# The key lines must be in place.
grep -q 'the Sort by choice switches to most downloaded or name A to Z' help.go && grep -c 'Find LLM sort ' scripts/test-smoke-load.sh | grep -q '^2$' || fail "a key line of the change is missing"
# Report it.
pass "the Help sentence and the two smoke checks are in place"

# The word the owner does not want in documents must not be in the new text.
if git diff -- help.go help_test.go scripts/test-smoke-load.sh | grep '^+' | grep -q 'KISS'; then fail "the forbidden word is in the new text"; fi
# Report it.
pass "the new text does not use the forbidden word"

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

# Run every test once; a timing failure of TestTableColumnOrder or TestDeleteConfirmRefusesLoadedModel is reported and not hidden.
go test -count=1 ./... || fail "go test failed (if only TestTableColumnOrder or TestDeleteConfirmRefusesLoadedModel failed, run the tests once more and tell Claude)"
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
echo "NEXT  build the program and run the smoke and load test (41 checks expected); instructions follow in the chat."
# Show what changed in the project folder.
git status --short
