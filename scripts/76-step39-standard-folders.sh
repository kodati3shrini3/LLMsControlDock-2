#!/usr/bin/env bash
# Script 76: the program now keeps its files in the three standard folders of each system instead of one: settings (configuration) in Linux ~/.config, Windows %AppData%, macOS ~/Library/Application Support; results, saved copies, deleted models, snapshots and the icon picture (data) in Linux ~/.local/share, Windows %LocalAppData%, macOS ~/Library/Application Support; the check history and the log (state) in Linux ~/.local/state, Windows %LocalAppData%, macOS ~/Library/Application Support. Linux follows the XDG Base Directory Specification. At the first start the files of version 0.25.0 are COPIED to the new folders once and the old files are left in place. The version becomes 0.26.0.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/standard-folders" ] || { echo "FAIL  not on feature/standard-folders"; exit 1; }
# Refuse to run twice.
if grep -q baseDirFor datafolder.go; then
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
index 8b53862..0f90d6c 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.25.0"
+const appVersion = "0.26.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/appsettings.go b/appsettings.go
index 3cf7b10..ba66bad 100644
--- a/appsettings.go
+++ b/appsettings.go
@@ -135,27 +135,40 @@ func (a appSettings) problems() []string {
 type settingsStore struct {
 	// mu protects everything below.
 	mu sync.Mutex
-	// dir is the folder of the files; empty means memory only.
+	// dir is the configuration folder (the settings); empty means memory only.
 	dir string
+	// stateDir is the state folder (the check history); empty means the same folder as dir.
+	stateDir string
 	// cur is the current settings.
 	cur appSettings
 	// note says why the file is not used or was ignored (empty when all is well).
 	note string
 } // end of settingsStore
 
-// settingsFolder finds the folder of the settings file; the second value is a plain note when none was found.
+// settingsFolder finds the configuration folder of the settings file (each system's standard place, see datafolder.go); the second value is a plain note when none was found.
 func settingsFolder() (string, string) {
-	// The person's configuration folder (a test replaces userConfigDir).
-	dir, err := userConfigDir()
+	// The program's own folder inside the configuration base (a test replaces userConfigDir).
+	dir := configRoot()
 	// No folder: memory only.
-	if err != nil || dir == "" {
+	if dir == "" {
 		// Say so.
 		return "", "No folder for the settings was found, so they are kept only until the monitor stops."
 	} // end of the lookup check
-	// The program's own folder inside it, the same one the performance results use.
-	return filepath.Join(dir, "OllamaControlCenter"), ""
+	// The folder.
+	return dir, ""
 } // end of settingsFolder
 
+// stateFolder returns the folder of the check history: the state folder when one is set, else the settings folder; empty means memory only.
+func (s *settingsStore) stateFolder() string {
+	// A state folder was set.
+	if s.stateDir != "" {
+		// Use it.
+		return s.stateDir
+	} // end of the state check
+	// Otherwise the settings folder.
+	return s.dir
+} // end of stateFolder
+
 // openSettingsStore reads the settings file when there is one; a damaged or out-of-range file is ignored with a note, never trusted.
 func openSettingsStore(dir, note string) *settingsStore {
 	// Start with the defaults.
@@ -293,15 +306,15 @@ func (s *settingsStore) put(a appSettings) error {
 				return err
 			} // end of the write check
 		} // end of the file case
-		// Without the history setting no history file may stay behind.
-		if !a.SaveHistory {
-			// Remove it; a missing file is fine.
-			if err := os.Remove(filepath.Join(s.dir, checkHistoryFileName)); err != nil && !os.IsNotExist(err) {
-				// Report it.
-				return err
-			} // end of the remove check
-		} // end of the history removal
 	} // end of the folder case
+	// Without the history setting no history file may stay behind.
+	if sf := s.stateFolder(); sf != "" && !a.SaveHistory {
+		// Remove it; a missing file is fine.
+		if err := os.Remove(filepath.Join(sf, checkHistoryFileName)); err != nil && !os.IsNotExist(err) {
+			// Report it.
+			return err
+		} // end of the remove check
+	} // end of the history removal
 	// Keep the new values.
 	s.cur = a
 	// A successful save clears an old note about an ignored file.
@@ -321,7 +334,7 @@ type checkHistoryFile struct {
 // saveSamples writes the check history to its file; it does nothing without a folder.
 func (s *settingsStore) saveSamples(items []sample) error {
 	// Without a folder there is nowhere to write.
-	if s.dir == "" {
+	if s.stateFolder() == "" {
 		// Nothing to do.
 		return nil
 	} // end of the memory case
@@ -333,18 +346,18 @@ func (s *settingsStore) saveSamples(items []sample) error {
 		return err
 	} // end of the encode check
 	// Write it.
-	return writeFile(s.dir, checkHistoryFileName, data)
+	return writeFile(s.stateFolder(), checkHistoryFileName, data)
 } // end of saveSamples
 
 // loadSamples reads the saved check history and keeps the checks inside the window; a missing or damaged file gives nothing.
 func (s *settingsStore) loadSamples(window time.Duration, now time.Time) []sample {
 	// Without a folder there is nothing to read.
-	if s.dir == "" {
+	if s.stateFolder() == "" {
 		// Nothing.
 		return nil
 	} // end of the memory case
 	// Open the file.
-	f, err := os.Open(filepath.Join(s.dir, checkHistoryFileName))
+	f, err := os.Open(filepath.Join(s.stateFolder(), checkHistoryFileName))
 	// A missing file is normal.
 	if err != nil {
 		// Nothing.
diff --git a/datafolder.go b/datafolder.go
index 334c440..96526d0 100644
--- a/datafolder.go
+++ b/datafolder.go
@@ -2,6 +2,8 @@
 package main
 
 import ( // import lists the standard-library packages this file uses.
+	// errors builds fixed error messages.
+	"errors"
 	// fmt builds the messages.
 	"fmt"
 	// io copies a file.
@@ -12,20 +14,126 @@ import ( // import lists the standard-library packages this file uses.
 	"path/filepath"
 	// regexp recognises the file names this program writes.
 	"regexp"
+	// runtime tells which operating system this is.
+	"runtime"
 	// strings checks name beginnings and endings.
 	"strings"
 ) // end of imports
 
-// dataFolderName is the folder, inside the person's configuration folder, that holds everything the program saves (settings, results, deleted models, snapshots, saved copies).
+// dataFolderName is the program's own folder inside each of the three base folders (config, data, state).
 const dataFolderName = "OllamaControlCenter"
 
 // maxMigrateBytes is the largest file that is copied from an old folder; a bigger file is never one of this program's own.
 var maxMigrateBytes int64 = 100 << 20
 
-// dataRoot returns the one folder where all saved data lives on every operating system: OllamaControlCenter inside the configuration folder (Linux: ~/.config, Windows: %AppData%, macOS: ~/Library/Application Support); it returns empty text when no configuration folder is known.
-func dataRoot() string {
-	// Ask Go for the configuration folder (a test replaces userConfigDir).
-	dir, err := userConfigDir()
+// The three kinds of saved file, as the Linux XDG Base Directory Specification names them: configuration (what the person chose), data (what the person created) and state (what the program can reuse on a restart, such as logs and history).
+const (
+	// kindConfig is for settings.
+	kindConfig = "config"
+	// kindData is for results, saved copies, deleted models and snapshots.
+	kindData = "data"
+	// kindState is for the check history and the log.
+	kindState = "state"
+) // end of the kinds
+
+// baseDirFor returns the base folder for one kind on one operating system, following that system's own standard; the program's own folder is added by the caller. Linux and other Unix systems follow the XDG Base Directory Specification (a variable that is empty or not an absolute path is ignored, as the specification says); Windows keeps configuration in %AppData% and data and state in %LocalAppData%; macOS keeps all three in ~/Library/Application Support. The operating system and the lookups are parameters so that a test can try every system.
+func baseDirFor(goos, kind string, getenv func(string) string, home func() (string, error)) (string, error) {
+	// Pick the system.
+	switch goos {
+	// Windows: configuration roams with the user, data and state stay on this computer.
+	case "windows":
+		// Data and state live in the local folder.
+		name := "LocalAppData"
+		// Configuration lives in the roaming folder.
+		if kind == kindConfig {
+			// The roaming folder.
+			name = "AppData"
+		} // end of the configuration check
+		// Read the variable.
+		dir := getenv(name)
+		// Not defined.
+		if dir == "" {
+			// A fixed message.
+			return "", errors.New("%" + name + "% is not defined")
+		} // end of the variable check
+		// The folder.
+		return dir, nil
+	// macOS: one folder for all kinds, as Apple's File System Programming Guide describes.
+	case "darwin", "ios":
+		// The person's home folder.
+		h, err := home()
+		// Not known.
+		if err != nil || h == "" {
+			// A fixed message.
+			return "", errors.New("$HOME is not defined")
+		} // end of the home check
+		// The folder.
+		return h + "/Library/Application Support", nil
+	} // end of the system switch
+	// Linux and the others: the XDG variable and its default for this kind.
+	envName, rel := "XDG_CONFIG_HOME", "/.config"
+	// Data.
+	if kind == kindData {
+		// The data variable and default.
+		envName, rel = "XDG_DATA_HOME", "/.local/share"
+	} // end of the data check
+	// State.
+	if kind == kindState {
+		// The state variable and default.
+		envName, rel = "XDG_STATE_HOME", "/.local/state"
+	} // end of the state check
+	// A variable that holds an absolute path is used as it is; anything else is ignored, as the specification says.
+	if v := getenv(envName); strings.HasPrefix(v, "/") {
+		// The person's choice.
+		return v, nil
+	} // end of the variable check
+	// The default below the home folder.
+	h, err := home()
+	// Not known.
+	if err != nil || h == "" {
+		// A fixed message.
+		return "", errors.New("neither $" + envName + " nor $HOME is defined")
+	} // end of the home check
+	// The folder.
+	return h + rel, nil
+} // end of baseDirFor
+
+// osUserBaseDir asks baseDirFor about the real system for one kind.
+func osUserBaseDir(kind string) (string, error) {
+	// The real system, the real environment and the real home folder.
+	return baseDirFor(runtime.GOOS, kind, os.Getenv, os.UserHomeDir)
+} // end of osUserBaseDir
+
+// osUserConfigDir is the real configuration base folder.
+func osUserConfigDir() (string, error) {
+	// Ask for the configuration kind.
+	return osUserBaseDir(kindConfig)
+} // end of osUserConfigDir
+
+// osUserDataDir is the real data base folder.
+func osUserDataDir() (string, error) {
+	// Ask for the data kind.
+	return osUserBaseDir(kindData)
+} // end of osUserDataDir
+
+// osUserStateDir is the real state base folder.
+func osUserStateDir() (string, error) {
+	// Ask for the state kind.
+	return osUserBaseDir(kindState)
+} // end of osUserStateDir
+
+// The two lookups that are not in perfstore.go; a test replaces them so it never touches the real folders.
+var (
+	// userDataDir finds the base folder for data.
+	userDataDir = osUserDataDir
+	// userStateDir finds the base folder for state.
+	userStateDir = osUserStateDir
+) // end of the lookups
+
+// rootOf adds the program's own folder to a base folder; it returns empty text when no base folder is known.
+func rootOf(lookup func() (string, error)) string {
+	// Ask.
+	dir, err := lookup()
 	// None found.
 	if err != nil || dir == "" {
 		// The caller keeps the data in memory and says why.
@@ -33,9 +141,27 @@ func dataRoot() string {
 	} // end of the lookup check
 	// The program's own folder inside it.
 	return filepath.Join(dir, dataFolderName)
+} // end of rootOf
+
+// configRoot is the folder of the settings and the desktop-icon choice.
+func configRoot() string {
+	// The configuration base.
+	return rootOf(userConfigDir)
+} // end of configRoot
+
+// dataRoot is the folder of the results, the saved copies, the deleted models and the snapshots.
+func dataRoot() string {
+	// The data base.
+	return rootOf(userDataDir)
 } // end of dataRoot
 
-// oldDataRoot returns the folder earlier versions used for the saved data: the folder the program is in, or the folder above it when the program sits in a folder called bin; it returns empty text when the program's place is unknown.
+// stateRoot is the folder of the check history and the log.
+func stateRoot() string {
+	// The state base.
+	return rootOf(userStateDir)
+} // end of stateRoot
+
+// oldDataRoot returns the folder the oldest versions used for the saved data: the folder the program is in, or the folder above it when the program sits in a folder called bin; it returns empty text when the program's place is unknown.
 func oldDataRoot() string {
 	// Where is the running program?
 	exe, err := executablePath()
@@ -169,23 +295,96 @@ func migrateFolder(oldDir, newDir string) string {
 	return fmt.Sprintf("Copied %d saved file(s) from %s to %s; the old folder was left in place and can be deleted when it is no longer needed.", len(names), oldDir, newDir)
 } // end of migrateFolder
 
-// migrateOldData copies the three folders of earlier versions (results, deleted models, snapshots) from the old place to the new one; it returns the sentences for the log.
-func migrateOldData(oldRoot, newRoot string) []string {
-	// Unknown places, or the same place: nothing to do.
-	if oldRoot == "" || newRoot == "" || oldRoot == newRoot {
+// migrateOldData copies the three data folders (results, deleted models, snapshots) of earlier versions into the data folder, once; the sources are tried in the order given (the first one that has the folder wins), and an unknown source, or one that is the data folder itself, is skipped. It returns the sentences for the log.
+func migrateOldData(newRoot string, sources ...string) []string {
+	// An unknown data folder: nothing to do.
+	if newRoot == "" {
 		// Nothing to do.
 		return nil
 	} // end of the place check
 	// The sentences.
 	var msgs []string
-	// The three folders earlier versions kept next to the program.
-	for _, name := range []string{historyFolderName, deletedFolderName, historyDirName} {
-		// Copy one.
-		if msg := migrateFolder(filepath.Join(oldRoot, name), filepath.Join(newRoot, name)); msg != "" {
+	// Each place earlier versions used.
+	for _, src := range sources {
+		// Unknown, or the same place: skip.
+		if src == "" || src == newRoot {
+			// Next source.
+			continue
+		} // end of the source check
+		// The three folders earlier versions kept there.
+		for _, name := range []string{historyFolderName, deletedFolderName, historyDirName} {
+			// Copy one.
+			if msg := migrateFolder(filepath.Join(src, name), filepath.Join(newRoot, name)); msg != "" {
+				// Keep the sentence.
+				msgs = append(msgs, msg)
+			} // end of the message check
+		} // end of the folder loop
+	} // end of the source loop
+	// Hand them back.
+	return msgs
+} // end of migrateOldData
+
+// migrateFile copies one file of this program from an old place to a new one, once: it does nothing when the old file is missing, is not a plain file, is too large, or the new file exists already; the old file is never changed. It returns a sentence for the log, or empty text.
+func migrateFile(oldPath, newPath string) string {
+	// Look at the old file.
+	st, err := os.Stat(oldPath)
+	// Missing, not a plain file, or too large: nothing to do.
+	if err != nil || !st.Mode().IsRegular() || st.Size() > maxMigrateBytes {
+		// Nothing to do.
+		return ""
+	} // end of the old-file check
+	// The new file exists already: it is never touched.
+	if _, err := os.Lstat(newPath); err == nil {
+		// Nothing to do.
+		return ""
+	} // end of the new-file check
+	// Make sure the folder exists, readable only by this user.
+	if err := os.MkdirAll(filepath.Dir(newPath), 0o700); err != nil {
+		// Say so; the old file stays where it is.
+		return fmt.Sprintf("%s could not be copied to %s (%v); it was left where it is.", oldPath, newPath, err)
+	} // end of the folder check
+	// Copy to a temporary name first, so a half copy is never mistaken for the real file.
+	tmp := newPath + ".copying"
+	// A leftover from an earlier attempt is this program's own and is removed.
+	os.Remove(tmp)
+	// Copy.
+	if err := copyOne(oldPath, tmp); err != nil {
+		// Throw the half copy away.
+		os.Remove(tmp)
+		// Say so.
+		return fmt.Sprintf("%s could not be copied to %s (%v); it was left where it is.", oldPath, newPath, err)
+	} // end of the copy check
+	// Put the finished copy in its place in one step.
+	if err := os.Rename(tmp, newPath); err != nil {
+		// Throw the copy away.
+		os.Remove(tmp)
+		// Say so.
+		return fmt.Sprintf("%s could not be copied to %s (%v); it was left where it is.", oldPath, newPath, err)
+	} // end of the rename check
+	// Done.
+	return fmt.Sprintf("Copied %s to %s; the old file was left in place and can be deleted when it is no longer needed.", oldPath, newPath)
+} // end of migrateFile
+
+// migrateOldFiles copies the two single files that earlier versions kept in the configuration folder to their proper folders: the check history to the state folder and the icon picture to the data folder. Unknown or equal folders are skipped (on macOS all three folders are the same).
+func migrateOldFiles(config, data, state string) []string {
+	// The sentences.
+	var msgs []string
+	// The check history belongs in the state folder.
+	if config != "" && state != "" && config != state {
+		// Copy it.
+		if msg := migrateFile(filepath.Join(config, checkHistoryFileName), filepath.Join(state, checkHistoryFileName)); msg != "" {
 			// Keep the sentence.
 			msgs = append(msgs, msg)
 		} // end of the message check
-	} // end of the folder loop
+	} // end of the history check
+	// The icon picture belongs in the data folder.
+	if config != "" && data != "" && config != data {
+		// Copy it.
+		if msg := migrateFile(filepath.Join(config, iconFileName), filepath.Join(data, iconFileName)); msg != "" {
+			// Keep the sentence.
+			msgs = append(msgs, msg)
+		} // end of the message check
+	} // end of the icon check
 	// Hand them back.
 	return msgs
-} // end of migrateOldData
+} // end of migrateOldFiles
diff --git a/datafolder_test.go b/datafolder_test.go
index a8a45cf..5dcaf3b 100644
--- a/datafolder_test.go
+++ b/datafolder_test.go
@@ -12,6 +12,8 @@ import ( // import lists the packages this test file uses.
 	"strings"
 	// testing is Go's built-in test framework.
 	"testing"
+	// time gives the moment of a check.
+	"time"
 ) // end of imports
 
 // writeTestFile writes one file for a test, making its folder first.
@@ -68,14 +70,22 @@ func TestDataRootAndOldDataRoot(t *testing.T) {
 	// Put them back afterwards.
 	t.Cleanup(func() { executablePath, userConfigDir = oldExe, oldCfg })
 	// A configuration folder.
+	// Keep the real lookups and put them back afterwards.
+	saveFolderLookups(t)
 	userConfigDir = func() (string, error) { return "/cfg", nil }
+	// Data and state follow the same fake folder.
+	userDataDir, userStateDir = userConfigDir, userConfigDir
 	// The new folder.
 	if got := dataRoot(); got != filepath.Join("/cfg", "OllamaControlCenter") {
 		// Report the problem.
 		t.Errorf("dataRoot = %q", got)
 	} // end of the new-folder check
 	// No configuration folder.
+	// Keep the real lookups and put them back afterwards.
+	saveFolderLookups(t)
 	userConfigDir = func() (string, error) { return "", errors.New("none") }
+	// Data and state follow the same fake folder.
+	userDataDir, userStateDir = userConfigDir, userConfigDir
 	// Nothing.
 	if got := dataRoot(); got != "" {
 		// Report the problem.
@@ -121,7 +131,7 @@ func TestMigrateOldData(t *testing.T) {
 	// A snapshot.
 	writeTestFile(t, filepath.Join(oldRoot, "history", "2026-11-02_17-54-00+0100_m.json"), "SNAP")
 	// Copy.
-	msgs := migrateOldData(oldRoot, newRoot)
+	msgs := migrateOldData(newRoot, oldRoot)
 	// One sentence per folder.
 	if len(msgs) != 3 {
 		// Report the problem.
@@ -177,7 +187,7 @@ func TestMigrateOldData(t *testing.T) {
 	// New data is never overwritten by a second start, even when the old files change.
 	writeTestFile(t, filepath.Join(oldRoot, "performanceCompare", "performance.json"), "CHANGED")
 	// Second start.
-	if msgs := migrateOldData(oldRoot, newRoot); len(msgs) != 0 {
+	if msgs := migrateOldData(newRoot, oldRoot); len(msgs) != 0 {
 		// Report the problem.
 		t.Errorf("second run: %q", msgs)
 	} // end of the second-run check
@@ -199,7 +209,7 @@ func TestMigrateSkipsOtherPeoplesFolders(t *testing.T) {
 	// Another one.
 	writeTestFile(t, filepath.Join(oldRoot, "history", "report.pdf"), "X")
 	// Copy.
-	if msgs := migrateOldData(oldRoot, newRoot); len(msgs) != 0 {
+	if msgs := migrateOldData(newRoot, oldRoot); len(msgs) != 0 {
 		// Report the problem.
 		t.Errorf("messages: %q", msgs)
 	} // end of the message check
@@ -209,7 +219,7 @@ func TestMigrateSkipsOtherPeoplesFolders(t *testing.T) {
 		t.Error("a folder was created for somebody else's files")
 	} // end of the creation check
 	// Unknown or equal places do nothing.
-	if migrateOldData("", newRoot) != nil || migrateOldData(oldRoot, "") != nil || migrateOldData(oldRoot, oldRoot) != nil {
+	if migrateOldData(newRoot, "") != nil || migrateOldData("", oldRoot) != nil || migrateOldData(oldRoot, oldRoot) != nil {
 		// Report the problem.
 		t.Error("an unknown or equal place did something")
 	} // end of the place check
@@ -234,7 +244,7 @@ func TestMigrateRules(t *testing.T) {
 	// A leftover temporary folder from an earlier attempt.
 	writeTestFile(t, filepath.Join(newRoot, "performanceCompare.copying", "junk.json"), "junk")
 	// Copy.
-	if msgs := migrateOldData(oldRoot, newRoot); len(msgs) != 1 || !strings.Contains(msgs[0], "Copied 1 saved file(s)") {
+	if msgs := migrateOldData(newRoot, oldRoot); len(msgs) != 1 || !strings.Contains(msgs[0], "Copied 1 saved file(s)") {
 		// Report the problem.
 		t.Fatalf("messages: %q", msgs)
 	} // end of the message check
@@ -256,7 +266,7 @@ func TestMigrateRules(t *testing.T) {
 		t.Fatalf("fixture: %v", err)
 	} // end of the folder check
 	// Copy again.
-	if msgs := migrateOldData(oldRoot, newRoot); len(msgs) != 0 {
+	if msgs := migrateOldData(newRoot, oldRoot); len(msgs) != 0 {
 		// Report the problem.
 		t.Errorf("an existing folder was touched: %q", msgs)
 	} // end of the existing check
@@ -284,7 +294,11 @@ func TestStartupCopiesOldData(t *testing.T) {
 	// The configuration folder.
 	cfg := filepath.Join(base, "cfg")
 	// Use it.
+	// Keep the real lookups and put them back afterwards.
+	saveFolderLookups(t)
 	userConfigDir = func() (string, error) { return cfg, nil }
+	// Data and state follow the same fake folder.
+	userDataDir, userStateDir = userConfigDir, userConfigDir
 	// Build the web interface the way the program does.
 	handlerFor(t, "http://127.0.0.1:11434")
 	// The old results are now in the data folder.
@@ -293,3 +307,172 @@ func TestStartupCopiesOldData(t *testing.T) {
 		t.Errorf("not copied at start-up: %q, %v", b, err)
 	} // end of the copy check
 } // end of TestStartupCopiesOldData
+
+// saveFolderLookups remembers the three folder lookups and puts them back when the test ends.
+func saveFolderLookups(t *testing.T) {
+	// Remember the current ones.
+	c, d, s := userConfigDir, userDataDir, userStateDir
+	// Put them back at the end.
+	t.Cleanup(func() { userConfigDir, userDataDir, userStateDir = c, d, s })
+} // end of saveFolderLookups
+
+// TestBaseDirFor checks the standard folders of every system, from each system's own rules, without needing that system.
+func TestBaseDirFor(t *testing.T) {
+	// A fixed home folder lookup.
+	home := func() (string, error) { return "/home/ann", nil }
+	// A lookup from a map.
+	env := func(m map[string]string) func(string) string { return func(k string) string { return m[k] } }
+	// The cases.
+	for _, tc := range []struct {
+		// name describes the case.
+		name string
+		// goos is the system.
+		goos string
+		// kind is config, data or state.
+		kind string
+		// env is the environment.
+		env map[string]string
+		// want is the expected folder.
+		want string
+		// fail says an error is expected.
+		fail bool
+	}{
+		// Linux defaults (XDG Base Directory Specification).
+		{"linux config", "linux", kindConfig, nil, "/home/ann/.config", false},
+		{"linux data", "linux", kindData, nil, "/home/ann/.local/share", false},
+		{"linux state", "linux", kindState, nil, "/home/ann/.local/state", false},
+		// Linux with the variables set.
+		{"linux xdg data", "linux", kindData, map[string]string{"XDG_DATA_HOME": "/x/data"}, "/x/data", false},
+		{"linux xdg state", "linux", kindState, map[string]string{"XDG_STATE_HOME": "/x/state"}, "/x/state", false},
+		// A relative path is invalid and ignored, as the specification says.
+		{"linux relative ignored", "linux", kindConfig, map[string]string{"XDG_CONFIG_HOME": "rel/path"}, "/home/ann/.config", false},
+		// Windows: roaming for configuration, local for data and state.
+		{"windows config", "windows", kindConfig, map[string]string{"AppData": `C:\Users\ann\AppData\Roaming`, "LocalAppData": `C:\Users\ann\AppData\Local`}, `C:\Users\ann\AppData\Roaming`, false},
+		{"windows data", "windows", kindData, map[string]string{"AppData": `C:\R`, "LocalAppData": `C:\L`}, `C:\L`, false},
+		{"windows state", "windows", kindState, map[string]string{"AppData": `C:\R`, "LocalAppData": `C:\L`}, `C:\L`, false},
+		{"windows missing", "windows", kindData, nil, "", true},
+		// macOS: Application Support for all three.
+		{"mac config", "darwin", kindConfig, nil, "/home/ann/Library/Application Support", false},
+		{"mac data", "darwin", kindData, nil, "/home/ann/Library/Application Support", false},
+		{"mac state", "darwin", kindState, nil, "/home/ann/Library/Application Support", false},
+	} { // end of the cases
+		// Ask.
+		got, err := baseDirFor(tc.goos, tc.kind, env(tc.env), home)
+		// Compare.
+		if (err != nil) != tc.fail || got != tc.want {
+			// Report the problem.
+			t.Errorf("%s: got %q, %v; want %q (fail=%v)", tc.name, got, err, tc.want, tc.fail)
+		} // end of the compare
+	} // end of the loop
+	// No home folder on Linux and macOS.
+	noHome := func() (string, error) { return "", errors.New("none") }
+	// Both must fail.
+	if _, err := baseDirFor("linux", kindData, env(nil), noHome); err == nil {
+		// Report the problem.
+		t.Error("linux without a home folder was accepted")
+	} // end of the Linux check
+	// macOS.
+	if _, err := baseDirFor("darwin", kindData, env(nil), noHome); err == nil {
+		// Report the problem.
+		t.Error("macOS without a home folder was accepted")
+	} // end of the macOS check
+} // end of TestBaseDirFor
+
+// TestThreeRootsAndMoves checks the three folders and the copying of version 0.25.0's files to them.
+func TestThreeRootsAndMoves(t *testing.T) {
+	// Keep and restore the lookups.
+	saveFolderLookups(t)
+	// A fresh place with three base folders.
+	base := t.TempDir()
+	// The base folders.
+	userConfigDir = func() (string, error) { return filepath.Join(base, "c"), nil }
+	// Data.
+	userDataDir = func() (string, error) { return filepath.Join(base, "d"), nil }
+	// State.
+	userStateDir = func() (string, error) { return filepath.Join(base, "s"), nil }
+	// The three roots.
+	cfg, data, state := configRoot(), dataRoot(), stateRoot()
+	// Each has the program's own folder.
+	if cfg != filepath.Join(base, "c", "OllamaControlCenter") || data != filepath.Join(base, "d", "OllamaControlCenter") || state != filepath.Join(base, "s", "OllamaControlCenter") {
+		// Report the problem.
+		t.Fatalf("roots: %q %q %q", cfg, data, state)
+	} // end of the roots check
+	// Version 0.25.0 kept everything in the configuration folder.
+	writeTestFile(t, filepath.Join(cfg, "settings.json"), `{}`)
+	// The history file.
+	writeTestFile(t, filepath.Join(cfg, checkHistoryFileName), `{"version":1}`)
+	// The icon picture.
+	writeTestFile(t, filepath.Join(cfg, iconFileName), `png`)
+	// The results.
+	writeTestFile(t, filepath.Join(cfg, "performanceCompare", "performance.json"), `{"runs":[]}`)
+	// Copy the folders and the files.
+	msgs := append(migrateOldData(data, cfg, ""), migrateOldFiles(cfg, data, state)...)
+	// Three copies were made.
+	if len(msgs) != 3 {
+		// Report the problem.
+		t.Errorf("messages: %v", msgs)
+	} // end of the count check
+	// Each file is in its proper folder.
+	for _, p := range []string{filepath.Join(data, "performanceCompare", "performance.json"), filepath.Join(data, iconFileName), filepath.Join(state, checkHistoryFileName)} {
+		// It must exist.
+		if _, err := os.Stat(p); err != nil {
+			// Report the problem.
+			t.Errorf("missing %s: %v", p, err)
+		} // end of the check
+	} // end of the loop
+	// The old files stay, and the settings stay where they are.
+	for _, p := range []string{filepath.Join(cfg, "settings.json"), filepath.Join(cfg, checkHistoryFileName), filepath.Join(cfg, iconFileName)} {
+		// It must still exist.
+		if _, err := os.Stat(p); err != nil {
+			// Report the problem.
+			t.Errorf("old file gone %s: %v", p, err)
+		} // end of the check
+	} // end of the loop
+	// A second run copies nothing (no overwrite).
+	if again := append(migrateOldData(data, cfg, ""), migrateOldFiles(cfg, data, state)...); len(again) != 0 {
+		// Report the problem.
+		t.Errorf("second run: %v", again)
+	} // end of the second-run check
+	// The same folder for all three (macOS): nothing to move.
+	if m := migrateOldFiles(cfg, cfg, cfg); len(m) != 0 {
+		// Report the problem.
+		t.Errorf("same folder: %v", m)
+	} // end of the same-folder check
+} // end of TestThreeRootsAndMoves
+
+// TestHistoryUsesStateFolder checks that the check history is written to and read from the state folder, and removed from it when the history is turned off.
+func TestHistoryUsesStateFolder(t *testing.T) {
+	// Two folders.
+	cfg, state := t.TempDir(), t.TempDir()
+	// A store with both.
+	s := openSettingsStore(cfg, "")
+	// The state folder.
+	s.stateDir = state
+	// Save one check.
+	now := time.Now()
+	// Write.
+	if err := s.saveSamples([]sample{{At: now, Online: true}}); err != nil {
+		// Report the problem.
+		t.Fatal(err)
+	} // end of the save check
+	// It is in the state folder, not the settings folder.
+	if _, err := os.Stat(filepath.Join(state, checkHistoryFileName)); err != nil {
+		// Report the problem.
+		t.Errorf("not in the state folder: %v", err)
+	} // end of the state check
+	// Not in the configuration folder.
+	if _, err := os.Stat(filepath.Join(cfg, checkHistoryFileName)); err == nil {
+		// Report the problem.
+		t.Error("history written to the configuration folder")
+	} // end of the config check
+	// Turning the history off removes it.
+	if err := s.put(appSettings{OllamaURL: "http://127.0.0.1:11434"}); err != nil {
+		// Report the problem.
+		t.Fatal(err)
+	} // end of the put check
+	// Gone.
+	if _, err := os.Stat(filepath.Join(state, checkHistoryFileName)); err == nil {
+		// Report the problem.
+		t.Error("history file stayed behind")
+	} // end of the removal check
+} // end of TestHistoryUsesStateFolder
diff --git a/delete_test.go b/delete_test.go
index f704332..0e81fed 100644
--- a/delete_test.go
+++ b/delete_test.go
@@ -244,7 +244,11 @@ func delRig(t *testing.T) (themeRig, *delFake, string) {
 	// Use it as the config folder (the tests never learn the program's own path).
 	old := userConfigDir
 	// The replacement.
+	// Keep the real lookups and put them back afterwards.
+	saveFolderLookups(t)
 	userConfigDir = func() (string, error) { return dir, nil }
+	// Data and state follow the same fake folder.
+	userDataDir, userStateDir = userConfigDir, userConfigDir
 	// Put it back afterwards.
 	t.Cleanup(func() { userConfigDir = old })
 	// The fake library; every path answers 404 until a test says otherwise, and the real network is never used.
diff --git a/desktopicon.go b/desktopicon.go
index 044b8cc..fe9630b 100644
--- a/desktopicon.go
+++ b/desktopicon.go
@@ -168,10 +168,23 @@ func desktopFileText(exe, icon string) string {
 type desktopIcon struct {
 	// env is the operating system as seen by the program.
 	env desktopEnv
-	// dir is the settings folder (empty means no folder: nothing can be kept).
+	// dir is the settings folder (empty means no folder: nothing can be kept); the person's answer is kept there.
 	dir string
+	// dataDir is the data folder, where the icon picture is kept; empty means the same folder as dir.
+	dataDir string
 } // end of desktopIcon
 
+// iconDir returns the folder of the icon picture: the data folder when one is set, else the settings folder.
+func (d desktopIcon) iconDir() string {
+	// A data folder was set.
+	if d.dataDir != "" {
+		// Use it.
+		return d.dataDir
+	} // end of the data check
+	// Otherwise the settings folder.
+	return d.dir
+} // end of iconDir
+
 // available says whether this system can have a launcher (a desktop exists and the settings folder is known).
 func (d desktopIcon) available() bool {
 	// Without a settings folder the icon picture cannot be kept.
@@ -299,14 +312,14 @@ func (d desktopIcon) create() error {
 		return errUnusualPath
 	} // end of the path check
 	// Where the picture goes.
-	icon := filepath.Join(d.dir, iconFileName)
+	icon := filepath.Join(d.iconDir(), iconFileName)
 	// The picture's path must be plain too.
 	if !safePathPattern.MatchString(icon) {
 		// Refuse.
 		return errUnusualPath
 	} // end of the icon path check
 	// Write the picture.
-	if err := writeFile(d.dir, iconFileName, appIcon); err != nil {
+	if err := writeFile(d.iconDir(), iconFileName, appIcon); err != nil {
 		// Report it.
 		return err
 	} // end of the picture check
@@ -339,9 +352,9 @@ func (d desktopIcon) remove() error {
 		} // end of the delete check
 	} // end of the launcher case
 	// The picture.
-	if d.dir != "" {
+	if d.iconDir() != "" {
 		// Delete it; a missing file is fine.
-		if err := os.Remove(filepath.Join(d.dir, iconFileName)); err != nil && !os.IsNotExist(err) {
+		if err := os.Remove(filepath.Join(d.iconDir(), iconFileName)); err != nil && !os.IsNotExist(err) {
 			// Report it.
 			return err
 		} // end of the delete check
diff --git a/history.go b/history.go
index e7fabd7..6e9f444 100644
--- a/history.go
+++ b/history.go
@@ -73,7 +73,7 @@ type historyStore struct {
 	note string
 } // end of historyStore
 
-// defaultHistoryDir picks the folder: "history" inside the program's data folder (the person's configuration folder, the same on every system); empty text and a reason mean nothing can be kept.
+// defaultHistoryDir picks the folder: "history" inside the program's data folder (each system's standard place for data, see datafolder.go); empty text and a reason mean nothing can be kept.
 func defaultHistoryDir() (string, string) {
 	// The one data folder.
 	root := dataRoot()
diff --git a/history_test.go b/history_test.go
index db8b53d..68e005c 100644
--- a/history_test.go
+++ b/history_test.go
@@ -310,7 +310,11 @@ func TestDefaultHistoryDir(t *testing.T) {
 	// Put them back afterwards.
 	t.Cleanup(func() { executablePath, userConfigDir = oldExe, oldCfg })
 	// A configuration folder.
+	// Keep the real lookups and put them back afterwards.
+	saveFolderLookups(t)
 	userConfigDir = func() (string, error) { return "/cfg", nil }
+	// Data and state follow the same fake folder.
+	userDataDir, userStateDir = userConfigDir, userConfigDir
 	// A program inside bin, and one elsewhere: the same answer.
 	for _, exe := range []string{"/p/OllamaControlCenter/bin/occ", "/p/occ"} {
 		// Use this program place.
@@ -322,7 +326,11 @@ func TestDefaultHistoryDir(t *testing.T) {
 		} // end of the check
 	} // end of the loop
 	// Nothing at all.
+	// Keep the real lookups and put them back afterwards.
+	saveFolderLookups(t)
 	userConfigDir = func() (string, error) { return "", http.ErrNotSupported }
+	// Data and state follow the same fake folder.
+	userDataDir, userStateDir = userConfigDir, userConfigDir
 	// The folder and the reason.
 	if d, note := defaultHistoryDir(); d != "" || note == "" {
 		// Report it.
diff --git a/main.go b/main.go
index f9706dd..3e36ecf 100644
--- a/main.go
+++ b/main.go
@@ -149,8 +149,15 @@ func main() {
 	// Choose the Ollama address by precedence: option, then environment variable, then default.
 	// The saved settings are read first (a damaged file is ignored with a note).
 	dir, dirNote := settingsFolder()
+	// Version 0.25.0 kept the check history and the icon picture in the configuration folder; copy them once to the state and data folders (the old files are left in place).
+	for _, msg := range migrateOldFiles(dir, dataRoot(), stateRoot()) {
+		// Say so in the log.
+		log.Print(msg)
+	} // end of the copy loop
 	// Open the store.
 	store := openSettingsStore(dir, dirNote)
+	// The check history belongs in the state folder.
+	store.stateDir = stateRoot()
 	// Tell the person when the file was ignored.
 	if n := store.noteText(); n != "" {
 		// Print the note.
@@ -195,7 +202,7 @@ func main() {
 		// The address the page is served on, by the same precedence as below.
 		la, _ := chooseListen(*listen, listenGiven(), store.get().AllowOthers)
 		// Run it and leave with its exit code.
-		os.Exit(runLaunch(launchURL(la), store.dir))
+		os.Exit(runLaunch(launchURL(la), store.stateFolder()))
 	} // end of the launch mode
 	mon := newMonitorWith(store)
 	// The real desktop, so the first-run banner and the Settings buttons can place the icon.
diff --git a/perf_test.go b/perf_test.go
index 8222491..8747495 100644
--- a/perf_test.go
+++ b/perf_test.go
@@ -317,7 +317,11 @@ func perfRig(t *testing.T, f *perfFake) (themeRig, string) {
 	// Remember the real lookup.
 	old := userConfigDir
 	// Use the test folder.
+	// Keep the real lookups and put them back afterwards.
+	saveFolderLookups(t)
 	userConfigDir = func() (string, error) { return dir, nil }
+	// Data and state follow the same fake folder.
+	userDataDir, userStateDir = userConfigDir, userConfigDir
 	// Put it back at the end.
 	t.Cleanup(func() { userConfigDir = old })
 	// Start the fake and build the handler.
@@ -1080,6 +1084,8 @@ func TestMain(m *testing.M) {
 	} // end of the folder check
 	// Use it as the configuration folder.
 	userConfigDir = func() (string, error) { return dir, nil }
+	// Data and state follow the same folder.
+	userDataDir, userStateDir = userConfigDir, userConfigDir
 	// The program's own place is not used by the tests, so no test can write a folder next to the test program.
 	executablePath = func() (string, error) { return "", errors.New("not used in tests") }
 	// Run the tests.
@@ -1097,7 +1103,11 @@ func TestDefaultHistoryPath(t *testing.T) {
 	// Restore them.
 	t.Cleanup(func() { executablePath, userConfigDir = oldExe, oldCfg })
 	// A configuration folder.
+	// Keep the real lookups and put them back afterwards.
+	saveFolderLookups(t)
 	userConfigDir = func() (string, error) { return "/cfg", nil }
+	// Data and state follow the same fake folder.
+	userDataDir, userStateDir = userConfigDir, userConfigDir
 	// Wherever the program is, the answer is the same.
 	for _, exe := range []string{"/home/u/OllamaControlCenter/bin/OllamaControlCenter", "/opt/occ/OllamaControlCenter", ""} {
 		// Use this program place.
@@ -1111,7 +1121,11 @@ func TestDefaultHistoryPath(t *testing.T) {
 		} // end of the check
 	} // end of the loop
 	// No configuration folder: memory only, with a reason.
+	// Keep the real lookups and put them back afterwards.
+	saveFolderLookups(t)
 	userConfigDir = func() (string, error) { return "", errors.New("none") }
+	// Data and state follow the same fake folder.
+	userDataDir, userStateDir = userConfigDir, userConfigDir
 	// Ask.
 	if got, note := defaultHistoryPath(); got != "" || note == "" {
 		// Report it.
diff --git a/perfstore.go b/perfstore.go
index d6ac6e9..776ca40 100644
--- a/perfstore.go
+++ b/perfstore.go
@@ -22,8 +22,8 @@ const historyFileVersion = 1
 // maxHistoryFile is the largest history file the monitor will read (8 MiB, far more than 200 runs need).
 const maxHistoryFile = 8 * 1024 * 1024
 
-// userConfigDir finds the person's configuration folder; a test replaces it so it never touches the real one.
-var userConfigDir = os.UserConfigDir
+// userConfigDir finds the base folder for configuration (see baseDirFor in datafolder.go); a test replaces it so it never touches the real one.
+var userConfigDir = osUserConfigDir
 
 // historyFile is the shape of the file on disk.
 type historyFile struct {
@@ -107,7 +107,7 @@ func mustStat(p string) os.FileInfo {
 // executablePath finds the running program; a test replaces it.
 var executablePath = os.Executable
 
-// defaultHistoryPath returns the results file: in a folder named performanceCompare inside the program's data folder (the person's configuration folder, the same on every system); an empty text and a reason mean memory only.
+// defaultHistoryPath returns the results file: in a folder named performanceCompare inside the program's data folder (each system's standard place for data, see datafolder.go); an empty text and a reason mean memory only.
 func defaultHistoryPath() (string, string) {
 	// The one data folder.
 	root := dataRoot()
diff --git a/settingspage.go b/settingspage.go
index aa15d6d..674cec9 100644
--- a/settingspage.go
+++ b/settingspage.go
@@ -69,8 +69,12 @@ type settingsPage struct {
 	RestartNeeded bool
 	// Note is the plain note about the file.
 	Note string
-	// Folder is the folder of the files (empty when none was found).
+	// Folder is the configuration folder, where the settings are kept (empty when none was found).
 	Folder string
+	// DataFolder is the data folder, where the results, saved copies and deleted models are kept (empty when none was found).
+	DataFolder string
+	// StateFolder is the state folder, where the check history and the log are kept (empty when none was found).
+	StateFolder string
 	// IconAvailable is true when this system can have a desktop icon; the section is hidden otherwise.
 	IconAvailable bool
 	// IconExists is true when the launcher is on the desktop now.
@@ -241,6 +245,18 @@ func settingsHandlers(addr ollamaAddress, mon *monitor, token string) (http.Hand
 		// Show it as a clean path.
 		folder = filepath.Clean(mon.store.dir)
 	} // end of the folder check
+	// The data and state folders shown to the person, as clean paths.
+	dataFolder, stateFolder := "", ""
+	// The data folder.
+	if d := dataRoot(); d != "" {
+		// Show it as a clean path.
+		dataFolder = filepath.Clean(d)
+	} // end of the data check
+	// The state folder.
+	if st := mon.store.stateFolder(); st != "" {
+		// Show it as a clean path.
+		stateFolder = filepath.Clean(st)
+	} // end of the state check
 	// render draws the page for the given typed values and problems.
 	render := func(w http.ResponseWriter, r *http.Request, typed settingsFormValues, problems []string, saved string, status int) {
 		// The saved settings.
@@ -248,13 +264,13 @@ func settingsHandlers(addr ollamaAddress, mon *monitor, token string) (http.Hand
 		// The lines and the restart flag.
 		rows, restart := buildSettingsRows(cfg, addr, mon.run, typed)
 		// Everything the template needs.
-		desk := desktopIcon{env: mon.denv, dir: mon.store.dir}
+		desk := desktopIcon{env: mon.denv, dir: mon.store.dir, dataDir: dataRoot()}
 		// The icon section's facts.
 		iconAvail, iconExists, iconPath := desk.available(), desk.exists(), desk.desktopPath()
 		// The note after a button; unknown keys show nothing.
 		iconNote := iconNotes[r.URL.Query().Get("icon")]
 		// Everything the template needs.
-		data := settingsPage{IconAvailable: iconAvail, IconExists: iconExists, IconPath: iconPath, IconNote: iconNote, Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Rows: rows, Problems: problems, Saved: saved, RestartNeeded: restart, Note: mon.store.noteText(), Folder: folder}
+		data := settingsPage{IconAvailable: iconAvail, IconExists: iconExists, IconPath: iconPath, IconNote: iconNote, Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Rows: rows, Problems: problems, Saved: saved, RestartNeeded: restart, Note: mon.store.noteText(), Folder: folder, DataFolder: dataFolder, StateFolder: stateFolder}
 		// Build the page in memory first, so a template error gives a clean 500.
 		var buf bytes.Buffer
 		// Fill the template.
diff --git a/web.go b/web.go
index 2b96267..77f1f1e 100644
--- a/web.go
+++ b/web.go
@@ -151,7 +151,7 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	// Route: a POST request for "/textsize" saves the chosen text size in a cookie (the checks are in size.go).
 	mux.HandleFunc("POST /textsize", sizeHandler(token))
 	// The desktop icon: the launcher, and the answer to the first-run question.
-	desktop := desktopIcon{env: mon.denv, dir: mon.store.dir}
+	desktop := desktopIcon{env: mon.denv, dir: mon.store.dir, dataDir: dataRoot()}
 	// Route: a POST request for "/desktopicon" creates or removes the launcher, or records "no".
 	mux.HandleFunc("POST /desktopicon", desktopHandler(token, desktop))
 	// Route: a GET request for "/icon.png" sends the program's icon (the page header, the browser tab and the desktop icon use it).
@@ -192,8 +192,8 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	// Route: a POST request for "/modelfile" shows a model's Modelfile, read-only.
 	mux.HandleFunc("POST /modelfile", modelfileHandler(addr, token))
 	// Make the four performance handlers: the start page, the test run, and the two steps of clearing the saved results (the checks are in perfpage.go); the history lives in the person's configuration folder.
-	// Earlier versions kept the results, the deleted models and the snapshots next to the program; copy them once to the data folder (the old folders are left in place).
-	for _, msg := range migrateOldData(oldDataRoot(), dataRoot()) {
+	// Earlier versions kept the results, the deleted models and the snapshots next to the program (versions before 0.25.0) or in the configuration folder (version 0.25.0); copy them once to the data folder (the old folders are left in place).
+	for _, msg := range migrateOldData(dataRoot(), configRoot(), oldDataRoot()) {
 		// Say so in the log.
 		log.Print(msg)
 	} // end of the copy loop
diff --git a/web/settings.html b/web/settings.html
index 3d1d920..3b83b5f 100644
--- a/web/settings.html
+++ b/web/settings.html
@@ -62,7 +62,7 @@
 {{/* The warning about other machines: the page has no password. */}}
 <p class="warn"><strong>⚠</strong> If you let other machines open this page, anyone on your network can use its buttons (unload, delete, stop). The page has no password, so turn this on only on a network you trust.</p>
 {{/* Where the files are kept. */}}
-<p class="muted">Saved in <code>{{if .Folder}}{{.Folder}}{{else}}(no folder found: kept only until the monitor stops){{end}}</code>. The check history file holds only the time, the result and the answer time of each check: no model names and no prompts. Turning the history off deletes that file.</p>
+<p class="muted">Settings are saved in <code>{{if .Folder}}{{.Folder}}{{else}}(no folder found: kept only until the monitor stops){{end}}</code>. Results, saved copies and deleted models are saved in <code>{{if .DataFolder}}{{.DataFolder}}{{else}}(no folder found){{end}}</code>. The check history and the log are saved in <code>{{if .StateFolder}}{{.StateFolder}}{{else}}(no folder found){{end}}</code>. These are the standard places of this system. The check history file holds only the time, the result and the answer time of each check: no model names and no prompts. Turning the history off deletes that file.</p>
 {{/* The buttons. */}}
 <p><button type="submit" name="action" value="save" class="btn-plain">Save settings</button> <button type="submit" name="action" value="defaults" class="btn-plain">Back to defaults</button> <a class="btn-plain" href="/settings">Cancel</a></p>
 {{/* End of the form. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
3fd8f592062edbf36028bb824c3767d4ba55392719f49d8960ad66d9ca4cd3e1  about.go
c29a4b4073b7a6269b1380cf60db3aa75a1933a35bc4efe2ff8d7b01895d6378  appsettings.go
ba5bf3d93be2efd46127811ead68139ec98a9229d6fb49a09d997a1c2e3e5dd8  datafolder.go
b4378420fc3e8afc4a8bc009820ea396891e846873ac9c9e85e28401ceab600c  datafolder_test.go
66fabd9e19be8310b69c8611f02a39e37739a9496d87b09b65a78f8c2f385b41  delete_test.go
209daeab767480a7adbee81c1ac4c2cf6df754c4d06f8cb5498d37b7665404f2  desktopicon.go
5ff2d41214de9001f2a18554e09b9d345c6a53cc84246ad55695ecb6ae65b586  history.go
395f6e210024920296ff9abf66d0a787d794714c753c1e8897119cd9386d9d56  history_test.go
aad581ebdb86376b9e765eb10006d942075d066284107519f674ccdb59eb7e74  main.go
35e5343b803686c7380285f8ee8a55dc16bf59b22d7c7f61e24da143ca83a68f  perf_test.go
27a3ef03e68509bc50599ac1f68eee345271175bdaa1aa13096f8fdb9c344cef  perfstore.go
89a57123f512cd545f6ac8766db59ca8288b42ca9a863fc57defe385141fe768  settingspage.go
7e02d92a1344162236c26880a98f5a944a023761907d592506aec41256287b16  web.go
eda8888d70b4d4658c8055e2b13bd05079ac93045bb3d7534479b756ea42b104  web/settings.html
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
echo "NEXT  start ./bin/OllamaControlCenter and read the first log lines: they must say Copied ... to ~/.local/state/OllamaControlCenter/checkhistory.json (if a check history existed), ... icon.png to ~/.local/share/..., and Copied N saved file(s) to ~/.local/share/OllamaControlCenter/...; then open http://127.0.0.1:8765/settings and read the three folders"
# List the changed files; nothing is committed yet.
git status --short
