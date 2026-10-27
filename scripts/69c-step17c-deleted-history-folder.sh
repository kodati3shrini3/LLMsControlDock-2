#!/usr/bin/env bash
# Script 69c: the list of deleted models now lives in its own folder, deletedHistory, in the project folder (an existing list is moved there once; the folder is kept out of GitHub).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/compare-groups" ] || { echo "FAIL  not on feature/compare-groups"; exit 1; }
# Script 69b must be applied already.
grep -q "func cmpBest" compgroup.go || { echo "FAIL  script 69b was not applied yet"; exit 1; }
# Refuse to run twice.
if grep -q "deletedFolderName" deletestore.go; then
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
index d9cbcfe..b314b01 100644
--- a/.gitignore
+++ b/.gitignore
@@ -18,6 +18,9 @@ history/
 # Saved performance test results (numbers about this machine): personal to each machine
 PerformanceCompare/
 
+# Remembered list of deleted models: personal to each machine
+deletedHistory/
+
 # Local user settings written by the app: personal to each machine
 settings.json
 
diff --git a/delete_test.go b/delete_test.go
index 09b0f10..b5fa2c5 100644
--- a/delete_test.go
+++ b/delete_test.go
@@ -443,7 +443,7 @@ func TestDeleteConfirmDeletesAndRemembers(t *testing.T) {
 		t.Errorf("%d delete requests, want 1", f.calls())
 	} // end of the call check
 	// The file exists and only the owner may read it.
