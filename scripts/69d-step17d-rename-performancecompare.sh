#!/usr/bin/env bash
# Script 69d: the results folder is now called performanceCompare (small p). An existing PerformanceCompare folder is renamed once, on start-up, with everything in it; both spellings stay out of GitHub.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/compare-groups" ] || { echo "FAIL  not on feature/compare-groups"; exit 1; }
# Script 69c must be applied already.
grep -q "deletedFolderName" deletestore.go || { echo "FAIL  script 69c was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q "oldHistoryFolderName" perfstore.go; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/.gitignore b/.gitignore
index b314b01..3d2c112 100644
--- a/.gitignore
+++ b/.gitignore
@@ -16,6 +16,8 @@ history/
 *.history.json
 
 # Saved performance test results (numbers about this machine): personal to each machine
+performanceCompare/
+# The name used by earlier versions (renamed on start-up); kept here so an old folder can never reach GitHub
 PerformanceCompare/
 
 # Remembered list of deleted models: personal to each machine
diff --git a/compreport.go b/compreport.go
index 3db79d9..262d4df 100644
--- a/compreport.go
+++ b/compreport.go
@@ -288,7 +288,7 @@ func csvEmbedTime(r perfRun) string {
 	return csvNum(r.WarmTotalSec, 3)
 } // end of csvEmbedTime
 
-// savedCopyFolder is the folder where copies of the downloads are kept: the folder that holds the saved results (PerformanceCompare next to the project); empty when the results are kept only in memory.
+// savedCopyFolder is the folder where copies of the downloads are kept: the folder that holds the saved results (performanceCompare next to the project); empty when the results are kept only in memory.
 func savedCopyFolder(store *perfStore) string {
 	// Where the results live.
 	path, _ := store.where()
diff --git a/compreport_test.go b/compreport_test.go
index 8372dcc..277f3c7 100644
--- a/compreport_test.go
+++ b/compreport_test.go
@@ -442,7 +442,7 @@ func TestDownloadsAreAlsoSavedAsCopies(t *testing.T) {
 	// A folder for the copy.
 	dir := t.TempDir()
 	// The copy.
-	p, err := saveCopy(filepath.Join(dir, "PerformanceCompare"), "a.csv", []byte("x,y\n"))
+	p, err := saveCopy(filepath.Join(dir, "performanceCompare"), "a.csv", []byte("x,y\n"))
 	// It must work, creating the folder.
 	if err != nil {
 		// Stop the test.
@@ -466,7 +466,7 @@ func TestDownloadsAreAlsoSavedAsCopies(t *testing.T) {
 		t.Errorf("folder %q for a memory-only store", got)
 	} // end of the memory check
 	// A store with a file uses the folder of that file.
-	if got := savedCopyFolder(openPerfStore(filepath.Join(dir, "PerformanceCompare", "performance.json"), "")); got != filepath.Join(dir, "PerformanceCompare") {
+	if got := savedCopyFolder(openPerfStore(filepath.Join(dir, "performanceCompare", "performance.json"), "")); got != filepath.Join(dir, "performanceCompare") {
 		// Report it.
 		t.Errorf("folder %q", got)
 	} // end of the folder check
diff --git a/delete_test.go b/delete_test.go
index b5fa2c5..f704332 100644
--- a/delete_test.go
+++ b/delete_test.go
@@ -662,10 +662,10 @@ func TestInstalledAgainHidesTheGhost(t *testing.T) {
 func TestDeletedStoreFile(t *testing.T) {
 	// A private folder.
 	dir := t.TempDir()
-	// With a PerformanceCompare results folder, the new folder sits beside it, in the project folder.
-	if got := deletedPathFor(filepath.Join(dir, "PerformanceCompare", "performance.json")); got != filepath.Join(dir, "deletedHistory", deletedFileName) {
+	// With a performanceCompare results folder, the new folder sits beside it, in the project folder.
+	if got := deletedPathFor(filepath.Join(dir, "performanceCompare", "performance.json")); got != filepath.Join(dir, "deletedHistory", deletedFileName) {
 		// Report it.
-		t.Errorf("path %q is not in the deletedHistory folder beside PerformanceCompare", got)
+		t.Errorf("path %q is not in the deletedHistory folder beside performanceCompare", got)
 	} // end of the path check
 	// With another results folder, the new folder sits beside the results file.
 	if got := deletedPathFor(filepath.Join(dir, "OllamaControlCenter", "performance.json")); got != filepath.Join(dir, "OllamaControlCenter", "deletedHistory", deletedFileName) {
@@ -928,10 +928,10 @@ func TestRestorePageLibraryNotes(t *testing.T) {
 
 // TestOldDeletedFileMovesToTheNewFolder checks that the list written by an earlier version is moved, never overwritten, and that nothing happens when there is nothing to move.
 func TestOldDeletedFileMovesToTheNewFolder(t *testing.T) {
-	// A project folder with a PerformanceCompare folder, as on the real machine.
+	// A project folder with a performanceCompare folder, as on the real machine.
 	root := t.TempDir()
 	// The results file path.
-	hist := filepath.Join(root, "PerformanceCompare", "performance.json")
+	hist := filepath.Join(root, "performanceCompare", "performance.json")
 	// The folder must exist.
 	if err := os.MkdirAll(filepath.Dir(hist), 0o700); err != nil {
 		// Stop the test.
@@ -943,7 +943,7 @@ func TestOldDeletedFileMovesToTheNewFolder(t *testing.T) {
 		t.Errorf("message %q with nothing to move", msg)
 	} // end of the empty check
 	// An old file from an earlier version.
-	oldFile := filepath.Join(root, "PerformanceCompare", deletedFileName)
+	oldFile := filepath.Join(root, "performanceCompare", deletedFileName)
 	// Write it.
 	if err := os.WriteFile(oldFile, []byte("old"), 0o600); err != nil {
 		// Stop the test.
diff --git a/deletestore.go b/deletestore.go
index f526941..5d5fbfa 100644
--- a/deletestore.go
+++ b/deletestore.go
@@ -64,7 +64,7 @@ type deletedStore struct {
 	note string
 } // end of deletedStore
 
-// deletedPathFor puts the file in its own folder, deletedHistory, next to the PerformanceCompare folder (that is, in the project folder); when the results are not in a PerformanceCompare folder, the folder goes beside the results file instead; an empty history path gives an empty path.
+// deletedPathFor puts the file in its own folder, deletedHistory, next to the performanceCompare folder (that is, in the project folder); when the results are not in a performanceCompare folder, the folder goes beside the results file instead; an empty history path gives an empty path.
 func deletedPathFor(historyPath string) string {
 	// No folder was found for the history, so none for this file either.
 	if historyPath == "" {
@@ -73,7 +73,7 @@ func deletedPathFor(historyPath string) string {
 	} // end of the memory case
 	// The folder of the results.
 	resultsDir := filepath.Dir(historyPath)
-	// A results folder named PerformanceCompare sits in the project folder; the new folder goes beside it.
+	// A results folder named performanceCompare sits in the project folder; the new folder goes beside it.
 	if filepath.Base(resultsDir) == historyFolderName {
 		// Go up one level.
 		resultsDir = filepath.Dir(resultsDir)
diff --git a/perf_test.go b/perf_test.go
index c18497f..1a0df6f 100644
--- a/perf_test.go
+++ b/perf_test.go
@@ -1108,9 +1108,9 @@ func TestDefaultHistoryPath(t *testing.T) {
 		want string
 	}{
 		// From the bin folder of the project.
-		{"/home/u/OllamaControlCenter/bin/OllamaControlCenter", nil, "/home/u/OllamaControlCenter/PerformanceCompare/performance.json"},
+		{"/home/u/OllamaControlCenter/bin/OllamaControlCenter", nil, "/home/u/OllamaControlCenter/performanceCompare/performance.json"},
 		// From any other folder: next to the program.
-		{"/opt/occ/OllamaControlCenter", nil, "/opt/occ/PerformanceCompare/performance.json"},
+		{"/opt/occ/OllamaControlCenter", nil, "/opt/occ/performanceCompare/performance.json"},
 		// Unknown place: the configuration folder.
 		{"", errors.New("no path"), "/cfg/OllamaControlCenter/performance.json"},
 	} {
diff --git a/perfstore.go b/perfstore.go
index 6837882..7ad24a2 100644
--- a/perfstore.go
+++ b/perfstore.go
@@ -46,12 +46,68 @@ type perfStore struct {
 } // end of perfStore
 
 // historyFolderName is the folder, next to the project, that holds the saved performance results.
-const historyFolderName = "PerformanceCompare"
+const historyFolderName = "performanceCompare"
+
+// oldHistoryFolderName is the name earlier versions used for that folder (with a capital P); a folder with this name is moved to the new name once.
+const oldHistoryFolderName = "PerformanceCompare"
+
+// moveOldHistoryFolder renames the folder of earlier versions (PerformanceCompare) to the current name, so saved results and copies are not left behind; it does nothing when there is no old folder or the new one exists already (that includes computers that do not tell the two names apart). The returned text is empty when all is well, or says in plain words what happened.
+func moveOldHistoryFolder(historyPath string) string {
+	// No file path: memory only, nothing to move.
+	if historyPath == "" {
+		// Nothing to do.
+		return ""
+	} // end of the memory check
+	// The current results folder.
+	newDir := filepath.Dir(historyPath)
+	// Only the project's own folder is touched, never a fallback folder.
+	if filepath.Base(newDir) != historyFolderName {
+		// Nothing to do.
+		return ""
+	} // end of the name check
+	// The folder of earlier versions, beside it.
+	oldDir := filepath.Join(filepath.Dir(newDir), oldHistoryFolderName)
+	// Is there an old folder?
+	if st, err := os.Stat(oldDir); err != nil || !st.IsDir() {
+		// None: leave everything as it is.
+		return ""
+	} // end of the old-folder check
+	// The new name exists already (or is the same folder on a computer that ignores capitals): leave both alone.
+	if _, err := os.Lstat(newDir); err == nil {
+		// Say it only when they really are two folders.
+		if os.SameFile(mustStat(oldDir), mustStat(newDir)) {
+			// The same folder: nothing to say.
+			return ""
+		} // end of the same-folder check
+		// Two folders: the person should look.
+		return "Both " + oldDir + " and " + newDir + " exist; the old one was left alone. Move its files by hand if you need them."
+	} // end of the new-folder check
+	// Rename the folder (same disk, so this is one step).
+	if err := os.Rename(oldDir, newDir); err != nil {
+		// The old folder stays where it is.
+		return "The results folder could not be renamed to " + newDir + " (" + err.Error() + "); the old folder was left where it is."
+	} // end of the rename check
+	// Done.
+	return ""
+} // end of moveOldHistoryFolder
+
+// mustStat returns the file information of a path that was just found to exist; a failure gives nil, which SameFile treats as "not the same".
+func mustStat(p string) os.FileInfo {
+	// Look at it.
+	st, err := os.Stat(p)
+	// A failure.
+	if err != nil {
+		// Nothing to compare.
+		return nil
+	} // end of the check
+	// The information.
+	return st
+} // end of mustStat
 
 // executablePath finds the running program; a test replaces it.
 var executablePath = os.Executable
 
-// defaultHistoryPath returns the history file: in a folder named PerformanceCompare next to the project (the program normally runs from the project's bin folder, so that is the folder above it), or, when the program's own place cannot be found, in the person's configuration folder; an empty text and a reason mean memory only.
+// defaultHistoryPath returns the history file: in a folder named performanceCompare next to the project (the program normally runs from the project's bin folder, so that is the folder above it), or, when the program's own place cannot be found, in the person's configuration folder; an empty text and a reason mean memory only.
 func defaultHistoryPath() (string, string) {
 	// Where is the running program?
 	if exe, err := executablePath(); err == nil && exe != "" {
diff --git a/perfstore_rename_test.go b/perfstore_rename_test.go
new file mode 100644
index 0000000..6f66d23
--- /dev/null
+++ b/perfstore_rename_test.go
@@ -0,0 +1,104 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// os makes the folders and reads the files.
+	"os"
+	// path/filepath builds paths in the test folder.
+	"path/filepath"
+	// strings searches the messages.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// TestOldResultsFolderIsRenamed checks that the folder of earlier versions is renamed with its files, that nothing is overwritten, and that fallback folders and memory-only stores are left alone.
+func TestOldResultsFolderIsRenamed(t *testing.T) {
+	// A project folder.
+	root := t.TempDir()
+	// The current results file path.
+	hist := filepath.Join(root, historyFolderName, "performance.json")
+	// Nothing exists yet: nothing to do.
+	if msg := moveOldHistoryFolder(hist); msg != "" {
+		// Report it.
+		t.Errorf("message %q with no old folder", msg)
+	} // end of the empty check
+	// An old folder with a results file and a copy.
+	old := filepath.Join(root, oldHistoryFolderName)
+	// Create it.
+	if err := os.MkdirAll(old, 0o700); err != nil {
+		// Stop the test.
+		t.Fatal(err)
+	} // end of the folder check
+	// Its files.
+	for _, f := range []string{"performance.json", "OllamaControlCenter-comparison-1.pdf"} {
+		// Write one.
+		if err := os.WriteFile(filepath.Join(old, f), []byte(f), 0o600); err != nil {
+			// Stop the test.
+			t.Fatal(err)
+		} // end of the write check
+	} // end of the files loop
+	// Rename.
+	if msg := moveOldHistoryFolder(hist); msg != "" {
+		// Report it.
+		t.Fatalf("message %q", msg)
+	} // end of the rename check
+	// The files are under the new name.
+	for _, f := range []string{"performance.json", "OllamaControlCenter-comparison-1.pdf"} {
+		// Read one.
+		if b, err := os.ReadFile(filepath.Join(root, historyFolderName, f)); err != nil || string(b) != f {
+			// Report it.
+			t.Errorf("%s: %q, %v", f, b, err)
+		} // end of the read check
+	} // end of the files loop
+	// The folder under the old name is gone (on a computer that ignores capitals the two names are one folder, so only check when they differ).
+	if _, err := os.Stat(old); err == nil && historyFolderName != oldHistoryFolderName {
+		// A case-blind disk answers for the new folder too; look at the real entry names.
+		ents, _ := os.ReadDir(root)
+		// Every entry.
+		for _, e := range ents {
+			// The old spelling must not remain.
+			if e.Name() == oldHistoryFolderName {
+				// Report it.
+				t.Errorf("the old folder name remains")
+			} // end of the name check
+		} // end of the entries loop
+	} // end of the old check
+	// Two folders with different names: both are left alone and the person is told (skipped on a computer that ignores capitals).
+	root2 := t.TempDir()
+	// Both exist.
+	if err := os.MkdirAll(filepath.Join(root2, historyFolderName), 0o700); err != nil {
+		// Stop the test.
+		t.Fatal(err)
+	} // end of the new folder
+	// The old one too.
+	if err := os.MkdirAll(filepath.Join(root2, oldHistoryFolderName), 0o700); err == nil {
+		// Are they really two folders?
+		ents, _ := os.ReadDir(root2)
+		// Two entries mean a case-sensitive disk.
+		if len(ents) == 2 {
+			// Try the rename.
+			msg := moveOldHistoryFolder(filepath.Join(root2, historyFolderName, "performance.json"))
+			// It must warn and leave both.
+			if !strings.Contains(msg, "exist") {
+				// Report it.
+				t.Errorf("message %q for two folders", msg)
+			} // end of the message check
+			// Both remain.
+			if ents2, _ := os.ReadDir(root2); len(ents2) != 2 {
+				// Report it.
+				t.Errorf("%d folders remain", len(ents2))
+			} // end of the remain check
+		} // end of the two-folders check
+	} // end of the old folder
+	// A fallback folder is never touched.
+	if msg := moveOldHistoryFolder(filepath.Join(root, "OllamaControlCenter", "performance.json")); msg != "" {
+		// Report it.
+		t.Errorf("message %q for a fallback folder", msg)
+	} // end of the fallback check
+	// Memory only.
+	if msg := moveOldHistoryFolder(""); msg != "" {
+		// Report it.
+		t.Errorf("message %q for memory only", msg)
+	} // end of the memory check
+} // end of TestOldResultsFolderIsRenamed
diff --git a/web.go b/web.go
index 6e717ea..79e02b8 100644
--- a/web.go
+++ b/web.go
@@ -132,6 +132,11 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	mux.HandleFunc("POST /modelfile", modelfileHandler(addr, token))
 	// Make the four performance handlers: the start page, the test run, and the two steps of clearing the saved results (the checks are in perfpage.go); the history lives in the person's configuration folder.
 	histPath, histNote := defaultHistoryPath()
+	// An earlier version named the results folder with a capital P; rename it before anything is opened, so the saved results are found.
+	if msg := moveOldHistoryFolder(histPath); msg != "" {
+		// Say so in the log.
+		log.Print(msg)
+	} // end of the rename check
 	// Open the saved results.
 	// One history store, shared by the performance pages and the comparison page.
 	perfHistory := openPerfStore(histPath, histNote)
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
680a10e7f712d10b2c90b7b0b36a180db24e571db7799b057386958a5063b94f  .gitignore
c0e522f2661519a0e547916d54b00f54b4b337122cd997cbff9c58d67e842286  compreport.go
b68448eef05cc472e156512e0eff5a42ff919e50e7f7571f291e0517e11558d4  compreport_test.go
308bbb9be7626a775495101fcacf822eea869431a809120d6093f2d0d2eafb33  delete_test.go
030fcdda19273874daee26bed568e7fc1400f7128f9a2440b88a17d724c4add9  deletestore.go
34abf5ccea9d01ebbeeb8eda610eec99be673f55b5bb3577eec17417e81067b2  perf_test.go
e40e5f9510497d0a4d4529ca5cf78cb2ddb1d49b3f4cbcca6a259c08f4a33c63  perfstore.go
29e49f393b24968c9d98c4c2b40b18ffd216a74c13e55e883b8eb5819c8c1c9f  web.go
7d51fbd12b001c9378e31afda1acb9938a725263a5b10ae6f26fb3238a86eeec  perfstore_rename_test.go
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
