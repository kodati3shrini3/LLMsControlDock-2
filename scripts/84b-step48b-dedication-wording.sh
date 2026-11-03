#!/usr/bin/env bash
# Script 84b (new wording of the dedication on the About page): the dedication now reads "Dedicated to my daughter Meghna, without whom I would never have had the inspiration to develop this." It changes the text in about.go and the test that checks it in about_test.go. Nothing else changes, and the version stays 0.30.0. It must be run on the branch where script 84 was already applied.
# Run it from the project folder, on the feature branch (never on main): cd ~/OllamaControlCenter && bash scripts/84b-step48b-dedication-wording.sh

# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the two files BEFORE the change (about.go as left by script 84).
EXPECT_ABOUT_BEFORE="da3ee399e59098ef3a22a014690075a1121510e7a1e868731ff8162e4731d4f9"
# about_test.go before the change.
EXPECT_TEST_BEFORE="3d59b289b38e40814b08b74fad6988fe22c5e3dac51ed3c965ef968ed2450eac"
# The expected sha256 of the two files AFTER the change.
EXPECT_ABOUT_AFTER="1f17ff5ac6a4053eeafd6f5701d77c7adb8d8f56fbcf106187b78b4185c9fbaa"
# about_test.go after the change.
EXPECT_TEST_AFTER="107965d01a1834b3b75b095b7ea24a5921665d46a5e0d098ec85412fd5cbd0f2"

# Count of passed checks, for the summary at the end.
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
# The project must be OllamaControlCenter: its main.go and go.mod must be here.
[ -f main.go ] && [ -f go.mod ] || fail "this is not the OllamaControlCenter folder (main.go or go.mod missing)"
# Say where we are.
echo "Project folder: $(pwd)"

# The branch we are on.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# Never change main directly: every change goes through a branch and a pull request.
[ "$BRANCH" != "main" ] || fail "you are on main; this script belongs on feature/environment-requirements"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 84 must have been applied: its new file exists.
[ -e environment.go ] || fail "environment.go is missing: run script 84 first"
# Report it.
pass "script 84 was applied (environment.go exists)"

# Refuse to run twice: the new wording is already there when the change was applied before.
if grep -q 'my daughter Meghna' about.go; then fail "the new dedication is already in about.go: this script was already applied"; fi
# Report it.
pass "the old dedication is still in place (script not applied before)"

# The files must be exactly the ones the change was made against.
[ "$(sha about.go)" = "$EXPECT_ABOUT_BEFORE" ] || fail "about.go is not the expected version (sha256 differs); tell Claude which state you are in"
# about_test.go.
[ "$(sha about_test.go)" = "$EXPECT_TEST_BEFORE" ] || fail "about_test.go is not the expected version (sha256 differs); tell Claude which state you are in"
# Report it.
pass "about.go and about_test.go are the expected versions before the change"

# A temporary file for the patch, removed when the script ends (also on an error).
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_84B_END'
diff --git a/about.go b/about.go
index 5337711..de7b257 100644
--- a/about.go
+++ b/about.go
@@ -38,7 +38,7 @@ const appDeveloperProfile = "https://www.linkedin.com/in/shrinikodati/"
 const appAssistant = "Claude (Sonnet 5.5), Anthropic"
 
 // appDedication is the dedication shown on the About page.
-const appDedication = "Dedicated to Ms. Meghna Kodati, without whom I would never have had the inspiration to develop this."
+const appDedication = "Dedicated to my daughter Meghna, without whom I would never have had the inspiration to develop this."
 
 // appCopyright is the copyright line shown on the About page.
 const appCopyright = "© 2026 Shrinivas Kodati. All rights reserved."
diff --git a/about_test.go b/about_test.go
index 423f487..0ec0157 100644
--- a/about_test.go
+++ b/about_test.go
@@ -57,7 +57,7 @@ func TestAboutPageShowsTheRequiredFacts(t *testing.T) {
 		// The assistant with its version.
 		"Claude (Sonnet 5.5), Anthropic",
 		// The dedication, exactly as the developer wrote it.
-		"Dedicated to Ms. Meghna Kodati, without whom I would never have had the inspiration to develop this.",
+		"Dedicated to my daughter Meghna, without whom I would never have had the inspiration to develop this.",
 		// The version.
 		appVersion,
 		// The short revision, twelve characters.
OCC_PATCH_84B_END

# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched files must be exactly what was tested in the sandbox.
[ "$(sha about.go)" = "$EXPECT_ABOUT_AFTER" ] || fail "about.go has an unexpected sha256 after the change"
# about_test.go after the change.
[ "$(sha about_test.go)" = "$EXPECT_TEST_AFTER" ] || fail "about_test.go has an unexpected sha256 after the change"
# Report it.
pass "the two changed files have the expected sha256"

# gofmt -l lists files that are not formatted; no output means all are formatted.
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
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter . || fail "go build failed"
# Report it.
pass "build for this computer: bin/OllamaControlCenter"

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
echo "NEXT  start the monitor, open http://127.0.0.1:8765/about and read the dedication (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
