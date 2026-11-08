// Package main tells Go that this test file belongs to the same program as legacyname.go.
package main

// Imports: the standard library only.
import (
	// os reads and writes the folders of the tests.
	"os"
	// path/filepath joins file names.
	"path/filepath"
	// runtime tells which system the test runs on.
	"runtime"
	// strings searches the log sentences.
	"strings"
	// testing is Go's built-in test framework.
	"testing"
) // end of imports

// pointFoldersAt makes the program use three pretend base folders (config, data, state) for one test and puts the real lookups back afterwards; it returns the three base folders.
func pointFoldersAt(t *testing.T) (cfg, data, state string) {
	// Mark this as a helper.
	t.Helper()
	// Three separate temporary base folders.
	cfg, data, state = t.TempDir(), t.TempDir(), t.TempDir()
	// Keep the real lookups.
	oc, od, os2 := userConfigDir, userDataDir, userStateDir
	// Put them back at the end.
	t.Cleanup(func() { userConfigDir, userDataDir, userStateDir = oc, od, os2 })
	// The pretend lookups.
	userConfigDir = func() (string, error) { return cfg, nil }
	userDataDir = func() (string, error) { return data, nil }
	userStateDir = func() (string, error) { return state, nil }
	// Hand the folders back.
	return cfg, data, state
} // end of pointFoldersAt

// TestMigrateLegacyRootsRenamesAllThree checks that the old settings, data and state folders get the new name with their content, and that a second start changes nothing.
func TestMigrateLegacyRootsRenamesAllThree(t *testing.T) {
	// Three pretend base folders.
	cfg, data, state := pointFoldersAt(t)
	// An old folder with one file in each.
	for _, base := range []string{cfg, data, state} {
		// The file keeps the base folder's name inside, to tell them apart.
		writeTestFile(t, filepath.Join(base, legacyAppName, "keep.json"), filepath.Base(base))
	} // end of the fixture loop
	// First start after the rename.
	msgs := migrateLegacyRoots()
	// One sentence per folder.
	if len(msgs) != 3 {
		// Report.
		t.Fatalf("want 3 sentences, got %d: %v", len(msgs), msgs)
	} // end of the count check
	// Each folder now has the new name and its own file; the old name is gone.
	for _, base := range []string{cfg, data, state} {
		// The file inside the new folder.
		got, err := os.ReadFile(filepath.Join(base, dataFolderName, "keep.json"))
		// It must be there with the right content.
		if err != nil || string(got) != filepath.Base(base) {
			// Report.
			t.Errorf("%s: new folder lost the file (%v, %q)", base, err, got)
		} // end of the content check
		// The old folder must be gone.
		if _, err := os.Lstat(filepath.Join(base, legacyAppName)); err == nil {
			// Report.
			t.Errorf("%s: the old folder is still there", base)
		} // end of the old-folder check
	} // end of the check loop
	// A second start finds nothing to do.
	if again := migrateLegacyRoots(); len(again) != 0 {
		// Report.
		t.Errorf("second start must be silent, got %v", again)
	} // end of the repeat check
} // end of TestMigrateLegacyRootsRenamesAllThree

// TestMigrateLegacyRootsSameFolderOnce checks the macOS case: one folder for all three kinds is renamed once, without a complaint about itself.
func TestMigrateLegacyRootsSameFolderOnce(t *testing.T) {
	// Three pretend base folders, then all three pointed at the first.
	cfg, _, _ := pointFoldersAt(t)
	// One shared base.
	userDataDir, userStateDir = userConfigDir, userConfigDir
	// The old folder.
	writeTestFile(t, filepath.Join(cfg, legacyAppName, "keep.json"), "x")
	// Rename.
	msgs := migrateLegacyRoots()
	// Exactly one sentence, and it is the success one.
	if len(msgs) != 1 || strings.Contains(msgs[0], "untouched") || strings.Contains(msgs[0], "could not") {
		// Report.
		t.Fatalf("want one success sentence, got %v", msgs)
	} // end of the sentence check
	// The file is in the new folder.
	if _, err := os.Stat(filepath.Join(cfg, dataFolderName, "keep.json")); err != nil {
		// Report.
		t.Errorf("file missing after rename: %v", err)
	} // end of the file check
} // end of TestMigrateLegacyRootsSameFolderOnce

