#!/usr/bin/env bash
# Script 102 (tooltips on a scrolled page): every help bubble is now tied to its own heading box, so it opens right next to the heading even when the page is scrolled (before, a plain fixed bubble stayed where the heading was before scrolling and could be far off the screen). Heading bubbles open below the heading, flip upwards or to the other side when there is no room, and span the window on a narrow screen. One new test.
# Run it from the project folder, on a new branch made from main (not on main): cd ~/LLMsControlDock && bash scripts/102-step65-tooltips-follow-heading.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as on main after PR 43), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["key_test.go"]="29c8db21da9707d1d612fc8baf064056542acd478ecfda18cd20e6aa0568225b"
BEFORE["web/app.css"]="5641d45b3cf65a45ca65547d243da46723fee1362e1f59994e1c2b4f2a03327c"
AFTER["key_test.go"]="84f8929091ef3d700932a42bedda4192891638c504a6d7de166659b54fe37a16"
AFTER["web/app.css"]="b95cf563d010554c8c8fc8539edc46393c435d356ee10e3e458a698b181411e7"

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
[ "$BRANCH" != "main" ] || fail "you are on main; make a new branch first: git switch -c feature/tooltips-follow-heading"
# Report the branch.
pass "on branch $BRANCH (not main)"

# The merged work must be here: the Sort by choice exists.
grep -q 'func modelBefore' findllm.go || fail "the merged Find LLM work (PR 42) must be here: update main first"
# Report it.
pass "the merged Find LLM work is here"

# Refuse to run twice: the heading bubble rule exists when this change was applied before.
if grep -q '.tip:not(.tip-icon) {' web/app.css; then fail "web/app.css already has the heading bubble rule: this script was already applied"; fi
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
diff --git a/key_test.go b/key_test.go
index 1a97108..8b655eb 100644
--- a/key_test.go
+++ b/key_test.go
@@ -93,3 +93,45 @@ func TestTagsHelpAlwaysShown(t *testing.T) {
 		t.Error("the style for the key row is missing")
 	} // end of the style check
 } // end of TestTagsHelpAlwaysShown
+
+// TestTipsFollowTheirHeading: every help bubble is tied to its own heading box, so it stays next to the heading when the page is scrolled (a plain fixed bubble stays far off the screen).
+func TestTipsFollowTheirHeading(t *testing.T) {
+	// Read the style file.
+	raw, err := os.ReadFile("web/app.css")
+	// The file must be readable.
+	if err != nil {
+		// Report it.
+		t.Fatal(err)
+	} // end of the read check
+	// The text of the style file.
+	css := string(raw)
+	// The rule of the heading box (.tipbox) must make the box an anchor with a private name.
+	box := css[strings.Index(css, ".tipbox {"):]
+	// Cut the rule at its end marker.
+	box = box[:strings.Index(box, "} /* end of rule */")]
+	// Both anchor lines must be in this rule.
+	for _, want := range []string{"anchor-name: --tipicon;", "anchor-scope: --tipicon;"} {
+		// Report a missing line.
+		if !strings.Contains(box, want) {
+			t.Errorf(".tipbox rule lacks %q", want)
+		} // end of the line check
+	} // end of the loop over the anchor lines
+	// The rule of the heading bubbles (not icon bubbles) must tie them to that anchor and open them below it.
+	at := strings.Index(css, ".tip:not(.tip-icon) {")
+	// The rule must exist.
+	if at < 0 {
+		// Nothing more to check.
+		t.Fatal("the rule for heading bubbles is missing")
+	} // end of the existence check
+	// Cut the rule at its end marker.
+	rule := css[at:]
+	// Only this rule.
+	rule = rule[:strings.Index(rule, "} /* end of rule */")]
+	// The lines that tie the bubble to its heading.
+	for _, want := range []string{"position-anchor: --tipicon;", "top: anchor(bottom);", "left: anchor(left);", "transform: none;", "position-try-fallbacks:"} {
+		// Report a missing line.
+		if !strings.Contains(rule, want) {
+			t.Errorf("heading bubble rule lacks %q", want)
+		} // end of the line check
+	} // end of the loop over the bubble lines
+} // end of TestTipsFollowTheirHeading
diff --git a/web/app.css b/web/app.css
index d132dc9..5cc4190 100644
--- a/web/app.css
+++ b/web/app.css
@@ -302,6 +302,10 @@ h2 {
   position: relative;
   /* Only as wide as its content, so the pointer must be on the heading. */
   display: inline-block;
+  /* Every heading box is its own anchor: its bubble is tied to it, so the bubble follows it when the page scrolls. */
+  anchor-name: --tipicon;
+  /* Keep the name private to this box, so the bubbles of other boxes never get mixed up. */
+  anchor-scope: --tipicon;
 } /* end of rule */
 
 /* The category heading box stays at the left edge while the table scrolls sideways. */
@@ -358,6 +362,22 @@ h2 {
   z-index: 10;
 } /* end of rule */
 
+/* A bubble that is not an icon bubble is tied to its own heading too: it opens just below the heading and follows it when the page scrolls (a plain fixed bubble stays where the heading was before scrolling, which can be far off the screen). */
+.tip:not(.tip-icon) {
+  /* The bubble is tied to the box of its own heading. */
+  position-anchor: --tipicon;
+  /* Its top edge sits on the bottom edge of the heading, so it opens downwards... */
+  top: anchor(bottom);
+  /* ...and its left edge lines up with the heading. */
+  left: anchor(left);
+  /* No centring shift: the older rule moved it left by half its width. */
+  transform: none;
+  /* A little gap between the heading and the bubble. */
+  margin: 0.25rem 0 0 0;
+  /* If there is no room below, open upwards; if there is no room to the right, line up with the right edge of the heading instead. */
+  position-try-fallbacks: flip-block, flip-inline, flip-block flip-inline;
+} /* end of rule */
+
 /* Show the bubble when the pointer is over the area or when the keyboard focus is inside it. */
 .tipbox:hover > .tip,
 .tipbox:focus-within > .tip { /* ...or when the focus is inside it. */
@@ -1129,8 +1149,8 @@ button.btn-plain {
 
 /* On a narrow window the bubble spans the window width instead, so it is never cut at the right edge. */
 @media (max-width: 40rem) {
-  /* The icon bubble. */
-  .tip-icon {
+  /* The icon bubble and the heading bubble. */
+  .tip-icon, .tip:not(.tip-icon) {
     /* Start near the left edge. */
     left: 0.5rem;
     /* End near the right edge. */
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
echo "NEXT  start bin/LLMsControlDock, scroll down and point at \"How models are grouped\" and at the column headings (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