-	info, err := os.Stat(filepath.Join(dir, deletedFileName))
+	info, err := os.Stat(filepath.Join(dir, deletedFolderName, deletedFileName))
 	// It must exist.
 	if err != nil {
 		// Stop the test.
@@ -559,7 +559,7 @@ func TestDeleteFailuresAreHonest(t *testing.T) {
 		t.Errorf("a failed delete was not reported: %s", body)
 	} // end of the failure check
 	// Nothing remembered.
-	if _, err := os.Stat(filepath.Join(dir, deletedFileName)); err == nil {
+	if _, err := os.Stat(filepath.Join(dir, deletedFolderName, deletedFileName)); err == nil {
 		// Report it.
 		t.Errorf("a failed delete was remembered as deleted")
 	} // end of the memory check
@@ -662,11 +662,16 @@ func TestInstalledAgainHidesTheGhost(t *testing.T) {
 func TestDeletedStoreFile(t *testing.T) {
 	// A private folder.
 	dir := t.TempDir()
-	// The path comes from the history path.
-	if got := deletedPathFor(filepath.Join(dir, "PerformanceCompare", "performance.json")); got != filepath.Join(dir, "PerformanceCompare", deletedFileName) {
+	// With a PerformanceCompare results folder, the new folder sits beside it, in the project folder.
+	if got := deletedPathFor(filepath.Join(dir, "PerformanceCompare", "performance.json")); got != filepath.Join(dir, "deletedHistory", deletedFileName) {
 		// Report it.
-		t.Errorf("path %q is not next to the history", got)
+		t.Errorf("path %q is not in the deletedHistory folder beside PerformanceCompare", got)
 	} // end of the path check
+	// With another results folder, the new folder sits beside the results file.
+	if got := deletedPathFor(filepath.Join(dir, "OllamaControlCenter", "performance.json")); got != filepath.Join(dir, "OllamaControlCenter", "deletedHistory", deletedFileName) {
+		// Report it.
+		t.Errorf("path %q for the fallback folder", got)
+	} // end of the fallback check
 	// No history path means memory only.
 	if deletedPathFor("") != "" {
 		// Report it.
@@ -920,3 +925,72 @@ func TestRestorePageLibraryNotes(t *testing.T) {
 		t.Errorf("restore page (missing) wrong: %s", body)
 	} // end of the missing check
 } // end of TestRestorePageLibraryNotes
+
+// TestOldDeletedFileMovesToTheNewFolder checks that the list written by an earlier version is moved, never overwritten, and that nothing happens when there is nothing to move.
+func TestOldDeletedFileMovesToTheNewFolder(t *testing.T) {
+	// A project folder with a PerformanceCompare folder, as on the real machine.
+	root := t.TempDir()
+	// The results file path.
+	hist := filepath.Join(root, "PerformanceCompare", "performance.json")
+	// The folder must exist.
+	if err := os.MkdirAll(filepath.Dir(hist), 0o700); err != nil {
+		// Stop the test.
+		t.Fatal(err)
+	} // end of the folder check
+	// Nothing to move yet.
+	if msg := moveOldDeletedFile(hist); msg != "" {
+		// Report it.
+		t.Errorf("message %q with nothing to move", msg)
+	} // end of the empty check
+	// An old file from an earlier version.
+	oldFile := filepath.Join(root, "PerformanceCompare", deletedFileName)
+	// Write it.
+	if err := os.WriteFile(oldFile, []byte("old"), 0o600); err != nil {
+		// Stop the test.
+		t.Fatal(err)
+	} // end of the write check
+	// Move it.
+	if msg := moveOldDeletedFile(hist); msg != "" {
+		// Report it.
+		t.Fatalf("message %q", msg)
+	} // end of the move check
+	// The new place holds it, the old place is empty.
+	newFile := filepath.Join(root, "deletedHistory", deletedFileName)
+	// Read the new file.
+	if b, err := os.ReadFile(newFile); err != nil || string(b) != "old" {
+		// Report it.
+		t.Errorf("new file %q, error %v", b, err)
+	} // end of the content check
+	// The old file is gone.
+	if _, err := os.Stat(oldFile); err == nil {
+		// Report it.
+		t.Errorf("the old file is still there")
+	} // end of the old-file check
+	// The new folder is private.
+	if st, err := os.Stat(filepath.Dir(newFile)); err != nil || st.Mode().Perm() != 0o700 {
+		// Report it.
+		t.Errorf("folder mode %v, error %v", st, err)
+	} // end of the mode check
+	// A second old file never overwrites the new one.
+	if err := os.WriteFile(oldFile, []byte("second"), 0o600); err != nil {
+		// Stop the test.
+		t.Fatal(err)
+	} // end of the write check
+	// Try again.
+	moveOldDeletedFile(hist)
+	// The new file keeps its content.
+	if b, _ := os.ReadFile(newFile); string(b) != "old" {
+		// Report it.
+		t.Errorf("the new file was overwritten: %q", b)
+	} // end of the overwrite check
+	// The second old file stays where it is.
+	if b, _ := os.ReadFile(oldFile); string(b) != "second" {
+		// Report it.
+		t.Errorf("the old file was changed: %q", b)
+	} // end of the stay check
+	// A memory-only store has nothing to move.
+	if moveOldDeletedFile("") != "" {
+		// Report it.
+		t.Errorf("a message for a memory-only store")
+	} // end of the memory check
+} // end of TestOldDeletedFileMovesToTheNewFolder
diff --git a/deletestore.go b/deletestore.go
index 2289b30..f526941 100644
--- a/deletestore.go
+++ b/deletestore.go
@@ -23,9 +23,12 @@ import ( // import lists the standard-library packages this file uses.
 // deletedFileVersion is written into the file so a future version of the program can recognise an older layout.
 const deletedFileVersion = 1
 
-// deletedFileName is the file that remembers deleted models; it sits next to the performance history, which the .gitignore already keeps out of GitHub (requirement S4).
+// deletedFileName is the file that remembers deleted models.
 const deletedFileName = "deleted-models.json"
 
+// deletedFolderName is the folder, next to the project, that holds that file; the .gitignore keeps it out of GitHub (requirement S4).
+const deletedFolderName = "deletedHistory"
+
 // maxDeletedFile is the biggest file that will be read; a normal list is a few kilobytes.
 const maxDeletedFile = 1 * 1024 * 1024
 
@@ -61,17 +64,64 @@ type deletedStore struct {
 	note string
 } // end of deletedStore
 
-// deletedPathFor puts the file in the same folder as the performance history; an empty history path gives an empty path.
+// deletedPathFor puts the file in its own folder, deletedHistory, next to the PerformanceCompare folder (that is, in the project folder); when the results are not in a PerformanceCompare folder, the folder goes beside the results file instead; an empty history path gives an empty path.
 func deletedPathFor(historyPath string) string {
 	// No folder was found for the history, so none for this file either.
 	if historyPath == "" {
 		// Memory only.
 		return ""
 	} // end of the memory case
-	// Same folder, other file name.
-	return filepath.Join(filepath.Dir(historyPath), deletedFileName)
+	// The folder of the results.
+	resultsDir := filepath.Dir(historyPath)
+	// A results folder named PerformanceCompare sits in the project folder; the new folder goes beside it.
+	if filepath.Base(resultsDir) == historyFolderName {
+		// Go up one level.
+		resultsDir = filepath.Dir(resultsDir)
+	} // end of the folder check
+	// Own folder, then the file name.
+	return filepath.Join(resultsDir, deletedFolderName, deletedFileName)
 } // end of deletedPathFor
 
+// moveOldDeletedFile moves the list from the place earlier versions used (next to the performance results) to the new folder, so nothing already remembered is lost; it does nothing when there is no old file or the new file exists already. The returned text is empty when all is well, or says in plain words what went wrong.
+func moveOldDeletedFile(historyPath string) string {
+	// No history path: nothing to move.
+	if historyPath == "" {
+		// Nothing to do.
+		return ""
+	} // end of the memory case
+	// Where earlier versions kept the file.
+	oldPath := filepath.Join(filepath.Dir(historyPath), deletedFileName)
+	// Where it belongs now.
+	newPath := deletedPathFor(historyPath)
+	// The same place: nothing to move.
+	if oldPath == newPath {
+		// Nothing to do.
+		return ""
+	} // end of the same-place check
+	// Is there an old file?
+	if _, err := os.Stat(oldPath); err != nil {
+		// None (or unreadable): leave everything as it is.
+		return ""
+	} // end of the old-file check
+	// A new file is never overwritten.
+	if _, err := os.Stat(newPath); err == nil {
+		// Leave both alone.
+		return ""
+	} // end of the new-file check
+	// The new folder, readable only by this user.
+	if err := os.MkdirAll(filepath.Dir(newPath), 0o700); err != nil {
+		// The old file stays where it is.
+		return "The list of deleted models could not be moved to its new folder (" + err.Error() + "); the old file was left where it is."
+	} // end of the folder check
+	// Move the file (same disk, so this is one step).
+	if err := os.Rename(oldPath, newPath); err != nil {
+		// The old file stays where it is.
+		return "The list of deleted models could not be moved to its new folder (" + err.Error() + "); the old file was left where it is."
+	} // end of the move check
+	// Done.
+	return ""
+} // end of moveOldDeletedFile
+
 // openDeletedStore reads the file if there is one; a missing file is normal (nothing deleted yet), a damaged one is left alone and the list is kept in memory only.
 func openDeletedStore(path string) *deletedStore {
 	// Start with an empty list.
diff --git a/web.go b/web.go
index d933256..6e717ea 100644
--- a/web.go
+++ b/web.go
@@ -135,7 +135,12 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	// Open the saved results.
 	// One history store, shared by the performance pages and the comparison page.
 	perfHistory := openPerfStore(histPath, histNote)
-	// The deleted models are remembered in a small file next to the history (kept out of GitHub by .gitignore).
+	// An older version kept the list of deleted models next to the results; bring it to the new folder first.
+	if msg := moveOldDeletedFile(histPath); msg != "" {
+		// Say so in the log; the list is then simply empty until the file can be moved.
+		log.Print(msg)
+	} // end of the move check
+	// The deleted models are remembered in a small file in the deletedHistory folder (kept out of GitHub by .gitignore).
 	deletedList := openDeletedStore(deletedPathFor(histPath))
 	// The folder for the snapshots of deleted models' parameters ("history" next to the program, kept out of GitHub by .gitignore).
 	histDir, histDirNote := defaultHistoryDir()
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
058ebe7b7cf82ef9956adcffe66c9cdb5037cc78230541a3de9111c1ec98aca9  deletestore.go
8d645ccf362936ff5c7dfce43e77f69e513a321e2cdfb02bef895783ce71face  delete_test.go
d46d2c802199cf240b58f90087b73aed9a66ef2b30d823ad3259ba336e035d6f  web.go
d6ff37ed3af8c90d48cb8cd938fa3ead8ef1f44d72c89bdcb85f4168171e883f  .gitignore
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
