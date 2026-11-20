#!/usr/bin/env bash
# Script 133 (smoke and load test folder): moves scripts/test-smoke-load.sh into the new folder smokeAndLoadTest/ (with git mv, so the history is kept), updates the usage line inside it, and makes git ignore the results folder smokeAndLoadTest/results/.
# Run it on your branch for release 0.34.0 (never main): cd ~/LLMsControlDock-2 && bash scripts/133-step95-move-smoke-test-folder.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The old and the new place of the script, and its expected sha256 BEFORE and AFTER the usage line change.
OLD="scripts/test-smoke-load.sh"
NEW="smokeAndLoadTest/test-smoke-load.sh"
BEFORE="667066491e6e551277f107105a67f473e8e08d147903655080bbe583b59771cf"
AFTER="50aab8961c2f1c3131883a3fb24f4149b11beb4655764a6cd51178d638bb2ef2"

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

# Script 131 must be applied (its two smoke checks are the sign).
grep -q 'Find LLM sort defaults' "$OLD" || fail "script 131 is not applied (the new smoke checks are missing in $OLD)"
# Report it.
pass "script 131 is applied"

# Refuse to run twice: the script is already in the new folder, or the old one is gone.
if [ -e "$NEW" ] || [ ! -e "$OLD" ]; then fail "$NEW exists or $OLD is gone: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# The script must be exactly the version expected.
[ "$(sha "$OLD")" = "$BEFORE" ] || fail "$OLD is not the expected version (sha256 differs); tell Claude which state you are in"
# Report it.
pass "$OLD is the expected version"

# The new folder (you made it already; this does nothing then).
mkdir -p smokeAndLoadTest
# Move the script with git, so the history stays.
git mv "$OLD" "$NEW" || fail "git mv failed"
# Report it.
pass "moved $OLD to $NEW"

# The only text that names the old place is the usage line (line 3); change it.
sed -i '3s#bash scripts/test-smoke-load.sh#bash smokeAndLoadTest/test-smoke-load.sh#' "$NEW"
# The moved and changed script must be exactly what was tested in the sandbox.
[ "$(sha "$NEW")" = "$AFTER" ] || fail "$NEW has an unexpected sha256 after the change"
# Report it.
pass "usage line updated; $NEW has the expected sha256"

# Make git ignore the results folder (once).
grep -qx 'smokeAndLoadTest/results/' .gitignore || printf '\n# Results of the smoke and load test runs (local only)\nsmokeAndLoadTest/results/\n' >> .gitignore
# Report it.
pass ".gitignore ignores smokeAndLoadTest/results/"

# The moved script must still be found by git as a rename of the old one.
git status --short | grep -q 'test-smoke-load.sh' || fail "git does not show the move"
# Report it.
pass "git shows the move"

# The summary.
echo "Result: $PASS passed, 0 failed"
# What to do next.
echo "NEXT  build the program and run: bash smokeAndLoadTest/test-smoke-load.sh bin/LLMsControlDock 8799"
# Show what changed in the project folder.
git status --short
