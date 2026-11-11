#!/usr/bin/env bash
# Script 116 (repository renamed to LLMsControlDock-2): the About page links (source code and licence) and their test, and the Go module name in go.mod, use the new repository name. The product name LLMsControlDock does not change anywhere.
# Run it on a new branch (never main): cd ~/LLMsControlDock && git switch -c feature/repo-name-llmscontroldock-2 && bash scripts/116-step79-repo-name-llmscontroldock-2.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the two Go files BEFORE the change (as on main, version 0.32.0), and AFTER it.
declare -A BEFORE AFTER
BEFORE["about.go"]="de4605651b1d79240fc71be283481b0502507d31817cfe717e0bf9f66f21481a"
BEFORE["about_test.go"]="f157baf46522493f0737d8072a00f24c878272572c8e49c11bf59ca31ef84f67"
AFTER["about.go"]="f9112465be2d34a9546851cd040a176aebfe4e653f11a1093b7d0c756e1e9d1a"
AFTER["about_test.go"]="e0d929b87170dca51cc3bd42e146b212414f12743f0bd2e770145f923f2c7731"
# The module line of go.mod before and after (go.mod is changed by line, so its other lines stay as they are).
OLD_MODULE="module github.com/kodati3shrini3/LLMsControlDock"
NEW_MODULE="module github.com/kodati3shrini3/LLMsControlDock-2"

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
[ "$BRANCH" != "main" ] || fail "you are on main; create a branch first: git switch -c feature/repo-name-llmscontroldock-2"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 115 must be in (its function exists in install.go), so this is the version 0.32.0 code.
grep -q 'func joinReportLines' install.go || fail "this is not the version 0.32.0 code (install.go lacks joinReportLines)"
# Report it.
pass "the code is version 0.32.0 (script 115 is in)"

# Refuse to run twice: the new repository name is already in about.go when this change was applied before.
if grep -q 'kodati3shrini3/LLMsControlDock-2' about.go; then fail "about.go already uses LLMsControlDock-2: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# The first line of go.mod must be exactly the old module line.
[ "$(head -n 1 go.mod)" = "$OLD_MODULE" ] || fail "go.mod line 1 is not '$OLD_MODULE'; tell Claude what it says"
# Report it.
pass "go.mod line 1 is the old module line"

# Each Go file to change must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the project is in another state than expected.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "both Go files are the expected versions before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# The temporary file for the new go.mod.
GOMOD_NEW="$(mktemp)"
# Remove both temporary files at the end, whatever happens.
trap 'rm -f "$PATCH_FILE" "$GOMOD_NEW"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_94_END'
diff --git a/about.go b/about.go
index 90070c3..47793d0 100644
--- a/about.go
+++ b/about.go
@@ -50,7 +50,7 @@ const appLicence = "Apache License 2.0"
 const appLicenceURL = appRepository + "/blob/main/LICENSE"
 
 // appRepository is the address of the source code; the repository is private, so only its owner can open it.
-const appRepository = "https://github.com/kodati3shrini3/LLMsControlDock"
+const appRepository = "https://github.com/kodati3shrini3/LLMsControlDock-2"
 
 // companyName is the developer's company, shown in the header, the footer bar and the About page.
 const companyName = "termGate Consulting"
diff --git a/about_test.go b/about_test.go
index 131665e..692d323 100644
--- a/about_test.go
+++ b/about_test.go
@@ -69,9 +69,9 @@ func TestAboutPageShowsTheRequiredFacts(t *testing.T) {
 		// The copyright holder, the same as in the NOTICE file.
 		"© 2026 termGate Consulting Limited.",
 		// The licence, as a link to the LICENSE file.
-		`href="https://github.com/kodati3shrini3/LLMsControlDock/blob/main/LICENSE" target="_blank" rel="noopener noreferrer">Apache License 2.0<span class="sr-only"> (opens in a new window)</span></a>`,
+		`href="https://github.com/kodati3shrini3/LLMsControlDock-2/blob/main/LICENSE" target="_blank" rel="noopener noreferrer">Apache License 2.0<span class="sr-only"> (opens in a new window)</span></a>`,
 		// The repository link, safe to follow.
-		`href="https://github.com/kodati3shrini3/LLMsControlDock" target="_blank" rel="noopener noreferrer"`,
+		`href="https://github.com/kodati3shrini3/LLMsControlDock-2" target="_blank" rel="noopener noreferrer"`,
 		// The way back.
 		`href="/"`,
 	} { // end of the list
OCC_PATCH_94_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied to about.go and about_test.go"

# The patched files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "both Go files have the expected sha256"

# Build the new go.mod: the new module line, then every other line exactly as it was.
{ echo "$NEW_MODULE"; tail -n +2 go.mod; } > "$GOMOD_NEW"
# Put it in place.
cp "$GOMOD_NEW" go.mod
# Line 1 must now be the new module line.
[ "$(head -n 1 go.mod)" = "$NEW_MODULE" ] || fail "go.mod line 1 was not changed"
# The go version line must still be there.
grep -q '^go ' go.mod || fail "the go line of go.mod is missing"
# Report it.
pass "go.mod line 1 changed to the new module name; other lines kept"

# No file outside scripts/ may still name the old repository (the new name starts with the old one, so the pattern needs a character other than a dash after it).
if git grep -InE 'kodati3shrini3/LLMsControlDock([^-A-Za-z0-9]|$)' -- . ':!scripts'; then fail "the old repository name is still used in the lines above"; fi
# Report it.
pass "the old repository name is not used any more outside scripts/"

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
echo "NEXT  start bin/LLMsControlDock, open the About page and check the two links (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
