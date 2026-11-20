#!/usr/bin/env bash
# Script 135 (release notes: verified so far): updates RELEASE-NOTES-0.34.0.md after the smoke, load and regression runs of 2026-11-20 (test count about 515; the 41-check smoke and load test and the 55-check regression test passed on the final files) and adds the Help sentences on Pause/Resume and the About estimate to the "Help and README" row. The Windows row stays as it is (0.33.0 only, as you confirmed). The README needs no change.
# Run it on your branch for release 0.34.0 (never main): cd ~/LLMsControlDock-2 && bash scripts/135-step97-release-notes-verified.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The file to change and its expected sha256 BEFORE and AFTER the change.
FILE="RELEASE-NOTES-0.34.0.md"
BEFORE="0cb833bc7a207ee106f0fe9fe2bd0f2bf46e9d1450e46fcbbaa4b0b99d8b5b8b"
AFTER="a3567e9b4761e427e35f19b87b52c423e7d0d3dbcbcc618c2346f6b4dcad553c"

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
[ "$BRANCH" != "main" ] || fail "you are on main; switch to your release branch first: git switch feature/release-0.34.0-preparation"
# Report the branch.
pass "on branch $BRANCH (not main)"

# The release notes must exist.
[ -f "$FILE" ] || fail "$FILE is missing (script 130 not applied?)"
# Refuse to run twice: the 2026-11-20 line is the sign.
if grep -q 'Run on 2026-11-20 on Linux ARM64' "$FILE"; then fail "$FILE already has the test line: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_135_END'
diff --git a/RELEASE-NOTES-0.34.0.md b/RELEASE-NOTES-0.34.0.md
--- a/RELEASE-NOTES-0.34.0.md
+++ b/RELEASE-NOTES-0.34.0.md
@@ -15,7 +15,7 @@
 | Find LLM, decision models | A new tick finds decision models. They classify text, answer yes or no, or score text, and they do not chat. They need Ollama 0.35.0 or newer. |
 | Find LLM, labels | Mixed sizes such as 8x7b are now counted as their total (56 billion). A label that ollama.com shows and this program does not know yet is named in a notice, with a request to report it. |
 | Docker and Kubernetes | The commands on Find LLM and on the Delete page now use `-it` (`docker exec -it`, `kubectl exec -it`), so they work in a terminal. |
-| Help and README | The Find LLM Help topic and the README describe the changes above. |
+| Help and README | The Find LLM Help topic and the README describe the changes above. The Help also now describes the Pause and Resume of the monitor page and the estimate on the About page, which it did not mention before. |
 | Behind the scenes | The README links straight to the issues page. The GitHub start-up check follows the first-start redirect to the System check. Four automated tests that failed on Windows in 0.33.0 are fixed. |
 
 ## Things to know about the new Find LLM features
@@ -58,10 +58,10 @@
 
 ## Verified so far
 
-- An automated suite of about 510 tests passes on Linux ARM64 (DGX Spark) for the final code of this release, and the program compiles for all six systems (Linux, Windows and macOS, each for x86-64 and ARM64 or Apple silicon).
+- An automated suite of about 515 tests passes on Linux ARM64 (DGX Spark) for the final code of this release, and the program compiles for all six systems (Linux, Windows and macOS, each for x86-64 and ARM64 or Apple silicon).
 - The GitHub start-up check, which also runs the automated tests, passed on all six systems for an earlier state of this version (run `43981980700`). It has **not** been run on the final files of this release.
 - Used by hand on Ubuntu ARM64 (DGX Spark): the Find LLM changes of this release. Used by hand on Windows 11 x86-64 with 0.33.0.
-- The 39-check smoke and load test and the 54-check functional regression test were run for 0.33.0. They have not been re-run for this release.
+- Run on 2026-11-20 on Linux ARM64 (DGX Spark, Ollama 0.34.4) with the final files of this release: the smoke and load test (41 checks; 10 parallel readers for 20 seconds, about 15,000 requests, none failed, 95th percentile 45 ms) and the functional regression test (55 checks: every page and button, checked against Ollama's own API, including delete and download again). All passed.
 - The files in this release were built on the author's computer.
 
 ## Known limits
OCC_PATCH_135_END
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

# The new lines must be in place and the old claim must be gone.
grep -q 'about 515 tests' "$FILE" && grep -q 'Run on 2026-11-20 on Linux ARM64' "$FILE" && ! grep -q 'have not been re-run for this release' "$FILE" || fail "a key line is wrong"
# Report it.
pass "the verified lines are updated"

# The word the owner does not want in documents must not be in the notes.
if grep -q 'KISS' "$FILE"; then fail "the forbidden word is in $FILE"; fi
# Report it.
pass "the release notes do not use the forbidden word"

# The summary.
echo "Result: $PASS passed, 0 failed"
# What to do next.
echo "NEXT  read the Verified so far part of RELEASE-NOTES-0.34.0.md (instructions follow in the chat)."
