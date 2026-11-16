#!/usr/bin/env bash
# Script 126 (README and Help topic for the new Find LLM behaviour): the README feature line says that each result tells which of your choices it matched, warns when a model needs a newer Ollama than yours and has a size comparison table; the README privacy line now names the one extra read-only request (the page of each listed model, to read which Ollama version it needs); the Help topic "Find LLM" gets the matching swimlane steps (asks each model's page, asks Ollama which version it is). Program change only through the Help text; version stays 0.33.0 until the release is made.
# Run it on the branch of scripts 122 to 125 (never main): cd ~/LLMsControlDock-2 && git switch feature/docker-it-flag && bash scripts/126-step88-readme-and-help-for-find-llm.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the two files BEFORE the change (as on this branch after script 125 was committed) and AFTER it.
declare -A BEFORE AFTER
BEFORE["README.md"]="331ff021e05918763b5d32dbc1396753ef5a576f7498e0fec5cbcddd48f331eb"
BEFORE["help.go"]="f4cbe962d0ce357f16504ebb1edfbaecc5a5658ee30fb32be1184918a5da249d"
AFTER["README.md"]="2eed4f06f1149dd56e73d8003b407250d19459fbd6256aca9dddb6e369c6fea4"
AFTER["help.go"]="d7e1103d47393419ebae602ee1f4aaf8049179a1d8a17e1b01d372723314a800"

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
[ "$BRANCH" != "main" ] || fail "you are on main; switch to the branch of scripts 122 to 125: git switch feature/docker-it-flag"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 125 must be in.
grep -q 'tipModelOld' findllm.go || fail "script 125 is not in this branch; run it first"
# Report it.
pass "script 125 is in"

# Refuse to run twice.
if grep -q "Sends the model's page" help.go; then fail "help.go already has the new steps: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_126_END'
diff --git a/README.md b/README.md
index 70ca5f2..4a01213 100644
--- a/README.md
+++ b/README.md
@@ -10,7 +10,7 @@ A small program that watches an [Ollama](https://ollama.com) server and lets you
 - Shows the loaded and the installed models, with their memory use.
 - Loads and unloads a model (it asks first, and warns about memory).
 - Shows and changes a model's settings, and shows its Modelfile.
-- Finds models: **Find LLM** reads the public Ollama model list, lets you search and sort it, and shows which models you already have.
+- Finds models: **Find LLM** reads the public Ollama model list, lets you search and sort it, and shows which models you already have. Each result says which of your choices it matched, warns when a model needs a newer Ollama than yours, and has a size comparison table.
 - Tests a model's speed with one fixed built-in prompt, and compares the tested models (PDF and CSV). A built-in guide explains each figure in plain words.
 - Has a Help page with 13 topics, each drawn as a swimlane diagram of who does what (You, LLMsControlDock, Ollama, ollama.com).
 - Deletes a model and helps you restore it later (it shows the commands; you run them yourself).
@@ -21,7 +21,7 @@ A small program that watches an [Ollama](https://ollama.com) server and lets you
 - The page listens on this computer only (`127.0.0.1:8765`) unless you change that in Settings.
 - Only the program's own page can use the Stop and Unload buttons.
 - No prompt or response text is stored.
-- The only internet requests are read-only: a look-up of a model name in the public Ollama library before a delete; the public model list and version lists, read when you press Find LLM (your choices are not sent; the list is also kept in the program's data folder, so Find LLM can show it, dated, when the website cannot be reached); and the optional `-check-links` command.
+- The only internet requests are read-only: a look-up of a model name in the public Ollama library before a delete; the public model list, the version list and the page of each listed model (to read which Ollama version it needs), read when you press Find LLM (your choices are not sent; the list is also kept in the program's data folder, so Find LLM can show it, dated, when the website cannot be reached); and the optional `-check-links` command.
 
 ## What is tested
 
diff --git a/help.go b/help.go
index 715daea..d5dea77 100644
--- a/help.go
+++ b/help.go
@@ -151,8 +151,12 @@ var helpTopics = []helpTopic{
 			{3, "Sends the public list. Your choices are not sent."},
 			{1, "Keeps matching models, asks for each one's versions."},
 			{3, "Sends sizes, context lengths and update ages."},
+			{1, "Asks each one's page which Ollama version it needs."},
+			{3, "Sends the model's page."},
 			{1, "Asks Ollama which models are installed."},
 			{2, "Lists the installed models."},
+			{1, "Asks Ollama which version it is."},
+			{2, "Reports its version."},
 			{1, "Checks every version against your limits and lists them."},
 			{0, "Copy the command of a version that fits."},
 			{2, "Downloads the model when you run the command."},
OCC_PATCH_126_END
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

# Only the two expected files may be changed among the files git tracks.
CHANGED="$(git diff --name-only | LC_ALL=C sort | tr '\n' ' ')"
# The expected list.
EXPECTED="README.md help.go "
# Anything else is a failure.
[ "$CHANGED" = "$EXPECTED" ] || fail "other files changed than expected: $CHANGED"
# Report it.
pass "only README.md and help.go changed"

# The key lines must be in place.
grep -q 'the page of each listed model' README.md && grep -q 'size comparison table' README.md && grep -q "Sends the model's page" help.go || fail "a key line of the change is missing"
# Report it.
pass "README and Help text carry the new lines"

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

# Run every test once (the Help test checks that every step fits its box); a timing failure of TestTableColumnOrder or TestDeleteConfirmRefusesLoadedModel is reported and not hidden.
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
