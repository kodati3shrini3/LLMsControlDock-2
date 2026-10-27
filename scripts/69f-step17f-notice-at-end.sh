#!/usr/bin/env bash
# Script 69f: the PDF carries the full notice (Notice and limitation of liability) once, at the end; the short notice stays in the footer of every page.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/compare-groups" ] || { echo "FAIL  not on feature/compare-groups"; exit 1; }
# Script 69e must be applied already.
[ -e web/compare-saved.html ] || { echo "FAIL  script 69e was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q "func writeNoticeBlock" compreport.go; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/compreport.go b/compreport.go
index f934d8c..53036fc 100644
--- a/compreport.go
+++ b/compreport.go
@@ -35,7 +35,24 @@ func footerLine(when time.Time) string {
 	return fmt.Sprintf("OllamaControlCenter %s  -  made %s", appVersion, when.UTC().Format("2006-01-02 15:04 UTC"))
 } // end of footerLine
 
-// writeComparePDF turns the comparison page into a PDF; the full notice is on the first page and again at the end, and a short notice is at the foot of every page.
+// writeNoticeBlock prints the full notice: a line, the heading and every paragraph, kept together at the start.
+func writeNoticeBlock(d *pdfDoc, p comparePage) {
+	// Keep the line, the heading and the first paragraph together.
+	d.keep(80)
+	// A line.
+	d.rule()
+	// Its heading.
+	d.text(p.NoticeTitle, 11, true, 0)
+	// Each paragraph.
+	for _, para := range p.NoticeFull {
+		// One paragraph.
+		d.text(para, 9, false, 0)
+		// A little air.
+		d.gap(3)
+	} // end of the notice loop
+} // end of writeNoticeBlock
+
+// writeComparePDF turns the comparison page into a PDF; the full notice is printed once, at the end, and a short notice is at the foot of every page.
 func writeComparePDF(p comparePage, when time.Time) []byte {
 	// The document.
 	d := newPDF("OllamaControlCenter model comparison", p.NoticeShort, p.NoticeShort, footerLine(when), when)
@@ -45,21 +62,16 @@ func writeComparePDF(p comparePage, when time.Time) []byte {
 	d.text(fmt.Sprintf("Made by OllamaControlCenter %s on %s, from tests saved on this computer.", appVersion, when.UTC().Format("2006-01-02 15:04 UTC")), 9, false, 0)
 	// A little air.
 	d.gap(6)
-	// The full notice first, so nobody reads a figure before it.
-	d.text(p.NoticeTitle, 11, true, 0)
-	// Each paragraph.
-	for _, para := range p.NoticeFull {
-		// One paragraph.
-		d.text(para, 9, false, 0)
-		// A little air.
-		d.gap(3)
-	} // end of the notice loop
-	// A line.
+	// The full notice is printed once, at the end; the short notice is at the foot of every page, so it is on the first page too.
 	d.rule()
 	// Nothing saved.
 	if p.Empty {
 		// Say so.
 		d.text("No model has been through a performance test yet.", 10, false, 0)
+		// The full notice is still printed, once, at the end.
+		d.gap(8)
+		// The notice.
+		writeNoticeBlock(d, p)
 		// The finished file.
 		return d.bytes()
 	} // end of the empty check
@@ -160,21 +172,10 @@ func writeComparePDF(p comparePage, when time.Time) []byte {
 	d.gap(3)
 	// The sentence.
 	d.text("The addresses were opened and read on "+p.RefsChecked+". A web page can change or disappear later.", 8.5, false, 0)
-	// The notice again at the end.
+	// The full notice, once, at the end.
 	d.gap(8)
-	// Keep the line, the heading and the first paragraph together.
-	d.keep(80)
-	// A line.
-	d.rule()
-	// Its heading.
-	d.text(p.NoticeTitle, 11, true, 0)
-	// Each paragraph.
-	for _, para := range p.NoticeFull {
-		// One paragraph.
-		d.text(para, 9, false, 0)
-		// A little air.
-		d.gap(3)
-	} // end of the notice loop
+	// The notice.
+	writeNoticeBlock(d, p)
 	// The finished file.
 	return d.bytes()
 } // end of writeComparePDF
diff --git a/compreport_test.go b/compreport_test.go
index e3998b5..0e8a0cb 100644
--- a/compreport_test.go
+++ b/compreport_test.go
@@ -52,22 +52,25 @@ func TestComparePDFCarriesEverything(t *testing.T) {
 	bodies, footers := pdfCheck(t, data)
 	// The body text.
 	body := flat(bodies)
-	// The full notice must be there twice: first page and the end.
+	// The full notice must be there exactly once, at the end of the file.
 	for _, para := range noticeFull {
 		// Normalise the paragraph the same way.
 		want := strings.Join(strings.Fields(para), " ")
-		// Twice.
-		if n := strings.Count(body, want); n != 2 {
+		// Once.
+		if n := strings.Count(body, want); n != 1 {
 			// Report it.
-			t.Errorf("notice paragraph %.40q appears %d times, want 2", want, n)
+			t.Errorf("notice paragraph %.40q appears %d times, want 1", want, n)
 		} // end of the count check
 	} // end of the notice loop
-	// The notice comes before any figure, on the first page.
-	first := flat(bodies[:1])
-	// The first page holds the whole notice, and it comes before the first group in reading order.
-	if !strings.Contains(first, "Nothing here limits any liability that cannot be limited by law") || strings.Index(body, "Nothing here limits any liability that cannot be limited by law") > strings.Index(body, "Chat · Small (1B to under 5B)") {
+	// The heading of the full notice appears once, after the last reference and after every group.
+	if n := strings.Count(body, noticeTitle); n != 1 || strings.Index(body, noticeTitle) < strings.LastIndex(body, "References") {
 		// Report it.
-		t.Errorf("the first page does not hold the notice before the figures")
+		t.Errorf("the notice heading appears %d times or not at the end", n)
+	} // end of the heading check
+	// The first page carries the short notice in its footer, before any figure.
+	if len(footers) == 0 || !strings.Contains(flat([][]pdfTextLine{footers[0]}), noticeShort) {
+		// Report it.
+		t.Errorf("the first page has no short notice in its footer")
 	} // end of the first page check
 	// A short notice and the page number in every footer.
 	for i, f := range footers {
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
e547032209b75f33920fc57b4f5a5e23110c41460ae8b80d1d09b0d612a87252  compreport.go
955e07c2ca9811e0e2b0d9c111673f48d271cfd30c173265bccdb361bab6e088  compreport_test.go
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
