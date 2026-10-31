#!/usr/bin/env bash
# Script 69q: a small follow-up to 69p, applied on the same branch before it is committed. The answer-time chart now always has a scale of at least 0 to 50 ms, so noise of a few milliseconds looks flat, and its drawing is lower (80 instead of 120 units), so it leaves less empty space on a wide screen.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/charts-state" ] || { echo "FAIL  not on feature/charts-state"; exit 1; }
# Script 69p (the charts) must be applied already.
[ -e monitor.go ] || { echo "FAIL  script 69p was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q "minScale" charts.go; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/charts.go b/charts.go
index cb9fd6d..2c5a76f 100644
--- a/charts.go
+++ b/charts.go
@@ -27,8 +27,11 @@ const stateCells = 60
 // chartWidth is the drawing width, in drawing units; the picture scales to the box.
 const chartWidth = 600
 
-// chartHeight is the height of the answer-time drawing.
-const chartHeight = 120
+// chartHeight is the height of the answer-time drawing; the picture keeps its proportions, so a low drawing stays compact on a wide screen.
+const chartHeight = 80
+
+// minScale is the smallest top of the answer-time scale, in milliseconds, so that small differences of a few milliseconds look flat.
+const minScale int64 = 50
 
 // cellHeight is the height of the state bar.
 const cellHeight = 24
@@ -106,17 +109,14 @@ type chartsView struct {
 	HasData bool
 } // end of chartsView
 
-// niceMax returns the first round number that is at least v, so the scale has tidy ends.
+// niceMax returns the first round number that is at least v, and never less than minScale, so the scale has tidy ends.
 func niceMax(v int64) int64 {
-	// The scale of round numbers.
-	for _, step := range []int64{10, 20, 50} {
-		// Big enough.
-		if v <= step {
-			// This one.
-			return step
-		} // end of the check
-	} // end of the loop
-	// Above 50: 100, 200, 500, 1000, and so on.
+	// Small answer times all fit on the smallest scale.
+	if v <= minScale {
+		// The smallest scale.
+		return minScale
+	} // end of the small case
+	// Above the smallest: 100, 200, 500, 1000, and so on.
 	for base := int64(100); ; base *= 10 {
 		// The three round numbers of this size.
 		for _, m := range []int64{1, 2, 5} {
diff --git a/charts_test.go b/charts_test.go
index bda5f43..a1cf941 100644
--- a/charts_test.go
+++ b/charts_test.go
@@ -65,7 +65,7 @@ func TestChartsAllAnswered(t *testing.T) {
 		t.Errorf("%d lines, %d dots", len(v.Segments), len(v.Dots))
 	} // end of the check
 	// The text alternative says what the chart shows.
-	if !strings.Contains(v.AnswerAlt, "scale 0 to 20 ms: lowest 20 ms, highest 20 ms, latest 20 ms") {
+	if !strings.Contains(v.AnswerAlt, "scale 0 to 50 ms: lowest 20 ms, highest 20 ms, latest 20 ms") {
 		// Report it.
 		t.Errorf("alt wrong: %q", v.AnswerAlt)
 	} // end of the check
@@ -179,7 +179,7 @@ func TestChartsDotsStayInsideTheDrawing(t *testing.T) {
 // TestNiceMax checks the round numbers of the scale.
 func TestNiceMax(t *testing.T) {
 	// Input and expected.
-	for in, want := range map[int64]int64{0: 10, 10: 10, 11: 20, 20: 20, 21: 50, 50: 50, 51: 100, 101: 200, 201: 500, 501: 1000, 1001: 2000, 5001: 10000} {
+	for in, want := range map[int64]int64{0: 50, 10: 50, 11: 50, 20: 50, 49: 50, 50: 50, 51: 100, 100: 100, 101: 200, 201: 500, 501: 1000, 1001: 2000, 5001: 10000} {
 		// Compare.
 		if got := niceMax(in); got != want {
 			// Report it.
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
3522c323e535052f994faae02687e31eecc591c4fa92b58b43b2f7505a290596  charts.go
0b27f6da183a4d5d7fa87124936476bf407b6e54ce06ba753a6b8817de2d5bcb  charts_test.go
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
echo "NEXT  start ./bin/OllamaControlCenter and look at the Answer time chart: flat line, lower drawing, text says scale 0 to 50 ms"
# List the changed files; nothing is committed yet.
git status --short
