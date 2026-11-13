#!/usr/bin/env bash
# Script 119 (workflow first-start check): the GitHub check "Build and test (manual, per system)" failed on all six systems because a first start answers the main address with a redirect to the System check page, so the old title test found nothing. This script changes only .github/workflows/build.yml: curl follows the redirect (-L), the test expects the System check title, and both title and version tests now print a reason when they fail. No Go file is touched, so the Go checks are replaced by "build.yml is the only tracked file changed".
# Run it on a new branch (never main): cd ~/LLMsControlDock-2 && git switch -c feature/workflow-first-start-check && bash scripts/119-step82-workflow-first-start-check.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of build.yml BEFORE the change (as on main after PR 55) and AFTER it.
BEFORE_YML="2c838ab3d0dce7446792f516c314aeaec8d734aae81642aa7a6925e7b9fd2720"
AFTER_YML="c8963e8dab722d687b7a1960a987806f19620d3ec182604afe179eb2c4cdd32c"

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
[ "$BRANCH" != "main" ] || fail "you are on main; create a branch first: git switch -c feature/workflow-first-start-check"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 118 must be in: the README has the new-issue link.
grep -q 'LLMsControlDock-2/issues/new' README.md || fail "script 118 (README issue link) is not in; update main first"
# Report it.
pass "script 118 is in"

# Refuse to run twice: the System check title is already in the workflow when this change was applied before.
if grep -q 'System check - LLMsControlDock' .github/workflows/build.yml; then fail "build.yml already has the System check test: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# build.yml must be exactly the version the patch was made against.
[ "$(sha .github/workflows/build.yml)" = "$BEFORE_YML" ] || fail "build.yml is not the expected version (sha256 differs); tell Claude which state you are in"
# Report it.
pass "build.yml is the expected version before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_95_END'
diff --git a/.github/workflows/build.yml b/.github/workflows/build.yml
index ef7b78f..b12da57 100644
--- a/.github/workflows/build.yml
+++ b/.github/workflows/build.yml
@@ -156,13 +156,13 @@ jobs:
           # Wait up to 30 seconds for the main page.
           ok=0
           for i in $(seq 1 30); do
-            if curl -fsS -o main.html http://127.0.0.1:8765/ 2> /dev/null; then ok=1; break; fi
+            if curl -fsSL -o main.html http://127.0.0.1:8765/ 2> /dev/null; then ok=1; break; fi
             sleep 1
           done
           if [ "$ok" != "1" ]; then echo "The program did not answer within 30 seconds"; cat run.log; exit 1; fi
-          # The main page names the program, the About page carries the version, the Settings page answers.
-          grep -q "<title>LLMsControlDock</title>" main.html
-          curl -fsS http://127.0.0.1:8765/about | grep -q "$VERSION"
+          # A fresh machine has no saved data folder, so the program answers the main address with its System check (a redirect that curl -L followed above); the About page carries the version, the Settings page answers.
+          grep -q "<title>System check - LLMsControlDock</title>" main.html || { echo "The first page is not the System check; its start is:"; head -c 600 main.html; exit 1; }
+          curl -fsS http://127.0.0.1:8765/about | grep -q "$VERSION" || { echo "The About page does not carry version $VERSION"; exit 1; }
           curl -fsS -o /dev/null http://127.0.0.1:8765/settings
           echo "PASS: $FILE answered on $RUNNER_OS $RUNNER_ARCH"
           cat run.log
OCC_PATCH_95_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched file must be exactly what was tested in the sandbox.
[ "$(sha .github/workflows/build.yml)" = "$AFTER_YML" ] || fail "build.yml has an unexpected sha256 after the change"
# Report it.
pass "build.yml has the expected sha256"

# The redirect must be followed and the new title must be tested.
grep -q 'curl -fsSL -o main.html' .github/workflows/build.yml && grep -q '<title>System check - LLMsControlDock</title>' .github/workflows/build.yml || fail "the new test lines are missing in build.yml"
# Report it.
pass "build.yml follows the redirect and tests the System check title"

# No unfinished marker may be in the workflow.
if grep -n -E 'CONFIRM|DRAFT' .github/workflows/build.yml; then fail "an unfinished marker is in the lines above"; fi
# Report it.
pass "build.yml holds no unfinished markers"

# Only build.yml may be changed among the files git tracks (no Go file, no web file, no README).
CHANGED="$(git diff --name-only)"
# Anything else is a failure.
[ "$CHANGED" = ".github/workflows/build.yml" ] || fail "files other than build.yml changed: $CHANGED"
# Report it.
pass "build.yml is the only tracked file that changed, so no Go check is needed"

# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  commit, push, pull request and merge (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
