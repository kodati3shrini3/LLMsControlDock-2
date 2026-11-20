#!/usr/bin/env bash
# Script 136 (release notes: built by GitHub): updates RELEASE-NOTES-0.34.0.md so it says the six files were built by the GitHub workflow run 44680558258 (Go 1.27.4) from commit ce30d4a, that this run completed successfully on the final code, and that the smoke and load test also passed on the GitHub-built Linux ARM64 file.
# Run it on a NEW branch made from the updated main (never main): cd ~/LLMsControlDock-2 && git switch main && git pull && git switch -c feature/release-0.34.0-notes-github-build && bash scripts/136-step98-release-notes-github-build.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The file to change and its expected sha256 BEFORE and AFTER the change.
FILE="RELEASE-NOTES-0.34.0.md"
BEFORE="a3567e9b4761e427e35f19b87b52c423e7d0d3dbcbcc618c2346f6b4dcad553c"
AFTER="c8e584b1575a70a32678d614707332268192dd9fc875d1bfb4a811dc75700ecc"

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
[ "$BRANCH" != "main" ] || fail "you are on main; make a branch first: git switch -c feature/release-0.34.0-notes-github-build"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Pull request 62 must be in.
grep -q 'Run on 2026-11-20 on Linux ARM64' "$FILE" || fail "pull request 62 is not in this branch; run git pull on main first"
# Report it.
pass "pull request 62 is in"

# Refuse to run twice: the run number is the sign.
if grep -q '44680558258' "$FILE"; then fail "$FILE already names the GitHub run: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_136_END'
diff --git a/RELEASE-NOTES-0.34.0.md b/RELEASE-NOTES-0.34.0.md
--- a/RELEASE-NOTES-0.34.0.md
+++ b/RELEASE-NOTES-0.34.0.md
@@ -59,10 +59,10 @@
 ## Verified so far
 
 - An automated suite of about 515 tests passes on Linux ARM64 (DGX Spark) for the final code of this release, and the program compiles for all six systems (Linux, Windows and macOS, each for x86-64 and ARM64 or Apple silicon).
-- The GitHub start-up check, which also runs the automated tests, passed on all six systems for an earlier state of this version (run `43981980700`). It has **not** been run on the final files of this release.
+- The GitHub workflow (go vet, build, start-up check and automated tests on each of the six systems) completed successfully on the final code of this release, commit `ce30d4a`: [run 44680558258](https://github.com/kodati3shrini3/LLMsControlDock-2/actions/runs/44680558258).
 - Used by hand on Ubuntu ARM64 (DGX Spark): the Find LLM changes of this release. Used by hand on Windows 11 x86-64 with 0.33.0.
 - Run on 2026-11-20 on Linux ARM64 (DGX Spark, Ollama 0.34.4) with the final files of this release: the smoke and load test (41 checks; 10 parallel readers for 20 seconds, about 15,000 requests, none failed, 95th percentile 45 ms) and the functional regression test (55 checks: every page and button, checked against Ollama's own API, including delete and download again). All passed.
-- The files in this release were built on the author's computer.
+- The six files in this release were built by that GitHub workflow run (Go 1.27.4) from commit `ce30d4a`, and each is listed with its checksum in `SHA256SUMS`. The smoke and load test (41 checks) was also run on the GitHub-built Linux ARM64 file and passed.
 
 ## Known limits
 
OCC_PATCH_136_END
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

# The old claims must be gone.
if grep -q "built on the author's computer\|has \*\*not\*\* been run on the final files" "$FILE"; then fail "an old claim is still in $FILE"; fi
# Report it.
pass "the old claims are gone"

# The word the owner does not want in documents must not be in the notes.
if grep -q 'KISS' "$FILE"; then fail "the forbidden word is in $FILE"; fi
# Report it.
pass "the release notes do not use the forbidden word"

# The summary.
echo "Result: $PASS passed, 0 failed"
# What to do next.
echo "NEXT  read the Verified so far part, then commit, push, pull request and merge."
# Show what changed in the project folder.
git status --short
