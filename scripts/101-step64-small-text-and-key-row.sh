#!/usr/bin/env bash
# Script 101 (small text changes): on the Settings page the button "Create the icon again" is now "Create icon"; on the main page the line "Tags under each name: How models are grouped" now sits at the right end of the same row as "Key to the symbols (click to hide)" and is visible whether the key is open or closed (on a narrow window it drops below). One new test, and the existing icon test follows the new button text.
# Run it from the project folder, on a new branch made from main (not on main): cd ~/LLMsControlDock && bash scripts/101-step64-small-text-and-key-row.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as on main after PR 42), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["desktopicon_test.go"]="43e02c68b8aed00daa03bb1af44d6944e643636c3e9499b0da3b6e0cd1193315"
BEFORE["key_test.go"]="0500642c544d86ee33c69073005a4af2dff7f37ee8157ec1181db7ade66267d7"
BEFORE["web/app.css"]="be813c41615b4882394c7b1f533c3bc2daeb0c318d47ee3d62696e26b39d0a03"
BEFORE["web/index.html"]="f9f3b8f7245f73790d0f94a0efc4f075b78e48a874073e7439b9ff2bb0f150e2"
BEFORE["web/settings.html"]="cff1496516e8b056e82dfd00f17504c0d693a5d6d42701e43fbc8af55c57b1ee"
AFTER["desktopicon_test.go"]="d4bc9e32c74b7cc08027f4a42722de0cc5afac5eaaa94b4e2cb276d27def539d"
AFTER["key_test.go"]="29c8db21da9707d1d612fc8baf064056542acd478ecfda18cd20e6aa0568225b"
AFTER["web/app.css"]="5641d45b3cf65a45ca65547d243da46723fee1362e1f59994e1c2b4f2a03327c"
AFTER["web/index.html"]="7d728a5b7903e355b38c763c9d53688d5bfc3590ddf0e880956ee448d9904ba5"
AFTER["web/settings.html"]="92c8377964ae4908753e48282c1be29d91b7e1ed1f44eb90c10f38b0a7d2d98d"

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
[ "$BRANCH" != "main" ] || fail "you are on main; make a new branch first: git switch -c feature/small-text-and-key-row"
# Report the branch.
pass "on branch $BRANCH (not main)"

# The merged work must be here: the Sort by choice exists.
grep -q 'func modelBefore' findllm.go || fail "the merged Find LLM work (PR 42) must be here: update main first"
# Report it.
pass "the merged Find LLM work is here"

