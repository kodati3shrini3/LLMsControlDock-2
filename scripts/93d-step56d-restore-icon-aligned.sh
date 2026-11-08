#!/usr/bin/env bash
# Script 93d (Find LLM, change after slice 3): the restore icon in the Deleted models rows sits level with the struck-through name. Before, the icon was in the lower of two slots (an empty slot above it), so it hung below the name; now the empty slot is gone and the icon is lifted three pixels to line up with the middle of the name. Only the page layout changes: no wording, no action, no new test.
# Run it from the project folder, on the branch feature/find-llm-tags after script 93c: cd ~/LLMsControlDock && bash scripts/93d-step56d-restore-icon-aligned.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 93c), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["web/app.css"]="f633347e14555f41d97ff4cd9ce7407dd2f92ccc0c7a96d9c8be8102bcd81705"
BEFORE["web/index.html"]="18a71003c3ea367e73944fb9f587f19bceec1524efdcb505d23825a7636837f4"
AFTER["web/app.css"]="af63391bef443005975b09f9fef4e2b55c44e6c33f78386bceeb6684371904d7"
AFTER["web/index.html"]="33566ee36a94f081ec68a6e916c5f1b408cab0fcacf876da7875f6b1868975e5"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/find-llm-tags"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 93c must have been applied: the icon colour variable exists.
grep -q 'icon-tag' web/app.css || fail "script 93c must be applied first"
# Report it.
pass "script 93c (coloured icons) is applied"

# Refuse to run twice: the new rule exists when this change was applied before.
if grep -q 'ghostrow .iconstack' web/app.css; then fail "web/app.css already has the restore icon rule: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_93D_END'
diff --git a/web/app.css b/web/app.css
index b9d4267..e64163f 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1445,6 +1445,14 @@ button.btn-plain {
   opacity: 0.75;
 } /* end of rule */
 
+/* The restore icon is alone in its column, so it is lifted a little to sit exactly level with the middle of the struck name. */
+.ghostrow .iconstack {
+  /* A box that can be moved without moving the text around it. */
+  position: relative;
+  /* Up by three pixels: the icon box is a little taller than the name's line. */
+  top: -3px;
+} /* end of rule */
+
 /* The deletion note under the struck name. */
 .ghostnote {
   /* Smaller than the name. */
diff --git a/web/index.html b/web/index.html
index 054afde..e3274d4 100644
--- a/web/index.html
+++ b/web/index.html
@@ -565,9 +565,8 @@
 {{/* A greyed row; it has no data-model, so the refresh script ignores it. */}}
 <tr class="ghostrow" data-deleted="{{.Name}}">
 <th scope="row" class="stickycol">
-{{/* The same icon column: an empty slot where the performance icon is, the restore icon where the delete icon is. */}}
+{{/* The same icon column width as the other rows; the restore icon is alone in it, so it sits level with the struck name. */}}
 <span class="iconstack">
-<span class="gearslot" aria-hidden="true"></span>
 {{/* A small form that sends the model name and the page token to the restore page, which changes nothing. */}}
 <form class="gearform" method="post" action="/restore">
 {{/* The page token proves the form comes from this monitor. */}}
OCC_PATCH_93D_END
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
echo "NEXT  start bin/LLMsControlDock and look at the restore icon in the Deleted models rows (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