// TestRenameLegacyRootRules checks the refusals: no old folder, both folders present, and an old name that is a link.
func TestRenameLegacyRootRules(t *testing.T) {
	// A pretend base.
	base := t.TempDir()
	// No old folder: silent.
	if msg := renameLegacyRoot(filepath.Join(base, "old"), filepath.Join(base, "new")); msg != "" {
		// Report.
		t.Errorf("missing old folder must be silent, got %q", msg)
	} // end of the missing check
	// Both folders exist: nothing moves and the sentence names both.
	writeTestFile(t, filepath.Join(base, "old2", "a.json"), "old")
	// The new one.
	writeTestFile(t, filepath.Join(base, "new2", "b.json"), "new")
	// Ask.
	msg := renameLegacyRoot(filepath.Join(base, "old2"), filepath.Join(base, "new2"))
	// The sentence says the old folder was left untouched.
	if !strings.Contains(msg, "untouched") {
		// Report.
		t.Errorf("both folders: want the untouched sentence, got %q", msg)
	} // end of the sentence check
	// Both are still as they were.
	if _, err := os.Stat(filepath.Join(base, "old2", "a.json")); err != nil {
		// Report.
		t.Errorf("old folder was changed: %v", err)
	} // end of the old check
	// The new one holds only its own file.
	if _, err := os.Stat(filepath.Join(base, "new2", "a.json")); err == nil {
		// Report.
		t.Error("the old file was moved into an existing new folder")
	} // end of the new check
	// A link is never followed (links need extra rights on Windows).
	if runtime.GOOS != "windows" {
		// A real folder elsewhere and a link to it with the old name.
		target := filepath.Join(base, "elsewhere")
		// Make the target.
		writeTestFile(t, filepath.Join(target, "c.json"), "x")
		// The link.
		if err := os.Symlink(target, filepath.Join(base, "old3")); err != nil {
			// The fixture failed.
			t.Fatal(err)
		} // end of the link check
		// Ask.
		if msg := renameLegacyRoot(filepath.Join(base, "old3"), filepath.Join(base, "new3")); msg != "" {
			// Report.
			t.Errorf("a link must be ignored, got %q", msg)
		} // end of the ignore check
		// The new name was not created.
		if _, err := os.Lstat(filepath.Join(base, "new3")); err == nil {
			// Report.
			t.Error("a link was renamed")
		} // end of the creation check
	} // end of the link case
} // end of TestRenameLegacyRootRules

// TestOllamaFromEnv checks the new variable first, the old one as a fallback, and nothing when neither is set.
func TestOllamaFromEnv(t *testing.T) {
	// A pretend environment.
	env := func(m map[string]string) func(string) string {
		// The lookup.
		return func(k string) string { return m[k] }
	} // end of env
	// Both set: the new name wins.
	if got := ollamaFromEnv(env(map[string]string{envOllamaURL: "http://new:1", envOllamaURLOld: "http://old:2"})); got != "http://new:1" {
		// Report.
		t.Errorf("both set: got %q", got)
	} // end of the both case
	// Only the old name: it still works.
	if got := ollamaFromEnv(env(map[string]string{envOllamaURLOld: "http://old:2"})); got != "http://old:2" {
		// Report.
		t.Errorf("old only: got %q", got)
	} // end of the old case
	// Neither: empty.
	if got := ollamaFromEnv(env(nil)); got != "" {
		// Report.
		t.Errorf("none: got %q", got)
	} // end of the none case
	// The two names are what the documents say.
	if envOllamaURL != "LLMSCONTROLDOCK_OLLAMA_URL" || envOllamaURLOld != "OCC_OLLAMA_URL" {
		// Report.
		t.Errorf("variable names changed: %s %s", envOllamaURL, envOllamaURLOld)
	} // end of the name check
} // end of TestOllamaFromEnv