# Refuse to run twice: the key row exists when this change was applied before.
if grep -q 'class="keyrow"' web/index.html; then fail "web/index.html already has the key row: this script was already applied"; fi
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
index 49baaf2..4d1ce0e 100644
--- a/desktopicon_test.go
+++ b/desktopicon_test.go
@@ -448,7 +448,7 @@ func TestDesktopBannerAndButtons(t *testing.T) {
 	// The Settings page shows the state, the note and the Remove button.
 	_, _, set := get(t, r.h, http.MethodGet, "/settings?icon=created")
 	// The words.
-	for _, w := range []string{"Desktop icon created. On Ubuntu", "The icon is on your desktop", "Remove desktop icon", "Create the icon again"} {
+	for _, w := range []string{"Desktop icon created. On Ubuntu", "The icon is on your desktop", "Remove desktop icon", "Create icon"} {
 		// Look for it.
 		if !strings.Contains(set, w) {
 			// Report it.
@@ -605,7 +605,7 @@ func TestDesktopStaleWarningOnPage(t *testing.T) {
 	// The page: no warning.
 	_, _, body := get(t, r.h, http.MethodGet, "/settings")
 	// No warning, the usual button.
-	if strings.Contains(body, "out of date") || strings.Contains(body, "Update the icon") || !strings.Contains(body, "Create the icon again") {
+	if strings.Contains(body, "out of date") || strings.Contains(body, "Update the icon") || !strings.Contains(body, "Create icon") {
 		// Report it.
 		t.Error("a current launcher shows a warning")
 	} // end of the current check
diff --git a/key_test.go b/key_test.go
index aeb9cdc..1a97108 100644
--- a/key_test.go
+++ b/key_test.go
@@ -4,6 +4,8 @@ package main
 import ( // import lists the standard-library packages this file uses.
 	// net/http provides the request method names.
 	"net/http"
+	// os reads the style file.
+	"os"
 	// strings searches the pages.
 	"strings"
 	// testing is Go's test framework.
@@ -52,3 +54,42 @@ func TestKeyTwistie(t *testing.T) {
 		t.Errorf("an odd value opened the key or was echoed")
 	} // end of the odd check
 } // end of TestKeyTwistie
+
+// TestTagsHelpAlwaysShown: the line "Tags under each name" sits in the same row as the key twistie, and is drawn whether the key is open or closed.
+func TestTagsHelpAlwaysShown(t *testing.T) {
+	// A fake Ollama and a rig.
+	rig, _ := perfRig(t, newPerfFake())
+	// The page as it first opens, and with the key opened.
+	_, _, closed := get(t, rig.h, http.MethodGet, "/")
+	_, _, open := get(t, rig.h, http.MethodGet, "/?key=open")
+	// Both pages must have the row, the twistie first and the tags help after it, inside the same row.
+	for name, page := range map[string]string{"closed": closed, "open": open} {
+		// Where the row starts, where the twistie is, where the tags line is, and where the row ends.
+		row := strings.Index(page, `<div class="keyrow">`)
+		toggle := strings.Index(page, `<p class="keytoggle" id="key">`)
+		tags := strings.Index(page, `<p class="muted groupedhelp">Tags under each name:`)
+		end := strings.Index(page[max(row, 0):], "</div>")
+		// Every part must exist, in this order, and the row must close after the tags line.
+		if row < 0 || toggle < row || tags < toggle || end < 0 || row+end < tags {
+			// Report which page failed.
+			t.Errorf("%s page: the key row is wrong (row %d, twistie %d, tags %d)", name, row, toggle, tags)
+		} // end of the order check
+		// The words of the tags line must be visible.
+		if !strings.Contains(page, "How models are grouped") {
+			// Report it.
+			t.Errorf("%s page lacks the words How models are grouped", name)
+		} // end of the words check
+	} // end of the loop over the two pages
+	// The row has a style that puts the two parts at the two ends.
+	css, err := os.ReadFile("web/app.css")
+	// The file must be readable.
+	if err != nil {
+		// Report it.
+		t.Fatal(err)
+	} // end of the read check
+	// The rule must hold the two-ends layout.
+	if !strings.Contains(string(css), ".keyrow {") || !strings.Contains(string(css), "justify-content: space-between;") {
+		// Report it.
+		t.Error("the style for the key row is missing")
+	} // end of the style check
+} // end of TestTagsHelpAlwaysShown
diff --git a/web/app.css b/web/app.css
index 2938dbe..d132dc9 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2049,6 +2049,20 @@ html[data-size="medium"] svg[width="22"] {
   overflow-wrap: anywhere;
 } /* end of rule */
 
+/* The row above the key: the twistie at one end and the tags help at the other, wrapping on a narrow window. */
+.keyrow {
+  /* The two parts sit in a row. */
+  display: flex;
+  /* The twistie goes to the left end and the tags help to the right end. */
+  justify-content: space-between;
+  /* Level with each other. */
+  align-items: center;
+  /* On a narrow window the second part drops below the first. */
+  flex-wrap: wrap;
+  /* Space between the parts when they wrap. */
+  gap: 0 1.5rem;
+} /* end of rule */
+
 /* The twistie line above the key: a small arrow, the name and a hint, all one link. */
 .keytoggle {
   /* Space above and below. */
@@ -2952,3 +2966,9 @@ html[data-size="medium"] svg[width="22"] {
   /* Space between the button and the choice. */
   margin-left: 1rem;
 } /* end of rule */
+
+/* The tags help line inside the row has the same space above and below as the twistie, so both sit level. */
+.keyrow .groupedhelp {
+  /* Same space as the twistie line. */
+  margin: 0.4rem 0 0.75rem;
+} /* end of rule */
diff --git a/web/index.html b/web/index.html
index fc2023d..785d34a 100644
--- a/web/index.html
+++ b/web/index.html
@@ -352,13 +352,16 @@
 {{/* A hint above the table so people know the dotted headings have help. */}}
 {{/* A key above the table: what each symbol and the dotted headings do. */}}
 {{/* The twistie: a plain link that opens or closes the key; the program draws the page again, so no script is needed. */}}
+{{/* One row: the twistie at the left end, the tags help at the right end; both are drawn whether the key is open or closed. */}}
+<div class="keyrow">
 {{if .KeyOpen}}
 <p class="keytoggle" id="key"><a href="/#key"><span aria-hidden="true">&#9662;</span> Key to the symbols <span class="keyhint">(click to hide)</span></a></p>
 {{else}}
 <p class="keytoggle" id="key"><a href="/?key=open#key"><span aria-hidden="true">&#9656;</span> Key to the symbols <span class="keyhint">(click to show)</span></a></p>
 {{end}}
-{{/* The help line for the tags under the model names. */}}
+{{/* The help line for the tags under the model names (always shown, at the right end of the row). */}}
 <p class="muted groupedhelp">Tags under each name: <span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Table.GroupedTip.ID}}">How models are grouped</span><span class="tip" role="tooltip" id="{{.Table.GroupedTip.ID}}">{{template "tip" .Table.GroupedTip}}</span></span></p>
+</div>
 {{/* The key itself, drawn only while it is open. */}}
 {{if .KeyOpen}}
 <ul class="legend muted" aria-label="How to read this table">
diff --git a/web/settings.html b/web/settings.html
index 36ff6c5..b74ddd7 100644
--- a/web/settings.html
+++ b/web/settings.html
@@ -81,7 +81,7 @@
 {{/* The page token proves the form comes from this monitor. */}}
 <input type="hidden" name="token" value="{{.Token}}">
 {{/* The buttons. */}}
-<p><button type="submit" name="action" value="create" class="btn-plain">{{if .IconStale}}Update the icon{{else if .IconExists}}Create the icon again{{else}}Create desktop icon{{end}}</button>{{if .IconExists}} <button type="submit" name="action" value="remove" class="btn-plain">Remove desktop icon</button>{{end}}</p>
+<p><button type="submit" name="action" value="create" class="btn-plain">{{if .IconStale}}Update the icon{{else if .IconExists}}Create icon{{else}}Create desktop icon{{end}}</button>{{if .IconExists}} <button type="submit" name="action" value="remove" class="btn-plain">Remove desktop icon</button>{{end}}</p>
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
echo "NEXT  start bin/LLMsControlDock; look at the Settings page button and the key row on the main page (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
