#!/usr/bin/env bash
# Script 138 (README: update section links to the releases page): step 1 of the update section no longer links to /releases/latest, because GitHub's "latest release" link skips pre-releases and both releases so far are pre-releases; it now links to the releases page and says to take the newest entry. Only README.md changes; the version stays 0.34.0.
# Run it on the branch of script 137 (never main), after script 137 was applied: cd ~/LLMsControlDock-2 && git switch feature/readme-update-section && bash scripts/138-step100-readme-releases-page-link.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The file to change and its expected sha256 BEFORE and AFTER the change.
FILE="README.md"
BEFORE="b951c7692440335265c06be880e654dd7f5ce67cfefb347f4cd806fe6972a460"
AFTER="6568b8753cd19a0024f665339f75d45723c246bf45eee56f35d973c43b3ec70f"

# Count of passed checks.
PASS=0
# pass prints one PASS line and counts it.
pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
# fail prints one FAIL line and stops the script at once.
fail() { echo "FAIL  $1"; echo "Result: $PASS passed, 1 failed"; exit 1; }
# sha prints the sha256 of one file.
sha() { sha256sum "$1" | cut -d' ' -f1; }

# Go to the top folder of the git project this script was started in.
cd "$(git rev-parse --show-toplevel)"
# The project must be the right one.
[ -f main.go ] && [ -f go.mod ] || fail "this is not the project folder (main.go or go.mod missing)"
# Say where we are.
echo "Project folder: $(pwd)"

# The branch we are on.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# Never change main directly.
[ "$BRANCH" != "main" ] || fail "you are on main; switch to the branch of script 137: git switch feature/readme-update-section"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 137 must be applied first: its section is the precondition.
grep -q '^## Update to a newer release' "$FILE" || fail "script 137 is not applied on this branch; run it first"
# Report it.
pass "script 137 is applied"
# Refuse to run twice: the new wording is the sign.
if grep -q 'newest entry on the' "$FILE"; then fail "$FILE already has the new link wording: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# The file must be exactly the version the patch was made against.
[ "$(sha "$FILE")" = "$BEFORE" ] || fail "$FILE is not the expected version (sha256 differs); tell Claude which state you are in"
# Report it.
pass "$FILE is the expected version"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_138_END'
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -58,7 +58,7 @@
 
 ## Update to a newer release
 
-1. Download the file for your system and `SHA256SUMS` from the [latest release](https://github.com/kodati3shrini3/LLMsControlDock-2/releases/latest), and check the checksum as described above.
+1. Download the file for your system and `SHA256SUMS` from the newest entry on the [releases page](https://github.com/kodati3shrini3/LLMsControlDock-2/releases), and check the checksum as described above.
 2. Stop the running program (the Stop button on the page, or Ctrl+C in its terminal).
 3. Run the new file once with `-install`. It shows the System check and a plan that names both versions, for example "Replace the installed program (version 0.33.0) with version 0.34.0 at ...; settings and results are kept", and it asks you to type `yes`. Your settings, results and history folders are kept, and Ollama and your models are not touched.
 4. Start the program again (the desktop icon, or the installed file) and open the About page: it shows the new version.
OCC_PATCH_138_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched file must be exactly what was checked in the sandbox.
[ "$(sha "$FILE")" = "$AFTER" ] || fail "$FILE has an unexpected sha256 after the change"
# Report it.
pass "$FILE has the expected sha256"

# Only this file may be changed.
[ "$(git diff --name-only)" = "$FILE" ] || fail "other files changed than expected: $(git diff --name-only | tr '\n' ' ')"
# Report it.
pass "only $FILE changed"

# The old link must be gone and the new one there.
if grep -q 'releases/latest' "$FILE"; then fail "the /releases/latest link is still in $FILE"; fi
# The new wording.
grep -q 'newest entry on the \[releases page\]' "$FILE" || fail "the new wording is missing"
# Report it.
pass "step 1 now links to the releases page"

# The word the owner does not want in documents must not be in the README.
if grep -q 'KISS' "$FILE"; then fail "the forbidden word is in $FILE"; fi
# Report it.
pass "the README does not use the forbidden word"

# The tests that read the README must still pass (licence, holder and version are checked there).
go test -count=1 -run 'TestLicenceFilesAgreeWithThePage' ./... > /dev/null 2>&1 || fail "go test of the README check failed; run: go test -run TestLicenceFilesAgreeWithThePage ./..."
# Report it.
pass "the README test passes"

# The summary.
echo "Result: $PASS passed, 0 failed"
# What to do next.
echo "NEXT  read step 1 of the update section, then say if you want to commit, open a pull request and merge."
# Show what changed in the project folder.
git status --short
