#!/usr/bin/env bash
# Script 127 (Help and README catch up with Find LLM): the Help topic "Find LLM" introduction now names what the page does since scripts 123 to 125 (which of your choices each result matched, the size comparison table, the warning with update steps when a model needs a newer Ollama, the tick for decision models, the notice for labels this program does not know yet); the README feature line names the Decision tick and the notice; a new test keeps the Help introduction in step with the page. No program behaviour changes; version stays 0.33.0 until the release is made.
# Run it on a NEW branch made from the updated main (never main): cd ~/LLMsControlDock-2 && git switch main && git pull && git switch -c feature/help-readme-find-llm && bash scripts/127-step89-help-and-readme-catch-up.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the three files BEFORE the change (as on main after pull request 59) and AFTER it.
declare -A BEFORE AFTER
BEFORE["README.md"]="2eed4f06f1149dd56e73d8003b407250d19459fbd6256aca9dddb6e369c6fea4"
BEFORE["help.go"]="d7e1103d47393419ebae602ee1f4aaf8049179a1d8a17e1b01d372723314a800"
BEFORE["help_test.go"]="478fbfb1add08db6fb89caa9e1c017522ec6269394d0425a260bd6a7df896daf"
AFTER["README.md"]="8aa78b1a3a98921ac932c87fc7ccb1cd99940a07717735f9dab9c178771f1be5"
AFTER["help.go"]="604e484f4022cb1e65ca22aa56f82b26b9a8b85723f939cb7290648be8a0be95"
AFTER["help_test.go"]="aa733d2572cbf8db0fe1a3b1e9feb7025b8745abf7f260b2f0c965d577b9b5b9"

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
[ "$BRANCH" != "main" ] || fail "you are on main; make a branch first: git switch -c feature/help-readme-find-llm"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Pull request 59 must be in (the unknown-label notice is its last piece).
grep -q 'unknownLabelNote' findsite.go || fail "pull request 59 is not in this branch; run git pull on main first"
# Report it.
pass "pull request 59 is in"

# Refuse to run twice.
if grep -q "TestHelpFindLLMIntroNamesTheNewBehaviour" help_test.go; then fail "help_test.go already has the new test: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_127_END'
diff --git a/README.md b/README.md
index 4a01213..6f6adb0 100644
--- a/README.md
+++ b/README.md
@@ -10,7 +10,7 @@ A small program that watches an [Ollama](https://ollama.com) server and lets you
 - Shows the loaded and the installed models, with their memory use.
 - Loads and unloads a model (it asks first, and warns about memory).
 - Shows and changes a model's settings, and shows its Modelfile.
-- Finds models: **Find LLM** reads the public Ollama model list, lets you search and sort it, and shows which models you already have. Each result says which of your choices it matched, warns when a model needs a newer Ollama than yours, and has a size comparison table.
+- Finds models: **Find LLM** reads the public Ollama model list, lets you search and sort it, and shows which models you already have. Each result says which of your choices it matched, warns when a model needs a newer Ollama than yours, and has a size comparison table. A separate tick finds decision models (they classify or score text and do not chat), and a label that ollama.com shows and this program does not know yet is named in a notice.
 - Tests a model's speed with one fixed built-in prompt, and compares the tested models (PDF and CSV). A built-in guide explains each figure in plain words.
 - Has a Help page with 13 topics, each drawn as a swimlane diagram of who does what (You, LLMsControlDock, Ollama, ollama.com).
 - Deletes a model and helps you restore it later (it shows the commands; you run them yourself).
diff --git a/help.go b/help.go
index d5dea77..eca7c2c 100644
--- a/help.go
+++ b/help.go
@@ -142,7 +142,7 @@ var helpTopics = []helpTopic{
 	{
 		ID:    "find-llm",
 		Title: "Find LLM: from your needs to a model you can install",
-		Intro: "Find LLM lists the models of the official Ollama library that fit what you tick and what this computer has. It never installs anything: you copy a command and run it yourself. If ollama.com cannot be reached, a saved copy of the list is shown with its date and without versions.",
+		Intro: "Find LLM lists the models of the official Ollama library that fit what you tick and what this computer has. Each result says which of your choices it matched, has a table to compare its sizes, and warns you, with the steps to update, when it needs a newer Ollama than yours. Decision models, which classify or score text and do not chat, have their own tick. A label that ollama.com shows and this program does not know yet is named in a notice. It never installs anything: you copy a command and run it yourself. If ollama.com cannot be reached, a saved copy of the list is shown with its date and without versions.",
 		Steps: []helpStep{
 			{0, "Open Find LLM from the monitor."},
 			{1, "Shows the choices, with free disk and memory filled in."},
diff --git a/help_test.go b/help_test.go
index f0297c0..7b32481 100644
--- a/help_test.go
+++ b/help_test.go
@@ -409,3 +409,30 @@ func TestHelpPerformanceGuide(t *testing.T) {
 		} // end of the link check
 	} // end of the template loop
 } // end of TestHelpPerformanceGuide
+
+// TestHelpFindLLMIntroNamesTheNewBehaviour keeps the Find LLM introduction in step with the page: matched choices, the size table, the newer-Ollama warning, decision models and the notice for unknown labels.
+func TestHelpFindLLMIntroNamesTheNewBehaviour(t *testing.T) {
+	// The Find LLM topic, found by its id.
+	var intro string
+	// Look through all topics.
+	for _, tp := range helpTopics {
+		// Only the Find LLM topic is wanted.
+		if tp.ID == "find-llm" {
+			// Keep its introduction.
+			intro = tp.Intro
+		} // end of the id check
+	} // end of the topic loop
+	// The topic must exist.
+	if intro == "" {
+		// Report.
+		t.Fatal("the find-llm help topic is missing")
+	} // end of the existence check
+	// Each phrase stands for one behaviour of the page; the introduction must name it.
+	for _, want := range []string{"which of your choices it matched", "compare its sizes", "newer Ollama", "Decision models", "does not know yet"} {
+		// A missing phrase means the Help text no longer matches the page.
+		if !strings.Contains(intro, want) {
+			// Report.
+			t.Errorf("the Find LLM help introduction does not say %q", want)
+		} // end of the phrase check
+	} // end of the phrase loop
+} // end of TestHelpFindLLMIntroNamesTheNewBehaviour
OCC_PATCH_127_END
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

# Only the three expected files may be changed among the files git tracks.
CHANGED="$(git diff --name-only | LC_ALL=C sort | tr '\n' ' ')"
# The expected list.
EXPECTED="README.md help.go help_test.go "
# Anything else is a failure.
[ "$CHANGED" = "$EXPECTED" ] || fail "other files changed than expected: $CHANGED"
# Report it.
pass "only README.md, help.go and help_test.go changed"

# The key phrases must be in place.
grep -q 'Decision models, which classify or score text' help.go && grep -q 'A separate tick finds decision models' README.md || fail "a key line of the change is missing"
# Report it.
pass "Help introduction and README carry the new lines"

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
echo "NEXT  look at the Help topic and the README by hand (instructions follow in the chat), then commit and push."
# Show what changed in the project folder.
git status --short
