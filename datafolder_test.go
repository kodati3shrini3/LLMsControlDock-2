// Package main tells Go that this test file belongs to the same program as datafolder.go.
package main

import ( // import lists the packages this test file uses.
	// errors builds the "no path" error.
	"errors"
	// os reads and writes the folders of the tests.
	"os"
	// path/filepath joins file names.
	"path/filepath"
	// strings searches the log sentences.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// writeTestFile writes one file for a test, making its folder first.
func writeTestFile(t *testing.T, path, text string) {
	// Mark this as a helper.
	t.Helper()
	// The folder.
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		// Stop the test.
		t.Fatalf("fixture folder: %v", err)
	} // end of the folder check
	// The file.
	if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
		// Stop the test.
		t.Fatalf("fixture file: %v", err)
	} // end of the file check
} // end of writeTestFile

// TestLooksOurs checks which file names count as this program's own.
func TestLooksOurs(t *testing.T) {
	// The cases.
	for name, want := range map[string]bool{
		// The results file.
		"performance.json": true,
		// The deleted-models file.
		"deleted-models.json": true,
		// A snapshot with a date.
		"2026-11-02_17-54-00+0100_llama3-8b.json": true,
		// A saved copy of a download.
		"OllamaControlCenter-comparison-20261102-175400+0100.pdf": true,
		// A saved copy as a table.
		"OllamaControlCenter-comparison-20261102-175400+0100.csv": true,
		// Somebody else's JSON file.
		"settings-backup.json": false,
		// Somebody else's text file.
		"notes.txt": false,
		// A program with a dated name is not one of ours.
		"2026-11-02_17-54-00_setup.exe": false,
		// No extension.
		"performance": false,
	} { // end of the cases
		// Check it.
		if got := looksOurs(name); got != want {
			// Report the problem.
			t.Errorf("looksOurs(%q) = %v, want %v", name, got, want)
		} // end of the check
	} // end of the loop
} // end of TestLooksOurs

// TestDataRootAndOldDataRoot checks the new and the old data folders.
func TestDataRootAndOldDataRoot(t *testing.T) {
	// Keep and restore the two lookups.
	oldExe, oldCfg := executablePath, userConfigDir
	// Put them back afterwards.
	t.Cleanup(func() { executablePath, userConfigDir = oldExe, oldCfg })
	// A configuration folder.
	userConfigDir = func() (string, error) { return "/cfg", nil }
	// The new folder.
	if got := dataRoot(); got != filepath.Join("/cfg", "OllamaControlCenter") {
		// Report the problem.
		t.Errorf("dataRoot = %q", got)
	} // end of the new-folder check
	// No configuration folder.
	userConfigDir = func() (string, error) { return "", errors.New("none") }
	// Nothing.
	if got := dataRoot(); got != "" {
		// Report the problem.
		t.Errorf("dataRoot without a folder = %q", got)
	} // end of the empty check
	// A program inside bin: the project folder above it.
	executablePath = func() (string, error) { return "/p/OllamaControlCenter/bin/occ", nil }
	// The old folder.
	if got := oldDataRoot(); got != filepath.FromSlash("/p/OllamaControlCenter") {
		// Report the problem.
		t.Errorf("old root from bin = %q", got)
	} // end of the bin check
	// A program elsewhere: its own folder.
	executablePath = func() (string, error) { return "/opt/occ/occ", nil }
	// The old folder.
	if got := oldDataRoot(); got != filepath.FromSlash("/opt/occ") {
		// Report the problem.
		t.Errorf("old root plain = %q", got)
	} // end of the plain check
	// Unknown program place.
	executablePath = func() (string, error) { return "", errors.New("no path") }
	// Nothing.
	if got := oldDataRoot(); got != "" {
		// Report the problem.
		t.Errorf("old root unknown = %q", got)
	} // end of the unknown check
} // end of TestDataRootAndOldDataRoot

