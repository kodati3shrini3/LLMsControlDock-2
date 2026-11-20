#!/usr/bin/env bash
# Script 132 (regression test: sort check): adds one check to the git-ignored functional regression test regressionTest/regression_test.py (54 checks become 55): the Find LLM sort starts on "Updated: new to old", and re-sorting by updated and by most downloaded keeps the results.
# The file is not tracked by git, so nothing here goes into a commit. A backup of the old file is kept next to it.
# Run it from anywhere inside the project: cd ~/LLMsControlDock-2 && bash scripts/132-step94-regression-test-sort-check.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The file to change and its expected sha256 BEFORE and AFTER the change.
FILE="regressionTest/regression_test.py"
BEFORE="3c6568162985f7ef63bdd7f5746693f189c8c56058d51ed988a0e623fc918d98"
AFTER="79f21ce8476aa088df74f9241250c0f956d71a790a2151afd679b3ea93bcd275"

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

# The file must exist.
[ -f "$FILE" ] || fail "$FILE is missing"
# Refuse to run twice: the new check's title is the sign.
if grep -q 'sort starts on Updated: new to old' "$FILE"; then fail "the sort check is already in $FILE: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_132_END'
diff --git a/regressionTest/regression_test.py b/regressionTest/regression_test.py
--- a/regressionTest/regression_test.py
+++ b/regressionTest/regression_test.py
@@ -878,6 +878,21 @@
             expect(n > 0, "no models listed: " + (re.search(r"(The Ollama library could not be read[^.]*\.)", p.plain()) or [None, "see the page"])[1])
             # How many.
             c.detail = "%d models listed" % n
+        with Check("find llm", "sort starts on Updated: new to old, and re-sorting by updated and by most downloaded keeps the results") as c:
+            # The results page of the search above (p) must offer the three sort choices, with Updated chosen.
+            expect('<option value="updated" selected>Updated: new to old</option>' in p.text, "the sort does not start on Updated: new to old")
+            # The two other choices must be offered too.
+            expect("Most downloaded</option>" in p.text and "Name A to Z</option>" in p.text, "Most downloaded or Name A to Z is missing")
+            # Re-sort by the update order and by the download count, without a new search.
+            for order in ("updated", "downloads"):
+                # Send the new order.
+                r = b.send("POST", "/findllm/resort", [("token", token), ("sort", order)], timeout=60)
+                # Followed by the page, or the page itself.
+                q = b.follow(r) if r.status == 303 else r
+                # Results are still shown.
+                expect(q.status == 200 and 'class="findresult"' in q.text, "no results after re-sort by %s (%d)" % (order, q.status))
+            # The same models are listed whatever the order: the count must be unchanged.
+            expect(q.text.count('class="findresult"') == p.text.count('class="findresult"'), "the number of models changed after re-sorting")
         with Check("find llm", "re-sort by name without a new search, then reset") as c:
             # Re-sort.
             r = b.send("POST", "/findllm/resort", [("token", token), ("sort", "name")], timeout=60)
OCC_PATCH_132_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"

# Keep a backup of the old file next to it (the folder is ignored by git).
cp -p "$FILE" "$FILE.before-0.34.0"
# Report it.
pass "backup kept as $FILE.before-0.34.0"

# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched file must be exactly what was checked in the sandbox.
[ "$(sha "$FILE")" = "$AFTER" ] || fail "$FILE has an unexpected sha256 after the change"
# Report it.
pass "$FILE has the expected sha256"

# Python must still be able to read the file (a syntax check only; nothing is run).
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$FILE" || fail "$FILE has a syntax error"
# Report it.
pass "python reads $FILE without a syntax error"

# The tracked files must not have changed because of this script.
[ -z "$(git status --short -- regressionTest)" ] || fail "git sees changes in regressionTest (it should be ignored)"
# Report it.
pass "git ignores regressionTest, so nothing new to commit"

# The summary.
echo "Result: $PASS passed, 0 failed"
# What to do next.
echo "NEXT  run the regression test (it uses your real Ollama; instructions follow in the chat)."
