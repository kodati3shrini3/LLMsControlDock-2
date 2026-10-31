#!/usr/bin/env bash
# Script 70 (F10, version 0.22.0): the Settings page. A Settings button on the monitor page opens a page where you change the Ollama address, the check interval (5-300 s), the check timeout (1-60 s), the chart history (5-240 min), whether other machines may open the page, and whether the check history is saved to a file. The values are kept in settings.json in your configuration folder. Order of precedence for the address: command-line option, environment variable, saved setting, default. Also: the About page table now fits a phone-width window.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/settings-panel" ] || { echo "FAIL  not on feature/settings-panel"; exit 1; }
# Refuse to run twice.
if [ -e settingspage.go ]; then
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
index 6921328..8203ac5 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.21.0"
+const appVersion = "0.22.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/appsettings.go b/appsettings.go
new file mode 100644
index 0000000..3cf7b10
--- /dev/null
+++ b/appsettings.go
@@ -0,0 +1,374 @@
+// Package main tells Go that this folder builds into a runnable program, not a library.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// encoding/json reads and writes the settings file and the saved check history.
+	"encoding/json"
+	// fmt builds the plain-language problem messages.
+	"fmt"
+	// io limits how much of a file is read.
+	"io"
+	// os reads, writes and removes the files.
+	"os"
+	// path/filepath joins folder and file names for any operating system.
+	"path/filepath"
+	// sync keeps two requests from changing the settings at the same moment.
+	"sync"
+	// time provides the durations of the settings.
+	"time"
+) // end of imports
+
+// The limits of the numeric settings (requirement F10, answer 7A); a value outside them is refused with a plain message.
+const (
+	// minIntervalSeconds is the shortest time between two background checks.
+	minIntervalSeconds = 5
+	// maxIntervalSeconds is the longest time between two background checks.
+	maxIntervalSeconds = 300
+	// minTimeoutSeconds is the shortest time one check waits for Ollama.
+	minTimeoutSeconds = 1
+	// maxTimeoutSeconds is the longest time one check waits for Ollama.
+	maxTimeoutSeconds = 60
+	// minHistoryMinutes is the shortest chart history.
+	minHistoryMinutes = 5
+	// maxHistoryMinutes is the longest chart history.
+	maxHistoryMinutes = 240
+) // end of the limits
+
+// settingsFileName is the file that holds the saved settings, inside the program's folder in the user's configuration folder.
+const settingsFileName = "settings.json"
+
+// checkHistoryFileName is the file that holds the saved check history (only when the person turned that on).
+const checkHistoryFileName = "checkhistory.json"
+
+// maxSettingsFile is the largest settings file the monitor will read (64 KiB; a real one is under 1 KiB).
+const maxSettingsFile = 64 * 1024
+
+// maxCheckHistoryFile is the largest check-history file the monitor will read (2 MiB; 6000 checks need about 400 KiB).
+const maxCheckHistoryFile = 2 * 1024 * 1024
+
+// appSettings holds the values the person can change on the Settings page; a zero or empty value means "not set, use the default".
+type appSettings struct {
+	// OllamaURL is the address of the Ollama server (used at the next start).
+	OllamaURL string `json:"ollama_url,omitempty"`
+	// IntervalSeconds is the time between two background checks.
+	IntervalSeconds int `json:"interval_seconds,omitempty"`
+	// TimeoutSeconds is how long one status check waits for Ollama.
+	TimeoutSeconds int `json:"timeout_seconds,omitempty"`
+	// HistoryMinutes is how much history the charts show and keep.
+	HistoryMinutes int `json:"history_minutes,omitempty"`
+	// AllowOthers lets other machines on the network open this page (used at the next start).
+	AllowOthers bool `json:"allow_others,omitempty"`
+	// SaveHistory keeps the check history in a file, so it survives a restart.
+	SaveHistory bool `json:"save_history,omitempty"`
+} // end of appSettings
+
+// interval is the time between two background checks; def is used when nothing is saved.
+func (a appSettings) interval(def time.Duration) time.Duration {
+	// A saved value wins.
+	if a.IntervalSeconds > 0 {
+		// Seconds to a duration.
+		return time.Duration(a.IntervalSeconds) * time.Second
+	} // end of the saved case
+	// Otherwise the default.
+	return def
+} // end of interval
+
+// timeout is how long one status check waits; def is used when nothing is saved.
+func (a appSettings) timeout(def time.Duration) time.Duration {
+	// A saved value wins.
+	if a.TimeoutSeconds > 0 {
+		// Seconds to a duration.
+		return time.Duration(a.TimeoutSeconds) * time.Second
+	} // end of the saved case
+	// Otherwise the default.
+	return def
+} // end of timeout
+
+// window is the chart history length; the built-in 30 minutes is used when nothing is saved.
+func (a appSettings) window() time.Duration {
+	// A saved value wins.
+	if a.HistoryMinutes > 0 {
+		// Minutes to a duration.
+		return time.Duration(a.HistoryMinutes) * time.Minute
+	} // end of the saved case
+	// Otherwise the default.
+	return chartWindow
+} // end of window
+
+// problems lists, in plain words, everything that is wrong with the values (an empty list means all is well).
+func (a appSettings) problems() []string {
+	// The list to fill.
+	var out []string
+	// The address, when given, must be usable.
+	if a.OllamaURL != "" {
+		// Reuse the same check as the command line and the environment variable.
+		if _, err := parseOllamaURL(a.OllamaURL); err != nil {
+			// Say what is wrong.
+			out = append(out, "Ollama address: "+err.Error())
+		} // end of the address check
+	} // end of the address case
+	// The interval, when given, must be inside its limits.
+	if a.IntervalSeconds != 0 && (a.IntervalSeconds < minIntervalSeconds || a.IntervalSeconds > maxIntervalSeconds) {
+		// Say the allowed range.
+		out = append(out, fmt.Sprintf("Check interval: use a whole number from %d to %d seconds.", minIntervalSeconds, maxIntervalSeconds))
+	} // end of the interval check
+	// The timeout, when given, must be inside its limits.
+	if a.TimeoutSeconds != 0 && (a.TimeoutSeconds < minTimeoutSeconds || a.TimeoutSeconds > maxTimeoutSeconds) {
+		// Say the allowed range.
+		out = append(out, fmt.Sprintf("Check timeout: use a whole number from %d to %d seconds.", minTimeoutSeconds, maxTimeoutSeconds))
+	} // end of the timeout check
+	// The history, when given, must be inside its limits.
+	if a.HistoryMinutes != 0 && (a.HistoryMinutes < minHistoryMinutes || a.HistoryMinutes > maxHistoryMinutes) {
+		// Say the allowed range.
+		out = append(out, fmt.Sprintf("Chart history: use a whole number from %d to %d minutes.", minHistoryMinutes, maxHistoryMinutes))
+	} // end of the history check
+	// The timeout must be shorter than the interval, or two checks would overlap.
+	if a.IntervalSeconds != 0 && a.TimeoutSeconds != 0 && a.TimeoutSeconds >= a.IntervalSeconds {
+		// Say so.
+		out = append(out, "Check timeout: it must be shorter than the check interval.")
+	} // end of the overlap check
+	// Hand back the list.
+	return out
+} // end of problems
+
+// settingsStore keeps the settings: in memory always, and in a file when a folder is known.
+type settingsStore struct {
+	// mu protects everything below.
+	mu sync.Mutex
+	// dir is the folder of the files; empty means memory only.
+	dir string
+	// cur is the current settings.
+	cur appSettings
+	// note says why the file is not used or was ignored (empty when all is well).
+	note string
+} // end of settingsStore
+
+// settingsFolder finds the folder of the settings file; the second value is a plain note when none was found.
+func settingsFolder() (string, string) {
+	// The person's configuration folder (a test replaces userConfigDir).
+	dir, err := userConfigDir()
+	// No folder: memory only.
+	if err != nil || dir == "" {
+		// Say so.
+		return "", "No folder for the settings was found, so they are kept only until the monitor stops."
+	} // end of the lookup check
+	// The program's own folder inside it, the same one the performance results use.
+	return filepath.Join(dir, "OllamaControlCenter"), ""
+} // end of settingsFolder
+
+// openSettingsStore reads the settings file when there is one; a damaged or out-of-range file is ignored with a note, never trusted.
+func openSettingsStore(dir, note string) *settingsStore {
+	// Start with the defaults.
+	s := &settingsStore{dir: dir, note: note}
+	// No folder, nothing to read.
+	if dir == "" {
+		// Memory only.
+		return s
+	} // end of the memory case
+	// Open the file.
+	f, err := os.Open(filepath.Join(dir, settingsFileName))
+	// A missing file is normal: nothing saved yet.
+	if err != nil {
+		// Defaults.
+		return s
+	} // end of the open check
+	// Close it at the end.
+	defer f.Close()
+	// Read at most the limit, so a huge file cannot fill memory.
+	var a appSettings
+	// Decode the JSON.
+	if err := json.NewDecoder(io.LimitReader(f, maxSettingsFile)).Decode(&a); err != nil {
+		// Ignore the file and say why.
+		s.note = "The saved settings file could not be read, so the defaults are used."
+		// Defaults.
+		return s
+	} // end of the decode check
+	// A value outside its limits is refused as a whole.
+	if len(a.problems()) > 0 {
+		// Ignore the file and say why.
+		s.note = "The saved settings file holds a value outside its limits, so the defaults are used."
+		// Defaults.
+		return s
+	} // end of the limits check
+	// The file is good.
+	s.cur = a
+	// Hand back the store.
+	return s
+} // end of openSettingsStore
+
+// get returns a copy of the current settings.
+func (s *settingsStore) get() appSettings {
+	// One at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// The copy.
+	return s.cur
+} // end of get
+
+// noteText returns the plain note about the file (empty when all is well).
+func (s *settingsStore) noteText() string {
+	// One at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// The note.
+	return s.note
+} // end of noteText
+
+// writeFile writes data next to its final name and then renames it, so a crash never leaves half a file; only the owner can read it.
+func writeFile(dir, name string, data []byte) error {
+	// Make the folder, private to the owner.
+	if err := os.MkdirAll(dir, 0o700); err != nil {
+		// Report it.
+		return err
+	} // end of the folder check
+	// A temporary file in the same folder, so the rename stays on one disk.
+	tmp, err := os.CreateTemp(dir, name+".tmp*")
+	// Report a failure.
+	if err != nil {
+		// Report it.
+		return err
+	} // end of the create check
+	// Write the data.
+	if _, err := tmp.Write(data); err != nil {
+		// Clean up.
+		tmp.Close()
+		// Remove the temporary file.
+		os.Remove(tmp.Name())
+		// Report it.
+		return err
+	} // end of the write check
+	// Close it, which also reports a late write failure.
+	if err := tmp.Close(); err != nil {
+		// Remove the temporary file.
+		os.Remove(tmp.Name())
+		// Report it.
+		return err
+	} // end of the close check
+	// Only the owner may read it.
+	if err := os.Chmod(tmp.Name(), 0o600); err != nil {
+		// Remove the temporary file.
+		os.Remove(tmp.Name())
+		// Report it.
+		return err
+	} // end of the chmod check
+	// Swap it into place.
+	if err := os.Rename(tmp.Name(), filepath.Join(dir, name)); err != nil {
+		// Remove the temporary file.
+		os.Remove(tmp.Name())
+		// Report it.
+		return err
+	} // end of the rename check
+	// Done.
+	return nil
+} // end of writeFile
+
+// put replaces the settings; the file is written first, and the settings change in memory only when the write worked (or when there is no folder). Turning the history off removes the saved history file.
+func (s *settingsStore) put(a appSettings) error {
+	// One at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// With a folder, save the file.
+	if s.dir != "" {
+		// An all-default setting removes the file instead of writing an empty one.
+		if a == (appSettings{}) {
+			// Remove it; a missing file is fine.
+			if err := os.Remove(filepath.Join(s.dir, settingsFileName)); err != nil && !os.IsNotExist(err) {
+				// Report it.
+				return err
+			} // end of the remove check
+		} else { // the other case
+			// Encode with indentation, so a person can read the file.
+			data, err := json.MarshalIndent(a, "", "  ")
+			// Report a failure.
+			if err != nil {
+				// Report it.
+				return err
+			} // end of the encode check
+			// Write it.
+			if err := writeFile(s.dir, settingsFileName, append(data, '\n')); err != nil {
+				// Report it.
+				return err
+			} // end of the write check
+		} // end of the file case
+		// Without the history setting no history file may stay behind.
+		if !a.SaveHistory {
+			// Remove it; a missing file is fine.
+			if err := os.Remove(filepath.Join(s.dir, checkHistoryFileName)); err != nil && !os.IsNotExist(err) {
+				// Report it.
+				return err
+			} // end of the remove check
+		} // end of the history removal
+	} // end of the folder case
+	// Keep the new values.
+	s.cur = a
+	// A successful save clears an old note about an ignored file.
+	s.note = ""
+	// Done.
+	return nil
+} // end of put
+
+// checkHistoryFile is the shape of the saved check history.
+type checkHistoryFile struct {
+	// Version is the format number.
+	Version int `json:"version"`
+	// Samples holds the checks, oldest first.
+	Samples []sample `json:"samples"`
+} // end of checkHistoryFile
+
+// saveSamples writes the check history to its file; it does nothing without a folder.
+func (s *settingsStore) saveSamples(items []sample) error {
+	// Without a folder there is nowhere to write.
+	if s.dir == "" {
+		// Nothing to do.
+		return nil
+	} // end of the memory case
+	// Encode.
+	data, err := json.Marshal(checkHistoryFile{Version: 1, Samples: items})
+	// Report a failure.
+	if err != nil {
+		// Report it.
+		return err
+	} // end of the encode check
+	// Write it.
+	return writeFile(s.dir, checkHistoryFileName, data)
+} // end of saveSamples
+
+// loadSamples reads the saved check history and keeps the checks inside the window; a missing or damaged file gives nothing.
+func (s *settingsStore) loadSamples(window time.Duration, now time.Time) []sample {
+	// Without a folder there is nothing to read.
+	if s.dir == "" {
+		// Nothing.
+		return nil
+	} // end of the memory case
+	// Open the file.
+	f, err := os.Open(filepath.Join(s.dir, checkHistoryFileName))
+	// A missing file is normal.
+	if err != nil {
+		// Nothing.
+		return nil
+	} // end of the open check
+	// Close it at the end.
+	defer f.Close()
+	// Decode at most the limit.
+	var h checkHistoryFile
+	// A damaged file gives nothing.
+	if err := json.NewDecoder(io.LimitReader(f, maxCheckHistoryFile)).Decode(&h); err != nil || h.Version != 1 {
+		// Nothing.
+		return nil
+	} // end of the decode check
+	// Keep the checks that are inside the window and not in the future.
+	var out []sample
+	// Walk them.
+	for _, it := range h.Samples {
+		// Inside the window and not later than now.
+		if !it.At.Before(now.Add(-window)) && !it.At.After(now) {
+			// Keep it.
+			out = append(out, it)
+		} // end of the window check
+	} // end of the loop
+	// Hand back the checks.
+	return out
+} // end of loadSamples
diff --git a/appsettings_test.go b/appsettings_test.go
new file mode 100644
index 0000000..06e5b8f
--- /dev/null
+++ b/appsettings_test.go
@@ -0,0 +1,570 @@
+// Package main tells Go that this test file belongs to the same program as appsettings.go.
+package main
+
+import ( // import lists the packages this test file uses.
+	// net/http provides status codes.
+	"net/http"
+	// net/url builds the forms.
+	"net/url"
+	// os looks at the files the settings write.
+	"os"
+	// path/filepath joins file names.
+	"path/filepath"
+	// regexp finds the page token.
+	"regexp"
+	// strings searches the page text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+	// time provides durations.
+	"time"
+) // end of imports
+
+// settingsRig is a web handler wired to a settings store in a temporary folder.
+type settingsRig struct {
+	// h is the handler.
+	h http.Handler
+	// mon is the monitor with the store.
+	mon *monitor
+	// dir is the temporary folder.
+	dir string
+	// token is the page token.
+	token string
+} // end of settingsRig
+
+// newSettingsRig builds the rig; run says how the program was started.
+func newSettingsRig(t *testing.T, run runInfo) *settingsRig {
+	// Mark this as a helper.
+	t.Helper()
+	// A fresh folder for the files.
+	dir := t.TempDir()
+	// The monitor with a store in it.
+	mon := newMonitorWith(openSettingsStore(dir, ""))
+	// How the program runs.
+	mon.run = run
+	// The default address, as the program resolves it with nothing set.
+	addr, err := resolve("", "")
+	// A bad address means the test is wrong.
+	if err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the address check
+	// The handler.
+	h := newWebHandlerWith(addr, time.Second, mon)
+	// The page carries the token.
+	_, _, body := get(t, h, http.MethodGet, "/settings")
+	// Find the token.
+	m := regexp.MustCompile(`name="token" value="([0-9a-f]+)"`).FindStringSubmatch(body)
+	// The page must carry one.
+	if m == nil {
+		// Stop.
+		t.Fatal("the settings page has no token")
+	} // end of the token check
+	// Hand back the rig.
+	return &settingsRig{h: h, mon: mon, dir: dir, token: m[1]}
+} // end of newSettingsRig
+
+// save posts the form with the given values (the token is added).
+func (r *settingsRig) save(t *testing.T, v url.Values) *http.Response {
+	// Mark this as a helper.
+	t.Helper()
+	// The token and the action.
+	v.Set("token", r.token)
+	// The save button.
+	if v.Get("action") == "" {
+		// Save.
+		v.Set("action", "save")
+	} // end of the action default
+	// Send it as the page would.
+	return post(t, r.h, "/settings", v, fromThisPage)
+} // end of save
+
+// TestSettingsProblems checks the limits and the plain messages.
+func TestSettingsProblems(t *testing.T) {
+	// The cases.
+	cases := []struct {
+		// The name, the settings and the word the message must contain ("" means all is well).
+		name string
+		a    appSettings
+		want string
+	}{
+		{"empty is fine", appSettings{}, ""},
+		{"good numbers", appSettings{IntervalSeconds: 30, TimeoutSeconds: 10, HistoryMinutes: 60}, ""},
+		{"interval too small", appSettings{IntervalSeconds: 4}, "Check interval"},
+		{"interval too large", appSettings{IntervalSeconds: 301}, "Check interval"},
+		{"timeout too small", appSettings{TimeoutSeconds: -1}, "Check timeout"},
+		{"timeout too large", appSettings{TimeoutSeconds: 61}, "Check timeout"},
+		{"history too small", appSettings{HistoryMinutes: 4}, "Chart history"},
+		{"history too large", appSettings{HistoryMinutes: 241}, "Chart history"},
+		{"timeout not shorter", appSettings{IntervalSeconds: 10, TimeoutSeconds: 10}, "shorter"},
+		{"bad address", appSettings{OllamaURL: "ftp://x"}, "Ollama address"},
+		{"good address", appSettings{OllamaURL: "http://10.0.0.5:11434"}, ""},
+	} // end of the cases
+	// Run them.
+	for _, c := range cases {
+		// The problems.
+		got := strings.Join(c.a.problems(), " | ")
+		// All well.
+		if c.want == "" && got != "" {
+			// Report it.
+			t.Errorf("%s: unexpected problems %q", c.name, got)
+		} // end of the fine check
+		// A problem is expected.
+		if c.want != "" && !strings.Contains(got, c.want) {
+			// Report it.
+			t.Errorf("%s: problems %q lack %q", c.name, got, c.want)
+		} // end of the problem check
+	} // end of the loop
+} // end of TestSettingsProblems
+
+// TestSettingsStoreRoundTrip checks that saved settings survive a restart, with private file rights, and that the defaults remove the file.
+func TestSettingsStoreRoundTrip(t *testing.T) {
+	// A folder.
+	dir := t.TempDir()
+	// The store.
+	s := openSettingsStore(dir, "")
+	// Save some values.
+	want := appSettings{OllamaURL: "http://10.0.0.5:11434", IntervalSeconds: 30, TimeoutSeconds: 10, HistoryMinutes: 60, AllowOthers: true, SaveHistory: true}
+	// Put them.
+	if err := s.put(want); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the put check
+	// A new store reads them back (a restart).
+	if got := openSettingsStore(dir, "").get(); got != want {
+		// Report it.
+		t.Errorf("after restart got %+v want %+v", got, want)
+	} // end of the read check
+	// The file is private to the owner.
+	info, err := os.Stat(filepath.Join(dir, settingsFileName))
+	// It must exist.
+	if err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the stat check
+	// Owner only (not on Windows, where the bits mean little).
+	if info.Mode().Perm()&0o077 != 0 {
+		// Report it.
+		t.Errorf("settings file mode %v is readable by others", info.Mode().Perm())
+	} // end of the mode check
+	// The defaults remove the file.
+	if err := s.put(appSettings{}); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the reset check
+	// Gone.
+	if _, err := os.Stat(filepath.Join(dir, settingsFileName)); !os.IsNotExist(err) {
+		// Report it.
+		t.Errorf("settings file still there after the defaults: %v", err)
+	} // end of the gone check
+} // end of TestSettingsStoreRoundTrip
+
+// TestSettingsStoreIgnoresBadFiles checks that damaged or out-of-range files are ignored with a note.
+func TestSettingsStoreIgnoresBadFiles(t *testing.T) {
+	// The bad contents.
+	for name, text := range map[string]string{"not json": "{{{", "out of range": `{"interval_seconds": 1}`, "bad address": `{"ollama_url": "ftp://x"}`} {
+		// A folder.
+		dir := t.TempDir()
+		// Write the file.
+		if err := os.WriteFile(filepath.Join(dir, settingsFileName), []byte(text), 0o600); err != nil {
+			// Stop.
+			t.Fatal(err)
+		} // end of the write check
+		// Open it.
+		s := openSettingsStore(dir, "")
+		// The defaults are used.
+		if s.get() != (appSettings{}) {
+			// Report it.
+			t.Errorf("%s: bad file was used: %+v", name, s.get())
+		} // end of the defaults check
+		// A note says why.
+		if s.noteText() == "" {
+			// Report it.
+			t.Errorf("%s: no note about the ignored file", name)
+		} // end of the note check
+	} // end of the loop
+} // end of TestSettingsStoreIgnoresBadFiles
+
+// TestSettingsPageSaves checks the whole path: the page, a good save, a refused save, and the defaults.
+func TestSettingsPageSaves(t *testing.T) {
+	// The rig: the program runs on this computer only.
+	r := newSettingsRig(t, runInfo{Listen: defaultListen, ListenSource: sourceDefault})
+	// The page shows all six settings and the warning.
+	_, _, body := get(t, r.h, http.MethodGet, "/settings")
+	// The things it must say.
+	for _, w := range []string{"Ollama address", "Check interval (seconds)", "Check timeout (seconds)", "Chart history (minutes)", "Let other machines open this page", "Save check history to a file", "no password", `name="interval"`} {
+		// Look for it.
+		if !strings.Contains(body, w) {
+			// Report it.
+			t.Errorf("the settings page lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// A good save: interval 30, timeout 8, history 60.
+	res := r.save(t, url.Values{"ollama_url": {""}, "interval": {"30"}, "timeout": {"8"}, "history": {"60"}, "others": {"no"}, "savehistory": {"no"}})
+	// It redirects back to the page.
+	if res.StatusCode != http.StatusSeeOther || !strings.Contains(res.Header.Get("Location"), "/settings?saved=saved") {
+		// Report it.
+		t.Fatalf("good save: status %d location %q", res.StatusCode, res.Header.Get("Location"))
+	} // end of the redirect check
+	// The store holds the values, and they apply at once.
+	if got := r.mon.store.get(); got.IntervalSeconds != 30 || got.TimeoutSeconds != 8 || got.HistoryMinutes != 60 {
+		// Report it.
+		t.Errorf("saved values wrong: %+v", got)
+	} // end of the value check
+	// The timeout in force is the saved one.
+	if r.mon.timeoutOr(time.Second) != 8*time.Second {
+		// Report it.
+		t.Errorf("timeout in force %v", r.mon.timeoutOr(time.Second))
+	} // end of the timeout check
+	// Values equal to the defaults are stored as not set.
+	r.save(t, url.Values{"interval": {"10"}, "timeout": {"5"}, "history": {"30"}, "others": {"no"}, "savehistory": {"no"}})
+	// Nothing is stored, so no file stays.
+	if got := r.mon.store.get(); got != (appSettings{}) {
+		// Report it.
+		t.Errorf("defaults were stored as values: %+v", got)
+	} // end of the default check
+	// A refused save: interval out of range, text instead of a number, and nothing changes.
+	r.save(t, url.Values{"interval": {"30"}, "timeout": {"8"}, "history": {"60"}, "others": {"no"}, "savehistory": {"no"}})
+	// Now the bad form.
+	res = r.save(t, url.Values{"interval": {"2"}, "timeout": {"abc"}, "history": {"60"}, "others": {"no"}, "savehistory": {"no"}})
+	// It is refused with 422.
+	if res.StatusCode != http.StatusUnprocessableEntity {
+		// Report it.
+		t.Errorf("bad save status %d", res.StatusCode)
+	} // end of the status check
+	// The body names both problems and keeps what was typed.
+	text := bodyOf(res)
+	// The messages.
+	for _, w := range []string{"Check interval: use a whole number from 5 to 300", "Check timeout: use a whole number", `value="2"`} {
+		// Look for it.
+		if !strings.Contains(text, w) {
+			// Report it.
+			t.Errorf("refused page lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// The earlier values stay.
+	if got := r.mon.store.get(); got.IntervalSeconds != 30 {
+		// Report it.
+		t.Errorf("a refused save changed the settings: %+v", got)
+	} // end of the unchanged check
+	// A timeout that is not shorter than the interval, with the interval at its default, is refused.
+	res = r.save(t, url.Values{"interval": {"10"}, "timeout": {"10"}, "history": {"30"}, "others": {"no"}, "savehistory": {"no"}})
+	// Refused.
+	if res.StatusCode != http.StatusUnprocessableEntity {
+		// Report it.
+		t.Errorf("overlap status %d", res.StatusCode)
+	} // end of the overlap check
+	// Back to the defaults.
+	res = r.save(t, url.Values{"action": {"defaults"}})
+	// Redirect with the reset note.
+	if res.StatusCode != http.StatusSeeOther || !strings.Contains(res.Header.Get("Location"), "saved=reset") {
+		// Report it.
+		t.Errorf("defaults: status %d location %q", res.StatusCode, res.Header.Get("Location"))
+	} // end of the defaults check
+	// Everything is cleared.
+	if got := r.mon.store.get(); got != (appSettings{}) {
+		// Report it.
+		t.Errorf("defaults left values: %+v", got)
+	} // end of the cleared check
+} // end of TestSettingsPageSaves
+
+// TestSettingsPageSecurity checks that a save needs the token and a same-origin request.
+func TestSettingsPageSecurity(t *testing.T) {
+	// The rig.
+	r := newSettingsRig(t, runInfo{Listen: defaultListen, ListenSource: sourceDefault})
+	// The form.
+	form := url.Values{"interval": {"30"}, "action": {"save"}}
+	// No token.
+	if res := post(t, r.h, "/settings", form, fromThisPage); res.StatusCode != http.StatusForbidden {
+		// Report it.
+		t.Errorf("no token: status %d", res.StatusCode)
+	} // end of the token check
+	// A good token but a foreign origin.
+	form.Set("token", r.token)
+	// Send it.
+	if res := post(t, r.h, "/settings", form, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
+		// Report it.
+		t.Errorf("cross-site: status %d", res.StatusCode)
+	} // end of the origin check
+	// Nothing was saved.
+	if got := r.mon.store.get(); got != (appSettings{}) {
+		// Report it.
+		t.Errorf("a refused request saved %+v", got)
+	} // end of the unchanged check
+} // end of TestSettingsPageSecurity
+
+// TestSettingsPageRestartNotes checks the notes for values that wait for a restart or are overridden.
+func TestSettingsPageRestartNotes(t *testing.T) {
+	// The program runs on this computer only, from the default.
+	r := newSettingsRig(t, runInfo{Listen: defaultListen, ListenSource: sourceDefault})
+	// Save a new address and allow other machines.
+	r.save(t, url.Values{"ollama_url": {"http://10.0.0.5:11434"}, "interval": {"10"}, "timeout": {"5"}, "history": {"30"}, "others": {"yes"}, "savehistory": {"no"}})
+	// The page says both wait for a restart.
+	_, _, body := get(t, r.h, http.MethodGet, "/settings?saved=saved")
+	// The words.
+	for _, w := range []string{"saved: http://10.0.0.5:11434 (used after a restart)", "saved: Yes (used after a restart)", "used the next time the monitor starts"} {
+		// Look for it.
+		if !strings.Contains(body, w) {
+			// Report it.
+			t.Errorf("the page lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// With -listen given, the saved choice is overridden and says so.
+	r2 := newSettingsRig(t, runInfo{Listen: "127.0.0.1:9000", ListenSource: sourceFlag})
+	// Allow others.
+	r2.save(t, url.Values{"interval": {"10"}, "timeout": {"5"}, "history": {"30"}, "others": {"yes"}, "savehistory": {"no"}})
+	// The page.
+	_, _, body2 := get(t, r2.h, http.MethodGet, "/settings")
+	// The words.
+	if !strings.Contains(body2, "-listen overrides this") {
+		// Report it.
+		t.Errorf("the page does not say that -listen overrides the saved choice")
+	} // end of the override check
+} // end of TestSettingsPageRestartNotes
+
+// TestCheckHistoryFile checks that the history file is written, read after a restart, cut to the window, and deleted when switched off.
+func TestCheckHistoryFile(t *testing.T) {
+	// A folder and a store.
+	dir := t.TempDir()
+	// The store.
+	s := openSettingsStore(dir, "")
+	// Now.
+	now := time.Now()
+	// Three checks: one too old, two inside, one in the future.
+	items := []sample{{At: now.Add(-3 * time.Hour), Online: true, Ms: 1}, {At: now.Add(-10 * time.Minute), Online: true, Ms: 2}, {At: now.Add(-time.Minute), Online: false, Ms: 3}, {At: now.Add(time.Hour), Online: true, Ms: 4}}
+	// Write them.
+	if err := s.saveSamples(items); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the write check
+	// Read them back with a 30-minute window.
+	got := s.loadSamples(30*time.Minute, now)
+	// Only the two inside the window.
+	if len(got) != 2 || got[0].Ms != 2 || got[1].Ms != 3 {
+		// Report it.
+		t.Errorf("loaded %+v", got)
+	} // end of the window check
+	// A damaged file gives nothing.
+	if err := os.WriteFile(filepath.Join(dir, checkHistoryFileName), []byte("nope"), 0o600); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the damage check
+	// Nothing comes back.
+	if got := s.loadSamples(30*time.Minute, now); got != nil {
+		// Report it.
+		t.Errorf("a damaged file gave %+v", got)
+	} // end of the nothing check
+	// Write it again, then switch the history off: the file is deleted.
+	if err := s.saveSamples(items); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the rewrite check
+	// Save settings with the history off.
+	if err := s.put(appSettings{IntervalSeconds: 30}); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the put check
+	// The history file is gone.
+	if _, err := os.Stat(filepath.Join(dir, checkHistoryFileName)); !os.IsNotExist(err) {
+		// Report it.
+		t.Errorf("history file stayed after the history was switched off: %v", err)
+	} // end of the gone check
+} // end of TestCheckHistoryFile
+
+// TestMonitorWritesHistoryWhenOn checks that record writes the file every saveHistoryEvery checks only while the setting is on.
+func TestMonitorWritesHistoryWhenOn(t *testing.T) {
+	// A folder and a monitor with the history on.
+	dir := t.TempDir()
+	// The store.
+	s := openSettingsStore(dir, "")
+	// Switch it on.
+	if err := s.put(appSettings{SaveHistory: true}); err != nil {
+		// Stop.
+		t.Fatal(err)
+	} // end of the put check
+	// The monitor.
+	m := newMonitorWith(s)
+	// One short of the write.
+	for i := 0; i < saveHistoryEvery-1; i++ {
+		// A check.
+		m.record(checkResult{Online: true}, time.Now())
+	} // end of the loop
+	// No file yet.
+	if _, err := os.Stat(filepath.Join(dir, checkHistoryFileName)); !os.IsNotExist(err) {
+		// Report it.
+		t.Errorf("history file written too early: %v", err)
+	} // end of the early check
+	// The check that triggers the write.
+	m.record(checkResult{Online: true}, time.Now())
+	// The file exists.
+	if _, err := os.Stat(filepath.Join(dir, checkHistoryFileName)); err != nil {
+		// Report it.
+		t.Errorf("history file not written: %v", err)
+	} // end of the file check
+	// With the setting off nothing is written.
+	off := t.TempDir()
+	// The monitor.
+	m2 := newMonitorWith(openSettingsStore(off, ""))
+	// Many checks.
+	for i := 0; i < saveHistoryEvery*2; i++ {
+		// A check.
+		m2.record(checkResult{Online: true}, time.Now())
+	} // end of the loop
+	// No file.
+	if _, err := os.Stat(filepath.Join(off, checkHistoryFileName)); !os.IsNotExist(err) {
+		// Report it.
+		t.Errorf("history written while switched off: %v", err)
+	} // end of the off check
+} // end of TestMonitorWritesHistoryWhenOn
+
+// TestHistoryCeilingFollowsTheSettings checks that a long window at a short interval keeps more than 400 checks, never more than the hard ceiling.
+func TestHistoryCeilingFollowsTheSettings(t *testing.T) {
+	// A history with a 240-minute window and a 5-second interval.
+	h := &sampleHistory{}
+	// Set the limits.
+	h.setLimits(240*time.Minute, 5*time.Second)
+	// Now.
+	now := time.Now()
+	// More checks than the old ceiling, fewer than the new one.
+	for i := 0; i < 1000; i++ {
+		// One check, 5 seconds apart, ending now.
+		h.add(sample{At: now.Add(-time.Duration(1000-i) * 5 * time.Second), Online: true, Ms: int64(i)})
+	} // end of the loop
+	// All kept.
+	if n := len(h.all()); n != 1000 {
+		// Report it.
+		t.Errorf("kept %d checks, want 1000", n)
+	} // end of the keep check
+	// The ceiling for the largest settings is the hard one at most.
+	if _, ceil := h.limits(); ceil > hardMaxSamples || ceil < 1000 {
+		// Report it.
+		t.Errorf("ceiling %d", ceil)
+	} // end of the ceiling check
+} // end of TestHistoryCeilingFollowsTheSettings
+
+// TestChartsUseTheWindow checks that the charts speak of the chosen window and block size.
+func TestChartsUseTheWindow(t *testing.T) {
+	// Now.
+	now := time.Now()
+	// A 60-minute window has blocks of one minute.
+	v := buildChartsFor([]sample{{At: now.Add(-time.Minute), Online: true, Ms: 10}}, now, true, false, 60*time.Minute, 20*time.Second)
+	// The window text.
+	if v.WindowText != "60 minutes" || v.EverySeconds != 20 {
+		// Report it.
+		t.Errorf("window %q every %d", v.WindowText, v.EverySeconds)
+	} // end of the text check
+	// The block size in the text alternative.
+	if !strings.Contains(v.StateAlt, "blocks of 1 minute") {
+		// Report it.
+		t.Errorf("state text %q", v.StateAlt)
+	} // end of the block check
+	// The span words.
+	for in, want := range map[time.Duration]string{30 * time.Second: "30 seconds", time.Second: "1 second", time.Minute: "1 minute", 4 * time.Minute: "4 minutes", 90 * time.Second: "90 seconds"} {
+		// Compare.
+		if got := spanWords(in); got != want {
+			// Report it.
+			t.Errorf("spanWords(%v) = %q want %q", in, got, want)
+		} // end of the compare
+	} // end of the loop
+} // end of TestChartsUseTheWindow
+
+// TestResolveWithSaved checks the order: option, environment variable, saved setting, default.
+func TestResolveWithSaved(t *testing.T) {
+	// The cases.
+	cases := []struct {
+		// The three layers and the expected source.
+		flag, env, saved, want string
+	}{
+		{"", "", "", sourceDefault},
+		{"", "", "http://10.0.0.5:11434", sourceSaved},
+		{"", "http://10.0.0.6:11434", "http://10.0.0.5:11434", sourceEnv},
+		{"http://10.0.0.7:11434", "http://10.0.0.6:11434", "http://10.0.0.5:11434", sourceFlag},
+	} // end of the cases
+	// Run them.
+	for _, c := range cases {
+		// Resolve.
+		a, err := resolveWithSaved(c.flag, c.env, c.saved)
+		// It must work.
+		if err != nil || a.Source != c.want {
+			// Report it.
+			t.Errorf("%+v: source %q err %v", c, a.Source, err)
+		} // end of the check
+	} // end of the loop
+} // end of TestResolveWithSaved
+
+// TestChooseListen checks the order: option, saved choice, default.
+func TestChooseListen(t *testing.T) {
+	// The option wins.
+	if a, s := chooseListen("127.0.0.1:9", true, true); a != "127.0.0.1:9" || s != sourceFlag {
+		// Report it.
+		t.Errorf("option: %q %q", a, s)
+	} // end of the option check
+	// The saved choice opens the page.
+	if a, s := chooseListen(defaultListen, false, true); a != openListen || s != sourceSaved {
+		// Report it.
+		t.Errorf("saved: %q %q", a, s)
+	} // end of the saved check
+	// The default.
+	if a, s := chooseListen(defaultListen, false, false); a != defaultListen || s != sourceDefault {
+		// Report it.
+		t.Errorf("default: %q %q", a, s)
+	} // end of the default check
+} // end of TestChooseListen
+
+// TestLanHostGuard checks the Host rules for a page that is open to the network.
+func TestLanHostGuard(t *testing.T) {
+	// Open and closed listen addresses.
+	for listen, want := range map[string]bool{"0.0.0.0:8765": true, "192.168.1.5:8765": true, "127.0.0.1:8765": false, "localhost:8765": false, "[::1]:8765": false} {
+		// Compare.
+		if got := lanListen(listen); got != want {
+			// Report it.
+			t.Errorf("lanListen(%q) = %v", listen, got)
+		} // end of the compare
+	} // end of the loop
+	// The Host headers.
+	for host, want := range map[string]bool{"192.168.1.20:8765": true, "localhost:8765": true, "[fe80::1]:8765": true, "evil.example:8765": false, "192.168.1.20:9999": false, "evil.example": false} {
+		// Compare.
+		if got := lanHostOK(host, "8765"); got != want {
+			// Report it.
+			t.Errorf("lanHostOK(%q) = %v", host, got)
+		} // end of the compare
+	} // end of the loop
+	// This computer's own name is accepted.
+	if name, err := os.Hostname(); err == nil && name != "" && !lanHostOK(name+":8765", "8765") {
+		// Report it.
+		t.Errorf("own host name %q refused", name)
+	} // end of the name check
+} // end of TestLanHostGuard
+
+// TestSettingsLinkAndArrow checks that the main page links to the Settings page and that the Settings page has the back arrow.
+func TestSettingsLinkAndArrow(t *testing.T) {
+	// The rig.
+	r := newSettingsRig(t, runInfo{Listen: defaultListen, ListenSource: sourceDefault})
+	// The main page.
+	_, _, main := get(t, r.h, http.MethodGet, "/")
+	// The link, its tooltip and its words.
+	for _, w := range []string{`href="/settings"`, `id="tipsettings"`, "Settings</a>"} {
+		// Look for it.
+		if !strings.Contains(main, w) {
+			// Report it.
+			t.Errorf("the main page lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// The Settings page.
+	_, _, page := get(t, r.h, http.MethodGet, "/settings")
+	// The arrow, before the heading.
+	if i, j := strings.Index(page, `class="tipbox backtop"`), strings.Index(page, "<h1"); i < 0 || j < 0 || i > j {
+		// Report it.
+		t.Errorf("the Settings page has no back arrow at the top (%d, %d)", i, j)
+	} // end of the arrow check
+	// A page never caches, because it shows live values.
+	if _, h, _ := get(t, r.h, http.MethodGet, "/settings"); h.Get("Cache-Control") != "no-store" {
+		// Report it.
+		t.Errorf("Cache-Control %q", h.Get("Cache-Control"))
+	} // end of the cache check
+	// An unknown saved word shows no note.
+	if _, _, p := get(t, r.h, http.MethodGet, "/settings?saved=<script>"); strings.Contains(p, "<script>") {
+		// Report it.
+		t.Errorf("the saved word was echoed")
+	} // end of the echo check
+} // end of TestSettingsLinkAndArrow
diff --git a/charts.go b/charts.go
index 2c5a76f..a7c1c89 100644
--- a/charts.go
+++ b/charts.go
@@ -155,14 +155,38 @@ func watchedFor(d time.Duration) string {
 	return fmt.Sprintf("%d min %d s", sec/60, sec%60)
 } // end of watchedFor
 
-// buildCharts turns the checks of the last window into what the page draws.
+// buildCharts builds the charts with the built-in window and check interval (the page uses buildChartsFor with the saved settings).
 func buildCharts(samples []sample, now time.Time, background, numbersOpen bool) chartsView {
+	// The defaults.
+	return buildChartsFor(samples, now, background, numbersOpen, chartWindow, sampleEvery)
+} // end of buildCharts
+
+// spanWords writes a short duration in words: seconds under a minute, whole minutes when it divides evenly, otherwise seconds.
+func spanWords(d time.Duration) string {
+	// Whole seconds.
+	sec := int(d / time.Second)
+	// A whole number of minutes of one minute or more.
+	if sec >= 60 && sec%60 == 0 {
+		// Reuse the minutes wording.
+		return windowWords(d)
+	} // end of the minutes case
+	// One second is singular.
+	if sec == 1 {
+		// Singular.
+		return "1 second"
+	} // end of the singular case
+	// Plural seconds.
+	return fmt.Sprintf("%d seconds", sec)
+} // end of spanWords
+
+// buildChartsFor turns the checks of the last window into what the page draws; window is the history length and every is the time between two checks (both come from the settings).
+func buildChartsFor(samples []sample, now time.Time, background, numbersOpen bool, window, every time.Duration) chartsView {
 	// The start of the window.
-	start := now.Add(-chartWindow)
+	start := now.Add(-window)
 	// The basic fields.
-	v := chartsView{WindowText: windowWords(chartWindow), EverySeconds: int(sampleEvery / time.Second), Background: background, NumbersOpen: numbersOpen,
+	v := chartsView{WindowText: windowWords(window), EverySeconds: int(every / time.Second), Background: background, NumbersOpen: numbersOpen,
 		CellHeight: cellHeight, Width: chartWidth, Height: chartHeight, BaseY: chartHeight - chartPad,
-		StartLabel: start.Format(chartTimeLayout), MidLabel: start.Add(chartWindow / 2).Format(chartTimeLayout), EndLabel: now.Format(chartTimeLayout)}
+		StartLabel: start.Format(chartTimeLayout), MidLabel: start.Add(window / 2).Format(chartTimeLayout), EndLabel: now.Format(chartTimeLayout)}
 	// The width of one block, leaving a one-unit gap.
 	v.CellWidth = chartWidth/stateCells - 1
 	// Only the checks inside the window count.
@@ -191,7 +215,7 @@ func buildCharts(samples []sample, now time.Time, background, numbersOpen bool)
 	// Walk the checks.
 	for _, s := range in {
 		// The block of this check.
-		i := int(s.At.Sub(start) * stateCells / chartWindow)
+		i := int(s.At.Sub(start) * stateCells / window)
 		// The very end belongs to the last block.
 		if i >= stateCells {
 			// Clamp.
@@ -250,7 +274,7 @@ func buildCharts(samples []sample, now time.Time, background, numbersOpen bool)
 		} // end of the switch
 	} // end of the loop
 	// The text alternative of the state bar.
-	v.StateAlt = fmt.Sprintf("State of Ollama in the last %s, in %d blocks of 30 seconds: %d blocks answered, %d blocks had a failed check, %d blocks have no check yet.", v.WindowText, stateCells, okN, badN, noneN)
+	v.StateAlt = fmt.Sprintf("State of Ollama in the last %s, in %d blocks of %s: %d blocks answered, %d blocks had a failed check, %d blocks have no check yet.", v.WindowText, stateCells, spanWords(window/stateCells), okN, badN, noneN)
 	// Nothing measured yet.
 	if len(in) == 0 {
 		// Say so; the charts stay empty.
@@ -281,7 +305,7 @@ func buildCharts(samples []sample, now time.Time, background, numbersOpen bool)
 		v.Summary += " Last failure at " + lastFail.Format(chartLastFailureLayout) + "."
 	} // end of the failure check
 	// A young monitor says how long it has been watching.
-	if watched := now.Sub(in[0].At); watched < chartWindow-time.Minute {
+	if watched := now.Sub(in[0].At); watched < window-time.Minute {
 		// The note.
 		v.Summary += " Watching for " + watchedFor(watched) + " so far."
 	} // end of the young check
@@ -313,12 +337,12 @@ func buildCharts(samples []sample, now time.Time, background, numbersOpen bool)
 			continue
 		} // end of the failure check
 		// A long pause breaks the line too.
-		if !prev.IsZero() && s.At.Sub(prev) > chartGap {
+		if !prev.IsZero() && s.At.Sub(prev) > 3*every {
 			// End the line.
 			flush()
 		} // end of the pause check
 		// The position.
-		x := float64(s.At.Sub(start)) / float64(chartWindow) * chartWidth
+		x := float64(s.At.Sub(start)) / float64(window) * chartWidth
 		// Zero at the bottom, the top of the scale at the top.
 		y := float64(chartHeight-chartPad) - float64(s.Ms)/float64(top)*usable
 		// The text of the point.
@@ -357,4 +381,4 @@ func buildCharts(samples []sample, now time.Time, background, numbersOpen bool)
 	} // end of the table
 	// Hand it back.
 	return v
-} // end of buildCharts
+} // end of buildChartsFor
diff --git a/config.go b/config.go
index b73e7ca..2e13be2 100644
--- a/config.go
+++ b/config.go
@@ -24,6 +24,8 @@ const (
 	sourceEnv = "environment variable"
 	// sourceDefault means nobody set an address, so the built-in default is used.
 	sourceDefault = "default"
+	// sourceSaved means the value came from the Settings page (the settings file).
+	sourceSaved = "saved setting"
 ) // end of the source names
 
 // ollamaAddress holds the chosen address and the layer that supplied it.
@@ -36,10 +38,23 @@ type ollamaAddress struct {
 
 // resolve picks the address by precedence: option, then environment variable, then default; an empty text counts as "not set".
 func resolve(flagValue, envValue string) (ollamaAddress, error) {
+	// No saved setting.
+	return resolveWithSaved(flagValue, envValue, "")
+} // end of resolve
+
+// resolveWithSaved picks the address by precedence: option, then environment variable, then the saved setting, then default.
+func resolveWithSaved(flagValue, envValue, savedValue string) (ollamaAddress, error) {
 	// Start from the default layer.
 	raw := defaultOllamaURL
 	// Remember that the default supplied it, until a stronger layer overrides.
 	source := sourceDefault
+	// The saved setting beats the default.
+	if strings.TrimSpace(savedValue) != "" {
+		// Use the saved text.
+		raw = strings.TrimSpace(savedValue)
+		// Record the layer.
+		source = sourceSaved
+	} // end of the saved check
 	// If the environment variable has real content, it beats the default.
 	if strings.TrimSpace(envValue) != "" {
 		// Use the environment variable's text.
@@ -63,7 +78,7 @@ func resolve(flagValue, envValue string) (ollamaAddress, error) {
 	} // end of the error check
 	// Everything is fine: return the address and where it came from.
 	return ollamaAddress{URL: parsed, Source: source}, nil
-} // end of resolve
+} // end of resolveWithSaved
 
 // parseOllamaURL checks that text is an http or https address with a host, and returns it parsed.
 func parseOllamaURL(raw string) (*url.URL, error) {
diff --git a/guard.go b/guard.go
index aa99b2a..4ddb532 100644
--- a/guard.go
+++ b/guard.go
@@ -12,6 +12,8 @@ import ( // import lists the standard-library packages this file uses.
 	"net"
 	// net/http provides requests and status codes.
 	"net/http"
+	// os gives this computer's own host name.
+	"os"
 	// strings makes host names lower case before they are compared.
 	"strings"
 ) // end of imports
@@ -85,10 +87,14 @@ func allowedHosts(listen string) map[string]bool {
 func hostGuard(next http.Handler, listen string) http.Handler {
 	// Work out the allowed names once.
 	allowed := allowedHosts(listen)
+	// Whether the page is open to other machines (set on the Settings page or by -listen).
+	lan := lanListen(listen)
+	// The port other machines must use.
+	_, port, _ := net.SplitHostPort(listen)
 	// Return a handler that checks the Host header and then calls the wrapped one.
 	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
 		// Host names are not case sensitive, so compare in lower case.
-		if !allowed[strings.ToLower(r.Host)] {
+		if !allowed[strings.ToLower(r.Host)] && !(lan && lanHostOK(r.Host, port)) {
 			// Never cache a refusal.
 			w.Header().Set("Cache-Control", "no-store")
 			// Refuse with a plain message.
@@ -100,3 +106,60 @@ func hostGuard(next http.Handler, listen string) http.Handler {
 		next.ServeHTTP(w, r)
 	}) // end of the wrapper
 } // end of hostGuard
+
+// lanListen says whether the listen address is open to other machines: any host part other than this computer's own loopback names.
+func lanListen(listen string) bool {
+	// Split it into host and port.
+	host, _, err := net.SplitHostPort(listen)
+	// An unusable address is treated as closed.
+	if err != nil {
+		// Closed.
+		return false
+	} // end of the split check
+	// The loopback names keep the page on this computer.
+	switch strings.ToLower(host) {
+	// This computer only.
+	case "127.0.0.1", "localhost", "::1":
+		// Closed.
+		return false
+	} // end of the loopback check
+	// Anything else (0.0.0.0, a network address, a name) is open to the network.
+	return true
+} // end of lanListen
+
+// lanHostOK accepts a Host header for a page that is open to the network: the right port, and a network address, "localhost" or this computer's own host name; any other name is refused, which keeps DNS rebinding out.
+func lanHostOK(hostport, port string) bool {
+	// Split the header into name and port.
+	host, p, err := net.SplitHostPort(hostport)
+	// A header without a port is only right when the port is the default web port.
+	if err != nil {
+		// The whole header is the name.
+		host, p = hostport, "80"
+	} // end of the split check
+	// The port must be ours.
+	if p != port {
+		// Refuse.
+		return false
+	} // end of the port check
+	// Brackets around an IPv6 address are not part of it.
+	host = strings.ToLower(strings.Trim(host, "[]"))
+	// A network address in numbers is fine.
+	if net.ParseIP(host) != nil {
+		// Accept.
+		return true
+	} // end of the address check
+	// The browser's own name for this computer.
+	if host == "localhost" {
+		// Accept.
+		return true
+	} // end of the localhost check
+	// This computer's own host name, with or without the .local ending that home networks add.
+	if name, err := os.Hostname(); err == nil && name != "" {
+		// Compare in lower case.
+		name = strings.ToLower(name)
+		// Either form.
+		return host == name || host == name+".local"
+	} // end of the host name check
+	// Anything else is refused.
+	return false
+} // end of lanHostOK
diff --git a/main.go b/main.go
index 2266789..75a5a19 100644
--- a/main.go
+++ b/main.go
@@ -23,6 +23,41 @@ import ( // import lists the standard-library packages this file uses.
 // defaultListen is where the page is served unless the user chooses otherwise: this machine only (requirement S1).
 const defaultListen = "127.0.0.1:8765"
 
+// openListen is the address used when the person allowed other machines: every network address of this computer, same port as the default.
+const openListen = "0.0.0.0:8765"
+
+// listenGiven says whether -listen was written on the command line (flag.Visit only walks the options that were set).
+func listenGiven() bool {
+	// Not given until seen.
+	given := false
+	// Walk the options that were set.
+	flag.Visit(func(f *flag.Flag) {
+		// The one we look for.
+		if f.Name == "listen" {
+			// Seen.
+			given = true
+		} // end of the name check
+	}) // end of the walk
+	// The answer.
+	return given
+} // end of listenGiven
+
+// chooseListen picks the listen address by precedence: the -listen option (when given), then "other machines allowed" from the settings, then this computer only; the second value names the layer.
+func chooseListen(flagValue string, flagGiven, allowOthers bool) (string, string) {
+	// The command line wins.
+	if flagGiven {
+		// Use it.
+		return flagValue, sourceFlag
+	} // end of the option case
+	// The saved setting opens the page to the network.
+	if allowOthers {
+		// Use the open address.
+		return openListen, sourceSaved
+	} // end of the saved case
+	// Otherwise this computer only.
+	return defaultListen, sourceDefault
+} // end of chooseListen
+
 // formatCheck turns one check result into the single status line the -check option prints.
 func formatCheck(res checkResult) string {
 	// A successful check says ONLINE, the version and the time taken.
@@ -100,7 +135,17 @@ func main() {
 	} // end of the links mode
 
 	// Choose the Ollama address by precedence: option, then environment variable, then default.
-	addr, err := resolve(*ollamaFlag, os.Getenv(envOllamaURL))
+	// The saved settings are read first (a damaged file is ignored with a note).
+	dir, dirNote := settingsFolder()
+	// Open the store.
+	store := openSettingsStore(dir, dirNote)
+	// Tell the person when the file was ignored.
+	if n := store.noteText(); n != "" {
+		// Print the note.
+		log.Print(n)
+	} // end of the note check
+	// The address: option, then environment variable, then saved setting, then default.
+	addr, err := resolveWithSaved(*ollamaFlag, os.Getenv(envOllamaURL), store.get().OllamaURL)
 	// If the address is unusable, stop with a clear message and a failure exit code.
 	if err != nil {
 		// log.Fatalf prints the message and exits with code 1.
@@ -133,14 +178,18 @@ func main() {
 	// Describe the web server: Addr is where to listen (the star reads the flag's value), Handler is the web interface from web.go wrapped in the Host-name check from guard.go,
 	// and ReadHeaderTimeout drops clients that take more than 5 seconds to send their request headers.
 	// The monitor holds the counters and the history of checks; it asks Ollama in the background every sampleEvery, so the charts have no gaps while the page is closed.
-	mon := newMonitor()
+	mon := newMonitorWith(store)
+	// The listen address: the -listen option if it was given, else "other machines allowed" from the settings, else this computer only.
+	listenAddr, listenSource := chooseListen(*listen, listenGiven(), store.get().AllowOthers)
+	// Tell the Settings page how the program was started.
+	mon.run = runInfo{Listen: listenAddr, ListenSource: listenSource}
 	// Start the background checks; they end with the program.
 	mon.start(context.Background(), addr.URL, defaultCheckTimeout, sampleEvery)
 	// The server, with the monitor built into the web interface.
-	server := &http.Server{Addr: *listen, Handler: hostGuard(newWebHandlerWith(addr, defaultCheckTimeout, mon), *listen), ReadHeaderTimeout: 5 * time.Second}
+	server := &http.Server{Addr: listenAddr, Handler: hostGuard(newWebHandlerWith(addr, defaultCheckTimeout, mon), listenAddr), ReadHeaderTimeout: 5 * time.Second}
 
 	// Tell the person which address we are about to serve on.
-	log.Printf("OllamaControlCenter listening on http://%s (press Ctrl+C to stop)", *listen)
+	log.Printf("OllamaControlCenter listening on http://%s (from %s; press Ctrl+C to stop)", listenAddr, listenSource)
 	// Closed when the shutdown that the Stop button started has finished.
 	stopped := make(chan struct{})
 	// The Stop button's last step: shut the web server down, waiting at most 5 seconds for requests that are still running.
@@ -151,6 +200,11 @@ func main() {
 			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
 			// Release the timer at the end.
 			defer cancel()
+			// With the history file switched on, write the checks one last time, so a stop loses nothing.
+			if store.get().SaveHistory {
+				// A failed write is not fatal.
+				_ = store.saveSamples(mon.hist.all())
+			} // end of the history write
 			// Ask politely first.
 			if err := server.Shutdown(ctx); err != nil {
 				// Requests that would not finish are cut off.
diff --git a/monitor.go b/monitor.go
index 598b088..5e0cf34 100644
--- a/monitor.go
+++ b/monitor.go
@@ -39,8 +39,67 @@ type sampleHistory struct {
 	mu sync.Mutex
 	// items are the checks, oldest first.
 	items []sample
+	// window is how long checks are kept; zero means the built-in chartWindow.
+	window time.Duration
+	// every is the time between checks; zero means the built-in sampleEvery. It sizes the ceiling.
+	every time.Duration
 } // end of sampleHistory
 
+// hardMaxSamples is the largest number of checks ever kept, whatever the settings (240 minutes at 5 seconds is 2880).
+const hardMaxSamples = 6000
+
+// setLimits tells the history how long to keep checks and how often they come (both from the settings).
+func (h *sampleHistory) setLimits(window, every time.Duration) {
+	// One at a time.
+	h.mu.Lock()
+	// Release at the end.
+	defer h.mu.Unlock()
+	// Keep them.
+	h.window, h.every = window, every
+} // end of setLimits
+
+// limits returns the window and the ceiling in use; the caller holds the lock.
+func (h *sampleHistory) limits() (time.Duration, int) {
+	// The window, or the built-in one.
+	w := h.window
+	// Zero means not set.
+	if w <= 0 {
+		// The built-in window.
+		w = chartWindow
+	} // end of the window default
+	// The interval, or the built-in one.
+	e := h.every
+	// Zero means not set.
+	if e <= 0 {
+		// The built-in interval.
+		e = sampleEvery
+	} // end of the interval default
+	// The checks that fit the window, plus a minute of slack; never fewer than the original ceiling.
+	n := int(w/e) + 60
+	// The original ceiling is the floor.
+	if n < maxSamples {
+		// Use it.
+		n = maxSamples
+	} // end of the floor
+	// The hard ceiling.
+	if n > hardMaxSamples {
+		// Use it.
+		n = hardMaxSamples
+	} // end of the hard ceiling
+	// Hand back both.
+	return w, n
+} // end of limits
+
+// all returns a copy of every kept check, oldest first.
+func (h *sampleHistory) all() []sample {
+	// One at a time.
+	h.mu.Lock()
+	// Release at the end.
+	defer h.mu.Unlock()
+	// A copy, so the caller cannot change the list.
+	return append([]sample(nil), h.items...)
+} // end of all
+
 // add keeps one more check and forgets the ones that are too old or beyond the ceiling.
 func (h *sampleHistory) add(s sample) {
 	// One writer at a time.
@@ -50,7 +109,9 @@ func (h *sampleHistory) add(s sample) {
 	// Add the new check at the end.
 	h.items = append(h.items, s)
 	// Anything older than the window plus a minute of slack is no longer shown, so it goes.
-	cut := s.At.Add(-(chartWindow + time.Minute))
+	w, ceiling := h.limits()
+	// Checks older than the window plus a minute are dropped.
+	cut := s.At.Add(-(w + time.Minute))
 	// Count the old ones at the front.
 	drop := 0
 	// The list is oldest first, so stop at the first one that is recent enough.
@@ -59,7 +120,7 @@ func (h *sampleHistory) add(s sample) {
 		drop++
 	} // end of the loop
 	// The ceiling: drop the oldest when there are too many.
-	if over := len(h.items) - drop - maxSamples; over > 0 {
+	if over := len(h.items) - drop - ceiling; over > 0 {
 		// Drop those too.
 		drop += over
 	} // end of the ceiling check
@@ -98,20 +159,60 @@ type monitor struct {
 	hist *sampleHistory
 	// background is true while a background check runs; the page then does not count its own checks.
 	background atomic.Bool
+	// store holds the saved settings (interval, timeout, history length, history file).
+	store *settingsStore
+	// run says how the program was started (listen address and where it came from); main sets it once before serving.
+	run runInfo
+	// unsaved counts the checks since the history file was last written.
+	unsaved atomic.Int32
 } // end of monitor
 
+// runInfo holds facts about the running program that the Settings page shows next to the saved values.
+type runInfo struct {
+	// Listen is the address the page is served on, as host:port.
+	Listen string
+	// ListenSource says which layer chose it: the command-line option, the saved setting or the default.
+	ListenSource string
+} // end of runInfo
+
+// saveHistoryEvery is how many checks pass between two writes of the history file (12 checks of 10 seconds are 2 minutes).
+const saveHistoryEvery = 12
+
 // newMonitor builds an empty monitor.
 func newMonitor() *monitor {
 	// Empty counters and an empty history.
-	return &monitor{health: &apiHealth{}, hist: &sampleHistory{}}
+	return newMonitorWith(openSettingsStore("", ""))
 } // end of newMonitor
 
+// newMonitorWith builds a monitor that reads its settings from the given store.
+func newMonitorWith(store *settingsStore) *monitor {
+	// Empty counters and an empty history, and the settings.
+	return &monitor{health: &apiHealth{}, hist: &sampleHistory{}, store: store}
+} // end of newMonitorWith
+
+// timeoutOr is how long one status check waits: the saved value, or def.
+func (m *monitor) timeoutOr(def time.Duration) time.Duration {
+	// Ask the settings.
+	return m.store.get().timeout(def)
+} // end of timeoutOr
+
 // record counts one check in the counters and in the history.
 func (m *monitor) record(res checkResult, now time.Time) {
 	// The counters of the API health box.
 	m.health.record(res.Online, now)
+	// The settings in force now.
+	cfg := m.store.get()
+	// The history keeps as long as the settings say.
+	m.hist.setLimits(cfg.window(), cfg.interval(sampleEvery))
 	// The history for the charts.
 	m.hist.add(sample{At: now, Online: res.Online, Ms: res.Elapsed.Milliseconds()})
+	// When the person asked for the history file, write it every few checks.
+	if cfg.SaveHistory && m.unsaved.Add(1) >= saveHistoryEvery {
+		// Start counting again.
+		m.unsaved.Store(0)
+		// A failed write is not fatal: the history stays in memory.
+		_ = m.store.saveSamples(m.hist.all())
+	} // end of the save check
 } // end of record
 
 // pageCheck is called by the page for its own check: it counts the check only when no background check runs, and returns the counters.
@@ -131,26 +232,32 @@ func (m *monitor) pageCheck(res checkResult, now time.Time) healthView {
 func (m *monitor) start(ctx context.Context, base *url.URL, timeout, every time.Duration) {
 	// From now on the page does not count its own checks.
 	m.background.Store(true)
+	// With the history file switched on, take back the checks of before the restart.
+	if cfg := m.store.get(); cfg.SaveHistory {
+		// Apply the limits first, so old checks are pruned correctly.
+		m.hist.setLimits(cfg.window(), cfg.interval(every))
+		// Add what the file holds.
+		for _, it := range m.store.loadSamples(cfg.window(), time.Now()) {
+			// One at a time, oldest first.
+			m.hist.add(it)
+		} // end of the loop
+	} // end of the history restore
 	// The loop runs on its own.
 	go func() {
-		// One check straight away, so the charts start at once.
-		m.record(checkOllama(ctx, base, timeout), time.Now())
-		// The clock for the next ones.
-		tick := time.NewTicker(every)
-		// Stop the clock at the end.
-		defer tick.Stop()
-		// Wait for each tick or the end.
+		// One check right away, with the timeout in force now.
+		m.record(checkOllama(ctx, base, m.timeoutOr(timeout)), time.Now())
+		// Then wait, check, wait, check; the interval is read again every round, so a saved change applies at once.
 		for {
-			// Which came first.
+			// Wait for the interval, or for the end of the program.
 			select {
-			// The program is ending.
+			// The program ends.
 			case <-ctx.Done():
 				// Leave the loop.
 				return
-			// Time for the next check.
-			case <-tick.C:
-				// Check and remember.
-				m.record(checkOllama(ctx, base, timeout), time.Now())
+			// The interval has passed.
+			case <-time.After(m.store.get().interval(every)):
+				// Check, with the timeout in force now.
+				m.record(checkOllama(ctx, base, m.timeoutOr(timeout)), time.Now())
 			} // end of the select
 		} // end of the loop
 	}() // end of the goroutine
diff --git a/monitor_test.go b/monitor_test.go
index b6815ab..1b7b899 100644
--- a/monitor_test.go
+++ b/monitor_test.go
@@ -131,7 +131,7 @@ func TestMainPageShowsTheCharts(t *testing.T) {
 	// The default page.
 	page := pageWithCookie(t, rig, nil)
 	// The parts.
-	for _, w := range []string{`aria-labelledby="charts-title"`, ">Charts</span>", "Ollama&#39;s answers over the last 30 minutes", "State of Ollama", "Answer time", "Ollama answered 100 % of", `<svg class="chartsvg"`, `id="hatch"`, `class="cell cell-ok"`, "each time this page loads", `href="/?numbers=open#numbers"`, `<meta http-equiv="refresh"`} {
+	for _, w := range []string{`aria-labelledby="charts-title"`, ">Charts</span>", "Ollama&#39;s answers over the chart history", "State of Ollama", "Answer time", "Ollama answered 100 % of", `<svg class="chartsvg"`, `id="hatch"`, `class="cell cell-ok"`, "each time this page loads", `href="/?numbers=open#numbers"`, `<meta http-equiv="refresh"`} {
 		// Look for it.
 		if !strings.Contains(page, w) {
 			// Report the gap.
diff --git a/settingspage.go b/settingspage.go
new file mode 100644
index 0000000..e77eb8f
--- /dev/null
+++ b/settingspage.go
@@ -0,0 +1,383 @@
+// Package main tells Go that this folder builds into a runnable program, not a library.
+package main
+
+import ( // import lists the packages this file uses.
+	// bytes builds the page in memory before it is sent.
+	"bytes"
+	// embed lets the page template travel inside the program.
+	_ "embed"
+	// fmt writes numbers into the texts.
+	"fmt"
+	// html/template builds the page and escapes every value.
+	"html/template"
+	// log reports a template error in the terminal.
+	"log"
+	// net/http provides requests and responses.
+	"net/http"
+	// path/filepath shows the folder of the files.
+	"path/filepath"
+	// strconv turns the typed text into whole numbers.
+	"strconv"
+	// strings trims the typed text.
+	"strings"
+) // end of imports
+
+// settingsTemplateText is the page template, embedded from web/settings.html.
+//
+//go:embed web/settings.html
+var settingsTemplateText string
+
+// settingsRow is one line of the settings table.
+type settingsRow struct {
+	// Label is the name of the setting.
+	Label string
+	// Help is one short sentence that explains it, with an example.
+	Help string
+	// Name is the name of the form field.
+	Name string
+	// Kind is the control: text, number or yesno.
+	Kind string
+	// Now is the value in use now.
+	Now string
+	// From says which layer supplied it (default, saved setting, command-line option, environment variable).
+	From string
+	// Pending says that a saved value waits for a restart (empty when nothing waits).
+	Pending string
+	// Typed is what the control holds.
+	Typed string
+	// Default is the built-in value.
+	Default string
+	// Applies says when a change takes effect: at once or after a restart.
+	Applies string
+	// Min and Max are the limits of a number.
+	Min, Max int
+} // end of settingsRow
+
+// settingsPage is everything the template shows.
+type settingsPage struct {
+	// Theme and Size are the saved look choices.
+	Theme, Size string
+	// Token proves the form comes from this page.
+	Token string
+	// Rows are the table lines.
+	Rows []settingsRow
+	// Problems are the things wrong with what was typed.
+	Problems []string
+	// Saved is "saved", "reset" or empty, for the note after saving.
+	Saved string
+	// RestartNeeded is true when a restart value differs from what runs now.
+	RestartNeeded bool
+	// Note is the plain note about the file.
+	Note string
+	// Folder is the folder of the files (empty when none was found).
+	Folder string
+} // end of settingsPage
+
+// yesNo writes a flag as the words used in the form.
+func yesNo(on bool) string {
+	// Yes.
+	if on {
+		// The word.
+		return "yes"
+	} // end of the yes case
+	// No.
+	return "no"
+} // end of yesNo
+
+// numberOrZero reads a typed whole number; empty text means 0 (not set), anything else that is not a whole number is reported.
+func numberOrZero(text string) (int, bool) {
+	// Empty means not set.
+	text = strings.TrimSpace(text)
+	// Nothing typed.
+	if text == "" {
+		// Not set.
+		return 0, true
+	} // end of the empty case
+	// Read it.
+	n, err := strconv.Atoi(text)
+	// Not a whole number.
+	if err != nil {
+		// Report it.
+		return 0, false
+	} // end of the parse check
+	// A number.
+	return n, true
+} // end of numberOrZero
+
+// settingsFormValues are the typed texts, kept so a refused form shows again what the person typed.
+type settingsFormValues struct {
+	// Address, Interval, Timeout and History are the typed texts.
+	Address, Interval, Timeout, History string
+	// Others and SaveHistory are "yes" or "no".
+	Others, SaveHistory string
+} // end of settingsFormValues
+
+// formFromSettings fills the typed values from saved settings (a default value shows as empty or as the default number).
+func formFromSettings(cfg appSettings) settingsFormValues {
+	// The numbers show the value in use, so the person sees what a change starts from.
+	return settingsFormValues{
+		// The address shows only when one was saved.
+		Address: cfg.OllamaURL,
+		// The interval in use.
+		Interval: strconv.Itoa(int(cfg.interval(sampleEvery).Seconds())),
+		// The timeout in use.
+		Timeout: strconv.Itoa(int(cfg.timeout(defaultCheckTimeout).Seconds())),
+		// The history in use.
+		History: strconv.Itoa(int(cfg.window().Minutes())),
+		// The two switches.
+		Others: yesNo(cfg.AllowOthers), SaveHistory: yesNo(cfg.SaveHistory),
+	} // end of the values
+} // end of formFromSettings
+
+// fromLayer names the layer of a numeric setting: the saved setting when one is saved, else the default.
+func fromLayer(saved bool) string {
+	// Saved.
+	if saved {
+		// The name.
+		return sourceSaved
+	} // end of the saved case
+	// Default.
+	return sourceDefault
+} // end of fromLayer
+
+// buildSettingsRows makes the table lines from the saved settings, how the program runs now and what the form holds.
+func buildSettingsRows(cfg appSettings, addr ollamaAddress, run runInfo, typed settingsFormValues) ([]settingsRow, bool) {
+	// Whether any restart value waits.
+	restart := false
+	// The address row: what runs now, and a note when the saved value differs.
+	pendAddr := ""
+	// A saved address that is not the one in use, and no stronger layer overrides it, waits for a restart.
+	if cfg.OllamaURL != "" && addr.Source != sourceFlag && addr.Source != sourceEnv && (addr.Source != sourceSaved || cfg.OllamaURL != addr.URL.String()) {
+		// Say so.
+		pendAddr = "saved: " + cfg.OllamaURL + " (used after a restart)"
+		// A restart is needed.
+		restart = true
+	} // end of the pending address
+	// A saved address that a stronger layer overrides is not used at all.
+	if cfg.OllamaURL != "" && (addr.Source == sourceFlag || addr.Source == sourceEnv) {
+		// Say so.
+		pendAddr = "the " + addr.Source + " overrides the saved address"
+	} // end of the overridden address
+	// An address cleared on the page while a saved one runs also needs a restart.
+	if cfg.OllamaURL == "" && addr.Source == sourceSaved {
+		// Say so.
+		pendAddr = "saved: (default) (used after a restart)"
+		// A restart is needed.
+		restart = true
+	} // end of the cleared address
+	// Whether the page is open to the network now.
+	openNow := lanListen(run.Listen)
+	// The network row's pending note.
+	pendNet := ""
+	// The saved choice differs from what runs, and the -listen option does not decide.
+	if run.ListenSource != sourceFlag && cfg.AllowOthers != openNow {
+		// Say so.
+		pendNet = "saved: " + map[bool]string{true: "Yes", false: "No"}[cfg.AllowOthers] + " (used after a restart)"
+		// A restart is needed.
+		restart = true
+	} // end of the pending network
+	// The -listen option overrides the saved choice.
+	if run.ListenSource == sourceFlag && cfg.AllowOthers {
+		// Say so.
+		pendNet = "the command-line option -listen overrides this"
+	} // end of the overridden network
+	// The words for the network row.
+	netNow := "No (this computer only)"
+	// Open now.
+	if openNow {
+		// The words.
+		netNow = "Yes (" + run.Listen + ")"
+	} // end of the network words
+	// The history file row's words.
+	histNow := "No"
+	// On.
+	if cfg.SaveHistory {
+		// The words.
+		histNow = "Yes"
+	} // end of the history words
+	// The seven lines.
+	rows := []settingsRow{
+		{Label: "Ollama address", Help: "Where Ollama listens, for example http://192.168.1.20:11434.", Name: "ollama_url", Kind: "text", Now: addr.URL.Redacted(), From: addr.Source, Pending: pendAddr, Typed: typed.Address, Default: defaultOllamaURL, Applies: "restart"},
+		{Label: "Check interval (seconds)", Help: "How often the monitor asks Ollama in the background, for example 10.", Name: "interval", Kind: "number", Now: strconv.Itoa(int(cfg.interval(sampleEvery).Seconds())), From: fromLayer(cfg.IntervalSeconds > 0), Typed: typed.Interval, Default: strconv.Itoa(int(sampleEvery.Seconds())), Applies: "at once", Min: minIntervalSeconds, Max: maxIntervalSeconds},
+		{Label: "Check timeout (seconds)", Help: "How long one status check waits for Ollama before it counts as failed, for example 5.", Name: "timeout", Kind: "number", Now: strconv.Itoa(int(cfg.timeout(defaultCheckTimeout).Seconds())), From: fromLayer(cfg.TimeoutSeconds > 0), Typed: typed.Timeout, Default: strconv.Itoa(int(defaultCheckTimeout.Seconds())), Applies: "at once", Min: minTimeoutSeconds, Max: maxTimeoutSeconds},
+		{Label: "Chart history (minutes)", Help: "How far back the charts look, for example 30.", Name: "history", Kind: "number", Now: strconv.Itoa(int(cfg.window().Minutes())), From: fromLayer(cfg.HistoryMinutes > 0), Typed: typed.History, Default: strconv.Itoa(int(chartWindow.Minutes())), Applies: "at once", Min: minHistoryMinutes, Max: maxHistoryMinutes},
+		{Label: "Let other machines open this page", Help: "Yes lets a browser on another computer open it; No keeps it on this computer.", Name: "others", Kind: "yesno", Now: netNow, From: run.ListenSource, Pending: pendNet, Typed: typed.Others, Default: "No", Applies: "restart"},
+		{Label: "Save check history to a file", Help: "Yes keeps the charts after a restart; No keeps them in memory only.", Name: "savehistory", Kind: "yesno", Now: histNow, From: fromLayer(cfg.SaveHistory), Typed: typed.SaveHistory, Default: "No", Applies: "at once"},
+	} // end of the rows
+	// Hand back the lines and whether a restart is waiting.
+	return rows, restart
+} // end of buildSettingsRows
+
+// settingsHandlers returns the page (GET) and the save (POST) handlers.
+func settingsHandlers(addr ollamaAddress, mon *monitor, token string) (http.HandlerFunc, http.HandlerFunc) {
+	// Parse the template once.
+	page := template.Must(template.New("settings").Parse(settingsTemplateText))
+	// The folder shown to the person.
+	folder := ""
+	// Only when a folder is in use.
+	if mon.store.dir != "" {
+		// Show it as a clean path.
+		folder = filepath.Clean(mon.store.dir)
+	} // end of the folder check
+	// render draws the page for the given typed values and problems.
+	render := func(w http.ResponseWriter, r *http.Request, typed settingsFormValues, problems []string, saved string, status int) {
+		// The saved settings.
+		cfg := mon.store.get()
+		// The lines and the restart flag.
+		rows, restart := buildSettingsRows(cfg, addr, mon.run, typed)
+		// Everything the template needs.
+		data := settingsPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Rows: rows, Problems: problems, Saved: saved, RestartNeeded: restart, Note: mon.store.noteText(), Folder: folder}
+		// Build the page in memory first, so a template error gives a clean 500.
+		var buf bytes.Buffer
+		// Fill the template.
+		if err := page.Execute(&buf, data); err != nil {
+			// Log the cause in the terminal.
+			log.Printf("settings page: %v", err)
+			// Tell the browser plainly.
+			http.Error(w, "internal error", http.StatusInternalServerError)
+			// Stop here.
+			return
+		} // end of the error check
+		// The page is HTML in UTF-8.
+		w.Header().Set("Content-Type", "text/html; charset=utf-8")
+		// The page shows live values, so it is never cached.
+		w.Header().Set("Cache-Control", "no-store")
+		// The status (200, or 422 when a form was refused).
+		w.WriteHeader(status)
+		// Send it.
+		w.Write(buf.Bytes())
+	} // end of render
+	// show answers a plain visit.
+	show := func(w http.ResponseWriter, r *http.Request) {
+		// The note after a save comes in the address.
+		saved := r.URL.Query().Get("saved")
+		// Only the two known words are shown.
+		if saved != "saved" && saved != "reset" {
+			// Nothing.
+			saved = ""
+		} // end of the word check
+		// Draw it with the saved values.
+		render(w, r, formFromSettings(mon.store.get()), nil, saved, http.StatusOK)
+	} // end of show
+	// save answers the form.
+	save := func(w http.ResponseWriter, r *http.Request) {
+		// A form is small.
+		r.Body = http.MaxBytesReader(w, r.Body, 4096)
+		// It must come from this page.
+		if !sameOrigin(r) {
+			// Refuse.
+			http.Error(w, "request did not come from this page", http.StatusForbidden)
+			// Stop here.
+			return
+		} // end of the origin check
+		// Read the form.
+		if err := r.ParseForm(); err != nil {
+			// Refuse.
+			http.Error(w, "bad form", http.StatusBadRequest)
+			// Stop here.
+			return
+		} // end of the form check
+		// The token must match.
+		if !tokenValid(token, r.PostFormValue("token")) {
+			// Refuse.
+			http.Error(w, "bad token", http.StatusForbidden)
+			// Stop here.
+			return
+		} // end of the token check
+		// Back to the defaults: save nothing at all.
+		if r.PostFormValue("action") == "defaults" {
+			// An empty settings value removes the file.
+			if err := mon.store.put(appSettings{}); err != nil {
+				// Show the problem.
+				render(w, r, formFromSettings(mon.store.get()), []string{"The settings could not be saved: " + err.Error()}, "", http.StatusInternalServerError)
+				// Stop here.
+				return
+			} // end of the save check
+			// Show the page again with the note.
+			http.Redirect(w, r, "/settings?saved=reset", http.StatusSeeOther)
+			// Stop here.
+			return
+		} // end of the defaults case
+		// What the person typed.
+		typed := settingsFormValues{
+			// The address.
+			Address: strings.TrimSpace(r.PostFormValue("ollama_url")),
+			// The numbers.
+			Interval: strings.TrimSpace(r.PostFormValue("interval")), Timeout: strings.TrimSpace(r.PostFormValue("timeout")), History: strings.TrimSpace(r.PostFormValue("history")),
+			// The switches; anything but yes is no.
+			Others: yesNo(r.PostFormValue("others") == "yes"), SaveHistory: yesNo(r.PostFormValue("savehistory") == "yes"),
+		} // end of the typed values
+		// The new settings; a value equal to the default is stored as "not set".
+		var next appSettings
+		// The problems of the typed texts.
+		var problems []string
+		// The address; the default address means not set.
+		if typed.Address != defaultOllamaURL {
+			// Keep it.
+			next.OllamaURL = typed.Address
+		} // end of the address
+		// The three numbers, each with its own name for the message.
+		for _, f := range []struct {
+			// The text, the destination, the default and the name.
+			text string
+			dst  *int
+			def  int
+			name string
+		}{
+			{typed.Interval, &next.IntervalSeconds, int(sampleEvery.Seconds()), "Check interval"},
+			{typed.Timeout, &next.TimeoutSeconds, int(defaultCheckTimeout.Seconds()), "Check timeout"},
+			{typed.History, &next.HistoryMinutes, int(chartWindow.Minutes()), "Chart history"},
+		} {
+			// Read the number.
+			n, ok := numberOrZero(f.text)
+			// Not a whole number.
+			if !ok {
+				// Say so.
+				problems = append(problems, fmt.Sprintf("%s: use a whole number.", f.name))
+				// Next one.
+				continue
+			} // end of the number check
+			// A value equal to the default is stored as not set; the limits are checked below.
+			if n != f.def {
+				// Keep it.
+				*f.dst = n
+			} // end of the default check
+		} // end of the loop
+		// The two switches.
+		next.AllowOthers = typed.Others == "yes"
+		// The history file.
+		next.SaveHistory = typed.SaveHistory == "yes"
+		// Add the limit problems.
+		problems = append(problems, next.problems()...)
+		// Something is wrong: save nothing and show the form again as typed.
+		if len(problems) > 0 {
+			// Refused.
+			render(w, r, typed, problems, "", http.StatusUnprocessableEntity)
+			// Stop here.
+			return
+		} // end of the problem check
+		// The timeout against the interval must be checked with the values in use, because one of them may be at its default.
+		if next.timeout(defaultCheckTimeout) >= next.interval(sampleEvery) {
+			// Refused.
+			render(w, r, typed, []string{"Check timeout: it must be shorter than the check interval."}, "", http.StatusUnprocessableEntity)
+			// Stop here.
+			return
+		} // end of the overlap check
+		// Save.
+		if err := mon.store.put(next); err != nil {
+			// The file could not be written; nothing changed.
+			render(w, r, typed, []string{"The settings could not be saved: " + err.Error()}, "", http.StatusInternalServerError)
+			// Stop here.
+			return
+		} // end of the save check
+		// Turning the history file on writes it soon; write what is in memory now so it is not empty.
+		if next.SaveHistory {
+			// A failed write is not fatal.
+			_ = mon.store.saveSamples(mon.hist.all())
+		} // end of the history write
+		// Show the page again with the note.
+		http.Redirect(w, r, "/settings?saved=saved", http.StatusSeeOther)
+	} // end of save
+	// Hand back both.
+	return show, save
+} // end of settingsHandlers
diff --git a/tooltips.go b/tooltips.go
index 3cd85ad..17a0153 100644
--- a/tooltips.go
+++ b/tooltips.go
@@ -43,7 +43,7 @@ var helpTexts = map[string]tooltip{
 	// The charts under the event log.
 	"Charts": {
 		// What it means.
-		Plain: "Ollama's answers over the last 30 minutes, and the memory of loaded models: how often it answered, how fast.",
+		Plain: "Ollama's answers over the chart history (see Settings), and the memory of loaded models: how often it answered, how fast.",
 		// A real case.
 		Example: "A hatched block in the state bar means a check failed in that half minute.",
 		// What it helps with.
diff --git a/web.go b/web.go
index c17d9e0..563d703 100644
--- a/web.go
+++ b/web.go
@@ -146,6 +146,12 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	mux.HandleFunc("POST /textsize", sizeHandler(token))
 	// Route: a GET request for "/about" shows the read-only About page (see about.go).
 	mux.HandleFunc("GET /about", aboutHandler())
+	// Make the two Settings handlers: the first shows the page, the second saves the form (see settingspage.go).
+	settingsShow, settingsSave := settingsHandlers(addr, mon, token)
+	// Route: a GET request for "/settings" shows the Settings page.
+	mux.HandleFunc("GET /settings", settingsShow)
+	// Route: a POST request for "/settings" saves the settings.
+	mux.HandleFunc("POST /settings", settingsSave)
 	// Make the two unload handlers: the first asks "are you sure?", the second unloads (the checks are in unload.go).
 	unloadAsk, unloadConfirm := unloadHandlers(addr, token)
 	// Route: a POST request for "/unload" shows the warning page and changes nothing.
@@ -254,6 +260,9 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	// Route: a GET request for exactly "/" shows the page; other paths get 404 and other methods get 405 from the router.
 	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
 		// Ask Ollama once; the request's own context cancels the check if the browser goes away.
+		// The check timeout from the Settings page, or the built-in one.
+		timeout := mon.timeoutOr(timeout)
+		// Ask Ollama.
 		res := checkOllama(r.Context(), addr.URL, timeout)
 		// Fill in what the template shows.
 		data := pageData{
@@ -336,7 +345,11 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 		// The charts of the last 30 minutes, and the bubble of their heading.
 		now := time.Now()
 		// Build them from the history of checks.
-		data.Charts = buildCharts(mon.hist.since(now.Add(-chartWindow)), now, mon.background.Load(), data.NumbersOpen)
+		cfg := mon.store.get()
+		// The history length and the check interval from the settings.
+		window, every := cfg.window(), cfg.interval(sampleEvery)
+		// Build the charts for them.
+		data.Charts = buildChartsFor(mon.hist.since(now.Add(-window)), now, mon.background.Load(), data.NumbersOpen, window, every)
 		// The bubble.
 		data.ChartsTip = chartsTip
 		// The loaded models with their memory, from the same lists the event log used.
diff --git a/web/app.css b/web/app.css
index 8e96a8c..b769b61 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2284,3 +2284,40 @@ html[data-size="medium"] svg[width="22"] {
   /* Never wider than the normal bubble. */
   max-width: min(26rem, 92vw);
 } /* end of rule */
+
+/* The About facts table on a narrow window: a narrower label column and long values (addresses, revisions) may break anywhere, so the table stays inside its card. */
+@media (max-width: 40rem) {
+  /* The labels take less room. */
+  .aboutfacts th {
+    /* A narrower fixed column. */
+    width: 6.5rem;
+  } /* end of rule */
+  /* Long values wrap instead of running past the card. */
+  .aboutfacts td {
+    /* Break a long word anywhere if needed. */
+    overflow-wrap: anywhere;
+  } /* end of rule */
+} /* end of media rule */
+
+/* The names of the Settings cells: hidden while the column headings are visible, shown when the table stacks on a narrow window. */
+.cellname {
+  /* Hidden on a wide window. */
+  display: none;
+  /* Quiet and semi-bold. */
+  color: var(--muted);
+  font-weight: 600;
+} /* end of rule */
+
+/* On a narrow window the cells stack, so each carries its own name; long paths and addresses wrap inside the box. */
+@media (max-width: 40rem) {
+  /* Show the names. */
+  .cellname {
+    /* Inline with the value. */
+    display: inline;
+  } /* end of rule */
+  /* Long words (folder paths, addresses) break instead of widening the page. */
+  .panel code, .settingtable td {
+    /* Break anywhere if needed. */
+    overflow-wrap: anywhere;
+  } /* end of rule */
+} /* end of media rule */
diff --git a/web/index.html b/web/index.html
index 1d88be6..4cc393f 100644
--- a/web/index.html
+++ b/web/index.html
@@ -59,6 +59,11 @@
 <a class="btn-plain ctlbtn" href="/" aria-describedby="tiprefresh"><svg class="ico" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 8a5 5 0 1 1-1.6-3.7"/><path d="M13 2.5V5h-2.5"/></svg> Refresh</a>
 <span class="tip tip-icon" role="tooltip" id="tiprefresh">Check Ollama once, right now</span>
 </span>
+{{/* Settings: a plain link to the Settings page; it changes nothing by itself. */}}
+<span class="tipbox">
+<a class="btn-plain ctlbtn" href="/settings" aria-describedby="tipsettings"><svg class="ico" viewBox="0 0 24 24" width="14" height="14" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 6h9"/><path d="M17 6h3"/><circle cx="15" cy="6" r="2"/><path d="M4 12h3"/><path d="M11 12h9"/><circle cx="9" cy="12" r="2"/><path d="M4 18h11"/><path d="M19 18h1"/><circle cx="17" cy="18" r="2"/></svg> Settings</a>
+<span class="tip tip-icon" role="tooltip" id="tipsettings">Settings: Ollama address, check interval, timeout, chart history, access from other machines</span>
+</span>
 {{/* Stop: a small form that goes to the question page; nothing is stopped yet. */}}
 <form method="post" action="/stop">
 {{/* The page token proves the form comes from this monitor. */}}
diff --git a/web/settings.html b/web/settings.html
new file mode 100644
index 0000000..4f26879
--- /dev/null
+++ b/web/settings.html
@@ -0,0 +1,77 @@
+{{/* Settings page template: the values the person can change. The comments are template comments, so they never reach the browser. */}}
+<!DOCTYPE html>
+{{/* lang tells screen readers which language the page is written in; the theme and the text size come from the saved choices. */}}
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
+<head>{{/* start of the head. */}}
+{{/* Text encoding. */}}
+<meta charset="utf-8">
+{{/* Fit the page to the width of the screen on phones. */}}
+<meta name="viewport" content="width=device-width, initial-scale=1">
+{{/* The title shown on the browser tab. */}}
+<title>Settings</title>
+{{/* Our one stylesheet. */}}
+<link rel="stylesheet" href="/app.css">
+</head>{{/* end of the head. */}}
+<body>{{/* start of the visible page. */}}
+{{/* The page content. */}}
+<main>
+{{/* One box holds everything. */}}
+<section class="panel">
+{{/* The back arrow in the top right corner of this box: a round link to the monitor; its words are in its tooltip and in its accessible name. It only follows a link and changes nothing. */}}
+<span class="tipbox backtop"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback">Back to the monitor</span></span>
+{{/* The heading. */}}
+<h1>Settings</h1>
+{{/* What the page does. */}}
+<p>Check the values, change what you need and press <strong>Save settings</strong>. A value left empty (or equal to the default) uses the default. Values marked <strong>restart</strong> are used the next time the monitor starts; the others apply at once. The look of the page (light or dark, text size) is changed with the buttons at the top of the monitor page.</p>
+{{/* A note after saving. */}}
+{{if eq .Saved "saved"}}<p class="muted" role="status"><strong>Saved.</strong> {{if .RestartNeeded}}The values marked restart are used the next time the monitor starts.{{else}}The changes are in use now.{{end}}</p>{{end}}
+{{/* A note after going back to the defaults. */}}
+{{if eq .Saved "reset"}}<p class="muted" role="status"><strong>All settings are back to their defaults.</strong> {{if .RestartNeeded}}The values marked restart are used the next time the monitor starts.{{end}}</p>{{end}}
+{{/* A note about a damaged settings file or a missing folder. */}}
+{{if .Note}}<p class="warn"><strong>⚠</strong> {{.Note}}</p>{{end}}
+{{/* Problems with what was typed; nothing was saved. */}}
+{{if .Problems}}<div class="warn" role="alert"><p><strong>⚠ Not saved.</strong> Please correct:</p><ul>{{range .Problems}}<li>{{.}}</li>{{end}}</ul></div>{{end}}
+{{/* The form: it sends the page token and the typed values. */}}
+<form method="post" action="/settings">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* The table of settings: one row each, with what is in use now, the new value, the default and when it applies. */}}
+<table class="settingtable">
+{{/* The column headings. */}}
+<thead><tr><th scope="col">Setting</th><th scope="col">In use now</th><th scope="col">New value</th><th scope="col">Default</th><th scope="col">Applies</th></tr></thead>
+{{/* The body. */}}
+<tbody>
+{{/* One row each. */}}
+{{range .Rows}}
+<tr>
+<th scope="row">{{.Label}}<br><small class="muted">{{.Help}}</small></th>
+<td><span class="cellname">In use now: </span>{{.Now}}{{if .From}}<br><small class="muted">from: {{.From}}</small>{{end}}{{if .Pending}}<br><small class="muted"><strong>{{.Pending}}</strong></small>{{end}}</td>
+<td>
+<span class="cellname">New value: </span>
+{{/* The right control for this row. */}}
+{{if eq .Kind "text"}}<input class="stopfield{{if not .Typed}} notset{{end}}" style="width:15rem" name="{{.Name}}" type="text" inputmode="url" maxlength="300" autocomplete="off" aria-label="{{.Label}}" placeholder="{{.Default}}" value="{{.Typed}}">{{end}}
+{{if eq .Kind "number"}}<input class="numfield" name="{{.Name}}" type="number" inputmode="numeric" min="{{.Min}}" max="{{.Max}}" step="1" aria-label="{{.Label}}" value="{{.Typed}}">{{end}}
+{{if eq .Kind "yesno"}}<select class="keepselect" name="{{.Name}}" aria-label="{{.Label}}"><option value="no"{{if eq .Typed "no"}} selected{{end}}>No</option><option value="yes"{{if eq .Typed "yes"}} selected{{end}}>Yes</option></select>{{end}}
+</td>
+<td><span class="cellname">Default: </span>{{.Default}}</td>
+<td><span class="cellname">Applies: </span>{{.Applies}}</td>
+</tr>
+{{end}}
+</tbody>
+</table>
+{{/* The warning about other machines: the page has no password. */}}
+<p class="warn"><strong>⚠</strong> If you let other machines open this page, anyone on your network can use its buttons (unload, delete, stop). The page has no password, so turn this on only on a network you trust.</p>
+{{/* Where the files are kept. */}}
+<p class="muted">Saved in <code>{{if .Folder}}{{.Folder}}{{else}}(no folder found: kept only until the monitor stops){{end}}</code>. The check history file holds only the time, the result and the answer time of each check: no model names and no prompts. Turning the history off deletes that file.</p>
+{{/* The buttons. */}}
+<p><button type="submit" name="action" value="save" class="btn-plain ctlbtn">Save settings</button> <button type="submit" name="action" value="defaults" class="btn-plain ctlbtn">Back to defaults</button></p>
+{{/* End of the form. */}}
+</form>
+{{/* A plain way back besides the arrow. */}}
+<p><a href="/">Back to the monitor</a></p>
+{{/* End of the box. */}}
+</section>
+{{/* End of the page content. */}}
+</main>
+</body>{{/* end of the visible page. */}}
+</html>
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
d0a27d7ac0700d0259dc31d03959fd2e713a2b830d502036de313ec05dd069aa  appsettings.go
f6153582d79839e04576103604fc0e52b752e88a1a2a204b77b4e057d1c4e980  appsettings_test.go
1355b8a7e1d72794bd91c28cbf8e42aa2910396f216c8e797316b2c8ae0b4779  settingspage.go
8701332dcf7f631d3fae7475c4f140c19a80fbee3b148d4df45eba1ae2cd335c  web/settings.html
1016836e6d7b68e29c7f91a841f86616978dab796d731e84c2737312d9ff9b34  charts.go
472068765aaa262d76885d4bb1627a1d5b5e47ff1f75c3120ad68f844adb3da9  config.go
ae4fca0ada891885a7866d9fd8290ecc5bc53171533c17e363dbf3ca57ed16b4  guard.go
3732d3d6a7ebff8a82b4dab4f5358a49b534edbccd7db43d2bd5b90b9b022954  main.go
fd15c3ebf6a0f30b1d158a61350c340456854e76691ce2f864ef8629e4c585ce  monitor.go
fddd32d0b5ad5f444704109097ba557bf427b2cc678107d1046a54363b5dafff  web.go
ed649cb59badef29dbe3cfdd56ee3ecb5bee9c934d8842bea4919b27db638128  web/index.html
5b1fb08889884cd22da1cf61db658e336c92309c56a433e5c6f3fb8c66e4a962  web/app.css
694ed66e9d52e0334b45aed6aab3c97d2f93d064e97c157f6240484611233bdd  tooltips.go
3d1e39c5bdd1a086e74e703e44131f75afa9dc6b2f1a5ca3af1086571943683a  monitor_test.go
532f6164cdc476b5f9bdc0927528a797f9ff3281d8da80d3f491f157e5d93a03  about.go
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
# Tell the person how to use the new command.
echo "NEXT  start ./bin/OllamaControlCenter, press the Settings button at the top right of the monitor page, change the check interval to 15 and press Save settings"
# List the changed files; nothing is committed yet.
git status --short
