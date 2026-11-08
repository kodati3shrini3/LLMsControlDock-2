// Package main tells Go that this test file belongs to the same program as datafolder.go.
package main

import ( // import lists the packages this test file uses.
	// errors builds the "no path" error.
	"errors"
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
	// time gives the moment of a check.
	"time"
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
		"LLMsControlDock-comparison-20261102-175400+0100.pdf": true,
		// A saved copy as a table.
		"LLMsControlDock-comparison-20261102-175400+0100.csv": true,
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
	// Keep the real lookups and put them back afterwards.
	saveFolderLookups(t)
	userConfigDir = func() (string, error) { return "/cfg", nil }
	// Data and state follow the same fake folder.
	userDataDir, userStateDir = userConfigDir, userConfigDir
	// The new folder.
	if got := dataRoot(); got != filepath.Join("/cfg", "LLMsControlDock") {
		// Report the problem.
		t.Errorf("dataRoot = %q", got)
	} // end of the new-folder check
	// No configuration folder.
	// Keep the real lookups and put them back afterwards.
	saveFolderLookups(t)
	userConfigDir = func() (string, error) { return "", errors.New("none") }
	// Data and state follow the same fake folder.
	userDataDir, userStateDir = userConfigDir, userConfigDir
	// Nothing.
	if got := dataRoot(); got != "" {
		// Report the problem.
		t.Errorf("dataRoot without a folder = %q", got)
	} // end of the empty check
	// A program inside bin: the project folder above it.
	executablePath = func() (string, error) { return "/p/LLMsControlDock/bin/occ", nil }
	// The old folder.
	if got := oldDataRoot(); got != filepath.FromSlash("/p/LLMsControlDock") {
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
	oldRoot, newRoot := filepath.Join(base, "project"), filepath.Join(base, "cfg", "LLMsControlDock")
	// Old results, with a saved copy and a stranger's file.
	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "performance.json"), "RESULTS")
	// A saved copy.
	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "LLMsControlDock-comparison-1.pdf"), "PDF")
	// A stranger's file in the same folder.
	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "my-notes.txt"), "NOTES")
	// The deleted-models list.
	writeTestFile(t, filepath.Join(oldRoot, "deletedHistory", "deleted-models.json"), "DELETED")
	// A snapshot.
	writeTestFile(t, filepath.Join(oldRoot, "history", "2026-11-02_17-54-00+0100_m.json"), "SNAP")
	// Copy.
	msgs := migrateOldData(newRoot, oldRoot)
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
		"performanceCompare/LLMsControlDock-comparison-1.pdf": "PDF",
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
	if st, err := os.Stat(filepath.Join(newRoot, "performanceCompare")); err != nil || (modesApply() && st.Mode().Perm() != 0o700) {
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
	if msgs := migrateOldData(newRoot, oldRoot); len(msgs) != 0 {
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
	if msgs := migrateOldData(newRoot, oldRoot); len(msgs) != 0 {
		// Report the problem.
		t.Errorf("messages: %q", msgs)
	} // end of the message check
	// Nothing was created.
	if _, err := os.Stat(newRoot); err == nil {
		// Report the problem.
		t.Error("a folder was created for somebody else's files")
	} // end of the creation check
	// Unknown or equal places do nothing.
	if migrateOldData(newRoot, "") != nil || migrateOldData("", oldRoot) != nil || migrateOldData(oldRoot, oldRoot) != nil {
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
	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "LLMsControlDock-big.pdf"), "0123456789")
	// A small limit.
	maxMigrateBytes = 5
	// A leftover temporary folder from an earlier attempt.
	writeTestFile(t, filepath.Join(newRoot, "performanceCompare.copying", "junk.json"), "junk")
	// Copy.
	if msgs := migrateOldData(newRoot, oldRoot); len(msgs) != 1 || !strings.Contains(msgs[0], "Copied 1 saved file(s)") {
		// Report the problem.
		t.Fatalf("messages: %q", msgs)
	} // end of the message check
	// The big file stayed behind.
	if _, err := os.Stat(filepath.Join(newRoot, "performanceCompare", "LLMsControlDock-big.pdf")); err == nil {
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
	if msgs := migrateOldData(newRoot, oldRoot); len(msgs) != 0 {
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
	// Keep the real lookups and put them back afterwards.
	saveFolderLookups(t)
	userConfigDir = func() (string, error) { return cfg, nil }
	// Data and state follow the same fake folder.
	userDataDir, userStateDir = userConfigDir, userConfigDir
	// Build the web interface the way the program does.
	handlerFor(t, "http://127.0.0.1:11434")
	// The old results are now in the data folder.
	if b, err := os.ReadFile(filepath.Join(cfg, "LLMsControlDock", "performanceCompare", "performance.json")); err != nil || string(b) != `{"runs":[]}` {
		// Report the problem.
		t.Errorf("not copied at start-up: %q, %v", b, err)
	} // end of the copy check
} // end of TestStartupCopiesOldData

// saveFolderLookups remembers the three folder lookups and puts them back when the test ends.
func saveFolderLookups(t *testing.T) {
	// Remember the current ones.
	c, d, s := userConfigDir, userDataDir, userStateDir
	// Put them back at the end.
	t.Cleanup(func() { userConfigDir, userDataDir, userStateDir = c, d, s })
} // end of saveFolderLookups

// TestBaseDirFor checks the standard folders of every system, from each system's own rules, without needing that system.
func TestBaseDirFor(t *testing.T) {
	// A fixed home folder lookup.
	home := func() (string, error) { return "/home/ann", nil }
	// A lookup from a map.
	env := func(m map[string]string) func(string) string { return func(k string) string { return m[k] } }
	// The cases.
	for _, tc := range []struct {
		// name describes the case.
		name string
		// goos is the system.
		goos string
		// kind is config, data or state.
		kind string
		// env is the environment.
		env map[string]string
		// want is the expected folder.
		want string
		// fail says an error is expected.
		fail bool
	}{
		// Linux defaults (XDG Base Directory Specification).
		{"linux config", "linux", kindConfig, nil, "/home/ann/.config", false},
		{"linux data", "linux", kindData, nil, "/home/ann/.local/share", false},
		{"linux state", "linux", kindState, nil, "/home/ann/.local/state", false},
		// Linux with the variables set.
		{"linux xdg data", "linux", kindData, map[string]string{"XDG_DATA_HOME": "/x/data"}, "/x/data", false},
		{"linux xdg state", "linux", kindState, map[string]string{"XDG_STATE_HOME": "/x/state"}, "/x/state", false},
		// A relative path is invalid and ignored, as the specification says.
		{"linux relative ignored", "linux", kindConfig, map[string]string{"XDG_CONFIG_HOME": "rel/path"}, "/home/ann/.config", false},
		// Windows: roaming for configuration, local for data and state.
		{"windows config", "windows", kindConfig, map[string]string{"AppData": `C:\Users\ann\AppData\Roaming`, "LocalAppData": `C:\Users\ann\AppData\Local`}, `C:\Users\ann\AppData\Roaming`, false},
		{"windows data", "windows", kindData, map[string]string{"AppData": `C:\R`, "LocalAppData": `C:\L`}, `C:\L`, false},
		{"windows state", "windows", kindState, map[string]string{"AppData": `C:\R`, "LocalAppData": `C:\L`}, `C:\L`, false},
		{"windows missing", "windows", kindData, nil, "", true},
		// macOS: Application Support for all three.
		{"mac config", "darwin", kindConfig, nil, "/home/ann/Library/Application Support", false},
		{"mac data", "darwin", kindData, nil, "/home/ann/Library/Application Support", false},
		{"mac state", "darwin", kindState, nil, "/home/ann/Library/Application Support", false},
	} { // end of the cases
		// Ask.
		got, err := baseDirFor(tc.goos, tc.kind, env(tc.env), home)
		// Compare.
		if (err != nil) != tc.fail || got != tc.want {
			// Report the problem.
			t.Errorf("%s: got %q, %v; want %q (fail=%v)", tc.name, got, err, tc.want, tc.fail)
		} // end of the compare
	} // end of the loop
	// No home folder on Linux and macOS.
	noHome := func() (string, error) { return "", errors.New("none") }
	// Both must fail.
	if _, err := baseDirFor("linux", kindData, env(nil), noHome); err == nil {
		// Report the problem.
		t.Error("linux without a home folder was accepted")
	} // end of the Linux check
	// macOS.
	if _, err := baseDirFor("darwin", kindData, env(nil), noHome); err == nil {
		// Report the problem.
		t.Error("macOS without a home folder was accepted")
	} // end of the macOS check
} // end of TestBaseDirFor

// TestThreeRootsAndMoves checks the three folders and the copying of version 0.25.0's files to them.
func TestThreeRootsAndMoves(t *testing.T) {
	// Keep and restore the lookups.
	saveFolderLookups(t)
	// A fresh place with three base folders.
	base := t.TempDir()
	// The base folders.
	userConfigDir = func() (string, error) { return filepath.Join(base, "c"), nil }
	// Data.
	userDataDir = func() (string, error) { return filepath.Join(base, "d"), nil }
	// State.
	userStateDir = func() (string, error) { return filepath.Join(base, "s"), nil }
	// The three roots.
	cfg, data, state := configRoot(), dataRoot(), stateRoot()
	// Each has the program's own folder.
	if cfg != filepath.Join(base, "c", "LLMsControlDock") || data != filepath.Join(base, "d", "LLMsControlDock") || state != filepath.Join(base, "s", "LLMsControlDock") {
		// Report the problem.
		t.Fatalf("roots: %q %q %q", cfg, data, state)
	} // end of the roots check
	// Version 0.25.0 kept everything in the configuration folder.
	writeTestFile(t, filepath.Join(cfg, "settings.json"), `{}`)
	// The history file.
	writeTestFile(t, filepath.Join(cfg, checkHistoryFileName), `{"version":1}`)
	// The icon picture.
	writeTestFile(t, filepath.Join(cfg, iconFileName), `png`)
	// The results.
	writeTestFile(t, filepath.Join(cfg, "performanceCompare", "performance.json"), `{"runs":[]}`)
	// Copy the folders and the files.
	msgs := append(migrateOldData(data, cfg, ""), migrateOldFiles(cfg, data, state)...)
	// Three copies were made.
	if len(msgs) != 3 {
		// Report the problem.
		t.Errorf("messages: %v", msgs)
	} // end of the count check
	// Each file is in its proper folder.
	for _, p := range []string{filepath.Join(data, "performanceCompare", "performance.json"), filepath.Join(data, iconFileName), filepath.Join(state, checkHistoryFileName)} {
		// It must exist.
		if _, err := os.Stat(p); err != nil {
			// Report the problem.
			t.Errorf("missing %s: %v", p, err)
		} // end of the check
	} // end of the loop
	// The old files stay, and the settings stay where they are.
	for _, p := range []string{filepath.Join(cfg, "settings.json"), filepath.Join(cfg, checkHistoryFileName), filepath.Join(cfg, iconFileName)} {
		// It must still exist.
		if _, err := os.Stat(p); err != nil {
			// Report the problem.
			t.Errorf("old file gone %s: %v", p, err)
		} // end of the check
	} // end of the loop
	// A second run copies nothing (no overwrite).
	if again := append(migrateOldData(data, cfg, ""), migrateOldFiles(cfg, data, state)...); len(again) != 0 {
		// Report the problem.
		t.Errorf("second run: %v", again)
	} // end of the second-run check
	// The same folder for all three (macOS): nothing to move.
	if m := migrateOldFiles(cfg, cfg, cfg); len(m) != 0 {
		// Report the problem.
		t.Errorf("same folder: %v", m)
	} // end of the same-folder check
} // end of TestThreeRootsAndMoves

// TestHistoryUsesStateFolder checks that the check history is written to and read from the state folder, and removed from it when the history is turned off.
func TestHistoryUsesStateFolder(t *testing.T) {
	// Two folders.
	cfg, state := t.TempDir(), t.TempDir()
	// A store with both.
	s := openSettingsStore(cfg, "")
	// The state folder.
	s.stateDir = state
	// Save one check.
	now := time.Now()
	// Write.
	if err := s.saveSamples([]sample{{At: now, Online: true}}); err != nil {
		// Report the problem.
		t.Fatal(err)
	} // end of the save check
	// It is in the state folder, not the settings folder.
	if _, err := os.Stat(filepath.Join(state, checkHistoryFileName)); err != nil {
		// Report the problem.
		t.Errorf("not in the state folder: %v", err)
	} // end of the state check
	// Not in the configuration folder.
	if _, err := os.Stat(filepath.Join(cfg, checkHistoryFileName)); err == nil {
		// Report the problem.
		t.Error("history written to the configuration folder")
	} // end of the config check
	// Turning the history off removes it.
	if err := s.put(appSettings{OllamaURL: "http://127.0.0.1:11434"}); err != nil {
		// Report the problem.
		t.Fatal(err)
	} // end of the put check
	// Gone.
	if _, err := os.Stat(filepath.Join(state, checkHistoryFileName)); err == nil {
		// Report the problem.
		t.Error("history file stayed behind")
	} // end of the removal check
} // end of TestHistoryUsesStateFolder

// modesApply says whether file permission bits mean anything on this system: Go's documentation says that on Windows only the owner-writable bit is used (it sets the read-only attribute), so private files there rest on the per-user access rules of the folders in %AppData% and %LocalAppData%, not on 0600 and 0700.
func modesApply() bool {
	// Only Windows lacks Unix permission bits.
	return runtime.GOOS != "windows"
} // end of modesApply
