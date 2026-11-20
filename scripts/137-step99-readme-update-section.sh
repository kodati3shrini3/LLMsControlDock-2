#!/usr/bin/env bash
# Script 137 (README: update to a newer release): adds the section "Update to a newer release" to README.md. It gives four steps (download and check the file, stop the running program, run the new file once with -install, start it and read the version on the About page) and three notes (Windows refuses to replace a running copy, a copy not placed by -install is called "an unknown version", and a person who never used -install replaces the file they start). The program itself and its version (0.34.0) do not change.
# Run it on a NEW branch made from the updated main (never main): cd ~/LLMsControlDock-2 && git switch main && git pull && git switch -c feature/readme-update-section && bash scripts/137-step99-readme-update-section.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The file to change and its expected sha256 BEFORE and AFTER the change.
FILE="README.md"
BEFORE="2b81246dd43b44d35b746494b89fa63d830483192417a916f207c9c681ae5efa"
AFTER="b951c7692440335265c06be880e654dd7f5ce67cfefb347f4cd806fe6972a460"

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
[ "$BRANCH" != "main" ] || fail "you are on main; make a branch first: git switch -c feature/readme-update-section"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Refuse to run twice: the section heading is the sign.
if grep -q '^## Update to a newer release' "$FILE"; then fail "$FILE already has the update section: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_137_END'
diff --git a/README.md b/README.md
index 1886ff6..848a725 100644
--- a/README.md
+++ b/README.md
@@ -56,6 +56,15 @@ Then open http://127.0.0.1:8765/ in your browser. On the first start you see a S
 
 Installing is optional: the program runs from wherever you put it and makes its folders when it first needs them. Run it once with `-install` to do everything up front, after it asks you: it shows the System check, makes its folders, copies itself to `~/.local/bin` (Windows: `%LocalAppData%\Programs\LLMsControlDock`) and creates the desktop icon. No administrator rights are needed. The About page shows where the files are.
 
+## Update to a newer release
+
+1. Download the file for your system and `SHA256SUMS` from the [latest release](https://github.com/kodati3shrini3/LLMsControlDock-2/releases/latest), and check the checksum as described above.
+2. Stop the running program (the Stop button on the page, or Ctrl+C in its terminal).
+3. Run the new file once with `-install`. It shows the System check and a plan that names both versions, for example "Replace the installed program (version 0.33.0) with version 0.34.0 at ...; settings and results are kept", and it asks you to type `yes`. Your settings, results and history folders are kept, and Ollama and your models are not touched.
+4. Start the program again (the desktop icon, or the installed file) and open the About page: it shows the new version.
+
+If the installed copy is still running, Windows refuses to replace it; the installer says so, and you stop the program and run `-install` again. If the earlier copy was not placed by `-install`, the plan says "an unknown version" and replaces the copy at the standard place. If you never used `-install`, replace the file you start the program from. The update steps have been tested by hand on Linux only.
+
 | Option | Effect |
 |---|---|
 | `-listen host:port` | Where the page listens (default `127.0.0.1:8765`) |
OCC_PATCH_137_END
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

# The new section must be there, with its four numbered steps.
grep -q '^## Update to a newer release' "$FILE" || fail "the section heading is missing"
# The steps.
[ "$(sed -n '/^## Update to a newer release/,/^If the installed copy/p' "$FILE" | grep -c '^[1-4]\. ')" = "4" ] || fail "the four steps are not all there"
# Report it.
pass "the update section has its four steps"

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
echo "NEXT  read the new section on the branch (README.md), try the steps' wording, then say if you want to commit, open a pull request and merge."
# Show what changed in the project folder.
git status --short
