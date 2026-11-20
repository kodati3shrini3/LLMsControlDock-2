#!/usr/bin/env bash
# Script 134 (Help: Pause/Resume and the About estimate): adds one sentence to the Settings Help topic about the Pause and Resume of the monitor page, one sentence to the System check Help topic about the estimate on the About page, and a test that keeps both in the Help (help.go, help_test.go).
# Run it on your branch for release 0.34.0 (never main): cd ~/LLMsControlDock-2 && bash scripts/134-step96-help-pause-and-estimate.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the two files BEFORE the change and AFTER it.
declare -A BEFORE AFTER
BEFORE["help.go"]="672099db7e0d054b2bcad36d0fdeb8bdb4a6deb4f7a83b914f5437d25cad8dbb"
BEFORE["help_test.go"]="422e1b9cf6cb5233917a48254f2d6ada5ffee017f3ab101f12271b525e69ea59"
AFTER["help.go"]="b27aa6073aedc5536abb321f0edd100fb92d49f0cd8c51e2d220d91eed2ac54b"
AFTER["help_test.go"]="5b2c082fb5e26be4c90e539327b19652c16a18a237e4c2643f354e4cf127c662"

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

# Script 131 must be applied (its Help sort sentence is the sign).
grep -q 'newest first' help.go || fail "script 131 is not applied (the Help sort sentence is missing)"
# Report it.
pass "script 131 is applied"

# Refuse to run twice: the Pause sentence is the sign.
if grep -q 'Pause button' help.go; then fail "help.go already has the Pause sentence: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# Every existing file must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the file is not the expected version.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} existing files are the expected version"

# The files that are already changed (earlier scripts are not committed yet); kept to compare afterwards.
CHANGED_BEFORE="$(git diff --name-only | LC_ALL=C sort)"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_134_END'
diff --git a/help.go b/help.go
--- a/help.go
+++ b/help.go
@@ -127,7 +127,7 @@
 	{
 		ID:    "system-check",
 		Title: "System check: what this computer offers",
-		Intro: "The first time the program starts, it shows this report before the monitor. It lists the processors, memory and graphics cards of this computer, checks that Ollama is found and states what the tool needs. If a problem stops the tool from working fully, an alert lists the steps to fix it. The report stays available later in the footer bar.",
+		Intro: "The first time the program starts, it shows this report before the monitor. It lists the processors, memory and graphics cards of this computer, checks that Ollama is found and states what the tool needs. If a problem stops the tool from working fully, an alert lists the steps to fix it. The report stays available later in the footer bar. On the About page, the button Estimate what this program uses runs it again and adds what the operating system reports for this program; the figures are an estimate from that one run, and the models that Ollama holds are not counted.",
 		Steps: []helpStep{
 			{0, "Start LLMsControlDock for the first time."},
 			{1, "Opens the System check before the monitor."},
@@ -312,7 +312,7 @@
 	{
 		ID:    "settings",
 		Title: "Settings",
-		Intro: "Settings holds the Ollama address, the check interval, the timeout, the chart history and the access from other machines. Values marked restart are used the next time the monitor starts; the others apply at once. The desktop icon is created, updated or removed on the same page.",
+		Intro: "Settings holds the Ollama address, the check interval, the timeout, the chart history and the access from other machines. Values marked restart are used the next time the monitor starts; the others apply at once. The desktop icon is created, updated or removed on the same page. The monitor page updates itself every 10 seconds; its Pause button stops that, the choice is remembered in this browser for a year, and Resume starts it again. The page also pauses by itself while the key to the symbols or the numbers of the charts are open.",
 		Steps: []helpStep{
 			{0, "Press Settings in the monitor's top bar."},
 			{1, "Shows each setting: in use now, new value and default."},
diff --git a/help_test.go b/help_test.go
--- a/help_test.go
+++ b/help_test.go
@@ -436,3 +436,23 @@
 		} // end of the phrase check
 	} // end of the phrase loop
 } // end of TestHelpFindLLMIntroNamesTheNewBehaviour
+
+// TestHelpNamesPauseAndTheAboutEstimate keeps two small features in the Help: the Pause and Resume of the monitor page (Settings topic) and the estimate on the About page (System check topic).
+func TestHelpNamesPauseAndTheAboutEstimate(t *testing.T) {
+	// The wanted phrases per topic: each stands for one thing the pages do.
+	want := map[string][]string{
+		"settings":     {"Pause button", "Resume", "every 10 seconds", "pauses by itself"},
+		"system-check": {"About page", "Estimate what this program uses", "estimate from that one run", "Ollama holds are not counted"},
+	}
+	// Look through all topics.
+	for _, tp := range helpTopics {
+		// Only the two topics above are wanted.
+		for _, phrase := range want[tp.ID] {
+			// A missing phrase means the Help text no longer matches the page.
+			if !strings.Contains(tp.Intro, phrase) {
+				// Report.
+				t.Errorf("the %s help introduction does not say %q", tp.ID, phrase)
+			} // end of the phrase check
+		} // end of the phrase loop
+	} // end of the topic loop
+} // end of TestHelpNamesPauseAndTheAboutEstimate
OCC_PATCH_134_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} changed files have the expected sha256"

# Only these two files may be newly changed (earlier changes stay).
CHANGED_AFTER="$(git diff --name-only | LC_ALL=C sort)"
# The expected list is the earlier list plus the two files, sorted and without doubles.
EXPECTED="$( { echo "$CHANGED_BEFORE"; echo help.go; echo help_test.go; } | sed '/^$/d' | LC_ALL=C sort -u)"
# Anything else is a failure.
[ "$CHANGED_AFTER" = "$EXPECTED" ] || fail "other files changed than expected: $CHANGED_AFTER"
# Report it.
pass "only help.go and help_test.go were newly changed"

# The key lines must be in place.
grep -q 'Estimate what this program uses runs it again' help.go && grep -q 'TestHelpNamesPauseAndTheAboutEstimate' help_test.go || fail "a key line of the change is missing"
# Report it.
pass "the two Help sentences and their test are in place"

# The word the owner does not want in documents must not be in the new text.
if git diff -- help.go help_test.go | grep '^+' | grep -q 'KISS'; then fail "the forbidden word is in the new text"; fi
# Report it.
pass "the new text does not use the forbidden word"

# gofmt lists files whose layout differs from the standard.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code (and compiles the tests).
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once; a timing failure of TestTableColumnOrder or TestDeleteConfirmRefusesLoadedModel is reported and not hidden.
go test -count=1 ./... || fail "go test failed (if only TestTableColumnOrder or TestDeleteConfirmRefusesLoadedModel failed, run the tests once more and tell Claude)"
# Report it.
pass "go test: all tests pass"

# Build the program for all six systems.
for TARGET in linux/amd64 linux/arm64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Build to nowhere (/dev/null) just to see that it compiles.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -o /dev/null . || fail "build for $TARGET failed"
  # Report it.
  pass "program builds for $TARGET"
# End of the loop over the systems.
done

# The summary.
echo "Result: $PASS passed, 0 failed"
# What to do next.
echo "NEXT  rebuild the program and look at the Help page by hand (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
