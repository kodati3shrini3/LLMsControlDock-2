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
	for _, f := range []string{"performance.json", "OllamaControlCenter-comparison-1.pdf"} {
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
	for _, f := range []string{"performance.json", "OllamaControlCenter-comparison-1.pdf"} {
		// Read one.
		if b, err := os.ReadFile(filepath.Join(root, historyFolderName, f)); err != nil || string(b) != f {
			// Report it.
			t.Errorf("%s: %q, %v", f, b, err)
		} // end of the read check
	} // end of the files loop
	// The folder under the old name is gone (on a computer that ignores capitals the two names are one folder, so only check when they differ).
	if _, err := os.Stat(old); err == nil && historyFolderName != oldHistoryFolderName {
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
	if msg := moveOldHistoryFolder(filepath.Join(root, "OllamaControlCenter", "performance.json")); msg != "" {
		// Report it.
		t.Errorf("message %q for a fallback folder", msg)
	} // end of the fallback check
	// Memory only.
	if msg := moveOldHistoryFolder(""); msg != "" {
		// Report it.
		t.Errorf("message %q for memory only", msg)
	} // end of the memory check
} // end of TestOldResultsFolderIsRenamed