// TestMigrateOldData checks the one-time copy: the program's own files are copied, other files are not, the old folders stay as they are, and a second run does nothing.
func TestMigrateOldData(t *testing.T) {
	// A fresh place for the old and the new folders.
	base := t.TempDir()
	// The old project folder and the new data folder.
	oldRoot, newRoot := filepath.Join(base, "project"), filepath.Join(base, "cfg", "OllamaControlCenter")
	// Old results, with a saved copy and a stranger's file.
	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "performance.json"), "RESULTS")
	// A saved copy.
	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "OllamaControlCenter-comparison-1.pdf"), "PDF")
	// A stranger's file in the same folder.
	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "my-notes.txt"), "NOTES")
	// The deleted-models list.
	writeTestFile(t, filepath.Join(oldRoot, "deletedHistory", "deleted-models.json"), "DELETED")
	// A snapshot.
	writeTestFile(t, filepath.Join(oldRoot, "history", "2026-11-02_17-54-00+0100_m.json"), "SNAP")
	// Copy.
	msgs := migrateOldData(oldRoot, newRoot)
	// One sentence per folder.
	if len(msgs) != 3 {
		// Report the problem.
		t.Fatalf("messages: %q", msgs)
	} // end of the message check
	// The first sentence names the two places and the number of files.
	if !strings.Contains(msgs[0], "Copied 2 saved file(s)") || !strings.Contains(msgs[0], oldRoot) || !strings.Contains(msgs[0], newRoot) {
		// Report the problem.
		t.Errorf("sentence: %q", msgs[0])
	} // end of the sentence check
	// What must be in the new place.
	for rel, want := range map[string]string{
		// The results.
		"performanceCompare/performance.json": "RESULTS",
		// The saved copy.
		"performanceCompare/OllamaControlCenter-comparison-1.pdf": "PDF",
		// The deleted models.
		"deletedHistory/deleted-models.json": "DELETED",
		// The snapshot.
		"history/2026-11-02_17-54-00+0100_m.json": "SNAP",
	} { // end of the expected files
		// Read it.
		b, err := os.ReadFile(filepath.Join(newRoot, filepath.FromSlash(rel)))
		// It must be there with the same content.
		if err != nil || string(b) != want {
			// Report the problem.
			t.Errorf("%s: %q, %v", rel, b, err)
		} // end of the content check
	} // end of the loop
	// The stranger's file is not copied.
	if _, err := os.Stat(filepath.Join(newRoot, "performanceCompare", "my-notes.txt")); err == nil {
		// Report the problem.
		t.Error("a file that is not ours was copied")
	} // end of the stranger check
	// The old files are all still there.
	for _, rel := range []string{"performanceCompare/performance.json", "performanceCompare/my-notes.txt", "deletedHistory/deleted-models.json", "history/2026-11-02_17-54-00+0100_m.json"} {
		// Look.
		if _, err := os.Stat(filepath.Join(oldRoot, filepath.FromSlash(rel))); err != nil {
			// Report the problem.
			t.Errorf("the old file %s is gone", rel)
		} // end of the check
	} // end of the loop
	// The copy is private and no temporary folder is left.
	if st, err := os.Stat(filepath.Join(newRoot, "performanceCompare")); err != nil || st.Mode().Perm() != 0o700 {
		// Report the problem.
		t.Errorf("new folder: %v %v", st, err)
	} // end of the privacy check
	// No leftovers.
	if _, err := os.Stat(filepath.Join(newRoot, "performanceCompare.copying")); err == nil {
		// Report the problem.
		t.Error("a temporary folder was left")
	} // end of the leftover check
	// New data is never overwritten by a second start, even when the old files change.
	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "performance.json"), "CHANGED")
	// Second start.
	if msgs := migrateOldData(oldRoot, newRoot); len(msgs) != 0 {
		// Report the problem.
		t.Errorf("second run: %q", msgs)
	} // end of the second-run check
	// The new content is as before.
	if b, _ := os.ReadFile(filepath.Join(newRoot, "performanceCompare", "performance.json")); string(b) != "RESULTS" {
		// Report the problem.
		t.Errorf("the new file was overwritten: %q", b)
	} // end of the overwrite check
} // end of TestMigrateOldData

// TestMigrateSkipsOtherPeoplesFolders checks that a folder with the same name but none of this program's files is left alone, and that nothing happens for unknown or equal places.
func TestMigrateSkipsOtherPeoplesFolders(t *testing.T) {
	// A fresh place.
	base := t.TempDir()
	// The old and new folders.
	oldRoot, newRoot := filepath.Join(base, "Downloads"), filepath.Join(base, "cfg")
	// A "history" folder full of somebody else's files.
	writeTestFile(t, filepath.Join(oldRoot, "history", "browser.json"), "X")
	// Another one.
	writeTestFile(t, filepath.Join(oldRoot, "history", "report.pdf"), "X")
	// Copy.
	if msgs := migrateOldData(oldRoot, newRoot); len(msgs) != 0 {
		// Report the problem.
		t.Errorf("messages: %q", msgs)
	} // end of the message check
	// Nothing was created.
	if _, err := os.Stat(newRoot); err == nil {
		// Report the problem.
		t.Error("a folder was created for somebody else's files")
	} // end of the creation check
	// Unknown or equal places do nothing.
	if migrateOldData("", newRoot) != nil || migrateOldData(oldRoot, "") != nil || migrateOldData(oldRoot, oldRoot) != nil {
		// Report the problem.
		t.Error("an unknown or equal place did something")
	} // end of the place check
} // end of TestMigrateSkipsOtherPeoplesFolders

