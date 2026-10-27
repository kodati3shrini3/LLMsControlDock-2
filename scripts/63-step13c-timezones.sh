#!/usr/bin/env bash
# Script 63: every shown or stored time names its time zone: the greyed row in the table now has the year and the zone, the snapshot file name carries the zone offset, and a test scans the source so a time without a zone can never be added again.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/delete-history" ] || { echo "FAIL  not on feature/delete-history"; exit 1; }
# Script 62 must be applied first.
grep -q 'Use View history below' web/delete.html || { echo "FAIL  script 62 was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e timezone_test.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/history.go b/history.go
index 84e5996..fd3c281 100644
--- a/history.go
+++ b/history.go
@@ -152,8 +152,8 @@ func (h *historyStore) save(s paramSnapshot) (string, error) {
 		// Fixed wording.
 		return "", fmt.Errorf("the snapshot could not be encoded: %w", err)
 	} // end of the encode check
-	// The first part of the name: time, then the model.
-	base := s.DeletedAt.Format("2006-01-02_15-04-05") + "_" + safeFilePart(s.Model)
+	// The first part of the name: time with its time zone offset (Z for UTC, otherwise such as +0100), then the model.
+	base := s.DeletedAt.Format("2006-01-02_15-04-05Z0700") + "_" + safeFilePart(s.Model)
 	// Try the plain name, then numbered ones.
 	for n := 0; n < 100; n++ {
 		// The file name.
diff --git a/history_test.go b/history_test.go
index 3195208..702cbce 100644
--- a/history_test.go
+++ b/history_test.go
@@ -152,7 +152,7 @@ func TestDeleteSavesSnapshotFirst(t *testing.T) {
 	// The history page.
 	page := bodyOf(post(t, rig.h, "/restore/history", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
 	// The parameters and the facts, with the stop word escaped.
-	for _, want := range []string{"History of <code>alpha:1b</code>", "<code>temperature</code>", "<code>0.7</code>", "<code>num_ctx</code>", "<code>4096</code>", "&#34;&lt;end&gt;&#34;", "1.3 GB", names[0]} {
+	for _, want := range []string{"History of <code>alpha:1b</code>", "<code>temperature</code>", "<code>0.7</code>", "<code>num_ctx</code>", "<code>4096</code>", "&#34;&lt;end&gt;&#34;", "1.3 GB", strings.ReplaceAll(names[0], "+", "&#43;")} {
 		// Look for it.
 		if !strings.Contains(page, want) {
 			// Report the gap.
diff --git a/tableview.go b/tableview.go
index 66a1bd3..613014d 100644
--- a/tableview.go
+++ b/tableview.go
@@ -87,7 +87,7 @@ type deletedRow struct {
 	Name string
 	// SizeText is the size it had, in words.
 	SizeText string
-	// WhenText is the deletion time in words, in the computer's own time zone.
+	// WhenText is the deletion time in words, with the year and the computer's own time zone.
 	WhenText string
 } // end of deletedRow
 
@@ -103,7 +103,7 @@ func deletedRows(items []deletedModel, installed []installedModel) []deletedRow
 			continue
 		} // end of the installed check
 		// Add the row.
-		rows = append(rows, deletedRow{Name: d.Name, SizeText: formatSize(d.Size), WhenText: d.DeletedAt.Local().Format("2 Jan 15:04")})
+		rows = append(rows, deletedRow{Name: d.Name, SizeText: formatSize(d.Size), WhenText: d.DeletedAt.Local().Format("2 Jan 2006 15:04 MST")})
 	} // end of the loop
 	// Hand back.
 	return rows
diff --git a/timezone_test.go b/timezone_test.go
new file mode 100644
index 0000000..ac294f6
--- /dev/null
+++ b/timezone_test.go
@@ -0,0 +1,137 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// os reads the source files.
+	"os"
+	// path/filepath finds the source files.
+	"path/filepath"
+	// regexp finds the time layouts.
+	"regexp"
+	// strings searches the source lines.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+	// time builds a moment in a chosen zone.
+	"time"
+) // end of imports
+
+// TestEveryShownTimeNamesItsZone is a standing rule of the project: wherever a time or date is shown or stored, its time zone is mentioned. It reads the program's own source and fails when a time layout with hours or minutes has no zone.
+func TestEveryShownTimeNamesItsZone(t *testing.T) {
+	// The program's source files.
+	files, err := filepath.Glob("*.go")
+	// A failure here is a broken test setup.
+	if err != nil || len(files) == 0 {
+		// Stop the test.
+		t.Fatalf("no source files found: %v", err)
+	} // end of the glob check
+	// A Format call with a text layout.
+	layout := regexp.MustCompile(`\.Format\("([^"]*)"\)`)
+	// What counts as naming the zone inside the layout.
+	zones := []string{"MST", "UTC", "Z0700", "-0700", "Z07:00", "-07:00"}
+	// How many layouts were checked, so the test cannot pass by finding nothing.
+	checked := 0
+	// Go through the files.
+	for _, f := range files {
+		// Tests may use any layout.
+		if strings.HasSuffix(f, "_test.go") {
+			// Skip it.
+			continue
+		} // end of the test-file check
+		// Read the file.
+		data, err := os.ReadFile(f)
+		// A failure here is a broken test setup.
+		if err != nil {
+			// Stop the test.
+			t.Fatalf("cannot read %s: %v", f, err)
+		} // end of the read check
+		// Go through the lines.
+		for i, line := range strings.Split(string(data), "\n") {
+			// Comments may talk about layouts freely.
+			if strings.HasPrefix(strings.TrimSpace(line), "//") {
+				// Skip it.
+				continue
+			} // end of the comment check
+			// Every layout on the line.
+			for _, m := range layout.FindAllStringSubmatch(line, -1) {
+				// Only layouts that show a time of day need a zone.
+				if !strings.Contains(m[1], "15") && !strings.Contains(m[1], "04") {
+					// A date alone is not checked here.
+					continue
+				} // end of the time-of-day check
+				// One more layout checked.
+				checked++
+				// The zone may be in the layout itself.
+				ok := false
+				// Look for each zone marker.
+				for _, z := range zones {
+					// Found one.
+					if strings.Contains(m[1], z) {
+						// Fine.
+						ok = true
+					} // end of the marker check
+				} // end of the zone loop
+				// Or the same line adds the word UTC after the time.
+				if strings.Contains(line, `" UTC"`) {
+					// Fine.
+					ok = true
+				} // end of the added-word check
+				// Report a layout without a zone.
+				if !ok {
+					// Name the place.
+					t.Errorf("%s:%d shows a time without its time zone: %q", f, i+1, m[1])
+				} // end of the zone check
+			} // end of the layout loop
+		} // end of the line loop
+	} // end of the file loop
+	// The test must have looked at something.
+	if checked < 5 {
+		// Report it.
+		t.Errorf("only %d time layouts were found; the scan is not working", checked)
+	} // end of the count check
+} // end of TestEveryShownTimeNamesItsZone
+
+// TestSnapshotFileNameHasZone checks the snapshot file name carries the time zone offset.
+func TestSnapshotFileNameHasZone(t *testing.T) {
+	// A store in a private folder.
+	h := &historyStore{dir: filepath.Join(t.TempDir(), "history")}
+	// A moment in a zone one hour ahead of UTC.
+	at := time.Date(2026, 10, 27, 17, 30, 0, 0, time.FixedZone("CET", 3600))
+	// Save.
+	name, err := h.save(paramSnapshot{Model: "a:1", DeletedAt: at})
+	// It must work and carry the offset.
+	if err != nil || !strings.HasPrefix(name, "2026-10-27_17-30-00+0100_a-1_") {
+		// Report it.
+		t.Errorf("name %q (err %v) lacks the zone offset", name, err)
+	} // end of the CET check
+	// The same moment in UTC is marked with Z.
+	name, err = h.save(paramSnapshot{Model: "a:1", DeletedAt: at.UTC()})
+	// Check.
+	if err != nil || !strings.HasPrefix(name, "2026-10-27_16-30-00Z_a-1_") {
+		// Report it.
+		t.Errorf("name %q (err %v) lacks the UTC mark", name, err)
+	} // end of the UTC check
+	// The time stored inside the file keeps its offset too.
+	data, _ := os.ReadFile(filepath.Join(h.dir, h.list("a:1")[1].File))
+	// The text.
+	if !strings.Contains(string(data), "2026-10-27T17:30:00+01:00") {
+		// Report it.
+		t.Errorf("the stored time lacks its offset: %s", data)
+	} // end of the stored check
+} // end of TestSnapshotFileNameHasZone
+
+// TestGreyedRowTimeHasYearAndZone checks the deleted-at text in the table carries the year and the zone.
+func TestGreyedRowTimeHasYearAndZone(t *testing.T) {
+	// A moment in a known zone; Local() would convert it, so the check is on the layout's parts.
+	rows := deletedRows([]deletedModel{{Name: "m:1", Size: 1, DeletedAt: time.Date(2026, 10, 27, 17, 30, 0, 0, time.UTC)}}, nil)
+	// One row.
+	if len(rows) != 1 {
+		// Stop the test.
+		t.Fatalf("rows: %v", rows)
+	} // end of the count check
+	// Year, hour and minute, and a zone name or offset at the end.
+	if ok, _ := regexp.MatchString(`^\d{1,2} [A-Z][a-z]{2} 2026 \d{2}:\d{2} \S+$`, rows[0].WhenText); !ok {
+		// Report it.
+		t.Errorf("greyed row time %q lacks the year or the zone", rows[0].WhenText)
+	} // end of the pattern check
+} // end of TestGreyedRowTimeHasYearAndZone
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
d16e0699c414d819ea7d7aeddf504ca4236a504cf86213d01fb7cc4426d18fde  history.go
ede909f8fe45a5d01ec70975d68cca973f5ea478ce570dd2dbe52041d93df945  history_test.go
bdb30161ccca3a1c29916f39cd53d2ff1e76703cd90ab497caea1f81dc068511  tableview.go
b92b0a8a3886bd37adb6fb0c352ec1cdee42cebd994c2e76630f7542801df28e  timezone_test.go
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