// TestLooksOursKnowsBothPrefixes checks that saved copies made before the rename are still recognised.
func TestLooksOursKnowsBothPrefixes(t *testing.T) {
	// Both prefixes, a CSV and a PDF.
	for _, name := range []string{"LLMsControlDock-comparison-20261102.pdf", "OllamaControlCenter-comparison-20261102.csv"} {
		// Recognised.
		if !looksOurs(name) {
			// Report.
			t.Errorf("%s should be recognised", name)
		} // end of the check
	} // end of the loop
	// Somebody else's file is not.
	if looksOurs("OllamaControlCenter-notes.txt") {
		// Report.
		t.Error("a text file must not be recognised")
	} // end of the stranger check
} // end of TestLooksOursKnowsBothPrefixes

// legacyIcon builds a desktopIcon on the pretend desktop and puts an old-named launcher on it; it returns the icon and the old launcher's path.
func legacyIcon(t *testing.T) (desktopIcon, fakeDesktop, string) {
	// Mark this as a helper.
	t.Helper()
	// The pretend desktop (skipped on Windows).
	f := newFakeDesktop(t)
	// A pretend settings folder.
	d := desktopIcon{env: f.env, dir: t.TempDir(), dataDir: t.TempDir()}
	// The old launcher.
	old := filepath.Join(f.desk, legacyDesktopFileName)
	// Write it.
	writeTestFile(t, old, "[Desktop Entry]\nName=OllamaControlCenter\n")
	// Hand everything back.
	return d, f, old
} // end of legacyIcon

// TestMigrateLegacyLauncherReplacesForSomeoneWhoChoseAnIcon checks that the old icon becomes a new one, and the old one is gone.
func TestMigrateLegacyLauncherReplacesForSomeoneWhoChoseAnIcon(t *testing.T) {
	// The setup.
	d, f, old := legacyIcon(t)
	// The person had chosen an icon.
	if err := d.remember("created"); err != nil {
		// The fixture failed.
		t.Fatal(err)
	} // end of the choice check
	// Migrate.
	msg := migrateLegacyLauncher(d)
	// The sentence says it was renamed.
	if !strings.Contains(msg, "renamed to LLMsControlDock") {
		// Report.
		t.Errorf("sentence: %q", msg)
	} // end of the sentence check
	// The new launcher is there, the old one is gone.
	if _, err := os.Stat(filepath.Join(f.desk, desktopFileName)); err != nil {
		// Report.
		t.Errorf("new launcher missing: %v", err)
	} // end of the new check
	// The old one.
	if _, err := os.Lstat(old); err == nil {
		// Report.
		t.Error("old launcher still there")
	} // end of the old check
	// The new launcher starts the running program under its new name.
	got, err := os.ReadFile(filepath.Join(f.desk, desktopFileName))
	// It must be readable and name the program.
	if err != nil || !strings.Contains(string(got), "LLMsControlDock") || strings.Contains(string(got), "OllamaControlCenter") {
		// Report.
		t.Errorf("new launcher text: %v %q", err, got)
	} // end of the text check
	// A second start is silent.
	if again := migrateLegacyLauncher(d); again != "" {
		// Report.
		t.Errorf("second start must be silent, got %q", again)
	} // end of the repeat check
} // end of TestMigrateLegacyLauncherReplacesForSomeoneWhoChoseAnIcon