// TestMigrateRules checks the size limit, an existing new folder and a leftover temporary folder.
func TestMigrateRules(t *testing.T) {
	// Put the limit back when the test ends.
	oldMax := maxMigrateBytes
	// Restore it.
	t.Cleanup(func() { maxMigrateBytes = oldMax })
	// A fresh place.
	base := t.TempDir()
	// The old and new folders.
	oldRoot, newRoot := filepath.Join(base, "p"), filepath.Join(base, "cfg")
	// A small result and a large one.
	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "performance.json"), "ok")
	// A file bigger than the limit set below.
	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "OllamaControlCenter-big.pdf"), "0123456789")
	// A small limit.
	maxMigrateBytes = 5
	// A leftover temporary folder from an earlier attempt.
	writeTestFile(t, filepath.Join(newRoot, "performanceCompare.copying", "junk.json"), "junk")
	// Copy.
	if msgs := migrateOldData(oldRoot, newRoot); len(msgs) != 1 || !strings.Contains(msgs[0], "Copied 1 saved file(s)") {
		// Report the problem.
		t.Fatalf("messages: %q", msgs)
	} // end of the message check
	// The big file stayed behind.
	if _, err := os.Stat(filepath.Join(newRoot, "performanceCompare", "OllamaControlCenter-big.pdf")); err == nil {
		// Report the problem.
		t.Error("a file over the limit was copied")
	} // end of the size check
	// The leftover is gone.
	if _, err := os.Stat(filepath.Join(newRoot, "performanceCompare.copying")); err == nil {
		// Report the problem.
		t.Error("the leftover folder is still there")
	} // end of the leftover check
	// An existing new folder is never touched: a second old folder with a new file does not change it.
	writeTestFile(t, filepath.Join(oldRoot, "deletedHistory", "deleted-models.json"), "D")
	// The new folder exists already (empty).
	if err := os.MkdirAll(filepath.Join(newRoot, "deletedHistory"), 0o700); err != nil {
		// Stop the test.
		t.Fatalf("fixture: %v", err)
	} // end of the folder check
	// Copy again.
	if msgs := migrateOldData(oldRoot, newRoot); len(msgs) != 0 {
		// Report the problem.
		t.Errorf("an existing folder was touched: %q", msgs)
	} // end of the existing check
	// It is still empty.
	if es, _ := os.ReadDir(filepath.Join(newRoot, "deletedHistory")); len(es) != 0 {
		// Report the problem.
		t.Error("files were put into an existing folder")
	} // end of the empty check
} // end of TestMigrateRules

// TestStartupCopiesOldData checks the wiring: building the web interface copies the old results of the program's own folder into the data folder, so the saved results are found.
func TestStartupCopiesOldData(t *testing.T) {
	// Keep and restore the two lookups.
	oldExe, oldCfg := executablePath, userConfigDir
	// Put them back afterwards.
	t.Cleanup(func() { executablePath, userConfigDir = oldExe, oldCfg })
	// A fresh place.
	base := t.TempDir()
	// A project with its bin folder and old results.
	project := filepath.Join(base, "project")
	// The old results.
	writeTestFile(t, filepath.Join(project, "performanceCompare", "performance.json"), `{"runs":[]}`)
	// The program is in bin.
	executablePath = func() (string, error) { return filepath.Join(project, "bin", "occ"), nil }
	// The configuration folder.
	cfg := filepath.Join(base, "cfg")
	// Use it.
	userConfigDir = func() (string, error) { return cfg, nil }
	// Build the web interface the way the program does.
	handlerFor(t, "http://127.0.0.1:11434")
	// The old results are now in the data folder.
	if b, err := os.ReadFile(filepath.Join(cfg, "OllamaControlCenter", "performanceCompare", "performance.json")); err != nil || string(b) != `{"runs":[]}` {
		// Report the problem.
		t.Errorf("not copied at start-up: %q, %v", b, err)
	} // end of the copy check
} // end of TestStartupCopiesOldData
