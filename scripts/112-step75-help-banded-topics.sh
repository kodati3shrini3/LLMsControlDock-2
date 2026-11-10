#!/usr/bin/env bash
# Script 112 (Help page, banded topics): every second topic on the Help page gets the same soft blue band as the category rows, and the open topic gets an accent bar at its left edge, so the topics are easy to tell apart. Only the style sheet changes; colours exist for light and dark. One test follows.
# Run it from the branch feature/help-topics-open-close (after script 111): cd ~/LLMsControlDock && bash scripts/112-step75-help-banded-topics.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 111), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["help_test.go"]="d95e1a2da414d65fa2dd3845e9d039cbcd32ad588a38962dbdc71d3a9d8f73b0"
BEFORE["web/app.css"]="5848f24471badf8631f2fcee1510acf7878cafeea9336b477d3829d6a24fc030"
AFTER["help_test.go"]="4df71b19a0841d4aaac1e94a3134d67ee36a3cdb4205891799cd8c2a3ba3125b"
AFTER["web/app.css"]="8a87e5ddb121243b5925627b430fdeb7d86f5aec62fd8be93ef0891e14f42bb8"

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

# Script 111 must have been applied: the short opening sentence is on the Help page.
grep -q 'step by step.</p>' web/help.html || fail "script 111 must be applied first"
# Report it.
pass "script 111 is applied"

# Refuse to run twice: the band rule is already in the style sheet when this change was applied before.
if grep -q 'details.helptopic:nth-of-type(even)' web/app.css; then fail "the band rule is already in the style sheet: this script was already applied"; fi
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
index feb3d20..bb266e4 100644
--- a/help_test.go
+++ b/help_test.go
@@ -255,3 +255,45 @@ func TestHelpCloseScriptIsServedAndHarmless(t *testing.T) {
 		} // end of the comment check
 	} // end of the line loop
 } // end of TestHelpCloseScriptIsServedAndHarmless
+
+// TestHelpTopicsAreBanded checks the style sheet tints every second topic and marks the open one, with colours that exist in all three colour sets and stay readable.
+func TestHelpTopicsAreBanded(t *testing.T) {
+	// Get the style sheet the way a browser does.
+	rig := newThemeRig(t)
+	// Fetch it.
+	_, _, css := get(t, rig.h, http.MethodGet, "/app.css")
+	// The three rules must exist.
+	for _, want := range []string{"details.helptopic:nth-of-type(even) {", "background: var(--cat-bg);", "details.helptopic[open] {", "border-left-color: var(--cat-accent);", "border-left: 6px solid transparent;"} {
+		// Look for it.
+		if !strings.Contains(css, want) {
+			// Report.
+			t.Errorf("the style sheet lacks %q", want)
+		} // end of the look
+	} // end of the loop
+	// The band and bar colours must be set in the light set, the automatic dark set and the chosen dark set: each variable appears three times.
+	for _, name := range []string{"--cat-bg:", "--cat-accent:"} {
+		// Count the definitions.
+		if n := strings.Count(css, name); n != 3 {
+			// Report.
+			t.Errorf("%s is defined %d times, want 3 (light, automatic dark, chosen dark)", name, n)
+		} // end of the count
+	} // end of the loop
+	// The text must stay readable on the band: at least 7:1 (AAA) in both sets, using the colours the sheet defines.
+	for _, th := range []struct{ name, band, text, muted string }{{"light", "#dbe7f5", "#1a1a1a", "#4a4f57"}, {"dark", "#1f3550", "#ececec", "#b8bdc5"}} {
+		// The band colour must really be the one the sheet defines.
+		if !strings.Contains(css, "--cat-bg: "+th.band+";") {
+			// Report.
+			t.Errorf("%s: the band colour %s is not defined", th.name, th.band)
+		} // end of the colour check
+		// The main text on the band.
+		if r := contrastOf(th.text, th.band); r < 7 {
+			// Report.
+			t.Errorf("%s: text on the band has contrast %.1f, want at least 7", th.name, r)
+		} // end of the text contrast
+		// The secondary text on the band, at least 4.5:1.
+		if r := contrastOf(th.muted, th.band); r < 4.5 {
+			// Report.
+			t.Errorf("%s: secondary text on the band has contrast %.1f, want at least 4.5", th.name, r)
+		} // end of the muted contrast
+	} // end of the loop
+} // end of TestHelpTopicsAreBanded
diff --git a/web/app.css b/web/app.css
index 4faefb3..9f7693a 100644
--- a/web/app.css
+++ b/web/app.css
@@ -3045,10 +3045,28 @@ html[data-size="medium"] svg[width="22"] {
   position: relative;
 } /* end of rule */
 
-/* One topic on the Help page. */
+/* One topic on the Help page: a block of its own, with a transparent bar on the left so that opening a topic does not move anything. */
 .helptopic {
-  /* Space above the topic. */
-  margin: 1.5rem 0;
+  /* A small space between the topics, so the bands read as separate blocks. */
+  margin: 0.4rem 0;
+  /* Room inside the block. */
+  padding: 0.1rem 0.9rem 0.1rem 0.7rem;
+  /* The bar on the left: invisible while the topic is closed, so the text does not shift when it opens. */
+  border-left: 6px solid transparent;
+  /* Slightly rounded corners, like the other boxes. */
+  border-radius: 0.5rem;
+} /* end of rule */
+
+/* Every second topic is tinted with the same soft blue band as the category rows (text contrast 13.9:1 in light, 10.6:1 in dark). */
+details.helptopic:nth-of-type(even) {
+  /* The band colour from the variables, set for light and dark. */
+  background: var(--cat-bg);
+} /* end of rule */
+
+/* The open topic shows the accent bar at its left edge (the same colour as the category rows), so the long diagram's start and end are easy to see. */
+details.helptopic[open] {
+  /* The accent colour from the variables, set for light and dark. */
+  border-left-color: var(--cat-accent);
 } /* end of rule */
 
 /* The swimlane picture: as wide as the card, never wider, so the page does not scroll sideways. */
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
echo "NEXT  start bin/LLMsControlDock and open the Help page and look at the banded topics (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
