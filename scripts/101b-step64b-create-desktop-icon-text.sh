#!/usr/bin/env bash
# Script 101b (small text change): the button on the Settings page reads "Create desktop icon" (not "Create icon") whenever the icon is current; "Update the icon" stays for an out-of-date icon. The page text is simpler (one wording instead of two) and the icon tests follow.
# Run it from the project folder, on the branch feature/small-text-and-key-row (after script 101): cd ~/LLMsControlDock && bash scripts/101b-step64b-create-desktop-icon-text.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 101), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["desktopicon_test.go"]="d4bc9e32c74b7cc08027f4a42722de0cc5afac5eaaa94b4e2cb276d27def539d"
BEFORE["web/settings.html"]="92c8377964ae4908753e48282c1be29d91b7e1ed1f44eb90c10f38b0a7d2d98d"
AFTER["desktopicon_test.go"]="f7f0adb5615b7c82977622acaf0ff577ca7cc6a16652443f1c6fce4f2e15aae9"
AFTER["web/settings.html"]="3985fc59e5167c8d167c74379c44214a2917fd5bc7e4659bd9cd049a80e25332"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/small-text-and-key-row"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 101 must have been applied: the key row exists.
grep -q 'class="keyrow"' web/index.html || fail "script 101 must be applied first"
# Report it.
pass "script 101 (key row) is applied"

# Refuse to run twice: the old wording is gone when this change was applied before.
if ! grep -q 'Create icon' web/settings.html; then fail "web/settings.html no longer has the old button text: this script was already applied"; fi
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
diff --git a/desktopicon_test.go b/desktopicon_test.go
index 4d1ce0e..8c610f6 100644
--- a/desktopicon_test.go
+++ b/desktopicon_test.go
@@ -448,7 +448,7 @@ func TestDesktopBannerAndButtons(t *testing.T) {
 	// The Settings page shows the state, the note and the Remove button.
 	_, _, set := get(t, r.h, http.MethodGet, "/settings?icon=created")
 	// The words.
-	for _, w := range []string{"Desktop icon created. On Ubuntu", "The icon is on your desktop", "Remove desktop icon", "Create icon"} {
+	for _, w := range []string{"Desktop icon created. On Ubuntu", "The icon is on your desktop", "Remove desktop icon", "Create desktop icon"} {
 		// Look for it.
 		if !strings.Contains(set, w) {
 			// Report it.
@@ -605,7 +605,7 @@ func TestDesktopStaleWarningOnPage(t *testing.T) {
 	// The page: no warning.
 	_, _, body := get(t, r.h, http.MethodGet, "/settings")
 	// No warning, the usual button.
-	if strings.Contains(body, "out of date") || strings.Contains(body, "Update the icon") || !strings.Contains(body, "Create icon") {
+	if strings.Contains(body, "out of date") || strings.Contains(body, "Update the icon") || !strings.Contains(body, "Create desktop icon") {
 		// Report it.
 		t.Error("a current launcher shows a warning")
 	} // end of the current check
diff --git a/web/settings.html b/web/settings.html
index b74ddd7..0a4409c 100644
--- a/web/settings.html
+++ b/web/settings.html
@@ -81,7 +81,7 @@
 {{/* The page token proves the form comes from this monitor. */}}
 <input type="hidden" name="token" value="{{.Token}}">
 {{/* The buttons. */}}
-<p><button type="submit" name="action" value="create" class="btn-plain">{{if .IconStale}}Update the icon{{else if .IconExists}}Create icon{{else}}Create desktop icon{{end}}</button>{{if .IconExists}} <button type="submit" name="action" value="remove" class="btn-plain">Remove desktop icon</button>{{end}}</p>
+<p><button type="submit" name="action" value="create" class="btn-plain">{{if .IconStale}}Update the icon{{else}}Create desktop icon{{end}}</button>{{if .IconExists}} <button type="submit" name="action" value="remove" class="btn-plain">Remove desktop icon</button>{{end}}</p>
 {{/* End of the form. */}}
 </form>
 {{end}}
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
echo "NEXT  start bin/LLMsControlDock and look at the Desktop icon section on the Settings page (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
