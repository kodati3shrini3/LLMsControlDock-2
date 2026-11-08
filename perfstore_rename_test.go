// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// os makes the folders and reads the files.
	"os"
	// path/filepath builds paths in the test folder.
	"path/filepath"
	// strings searches the messages.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// TestOldResultsFolderIsRenamed checks that the folder of earlier versions is renamed with its files, that nothing is overwritten, and that fallback folders and memory-only stores are left alone.
func TestOldResultsFolderIsRenamed(t *testing.T) {
	// A project folder.
	root := t.TempDir()
	// The current results file path.
	hist := filepath.Join(root, historyFolderName, "performance.json")
	// Nothing exists yet: nothing to do.
	if msg := moveOldHistoryFolder(hist); msg != "" {
		// Report it.
		t.Errorf("message %q with no old folder", msg)
	} // end of the empty check
	// An old folder with a results file and a copy.
	old := filepath.Join(root, oldHistoryFolderName)
	// Create it.
	if err := os.MkdirAll(old, 0o700); err != nil {
		// Stop the test.
		t.Fatal(err)
	} // end of the folder check
	// Its files.
	for _, f := range []string{"performance.json", "LLMsControlDock-comparison-1.pdf"} {
		// Write one.
		if err := os.WriteFile(filepath.Join(old, f), []byte(f), 0o600); err != nil {
			// Stop the test.
			t.Fatal(err)
		} // end of the write check
	} // end of the files loop
	// Rename.
	if msg := moveOldHistoryFolder(hist); msg != "" {
		// Report it.
		t.Fatalf("message %q", msg)
	} // end of the rename check
	// The files are under the new name.
	for _, f := range []string{"performance.json", "LLMsControlDock-comparison-1.pdf"} {
		// Read one.
		if b, err := os.ReadFile(filepath.Join(root, historyFolderName, f)); err != nil || string(b) != f {
			// Report it.
			t.Errorf("%s: %q, %v", f, b, err)
		} // end of the read check
	} // end of the files loop
	// The folder under the old name is gone (on a computer that ignores capitals the two names are one folder, so only check when they differ).
	if _, err := os.Stat(old); err == nil && historyFolderName != oldHistoryFolderName && !ignoresCapitals(t, root) {
		// A case-blind disk answers for the new folder too; look at the real entry names.
		ents, _ := os.ReadDir(root)
		// Every entry.
		for _, e := range ents {
			// The old spelling must not remain.
			if e.Name() == oldHistoryFolderName {
				// Report it.
				t.Errorf("the old folder name remains")
			} // end of the name check
		} // end of the entries loop
	} // end of the old check
	// Two folders with different names: both are left alone and the person is told (skipped on a computer that ignores capitals).
	root2 := t.TempDir()
	// Both exist.
	if err := os.MkdirAll(filepath.Join(root2, historyFolderName), 0o700); err != nil {
		// Stop the test.
		t.Fatal(err)
	} // end of the new folder
	// The old one too.
	if err := os.MkdirAll(filepath.Join(root2, oldHistoryFolderName), 0o700); err == nil {
		// Are they really two folders?
		ents, _ := os.ReadDir(root2)
		// Two entries mean a case-sensitive disk.
		if len(ents) == 2 {
			// Try the rename.
			msg := moveOldHistoryFolder(filepath.Join(root2, historyFolderName, "performance.json"))
			// It must warn and leave both.
			if !strings.Contains(msg, "exist") {
				// Report it.
				t.Errorf("message %q for two folders", msg)
			} // end of the message check
			// Both remain.
			if ents2, _ := os.ReadDir(root2); len(ents2) != 2 {
				// Report it.
				t.Errorf("%d folders remain", len(ents2))
			} // end of the remain check
		} // end of the two-folders check
	} // end of the old folder
	// A fallback folder is never touched.
	if msg := moveOldHistoryFolder(filepath.Join(root, "LLMsControlDock", "performance.json")); msg != "" {
		// Report it.
		t.Errorf("message %q for a fallback folder", msg)
	} // end of the fallback check
	// Memory only.
	if msg := moveOldHistoryFolder(""); msg != "" {
		// Report it.
		t.Errorf("message %q for memory only", msg)
	} // end of the memory check
} // end of TestOldResultsFolderIsRenamed

// ignoresCapitals says whether the disk of dir treats "A" and "a" as the same name (Windows and macOS usually do; Linux does not).
func ignoresCapitals(t *testing.T, dir string) bool {
	// Mark this as a helper.
	t.Helper()
	// A file with a lower-case name in a folder of its own.
	probe := filepath.Join(t.TempDir(), "probe")
	// Make it.
	if err := os.WriteFile(probe, []byte("x"), 0o600); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the write check
	// Ask for it with a capital letter.
	_, err := os.Stat(filepath.Join(filepath.Dir(probe), "PROBE"))
	// Found: the disk ignores capitals.
	return err == nil
} // end of ignoresCapitals

// TestCanCreateBelow checks that a plain file in the way is noticed on every system, and that missing folders are not a problem.
func TestCanCreateBelow(t *testing.T) {
	// A folder, a plain file in it.
	base := t.TempDir()
	// The file.
	plain := filepath.Join(base, "plain-file")
	// Make it.
	if err := os.WriteFile(plain, []byte("x"), 0o600); err != nil {
		// Stop.
		t.Fatal(err)
	} // end of the write check
	// A real folder: fine.
	if !canCreateBelow(base) {
		// Report it.
		t.Error("an existing folder was refused")
	} // end of the folder check
	// Folders that do not exist yet below a real folder: fine.
	if !canCreateBelow(filepath.Join(base, "a", "b")) {
		// Report it.
		t.Error("missing folders below a real folder were refused")
	} // end of the missing check
	// A plain file in the way: refused, directly and further down.
	if canCreateBelow(plain) || canCreateBelow(filepath.Join(plain, "sub")) {
		// Report it.
		t.Error("a plain file in the way was accepted")
	} // end of the file check
} // end of TestCanCreateBelow
