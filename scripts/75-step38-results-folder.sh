#!/usr/bin/env bash
# Script 75: everything the program saves (the performance results, the saved PDF and CSV copies, the list of deleted models and the parameter snapshots) now lives in one folder on every system: OllamaControlCenter inside the user's configuration folder (Linux: ~/.config, Windows: %AppData%, macOS: ~/Library/Application Support), next to settings.json. Earlier versions kept them next to the program; at the first start the program COPIES its own files from there to the new folder once, and leaves the old folders in place. The version becomes 0.25.0.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/results-folder" ] || { echo "FAIL  not on feature/results-folder"; exit 1; }
# Refuse to run twice.
if [ -e datafolder.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/about.go b/about.go
index bb8c05e..8b53862 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.24.0"
+const appVersion = "0.25.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/datafolder.go b/datafolder.go
new file mode 100644
index 0000000..334c440
--- /dev/null
+++ b/datafolder.go
@@ -0,0 +1,191 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// fmt builds the messages.
+	"fmt"
+	// io copies a file.
+	"io"
+	// os reads and writes the folders and files.
+	"os"
+	// path/filepath joins the folder and file names.
+	"path/filepath"
+	// regexp recognises the file names this program writes.
+	"regexp"
+	// strings checks name beginnings and endings.
+	"strings"
+) // end of imports
+
+// dataFolderName is the folder, inside the person's configuration folder, that holds everything the program saves (settings, results, deleted models, snapshots, saved copies).
+const dataFolderName = "OllamaControlCenter"
+
+// maxMigrateBytes is the largest file that is copied from an old folder; a bigger file is never one of this program's own.
+var maxMigrateBytes int64 = 100 << 20
+
+// dataRoot returns the one folder where all saved data lives on every operating system: OllamaControlCenter inside the configuration folder (Linux: ~/.config, Windows: %AppData%, macOS: ~/Library/Application Support); it returns empty text when no configuration folder is known.
+func dataRoot() string {
+	// Ask Go for the configuration folder (a test replaces userConfigDir).
+	dir, err := userConfigDir()
+	// None found.
+	if err != nil || dir == "" {
+		// The caller keeps the data in memory and says why.
+		return ""
+	} // end of the lookup check
+	// The program's own folder inside it.
+	return filepath.Join(dir, dataFolderName)
+} // end of dataRoot
+
+// oldDataRoot returns the folder earlier versions used for the saved data: the folder the program is in, or the folder above it when the program sits in a folder called bin; it returns empty text when the program's place is unknown.
+func oldDataRoot() string {
+	// Where is the running program?
+	exe, err := executablePath()
+	// Unknown.
+	if err != nil || exe == "" {
+		// Nothing to look at.
+		return ""
+	} // end of the program check
+	// The folder that holds it.
+	dir := filepath.Dir(exe)
+	// A program inside bin belongs to the project folder above it.
+	if filepath.Base(dir) == "bin" {
+		// Go one level up.
+		dir = filepath.Dir(dir)
+	} // end of the bin check
+	// The old data folder.
+	return dir
+} // end of oldDataRoot
+
+// stampedName matches the names this program gives to the files it saves with a date: 2026-11-02_17-54-00...
+var stampedName = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}`)
+
+// looksOurs says whether a file name is one this program writes (and so may be copied): the results file, the deleted-models file, a dated snapshot, or a saved copy of a download; and only the kinds of file it writes.
+func looksOurs(name string) bool {
+	// Only these kinds of file are ever written.
+	ext := strings.ToLower(filepath.Ext(name))
+	// Anything else is somebody else's file.
+	if ext != ".json" && ext != ".csv" && ext != ".pdf" {
+		// Not ours.
+		return false
+	} // end of the kind check
+	// The two fixed names, the saved copies and the dated files.
+	return name == "performance.json" || name == deletedFileName || strings.HasPrefix(name, "OllamaControlCenter-") || stampedName.MatchString(name)
+} // end of looksOurs
+
+// copyOne copies one file into a new file that only this user can read; an existing file is never overwritten.
+func copyOne(src, dst string) error {
+	// Open the source.
+	in, err := os.Open(src)
+	// Not readable.
+	if err != nil {
+		// Give up with the reason.
+		return err
+	} // end of the open check
+	// Close it at the end.
+	defer in.Close()
+	// Create the target; O_EXCL refuses an existing file.
+	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
+	// Cannot create.
+	if err != nil {
+		// Give up with the reason.
+		return err
+	} // end of the create check
+	// Copy the bytes.
+	if _, err := io.Copy(out, in); err != nil {
+		// Close and give up.
+		out.Close()
+		// The reason.
+		return err
+	} // end of the copy check
+	// Closing is where a full disk shows up.
+	return out.Close()
+} // end of copyOne
+
+// migrateFolder copies this program's own files from an old folder into the new one, once: it does nothing when the old folder is missing, holds none of this program's files, or the new folder exists already; the old folder is never changed. It returns a sentence for the log, or empty text.
+func migrateFolder(oldDir, newDir string) string {
+	// Is there an old folder?
+	if st, err := os.Stat(oldDir); err != nil || !st.IsDir() {
+		// None: nothing to do.
+		return ""
+	} // end of the old-folder check
+	// The new folder exists already: it is never touched, and this also makes the copy happen only once.
+	if _, err := os.Lstat(newDir); err == nil {
+		// Nothing to do.
+		return ""
+	} // end of the new-folder check
+	// What is in the old folder.
+	entries, err := os.ReadDir(oldDir)
+	// Unreadable: leave it.
+	if err != nil {
+		// Nothing to do.
+		return ""
+	} // end of the read check
+	// The files to copy.
+	var names []string
+	// Look at each entry.
+	for _, e := range entries {
+		// Only plain files of this program's kind, of a sensible size.
+		if info, err := e.Info(); err == nil && e.Type().IsRegular() && looksOurs(e.Name()) && info.Size() <= maxMigrateBytes {
+			// Keep it.
+			names = append(names, e.Name())
+		} // end of the file check
+	} // end of the entry loop
+	// None of this program's files: the folder belongs to somebody else.
+	if len(names) == 0 {
+		// Nothing to do.
+		return ""
+	} // end of the empty check
+	// Make sure the parent folder exists.
+	if err := os.MkdirAll(filepath.Dir(newDir), 0o700); err != nil {
+		// Say so; the old data stays where it is.
+		return fmt.Sprintf("Saved data could not be copied from %s (%v); it was left where it is.", oldDir, err)
+	} // end of the parent check
+	// Copy into a temporary folder first, so a half copy is never mistaken for the real one.
+	tmp := newDir + ".copying"
+	// A leftover from an earlier attempt is this program's own and is removed.
+	os.RemoveAll(tmp)
+	// Make it, readable only by this user.
+	if err := os.Mkdir(tmp, 0o700); err != nil {
+		// Say so.
+		return fmt.Sprintf("Saved data could not be copied from %s (%v); it was left where it is.", oldDir, err)
+	} // end of the temporary-folder check
+	// Copy each file.
+	for _, n := range names {
+		// One file.
+		if err := copyOne(filepath.Join(oldDir, n), filepath.Join(tmp, n)); err != nil {
+			// Throw the half copy away.
+			os.RemoveAll(tmp)
+			// Say so.
+			return fmt.Sprintf("Saved data could not be copied from %s (%v); it was left where it is.", oldDir, err)
+		} // end of the copy check
+	} // end of the copy loop
+	// Put the finished copy in its place in one step.
+	if err := os.Rename(tmp, newDir); err != nil {
+		// Throw the copy away.
+		os.RemoveAll(tmp)
+		// Say so.
+		return fmt.Sprintf("Saved data could not be copied from %s (%v); it was left where it is.", oldDir, err)
+	} // end of the rename check
+	// Done: tell the person where things are now.
+	return fmt.Sprintf("Copied %d saved file(s) from %s to %s; the old folder was left in place and can be deleted when it is no longer needed.", len(names), oldDir, newDir)
+} // end of migrateFolder
+
+// migrateOldData copies the three folders of earlier versions (results, deleted models, snapshots) from the old place to the new one; it returns the sentences for the log.
+func migrateOldData(oldRoot, newRoot string) []string {
+	// Unknown places, or the same place: nothing to do.
+	if oldRoot == "" || newRoot == "" || oldRoot == newRoot {
+		// Nothing to do.
+		return nil
+	} // end of the place check
+	// The sentences.
+	var msgs []string
+	// The three folders earlier versions kept next to the program.
+	for _, name := range []string{historyFolderName, deletedFolderName, historyDirName} {
+		// Copy one.
+		if msg := migrateFolder(filepath.Join(oldRoot, name), filepath.Join(newRoot, name)); msg != "" {
+			// Keep the sentence.
+			msgs = append(msgs, msg)
+		} // end of the message check
+	} // end of the folder loop
+	// Hand them back.
+	return msgs
+} // end of migrateOldData
diff --git a/datafolder_test.go b/datafolder_test.go
new file mode 100644
index 0000000..a8a45cf
--- /dev/null
+++ b/datafolder_test.go
@@ -0,0 +1,295 @@
+// Package main tells Go that this test file belongs to the same program as datafolder.go.
+package main
+
+import ( // import lists the packages this test file uses.
+	// errors builds the "no path" error.
+	"errors"
+	// os reads and writes the folders of the tests.
+	"os"
+	// path/filepath joins file names.
+	"path/filepath"
+	// strings searches the log sentences.
+	"strings"
+	// testing is Go's built-in test framework.
+	"testing"
+) // end of imports
+
+// writeTestFile writes one file for a test, making its folder first.
+func writeTestFile(t *testing.T, path, text string) {
+	// Mark this as a helper.
+	t.Helper()
+	// The folder.
+	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
+		// Stop the test.
+		t.Fatalf("fixture folder: %v", err)
+	} // end of the folder check
+	// The file.
+	if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
+		// Stop the test.
+		t.Fatalf("fixture file: %v", err)
+	} // end of the file check
+} // end of writeTestFile
+
+// TestLooksOurs checks which file names count as this program's own.
+func TestLooksOurs(t *testing.T) {
+	// The cases.
+	for name, want := range map[string]bool{
+		// The results file.
+		"performance.json": true,
+		// The deleted-models file.
+		"deleted-models.json": true,
+		// A snapshot with a date.
+		"2026-11-02_17-54-00+0100_llama3-8b.json": true,
+		// A saved copy of a download.
+		"OllamaControlCenter-comparison-20261102-175400+0100.pdf": true,
+		// A saved copy as a table.
+		"OllamaControlCenter-comparison-20261102-175400+0100.csv": true,
+		// Somebody else's JSON file.
+		"settings-backup.json": false,
+		// Somebody else's text file.
+		"notes.txt": false,
+		// A program with a dated name is not one of ours.
+		"2026-11-02_17-54-00_setup.exe": false,
+		// No extension.
+		"performance": false,
+	} { // end of the cases
+		// Check it.
+		if got := looksOurs(name); got != want {
+			// Report the problem.
+			t.Errorf("looksOurs(%q) = %v, want %v", name, got, want)
+		} // end of the check
+	} // end of the loop
+} // end of TestLooksOurs
+
+// TestDataRootAndOldDataRoot checks the new and the old data folders.
+func TestDataRootAndOldDataRoot(t *testing.T) {
+	// Keep and restore the two lookups.
+	oldExe, oldCfg := executablePath, userConfigDir
+	// Put them back afterwards.
+	t.Cleanup(func() { executablePath, userConfigDir = oldExe, oldCfg })
+	// A configuration folder.
+	userConfigDir = func() (string, error) { return "/cfg", nil }
+	// The new folder.
+	if got := dataRoot(); got != filepath.Join("/cfg", "OllamaControlCenter") {
+		// Report the problem.
+		t.Errorf("dataRoot = %q", got)
+	} // end of the new-folder check
+	// No configuration folder.
+	userConfigDir = func() (string, error) { return "", errors.New("none") }
+	// Nothing.
+	if got := dataRoot(); got != "" {
+		// Report the problem.
+		t.Errorf("dataRoot without a folder = %q", got)
+	} // end of the empty check
+	// A program inside bin: the project folder above it.
+	executablePath = func() (string, error) { return "/p/OllamaControlCenter/bin/occ", nil }
+	// The old folder.
+	if got := oldDataRoot(); got != filepath.FromSlash("/p/OllamaControlCenter") {
+		// Report the problem.
+		t.Errorf("old root from bin = %q", got)
+	} // end of the bin check
+	// A program elsewhere: its own folder.
+	executablePath = func() (string, error) { return "/opt/occ/occ", nil }
+	// The old folder.
+	if got := oldDataRoot(); got != filepath.FromSlash("/opt/occ") {
+		// Report the problem.
+		t.Errorf("old root plain = %q", got)
+	} // end of the plain check
+	// Unknown program place.
+	executablePath = func() (string, error) { return "", errors.New("no path") }
+	// Nothing.
+	if got := oldDataRoot(); got != "" {
+		// Report the problem.
+		t.Errorf("old root unknown = %q", got)
+	} // end of the unknown check
+} // end of TestDataRootAndOldDataRoot
+
+// TestMigrateOldData checks the one-time copy: the program's own files are copied, other files are not, the old folders stay as they are, and a second run does nothing.
+func TestMigrateOldData(t *testing.T) {
+	// A fresh place for the old and the new folders.
+	base := t.TempDir()
+	// The old project folder and the new data folder.
+	oldRoot, newRoot := filepath.Join(base, "project"), filepath.Join(base, "cfg", "OllamaControlCenter")
+	// Old results, with a saved copy and a stranger's file.
+	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "performance.json"), "RESULTS")
+	// A saved copy.
+	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "OllamaControlCenter-comparison-1.pdf"), "PDF")
+	// A stranger's file in the same folder.
+	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "my-notes.txt"), "NOTES")
+	// The deleted-models list.
+	writeTestFile(t, filepath.Join(oldRoot, "deletedHistory", "deleted-models.json"), "DELETED")
+	// A snapshot.
+	writeTestFile(t, filepath.Join(oldRoot, "history", "2026-11-02_17-54-00+0100_m.json"), "SNAP")
+	// Copy.
+	msgs := migrateOldData(oldRoot, newRoot)
+	// One sentence per folder.
+	if len(msgs) != 3 {
+		// Report the problem.
+		t.Fatalf("messages: %q", msgs)
+	} // end of the message check
+	// The first sentence names the two places and the number of files.
+	if !strings.Contains(msgs[0], "Copied 2 saved file(s)") || !strings.Contains(msgs[0], oldRoot) || !strings.Contains(msgs[0], newRoot) {
+		// Report the problem.
+		t.Errorf("sentence: %q", msgs[0])
+	} // end of the sentence check
+	// What must be in the new place.
+	for rel, want := range map[string]string{
+		// The results.
+		"performanceCompare/performance.json": "RESULTS",
+		// The saved copy.
+		"performanceCompare/OllamaControlCenter-comparison-1.pdf": "PDF",
+		// The deleted models.
+		"deletedHistory/deleted-models.json": "DELETED",
+		// The snapshot.
+		"history/2026-11-02_17-54-00+0100_m.json": "SNAP",
+	} { // end of the expected files
+		// Read it.
+		b, err := os.ReadFile(filepath.Join(newRoot, filepath.FromSlash(rel)))
+		// It must be there with the same content.
+		if err != nil || string(b) != want {
+			// Report the problem.
+			t.Errorf("%s: %q, %v", rel, b, err)
+		} // end of the content check
+	} // end of the loop
+	// The stranger's file is not copied.
+	if _, err := os.Stat(filepath.Join(newRoot, "performanceCompare", "my-notes.txt")); err == nil {
+		// Report the problem.
+		t.Error("a file that is not ours was copied")
+	} // end of the stranger check
+	// The old files are all still there.
+	for _, rel := range []string{"performanceCompare/performance.json", "performanceCompare/my-notes.txt", "deletedHistory/deleted-models.json", "history/2026-11-02_17-54-00+0100_m.json"} {
+		// Look.
+		if _, err := os.Stat(filepath.Join(oldRoot, filepath.FromSlash(rel))); err != nil {
+			// Report the problem.
+			t.Errorf("the old file %s is gone", rel)
+		} // end of the check
+	} // end of the loop
+	// The copy is private and no temporary folder is left.
+	if st, err := os.Stat(filepath.Join(newRoot, "performanceCompare")); err != nil || st.Mode().Perm() != 0o700 {
+		// Report the problem.
+		t.Errorf("new folder: %v %v", st, err)
+	} // end of the privacy check
+	// No leftovers.
+	if _, err := os.Stat(filepath.Join(newRoot, "performanceCompare.copying")); err == nil {
+		// Report the problem.
+		t.Error("a temporary folder was left")
+	} // end of the leftover check
+	// New data is never overwritten by a second start, even when the old files change.
+	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "performance.json"), "CHANGED")
+	// Second start.
+	if msgs := migrateOldData(oldRoot, newRoot); len(msgs) != 0 {
+		// Report the problem.
+		t.Errorf("second run: %q", msgs)
+	} // end of the second-run check
+	// The new content is as before.
+	if b, _ := os.ReadFile(filepath.Join(newRoot, "performanceCompare", "performance.json")); string(b) != "RESULTS" {
+		// Report the problem.
+		t.Errorf("the new file was overwritten: %q", b)
+	} // end of the overwrite check
+} // end of TestMigrateOldData
+
+// TestMigrateSkipsOtherPeoplesFolders checks that a folder with the same name but none of this program's files is left alone, and that nothing happens for unknown or equal places.
+func TestMigrateSkipsOtherPeoplesFolders(t *testing.T) {
+	// A fresh place.
+	base := t.TempDir()
+	// The old and new folders.
+	oldRoot, newRoot := filepath.Join(base, "Downloads"), filepath.Join(base, "cfg")
+	// A "history" folder full of somebody else's files.
+	writeTestFile(t, filepath.Join(oldRoot, "history", "browser.json"), "X")
+	// Another one.
+	writeTestFile(t, filepath.Join(oldRoot, "history", "report.pdf"), "X")
+	// Copy.
+	if msgs := migrateOldData(oldRoot, newRoot); len(msgs) != 0 {
+		// Report the problem.
+		t.Errorf("messages: %q", msgs)
+	} // end of the message check
+	// Nothing was created.
+	if _, err := os.Stat(newRoot); err == nil {
+		// Report the problem.
+		t.Error("a folder was created for somebody else's files")
+	} // end of the creation check
+	// Unknown or equal places do nothing.
+	if migrateOldData("", newRoot) != nil || migrateOldData(oldRoot, "") != nil || migrateOldData(oldRoot, oldRoot) != nil {
+		// Report the problem.
+		t.Error("an unknown or equal place did something")
+	} // end of the place check
+} // end of TestMigrateSkipsOtherPeoplesFolders
+
+// TestMigrateRules checks the size limit, an existing new folder and a leftover temporary folder.
+func TestMigrateRules(t *testing.T) {
+	// Put the limit back when the test ends.
+	oldMax := maxMigrateBytes
+	// Restore it.
+	t.Cleanup(func() { maxMigrateBytes = oldMax })
+	// A fresh place.
+	base := t.TempDir()
+	// The old and new folders.
+	oldRoot, newRoot := filepath.Join(base, "p"), filepath.Join(base, "cfg")
+	// A small result and a large one.
+	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "performance.json"), "ok")
+	// A file bigger than the limit set below.
+	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "OllamaControlCenter-big.pdf"), "0123456789")
+	// A small limit.
+	maxMigrateBytes = 5
+	// A leftover temporary folder from an earlier attempt.
+	writeTestFile(t, filepath.Join(newRoot, "performanceCompare.copying", "junk.json"), "junk")
+	// Copy.
+	if msgs := migrateOldData(oldRoot, newRoot); len(msgs) != 1 || !strings.Contains(msgs[0], "Copied 1 saved file(s)") {
+		// Report the problem.
+		t.Fatalf("messages: %q", msgs)
+	} // end of the message check
+	// The big file stayed behind.
+	if _, err := os.Stat(filepath.Join(newRoot, "performanceCompare", "OllamaControlCenter-big.pdf")); err == nil {
+		// Report the problem.
+		t.Error("a file over the limit was copied")
+	} // end of the size check
+	// The leftover is gone.
+	if _, err := os.Stat(filepath.Join(newRoot, "performanceCompare.copying")); err == nil {
+		// Report the problem.
+		t.Error("the leftover folder is still there")
+	} // end of the leftover check
+	// An existing new folder is never touched: a second old folder with a new file does not change it.
+	writeTestFile(t, filepath.Join(oldRoot, "deletedHistory", "deleted-models.json"), "D")
+	// The new folder exists already (empty).
+	if err := os.MkdirAll(filepath.Join(newRoot, "deletedHistory"), 0o700); err != nil {
+		// Stop the test.
+		t.Fatalf("fixture: %v", err)
+	} // end of the folder check
+	// Copy again.
+	if msgs := migrateOldData(oldRoot, newRoot); len(msgs) != 0 {
+		// Report the problem.
+		t.Errorf("an existing folder was touched: %q", msgs)
+	} // end of the existing check
+	// It is still empty.
+	if es, _ := os.ReadDir(filepath.Join(newRoot, "deletedHistory")); len(es) != 0 {
+		// Report the problem.
+		t.Error("files were put into an existing folder")
+	} // end of the empty check
+} // end of TestMigrateRules
+
+// TestStartupCopiesOldData checks the wiring: building the web interface copies the old results of the program's own folder into the data folder, so the saved results are found.
+func TestStartupCopiesOldData(t *testing.T) {
+	// Keep and restore the two lookups.
+	oldExe, oldCfg := executablePath, userConfigDir
+	// Put them back afterwards.
+	t.Cleanup(func() { executablePath, userConfigDir = oldExe, oldCfg })
+	// A fresh place.
+	base := t.TempDir()
+	// A project with its bin folder and old results.
+	project := filepath.Join(base, "project")
+	// The old results.
+	writeTestFile(t, filepath.Join(project, "performanceCompare", "performance.json"), `{"runs":[]}`)
+	// The program is in bin.
+	executablePath = func() (string, error) { return filepath.Join(project, "bin", "occ"), nil }
+	// The configuration folder.
+	cfg := filepath.Join(base, "cfg")
+	// Use it.
+	userConfigDir = func() (string, error) { return cfg, nil }
+	// Build the web interface the way the program does.
+	handlerFor(t, "http://127.0.0.1:11434")
+	// The old results are now in the data folder.
+	if b, err := os.ReadFile(filepath.Join(cfg, "OllamaControlCenter", "performanceCompare", "performance.json")); err != nil || string(b) != `{"runs":[]}` {
+		// Report the problem.
+		t.Errorf("not copied at start-up: %q, %v", b, err)
+	} // end of the copy check
+} // end of TestStartupCopiesOldData
diff --git a/history.go b/history.go
index 531721a..e7fabd7 100644
--- a/history.go
+++ b/history.go
@@ -73,29 +73,17 @@ type historyStore struct {
 	note string
 } // end of historyStore
 
-// defaultHistoryDir picks the folder: "history" next to the program's folder (the same project folder as the performance results), or in the user's config folder when the program's place is unknown.
+// defaultHistoryDir picks the folder: "history" inside the program's data folder (the person's configuration folder, the same on every system); empty text and a reason mean nothing can be kept.
 func defaultHistoryDir() (string, string) {
-	// Next to the program, one level above a "bin" folder.
-	if exe, err := executablePath(); err == nil && exe != "" {
-		// The folder the program is in.
-		dir := filepath.Dir(exe)
-		// A program inside "bin" belongs to the project folder above it.
-		if filepath.Base(dir) == "bin" {
-			// Go one level up.
-			dir = filepath.Dir(dir)
-		} // end of the bin check
-		// The history folder.
-		return filepath.Join(dir, historyDirName), ""
-	} // end of the program check
-	// Otherwise the user's own config folder.
-	dir, err := userConfigDir()
-	// Nothing found.
-	if err != nil || dir == "" {
+	// The one data folder.
+	root := dataRoot()
+	// None found.
+	if root == "" {
 		// Say so in words.
 		return "", "No folder for the history was found, so no snapshots are kept."
 	} // end of the lookup check
-	// The history folder in the config folder.
-	return filepath.Join(dir, "OllamaControlCenter", historyDirName), ""
+	// The history folder in the data folder.
+	return filepath.Join(root, historyDirName), ""
 } // end of defaultHistoryDir
 
 // unsafeNameChars matches every character that is not safe inside a file name.
diff --git a/history_test.go b/history_test.go
index ed3401e..db8b53d 100644
--- a/history_test.go
+++ b/history_test.go
@@ -303,42 +303,31 @@ func TestHistoryFolderStaysOutOfGitHub(t *testing.T) {
 	} // end of the ignore check
 } // end of TestHistoryFolderStaysOutOfGitHub
 
-// TestDefaultHistoryDir checks the folder choice: next to the program, one level above bin, with a fallback in the config folder.
+// TestDefaultHistoryDir checks the folder choice: always "history" in the data folder inside the configuration folder, wherever the program is.
 func TestDefaultHistoryDir(t *testing.T) {
 	// Keep and restore the two lookups.
 	oldExe, oldCfg := executablePath, userConfigDir
 	// Put them back afterwards.
 	t.Cleanup(func() { executablePath, userConfigDir = oldExe, oldCfg })
-	// A program inside bin.
-	executablePath = func() (string, error) { return "/p/OllamaControlCenter/bin/occ", nil }
-	// The folder.
-	if d, _ := defaultHistoryDir(); d != filepath.Join("/p/OllamaControlCenter", "history") {
-		// Report it.
-		t.Errorf("bin case gave %q", d)
-	} // end of the bin check
-	// A program elsewhere.
-	executablePath = func() (string, error) { return "/p/occ", nil }
-	// The folder.
-	if d, _ := defaultHistoryDir(); d != filepath.Join("/p", "history") {
-		// Report it.
-		t.Errorf("plain case gave %q", d)
-	} // end of the plain check
-	// Unknown program place: the config folder.
-	executablePath = func() (string, error) { return "", http.ErrNotSupported }
-	// A config folder.
+	// A configuration folder.
 	userConfigDir = func() (string, error) { return "/cfg", nil }
-	// The folder.
-	if d, _ := defaultHistoryDir(); d != filepath.Join("/cfg", "OllamaControlCenter", "history") {
-		// Report it.
-		t.Errorf("fallback gave %q", d)
-	} // end of the fallback check
+	// A program inside bin, and one elsewhere: the same answer.
+	for _, exe := range []string{"/p/OllamaControlCenter/bin/occ", "/p/occ"} {
+		// Use this program place.
+		executablePath = func() (string, error) { return exe, nil }
+		// The folder.
+		if d, _ := defaultHistoryDir(); d != filepath.Join("/cfg", "OllamaControlCenter", "history") {
+			// Report it.
+			t.Errorf("exe %q gave %q", exe, d)
+		} // end of the check
+	} // end of the loop
 	// Nothing at all.
 	userConfigDir = func() (string, error) { return "", http.ErrNotSupported }
 	// The folder and the reason.
 	if d, note := defaultHistoryDir(); d != "" || note == "" {
 		// Report it.
 		t.Errorf("no-folder case gave %q, %q", d, note)
-	} // end of the none check
+	} // end of the no-folder check
 } // end of TestDefaultHistoryDir
 
 // TestRestorePageSaysWhenNothingWasKept checks a model deleted without a snapshot says so on the restore page.
diff --git a/perf_test.go b/perf_test.go
index 1a0df6f..8222491 100644
--- a/perf_test.go
+++ b/perf_test.go
@@ -334,7 +334,7 @@ func perfRig(t *testing.T, f *perfFake) (themeRig, string) {
 	// The token is 32 characters after the marker.
 	tok := body[i+len(`name="token" value="`) : i+len(`name="token" value="`)+32]
 	// Hand back the rig and the file path.
-	return themeRig{h: h, token: tok}, filepath.Join(dir, "OllamaControlCenter", "performance.json")
+	return themeRig{h: h, token: tok}, filepath.Join(dir, "OllamaControlCenter", "performanceCompare", "performance.json")
 } // end of perfRig
 
 // perfPost sends a form to a performance route as the page's own form would.
@@ -1090,43 +1090,27 @@ func TestMain(m *testing.M) {
 	os.Exit(code)
 } // end of TestMain
 
-// TestDefaultHistoryPath checks where the saved results go: next to the project when the program runs from its bin folder, next to the program elsewhere, and in the configuration folder when the program's place is unknown.
+// TestDefaultHistoryPath checks where the saved results go: always in the data folder inside the configuration folder, wherever the program is, and memory only (with a reason) when there is no configuration folder.
 func TestDefaultHistoryPath(t *testing.T) {
 	// Put the real lookups back when the test ends.
 	oldExe, oldCfg := executablePath, userConfigDir
 	// Restore them.
 	t.Cleanup(func() { executablePath, userConfigDir = oldExe, oldCfg })
-	// The configuration folder, for the fallback.
+	// A configuration folder.
 	userConfigDir = func() (string, error) { return "/cfg", nil }
-	// The cases.
-	for _, c := range []struct {
-		// exe is where the program is.
-		exe string
-		// err is the failure of the lookup, when there is one.
-		err error
-		// want is the expected file.
-		want string
-	}{
-		// From the bin folder of the project.
-		{"/home/u/OllamaControlCenter/bin/OllamaControlCenter", nil, "/home/u/OllamaControlCenter/performanceCompare/performance.json"},
-		// From any other folder: next to the program.
-		{"/opt/occ/OllamaControlCenter", nil, "/opt/occ/performanceCompare/performance.json"},
-		// Unknown place: the configuration folder.
-		{"", errors.New("no path"), "/cfg/OllamaControlCenter/performance.json"},
-	} {
-		// Use this case.
-		executablePath = func() (string, error) { return c.exe, c.err }
+	// Wherever the program is, the answer is the same.
+	for _, exe := range []string{"/home/u/OllamaControlCenter/bin/OllamaControlCenter", "/opt/occ/OllamaControlCenter", ""} {
+		// Use this program place.
+		executablePath = func() (string, error) { return exe, nil }
 		// Ask.
 		got, note := defaultHistoryPath()
 		// Compare.
-		if filepath.ToSlash(got) != c.want || note != "" {
+		if filepath.ToSlash(got) != "/cfg/OllamaControlCenter/performanceCompare/performance.json" || note != "" {
 			// Report it.
-			t.Errorf("exe %q: path %q note %q, want %q", c.exe, got, note, c.want)
+			t.Errorf("exe %q: path %q note %q", exe, got, note)
 		} // end of the check
 	} // end of the loop
-	// No program place and no configuration folder: memory only, with a reason.
-	executablePath = func() (string, error) { return "", errors.New("no path") }
-	// No folder either.
+	// No configuration folder: memory only, with a reason.
 	userConfigDir = func() (string, error) { return "", errors.New("none") }
 	// Ask.
 	if got, note := defaultHistoryPath(); got != "" || note == "" {
diff --git a/perfstore.go b/perfstore.go
index 7ad24a2..d6ac6e9 100644
--- a/perfstore.go
+++ b/perfstore.go
@@ -45,7 +45,7 @@ type perfStore struct {
 	note string
 } // end of perfStore
 
-// historyFolderName is the folder, next to the project, that holds the saved performance results.
+// historyFolderName is the folder, inside the data folder, that holds the saved performance results.
 const historyFolderName = "performanceCompare"
 
 // oldHistoryFolderName is the name earlier versions used for that folder (with a capital P); a folder with this name is moved to the new name once.
@@ -107,29 +107,17 @@ func mustStat(p string) os.FileInfo {
 // executablePath finds the running program; a test replaces it.
 var executablePath = os.Executable
 
-// defaultHistoryPath returns the history file: in a folder named performanceCompare next to the project (the program normally runs from the project's bin folder, so that is the folder above it), or, when the program's own place cannot be found, in the person's configuration folder; an empty text and a reason mean memory only.
+// defaultHistoryPath returns the results file: in a folder named performanceCompare inside the program's data folder (the person's configuration folder, the same on every system); an empty text and a reason mean memory only.
 func defaultHistoryPath() (string, string) {
-	// Where is the running program?
-	if exe, err := executablePath(); err == nil && exe != "" {
-		// The folder that holds it.
-		dir := filepath.Dir(exe)
-		// A program in a folder called bin belongs to the project one level up.
-		if filepath.Base(dir) == "bin" {
-			// Go up one level.
-			dir = filepath.Dir(dir)
-		} // end of the bin check
-		// The results live in their own folder there.
-		return filepath.Join(dir, historyFolderName, "performance.json"), ""
-	} // end of the program check
-	// Ask for the configuration folder instead.
-	dir, err := userConfigDir()
+	// The one data folder.
+	root := dataRoot()
 	// None found.
-	if err != nil || dir == "" {
+	if root == "" {
 		// Memory only.
 		return "", "No folder for the results was found, so they are kept only until the monitor stops."
 	} // end of the lookup check
-	// The file lives in a folder of its own.
-	return filepath.Join(dir, "OllamaControlCenter", "performance.json"), ""
+	// The results live in their own folder there.
+	return filepath.Join(root, historyFolderName, "performance.json"), ""
 } // end of defaultHistoryPath
 
 // openPerfStore opens the history at the given path (an empty path means memory only); a file that cannot be read is left untouched and the store stays in memory.
diff --git a/web.go b/web.go
index 7cd5fca..2b96267 100644
--- a/web.go
+++ b/web.go
@@ -192,6 +192,12 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	// Route: a POST request for "/modelfile" shows a model's Modelfile, read-only.
 	mux.HandleFunc("POST /modelfile", modelfileHandler(addr, token))
 	// Make the four performance handlers: the start page, the test run, and the two steps of clearing the saved results (the checks are in perfpage.go); the history lives in the person's configuration folder.
+	// Earlier versions kept the results, the deleted models and the snapshots next to the program; copy them once to the data folder (the old folders are left in place).
+	for _, msg := range migrateOldData(oldDataRoot(), dataRoot()) {
+		// Say so in the log.
+		log.Print(msg)
+	} // end of the copy loop
+	// Where the results live now.
 	histPath, histNote := defaultHistoryPath()
 	// An earlier version named the results folder with a capital P; rename it before anything is opened, so the saved results are found.
 	if msg := moveOldHistoryFolder(histPath); msg != "" {
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
78c6f99f5261c28a05193c271122c23e561b32db3d2a823afa2c5ea0554fa149  about.go
b7b10755459aafb3824753668546ff5375921748d41f9f21b0ba7b3b8d163d90  datafolder.go
ec4f40589ed9b4a96013e67f0b52211017a6bdaac5952e914487384d935d0f39  datafolder_test.go
01ebd8b71e321aadbb1461967b8843e0b3f3ac65d587c8b6259a37a25c2e404e  history.go
a39fceab3702983386e4a9665f5033fc69754affcfa0093fd0e76ff42b3601bf  history_test.go
ec5198d2aad7ae30b302ca8b04fb43c64b0f3e09d002fde8e520cf7d667528e0  perf_test.go
646a1834ef9410783a4d1e939898579083a86f2d45f64ee4be33616d59bf5e48  perfstore.go
0d2384f4b209faa83f4e6d739d138eaab59b704f4b4bd4d725912c0eedc11469  web.go
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
# Build for this computer the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Check that the program also compiles for Windows and macOS (nothing is kept).
for target in windows/amd64 darwin/arm64 darwin/amd64; do
  # Build for one target and throw the file away.
  GOOS="${target%/*}" GOARCH="${target#*/}" CGO_ENABLED=0 go build -trimpath -o /dev/null . || { echo "FAIL  build for $target"; exit 1; }
  # Report it.
  echo "PASS  compiles for $target"
done
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
# Tell the person what to look at.
echo "NEXT  start ./bin/OllamaControlCenter and read the first log lines: they must say Copied N saved file(s) from ~/OllamaControlCenter/... to ~/.config/OllamaControlCenter/...; then open http://127.0.0.1:8765/ and check that the saved results and the deleted-models history are still there"
# List the changed files; nothing is committed yet.
git status --short
