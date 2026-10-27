#!/usr/bin/env bash
# Script 61: when a model is deleted, a snapshot of its inference parameters is saved in the history folder (kept out of GitHub); the restore page gets a View history button; the warning page says what will be kept.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/delete-history" ] || { echo "FAIL  not on feature/delete-history"; exit 1; }
# Script 60 must be applied first.
grep -q 'lossbox' web/delete.html || { echo "FAIL  script 60 was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e history.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/delete.go b/delete.go
index 9fe982d..d605832 100644
--- a/delete.go
+++ b/delete.go
@@ -53,6 +53,20 @@ func deleteModel(ctx context.Context, base *url.URL, name string, timeout time.D
 	return fmt.Errorf("Ollama answered the delete request with status %d", status)
 } // end of deleteModel
 
+// snapView is one snapshot, ready to be drawn on the history page.
+type snapView struct {
+	// When is the deletion time in words.
+	When string
+	// SizeText is the size then.
+	SizeText string
+	// Digest is the fingerprint then.
+	Digest string
+	// Params are the inference parameters then; empty means none were set.
+	Params []snapParam
+	// File is the file the snapshot is kept in.
+	File string
+} // end of snapView
+
 // deletePage is everything the delete page template can show.
 type deletePage struct {
 	// Kind says which version of the page to draw: confirm, busy, done, gone, restore, forgotten, error.
@@ -75,6 +89,16 @@ type deletePage struct {
 	Detail string
 	// Note carries a warning that does not stop the work (for example, the list could not be saved).
 	Note string
+	// SnapText says, before deleting, what will be kept about the model's inference parameters (or that nothing can be kept).
+	SnapText string
+	// SnapClass is "ok" for good news and "warn" for a caution.
+	SnapClass string
+	// SnapFile is the snapshot file that was saved (done page); empty when none was saved.
+	SnapFile string
+	// SnapErr is why no snapshot was saved (done page); empty when it was saved.
+	SnapErr string
+	// Snaps are the snapshots of the model, newest first (history page).
+	Snaps []snapView
 	// LibText is what the check of the Ollama library found, in words (empty when no check was made).
 	LibText string
 	// LibClass is "ok" for good news and "warn" for a caution; it decides how the note is drawn.
@@ -87,8 +111,8 @@ type deletePage struct {
 	Token string
 } // end of deletePage
 
-// deleteHandlers builds the handlers: ask (changes nothing), confirm, force, restore (information only) and forget.
-func deleteHandlers(addr ollamaAddress, token string, store *deletedStore) (ask, confirm, force, restore, forget http.HandlerFunc) {
+// deleteHandlers builds the handlers: ask (changes nothing), confirm, force, restore (information only), forget, and viewHistory (read-only list of the parameter snapshots).
+func deleteHandlers(addr ollamaAddress, token string, store *deletedStore, hist *historyStore) (ask, confirm, force, restore, forget, viewHistory http.HandlerFunc) {
 	// Read the template once; Must stops the program at start-up if the template is broken, which a test would catch first.
 	page := template.Must(template.New("delete").Parse(deleteTemplateText))
 	// readForm runs the checks that all handlers share and returns the model name; ok is false when a refusal was already sent.
@@ -162,6 +186,30 @@ func deleteHandlers(addr ollamaAddress, token string, store *deletedStore) (ask,
 		// Build the page data.
 		return deletePage{Kind: "busy", Model: name, SizeText: formatSize(size), Remaining: remainingText(time.Now(), exp, expOK), Seconds: remainingSeconds(time.Now(), exp, expOK), Mismatch: mismatch}
 	} // end of busyPage
+	// snapPlan checks, without writing anything, whether a snapshot of the model's parameters can be taken, and words the answer for the warning page.
+	snapPlan := func(r *http.Request, name string) (string, string) {
+		// No folder, no snapshot.
+		if hist.dir == "" {
+			// Say so.
+			return "Nothing about this model's inference parameters can be kept, because there is no history folder. " + hist.note, "warn"
+		} // end of the folder check
+		// Ask Ollama for the parameters.
+		info, status, err := fetchShow(r.Context(), addr.URL, name, defaultCheckTimeout)
+		// Ollama did not tell.
+		if err != nil || status != http.StatusOK {
+			// Say so.
+			return "Could not read this model's inference parameters just now, so they will not be kept if you delete it.", "warn"
+		} // end of the show check
+		// How many are set.
+		n := len(parseParams(info.Parameters))
+		// None set.
+		if n == 0 {
+			// Say so.
+			return "This model has no tuned inference parameters. A note saying so is kept in the history folder.", "ok"
+		} // end of the none case
+		// Some set.
+		return fmt.Sprintf("Before deleting, a snapshot of its %d inference parameter(s) is saved in the history folder. After a restore, Restore, then View history, shows them.", n), "ok"
+	} // end of snapPlan
 	// withLib asks the Ollama library, read-only, about this model and adds the answer in words to the page; phase is "delete" or "restore". Only the model name leaves this computer.
 	withLib := func(r *http.Request, p deletePage, name, digest, phase string) deletePage {
 		// Ask the library.
@@ -170,6 +218,11 @@ func deleteHandlers(addr ollamaAddress, token string, store *deletedStore) (ask,
 		p.LibText, p.LibClass = libraryNote(state, phase)
 		// A command that is certain to fail is not offered.
 		p.ShowPull = state != libMissing
+		// Before deleting, also say what will be kept about the model's parameters.
+		if phase == "delete" {
+			// Plan the snapshot.
+			p.SnapText, p.SnapClass = snapPlan(r, name)
+		} // end of the delete phase
 		// Hand the page back.
 		return p
 	} // end of withLib
@@ -209,6 +262,21 @@ func deleteHandlers(addr ollamaAddress, token string, store *deletedStore) (ask,
 	} // end of look
 	// doDelete deletes, checks that the model is really gone, remembers it, and shows the result page.
 	doDelete := func(w http.ResponseWriter, r *http.Request, m installedModel) {
+		// The moment of deletion, used for the snapshot and for the list of deleted models.
+		at := time.Now()
+		// Keep the model's inference parameters first, because after the deletion they are gone; a failure is reported, not hidden, and does not block the deletion the person has already confirmed.
+		snapFile, snapErr := "", ""
+		// Ask Ollama for them.
+		if info, status, err := fetchShow(r.Context(), addr.URL, m.Name, defaultCheckTimeout); err != nil || status != http.StatusOK {
+			// Say why nothing was kept.
+			snapErr = "Ollama could not tell this model's inference parameters."
+		} else if f, err := hist.save(snapshotFrom(m, info, at)); err != nil { // the other case
+			// Say why nothing was kept.
+			snapErr = err.Error()
+		} else { // the saved case
+			// Remember the file name.
+			snapFile = f
+		} // end of the snapshot
 		// Ask Ollama to delete it.
 		if err := deleteModel(r.Context(), addr.URL, m.Name, deleteTimeout); err != nil {
 			// Show the plain reason.
@@ -235,12 +303,12 @@ func deleteHandlers(addr ollamaAddress, token string, store *deletedStore) (ask,
 		// Remember it, so the table can show it greyed out and Restore can offer it again.
 		note := ""
 		// Save; a failure does not undo the deletion, it only means the ghost row will be missing.
-		if err := store.add(deletedModel{Name: m.Name, Digest: m.Digest, Size: m.Size, DeletedAt: time.Now()}); err != nil {
+		if err := store.add(deletedModel{Name: m.Name, Digest: m.Digest, Size: m.Size, DeletedAt: at}); err != nil {
 			// Say so in words.
 			note = "The model is deleted, but this monitor could not remember it, so there will be no Restore row. " + err.Error()
 		} // end of the save check
 		// Done.
-		show(w, r, http.StatusOK, deletePage{Kind: "done", Model: m.Name, SizeText: formatSize(m.Size), Note: note})
+		show(w, r, http.StatusOK, deletePage{Kind: "done", Model: m.Name, SizeText: formatSize(m.Size), Note: note, SnapFile: snapFile, SnapErr: snapErr})
 	} // end of doDelete
 	// ask is the first step: it re-checks Ollama and shows the right warning; it never deletes anything.
 	ask = func(w http.ResponseWriter, r *http.Request) {
@@ -366,6 +434,25 @@ func deleteHandlers(addr ollamaAddress, token string, store *deletedStore) (ask,
 		// Done.
 		show(w, r, http.StatusOK, deletePage{Kind: "forgotten", Model: name})
 	} // end of forget
-	// Hand all five back (they are the named results).
+	// viewHistory lists the snapshots of one model; it only reads and changes nothing.
+	viewHistory = func(w http.ResponseWriter, r *http.Request) {
+		// Run the shared checks.
+		name, ok := readForm(w, r)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the checks
+		// Build the views.
+		var views []snapView
+		// One per snapshot.
+		for _, sn := range hist.list(name) {
+			// Add it.
+			views = append(views, snapView{When: sn.DeletedAt.Local().Format("2 Jan 2006 15:04:05 MST"), SizeText: formatSize(sn.Size), Digest: sn.Digest, Params: sn.Parameters, File: sn.File})
+		} // end of the loop
+		// Show the page.
+		show(w, r, http.StatusOK, deletePage{Kind: "history", Model: name, Snaps: views})
+	} // end of viewHistory
+	// Hand all six back (they are the named results).
 	return
 } // end of deleteHandlers
diff --git a/delete_test.go b/delete_test.go
index 3617a8d..6de38cf 100644
--- a/delete_test.go
+++ b/delete_test.go
@@ -50,6 +50,12 @@ type delFake struct {
 	digests map[string]string
 	// reg is the fake Ollama library this rig points the monitor at.
 	reg *regFake
+	// params maps a model name to the parameters text /api/show reports (a missing name reports none).
+	params map[string]string
+	// failShow makes /api/show answer with a server error.
+	failShow bool
+	// events lists "show" and "delete" in the order Ollama received them.
+	events []string
 } // end of delFake
 
 // regFake is a fake Ollama library: for each manifest path it answers a status and a body, and it records every path it was asked for.
@@ -147,6 +153,33 @@ func (f *delFake) start(t *testing.T) string {
 			} // end of the loop
 			// Send it.
 			json.NewEncoder(w).Encode(map[string]any{"models": list})
+		// The details of one model.
+		case "/api/show":
+			// Record the request.
+			f.events = append(f.events, "show")
+			// A failing server.
+			if f.failShow {
+				// Say so.
+				w.WriteHeader(http.StatusInternalServerError)
+				// Stop.
+				return
+			} // end of the failure case
+			// Read the name.
+			var req struct {
+				// Model is the name.
+				Model string `json:"model"`
+			} // end of the request shape
+			// Decode it.
+			json.NewDecoder(r.Body).Decode(&req)
+			// Unknown model.
+			if _, ok := f.sizes[req.Model]; !ok {
+				// Ollama answers 404.
+				w.WriteHeader(http.StatusNotFound)
+				// Stop.
+				return
+			} // end of the unknown case
+			// The reply: parameters, a Modelfile and no model facts.
+			json.NewEncoder(w).Encode(map[string]any{"parameters": f.params[req.Model], "modelfile": "FROM " + req.Model})
 		// The delete request.
 		case "/api/delete":
 			// It must be a DELETE.
@@ -158,6 +191,8 @@ func (f *delFake) start(t *testing.T) string {
 			} // end of the method check
 			// Count it.
 			f.deleteCalls++
+			// Record the order.
+			f.events = append(f.events, "delete")
 			// A failing server.
 			if f.failDelete {
 				// Say so.
@@ -243,7 +278,7 @@ func delRig(t *testing.T) (themeRig, *delFake, string) {
 	// Put it back afterwards.
 	t.Cleanup(func() { registryBase = oldReg })
 	// The fake with its models.
-	f := &delFake{sizes: map[string]int64{"alpha:1b": 1300000000, "beta:7b": 4700000000}, loaded: map[string]bool{"beta:7b": true}, reg: g}
+	f := &delFake{sizes: map[string]int64{"alpha:1b": 1300000000, "beta:7b": 4700000000}, loaded: map[string]bool{"beta:7b": true}, reg: g, params: map[string]string{"alpha:1b": "temperature                    0.7\nnum_ctx                        4096\nstop                           \"<end>\""}}
 	// The monitor.
 	h := handlerFor(t, f.start(t))
 	// Read the main page to learn the token.
@@ -553,7 +588,7 @@ func TestDeleteRoutesAreGuarded(t *testing.T) {
 	// The rig.
 	rig, f, _ := delRig(t)
 	// Every delete and restore route.
-	for _, path := range []string{"/delete", "/delete/confirm", "/delete/force", "/restore", "/restore/forget"} {
+	for _, path := range []string{"/delete", "/delete/confirm", "/delete/force", "/restore", "/restore/forget", "/restore/history"} {
 		// A GET is not allowed.
 		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed {
 			// Report it.
diff --git a/history.go b/history.go
new file mode 100644
index 0000000..84e5996
--- /dev/null
+++ b/history.go
@@ -0,0 +1,277 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// encoding/json reads and writes the snapshot files.
+	"encoding/json"
+	// errors tells "file exists" apart from other problems.
+	"errors"
+	// fmt builds file names and error texts.
+	"fmt"
+	// io limits how much of a file is read.
+	"io"
+	// os reads and writes the files.
+	"os"
+	// path/filepath builds file paths for any operating system.
+	"path/filepath"
+	// regexp makes a model name safe to use inside a file name.
+	"regexp"
+	// sort keeps the list newest first.
+	"sort"
+	// strings checks file name endings.
+	"strings"
+	// time stamps the snapshot and its file name.
+	"time"
+) // end of imports
+
+// historyDirName is the folder for the history files; the .gitignore already keeps this name out of GitHub (requirement S4).
+const historyDirName = "history"
+
+// snapshotSuffix ends the name of every snapshot file taken when a model is deleted.
+const snapshotSuffix = "_deleted.json"
+
+// snapshotVersion is written into every file so a future version of the program can recognise an older layout.
+const snapshotVersion = 1
+
+// maxSnapshotFile is the biggest snapshot file that will be read; a real one is under a kilobyte.
+const maxSnapshotFile = 64 * 1024
+
+// maxSnapshotFiles is the most files looked at when listing; a folder with more is not ours.
+const maxSnapshotFiles = 5000
+
+// snapParam is one inference parameter in a snapshot, for example temperature with 0.7.
+type snapParam struct {
+	// Name is the parameter name.
+	Name string `json:"name"`
+	// Value is the value as Ollama printed it.
+	Value string `json:"value"`
+} // end of snapParam
+
+// paramSnapshot is what is kept about a model at the moment it is deleted.
+type paramSnapshot struct {
+	// Version is snapshotVersion.
+	Version int `json:"version"`
+	// Model is the model name with its tag.
+	Model string `json:"model"`
+	// DeletedAt is the moment of deletion.
+	DeletedAt time.Time `json:"deleted_at"`
+	// Digest is the model's fingerprint at that moment.
+	Digest string `json:"digest"`
+	// Size is the size on disk in bytes.
+	Size int64 `json:"size"`
+	// Parameters are the inference parameters the model had; empty means none were set.
+	Parameters []snapParam `json:"parameters"`
+	// File is the file name the snapshot was saved under (filled in when saved or listed; not stored inside the file).
+	File string `json:"-"`
+} // end of paramSnapshot
+
+// historyStore writes and reads the snapshot files in one folder.
+type historyStore struct {
+	// dir is the folder; empty means nothing can be saved.
+	dir string
+	// note explains, in plain words, why nothing can be saved (empty when all is well).
+	note string
+} // end of historyStore
+
+// defaultHistoryDir picks the folder: "history" next to the program's folder (the same project folder as the performance results), or in the user's config folder when the program's place is unknown.
+func defaultHistoryDir() (string, string) {
+	// Next to the program, one level above a "bin" folder.
+	if exe, err := executablePath(); err == nil && exe != "" {
+		// The folder the program is in.
+		dir := filepath.Dir(exe)
+		// A program inside "bin" belongs to the project folder above it.
+		if filepath.Base(dir) == "bin" {
+			// Go one level up.
+			dir = filepath.Dir(dir)
+		} // end of the bin check
+		// The history folder.
+		return filepath.Join(dir, historyDirName), ""
+	} // end of the program check
+	// Otherwise the user's own config folder.
+	dir, err := userConfigDir()
+	// Nothing found.
+	if err != nil || dir == "" {
+		// Say so in words.
+		return "", "No folder for the history was found, so no snapshots are kept."
+	} // end of the lookup check
+	// The history folder in the config folder.
+	return filepath.Join(dir, "OllamaControlCenter", historyDirName), ""
+} // end of defaultHistoryDir
+
+// unsafeNameChars matches every character that is not safe inside a file name.
+var unsafeNameChars = regexp.MustCompile(`[^A-Za-z0-9._-]`)
+
+// safeFilePart turns a model name into text that can sit inside a file name; it can never contain a slash, a colon or a leading dot.
+func safeFilePart(name string) string {
+	// Replace every odd character.
+	s := unsafeNameChars.ReplaceAllString(name, "-")
+	// A name made only of dots or nothing becomes a plain word.
+	s = strings.TrimLeft(s, ".")
+	// Empty after cleaning.
+	if s == "" {
+		// A fixed word.
+		return "model"
+	} // end of the empty check
+	// Keep file names short.
+	if len(s) > 80 {
+		// Cut it.
+		s = s[:80]
+	} // end of the length check
+	// Hand back.
+	return s
+} // end of safeFilePart
+
+// save writes one snapshot file and returns its name; a file is never overwritten, and a second snapshot in the same second gets a number.
+func (h *historyStore) save(s paramSnapshot) (string, error) {
+	// No folder: nothing can be saved.
+	if h.dir == "" {
+		// Say why.
+		if h.note != "" {
+			// The stored reason.
+			return "", errors.New(h.note)
+		} // end of the note check
+		// A fixed reason.
+		return "", errors.New("there is no history folder")
+	} // end of the folder check
+	// The folder, readable only by this user.
+	if err := os.MkdirAll(h.dir, 0o700); err != nil {
+		// Fixed wording with the system reason.
+		return "", fmt.Errorf("the history folder could not be created: %w", err)
+	} // end of the folder check
+	// Mark the file layout.
+	s.Version = snapshotVersion
+	// Never write a JSON null for the parameters.
+	if s.Parameters == nil {
+		// An empty list.
+		s.Parameters = []snapParam{}
+	} // end of the nil check
+	// Encode with indentation so the person can read the file.
+	data, err := json.MarshalIndent(s, "", "  ")
+	// A bug, not a user problem.
+	if err != nil {
+		// Fixed wording.
+		return "", fmt.Errorf("the snapshot could not be encoded: %w", err)
+	} // end of the encode check
+	// The first part of the name: time, then the model.
+	base := s.DeletedAt.Format("2006-01-02_15-04-05") + "_" + safeFilePart(s.Model)
+	// Try the plain name, then numbered ones.
+	for n := 0; n < 100; n++ {
+		// The file name.
+		name := base + snapshotSuffix
+		// A number from the second try on.
+		if n > 0 {
+			// Add it.
+			name = fmt.Sprintf("%s-%d%s", base, n+1, snapshotSuffix)
+		} // end of the number
+		// Create the file, failing when it exists, so nothing is ever overwritten; only this user may read it.
+		f, err := os.OpenFile(filepath.Join(h.dir, name), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
+		// The name is taken: try the next.
+		if errors.Is(err, os.ErrExist) {
+			// Next number.
+			continue
+		} // end of the exists check
+		// Another problem.
+		if err != nil {
+			// Fixed wording with the system reason.
+			return "", fmt.Errorf("the snapshot file could not be created: %w", err)
+		} // end of the create check
+		// Write the bytes.
+		if _, err := f.Write(data); err != nil {
+			// Close before returning.
+			f.Close()
+			// Fixed wording.
+			return "", fmt.Errorf("the snapshot file could not be written: %w", err)
+		} // end of the write check
+		// Close to flush.
+		if err := f.Close(); err != nil {
+			// Fixed wording.
+			return "", fmt.Errorf("the snapshot file could not be written: %w", err)
+		} // end of the close check
+		// Saved.
+		return name, nil
+	} // end of the loop
+	// Too many snapshots in one second.
+	return "", errors.New("the snapshot file name was already taken")
+} // end of save
+
+// list returns the snapshots of one model, newest first; files that are not ours, damaged, too large or from another model are skipped.
+func (h *historyStore) list(model string) []paramSnapshot {
+	// Nothing to read.
+	if h.dir == "" {
+		// An empty list.
+		return nil
+	} // end of the folder check
+	// Read the folder.
+	entries, err := os.ReadDir(h.dir)
+	// A missing folder just means no history yet.
+	if err != nil {
+		// An empty list.
+		return nil
+	} // end of the read check
+	// The result.
+	var out []paramSnapshot
+	// How many files were looked at.
+	seen := 0
+	// Go through the files.
+	for _, e := range entries {
+		// Only plain files with our ending (no folders, no links).
+		if !e.Type().IsRegular() || !strings.HasSuffix(e.Name(), snapshotSuffix) {
+			// Skip it.
+			continue
+		} // end of the type check
+		// A folder with far too many files is not ours; stop.
+		if seen++; seen > maxSnapshotFiles {
+			// Stop.
+			break
+		} // end of the count check
+		// Open the file.
+		f, err := os.Open(filepath.Join(h.dir, e.Name()))
+		// Skip what cannot be opened.
+		if err != nil {
+			// Next file.
+			continue
+		} // end of the open check
+		// Read at most one byte more than the limit, to notice an oversized file.
+		data, err := io.ReadAll(io.LimitReader(f, maxSnapshotFile+1))
+		// Close it.
+		f.Close()
+		// Skip what cannot be read or is too large.
+		if err != nil || len(data) > maxSnapshotFile {
+			// Next file.
+			continue
+		} // end of the read check
+		// Decode it.
+		var s paramSnapshot
+		// Skip damaged files and other versions.
+		if err := json.Unmarshal(data, &s); err != nil || s.Version != snapshotVersion {
+			// Next file.
+			continue
+		} // end of the decode check
+		// Only this model's snapshots.
+		if s.Model != model {
+			// Next file.
+			continue
+		} // end of the model check
+		// Remember the file name for display.
+		s.File = e.Name()
+		// Keep it.
+		out = append(out, s)
+	} // end of the loop
+	// Newest first.
+	sort.Slice(out, func(i, j int) bool { return out[i].DeletedAt.After(out[j].DeletedAt) })
+	// Hand back.
+	return out
+} // end of list
+
+// snapshotFrom builds a snapshot from what Ollama said about the model.
+func snapshotFrom(m installedModel, info showReply, at time.Time) paramSnapshot {
+	// The parameters as pairs.
+	var params []snapParam
+	// Convert each saved line.
+	for _, p := range parseParams(info.Parameters) {
+		// Keep name and value.
+		params = append(params, snapParam{Name: p.Name, Value: p.Value})
+	} // end of the loop
+	// Hand back.
+	return paramSnapshot{Model: m.Name, DeletedAt: at, Digest: m.Digest, Size: m.Size, Parameters: params}
+} // end of snapshotFrom
diff --git a/history_test.go b/history_test.go
new file mode 100644
index 0000000..309ec6f
--- /dev/null
+++ b/history_test.go
@@ -0,0 +1,337 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// encoding/json reads the saved snapshot.
+	"encoding/json"
+	// net/http provides status codes.
+	"net/http"
+	// net/url builds form values.
+	"net/url"
+	// os reads and writes the test files.
+	"os"
+	// path/filepath builds paths.
+	"path/filepath"
+	// strings searches the pages.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+	// time stamps the test snapshots.
+	"time"
+) // end of imports
+
+// order returns the requests Ollama received, in order, as "show" and "delete".
+func (f *delFake) order() []string {
+	// One at a time.
+	f.mu.Lock()
+	// Release at the end.
+	defer f.mu.Unlock()
+	// A copy.
+	return append([]string(nil), f.events...)
+} // end of order
+
+// snapFiles lists the snapshot files in a folder.
+func snapFiles(t *testing.T, dir string) []string {
+	// Mark this as a helper.
+	t.Helper()
+	// Read the folder; a missing one is empty.
+	entries, _ := os.ReadDir(dir)
+	// The names.
+	var names []string
+	// Collect them.
+	for _, e := range entries {
+		// Add it.
+		names = append(names, e.Name())
+	} // end of the loop
+	// Hand back.
+	return names
+} // end of snapFiles
+
+// TestWarningTellsWhatIsKept checks the warning page says what will be kept about the parameters, before anything is deleted.
+func TestWarningTellsWhatIsKept(t *testing.T) {
+	// The rig: alpha has three parameters.
+	rig, f, dir := delRig(t)
+	// Ask about alpha.
+	body := bodyOf(post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// The words.
+	if !strings.Contains(body, "a snapshot of its 3 inference parameter(s) is saved in the history folder") {
+		// Report it.
+		t.Errorf("the warning does not say what will be kept: %s", body)
+	} // end of the check
+	// A model without parameters.
+	f.mu.Lock()
+	// Remove alpha's parameters.
+	f.params = map[string]string{}
+	// Release.
+	f.mu.Unlock()
+	// Ask again.
+	body = bodyOf(post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// The words.
+	if !strings.Contains(body, "has no tuned inference parameters") {
+		// Report it.
+		t.Errorf("the warning does not say there are none: %s", body)
+	} // end of the none check
+	// Ollama cannot tell.
+	f.mu.Lock()
+	// Make show fail.
+	f.failShow = true
+	// Release.
+	f.mu.Unlock()
+	// Ask again.
+	body = bodyOf(post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// The caution.
+	if !strings.Contains(body, "inference parameters just now, so they will not be kept") || !strings.Contains(body, "Yes, delete it") {
+		// Report it.
+		t.Errorf("the caution is missing, or the choice was taken away: %s", body)
+	} // end of the caution check
+	// Asking wrote nothing and deleted nothing.
+	if len(snapFiles(t, filepath.Join(dir, historyDirName))) != 0 || f.calls() != 0 {
+		// Report it.
+		t.Errorf("only asking changed something")
+	} // end of the nothing check
+} // end of TestWarningTellsWhatIsKept
+
+// TestDeleteSavesSnapshotFirst checks the snapshot is read before the delete, written privately, and shown on the done page and in the history.
+func TestDeleteSavesSnapshotFirst(t *testing.T) {
+	// The rig.
+	rig, f, dir := delRig(t)
+	// Delete alpha.
+	body := bodyOf(post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// The done page names the snapshot file.
+	if !strings.Contains(body, "A snapshot of its inference parameters was saved in the history folder") || !strings.Contains(body, "_alpha-1b_deleted.json") {
+		// Report it.
+		t.Errorf("the done page does not name the snapshot: %s", body)
+	} // end of the done check
+	// The last show request came before the delete request.
+	ev := f.order()
+	// The delete request is the last one; a show must be right before it.
+	if len(ev) < 2 || ev[len(ev)-1] != "delete" || ev[len(ev)-2] != "show" {
+		// Report it.
+		t.Errorf("order of requests %v: the parameters must be read before the delete", ev)
+	} // end of the order check
+	// Exactly one file in the history folder, private.
+	hd := filepath.Join(dir, historyDirName)
+	// The files.
+	names := snapFiles(t, hd)
+	// One file.
+	if len(names) != 1 {
+		// Stop the test.
+		t.Fatalf("history files: %v", names)
+	} // end of the count check
+	// Its mode.
+	if info, _ := os.Stat(filepath.Join(hd, names[0])); info.Mode().Perm() != 0o600 {
+		// Report it.
+		t.Errorf("file mode %o, want 600", info.Mode().Perm())
+	} // end of the file mode check
+	// The folder mode.
+	if info, _ := os.Stat(hd); info.Mode().Perm() != 0o700 {
+		// Report it.
+		t.Errorf("folder mode %o, want 700", info.Mode().Perm())
+	} // end of the folder mode check
+	// Its content.
+	data, _ := os.ReadFile(filepath.Join(hd, names[0]))
+	// Decode it.
+	var s paramSnapshot
+	// Check it.
+	if err := json.Unmarshal(data, &s); err != nil || s.Model != "alpha:1b" || s.Version != snapshotVersion || len(s.Parameters) != 3 || s.Parameters[0] != (snapParam{Name: "temperature", Value: "0.7"}) || s.Size != 1300000000 || s.Digest != "sha256:alpha:1b" {
+		// Report it.
+		t.Errorf("snapshot content wrong: %v %+v", err, s)
+	} // end of the content check
+	// The restore page offers the history.
+	restore := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// The button.
+	if !strings.Contains(restore, `action="/restore/history"`) || !strings.Contains(restore, "View history") {
+		// Report it.
+		t.Errorf("the restore page has no View history button")
+	} // end of the button check
+	// The history page.
+	page := bodyOf(post(t, rig.h, "/restore/history", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// The parameters and the facts, with the stop word escaped.
+	for _, want := range []string{"History of <code>alpha:1b</code>", "<code>temperature</code>", "<code>0.7</code>", "<code>num_ctx</code>", "<code>4096</code>", "&#34;&lt;end&gt;&#34;", "1.3 GB", names[0]} {
+		// Look for it.
+		if !strings.Contains(page, want) {
+			// Report the gap.
+			t.Errorf("the history page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// Nothing about other models.
+	empty := bodyOf(post(t, rig.h, "/restore/history", url.Values{"token": {rig.token}, "model": {"beta:7b"}}, fromThisPage))
+	// The honest empty page.
+	if !strings.Contains(empty, "No history was recorded for this model") {
+		// Report it.
+		t.Errorf("an unknown model should have no history: %s", empty)
+	} // end of the empty check
+} // end of TestDeleteSavesSnapshotFirst
+
+// TestDeleteWithoutSnapshotIsReported checks a failed snapshot is said plainly, and the confirmed delete still happens.
+func TestDeleteWithoutSnapshotIsReported(t *testing.T) {
+	// Ollama cannot tell the parameters.
+	rig, f, dir := delRig(t)
+	// Make show fail.
+	f.failShow = true
+	// Delete alpha.
+	body := bodyOf(post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// The honest note and the deletion.
+	if !strings.Contains(body, "No snapshot of its inference parameters was saved") || !strings.Contains(body, "Done.") || f.calls() != 1 {
+		// Report it.
+		t.Errorf("failed snapshot not reported, or the delete did not happen (calls %d): %s", f.calls(), body)
+	} // end of the check
+	// No file.
+	if n := snapFiles(t, filepath.Join(dir, historyDirName)); len(n) != 0 {
+		// Report it.
+		t.Errorf("files after a failed snapshot: %v", n)
+	} // end of the file check
+	// The folder cannot be created: a plain file sits where it should be.
+	rig2, f2, dir2 := delRig(t)
+	// Block the folder.
+	os.MkdirAll(dir2, 0o700)
+	// The blocker.
+	os.WriteFile(filepath.Join(dir2, historyDirName), []byte("x"), 0o600)
+	// Delete alpha.
+	body = bodyOf(post(t, rig2.h, "/delete/confirm", url.Values{"token": {rig2.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// Still deleted, with the reason.
+	if !strings.Contains(body, "No snapshot of its inference parameters was saved: the history folder could not be created") || f2.calls() != 1 {
+		// Report it.
+		t.Errorf("unwritable folder not reported: %s", body)
+	} // end of the unwritable check
+} // end of TestDeleteWithoutSnapshotIsReported
+
+// TestHistoryStoreRules checks file names, no overwriting, and what the listing ignores.
+func TestHistoryStoreRules(t *testing.T) {
+	// A private folder.
+	dir := filepath.Join(t.TempDir(), "history")
+	// The store.
+	h := &historyStore{dir: dir}
+	// One moment.
+	at := time.Date(2026, 10, 27, 17, 30, 0, 0, time.UTC)
+	// A hostile model name.
+	hostile := "../../etc/pass wd:1"
+	// Save twice in the same second.
+	a, err1 := h.save(paramSnapshot{Model: hostile, DeletedAt: at})
+	// The second.
+	b, err2 := h.save(paramSnapshot{Model: hostile, DeletedAt: at})
+	// Both must work and differ.
+	if err1 != nil || err2 != nil || a == b {
+		// Report it.
+		t.Fatalf("saves: %q %v / %q %v", a, err1, b, err2)
+	} // end of the save check
+	// Nothing may leave the folder, and the names hold no separators.
+	for _, n := range []string{a, b} {
+		// Check the name.
+		if strings.ContainsAny(n, "/\\:") || strings.HasPrefix(n, ".") {
+			// Report it.
+			t.Errorf("unsafe file name %q", n)
+		} // end of the name check
+		// The file is inside the folder.
+		if _, err := os.Stat(filepath.Join(dir, n)); err != nil {
+			// Report it.
+			t.Errorf("file %q is not in the folder", n)
+		} // end of the place check
+	} // end of the loop
+	// Nothing was written outside.
+	if _, err := os.Stat(filepath.Join(dir, "..", "..", "etc")); err == nil {
+		// Report it.
+		t.Errorf("a file escaped the folder")
+	} // end of the escape check
+	// Things the listing must ignore.
+	os.WriteFile(filepath.Join(dir, "notes.txt"), []byte("x"), 0o600)
+	// A damaged snapshot.
+	os.WriteFile(filepath.Join(dir, "bad"+snapshotSuffix), []byte("{no"), 0o600)
+	// An oversized one.
+	os.WriteFile(filepath.Join(dir, "big"+snapshotSuffix), []byte(strings.Repeat("a", maxSnapshotFile+5)), 0o600)
+	// Another version.
+	os.WriteFile(filepath.Join(dir, "v9"+snapshotSuffix), []byte(`{"version":9,"model":"`+hostile+`"}`), 0o600)
+	// A link to a file outside.
+	outside := filepath.Join(t.TempDir(), "o.json")
+	// Its content would match the model.
+	os.WriteFile(outside, []byte(`{"version":1,"model":"`+hostile+`"}`), 0o600)
+	// The link.
+	os.Symlink(outside, filepath.Join(dir, "link"+snapshotSuffix))
+	// Another model's snapshot.
+	h.save(paramSnapshot{Model: "other:1", DeletedAt: at})
+	// A newer snapshot of the hostile model.
+	h.save(paramSnapshot{Model: hostile, DeletedAt: at.Add(time.Hour), Digest: "newer"})
+	// List.
+	got := h.list(hostile)
+	// Three real snapshots, newest first.
+	if len(got) != 3 || got[0].Digest != "newer" {
+		// Report it.
+		t.Errorf("listing gave %d snapshots (want 3, newest first): %+v", len(got), got)
+	} // end of the list check
+	// A store without a folder saves nothing and lists nothing, and says why.
+	none := &historyStore{note: "no folder"}
+	// Save.
+	if _, err := none.save(paramSnapshot{Model: "x"}); err == nil || !strings.Contains(err.Error(), "no folder") {
+		// Report it.
+		t.Errorf("a store without a folder must refuse with its reason: %v", err)
+	} // end of the refuse check
+	// List.
+	if len(none.list("x")) != 0 {
+		// Report it.
+		t.Errorf("a store without a folder listed something")
+	} // end of the empty list check
+} // end of TestHistoryStoreRules
+
+// TestHistoryFolderStaysOutOfGitHub checks the .gitignore keeps the history folder out of the repository (requirement S4).
+func TestHistoryFolderStaysOutOfGitHub(t *testing.T) {
+	// Read the ignore file of the project.
+	data, err := os.ReadFile(".gitignore")
+	// It must exist.
+	if err != nil {
+		// Stop the test.
+		t.Fatalf("no .gitignore: %v", err)
+	} // end of the read check
+	// A line that ignores the folder.
+	ok := false
+	// Look at every line.
+	for _, l := range strings.Split(string(data), "\n") {
+		// The folder name with a slash.
+		if strings.TrimSpace(l) == historyDirName+"/" {
+			// Found.
+			ok = true
+		} // end of the line check
+	} // end of the loop
+	// Report a gap.
+	if !ok {
+		// Report it.
+		t.Errorf(".gitignore does not ignore %s/", historyDirName)
+	} // end of the ignore check
+} // end of TestHistoryFolderStaysOutOfGitHub
+
+// TestDefaultHistoryDir checks the folder choice: next to the program, one level above bin, with a fallback in the config folder.
+func TestDefaultHistoryDir(t *testing.T) {
+	// Keep and restore the two lookups.
+	oldExe, oldCfg := executablePath, userConfigDir
+	// Put them back afterwards.
+	t.Cleanup(func() { executablePath, userConfigDir = oldExe, oldCfg })
+	// A program inside bin.
+	executablePath = func() (string, error) { return "/p/OllamaControlCenter/bin/occ", nil }
+	// The folder.
+	if d, _ := defaultHistoryDir(); d != filepath.Join("/p/OllamaControlCenter", "history") {
+		// Report it.
+		t.Errorf("bin case gave %q", d)
+	} // end of the bin check
+	// A program elsewhere.
+	executablePath = func() (string, error) { return "/p/occ", nil }
+	// The folder.
+	if d, _ := defaultHistoryDir(); d != filepath.Join("/p", "history") {
+		// Report it.
+		t.Errorf("plain case gave %q", d)
+	} // end of the plain check
+	// Unknown program place: the config folder.
+	executablePath = func() (string, error) { return "", http.ErrNotSupported }
+	// A config folder.
+	userConfigDir = func() (string, error) { return "/cfg", nil }
+	// The folder.
+	if d, _ := defaultHistoryDir(); d != filepath.Join("/cfg", "OllamaControlCenter", "history") {
+		// Report it.
+		t.Errorf("fallback gave %q", d)
+	} // end of the fallback check
+	// Nothing at all.
+	userConfigDir = func() (string, error) { return "", http.ErrNotSupported }
+	// The folder and the reason.
+	if d, note := defaultHistoryDir(); d != "" || note == "" {
+		// Report it.
+		t.Errorf("no-folder case gave %q, %q", d, note)
+	} // end of the none check
+} // end of TestDefaultHistoryDir
diff --git a/web.go b/web.go
index 9c92dc2..869bd1d 100644
--- a/web.go
+++ b/web.go
@@ -121,8 +121,12 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	perfHistory := openPerfStore(histPath, histNote)
 	// The deleted models are remembered in a small file next to the history (kept out of GitHub by .gitignore).
 	deletedList := openDeletedStore(deletedPathFor(histPath))
-	// The five delete and restore handlers.
-	delAsk, delConfirm, delForce, restoreInfo, restoreForget := deleteHandlers(addr, token, deletedList)
+	// The folder for the snapshots of deleted models' parameters ("history" next to the program, kept out of GitHub by .gitignore).
+	histDir, histDirNote := defaultHistoryDir()
+	// The snapshot store.
+	historyDir := &historyStore{dir: histDir, note: histDirNote}
+	// The six delete and restore handlers.
+	delAsk, delConfirm, delForce, restoreInfo, restoreForget, restoreHistory := deleteHandlers(addr, token, deletedList, historyDir)
 	// The first delete step: shows the warning, changes nothing.
 	mux.HandleFunc("POST /delete", delAsk)
 	// The second step for a model that is not loaded.
@@ -133,6 +137,8 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	mux.HandleFunc("POST /restore", restoreInfo)
 	// Remove a greyed row.
 	mux.HandleFunc("POST /restore/forget", restoreForget)
+	// The read-only list of parameter snapshots of a deleted model.
+	mux.HandleFunc("POST /restore/history", restoreHistory)
 	// The four handlers of the performance pages.
 	perfStart, perfRun, perfClearAsk, perfClearDo := perfHandlers(addr, token, perfHistory)
 	// Route: a POST request for "/performance" shows the performance page and changes nothing.
diff --git a/web/delete.html b/web/delete.html
index 5c5f05e..1b9fd8d 100644
--- a/web/delete.html
+++ b/web/delete.html
@@ -27,6 +27,8 @@
 {{if .LibText}}<p class="{{if eq .LibClass "ok"}}goodnote{{else}}warn{{end}}" role="{{if eq .LibClass "ok"}}status{{else}}alert{{end}}">{{.LibText}}</p>{{end}}
 {{/* The loss of tuning gets its own box, because it is the part people forget. */}}
 <div class="lossbox" role="alert"><strong>You lose your tuning.</strong> Inference parameters you changed here are deleted with the model. A restored model comes back with the default parameters, so you must tune it again.</div>
+{{/* What will be kept about the model's inference parameters. */}}
+{{if .SnapText}}<p class="{{if eq .SnapClass "ok"}}goodnote{{else}}warn{{end}}">{{.SnapText}}</p>{{end}}
 {{/* The consequences, one by one. */}}
 <ul>
 {{/* Disk space. */}}
@@ -67,6 +69,8 @@
 {{if .LibText}}<p class="{{if eq .LibClass "ok"}}goodnote{{else}}warn{{end}}" role="{{if eq .LibClass "ok"}}status{{else}}alert{{end}}">{{.LibText}}</p>{{end}}
 {{/* The loss of tuning gets its own box, because it is the part people forget. */}}
 <div class="lossbox" role="alert"><strong>You lose your tuning.</strong> Inference parameters you changed here are deleted with the model. A restored model comes back with the default parameters, so you must tune it again.</div>
+{{/* What will be kept about the model's inference parameters. */}}
+{{if .SnapText}}<p class="{{if eq .SnapClass "ok"}}goodnote{{else}}warn{{end}}">{{.SnapText}}</p>{{end}}
 {{/* What the monitor can and cannot see. */}}
 <p>This monitor cannot see whether an application is using it at this moment. Deleting a model that is in use can make that application fail or behave unexpectedly.</p>
 {{/* What happens by itself. */}}
@@ -103,6 +107,9 @@
 <p><strong>Done.</strong> Ollama no longer lists this model, and about {{.SizeText}} of disk space is free again.</p>
 {{/* A problem with the memory file, if any. */}}
 {{if .Note}}<p class="warn" role="alert">{{.Note}}</p>{{end}}
+{{/* Whether the parameter snapshot was kept. */}}
+{{if .SnapFile}}<p class="goodnote">A snapshot of its inference parameters was saved in the history folder: <code>{{.SnapFile}}</code></p>{{end}}
+{{if .SnapErr}}<p class="warn" role="alert">No snapshot of its inference parameters was saved: {{.SnapErr}}</p>{{end}}
 {{/* How to get it back. */}}
 <p class="muted">It stays in the table, greyed out, with a Restore icon.</p>
 {{/* A link back. */}}
@@ -148,6 +155,16 @@
 <div class="choices">
 {{/* Back. */}}
 <a class="btn-load" href="/">Back to the monitor</a>
+{{/* The history form only shows what was kept; it changes nothing. */}}
+<form method="post" action="/restore/history">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* The model name. */}}
+<input type="hidden" name="model" value="{{.Model}}">
+{{/* The button. */}}
+<button type="submit" class="btn-plain">View history (inference parameters it had)</button>
+{{/* End of the history form. */}}
+</form>
 {{/* The forget form removes the greyed row without touching Ollama. */}}
 <form method="post" action="/restore/forget">
 {{/* The page token proves the form comes from this monitor. */}}
@@ -160,6 +177,40 @@
 </form>
 {{/* End of the choices. */}}
 </div>
+{{/* Version 5b: the history of a deleted model (read-only). */}}
+{{else if eq .Kind "history"}}
+{{/* The heading names the model. */}}
+<h1>History of <code>{{.Model}}</code></h1>
+{{if .Snaps}}
+{{/* One block per snapshot, newest first. */}}
+<p class="muted">Taken when the model was deleted. This is a record only; nothing here changes Ollama.</p>
+{{range .Snaps}}
+<h2>Deleted on {{.When}}</h2>
+<p class="muted">Size then {{.SizeText}}. Fingerprint then <code>{{.Digest}}</code>. Kept in <code>history/{{.File}}</code></p>
+{{if .Params}}
+<table class="cmds">
+<thead><tr><th scope="col">Inference parameter</th><th scope="col">Value</th></tr></thead>
+<tbody>
+{{range .Params}}<tr><th scope="row"><code>{{.Name}}</code></th><td><code>{{.Value}}</code></td></tr>
+{{end}}</tbody>
+</table>
+{{else}}
+<p>No inference parameters were set on this model.</p>
+{{end}}
+{{end}}
+{{else}}
+{{/* Nothing kept. */}}
+<p>No history was recorded for this model. It was deleted before the history existed, or no snapshot could be saved.</p>
+{{end}}
+{{/* The choices. */}}
+<div class="choices">
+<a class="btn-load" href="/">Back to the monitor</a>
+<form method="post" action="/restore">
+<input type="hidden" name="token" value="{{.Token}}">
+<input type="hidden" name="model" value="{{.Model}}">
+<button type="submit" class="btn-plain">Back to Restore</button>
+</form>
+</div>
 {{/* Version 6: the greyed row was removed or is unknown. */}}
 {{else if eq .Kind "forgotten"}}
 {{/* The heading names the model. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
fee7c36cbf681e427a11013abdf7d8bd8a8f3bef49c893b7e2995a1918b3f06f  delete.go
8deda1708bc13587f89127f63dfdf14d5b30696b95de7571b13663a2bd52aa91  delete_test.go
826460987e856f80167ff935fcebe8cb1498d93a7bfeb336457310c3fe7f6fdb  history.go
a3bf1167bde5882a4c4a0dfa60fc247d138f599bdcb322a9b50ef1a62ca45d0f  history_test.go
1553088adb8016addb519d17b96154581ea149c84b04576a663b5b448fe44ab4  web.go
dbd87ac4957c0e69c30a1db28d3979ee252f92e40b656904cd93ee66b76882e4  web/delete.html
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
# List the changed files; nothing is committed yet.
git status --short
