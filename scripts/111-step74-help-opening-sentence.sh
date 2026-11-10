#!/usr/bin/env bash
# Script 111 (Help page, shorter opening sentence): the opening sentence of the Help page now ends after 'step by step.' (the part about the lanes is removed). One test checks it.
# Run it from the branch feature/help-topics-open-close (after script 110): cd ~/LLMsControlDock && bash scripts/111-step74-help-opening-sentence.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 110), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["help_test.go"]="fd87192e825142ec5691d6008bebcff6d3aa43b3828f34a2135cae9ca9753687"
BEFORE["web/help.html"]="fc0057fc03971e3adbacaa69b804dfc8808879ab3dfe045d218fbd140c82232c"
AFTER["help_test.go"]="d95e1a2da414d65fa2dd3845e9d039cbcd32ad588a38962dbdc71d3a9d8f73b0"
AFTER["web/help.html"]="ccade38e803d313f074b2e1b8a261e0841885231dfe757c6965435527837da1a"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/help-topics-open-close (git switch feature/help-topics-open-close)"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 110 must have been applied: the collapse button script file exists.
[ -e helpclose.go ] || fail "script 110 must be applied first"
# Report it.
pass "script 110 is applied"

# Refuse to run twice: the short sentence is already there when this change was applied before.
if grep -q 'step by step.</p>' web/help.html; then fail "the short sentence is already on the Help page: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# Every file to change must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the project is in another state than expected.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} files to change are the expected versions before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_94_END'
diff --git a/help_test.go b/help_test.go
index 46eb836..feb3d20 100644
--- a/help_test.go
+++ b/help_test.go
@@ -181,6 +181,11 @@ func TestHelpPage(t *testing.T) {
 		// Report.
 		t.Error("the contents list or the old sentence is still on the page")
 	} // end of the old-text check
+	// The opening sentence is the short one, without the sentence about the lanes.
+	if !strings.Contains(body, "Click a topic to open a diagram of what happens, step by step.</p>") || strings.Contains(body, "one lane for each") {
+		// Report.
+		t.Error("the opening sentence of the Help page is not the short one")
+	} // end of the opening sentence check
 	// The monitor links to the Help page.
 	if _, _, main := get(t, rig.h, http.MethodGet, "/"); !strings.Contains(main, `<a class="brandbtn" href="/help">Help</a>`) {
 		// Report.
diff --git a/web/help.html b/web/help.html
index e554152..d7a0b45 100644
--- a/web/help.html
+++ b/web/help.html
@@ -22,7 +22,7 @@
 {{/* The name of the page. */}}
 <h1>Help</h1>
 {{/* What the page is. */}}
-<p class="muted">Click a topic to open a diagram of what happens, step by step. It has one lane for each of you, LLMsControlDock, Ollama and ollama.com, and it reads from the top down.</p>
+<p class="muted">Click a topic to open a diagram of what happens, step by step.</p>
 {{/* The topics; each one starts closed and opens when its title is clicked (no script is needed). */}}
 {{range $t := .Topics}}
 {{/* One topic. */}}
OCC_PATCH_94_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched and new files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} changed or new files have the expected sha256"

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
echo "NEXT  start bin/LLMsControlDock and open the Help page to read the new opening sentence (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
