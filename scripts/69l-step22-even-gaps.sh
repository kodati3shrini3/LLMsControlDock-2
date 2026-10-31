#!/usr/bin/env bash
# Script 69l: the gap above the footer bar on the main page becomes 1rem (16 pixels), the same as the gaps between the boxes (it was 1.5rem). A test keeps the two equal.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/even-gaps" ] || { echo "FAIL  not on feature/even-gaps"; exit 1; }
# Script 69k (group re-test) must be applied already (merged into main).
[ -e retest.go ] || { echo "FAIL  script 69k was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e spacing_test.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/spacing_test.go b/spacing_test.go
new file mode 100644
index 0000000..f9318ad
--- /dev/null
+++ b/spacing_test.go
@@ -0,0 +1,47 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// net/http provides the method name.
+	"net/http"
+	// regexp reads the margin value out of a rule.
+	"regexp"
+	// strings splits the value.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// marginTop returns the top margin of a rule: the first of the values of its margin line.
+func marginTop(t *testing.T, css, selector string) string {
+	// Mark this as a helper.
+	t.Helper()
+	// The rule.
+	rule := ruleOf(css, selector)
+	// The margin line.
+	m := regexp.MustCompile(`margin:\s*([^;]+);`).FindStringSubmatch(rule)
+	// It must have one.
+	if m == nil {
+		// Stop the test.
+		t.Fatalf("%s has no margin line: %q", selector, rule)
+	} // end of the presence check
+	// The first value is the top margin.
+	return strings.Fields(m[1])[0]
+} // end of marginTop
+
+// TestBoxesHaveEvenGaps checks the gap above the footer bar equals the gap between the boxes, so the spaces on the main page are all the same.
+func TestBoxesHaveEvenGaps(t *testing.T) {
+	// A fake and a rig.
+	rig, _ := perfRig(t, newPerfFake())
+	// The stylesheet the monitor serves.
+	_, _, css := get(t, rig.h, http.MethodGet, "/app.css")
+	// The gap that boxes leave above and below themselves.
+	box := marginTop(t, css, ".panel")
+	// The gap above the footer bar.
+	bar := marginTop(t, css, ".brandbar")
+	// They must be the same.
+	if box != bar {
+		// Report the problem.
+		t.Errorf("gap above the footer bar is %s, between the boxes %s", bar, box)
+	} // end of the equality check
+} // end of TestBoxesHaveEvenGaps
diff --git a/web/app.css b/web/app.css
index ee230ef..cce1e0c 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1773,8 +1773,8 @@ html[data-size="medium"] svg[width="22"] {
   flex-wrap: wrap;
   /* Space between the parts when they wrap. */
   gap: 0.75rem 1rem;
-  /* Space above and below the bar. */
-  margin: 1.5rem 0 2rem;
+  /* Space above (the same as between the boxes, so every gap on the page is equal) and below the bar. */
+  margin: 1rem 0 2rem;
   /* Air inside. */
   padding: 0.9rem 1.1rem;
   /* The same solid outline and panel colour as the other boxes. */
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
235bf8c5ad0085755e7e0f629f54c033f89765848a74f03f064389cc00123ab1  web/app.css
515adef07069260a1c267373d9fea43b6bf202ce024574da86fd5a78dc5dbee8  spacing_test.go
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
# Tell the person how to use the new command.
echo "NEXT  start ./bin/OllamaControlCenter and look at the gaps between the boxes and above the footer bar"
# List the changed files; nothing is committed yet.
git status --short
