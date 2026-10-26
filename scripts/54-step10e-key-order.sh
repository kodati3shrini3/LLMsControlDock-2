#!/usr/bin/env bash
# Script 54: the key above the models table now starts with "Dotted headings" and "Sideways scroll", followed by the four icon explanations.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/monitor-controls" ] || { echo "FAIL  not on feature/monitor-controls"; exit 1; }
# Script 53 must be applied first (it adds the key).
grep -q 'class="legend' web/index.html || { echo "FAIL  script 53 was not applied yet"; exit 1; }
# Refuse to run twice: after this change the first entry of the key is "Dotted headings".
if grep -A1 'class="legend' web/index.html | grep -q 'Dotted headings'; then
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
index 0fd4d6d..41fa40d 100644
--- a/control_test.go
+++ b/control_test.go
@@ -400,6 +400,22 @@ func TestKeyAndDrawnIcons(t *testing.T) {
 		// Report it.
 		t.Errorf("the key has %d entries, want 6", n)
 	} // end of the count check
+	// The two reading hints come first in the key, then the four icon explanations.
+	order := []string{"Dotted headings</strong>", "Sideways scroll</strong>", "Modelfile</strong>", "Inference parameters</strong>", "Performance</strong>", "Compare tested models</strong>"}
+	// Walk the list and make sure each entry comes after the one before.
+	last := -1
+	// Each entry.
+	for _, o := range order {
+		// Where it is.
+		at := strings.Index(body, o)
+		// It must come after the previous one.
+		if at <= last {
+			// Report it.
+			t.Errorf("the key entry %q is out of order", o)
+		} // end of the order check
+		// Remember the place.
+		last = at
+	} // end of the loop
 	// The compare button has the bigger drawn scale.
 	if !strings.Contains(body, `<svg class="ico ico-big"`) {
 		// Report it.
diff --git a/web/index.html b/web/index.html
index ccddb78..069de42 100644
--- a/web/index.html
+++ b/web/index.html
@@ -150,12 +150,12 @@
 {{/* A hint above the table so people know the dotted headings have help. */}}
 {{/* A key above the table: what each symbol and the dotted headings do. */}}
 <ul class="legend muted" aria-label="How to read this table">
+<li><span class="sym"><span class="dotsample">Aa</span></span><span><strong>Dotted headings</strong>: point at one, or press Tab, to see what it means</span></li>
+<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h18"/><path d="M7 8l-4 4 4 4"/><path d="M17 8l4 4-4 4"/></svg></span><span><strong>Sideways scroll</strong>: the table scrolls sideways</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M9 13h6"/><path d="M9 17h6"/></svg></span><span><strong>Modelfile</strong>: shows a model&#39;s Modelfile, read-only</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h9"/><path d="M17 7h3"/><circle cx="15" cy="7" r="2"/><path d="M4 17h3"/><path d="M11 17h9"/><circle cx="9" cy="17" r="2"/></svg></span><span><strong>Inference parameters</strong>: only for models that are not loaded</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M7 15l4-5 3 3 5-7"/></svg></span><span><strong>Performance</strong>: before a model name; not shown while the model is loaded, because it may be in use</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M7 21h10"/><path d="M4 7h16"/><path d="M4 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/><path d="M20 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/></svg></span><span><strong>Compare tested models</strong>: the button at the top right of this panel</span></li>
-<li><span class="sym"><span class="dotsample">Aa</span></span><span><strong>Dotted headings</strong>: point at one, or press Tab, to see what it means</span></li>
-<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h18"/><path d="M7 8l-4 4 4 4"/><path d="M17 8l4 4-4 4"/></svg></span><span><strong>Sideways scroll</strong>: the table scrolls sideways</span></li>
 </ul>
 {{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
 <div class="scrollbox" tabindex="0" role="region" aria-label="Installed models table, scrolls sideways">
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
01cbd1f20d8ce25dc0425fa2f440b0847e11b5ff1ce1c1e28989cda4139204b4  control_test.go
bb56d27133bbdc2b970d83605652bd337d21b7805cc491852fa83ad311744e27  web/index.html
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
