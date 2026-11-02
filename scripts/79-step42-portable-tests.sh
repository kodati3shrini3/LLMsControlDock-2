#!/usr/bin/env bash
# Script 79 (make the tests portable to Windows and macOS, Windows 11 first): the first manual GitHub run showed which tests fail on Windows and macOS. This change fixes the one real program difference (a results folder below a plain file now always means memory only, also on Windows), adds .gitattributes so source and web files use LF line endings on every system (a Windows checkout turned them into CRLF and broke two tests), and makes the tests system-aware: no Unix permission bits on Windows, replaceable machine readers instead of fake /proc files, resolved links on macOS, case-insensitive disks, a coarse Windows clock, and no Linux desktop-icon tests on Windows. The version becomes 0.27.1.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/portable-tests" ] || { echo "FAIL  not on feature/portable-tests"; exit 1; }
# Refuse to run twice.
if [ -e .gitattributes ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/.gitattributes b/.gitattributes
new file mode 100644
index 0000000..1a32198
--- /dev/null
+++ b/.gitattributes
@@ -0,0 +1,13 @@
+# Line endings: source, web, script and workflow files always use LF, on every system, so the tests and gofmt give the same result on Windows, macOS and Linux (Go's own tools expect LF).
+*.go text eol=lf
+*.html text eol=lf
+*.css text eol=lf
+*.js text eol=lf
+*.md text eol=lf
+*.txt text eol=lf
+*.yml text eol=lf
+*.sh text eol=lf
+go.mod text eol=lf
+go.sum text eol=lf
+# Pictures and the built program are binary: never changed.
+*.png binary
diff --git a/about.go b/about.go
index 3609e19..6bc449a 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.27.0"
+const appVersion = "0.27.1"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/appsettings_test.go b/appsettings_test.go
index 7cb7776..e2f2bef 100644
--- a/appsettings_test.go
+++ b/appsettings_test.go
@@ -142,8 +142,8 @@ func TestSettingsStoreRoundTrip(t *testing.T) {
 		// Stop.
 		t.Fatal(err)
 	} // end of the stat check
-	// Owner only (not on Windows, where the bits mean little).
-	if info.Mode().Perm()&0o077 != 0 {
+	// Owner only (not checked on Windows: see modesApply).
+	if modesApply() && info.Mode().Perm()&0o077 != 0 {
 		// Report it.
 		t.Errorf("settings file mode %v is readable by others", info.Mode().Perm())
 	} // end of the mode check
diff --git a/backarrow_test.go b/backarrow_test.go
index 6670ff9..ac95a9e 100644
--- a/backarrow_test.go
+++ b/backarrow_test.go
@@ -42,7 +42,7 @@ func TestEverySubPageTemplateHasTheBackArrow(t *testing.T) {
 		// The main page and the shared bubble texts have none; every other page has exactly one.
 		want := 1
 		// The two exceptions.
-		if f == "web/index.html" || f == "web/tips.html" {
+		if g := filepath.ToSlash(f); g == "web/index.html" || g == "web/tips.html" {
 			// None.
 			want = 0
 		} // end of the exception check
diff --git a/compreport_test.go b/compreport_test.go
index 0e8a0cb..624dde9 100644
--- a/compreport_test.go
+++ b/compreport_test.go
@@ -489,7 +489,7 @@ func TestDownloadsAreAlsoSavedAsCopies(t *testing.T) {
 		t.Fatalf("copy %q err %v", b, err)
 	} // end of the read check
 	// Only the owner may read it.
-	if st, _ := os.Stat(p); st.Mode().Perm() != 0o600 {
+	if st, _ := os.Stat(p); modesApply() && st.Mode().Perm() != 0o600 {
 		// Report it.
 		t.Errorf("mode %v", st.Mode().Perm())
 	} // end of the mode check
diff --git a/datafolder_test.go b/datafolder_test.go
index 5dcaf3b..108e6ef 100644
--- a/datafolder_test.go
+++ b/datafolder_test.go
@@ -8,6 +8,8 @@ import ( // import lists the packages this test file uses.
 	"os"
 	// path/filepath joins file names.
 	"path/filepath"
+	// runtime tells which system the test runs on.
+	"runtime"
 	// strings searches the log sentences.
 	"strings"
 	// testing is Go's built-in test framework.
@@ -175,7 +177,7 @@ func TestMigrateOldData(t *testing.T) {
 		} // end of the check
 	} // end of the loop
 	// The copy is private and no temporary folder is left.
-	if st, err := os.Stat(filepath.Join(newRoot, "performanceCompare")); err != nil || st.Mode().Perm() != 0o700 {
+	if st, err := os.Stat(filepath.Join(newRoot, "performanceCompare")); err != nil || (modesApply() && st.Mode().Perm() != 0o700) {
 		// Report the problem.
 		t.Errorf("new folder: %v %v", st, err)
 	} // end of the privacy check
@@ -476,3 +478,9 @@ func TestHistoryUsesStateFolder(t *testing.T) {
 		t.Error("history file stayed behind")
 	} // end of the removal check
 } // end of TestHistoryUsesStateFolder
+
+// modesApply says whether file permission bits mean anything on this system: Go's documentation says that on Windows only the owner-writable bit is used (it sets the read-only attribute), so private files there rest on the per-user access rules of the folders in %AppData% and %LocalAppData%, not on 0600 and 0700.
+func modesApply() bool {
+	// Only Windows lacks Unix permission bits.
+	return runtime.GOOS != "windows"
+} // end of modesApply
diff --git a/delete_test.go b/delete_test.go
index 0e81fed..81bd9a4 100644
--- a/delete_test.go
+++ b/delete_test.go
@@ -454,7 +454,7 @@ func TestDeleteConfirmDeletesAndRemembers(t *testing.T) {
 		t.Fatalf("no deleted-models file: %v", err)
 	} // end of the file check
 	// Owner only.
-	if info.Mode().Perm() != 0o600 {
+	if modesApply() && info.Mode().Perm() != 0o600 {
 		// Report it.
 		t.Errorf("file mode %o, want 600", info.Mode().Perm())
 	} // end of the mode check
@@ -971,7 +971,7 @@ func TestOldDeletedFileMovesToTheNewFolder(t *testing.T) {
 		t.Errorf("the old file is still there")
 	} // end of the old-file check
 	// The new folder is private.
-	if st, err := os.Stat(filepath.Dir(newFile)); err != nil || st.Mode().Perm() != 0o700 {
+	if st, err := os.Stat(filepath.Dir(newFile)); err != nil || (modesApply() && st.Mode().Perm() != 0o700) {
 		// Report it.
 		t.Errorf("folder mode %v, error %v", st, err)
 	} // end of the mode check
diff --git a/desktopicon_test.go b/desktopicon_test.go
index 4d18579..55f729b 100644
--- a/desktopicon_test.go
+++ b/desktopicon_test.go
@@ -18,6 +18,8 @@ import ( // import lists the packages this test file uses.
 	"path/filepath"
 	// regexp finds the page token.
 	"regexp"
+	// runtime tells which system the test runs on.
+	"runtime"
 	// strings searches the page text.
 	"strings"
 	// testing is Go's test framework.
@@ -44,8 +46,18 @@ type fakeDesktop struct {
 func newFakeDesktop(t *testing.T) fakeDesktop {
 	// Mark this as a helper.
 	t.Helper()
-	// The pretend home.
-	home := t.TempDir()
+	// The desktop icon is offered on Linux only and its paths are Unix paths, so a Windows test run has nothing to check here.
+	if runtime.GOOS == "windows" {
+		// Skip with the reason.
+		t.Skip("the desktop icon is offered on Linux only; its paths are Unix paths")
+	} // end of the Windows check
+	// The pretend home, with symbolic links resolved (on macOS the temporary folder /var is really /private/var, and the program resolves links too).
+	home, err := filepath.EvalSymlinks(t.TempDir())
+	// A failure means the test itself is wrong.
+	if err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the home check
 	// Its desktop folder.
 	desk := filepath.Join(home, "Desktop")
 	// Make it.
diff --git a/history_test.go b/history_test.go
index 68e005c..9bd460f 100644
--- a/history_test.go
+++ b/history_test.go
@@ -119,12 +119,12 @@ func TestDeleteSavesSnapshotFirst(t *testing.T) {
 		t.Fatalf("history files: %v", names)
 	} // end of the count check
 	// Its mode.
-	if info, _ := os.Stat(filepath.Join(hd, names[0])); info.Mode().Perm() != 0o600 {
+	if info, _ := os.Stat(filepath.Join(hd, names[0])); modesApply() && info.Mode().Perm() != 0o600 {
 		// Report it.
 		t.Errorf("file mode %o, want 600", info.Mode().Perm())
 	} // end of the file mode check
 	// The folder mode.
-	if info, _ := os.Stat(hd); info.Mode().Perm() != 0o700 {
+	if info, _ := os.Stat(hd); modesApply() && info.Mode().Perm() != 0o700 {
 		// Report it.
 		t.Errorf("folder mode %o, want 700", info.Mode().Perm())
 	} // end of the folder mode check
diff --git a/perf_test.go b/perf_test.go
index 8747495..3c7e246 100644
--- a/perf_test.go
+++ b/perf_test.go
@@ -26,6 +26,8 @@ import ( // import lists the packages this test file uses.
 	"sync"
 	// testing is Go's built-in test framework.
 	"testing"
+	// time gives the small delay of the fake Ollama.
+	"time"
 ) // end of imports
 
 // secretText is the answer text of the fake; it must never reach a page of the monitor's own making or the saved file.
@@ -192,6 +194,8 @@ func (f *perfFake) start(t *testing.T) string {
 			} // end of the thinking check
 			// The last piece carries the figures.
 			last := map[string]any{"response": "", "done": true, "done_reason": "stop", "total_duration": load + prompt + eval, "load_duration": load, "prompt_eval_count": 200, "prompt_eval_duration": prompt, "eval_count": 64, "eval_duration": eval}
+			// The first piece comes a few milliseconds late, so that even a coarse clock (Windows) measures a time above zero.
+			time.Sleep(3 * time.Millisecond)
 			// The flusher sends each line at once.
 			fl, _ := w.(http.Flusher)
 			// Both pieces.
@@ -275,35 +279,25 @@ func (f *perfFake) unloadCount() int {
 	return len(f.unloads)
 } // end of unloadCount
 
-// quietMachine points the machine readers at a calm fake machine for one test and restores them afterwards.
+// quietMachine points the machine readers at a calm fake machine for one test and restores them afterwards; it replaces the readers themselves, so it works the same on every system (the Linux file reader has its own test in sysinfo_linux_test.go).
 func quietMachine(t *testing.T) {
 	// Mark this as a helper.
 	t.Helper()
-	// A folder that plays the role of /proc.
-	dir := t.TempDir()
-	// The files.
-	for name, text := range map[string]string{
-		// Four-core machine, quiet.
-		"cpuinfo": "processor\t: 0\nmodel name\t: Test Processor 9000\n",
-		// Load of 0.5 on 4 cores.
-		"loadavg": "0.50 0.40 0.30 1/200 123\n",
-		// 16 GB total, 8 GB free, swap 2 GB with 1 GB free (in kilobytes).
-		"meminfo": "MemTotal:       16000000 kB\nMemAvailable:    8000000 kB\nSwapTotal:       2000000 kB\nSwapFree:        1000000 kB\n",
-	} { // end of the files
-		// Write each.
-		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o600); err != nil {
-			// Stop the test.
-			t.Fatalf("fixture: %v", err)
-		} // end of the write check
-	} // end of the loop
-	// Remember the real readers.
-	oldProc, oldGPU := procDir, gpuQuery
-	// Use the fixtures.
-	procDir = dir
+	// Remember the real readers and the graphics-card query.
+	oldMem, oldCPU, oldLoad, oldGPU := readMemInfo, readCPUName, readLoad1, gpuQuery
+	// Put them back at the end.
+	t.Cleanup(func() { readMemInfo, readCPUName, readLoad1, gpuQuery = oldMem, oldCPU, oldLoad, oldGPU })
+	// 16.384 GB total, 8.192 GB free, swap 2.048 GB with 1.024 GB in use.
+	readMemInfo = func() (memInfo, error) {
+		// The figures.
+		return memInfo{TotalBytes: 16_384_000_000, AvailBytes: 8_192_000_000, HaveSwap: true, SwapTotalBytes: 2_048_000_000, SwapUsedBytes: 1_024_000_000}, nil
+	} // end of the memory reader
+	// A named processor.
+	readCPUName = func() string { return "Test Processor 9000" }
+	// A load of 0.5, far below half of the cores of any machine.
+	readLoad1 = func() float64 { return 0.5 }
 	// A card that is idle and shares its memory.
 	gpuQuery = func(ctx context.Context) (string, error) { return "Test GPU, [N/A], [N/A], 0 %", nil }
-	// Put the real readers back at the end.
-	t.Cleanup(func() { procDir, gpuQuery = oldProc, oldGPU })
 } // end of quietMachine
 
 // perfRig builds a web handler for a fake, with the history in a folder of the test; it returns the rig and the history file path.
@@ -314,16 +308,12 @@ func perfRig(t *testing.T, f *perfFake) (themeRig, string) {
 	quietMachine(t)
 	// The history goes into a folder of this test, never into the real configuration folder.
 	dir := t.TempDir()
-	// Remember the real lookup.
-	old := userConfigDir
-	// Use the test folder.
 	// Keep the real lookups and put them back afterwards.
 	saveFolderLookups(t)
+	// Use the test folder.
 	userConfigDir = func() (string, error) { return dir, nil }
 	// Data and state follow the same fake folder.
 	userDataDir, userStateDir = userConfigDir, userConfigDir
-	// Put it back at the end.
-	t.Cleanup(func() { userConfigDir = old })
 	// Start the fake and build the handler.
 	h := handlerFor(t, f.start(t))
 	// Fetch the main page.
@@ -499,7 +489,7 @@ func TestPerfRunGenerate(t *testing.T) {
 		// Look at the file.
 		info, err := os.Stat(hist)
 		// It must exist with mode 0600.
-		if err != nil || info.Mode().Perm() != 0o600 {
+		if err != nil || (modesApply() && info.Mode().Perm() != 0o600) {
 			// Report the problem.
 			t.Errorf("history file permissions: %v %v", info, err)
 		} // end of the mode check
diff --git a/perfclear_test.go b/perfclear_test.go
index 9132b29..d35b82b 100644
--- a/perfclear_test.go
+++ b/perfclear_test.go
@@ -207,7 +207,7 @@ func TestClearAllKeepsACopy(t *testing.T) {
 		t.Errorf("copy is wrong: %v %+v", err, got)
 	} // end of the content check
 	// Only this user may read it.
-	if st, _ := os.Stat(files[0]); st.Mode().Perm() != 0o600 {
+	if st, _ := os.Stat(files[0]); modesApply() && st.Mode().Perm() != 0o600 {
 		// Report the problem.
 		t.Errorf("copy mode %v, want 0600", st.Mode().Perm())
 	} // end of the mode check
diff --git a/perfstore.go b/perfstore.go
index 776ca40..e6be1cf 100644
--- a/perfstore.go
+++ b/perfstore.go
@@ -91,6 +91,29 @@ func moveOldHistoryFolder(historyPath string) string {
 	return ""
 } // end of moveOldHistoryFolder
 
+// canCreateBelow says whether a folder can be made at dir: the nearest part of the path that exists must be a folder (a plain file in the way makes it impossible).
+func canCreateBelow(dir string) bool {
+	// Walk up until something exists.
+	for {
+		// Look at this level.
+		st, err := os.Stat(dir)
+		// It exists: it must be a folder.
+		if err == nil {
+			// The answer.
+			return st.IsDir()
+		} // end of the exists case
+		// The next level up.
+		parent := filepath.Dir(dir)
+		// The top was reached without finding anything: nothing blocks it here.
+		if parent == dir {
+			// Nothing is in the way.
+			return true
+		} // end of the top check
+		// Look one level up.
+		dir = parent
+	} // end of the loop
+} // end of canCreateBelow
+
 // mustStat returns the file information of a path that was just found to exist; a failure gives nil, which SameFile treats as "not the same".
 func mustStat(p string) os.FileInfo {
 	// Look at it.
@@ -131,8 +154,15 @@ func openPerfStore(path, note string) *perfStore {
 	} // end of the memory case
 	// Look at the file.
 	info, err := os.Stat(path)
-	// No file yet is normal.
+	// No file yet is normal, as long as the folder can be made later: Linux answers "not a directory" when a parent is a plain file (handled below as another problem), Windows answers "path not found" (the same words as "no file yet"), so the nearest existing parent is checked here.
 	if errors.Is(err, os.ErrNotExist) {
+		// A parent that is not a folder: the file could never be saved.
+		if !canCreateBelow(filepath.Dir(path)) {
+			// Keep the results in memory only, and say why.
+			s.path, s.note = "", "The results folder cannot be created below "+filepath.Dir(path)+", so results are kept only until the monitor stops."
+			// Done.
+			return s
+		} // end of the parent check
 		// Start empty.
 		return s
 	} // end of the missing-file case
diff --git a/perfstore_rename_test.go b/perfstore_rename_test.go
index 6f66d23..854b163 100644
--- a/perfstore_rename_test.go
+++ b/perfstore_rename_test.go
@@ -52,7 +52,7 @@ func TestOldResultsFolderIsRenamed(t *testing.T) {
 		} // end of the read check
 	} // end of the files loop
 	// The folder under the old name is gone (on a computer that ignores capitals the two names are one folder, so only check when they differ).
-	if _, err := os.Stat(old); err == nil && historyFolderName != oldHistoryFolderName {
+	if _, err := os.Stat(old); err == nil && historyFolderName != oldHistoryFolderName && !ignoresCapitals(t, root) {
 		// A case-blind disk answers for the new folder too; look at the real entry names.
 		ents, _ := os.ReadDir(root)
 		// Every entry.
@@ -102,3 +102,48 @@ func TestOldResultsFolderIsRenamed(t *testing.T) {
 		t.Errorf("message %q for memory only", msg)
 	} // end of the memory check
 } // end of TestOldResultsFolderIsRenamed
+
+// ignoresCapitals says whether the disk of dir treats "A" and "a" as the same name (Windows and macOS usually do; Linux does not).
+func ignoresCapitals(t *testing.T, dir string) bool {
+	// Mark this as a helper.
+	t.Helper()
+	// A file with a lower-case name in a folder of its own.
+	probe := filepath.Join(t.TempDir(), "probe")
+	// Make it.
+	if err := os.WriteFile(probe, []byte("x"), 0o600); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the write check
+	// Ask for it with a capital letter.
+	_, err := os.Stat(filepath.Join(filepath.Dir(probe), "PROBE"))
+	// Found: the disk ignores capitals.
+	return err == nil
+} // end of ignoresCapitals
+
+// TestCanCreateBelow checks that a plain file in the way is noticed on every system, and that missing folders are not a problem.
+func TestCanCreateBelow(t *testing.T) {
+	// A folder, a plain file in it.
+	base := t.TempDir()
+	// The file.
+	plain := filepath.Join(base, "plain-file")
+	// Make it.
+	if err := os.WriteFile(plain, []byte("x"), 0o600); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the write check
+	// A real folder: fine.
+	if !canCreateBelow(base) {
+		// Report it.
+		t.Error("an existing folder was refused")
+	} // end of the folder check
+	// Folders that do not exist yet below a real folder: fine.
+	if !canCreateBelow(filepath.Join(base, "a", "b")) {
+		// Report it.
+		t.Error("missing folders below a real folder were refused")
+	} // end of the missing check
+	// A plain file in the way: refused, directly and further down.
+	if canCreateBelow(plain) || canCreateBelow(filepath.Join(plain, "sub")) {
+		// Report it.
+		t.Error("a plain file in the way was accepted")
+	} // end of the file check
+} // end of TestCanCreateBelow
diff --git a/sysinfo_linux_test.go b/sysinfo_linux_test.go
new file mode 100644
index 0000000..599b544
--- /dev/null
+++ b/sysinfo_linux_test.go
@@ -0,0 +1,57 @@
+//go:build linux
+
+// Package main tells Go that this test file belongs to the same program as sysinfo_linux.go.
+package main
+
+import ( // import lists the packages this test file uses.
+	// os writes the fixture files.
+	"os"
+	// path/filepath joins file names.
+	"path/filepath"
+	// testing is Go's built-in test framework.
+	"testing"
+) // end of imports
+
+// TestLinuxReadersUseProcFiles checks the Linux readers against a folder that plays the role of /proc.
+func TestLinuxReadersUseProcFiles(t *testing.T) {
+	// A folder that plays the role of /proc.
+	dir := t.TempDir()
+	// The files.
+	for name, text := range map[string]string{
+		// A named processor.
+		"cpuinfo": "processor\t: 0\nmodel name\t: Test Processor 9000\n",
+		// A load of 0.5.
+		"loadavg": "0.50 0.40 0.30 1/200 123\n",
+		// 16 GB total, 8 GB free, swap 2 GB with 1 GB free (in kilobytes).
+		"meminfo": "MemTotal:       16000000 kB\nMemAvailable:    8000000 kB\nSwapTotal:       2000000 kB\nSwapFree:        1000000 kB\n",
+	} { // end of the files
+		// Write each.
+		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o600); err != nil {
+			// Stop the test.
+			t.Fatalf("fixture: %v", err)
+		} // end of the write check
+	} // end of the loop
+	// Use the fixtures and restore the real folder afterwards.
+	old := procDir
+	// Restore.
+	t.Cleanup(func() { procDir = old })
+	// Point at the fixtures.
+	procDir = dir
+	// The memory figures.
+	mi, err := osMemInfo()
+	// Compare (kilobytes are kibibytes: 1024 bytes).
+	if err != nil || mi.TotalBytes != 16_384_000_000 || mi.AvailBytes != 8_192_000_000 || !mi.HaveSwap || mi.SwapTotalBytes != 2_048_000_000 || mi.SwapUsedBytes != 1_024_000_000 {
+		// Report the problem.
+		t.Errorf("osMemInfo: %+v, %v", mi, err)
+	} // end of the memory check
+	// The processor name.
+	if n := osCPUName(); n != "Test Processor 9000" {
+		// Report the problem.
+		t.Errorf("osCPUName = %q", n)
+	} // end of the name check
+	// The load.
+	if l := osLoad1(); l != 0.5 {
+		// Report the problem.
+		t.Errorf("osLoad1 = %v", l)
+	} // end of the load check
+} // end of TestLinuxReadersUseProcFiles
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
dbbef157e7ac4a4835839fc627fbecb25d5e89d5ddb4a096ea6aa0ef05cc27cb  .gitattributes
14017ca0c3b8e7675545f30e3553e8c41289a4a909fcf9f4b9f714597f6a8e5d  about.go
9612279527a4c929d90d5c8cbcf3c7b937de89d53abe9d31c00c2521254f3a9e  appsettings_test.go
208b073e89e9b4c2ab919627b7091baa4e77b77a605042cdc2bfb0e4bd8d62c6  backarrow_test.go
0f336217ef06b70e205249e000fd22ab29eed027590c3fc646d8bd321ab84657  compreport_test.go
c994a59e45aefc805d0a8d5f315530320f438b74dde707a676d99613af472186  datafolder_test.go
2a1fe9ee96c5b23393811926601d76495a90e9ed1001a9acaddc9ecf6c7d62c8  delete_test.go
6ce6dcfca2cfa9a90d9511ae033400ecdee63d7dd9c0fc61decb6161e3d19d29  desktopicon_test.go
6e4e54c75cc67acf7df0779b22406214e7be00f174f60e7fdcf6571c4c31a780  history_test.go
4ff83adbb9217ff80574ae8289efbbe8a709b10a6bded2ab91965d909d92e3db  perf_test.go
64fb2e3f7069a98a2987f8057e4bc833aa531f38e2a20c887ce36868b3315b0f  perfclear_test.go
3ce6cb31b50d18c5a6e3d4a46df8aa648109636865c1609493d57053435cf559  perfstore.go
fc4e8798340b222d19f47f0d7aec6c233df2d67022f4eb2c9f0db40ee4f1ead1  perfstore_rename_test.go
61d41833ebeaf858a5ff63ffd42154c887041ec56aac55cec050f457b8f1d03b  sysinfo_linux_test.go
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
echo "NEXT  start ./bin/OllamaControlCenter and check the main page opens (the program changed in one place only: a results folder that cannot be created); then commit, push and merge, and run the workflow again to see Windows and macOS"
# List the changed files; nothing is committed yet.
git status --short