// TestMigrateLegacyLauncherLeavesOthersAlone checks that someone who never chose an icon keeps the old file untouched and gets no new one.
func TestMigrateLegacyLauncherLeavesOthersAlone(t *testing.T) {
	// The setup, with no remembered choice.
	d, f, old := legacyIcon(t)
	// Migrate.
	if msg := migrateLegacyLauncher(d); msg != "" {
		// Report.
		t.Errorf("sentence: %q", msg)
	} // end of the sentence check
	// The old launcher is still there.
	if _, err := os.Stat(old); err != nil {
		// Report.
		t.Errorf("old launcher was touched: %v", err)
	} // end of the old check
	// No new one was made.
	if _, err := os.Stat(filepath.Join(f.desk, desktopFileName)); err == nil {
		// Report.
		t.Error("a new launcher was made without a choice")
	} // end of the new check
} // end of TestMigrateLegacyLauncherLeavesOthersAlone

// TestMigrateLegacyLauncherRemovesDuplicate checks that when both launchers exist, only the old one goes.
func TestMigrateLegacyLauncherRemovesDuplicate(t *testing.T) {
	// The setup.
	d, f, old := legacyIcon(t)
	// Make the new launcher too.
	writeTestFile(t, filepath.Join(f.desk, desktopFileName), "new")
	// Migrate.
	msg := migrateLegacyLauncher(d)
	// The sentence says the old one was removed.
	if !strings.Contains(msg, "removed") {
		// Report.
		t.Errorf("sentence: %q", msg)
	} // end of the sentence check
	// The old one is gone.
	if _, err := os.Lstat(old); err == nil {
		// Report.
		t.Error("old launcher still there")
	} // end of the old check
	// The new one is untouched.
	if got, _ := os.ReadFile(filepath.Join(f.desk, desktopFileName)); string(got) != "new" {
		// Report.
		t.Errorf("new launcher changed: %q", got)
	} // end of the new check
} // end of TestMigrateLegacyLauncherRemovesDuplicate

// TestUninstallAlsoRemovesTheOldLauncher checks that removing the icon files leaves no old-named launcher behind.
func TestUninstallAlsoRemovesTheOldLauncher(t *testing.T) {
	// The setup.
	d, _, old := legacyIcon(t)
	// Remove everything the icon owns.
	if err := d.removeFiles(); err != nil {
		// Report.
		t.Fatal(err)
	} // end of the remove check
	// The old launcher is gone.
	if _, err := os.Lstat(old); err == nil {
		// Report.
		t.Error("old launcher survived the uninstall")
	} // end of the old check
} // end of TestUninstallAlsoRemovesTheOldLauncher

// TestRemoveLauncherKnowsTheOldBundle checks that a macOS bundle with the old name is removed as a whole folder, and a bundle with another name is not.
func TestRemoveLauncherKnowsTheOldBundle(t *testing.T) {
	// A pretend desktop folder.
	base := t.TempDir()
	// An old bundle with a file inside.
	old := filepath.Join(base, legacyMacLauncherName)
	// Make it.
	writeTestFile(t, filepath.Join(old, "Contents", "x"), "x")
	// Remove it.
	if err := removeLauncher(old); err != nil {
		// Report.
		t.Fatal(err)
	} // end of the remove check
	// It is gone as a whole.
	if _, err := os.Lstat(old); err == nil {
		// Report.
		t.Error("old bundle was not removed")
	} // end of the gone check
	// Somebody else's folder with another name is not removed as a bundle (removing a folder with os.Remove fails because it is not empty).
	other := filepath.Join(base, "Other.app")
	// Make it.
	writeTestFile(t, filepath.Join(other, "Contents", "x"), "x")
	// Try; the call fails or does nothing, and the content survives.
	_ = removeLauncher(other)
	// Still there.
	if _, err := os.Stat(filepath.Join(other, "Contents", "x")); err != nil {
		// Report.
		t.Errorf("a foreign folder was removed: %v", err)
	} // end of the survive check
} // end of TestRemoveLauncherKnowsTheOldBundle
