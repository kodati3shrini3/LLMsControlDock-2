#!/usr/bin/env bash
# Script 56: the key above the models table is now a box (outline, rounded corners, padding) with clear space between it and the heading row and the table.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/key-box" ] || { echo "FAIL  not on feature/key-box"; exit 1; }
# Script 55 must be applied first (it words the key entries).
grep -q 'View and modify the model' web/index.html || { echo "FAIL  script 55 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q 'Room between the box outline and the entries' web/app.css; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/control_test.go b/control_test.go
index 41fa40d..8d23f9e 100644
--- a/control_test.go
+++ b/control_test.go
@@ -427,3 +427,50 @@ func TestKeyAndDrawnIcons(t *testing.T) {
 		t.Errorf("only %d icon buttons in the table", n)
 	} // end of the row check
 } // end of TestKeyAndDrawnIcons
+
+// ruleOf returns the text of the first CSS rule that starts with the given selector line, from the selector to its closing brace.
+func ruleOf(css, selector string) string {
+	// Where the rule starts (at the beginning of a line).
+	i := strings.Index(css, "\n"+selector+" {")
+	// Not found.
+	if i < 0 {
+		// An empty result makes the caller's check fail with a clear message.
+		return ""
+	} // end of the presence check
+	// The text from the selector on.
+	rest := css[i+1:]
+	// Cut at the closing brace.
+	return rest[:strings.Index(rest, "}")+1]
+} // end of ruleOf
+
+// TestKeyBox checks that the key above the models table is a box (outline, rounded corners, padding) with clear space around it.
+func TestKeyBox(t *testing.T) {
+	// A fake and a rig.
+	rig, _ := perfRig(t, newPerfFake())
+	// The stylesheet the monitor serves.
+	_, _, css := get(t, rig.h, http.MethodGet, "/app.css")
+	// The key's rule.
+	legend := ruleOf(css, ".legend")
+	// What the box needs.
+	for _, want := range []string{"border: 2px solid var(--border)", "border-radius: 0.6rem", "padding: 0.9rem 1rem", "margin: 0 0 1.1rem", "background: var(--bg)"} {
+		// Look for it.
+		if !strings.Contains(legend, want) {
+			// Report the gap.
+			t.Errorf(".legend lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// The heading row above the box leaves clear space below it.
+	if head := ruleOf(css, ".panelhead"); !strings.Contains(head, "margin-bottom: 1rem") {
+		// Report it.
+		t.Errorf(".panelhead has no space below it")
+	} // end of the space check
+	// The key sits in the panel of the models table, after the heading row and before the table.
+	_, _, body := get(t, rig.h, http.MethodGet, "/")
+	// The three places.
+	head, key, table := strings.Index(body, `class="panelhead"`), strings.Index(body, `<ul class="legend`), strings.Index(body, `<table class="models"`)
+	// The order must be heading row, key, table.
+	if !(head >= 0 && head < key && key < table) {
+		// Report it.
+		t.Errorf("order wrong: heading row %d, key %d, table %d", head, key, table)
+	} // end of the order check
+} // end of TestKeyBox
diff --git a/web/app.css b/web/app.css
index 00ee386..de7949c 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1175,6 +1175,8 @@ button.btn-plain {
   justify-content: space-between;
   /* Space between them when they wrap. */
   gap: 0.4rem 1rem;
+  /* Clear space between this row and whatever follows (the key box). */
+  margin-bottom: 1rem;
 } /* end of rule */
 
 /* The heading inside that row has no extra space of its own. */
@@ -1329,10 +1331,16 @@ button.btn-plain {
 .legend {
   /* No bullets. */
   list-style: none;
-  /* A little room below. */
-  margin: 0 0 0.8rem;
-  /* No inner space. */
-  padding: 0;
+  /* Clear space below, before the table. */
+  margin: 0 0 1.1rem;
+  /* Room between the box outline and the entries. */
+  padding: 0.9rem 1rem;
+  /* A solid outline like the panels, visible without colour. */
+  border: 2px solid var(--border);
+  /* Rounded corners. */
+  border-radius: 0.6rem;
+  /* The page background, so the box stands out from the grey panel in both themes. */
+  background: var(--bg);
   /* Columns of at least 15rem, as many as fit. */
   display: grid;
   /* The column rule. */
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
9aff59d11d96be59dcfb292440d750cc475215195d6d0563f8491311560c2fac  control_test.go
aaf4ac1ec7b0121f01441f55c5d0dae169dfe1f853928ab0d485bd528dd52ae7  web/app.css
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the files are exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
# Check the formatting of the Go files (no output means all is well).
[ -z "$(gofmt -l .)" ] || { echo "FAIL  gofmt reports unformatted files"; gofmt -l .; exit 1; }
# Report the check.
echo "PASS  gofmt"
# Run Go's own checker for suspicious code.
go vet ./...
# Report the check.
echo "PASS  go vet"
# Run every test.
go test ./...
# Report the check.
echo "PASS  tests"
# Build the executable the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Stop any monitor that is still running the old build (a leftover one would keep showing the old page).
pkill -f "bin/OllamaControlCenter" || true
# Give it a moment to exit.
sleep 1
# Confirm that none is left.
if pgrep -f "bin/OllamaControlCenter" > /dev/null; then
  # Report it.
  echo "FAIL  an old monitor is still running"; exit 1
fi
# Report the check.
echo "PASS  no old monitor is running; start the new one with: ./bin/OllamaControlCenter"
# List the changed files; nothing is committed yet.
git status --short
