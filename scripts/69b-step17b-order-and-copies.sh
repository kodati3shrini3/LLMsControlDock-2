#!/usr/bin/env bash
# Script 69b: groups and models are listed largest first, and every PDF or CSV download is also saved as a copy in the PerformanceCompare folder (owner-only permissions, never committed).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/compare-groups" ] || { echo "FAIL  not on feature/compare-groups"; exit 1; }
# Script 69 must be applied already.
[ -e compgroup.go ] || { echo "FAIL  script 69 was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q "func cmpBest" compgroup.go; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/compare.go b/compare.go
index 570a45a..3ca5987 100644
--- a/compare.go
+++ b/compare.go
@@ -14,6 +14,8 @@ import ( // import lists the standard-library packages this file uses.
 	"log"
 	// net/http serves the page.
 	"net/http"
+	// path/filepath names the folder of the saved results.
+	"path/filepath"
 ) // end of imports
 
 // compareTemplateText is the page template, stored inside the executable at build time.
@@ -231,8 +233,8 @@ func cmpVsFastest(g cmpGroup, m cmpModel) string {
 		// Say so.
 		return "not ranked"
 	} // end of the rank check
-	// The best model is first.
-	best := g.Models[0].Run
+	// The best model is the one in first place.
+	best := cmpBest(g.Models).Run
 	// The best model itself.
 	if m.Rank == 1 {
 		// Say so.
@@ -428,7 +430,7 @@ func gatherCompare(r *http.Request, addr ollamaAddress, store *perfStore) compar
 	// A file, or the reason there is none.
 	if path != "" {
 		// Say where.
-		data.SaveNote = "The figures come from " + path + "."
+		data.SaveNote = "The figures come from " + path + ". Each PDF or CSV you download is also saved as a copy in the folder " + filepath.Dir(path) + "."
 	} else {
 		// The reason.
 		data.SaveNote = note
diff --git a/compare_test.go b/compare_test.go
index 572f5bc..23e240b 100644
--- a/compare_test.go
+++ b/compare_test.go
@@ -271,10 +271,10 @@ func TestEveryConditionKeepsAModelOutOfTheRanking(t *testing.T) {
 			// Report it.
 			t.Errorf("%s: the others are not ranked 1 and 2", c.name)
 		} // end of the others check
-		// The odd model is listed after the ranked ones.
-		if g.Models[2].Run.Model != "odd:4b" {
+		// The listing order does not depend on the ranking: the same size is listed fastest first, so the odd model of 250 sits between the others unless its speed was changed.
+		if c.name != "no characters" && c.name != "short answer" && g.Models[1].Run.Model != "odd:4b" {
 			// Report it.
-			t.Errorf("%s: order %v", c.name, g.Models[2].Run.Model)
+			t.Errorf("%s: order %v", c.name, g.Models[1].Run.Model)
 		} // end of the order check
 		// The cell says no and why.
 		if cell := cmpFair(m, true); !strings.HasPrefix(cell, "⚠ No: ") || !strings.Contains(cell, c.want) {
@@ -359,8 +359,8 @@ func TestGroupsBySizeAndKind(t *testing.T) {
 	runs := []perfRun{okRun("small:4b", 200), embRun("emb-b", 0.2), huge, tiny, blank, large, embRun("emb-a", 0.04), guess}
 	// Group them.
 	gs := groupRuns(runs, nil, false)
-	// The order: tiny, small, medium (the guess), large, extra-large, unknown, embedding.
-	want := []string{"Chat · Tiny (under 1B)", "Chat · Small (1B to under 5B)", "Chat · Medium (5B to under 12B)", "Chat · Large (12B to under 36B)", "Chat · Extra-large (36B and over)", "Chat · size not known", "Embedding models"}
+	// The order, largest first: extra-large, large, medium (the guess), small, tiny, then unknown, then embedding.
+	want := []string{"Chat · Extra-large (36B and over)", "Chat · Large (12B to under 36B)", "Chat · Medium (5B to under 12B)", "Chat · Small (1B to under 5B)", "Chat · Tiny (under 1B)", "Chat · size not known", "Embedding models"}
 	// Compare.
 	if got := groupTitles(gs); strings.Join(got, "|") != strings.Join(want, "|") {
 		// Stop the test.
@@ -820,3 +820,49 @@ func TestCompareRoute(t *testing.T) {
 		t.Errorf("main page button wrong (count %d)", strings.Count(main, `action="/compare"`))
 	} // end of the icon check
 } // end of TestCompareRoute
+
+// TestModelsAreListedLargestFirst checks that inside a group the larger model comes first whatever the speed, that equal sizes go fastest first, and that the headline still names the fastest ranked model.
+func TestModelsAreListedLargestFirst(t *testing.T) {
+	// Three models of the Small class with different sizes; the smallest is the fastest.
+	big := okRun("big:4b", 100)
+	// Its size.
+	big.ParameterSize = "4.9B"
+	// A middle model.
+	mid := okRun("mid:3b", 150)
+	// Its size.
+	mid.ParameterSize = "3.2B"
+	// The smallest and fastest.
+	low := okRun("low:2b", 400)
+	// Its size.
+	low.ParameterSize = "1.5B"
+	// A model of the same size as mid but faster.
+	twin := okRun("twin:3b", 180)
+	// Its size.
+	twin.ParameterSize = "3.2B"
+	// Group them.
+	gs := groupRuns([]perfRun{low, mid, big, twin}, nil, false)
+	// The group.
+	g := groupOf(t, gs, "Chat · Small (1B to under 5B)")
+	// The names in listed order.
+	var got []string
+	// Collect them.
+	for _, m := range g.Models {
+		// One name.
+		got = append(got, m.Run.Model)
+	} // end of the loop
+	// Largest first; the twins fastest first.
+	if strings.Join(got, ",") != "big:4b,twin:3b,mid:3b,low:2b" {
+		// Report it.
+		t.Errorf("order %v", got)
+	} // end of the order check
+	// The fastest is named in the headline although it is listed last.
+	if !strings.HasPrefix(g.Headline, "low:2b writes fastest") {
+		// Report it.
+		t.Errorf("headline %q", g.Headline)
+	} // end of the headline check
+	// The cells agree: the listed-first model is the slowest.
+	if cell := cmpVsFastest(g, g.Models[0]); !strings.HasPrefix(cell, "#4, 4.0× slower") {
+		// Report it.
+		t.Errorf("cell %q", cell)
+	} // end of the cell check
+} // end of TestModelsAreListedLargestFirst
diff --git a/compgroup.go b/compgroup.go
index c746eb0..6596190 100644
--- a/compgroup.go
+++ b/compgroup.go
@@ -174,6 +174,8 @@ type cmpModel struct {
 	Reasons []string
 	// Rank is the place in the like-for-like ranking, or zero when the model is not ranked.
 	Rank int
+	// SizeB is the size in billions of parameters used to list the largest first: the size Ollama reports, or an estimate from the memory used.
+	SizeB float64
 } // end of cmpModel
 
 // cmpGroup is one comparison group: models that may be compared with each other.
@@ -312,6 +314,14 @@ func groupRuns(runs []perfRun, installed map[string]modelDetails, known bool) []
 				m.Name += " (no longer installed)"
 			} // end of the installed check
 		} // end of the known check
+		// The size used for the listing order: the reported size when it can be read.
+		if b, ok := parseParamBillions(d.ParameterSize); ok {
+			// Use it.
+			m.SizeB = b
+		} else {
+			// Otherwise the same estimate that classifySize uses: memory divided by 0.6 GB per billion.
+			m.SizeB = float64(r.ModelBytes) / 0.6e9
+		} // end of the size check
 		// The nominal precision.
 		m.Bits, m.Quant = precisionOf(d.QuantizationLevel)
 		// The size label to show.
@@ -341,14 +351,14 @@ func groupRuns(runs []perfRun, installed map[string]modelDetails, known bool) []
 		// Put the model into its group.
 		byKey[key] = append(byKey[key], m)
 	} // end of the loop
-	// The keys in the order the groups are shown: chat classes from the smallest, then unknown, then embedding.
+	// The keys in the order the groups are shown: chat classes from the largest, then unknown, then embedding.
 	var keys []int
 	// Collect them.
 	for k := range byKey {
 		// One key.
 		keys = append(keys, k)
 	} // end of the loop
-	// Sort: classes 0..4 first, then unknown (-1), then embedding (-2).
+	// Sort: classes 4..0 first (largest first), then unknown, then embedding.
 	sort.Slice(keys, func(i, j int) bool {
 		// A rank for each key.
 		return keyOrder(keys[i]) < keyOrder(keys[j])
@@ -386,8 +396,8 @@ func keyOrder(k int) int {
 		// After the classes.
 		return 900
 	} // end of the unknown check
-	// The classes in their own order.
-	return k
+	// The classes, largest first: class 4 (extra-large) gets the lowest number.
+	return len(sizeClassNames) - 1 - k
 } // end of keyOrder
 
 // groupTitle writes the heading of a group.
@@ -489,19 +499,14 @@ func buildGroup(key int, models []cmpModel) cmpGroup {
 		// How many are ranked.
 		g.Ranked = len(fair)
 	} // end of the ranking
-	// Put the ranked models first, then the others by speed and name.
+	// List the models largest first; models of the same size are listed fastest first, then by name. The ranking is shown in its own column.
 	sort.SliceStable(models, func(a, b int) bool {
-		// Both ranked: by place.
-		if models[a].Rank > 0 && models[b].Rank > 0 {
-			// Lower place first.
-			return models[a].Rank < models[b].Rank
-		} // end of the both-ranked case
-		// A ranked model goes before an unranked one.
-		if (models[a].Rank > 0) != (models[b].Rank > 0) {
-			// The ranked one first.
-			return models[a].Rank > 0
-		} // end of the mixed case
-		// Both unranked: faster first.
+		// A larger model first.
+		if models[a].SizeB != models[b].SizeB {
+			// Larger is first.
+			return models[a].SizeB > models[b].SizeB
+		} // end of the size case
+		// The same size: faster first.
 		if speedKey(models[a].Run) != speedKey(models[b].Run) {
 			// Higher is better.
 			return speedKey(models[a].Run) > speedKey(models[b].Run)
@@ -592,12 +597,26 @@ func reasonsFor(m cmpModel, embedding bool, refBits int, refLabel string, refCtx
 	return out
 } // end of reasonsFor
 
+// cmpBest returns the model in first place of the ranking (the list is ordered by size, so it is searched for).
+func cmpBest(models []cmpModel) cmpModel {
+	// Look for place one.
+	for _, m := range models {
+		// Found.
+		if m.Rank == 1 {
+			// Done.
+			return m
+		} // end of the check
+	} // end of the loop
+	// Nothing is ranked (callers check this first).
+	return cmpModel{}
+} // end of cmpBest
+
 // groupSentences writes the headline of a group (only when it is ranked) and the notes that explain why there is no ranking.
 func groupSentences(g cmpGroup) (string, []string) {
 	// A ranked group names its fastest model.
 	if g.Ranked >= 2 {
-		// The best model is first.
-		best := g.Models[0]
+		// The best model is the one in first place.
+		best := cmpBest(g.Models)
 		// How many others were compared with it fairly.
 		others := g.Ranked - 1
 		// The word for the others.
diff --git a/compreport.go b/compreport.go
index b86c3b2..3db79d9 100644
--- a/compreport.go
+++ b/compreport.go
@@ -8,8 +8,14 @@ import ( // import lists the standard-library packages this file uses.
 	"encoding/csv"
 	// fmt formats numbers.
 	"fmt"
+	// log records that a copy was saved, or why it was not.
+	"log"
 	// net/http serves the downloads.
 	"net/http"
+	// os makes the folder and writes the copy.
+	"os"
+	// path/filepath builds the path of the copy.
+	"path/filepath"
 	// strings cleans text.
 	"strings"
 	// time stamps the files.
@@ -282,6 +288,37 @@ func csvEmbedTime(r perfRun) string {
 	return csvNum(r.WarmTotalSec, 3)
 } // end of csvEmbedTime
 
+// savedCopyFolder is the folder where copies of the downloads are kept: the folder that holds the saved results (PerformanceCompare next to the project); empty when the results are kept only in memory.
+func savedCopyFolder(store *perfStore) string {
+	// Where the results live.
+	path, _ := store.where()
+	// Memory only: no folder.
+	if path == "" {
+		// Nothing to do.
+		return ""
+	} // end of the memory check
+	// The folder of the results file.
+	return filepath.Dir(path)
+} // end of savedCopyFolder
+
+// saveCopy writes one downloaded file into the folder, readable only by the person who runs the monitor, and returns its path.
+func saveCopy(dir, name string, body []byte) (string, error) {
+	// Make the folder when it is not there yet.
+	if err := os.MkdirAll(dir, 0o700); err != nil {
+		// Give up with the reason.
+		return "", err
+	} // end of the folder check
+	// The full path of the file.
+	p := filepath.Join(dir, name)
+	// Write it (the name carries the time to the second, so it does not clash with an earlier copy).
+	if err := os.WriteFile(p, body, 0o600); err != nil {
+		// Give up with the reason.
+		return "", err
+	} // end of the write check
+	// Done.
+	return p, nil
+} // end of saveCopy
+
 // compareDownloadHandlers return the handlers of the two downloads; both run the same checks as the page and only read the saved figures.
 func compareDownloadHandlers(addr ollamaAddress, token string, store *perfStore) (http.HandlerFunc, http.HandlerFunc) {
 	// serve builds one download: the render function turns the page data into the file bytes.
@@ -310,6 +347,17 @@ func compareDownloadHandlers(addr ollamaAddress, token string, store *perfStore)
 			w.Header().Set("Content-Type", contentType)
 			// Ask the browser to save it, under a name that carries the time.
 			w.Header().Set("Content-Disposition", `attachment; filename="OllamaControlCenter-comparison-`+now.Format("20060102-150405Z0700")+`.`+extension+`"`)
+			// Keep a copy next to the saved results; a failure is only logged, because the download itself must still work.
+			if dir := savedCopyFolder(store); dir != "" {
+				// Write it.
+				if p, err := saveCopy(dir, "OllamaControlCenter-comparison-"+now.Format("20060102-150405Z0700")+"."+extension, body); err != nil {
+					// Say why there is no copy.
+					log.Printf("could not save a copy of the download: %v", err)
+				} else {
+					// Say where it is.
+					log.Printf("saved a copy of the download in %s", p)
+				} // end of the save check
+			} // end of the folder check
 			// Send it.
 			w.Write(body)
 		} // end of the handler
diff --git a/compreport_test.go b/compreport_test.go
index 313b395..8372dcc 100644
--- a/compreport_test.go
+++ b/compreport_test.go
@@ -10,6 +10,10 @@ import ( // import lists the standard-library packages this file uses.
 	"net/http"
 	// net/url builds the form values.
 	"net/url"
+	// os reads the copies back.
+	"os"
+	// path/filepath builds paths in the test folder.
+	"path/filepath"
 	// regexp checks the file name.
 	"regexp"
 	// strings joins and searches text.
@@ -252,7 +256,7 @@ func TestCompareDownloadRoutes(t *testing.T) {
 	// A fake Ollama and a rig.
 	f := newPerfFake()
 	// Build the rig.
-	rig, _ := perfRig(t, f)
+	rig, histFile := perfRig(t, f)
 	// With nothing saved there is nothing to download.
 	for _, path := range []string{"/compare/pdf", "/compare/csv"} {
 		// Ask.
@@ -349,6 +353,31 @@ func TestCompareDownloadRoutes(t *testing.T) {
 		// Report it.
 		t.Errorf("download buttons: %d / %d", strings.Count(page, `action="/compare/pdf"`), strings.Count(page, `action="/compare/csv"`))
 	} // end of the button check
+	// Each download left a copy next to the saved results.
+	var pdfs, csvs int
+	// Look through the folder of the results.
+	_ = filepath.WalkDir(filepath.Dir(histFile), func(p string, d os.DirEntry, err error) error {
+		// Count by ending.
+		if err == nil && strings.HasPrefix(d.Name(), "OllamaControlCenter-comparison-") {
+			// A PDF copy.
+			if strings.HasSuffix(d.Name(), ".pdf") {
+				// Count it.
+				pdfs++
+			} // end of the PDF check
+			// A CSV copy.
+			if strings.HasSuffix(d.Name(), ".csv") {
+				// Count it.
+				csvs++
+			} // end of the CSV check
+		} // end of the name check
+		// Keep walking.
+		return nil
+	}) // end of the walk
+	// At least one of each.
+	if pdfs < 1 || csvs < 1 {
+		// Report it.
+		t.Errorf("copies saved: %d PDF, %d CSV", pdfs, csvs)
+	} // end of the copies check
 } // end of TestCompareDownloadRoutes
 
 // TestPDFNeverLeavesAHeadingAloneAtTheFootOfAPage builds the report with many different lengths, so headings land at every height, and checks that no page ends with a heading, a question or a model name.
@@ -407,3 +436,38 @@ func TestPDFNeverLeavesAHeadingAloneAtTheFootOfAPage(t *testing.T) {
 		} // end of the padding loop
 	} // end of the loop
 } // end of TestPDFNeverLeavesAHeadingAloneAtTheFootOfAPage
+
+// TestDownloadsAreAlsoSavedAsCopies checks that the folder of the results receives a copy of each download, that the copy equals the download, and that it is readable only by its owner.
+func TestDownloadsAreAlsoSavedAsCopies(t *testing.T) {
+	// A folder for the copy.
+	dir := t.TempDir()
+	// The copy.
+	p, err := saveCopy(filepath.Join(dir, "PerformanceCompare"), "a.csv", []byte("x,y\n"))
+	// It must work, creating the folder.
+	if err != nil {
+		// Stop the test.
+		t.Fatal(err)
+	} // end of the error check
+	// Read it back.
+	b, err := os.ReadFile(p)
+	// The same bytes.
+	if err != nil || string(b) != "x,y\n" {
+		// Report it.
+		t.Fatalf("copy %q err %v", b, err)
+	} // end of the read check
+	// Only the owner may read it.
+	if st, _ := os.Stat(p); st.Mode().Perm() != 0o600 {
+		// Report it.
+		t.Errorf("mode %v", st.Mode().Perm())
+	} // end of the mode check
+	// A store without a file has no folder, so nothing is written.
+	if got := savedCopyFolder(openPerfStore("", "memory only")); got != "" {
+		// Report it.
+		t.Errorf("folder %q for a memory-only store", got)
+	} // end of the memory check
+	// A store with a file uses the folder of that file.
+	if got := savedCopyFolder(openPerfStore(filepath.Join(dir, "PerformanceCompare", "performance.json"), "")); got != filepath.Join(dir, "PerformanceCompare") {
+		// Report it.
+		t.Errorf("folder %q", got)
+	} // end of the folder check
+} // end of TestDownloadsAreAlsoSavedAsCopies
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
63e6987b7940ea2cbb039e188fcc7829f48bef7873d8c1eeda372a626088acee  compgroup.go
058c088b0c03d4e7cac3a6457375ba32cb0fca8ff660231a90a02c83abaced4d  compare.go
a0a80f6a9ee28bb2048d749db0498033f3b363b5dfc4b917d36898b8b32ce49f  compreport.go
c2f0ffb789bf0680c79c82ca7e71f163d6ec686d68fbc3bb1301ca3f50eab911  compare_test.go
59857fb1fcf631c91bc293cfdff716cea0167bb4811fd0e2edef3bb4ff095481  compreport_test.go
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
