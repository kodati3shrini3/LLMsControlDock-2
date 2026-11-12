#!/usr/bin/env bash
# Script 118 (README issue link): the Contributing section of the README links directly to the issues page and to "new issue", and says what to include in a report. Only README.md changes; no Go file is touched, so the Go checks are replaced by a check that README.md is the only changed file.
# Run it on a new branch (never main): cd ~/LLMsControlDock-2 && git switch -c feature/readme-issues-link && bash scripts/118-step81-readme-issues-link.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of README.md BEFORE the change (as on main after script 117) and AFTER it.
BEFORE_README="0b9298999ae1474270d5a2541930ec3330a078b0460344fa8ded7ed72663dd9e"
AFTER_README="0bd8100ce955f6b020e75a9acf472d5c244708ea525ee004c4bf706f3ddc3a13"

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
[ "$BRANCH" != "main" ] || fail "you are on main; create a branch first: git switch -c feature/readme-issues-link"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 117 must be in: the release notes file exists.
[ -e RELEASE-NOTES-0.33.0.md ] || fail "script 117 (release preparation) is not in: RELEASE-NOTES-0.33.0.md is missing"
# Report it.
pass "script 117 is in"

# Refuse to run twice: the new-issue link is already in the README when this change was applied before.
if grep -q 'LLMsControlDock-2/issues/new' README.md; then fail "README.md already has the new-issue link: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# README.md must be exactly the version the patch was made against.
[ "$(sha README.md)" = "$BEFORE_README" ] || fail "README.md is not the expected version (sha256 differs); tell Claude which state you are in"
# Report it.
pass "README.md is the expected version before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_94_END'
diff --git a/README.md b/README.md
index c1f8b6a..982ad4f 100644
--- a/README.md
+++ b/README.md
@@ -76,7 +76,7 @@ LLMsControlDock is an independent tool. It is not affiliated with, endorsed by o
 
 ## Contributing
 
-Questions, bug reports and ideas are welcome as issues. Code contributions are not accepted for now.
+Questions, bug reports and ideas are welcome as [issues](https://github.com/kodati3shrini3/LLMsControlDock-2/issues). To report a problem, [open a new issue](https://github.com/kodati3shrini3/LLMsControlDock-2/issues/new) (a free GitHub account is needed) and tell us which version you use (the About page shows it), which system, which Ollama version, and what you did and what happened. Please do not paste passwords or private addresses. Code contributions are not accepted for now.
 
 ## Licence
 
OCC_PATCH_94_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched README must be exactly what was tested in the sandbox.
[ "$(sha README.md)" = "$AFTER_README" ] || fail "README.md has an unexpected sha256 after the change"
# Report it.
pass "README.md has the expected sha256"

# Both links must be in the README.
grep -q 'https://github.com/kodati3shrini3/LLMsControlDock-2/issues)' README.md && grep -q 'https://github.com/kodati3shrini3/LLMsControlDock-2/issues/new)' README.md || fail "an issues link is missing in README.md"
# Report it.
pass "README.md links to the issues page and to a new issue"

# No unfinished marker may be in the README.
if grep -n -E 'CONFIRM|DRAFT' README.md; then fail "an unfinished marker is in the lines above"; fi
# Report it.
pass "README.md holds no unfinished markers"

# Only README.md may be changed among the files git tracks (no Go file, no web file).
CHANGED="$(git diff --name-only)"
# Anything else is a failure.
[ "$CHANGED" = "README.md" ] || fail "files other than README.md changed: $CHANGED"
# Report it.
pass "README.md is the only tracked file that changed, so no Go check is needed"

# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  read the Contributing section (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
