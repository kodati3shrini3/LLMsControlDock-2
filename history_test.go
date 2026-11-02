// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// encoding/json reads the saved snapshot.
	"encoding/json"
	// net/http provides status codes.
	"net/http"
	// net/url builds form values.
	"net/url"
	// os reads and writes the test files.
	"os"
	// path/filepath builds paths.
	"path/filepath"
	// strings searches the pages.
	"strings"
	// testing is Go's test framework.
	"testing"
	// time stamps the test snapshots.
	"time"
) // end of imports

// order returns the requests Ollama received, in order, as "show" and "delete".
func (f *delFake) order() []string {
	// One at a time.
	f.mu.Lock()
	// Release at the end.
	defer f.mu.Unlock()
	// A copy.
	return append([]string(nil), f.events...)
} // end of order

// snapFiles lists the snapshot files in a folder.
func snapFiles(t *testing.T, dir string) []string {
	// Mark this as a helper.
	t.Helper()
	// Read the folder; a missing one is empty.
	entries, _ := os.ReadDir(dir)
	// The names.
	var names []string
	// Collect them.
	for _, e := range entries {
		// Add it.
		names = append(names, e.Name())
	} // end of the loop
	// Hand back.
	return names
} // end of snapFiles

// TestWarningTellsWhatIsKept checks the warning page says what will be kept about the parameters, before anything is deleted.
func TestWarningTellsWhatIsKept(t *testing.T) {
	// The rig: alpha has three parameters.
	rig, f, dir := delRig(t)
	// Ask about alpha.
	body := bodyOf(post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
	// The words.
	if !strings.Contains(body, "a snapshot of its 3 inference parameter(s) is saved in the history folder") {
		// Report it.
		t.Errorf("the warning does not say what will be kept: %s", body)
	} // end of the check
	// A model without parameters.
	f.mu.Lock()
	// Remove alpha's parameters.
	f.params = map[string]string{}
	// Release.
	f.mu.Unlock()
	// Ask again.
	body = bodyOf(post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
	// The words.
	if !strings.Contains(body, "has no tuned inference parameters") {
		// Report it.
		t.Errorf("the warning does not say there are none: %s", body)
	} // end of the none check
	// Ollama cannot tell.
	f.mu.Lock()
	// Make show fail.
	f.failShow = true
	// Release.
	f.mu.Unlock()
	// Ask again.
	body = bodyOf(post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
	// The caution.
	if !strings.Contains(body, "inference parameters just now, so they will not be kept") || !strings.Contains(body, "Yes, delete it") {
		// Report it.
		t.Errorf("the caution is missing, or the choice was taken away: %s", body)
	} // end of the caution check
	// Asking wrote nothing and deleted nothing.
	if len(snapFiles(t, filepath.Join(dir, historyDirName))) != 0 || f.calls() != 0 {
		// Report it.
		t.Errorf("only asking changed something")
	} // end of the nothing check
} // end of TestWarningTellsWhatIsKept

// TestDeleteSavesSnapshotFirst checks the snapshot is read before the delete, written privately, and shown on the done page and in the history.
func TestDeleteSavesSnapshotFirst(t *testing.T) {
	// The rig.
	rig, f, dir := delRig(t)
	// Delete alpha.
	body := bodyOf(post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
	// The done page names the snapshot file.
	if !strings.Contains(body, "A snapshot of its inference parameters was saved in the history folder") || !strings.Contains(body, "_alpha-1b_deleted.json") {
		// Report it.
		t.Errorf("the done page does not name the snapshot: %s", body)
	} // end of the done check
	// The last show request came before the delete request.
	ev := f.order()
	// The delete request is the last one; a show must be right before it.
	if len(ev) < 2 || ev[len(ev)-1] != "delete" || ev[len(ev)-2] != "show" {
		// Report it.
		t.Errorf("order of requests %v: the parameters must be read before the delete", ev)
	} // end of the order check
	// Exactly one file in the history folder, private.
	hd := filepath.Join(dir, historyDirName)
	// The files.
	names := snapFiles(t, hd)
	// One file.
	if len(names) != 1 {
		// Stop the test.
		t.Fatalf("history files: %v", names)
	} // end of the count check
	// Its mode.
	if info, _ := os.Stat(filepath.Join(hd, names[0])); info.Mode().Perm() != 0o600 {
		// Report it.
		t.Errorf("file mode %o, want 600", info.Mode().Perm())
	} // end of the file mode check
	// The folder mode.
	if info, _ := os.Stat(hd); info.Mode().Perm() != 0o700 {
		// Report it.
		t.Errorf("folder mode %o, want 700", info.Mode().Perm())
	} // end of the folder mode check
	// Its content.
	data, _ := os.ReadFile(filepath.Join(hd, names[0]))
	// Decode it.
	var s paramSnapshot
	// Check it.
	if err := json.Unmarshal(data, &s); err != nil || s.Model != "alpha:1b" || s.Version != snapshotVersion || len(s.Parameters) != 3 || s.Parameters[0] != (snapParam{Name: "temperature", Value: "0.7"}) || s.Size != 1300000000 || s.Digest != "sha256:alpha:1b" {
		// Report it.
		t.Errorf("snapshot content wrong: %v %+v", err, s)
	} // end of the content check
	// The restore page offers the history.
	restore := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
	// The page says a snapshot was kept, before the button is clicked.
	if !strings.Contains(restore, "A snapshot of the parameters it had was kept (1). Use View history below.") {
		// Report it.
		t.Errorf("the restore page does not say a snapshot exists")
	} // end of the snapshot line check
	// The button.
	if !strings.Contains(restore, `action="/restore/history"`) || !strings.Contains(restore, "View history") {
		// Report it.
		t.Errorf("the restore page has no View history button")
	} // end of the button check
	// The history page.
	page := bodyOf(post(t, rig.h, "/restore/history", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
	// The parameters and the facts, with the stop word escaped.
	for _, want := range []string{"History of <code>alpha:1b</code>", "<code>temperature</code>", "<code>0.7</code>", "<code>num_ctx</code>", "<code>4096</code>", "&#34;&lt;end&gt;&#34;", "1.3 GB", strings.ReplaceAll(names[0], "+", "&#43;")} {
		// Look for it.
		if !strings.Contains(page, want) {
			// Report the gap.
			t.Errorf("the history page lacks %q", want)
		} // end of the check
	} // end of the loop
	// Nothing about other models.
	empty := bodyOf(post(t, rig.h, "/restore/history", url.Values{"token": {rig.token}, "model": {"beta:7b"}}, fromThisPage))
	// The honest empty page.
	if !strings.Contains(empty, "No history was recorded for this model") {
		// Report it.
		t.Errorf("an unknown model should have no history: %s", empty)
	} // end of the empty check
} // end of TestDeleteSavesSnapshotFirst

// TestDeleteWithoutSnapshotIsReported checks a failed snapshot is said plainly, and the confirmed delete still happens.
func TestDeleteWithoutSnapshotIsReported(t *testing.T) {
	// Ollama cannot tell the parameters.
	rig, f, dir := delRig(t)
	// Make show fail.
	f.failShow = true
	// Delete alpha.
	body := bodyOf(post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
	// The honest note and the deletion.
	if !strings.Contains(body, "No snapshot of its inference parameters was saved") || !strings.Contains(body, "Done.") || f.calls() != 1 {
		// Report it.
		t.Errorf("failed snapshot not reported, or the delete did not happen (calls %d): %s", f.calls(), body)
	} // end of the check
	// No file.
	if n := snapFiles(t, filepath.Join(dir, historyDirName)); len(n) != 0 {
		// Report it.
		t.Errorf("files after a failed snapshot: %v", n)
	} // end of the file check
	// The folder cannot be created: a plain file sits where it should be.
	rig2, f2, dir2 := delRig(t)
	// Block the folder.
	os.MkdirAll(dir2, 0o700)
	// The blocker.
	os.WriteFile(filepath.Join(dir2, historyDirName), []byte("x"), 0o600)
	// Delete alpha.
	body = bodyOf(post(t, rig2.h, "/delete/confirm", url.Values{"token": {rig2.token}, "model": {"alpha:1b"}}, fromThisPage))
	// Still deleted, with the reason.
	if !strings.Contains(body, "No snapshot of its inference parameters was saved: the history folder could not be created") || f2.calls() != 1 {
		// Report it.
		t.Errorf("unwritable folder not reported: %s", body)
	} // end of the unwritable check
} // end of TestDeleteWithoutSnapshotIsReported

// TestHistoryStoreRules checks file names, no overwriting, and what the listing ignores.
func TestHistoryStoreRules(t *testing.T) {
	// A private folder.
	dir := filepath.Join(t.TempDir(), "history")
	// The store.
	h := &historyStore{dir: dir}
	// One moment.
	at := time.Date(2026, 10, 27, 17, 30, 0, 0, time.UTC)
	// A hostile model name.
	hostile := "../../etc/pass wd:1"
	// Save twice in the same second.
	a, err1 := h.save(paramSnapshot{Model: hostile, DeletedAt: at})
	// The second.
	b, err2 := h.save(paramSnapshot{Model: hostile, DeletedAt: at})
	// Both must work and differ.
	if err1 != nil || err2 != nil || a == b {
		// Report it.
		t.Fatalf("saves: %q %v / %q %v", a, err1, b, err2)
	} // end of the save check
	// Nothing may leave the folder, and the names hold no separators.
	for _, n := range []string{a, b} {
		// Check the name.
		if strings.ContainsAny(n, "/\\:") || strings.HasPrefix(n, ".") {
			// Report it.
			t.Errorf("unsafe file name %q", n)
		} // end of the name check
		// The file is inside the folder.
		if _, err := os.Stat(filepath.Join(dir, n)); err != nil {
			// Report it.
			t.Errorf("file %q is not in the folder", n)
		} // end of the place check
	} // end of the loop
	// Nothing was written outside.
	if _, err := os.Stat(filepath.Join(dir, "..", "..", "etc")); err == nil {
		// Report it.
		t.Errorf("a file escaped the folder")
	} // end of the escape check
	// Things the listing must ignore.
	os.WriteFile(filepath.Join(dir, "notes.txt"), []byte("x"), 0o600)
	// A damaged snapshot.
	os.WriteFile(filepath.Join(dir, "bad"+snapshotSuffix), []byte("{no"), 0o600)
	// An oversized one.
	os.WriteFile(filepath.Join(dir, "big"+snapshotSuffix), []byte(strings.Repeat("a", maxSnapshotFile+5)), 0o600)
	// Another version.
	os.WriteFile(filepath.Join(dir, "v9"+snapshotSuffix), []byte(`{"version":9,"model":"`+hostile+`"}`), 0o600)
	// A link to a file outside.
	outside := filepath.Join(t.TempDir(), "o.json")
	// Its content would match the model.
	os.WriteFile(outside, []byte(`{"version":1,"model":"`+hostile+`"}`), 0o600)
	// The link.
	os.Symlink(outside, filepath.Join(dir, "link"+snapshotSuffix))
	// Another model's snapshot.
	h.save(paramSnapshot{Model: "other:1", DeletedAt: at})
	// A newer snapshot of the hostile model.
	h.save(paramSnapshot{Model: hostile, DeletedAt: at.Add(time.Hour), Digest: "newer"})
	// List.
	got := h.list(hostile)
	// Three real snapshots, newest first.
	if len(got) != 3 || got[0].Digest != "newer" {
		// Report it.
		t.Errorf("listing gave %d snapshots (want 3, newest first): %+v", len(got), got)
	} // end of the list check
	// A store without a folder saves nothing and lists nothing, and says why.
	none := &historyStore{note: "no folder"}
	// Save.
	if _, err := none.save(paramSnapshot{Model: "x"}); err == nil || !strings.Contains(err.Error(), "no folder") {
		// Report it.
		t.Errorf("a store without a folder must refuse with its reason: %v", err)
	} // end of the refuse check
	// List.
	if len(none.list("x")) != 0 {
		// Report it.
		t.Errorf("a store without a folder listed something")
	} // end of the empty list check
} // end of TestHistoryStoreRules

// TestHistoryFolderStaysOutOfGitHub checks the .gitignore keeps the history folder out of the repository (requirement S4).
func TestHistoryFolderStaysOutOfGitHub(t *testing.T) {
	// Read the ignore file of the project.
	data, err := os.ReadFile(".gitignore")
	// It must exist.
	if err != nil {
		// Stop the test.
		t.Fatalf("no .gitignore: %v", err)
	} // end of the read check
	// A line that ignores the folder.
	ok := false
	// Look at every line.
	for _, l := range strings.Split(string(data), "\n") {
		// The folder name with a slash.
		if strings.TrimSpace(l) == historyDirName+"/" {
			// Found.
			ok = true
		} // end of the line check
	} // end of the loop
	// Report a gap.
	if !ok {
		// Report it.
		t.Errorf(".gitignore does not ignore %s/", historyDirName)
	} // end of the ignore check
} // end of TestHistoryFolderStaysOutOfGitHub

// TestDefaultHistoryDir checks the folder choice: always "history" in the data folder inside the configuration folder, wherever the program is.
func TestDefaultHistoryDir(t *testing.T) {
	// Keep and restore the two lookups.
	oldExe, oldCfg := executablePath, userConfigDir
	// Put them back afterwards.
	t.Cleanup(func() { executablePath, userConfigDir = oldExe, oldCfg })
	// A configuration folder.
	userConfigDir = func() (string, error) { return "/cfg", nil }
	// A program inside bin, and one elsewhere: the same answer.
	for _, exe := range []string{"/p/OllamaControlCenter/bin/occ", "/p/occ"} {
		// Use this program place.
		executablePath = func() (string, error) { return exe, nil }
		// The folder.
		if d, _ := defaultHistoryDir(); d != filepath.Join("/cfg", "OllamaControlCenter", "history") {
			// Report it.
			t.Errorf("exe %q gave %q", exe, d)
		} // end of the check
	} // end of the loop
	// Nothing at all.
	userConfigDir = func() (string, error) { return "", http.ErrNotSupported }
	// The folder and the reason.
	if d, note := defaultHistoryDir(); d != "" || note == "" {
		// Report it.
		t.Errorf("no-folder case gave %q, %q", d, note)
	} // end of the no-folder check
} // end of TestDefaultHistoryDir

// TestRestorePageSaysWhenNothingWasKept checks a model deleted without a snapshot says so on the restore page.
func TestRestorePageSaysWhenNothingWasKept(t *testing.T) {
	// Ollama cannot tell the parameters, so no snapshot is taken.
	rig, f, _ := delRig(t)
	// Make show fail.
	f.failShow = true
	// Delete alpha anyway.
	post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// The restore page.
	body := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
	// The honest line, and no claim that a snapshot exists.
	if !strings.Contains(body, "No snapshot of its parameters was kept, so the old values are not known.") || strings.Contains(body, "was kept (") {
		// Report it.
		t.Errorf("the restore page does not say nothing was kept: %s", body)
	} // end of the check
	// The key explains the history too.
	_, _, page := get(t, rig.h, http.MethodGet, "/?key=open")
	// The key text.
	if !strings.Contains(page, "how to download it again, and the parameters it had") {
		// Report it.
		t.Errorf("the key does not mention the parameters")
	} // end of the key check
} // end of TestRestorePageSaysWhenNothingWasKept
