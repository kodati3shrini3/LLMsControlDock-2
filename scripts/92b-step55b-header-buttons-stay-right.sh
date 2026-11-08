#!/usr/bin/env bash
# Script 92b (Find LLM, fix after slice 2): the top-row buttons stay at the top right of the page. The new Find LLM button made the button block wider than the space beside the title, so the whole block dropped under the title. The title block may now shrink and wrap its lines instead (one rule in web/app.css). Nothing else changes; version stays 0.31.0.
# Run it from the project folder, on the branch feature/find-llm-page after script 92: cd ~/LLMsControlDock && bash scripts/92b-step55b-header-buttons-stay-right.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of web/app.css BEFORE the change (as left by script 92) and AFTER it.
BEFORE_CSS="b7c3410711fa32b51ecd755112c1cfadf5cd0591c74490b35b1a7a1e61abd484"
# The sha256 tested in the sandbox.
AFTER_CSS="3982732efc48319ece84aba5d317c97bff76e0284d6e01d598b7c980ad305dbb"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/find-llm-page"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 92 must have been applied: its page file exists.
[ -e findllm.go ] || fail "findllm.go is missing: run script 92 first"
# Report it.
pass "script 92 (the Find LLM page) is applied"

# Refuse to run twice: the new rule is in the file when this fix was applied before.
if grep -q 'The title block may shrink' web/app.css; then fail "web/app.css already has the fix: this script was already applied"; fi
# Report it.
pass "this fix is not applied yet"

# The file must be exactly the version the patch was made against.
[ "$(sha web/app.css)" = "$BEFORE_CSS" ] || fail "web/app.css is not the expected version (sha256 differs); tell Claude which state you are in"
# Report it.
pass "web/app.css is the expected version before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_92B_END'
--- a/web/app.css
+++ b/web/app.css
@@ -391,6 +391,14 @@
   gap: 1rem;
 } /* end of rule */
 
+/* The title block may shrink and wrap its lines, so the buttons stay at the top right even when there are six of them; below 20rem of title width the buttons drop under the title as before. */
+.headrow > :first-child {
+  /* Take the space that is left beside the buttons; start from nothing so the long line under the title does not push the buttons down. */
+  flex: 1 1 0;
+  /* Never narrower than this; if the buttons need more room, they wrap under the title. */
+  min-width: 20rem;
+} /* end of rule */
+
 /* The last line of the title block leaves no space of its own: the header's gap and the bar below decide the distance, so it is the same 1rem whether the buttons sit beside the title or below it. */
 .headrow #watchline {
   /* No space below the line. */
OCC_PATCH_92B_END

# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched file must be exactly what was tested in the sandbox.
[ "$(sha web/app.css)" = "$AFTER_CSS" ] || fail "web/app.css has an unexpected sha256 after the change"
# Report it.
pass "web/app.css has the expected sha256"

# gofmt lists files whose layout differs from the standard.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code.
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once.
go test -count=1 ./... || fail "go test failed"
# Report it.
pass "go test: all tests pass"

# Build the program for this computer, as the project always does (no C compiler: CGO_ENABLED=0; -trimpath removes folder names).
CGO_ENABLED=0 go build -trimpath -o bin/LLMsControlDock . || fail "go build failed"
# Report it.
pass "build for this computer: bin/LLMsControlDock"

# Compile (without keeping the result) for all six systems; nothing here uses GitHub Actions.
for TARGET in linux/arm64 linux/amd64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Compile; the output goes to /dev/null because only errors matter.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -trimpath -o /dev/null . || fail "compile for $TARGET failed"
  # Report it.
  pass "compile for $TARGET"
# End of the loop over the systems.
done


# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  start bin/LLMsControlDock and look at the top row (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
