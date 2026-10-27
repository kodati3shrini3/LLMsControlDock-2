#!/usr/bin/env bash
# Script 57: delete a model (trash icon under the performance icon, warning page, Hold / Force delete for a loaded model), greyed "Deleted models" rows that are remembered in a file outside GitHub, and a restore page (manual "ollama pull" for now).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/delete-model" ] || { echo "FAIL  not on feature/delete-model"; exit 1; }
# Script 56 must be applied first (it adds the box around the key).
grep -q 'var(--bg)' web/app.css && grep -q '^\.legend {' web/app.css && grep -q 'border: 2px solid var(--border)' web/app.css || { echo "FAIL  script 56 (key box) is not in this branch yet"; exit 1; }
# Refuse to run twice.
if [ -e delete.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/control_test.go b/control_test.go
index 8d23f9e..c3fc584 100644
--- a/control_test.go
+++ b/control_test.go
@@ -387,21 +387,21 @@ func TestKeyAndDrawnIcons(t *testing.T) {
 			t.Errorf("the page still contains %q", bad)
 		} // end of the character check
 	} // end of the loop
-	// The key names all six things.
-	for _, want := range []string{"Modelfile</strong>", "Inference parameters</strong>", "Performance</strong>", "Compare tested models</strong>", "Dotted headings</strong>", "Sideways scroll</strong>", `class="legend muted"`} {
+	// The key names all seven things.
+	for _, want := range []string{"Modelfile</strong>", "Inference parameters</strong>", "Performance</strong>", "Delete</strong>", "Compare tested models</strong>", "Dotted headings</strong>", "Sideways scroll</strong>", `class="legend muted"`} {
 		// Look for it.
 		if !strings.Contains(body, want) {
 			// Report the gap.
 			t.Errorf("the key lacks %q", want)
 		} // end of the check
 	} // end of the loop
-	// Six entries in the key.
-	if n := strings.Count(body, `<li><span class="sym">`); n != 6 {
+	// Seven entries in the key.
+	if n := strings.Count(body, `<li><span class="sym">`); n != 7 {
 		// Report it.
-		t.Errorf("the key has %d entries, want 6", n)
+		t.Errorf("the key has %d entries, want 7", n)
 	} // end of the count check
-	// The two reading hints come first in the key, then the four icon explanations.
-	order := []string{"Dotted headings</strong>", "Sideways scroll</strong>", "Modelfile</strong>", "Inference parameters</strong>", "Performance</strong>", "Compare tested models</strong>"}
+	// The two reading hints come first in the key, then the five icon explanations.
+	order := []string{"Dotted headings</strong>", "Sideways scroll</strong>", "Modelfile</strong>", "Inference parameters</strong>", "Performance</strong>", "Delete</strong>", "Compare tested models</strong>"}
 	// Walk the list and make sure each entry comes after the one before.
 	last := -1
 	// Each entry.
diff --git a/delete.go b/delete.go
new file mode 100644
index 0000000..ba35352
--- /dev/null
+++ b/delete.go
@@ -0,0 +1,354 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes holds the finished page.
+	"bytes"
+	// context lets a request be cancelled or given a deadline.
+	"context"
+	// embed lets the delete page template be stored inside the executable (the blank name means we only need its side effect).
+	_ "embed"
+	// fmt builds formatted text.
+	"fmt"
+	// html/template builds HTML and escapes every inserted value.
+	"html/template"
+	// log prints messages to the terminal.
+	"log"
+	// net/http provides requests and status codes.
+	"net/http"
+	// net/url holds the parsed address type.
+	"net/url"
+	// time provides durations and the deletion stamp.
+	"time"
+) // end of imports
+
+// deleteTemplateText is the delete page template, stored inside the executable at build time.
+//
+//go:embed web/delete.html
+var deleteTemplateText string
+
+// deleteTimeout is how long the delete request may take; removing a big model's files can take a moment.
+const deleteTimeout = 30 * time.Second
+
+// deleteModel asks Ollama to remove one model from the disk (the documented DELETE /api/delete request).
+func deleteModel(ctx context.Context, base *url.URL, name string, timeout time.Duration) error {
+	// Send the request with the DELETE method.
+	status, err := sendJSON(ctx, http.MethodDelete, base, "api/delete", timeout, map[string]any{"model": name})
+	// No answer at all.
+	if err != nil {
+		// Pass the safe error on.
+		return err
+	} // end of the send check
+	// Status 200 means Ollama removed it.
+	if status == http.StatusOK {
+		// Done.
+		return nil
+	} // end of the success case
+	// Status 404 means Ollama does not know the name (it may have been removed by someone else a moment ago).
+	if status == http.StatusNotFound {
+		// Say so in words.
+		return fmt.Errorf("Ollama does not have a model with this name (status 404)")
+	} // end of the 404 case
+	// Any other status.
+	return fmt.Errorf("Ollama answered the delete request with status %d", status)
+} // end of deleteModel
+
+// deletePage is everything the delete page template can show.
+type deletePage struct {
+	// Kind says which version of the page to draw: confirm, busy, done, gone, restore, forgotten, error.
+	Kind string
+	// Model is the model name.
+	Model string
+	// SizeText is the size on disk in words, for example "4.7 GB".
+	SizeText string
+	// When is the deletion time in words (restore page).
+	When string
+	// Digest is the model's fingerprint as remembered (restore page).
+	Digest string
+	// Remaining is the time left before Ollama unloads the model by itself (busy page).
+	Remaining string
+	// Seconds is the same time in seconds, for the ticking timer; 0 means no ticking timer.
+	Seconds int
+	// Mismatch is true when the typed name did not match (busy page after a failed force delete).
+	Mismatch bool
+	// Detail is the plain reason shown on the error page.
+	Detail string
+	// Note carries a warning that does not stop the work (for example, the list could not be saved).
+	Note string
+	// Theme is the saved theme choice, as on the main page.
+	Theme string
+	// Token is the page token for the forms on this page.
+	Token string
+} // end of deletePage
+
+// deleteHandlers builds the handlers: ask (changes nothing), confirm, force, restore (information only) and forget.
+func deleteHandlers(addr ollamaAddress, token string, store *deletedStore) (ask, confirm, force, restore, forget http.HandlerFunc) {
+	// Read the template once; Must stops the program at start-up if the template is broken, which a test would catch first.
+	page := template.Must(template.New("delete").Parse(deleteTemplateText))
+	// readForm runs the checks that all handlers share and returns the model name; ok is false when a refusal was already sent.
+	readForm := func(w http.ResponseWriter, r *http.Request) (string, bool) {
+		// Never read more than 2 KB of form data; the real forms are tiny.
+		r.Body = http.MaxBytesReader(w, r.Body, 2048)
+		// Only a form on this very page may send this request (requirement S2).
+		if !sameOrigin(r) {
+			// Refuse.
+			http.Error(w, "request did not come from this page", http.StatusForbidden)
+			// Stop here.
+			return "", false
+		} // end of the origin check
+		// Read the form fields.
+		if err := r.ParseForm(); err != nil {
+			// A broken or too large form.
+			http.Error(w, "bad form", http.StatusBadRequest)
+			// Stop here.
+			return "", false
+		} // end of the form check
+		// The token proves the form came from a page this monitor made.
+		if !tokenValid(token, r.PostFormValue("token")) {
+			// Refuse.
+			http.Error(w, "bad token", http.StatusForbidden)
+			// Stop here.
+			return "", false
+		} // end of the token check
+		// The model name must be present and not absurdly long.
+		name := r.PostFormValue("model")
+		// Check the name.
+		if name == "" || len(name) > maxModelNameLen {
+			// Refuse.
+			http.Error(w, "bad model name", http.StatusBadRequest)
+			// Stop here.
+			return "", false
+		} // end of the name check
+		// All checks passed.
+		return name, true
+	} // end of readForm
+	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
+	show := func(w http.ResponseWriter, r *http.Request, status int, data deletePage) {
+		// Add what every version of the page needs.
+		data.Theme, data.Token = themeFromRequest(r), token
+		// Build the page.
+		var buf bytes.Buffer
+		// Run the template.
+		if err := page.Execute(&buf, data); err != nil {
+			// Log the real reason for the person running the program.
+			log.Printf("delete page error: %v", err)
+			// Send a plain 500 without details.
+			http.Error(w, "internal error", http.StatusInternalServerError)
+			// Stop here.
+			return
+		} // end of the template check
+		// A page with a ticking timer may run the monitor's own script, and nothing else.
+		if data.Seconds > 0 {
+			// Replace the strict policy by the one that allows the script file.
+			w.Header().Set("Content-Security-Policy", contentSecurityPolicyWithScript)
+		} // end of the script policy
+		// Tell the browser this is an HTML page.
+		w.Header().Set("Content-Type", "text/html; charset=utf-8")
+		// Send the status line.
+		w.WriteHeader(status)
+		// Send the finished page.
+		w.Write(buf.Bytes())
+	} // end of show
+	// busyPage fills the "model is loaded, it may be in use" version, with the time left before Ollama unloads it by itself.
+	busyPage := func(name string, size int64, l loadedModel, mismatch bool) deletePage {
+		// Work out the time left.
+		exp, expOK := l.expiresTime()
+		// Build the page data.
+		return deletePage{Kind: "busy", Model: name, SizeText: formatSize(size), Remaining: remainingText(time.Now(), exp, expOK), Seconds: remainingSeconds(time.Now(), exp, expOK), Mismatch: mismatch}
+	} // end of busyPage
+	// look asks Ollama, right now, what is installed and what is loaded; the loaded entry has an empty name when the model is not loaded. It shows the error or "gone" page itself when it cannot go on, and then returns false.
+	look := func(w http.ResponseWriter, r *http.Request, name string) (installedModel, loadedModel, bool) {
+		// What is installed.
+		inst, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
+		// Ollama could not be read.
+		if err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusBadGateway, deletePage{Kind: "error", Model: name, Detail: err.Error()})
+			// Stop here.
+			return installedModel{}, loadedModel{}, false
+		} // end of the installed check
+		// What is loaded.
+		ld, err := fetchLoaded(r.Context(), addr.URL, defaultCheckTimeout)
+		// Ollama could not be read.
+		if err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusBadGateway, deletePage{Kind: "error", Model: name, Detail: err.Error()})
+			// Stop here.
+			return installedModel{}, loadedModel{}, false
+		} // end of the loaded check
+		// The model, if it is installed.
+		m, found := findInstalled(inst, name)
+		// It is not installed (any more): say so, with no delete button.
+		if !found {
+			// Show that page.
+			show(w, r, http.StatusOK, deletePage{Kind: "gone", Model: name})
+			// Stop here.
+			return installedModel{}, loadedModel{}, false
+		} // end of the installed case
+		// The loaded entry, if it is loaded (the zero value otherwise).
+		l, _ := findLoaded(ld, name)
+		// Hand back the facts and say no page has been sent yet.
+		return m, l, true
+	} // end of look
+	// doDelete deletes, checks that the model is really gone, remembers it, and shows the result page.
+	doDelete := func(w http.ResponseWriter, r *http.Request, m installedModel) {
+		// Ask Ollama to delete it.
+		if err := deleteModel(r.Context(), addr.URL, m.Name, deleteTimeout); err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusBadGateway, deletePage{Kind: "error", Model: m.Name, Detail: err.Error()})
+			// Stop here.
+			return
+		} // end of the delete check
+		// Do not trust the 200 alone: ask Ollama whether the model is still installed.
+		inst, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
+		// The list could not be read afterwards.
+		if err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusBadGateway, deletePage{Kind: "error", Model: m.Name, Detail: err.Error()})
+			// Stop here.
+			return
+		} // end of the verify check
+		// Still listed: say so honestly.
+		if _, still := findInstalled(inst, m.Name); still {
+			// Show the plain reason.
+			show(w, r, http.StatusOK, deletePage{Kind: "error", Model: m.Name, Detail: "Ollama accepted the request, but the model is still listed. Reload the monitor page in a moment to check."})
+			// Stop here.
+			return
+		} // end of the still-listed case
+		// Remember it, so the table can show it greyed out and Restore can offer it again.
+		note := ""
+		// Save; a failure does not undo the deletion, it only means the ghost row will be missing.
+		if err := store.add(deletedModel{Name: m.Name, Digest: m.Digest, Size: m.Size, DeletedAt: time.Now()}); err != nil {
+			// Say so in words.
+			note = "The model is deleted, but this monitor could not remember it, so there will be no Restore row. " + err.Error()
+		} // end of the save check
+		// Done.
+		show(w, r, http.StatusOK, deletePage{Kind: "done", Model: m.Name, SizeText: formatSize(m.Size), Note: note})
+	} // end of doDelete
+	// ask is the first step: it re-checks Ollama and shows the right warning; it never deletes anything.
+	ask = func(w http.ResponseWriter, r *http.Request) {
+		// Run the shared checks.
+		name, ok := readForm(w, r)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the checks
+		// Ask Ollama what is installed and loaded right now.
+		m, l, ok := look(w, r, name)
+		// A page was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the look check
+		// Loaded means it may be in use: Hold or Force delete.
+		if l.Name == name {
+			// Show the busy version.
+			show(w, r, http.StatusOK, busyPage(name, m.Size, l, false))
+			// Stop here.
+			return
+		} // end of the loaded case
+		// Not loaded: the normal warning.
+		show(w, r, http.StatusOK, deletePage{Kind: "confirm", Model: name, SizeText: formatSize(m.Size)})
+	} // end of ask
+	// confirm is the second step for a model that is not loaded; if it has been loaded meanwhile, it goes back to the busy version.
+	confirm = func(w http.ResponseWriter, r *http.Request) {
+		// Run the shared checks.
+		name, ok := readForm(w, r)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the checks
+		// Look again.
+		m, l, ok := look(w, r, name)
+		// A page was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the look check
+		// Loaded in the meantime: this button must not delete it.
+		if l.Name == name {
+			// Show the busy version.
+			show(w, r, http.StatusOK, busyPage(name, m.Size, l, false))
+			// Stop here.
+			return
+		} // end of the loaded case
+		// Delete it.
+		doDelete(w, r, m)
+	} // end of confirm
+	// force deletes a model that is loaded, but only when its exact name was typed.
+	force = func(w http.ResponseWriter, r *http.Request) {
+		// Run the shared checks.
+		name, ok := readForm(w, r)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the checks
+		// Look again.
+		m, l, ok := look(w, r, name)
+		// A page was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the look check
+		// The typed name must match exactly.
+		if r.PostFormValue("typed") != name {
+			// Show the busy version again with a note; if it is no longer loaded, show the normal warning.
+			if l.Name == name {
+				// Busy again.
+				show(w, r, http.StatusOK, busyPage(name, m.Size, l, true))
+			} else { // the other case
+				// Normal warning.
+				show(w, r, http.StatusOK, deletePage{Kind: "confirm", Model: name, SizeText: formatSize(m.Size)})
+			} // end of the loaded check
+			// Stop here.
+			return
+		} // end of the name check
+		// Delete it.
+		doDelete(w, r, m)
+	} // end of force
+	// restore (Phase 1) only explains how to bring a deleted model back; it changes nothing.
+	restore = func(w http.ResponseWriter, r *http.Request) {
+		// Run the shared checks.
+		name, ok := readForm(w, r)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the checks
+		// The monitor must remember this name.
+		d, found := store.find(name)
+		// Unknown name.
+		if !found {
+			// Say so.
+			show(w, r, http.StatusOK, deletePage{Kind: "forgotten", Model: name})
+			// Stop here.
+			return
+		} // end of the unknown case
+		// Show the information page.
+		show(w, r, http.StatusOK, deletePage{Kind: "restore", Model: d.Name, SizeText: formatSize(d.Size), Digest: d.Digest, When: d.DeletedAt.Local().Format("2 Jan 2006 15:04 MST")})
+	} // end of restore
+	// forget removes the greyed row, without touching Ollama.
+	forget = func(w http.ResponseWriter, r *http.Request) {
+		// Run the shared checks.
+		name, ok := readForm(w, r)
+		// A refusal was already sent.
+		if !ok {
+			// Stop here.
+			return
+		} // end of the checks
+		// Remove it from the list.
+		if err := store.forget(name); err != nil {
+			// Show the plain reason.
+			show(w, r, http.StatusInternalServerError, deletePage{Kind: "error", Model: name, Detail: err.Error()})
+			// Stop here.
+			return
+		} // end of the save check
+		// Done.
+		show(w, r, http.StatusOK, deletePage{Kind: "forgotten", Model: name})
+	} // end of forget
+	// Hand all five back (they are the named results).
+	return
+} // end of deleteHandlers
diff --git a/delete_test.go b/delete_test.go
new file mode 100644
index 0000000..cdca480
--- /dev/null
+++ b/delete_test.go
@@ -0,0 +1,579 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// encoding/json builds the fake Ollama replies.
+	"encoding/json"
+	// net/http provides status codes and the handler type.
+	"net/http"
+	// net/url builds form values.
+	"net/url"
+	// os reads the saved file.
+	"os"
+	// path/filepath builds the file path.
+	"path/filepath"
+	// sort keeps the fake's reply stable.
+	"sort"
+	// strings searches the pages.
+	"strings"
+	// sync protects the fake's state.
+	"sync"
+	// testing is Go's test framework.
+	"testing"
+	// time stamps the fake models.
+	"time"
+) // end of imports
+
+// delFake is a fake Ollama that really removes models when asked, so the tests can see the whole delete flow.
+type delFake struct {
+	// mu protects the fields below.
+	mu sync.Mutex
+	// sizes maps each installed model name to its size.
+	sizes map[string]int64
+	// loaded is the set of loaded model names.
+	loaded map[string]bool
+	// deleteCalls counts DELETE /api/delete requests.
+	deleteCalls int
+	// failDelete makes the delete request answer with a server error.
+	failDelete bool
+	// keepAfterDelete makes Ollama answer 200 but keep the model (to test the check afterwards).
+	keepAfterDelete bool
+} // end of delFake
+
+// start runs the fake and returns its address.
+func (f *delFake) start(t *testing.T) string {
+	// Mark this as a helper.
+	t.Helper()
+	// The server.
+	srv := fakeOllama(t, func(w http.ResponseWriter, r *http.Request) {
+		// One request at a time.
+		f.mu.Lock()
+		// Release at the end.
+		defer f.mu.Unlock()
+		// Every reply is JSON.
+		w.Header().Set("Content-Type", "application/json")
+		// Choose by path.
+		switch r.URL.Path {
+		// The version, used by the main page check.
+		case "/api/version":
+			// A version.
+			w.Write([]byte(`{"version":"0.34.4"}`))
+		// The installed models.
+		case "/api/tags":
+			// Stable order.
+			var names []string
+			// Collect the names.
+			for n := range f.sizes {
+				// Add it.
+				names = append(names, n)
+			} // end of the loop
+			// Sort them.
+			sort.Strings(names)
+			// Build the list.
+			var list []map[string]any
+			// One entry per model.
+			for _, n := range names {
+				// The fields the monitor reads.
+				list = append(list, map[string]any{"name": n, "model": n, "size": f.sizes[n], "digest": "sha256:" + n, "modified_at": time.Now().Format(time.RFC3339), "details": map[string]any{"family": "test", "parameter_size": "1B", "quantization_level": "Q4"}})
+			} // end of the loop
+			// Send it.
+			json.NewEncoder(w).Encode(map[string]any{"models": list})
+		// The loaded models.
+		case "/api/ps":
+			// Build the list.
+			var list []map[string]any
+			// One entry per loaded model.
+			for n := range f.loaded {
+				// The fields the monitor reads.
+				list = append(list, map[string]any{"name": n, "model": n, "size": f.sizes[n], "expires_at": time.Now().Add(90 * time.Minute).Format(time.RFC3339)})
+			} // end of the loop
+			// Send it.
+			json.NewEncoder(w).Encode(map[string]any{"models": list})
+		// The delete request.
+		case "/api/delete":
+			// It must be a DELETE.
+			if r.Method != http.MethodDelete {
+				// Refuse like Ollama would.
+				w.WriteHeader(http.StatusMethodNotAllowed)
+				// Stop.
+				return
+			} // end of the method check
+			// Count it.
+			f.deleteCalls++
+			// A failing server.
+			if f.failDelete {
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
+			// Remove it, unless the fake should pretend.
+			if !f.keepAfterDelete {
+				// Gone from disk.
+				delete(f.sizes, req.Model)
+				// Gone from memory too.
+				delete(f.loaded, req.Model)
+			} // end of the removal
+			// Success.
+			w.WriteHeader(http.StatusOK)
+		// Anything else.
+		default:
+			// Not found.
+			w.WriteHeader(http.StatusNotFound)
+		} // end of the switch
+	}) // end of the server
+	// Hand back the address.
+	return srv.URL
+} // end of start
+
+// delRig builds the monitor against a fake with two installed models (one loaded) and returns the rig, the fake and the folder of the saved files.
+func delRig(t *testing.T) (themeRig, *delFake, string) {
+	// Mark this as a helper.
+	t.Helper()
+	// Fixed machine facts.
+	quietMachine(t)
+	// A private folder for the saved files.
+	dir := t.TempDir()
+	// Use it as the config folder (the tests never learn the program's own path).
+	old := userConfigDir
+	// The replacement.
+	userConfigDir = func() (string, error) { return dir, nil }
+	// Put it back afterwards.
+	t.Cleanup(func() { userConfigDir = old })
+	// The fake with its models.
+	f := &delFake{sizes: map[string]int64{"alpha:1b": 1300000000, "beta:7b": 4700000000}, loaded: map[string]bool{"beta:7b": true}}
+	// The monitor.
+	h := handlerFor(t, f.start(t))
+	// Read the main page to learn the token.
+	_, _, body := get(t, h, http.MethodGet, "/")
+	// Find the token.
+	i := strings.Index(body, `name="token" value="`)
+	// The page must carry one.
+	if i < 0 {
+		// Stop the test.
+		t.Fatalf("no token found in the page")
+	} // end of the token check
+	// The token is 32 characters.
+	tok := body[i+len(`name="token" value="`) : i+len(`name="token" value="`)+32]
+	// Hand back everything.
+	return themeRig{h: h, token: tok}, f, filepath.Join(dir, "OllamaControlCenter")
+} // end of delRig
+
+// calls returns the number of delete requests so far.
+func (f *delFake) calls() int {
+	// One at a time.
+	f.mu.Lock()
+	// Release at the end.
+	defer f.mu.Unlock()
+	// The number.
+	return f.deleteCalls
+} // end of calls
+
+// TestDeleteIconsInTable checks that every model row has the delete form, below the performance icon, and that a loaded row keeps an empty slot for the performance icon.
+func TestDeleteIconsInTable(t *testing.T) {
+	// The rig.
+	rig, _, _ := delRig(t)
+	// The main page.
+	_, _, body := get(t, rig.h, http.MethodGet, "/")
+	// One delete form per model.
+	if n := strings.Count(body, `action="/delete"`); n != 2 {
+		// Report it.
+		t.Errorf("%d delete forms, want 2", n)
+	} // end of the count check
+	// The tooltip text.
+	if !strings.Contains(body, "Delete this model from this computer (it asks first)") {
+		// Report it.
+		t.Errorf("the delete tooltip is missing")
+	} // end of the tip check
+	// In the alpha row the performance form comes before the delete form.
+	row := body[strings.Index(body, `data-model="alpha:1b"`):]
+	// Where the two forms are.
+	perf, del := strings.Index(row, `action="/performance"`), strings.Index(row, `action="/delete"`)
+	// The order.
+	if perf < 0 || del < 0 || perf > del {
+		// Report it.
+		t.Errorf("performance form at %d, delete form at %d: delete must come below performance", perf, del)
+	} // end of the order check
+	// The loaded row has no performance form but still a delete form.
+	loaded := body[strings.Index(body, `data-model="beta:7b"`):]
+	// Cut at the end of the row.
+	loaded = loaded[:strings.Index(loaded, "</tr>")]
+	// No performance form there.
+	if strings.Contains(loaded, `action="/performance"`) {
+		// Report it.
+		t.Errorf("a loaded model must not offer the performance icon")
+	} // end of the loaded check
+	// But a delete form.
+	if !strings.Contains(loaded, `action="/delete"`) {
+		// Report it.
+		t.Errorf("a loaded model must still offer the delete icon")
+	} // end of the delete check
+} // end of TestDeleteIconsInTable
+
+// TestDeleteWarningChangesNothing checks the first step shows the warning and deletes nothing.
+func TestDeleteWarningChangesNothing(t *testing.T) {
+	// The rig.
+	rig, f, _ := delRig(t)
+	// Ask about the model that is not loaded.
+	res := post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
+	// The page.
+	body := bodyOf(res)
+	// It must be a normal page.
+	if res.StatusCode != http.StatusOK {
+		// Report it.
+		t.Fatalf("status %d", res.StatusCode)
+	} // end of the status check
+	// The warning words and both choices.
+	for _, want := range []string{"This removes the model from this computer", "1.3 GB", "Restore", "Yes, delete it", "No, keep it", `action="/delete/confirm"`} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("the warning page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// No force form for a model that is not in use.
+	if strings.Contains(body, "/delete/force") {
+		// Report it.
+		t.Errorf("the plain warning must not offer force delete")
+	} // end of the force check
+	// Nothing was deleted.
+	if f.calls() != 0 {
+		// Report it.
+		t.Errorf("%d delete requests after only asking", f.calls())
+	} // end of the call check
+} // end of TestDeleteWarningChangesNothing
+
+// TestDeleteBusyPage checks a loaded model gets the Hold / Force version and nothing is deleted.
+func TestDeleteBusyPage(t *testing.T) {
+	// The rig.
+	rig, f, _ := delRig(t)
+	// Ask about the loaded model.
+	res := post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"beta:7b"}}, fromThisPage)
+	// The page.
+	body := bodyOf(res)
+	// The words that matter.
+	for _, want := range []string{"loaded right now, so it may be in use", "Hold: do not delete", "Force delete", `action="/delete/force"`, `name="typed"`, "unloads this model by itself in"} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report the gap.
+			t.Errorf("the busy page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// The plain confirm form must not be there.
+	if strings.Contains(body, "/delete/confirm") {
+		// Report it.
+		t.Errorf("a loaded model must not get the one-click confirm form")
+	} // end of the confirm check
+	// The ticking timer needs the script policy.
+	if !strings.Contains(res.Header.Get("Content-Security-Policy"), "script-src 'self'") {
+		// Report it.
+		t.Errorf("the busy page has a timer but no script policy: %q", res.Header.Get("Content-Security-Policy"))
+	} // end of the policy check
+	// Nothing was deleted.
+	if f.calls() != 0 {
+		// Report it.
+		t.Errorf("%d delete requests after only asking", f.calls())
+	} // end of the call check
+} // end of TestDeleteBusyPage
+
+// TestDeleteConfirmDeletesAndRemembers checks the full flow: delete, verify, remember in a private file, greyed row, restore page, forget.
+func TestDeleteConfirmDeletesAndRemembers(t *testing.T) {
+	// The rig.
+	rig, f, dir := delRig(t)
+	// Confirm the deletion.
+	res := post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
+	// The page.
+	body := bodyOf(res)
+	// It says done.
+	if res.StatusCode != http.StatusOK || !strings.Contains(body, "Deleted <code>alpha:1b</code>") || !strings.Contains(body, "Done.") {
+		// Report it.
+		t.Fatalf("unexpected result page (status %d): %s", res.StatusCode, body)
+	} // end of the done check
+	// Exactly one request reached Ollama.
+	if f.calls() != 1 {
+		// Report it.
+		t.Errorf("%d delete requests, want 1", f.calls())
+	} // end of the call check
+	// The file exists and only the owner may read it.
+	info, err := os.Stat(filepath.Join(dir, deletedFileName))
+	// It must exist.
+	if err != nil {
+		// Stop the test.
+		t.Fatalf("no deleted-models file: %v", err)
+	} // end of the file check
+	// Owner only.
+	if info.Mode().Perm() != 0o600 {
+		// Report it.
+		t.Errorf("file mode %o, want 600", info.Mode().Perm())
+	} // end of the mode check
+	// The main page now shows the greyed row with a restore form, and the model is not in the installed rows.
+	_, _, page := get(t, rig.h, http.MethodGet, "/")
+	// The things that must be there.
+	for _, want := range []string{`data-deleted="alpha:1b"`, "<s>alpha:1b</s>", `action="/restore"`, "Restore: how to download this model again", "Deleted models", "1.3 GB"} {
+		// Look for it.
+		if !strings.Contains(page, want) {
+			// Report the gap.
+			t.Errorf("the main page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// The ghost row must not carry data-model (the refresh script compares those).
+	if strings.Contains(page, `data-model="alpha:1b"`) {
+		// Report it.
+		t.Errorf("the greyed row must not look like a live model row")
+	} // end of the ghost check
+	// A second run of the warning says the model is gone.
+	again := bodyOf(post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// The words.
+	if !strings.Contains(again, "does not list this model any more") {
+		// Report it.
+		t.Errorf("deleting twice should say the model is gone: %s", again)
+	} // end of the second check
+	// The restore page shows the manual command.
+	restore := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// The words.
+	for _, want := range []string{"ollama pull alpha:1b", "latest version", "cannot be downloaded again"} {
+		// Look for it.
+		if !strings.Contains(restore, want) {
+			// Report the gap.
+			t.Errorf("the restore page lacks %q", want)
+		} // end of the check
+	} // end of the loop
+	// Forget removes the greyed row.
+	post(t, rig.h, "/restore/forget", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
+	// The main page again.
+	_, _, page = get(t, rig.h, http.MethodGet, "/")
+	// No ghost any more.
+	if strings.Contains(page, `data-deleted=`) {
+		// Report it.
+		t.Errorf("the greyed row is still there after forgetting")
+	} // end of the forget check
+} // end of TestDeleteConfirmDeletesAndRemembers
+
+// TestDeleteConfirmRefusesLoadedModel checks the one-click confirm never deletes a model that became loaded after the warning.
+func TestDeleteConfirmRefusesLoadedModel(t *testing.T) {
+	// The rig.
+	rig, f, _ := delRig(t)
+	// The loaded model, sent to the plain confirm step as a stale page might.
+	body := bodyOf(post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"beta:7b"}}, fromThisPage))
+	// It must be sent back to the busy version.
+	if !strings.Contains(body, "may be in use") {
+		// Report it.
+		t.Errorf("a loaded model reached the plain confirm step without a warning: %s", body)
+	} // end of the page check
+	// And nothing was deleted.
+	if f.calls() != 0 {
+		// Report it.
+		t.Errorf("%d delete requests for a loaded model on the plain confirm step", f.calls())
+	} // end of the call check
+} // end of TestDeleteConfirmRefusesLoadedModel
+
+// TestForceDeleteNeedsTheTypedName checks a wrong or missing name deletes nothing and the right one does.
+func TestForceDeleteNeedsTheTypedName(t *testing.T) {
+	// The rig.
+	rig, f, _ := delRig(t)
+	// Wrong names: empty, different, differing in case, with a space.
+	for _, typed := range []string{"", "beta", "BETA:7B", "beta:7b "} {
+		// Send it.
+		body := bodyOf(post(t, rig.h, "/delete/force", url.Values{"token": {rig.token}, "model": {"beta:7b"}, "typed": {typed}}, fromThisPage))
+		// The page says nothing was deleted.
+		if !strings.Contains(body, "The name did not match, so nothing was deleted.") {
+			// Report it.
+			t.Errorf("typed %q: no mismatch message", typed)
+		} // end of the message check
+	} // end of the loop
+	// Nothing reached Ollama.
+	if f.calls() != 0 {
+		// Report it.
+		t.Fatalf("%d delete requests after wrong names", f.calls())
+	} // end of the call check
+	// The right name.
+	body := bodyOf(post(t, rig.h, "/delete/force", url.Values{"token": {rig.token}, "model": {"beta:7b"}, "typed": {"beta:7b"}}, fromThisPage))
+	// It worked.
+	if !strings.Contains(body, "Done.") || f.calls() != 1 {
+		// Report it.
+		t.Errorf("force delete with the right name failed (calls %d): %s", f.calls(), body)
+	} // end of the success check
+} // end of TestForceDeleteNeedsTheTypedName
+
+// TestDeleteFailuresAreHonest checks an Ollama failure, a 200 that did not remove the model, and an unknown model.
+func TestDeleteFailuresAreHonest(t *testing.T) {
+	// A server error.
+	rig, f, dir := delRig(t)
+	// Make the fake fail.
+	f.failDelete = true
+	// Confirm.
+	body := bodyOf(post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// The plain reason.
+	if !strings.Contains(body, "Could not do this.") || !strings.Contains(body, "status 500") {
+		// Report it.
+		t.Errorf("a failed delete was not reported: %s", body)
+	} // end of the failure check
+	// Nothing remembered.
+	if _, err := os.Stat(filepath.Join(dir, deletedFileName)); err == nil {
+		// Report it.
+		t.Errorf("a failed delete was remembered as deleted")
+	} // end of the memory check
+	// A 200 that left the model installed.
+	rig2, f2, _ := delRig(t)
+	// Make the fake pretend.
+	f2.keepAfterDelete = true
+	// Confirm.
+	body = bodyOf(post(t, rig2.h, "/delete/confirm", url.Values{"token": {rig2.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// The honest wording.
+	if !strings.Contains(body, "still listed") || strings.Contains(body, "Done.") {
+		// Report it.
+		t.Errorf("a delete that did not take effect was reported as done: %s", body)
+	} // end of the pretend check
+	// And the table shows no greyed row.
+	_, _, page := get(t, rig2.h, http.MethodGet, "/")
+	// No ghost.
+	if strings.Contains(page, `data-deleted=`) {
+		// Report it.
+		t.Errorf("a greyed row appeared for a model that is still installed")
+	} // end of the ghost check
+} // end of TestDeleteFailuresAreHonest
+
+// TestDeleteRoutesAreGuarded checks the safety rules shared by every change route: POST only, same page only, right token, sensible model name.
+func TestDeleteRoutesAreGuarded(t *testing.T) {
+	// The rig.
+	rig, f, _ := delRig(t)
+	// Every delete and restore route.
+	for _, path := range []string{"/delete", "/delete/confirm", "/delete/force", "/restore", "/restore/forget"} {
+		// A GET is not allowed.
+		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed {
+			// Report it.
+			t.Errorf("GET %s = %d, want 405", path, status)
+		} // end of the method check
+		// A form from another site is refused.
+		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "typed": {"alpha:1b"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
+			// Report it.
+			t.Errorf("cross-site POST %s = %d, want 403", path, res.StatusCode)
+		} // end of the origin check
+		// A wrong token is refused.
+		if res := post(t, rig.h, path, url.Values{"token": {"wrong"}, "model": {"alpha:1b"}, "typed": {"alpha:1b"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
+			// Report it.
+			t.Errorf("bad token POST %s = %d, want 403", path, res.StatusCode)
+		} // end of the token check
+		// An empty name is refused.
+		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {""}}, fromThisPage); res.StatusCode != http.StatusBadRequest {
+			// Report it.
+			t.Errorf("empty name POST %s = %d, want 400", path, res.StatusCode)
+		} // end of the name check
+		// A huge name is refused.
+		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {strings.Repeat("a", 301)}}, fromThisPage); res.StatusCode != http.StatusBadRequest {
+			// Report it.
+			t.Errorf("long name POST %s = %d, want 400", path, res.StatusCode)
+		} // end of the length check
+	} // end of the route loop
+	// None of that reached Ollama.
+	if f.calls() != 0 {
+		// Report it.
+		t.Errorf("%d delete requests from refused forms", f.calls())
+	} // end of the call check
+} // end of TestDeleteRoutesAreGuarded
+
+// TestRestoreOnlyForRememberedNames checks the restore page does not echo a command for a name the monitor never deleted, and a hostile name is escaped.
+func TestRestoreOnlyForRememberedNames(t *testing.T) {
+	// The rig.
+	rig, _, _ := delRig(t)
+	// A name that was never deleted, written to hurt if it were printed raw.
+	evil := `x"><script>alert(1)</script>`
+	// Ask.
+	body := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {evil}}, fromThisPage))
+	// No command and no raw script.
+	if strings.Contains(body, "ollama pull") || strings.Contains(body, "<script>alert(1)") {
+		// Report it.
+		t.Errorf("the restore page printed an unknown or hostile name: %s", body)
+	} // end of the echo check
+} // end of TestRestoreOnlyForRememberedNames
+
+// TestInstalledAgainHidesTheGhost checks a model pulled back by hand makes its greyed row disappear.
+func TestInstalledAgainHidesTheGhost(t *testing.T) {
+	// The rig.
+	rig, f, _ := delRig(t)
+	// Delete alpha.
+	post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
+	// Somebody pulls it again.
+	f.mu.Lock()
+	// It is installed again.
+	f.sizes["alpha:1b"] = 1300000000
+	// Release.
+	f.mu.Unlock()
+	// The main page.
+	_, _, page := get(t, rig.h, http.MethodGet, "/")
+	// No greyed row, and a normal row.
+	if strings.Contains(page, `data-deleted=`) || !strings.Contains(page, `data-model="alpha:1b"`) {
+		// Report it.
+		t.Errorf("a model that is installed again still shows as deleted")
+	} // end of the check
+} // end of TestInstalledAgainHidesTheGhost
+
+// TestDeletedStoreFile checks the file rules: a missing file is fine, a damaged one is left alone, and the path sits next to the performance history.
+func TestDeletedStoreFile(t *testing.T) {
+	// A private folder.
+	dir := t.TempDir()
+	// The path comes from the history path.
+	if got := deletedPathFor(filepath.Join(dir, "PerformanceCompare", "performance.json")); got != filepath.Join(dir, "PerformanceCompare", deletedFileName) {
+		// Report it.
+		t.Errorf("path %q is not next to the history", got)
+	} // end of the path check
+	// No history path means memory only.
+	if deletedPathFor("") != "" {
+		// Report it.
+		t.Errorf("an empty history path must give an empty path")
+	} // end of the memory check
+	// A damaged file.
+	bad := filepath.Join(dir, "bad.json")
+	// Write garbage.
+	os.WriteFile(bad, []byte("{not json"), 0o600)
+	// Open it.
+	s := openDeletedStore(bad)
+	// It is kept in memory only, with a note, and the file is untouched.
+	if s.path != "" || s.note == "" {
+		// Report it.
+		t.Errorf("a damaged file was not handled: path %q note %q", s.path, s.note)
+	} // end of the damaged check
+	// Adding still works in memory.
+	if err := s.add(deletedModel{Name: "m:1", DeletedAt: time.Now()}); err != nil || len(s.list()) != 1 {
+		// Report it.
+		t.Errorf("memory-only add failed: %v", err)
+	} // end of the add check
+	// The garbage is still there.
+	if data, _ := os.ReadFile(bad); string(data) != "{not json" {
+		// Report it.
+		t.Errorf("the damaged file was overwritten")
+	} // end of the untouched check
+	// A good round trip.
+	good := filepath.Join(dir, "sub", "good.json")
+	// Open (missing is fine).
+	g := openDeletedStore(good)
+	// Add two, the second replaces nothing, a repeat replaces the first.
+	g.add(deletedModel{Name: "a:1", Size: 1, DeletedAt: time.Now().Add(-time.Hour)})
+	// Second model.
+	g.add(deletedModel{Name: "b:1", Size: 2, DeletedAt: time.Now()})
+	// Repeat of the first.
+	g.add(deletedModel{Name: "a:1", Size: 3, DeletedAt: time.Now().Add(time.Minute)})
+	// Open again from disk.
+	again := openDeletedStore(good)
+	// Two entries, newest first, with the new size.
+	l := again.list()
+	// Check.
+	if len(l) != 2 || l[0].Name != "a:1" || l[0].Size != 3 {
+		// Report it.
+		t.Errorf("round trip gave %+v", l)
+	} // end of the round-trip check
+} // end of TestDeletedStoreFile
diff --git a/deletestore.go b/deletestore.go
new file mode 100644
index 0000000..2289b30
--- /dev/null
+++ b/deletestore.go
@@ -0,0 +1,268 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// encoding/json reads and writes the small file of deleted models.
+	"encoding/json"
+	// errors tells "file does not exist" apart from other problems.
+	"errors"
+	// fmt builds the error texts.
+	"fmt"
+	// os reads and writes the file.
+	"os"
+	// path/filepath builds file paths for any operating system.
+	"path/filepath"
+	// sort keeps the list in a steady order (newest deletion first).
+	"sort"
+	// sync lets several requests use the list safely.
+	"sync"
+	// time stamps the deletion.
+	"time"
+) // end of imports
+
+// deletedFileVersion is written into the file so a future version of the program can recognise an older layout.
+const deletedFileVersion = 1
+
+// deletedFileName is the file that remembers deleted models; it sits next to the performance history, which the .gitignore already keeps out of GitHub (requirement S4).
+const deletedFileName = "deleted-models.json"
+
+// maxDeletedFile is the biggest file that will be read; a normal list is a few kilobytes.
+const maxDeletedFile = 1 * 1024 * 1024
+
+// deletedModel is what the monitor remembers about one model it deleted, so the table can show it greyed out and Restore can offer it again.
+type deletedModel struct {
+	// Name is the model name with its tag, for example "gemma3:4b".
+	Name string `json:"name"`
+	// Digest is the model's fingerprint at deletion time (shown on the restore page so a later re-download can be compared).
+	Digest string `json:"digest"`
+	// Size is the size on disk in bytes, so the person sees how much space was freed and how much a download will need.
+	Size int64 `json:"size"`
+	// DeletedAt is the moment of deletion.
+	DeletedAt time.Time `json:"deleted_at"`
+} // end of deletedModel
+
+// deletedFile is the layout of the file on disk.
+type deletedFile struct {
+	// Version is deletedFileVersion.
+	Version int `json:"version"`
+	// Models is the list.
+	Models []deletedModel `json:"models"`
+} // end of deletedFile
+
+// deletedStore keeps the list in memory and, when there is a path, on disk.
+type deletedStore struct {
+	// mu protects the list.
+	mu sync.Mutex
+	// path is the file; empty means the list is kept only until the monitor stops.
+	path string
+	// items is the list.
+	items []deletedModel
+	// note explains, in plain words, why the list is only kept in memory (empty when all is well).
+	note string
+} // end of deletedStore
+
+// deletedPathFor puts the file in the same folder as the performance history; an empty history path gives an empty path.
+func deletedPathFor(historyPath string) string {
+	// No folder was found for the history, so none for this file either.
+	if historyPath == "" {
+		// Memory only.
+		return ""
+	} // end of the memory case
+	// Same folder, other file name.
+	return filepath.Join(filepath.Dir(historyPath), deletedFileName)
+} // end of deletedPathFor
+
+// openDeletedStore reads the file if there is one; a missing file is normal (nothing deleted yet), a damaged one is left alone and the list is kept in memory only.
+func openDeletedStore(path string) *deletedStore {
+	// Start with an empty list.
+	s := &deletedStore{path: path}
+	// No path: memory only.
+	if path == "" {
+		// Nothing to read.
+		return s
+	} // end of the memory case
+	// Look at the file first.
+	info, err := os.Stat(path)
+	// A missing file just means nothing was deleted yet.
+	if errors.Is(err, os.ErrNotExist) {
+		// Keep the path so the first deletion creates the file.
+		return s
+	} // end of the missing-file case
+	// Another problem with the file.
+	if err != nil {
+		// Do not touch the file; keep the list in memory.
+		s.path, s.note = "", "The list of deleted models could not be opened, so it is kept only until the monitor stops."
+		// Hand back.
+		return s
+	} // end of the stat check
+	// An absurdly big file is not ours.
+	if info.Size() > maxDeletedFile {
+		// Leave it alone.
+		s.path, s.note = "", "The file of deleted models is unusually large, so it was left alone and the list is kept only until the monitor stops."
+		// Hand back.
+		return s
+	} // end of the size check
+	// Read it.
+	data, err := os.ReadFile(path)
+	// A read failure.
+	if err != nil {
+		// Leave it alone.
+		s.path, s.note = "", "The list of deleted models could not be read, so it is kept only until the monitor stops."
+		// Hand back.
+		return s
+	} // end of the read check
+	// Decode it.
+	var f deletedFile
+	// A damaged file or another version is left alone.
+	if err := json.Unmarshal(data, &f); err != nil || f.Version != deletedFileVersion {
+		// Leave it alone.
+		s.path, s.note = "", "The file of deleted models is damaged or from another version, so it was left alone and the list is kept only until the monitor stops."
+		// Hand back.
+		return s
+	} // end of the decode check
+	// Use what was read.
+	s.items = f.Models
+	// Hand back.
+	return s
+} // end of openDeletedStore
+
+// writeLocked saves the list; the caller holds the lock. It writes a temporary file and renames it, so a crash never leaves half a file.
+func (s *deletedStore) writeLocked() error {
+	// Memory only: nothing to write.
+	if s.path == "" {
+		// Fine.
+		return nil
+	} // end of the memory case
+	// The folder of the file.
+	dir := filepath.Dir(s.path)
+	// Create it if needed, readable only by this user.
+	if err := os.MkdirAll(dir, 0o700); err != nil {
+		// Fixed wording with the system reason.
+		return fmt.Errorf("the folder for the deleted-models list could not be created: %w", err)
+	} // end of the folder check
+	// Never write a JSON null.
+	list := s.items
+	// An empty list becomes an empty array.
+	if list == nil {
+		// Empty array.
+		list = []deletedModel{}
+	} // end of the nil check
+	// Encode with indentation so the person can read the file.
+	data, err := json.MarshalIndent(deletedFile{Version: deletedFileVersion, Models: list}, "", "  ")
+	// A bug, not a user problem.
+	if err != nil {
+		// Fixed wording.
+		return fmt.Errorf("the deleted-models list could not be encoded: %w", err)
+	} // end of the encode check
+	// Temporary file in the same folder, so the rename stays on one disk.
+	tmp, err := os.CreateTemp(dir, "deleted-*.tmp")
+	// A create failure.
+	if err != nil {
+		// Fixed wording.
+		return fmt.Errorf("the deleted-models list could not be written: %w", err)
+	} // end of the create check
+	// Remove the temporary file if anything below fails.
+	defer os.Remove(tmp.Name())
+	// Only this user may read it.
+	if err := tmp.Chmod(0o600); err != nil {
+		// Close before returning.
+		tmp.Close()
+		// Fixed wording.
+		return fmt.Errorf("the deleted-models list could not be protected: %w", err)
+	} // end of the chmod check
+	// Write the bytes.
+	if _, err := tmp.Write(data); err != nil {
+		// Close before returning.
+		tmp.Close()
+		// Fixed wording.
+		return fmt.Errorf("the deleted-models list could not be written: %w", err)
+	} // end of the write check
+	// Close to flush.
+	if err := tmp.Close(); err != nil {
+		// Fixed wording.
+		return fmt.Errorf("the deleted-models list could not be written: %w", err)
+	} // end of the close check
+	// Replace the old file in one step.
+	if err := os.Rename(tmp.Name(), s.path); err != nil {
+		// Fixed wording.
+		return fmt.Errorf("the deleted-models list could not be replaced: %w", err)
+	} // end of the rename check
+	// Saved.
+	return nil
+} // end of writeLocked
+
+// add remembers one deleted model (a second deletion of the same name replaces the first).
+func (s *deletedStore) add(m deletedModel) error {
+	// One request at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// Keep every other model.
+	kept := make([]deletedModel, 0, len(s.items)+1)
+	// Go through the list.
+	for _, it := range s.items {
+		// Drop an older entry with the same name.
+		if it.Name != m.Name {
+			// Keep it.
+			kept = append(kept, it)
+		} // end of the name check
+	} // end of the loop
+	// Add the new one.
+	s.items = append(kept, m)
+	// Save.
+	return s.writeLocked()
+} // end of add
+
+// forget removes one name from the list (after a restore, or when the person no longer wants to see it).
+func (s *deletedStore) forget(name string) error {
+	// One request at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// Keep every other model.
+	kept := make([]deletedModel, 0, len(s.items))
+	// Go through the list.
+	for _, it := range s.items {
+		// Keep all but the named one.
+		if it.Name != name {
+			// Keep it.
+			kept = append(kept, it)
+		} // end of the name check
+	} // end of the loop
+	// Use the shorter list.
+	s.items = kept
+	// Save.
+	return s.writeLocked()
+} // end of forget
+
+// find returns the remembered model with this name.
+func (s *deletedStore) find(name string) (deletedModel, bool) {
+	// One request at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// Look at every entry.
+	for _, it := range s.items {
+		// A match.
+		if it.Name == name {
+			// Found.
+			return it, true
+		} // end of the name check
+	} // end of the loop
+	// Not remembered.
+	return deletedModel{}, false
+} // end of find
+
+// list returns a copy, newest deletion first.
+func (s *deletedStore) list() []deletedModel {
+	// One request at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// Copy, so the caller cannot change the store.
+	out := append([]deletedModel(nil), s.items...)
+	// Newest first.
+	sort.Slice(out, func(i, j int) bool { return out[i].DeletedAt.After(out[j].DeletedAt) })
+	// Hand back.
+	return out
+} // end of list
diff --git a/tableview.go b/tableview.go
index 111f382..66a1bd3 100644
--- a/tableview.go
+++ b/tableview.go
@@ -81,6 +81,34 @@ type groupView struct {
 	Rows []rowView
 } // end of groupView
 
+// deletedRow is one greyed-out row for a model that was deleted.
+type deletedRow struct {
+	// Name is the model name.
+	Name string
+	// SizeText is the size it had, in words.
+	SizeText string
+	// WhenText is the deletion time in words, in the computer's own time zone.
+	WhenText string
+} // end of deletedRow
+
+// deletedRows turns the remembered deleted models into rows; a name that is installed again is left out (it was restored, or pulled by hand).
+func deletedRows(items []deletedModel, installed []installedModel) []deletedRow {
+	// The rows to show.
+	var rows []deletedRow
+	// Go through the remembered models, newest first.
+	for _, d := range items {
+		// Installed again: no ghost.
+		if _, back := findInstalled(installed, d.Name); back {
+			// Skip it.
+			continue
+		} // end of the installed check
+		// Add the row.
+		rows = append(rows, deletedRow{Name: d.Name, SizeText: formatSize(d.Size), WhenText: d.DeletedAt.Local().Format("2 Jan 15:04")})
+	} // end of the loop
+	// Hand back.
+	return rows
+} // end of deletedRows
+
 // tableView is everything the page needs to draw the Installed table.
 type tableView struct {
 	// Total is the number of installed models.
@@ -89,6 +117,8 @@ type tableView struct {
 	Columns []columnView
 	// Groups are the non-empty category sections, in the fixed order.
 	Groups []groupView
+	// Deleted are the models this monitor deleted and that are not installed now; they are drawn greyed out at the end of the table.
+	Deleted []deletedRow
 } // end of tableView
 
 // makeTip looks up the help text for a heading and attaches the element name.
diff --git a/unload.go b/unload.go
index 1407a2a..b74eb64 100644
--- a/unload.go
+++ b/unload.go
@@ -45,8 +45,14 @@ const unloadVerifyStep = 300 * time.Millisecond
 // maxModelNameLen is the longest model name the forms accept.
 const maxModelNameLen = 300
 
-// postJSON sends one JSON body to base+path and returns only the status number; every error text is fixed and never contains the address.
+// postJSON sends one JSON body with the POST method; it is the short form of sendJSON that every earlier feature uses.
 func postJSON(ctx context.Context, base *url.URL, path string, timeout time.Duration, payload any) (int, error) {
+	// Hand over to the general function with the POST method.
+	return sendJSON(ctx, http.MethodPost, base, path, timeout, payload)
+} // end of postJSON
+
+// sendJSON sends one JSON body to base+path with the given method (POST, or DELETE for removing a model) and returns only the status number; every error text is fixed and never contains the address.
+func sendJSON(ctx context.Context, method string, base *url.URL, path string, timeout time.Duration, payload any) (int, error) {
 	// Turn the payload into JSON text.
 	body, err := json.Marshal(payload)
 	// A failure here is a bug in the program, not in Ollama.
@@ -57,7 +63,7 @@ func postJSON(ctx context.Context, base *url.URL, path string, timeout time.Dura
 	// Build the full address by adding the path safely.
 	target := base.JoinPath(path).String()
 	// Create the request; the context allows cancelling it from outside.
-	req, err := http.NewRequestWithContext(ctx, http.MethodPost, target, bytes.NewReader(body))
+	req, err := http.NewRequestWithContext(ctx, method, target, bytes.NewReader(body))
 	// A failure here means the address could not form a request.
 	if err != nil {
 		// Return a fixed message.
@@ -80,7 +86,7 @@ func postJSON(ctx context.Context, base *url.URL, path string, timeout time.Dura
 	io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<20))
 	// Hand back the status number.
 	return resp.StatusCode, nil
-} // end of postJSON
+} // end of sendJSON
 
 // unloadModel asks Ollama to unload one model now by setting its keep-alive time to 0; it returns which request worked.
 func unloadModel(ctx context.Context, base *url.URL, name string, timeout time.Duration) (string, error) {
diff --git a/web.go b/web.go
index 9aa9e8c..9c92dc2 100644
--- a/web.go
+++ b/web.go
@@ -119,6 +119,20 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	// Open the saved results.
 	// One history store, shared by the performance pages and the comparison page.
 	perfHistory := openPerfStore(histPath, histNote)
+	// The deleted models are remembered in a small file next to the history (kept out of GitHub by .gitignore).
+	deletedList := openDeletedStore(deletedPathFor(histPath))
+	// The five delete and restore handlers.
+	delAsk, delConfirm, delForce, restoreInfo, restoreForget := deleteHandlers(addr, token, deletedList)
+	// The first delete step: shows the warning, changes nothing.
+	mux.HandleFunc("POST /delete", delAsk)
+	// The second step for a model that is not loaded.
+	mux.HandleFunc("POST /delete/confirm", delConfirm)
+	// The force step for a loaded model; it needs the typed name.
+	mux.HandleFunc("POST /delete/force", delForce)
+	// The restore information page.
+	mux.HandleFunc("POST /restore", restoreInfo)
+	// Remove a greyed row.
+	mux.HandleFunc("POST /restore/forget", restoreForget)
 	// The four handlers of the performance pages.
 	perfStart, perfRun, perfClearAsk, perfClearDo := perfHandlers(addr, token, perfHistory)
 	// Route: a POST request for "/performance" shows the performance page and changes nothing.
@@ -192,6 +206,8 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 			} else { // the other case
 				// Build the table and switch it on.
 				data.Table = buildTableView(installed, loaded)
+				// Add the greyed rows of deleted models that are still gone.
+				data.Table.Deleted = deletedRows(deletedList.list(), installed)
 				// The table can be drawn now.
 				data.HasTable = true
 			} // end of the error check
diff --git a/web/app.css b/web/app.css
index de7949c..4175d1e 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1388,3 +1388,41 @@ button.btn-plain {
   /* Bold like a heading. */
   font-weight: 600;
 } /* end of rule */
+
+/* The delete icon turns to the problem colour when pointed at, so it is clear it is the risky one. */
+.gear-delete:hover, .gear-delete:focus-visible {
+  /* The problem colour. */
+  color: var(--bad);
+} /* end of rule */
+
+/* The restore icon turns to the good colour when pointed at. */
+.gear-restore:hover, .gear-restore:focus-visible {
+  /* The good colour. */
+  color: var(--ok);
+} /* end of rule */
+
+/* A greyed row for a deleted model. */
+.ghostrow th, .ghostrow td {
+  /* Faded, but still readable. */
+  opacity: 0.75;
+} /* end of rule */
+
+/* The deletion note under the struck name. */
+.ghostnote {
+  /* Smaller than the name. */
+  font-size: 0.85em;
+} /* end of rule */
+
+/* A link that looks like the blue button (Hold, Back): no underline. */
+a.btn-load {
+  /* Buttons are not underlined. */
+  text-decoration: none;
+  /* Sits in the line like the other buttons. */
+  display: inline-block;
+} /* end of rule */
+
+/* A heading right after a row of choices needs room above it. */
+.choices + h2 {
+  /* Space above. */
+  margin-top: 1.6rem;
+} /* end of rule */
diff --git a/web/delete.html b/web/delete.html
new file mode 100644
index 0000000..e2e5956
--- /dev/null
+++ b/web/delete.html
@@ -0,0 +1,165 @@
+{{/* Delete page template: one page with several versions, chosen by Kind. The comments are template comments, so they never reach the browser. */}}
+<!DOCTYPE html>
+{{/* lang tells screen readers which language the page is written in. */}}
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<head>{{/* start of the head. */}}
+{{/* Text encoding. */}}
+<meta charset="utf-8">
+{{/* Fit the page to the width of the screen on phones. */}}
+<meta name="viewport" content="width=device-width, initial-scale=1">
+{{/* The title shown on the browser tab. */}}
+<title>Delete a model - OllamaControlCenter</title>
+{{/* Our one stylesheet. */}}
+<link rel="stylesheet" href="/app.css">
+</head>{{/* end of the head. */}}
+<body>{{/* start of the visible page. */}}
+{{/* The page content. */}}
+<main>
+{{/* A panel that holds the message. */}}
+<section class="panel">
+{{/* Version 1: the model is not loaded and the person must confirm. */}}
+{{if eq .Kind "confirm"}}
+{{/* The heading names the model, so there is no doubt which one is meant. */}}
+<h1>Delete <code>{{.Model}}</code>?</h1>
+{{/* The warning bar. */}}
+<p class="warn" role="alert"><strong>This removes the model from this computer.</strong></p>
+{{/* The consequences, one by one. */}}
+<ul>
+{{/* Disk space. */}}
+<li>It frees about <strong>{{.SizeText}}</strong> of disk space.</li>
+{{/* Applications. */}}
+<li>Every application that asks Ollama for <code>{{.Model}}</code> gets an error from now on.</li>
+{{/* Saved settings. */}}
+<li>Settings saved inside the model, such as inference parameters you changed here, are removed with it.</li>
+{{/* How to get it back. */}}
+<li>You can bring it back with <strong>Restore</strong>. That downloads it again (about {{.SizeText}}, from the Ollama library) and gives you the latest version of the same name, which may differ from today&#39;s. A model you made yourself, from a Modelfile or an import, cannot be downloaded again.</li>
+{{/* End of the consequences. */}}
+</ul>
+{{/* What the monitor keeps. */}}
+<p class="muted">This monitor remembers the name, size and deletion time in a small file on this computer, so Restore can offer the model again.</p>
+{{/* The two choices side by side. */}}
+<div class="choices">
+{{/* The Yes form sends the model name and the page token to the second step. */}}
+<form method="post" action="/delete/confirm">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* The model name. */}}
+<input type="hidden" name="model" value="{{.Model}}">
+{{/* The Yes button. */}}
+<button type="submit" class="btn-solid">Yes, delete it</button>
+{{/* End of the Yes form. */}}
+</form>
+{{/* The cancel link simply goes back; nothing was changed. */}}
+<a class="btn-plain" href="/">No, keep it</a>
+{{/* End of the choices. */}}
+</div>
+{{/* Version 2: the model is loaded, so it may be in use. */}}
+{{else if eq .Kind "busy"}}
+{{/* The heading names the model. */}}
+<h1>Delete <code>{{.Model}}</code>?</h1>
+{{/* The warning bar. */}}
+<p class="warn" role="alert"><strong>This model is loaded right now, so it may be in use.</strong></p>
+{{/* What the monitor can and cannot see. */}}
+<p>This monitor cannot see whether an application is using it at this moment. Deleting a model that is in use can make that application fail or behave unexpectedly.</p>
+{{/* What happens by itself. */}}
+<p class="muted">If you do nothing, Ollama unloads this model by itself in: <span class="countdown"{{if .Seconds}} data-seconds="{{.Seconds}}"{{end}}>{{.Remaining}}</span>. After that, deleting it is the normal, safe case.</p>
+{{/* The first choice: do nothing. */}}
+<div class="choices">
+{{/* Hold goes back and changes nothing. */}}
+<a class="btn-load" href="/">Hold: do not delete</a>
+{{/* End of the choices. */}}
+</div>
+{{/* The second choice, for when the person is sure; it needs the exact name typed. */}}
+<h2>Force delete</h2>
+{{/* Said when the last try had a wrong name. */}}
+{{if .Mismatch}}<p class="warn" role="alert"><strong>The name did not match, so nothing was deleted.</strong></p>{{end}}
+{{/* The explanation. */}}
+<p>Only if you are sure that nothing is using it. Type the model name exactly as shown to confirm: <code>{{.Model}}</code> (frees about {{.SizeText}}).</p>
+{{/* The force form. */}}
+<form method="post" action="/delete/force" autocomplete="off">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* The model name. */}}
+<input type="hidden" name="model" value="{{.Model}}">
+{{/* The field where the person types the name. */}}
+<input type="text" name="typed" class="stopfield" aria-label="Type the model name to confirm" placeholder="{{.Model}}" required maxlength="300">
+{{/* The force button. */}}
+<button type="submit" class="unload">Force delete</button>
+{{/* End of the force form. */}}
+</form>
+{{/* Version 3: the delete worked. */}}
+{{else if eq .Kind "done"}}
+{{/* The heading names the model. */}}
+<h1>Deleted <code>{{.Model}}</code></h1>
+{{/* Say so; it was checked afterwards. */}}
+<p><strong>Done.</strong> Ollama no longer lists this model, and about {{.SizeText}} of disk space is free again.</p>
+{{/* A problem with the memory file, if any. */}}
+{{if .Note}}<p class="warn" role="alert">{{.Note}}</p>{{end}}
+{{/* How to get it back. */}}
+<p class="muted">It stays in the table, greyed out, with a Restore icon.</p>
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 4: the model is not installed (any more). */}}
+{{else if eq .Kind "gone"}}
+{{/* The heading names the model. */}}
+<h1>Delete <code>{{.Model}}</code></h1>
+{{/* Say so; there is nothing to delete. */}}
+<p>Ollama does not list this model any more, so there is nothing to delete.</p>
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 5: how to restore (information only in this phase). */}}
+{{else if eq .Kind "restore"}}
+{{/* The heading names the model. */}}
+<h1>Restore <code>{{.Model}}</code></h1>
+{{/* What is remembered. */}}
+<p>Deleted on {{.When}}. Size then: <strong>{{.SizeText}}</strong>.{{if .Digest}} Fingerprint then: <code>{{.Digest}}</code>.{{end}}</p>
+{{/* What Restore means. */}}
+<p>Restoring means downloading the model again from the Ollama library. You get the latest version of this name, which may differ from the one that was deleted. A model you made yourself, from a Modelfile or an import, cannot be downloaded again.</p>
+{{/* The manual way, until the in-page download arrives. */}}
+<p>For now, run this in a terminal on the computer that runs Ollama:</p>
+{{/* The command. */}}
+<pre><code>ollama pull {{.Model}}</code></pre>
+{{/* What happens afterwards. */}}
+<p class="muted">When the download is finished, this model appears in the table again and the greyed row disappears.</p>
+{{/* The two choices side by side. */}}
+<div class="choices">
+{{/* Back. */}}
+<a class="btn-load" href="/">Back to the monitor</a>
+{{/* The forget form removes the greyed row without touching Ollama. */}}
+<form method="post" action="/restore/forget">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{.Token}}">
+{{/* The model name. */}}
+<input type="hidden" name="model" value="{{.Model}}">
+{{/* The button. */}}
+<button type="submit" class="btn-plain">Remove this greyed row (I do not need it back)</button>
+{{/* End of the forget form. */}}
+</form>
+{{/* End of the choices. */}}
+</div>
+{{/* Version 6: the greyed row was removed or is unknown. */}}
+{{else if eq .Kind "forgotten"}}
+{{/* The heading names the model. */}}
+<h1><code>{{.Model}}</code></h1>
+{{/* Say so. */}}
+<p>This monitor no longer lists this model as deleted. Ollama was not touched.</p>
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* Version 7: something went wrong. */}}
+{{else}}
+{{/* The heading names the model. */}}
+<h1>Delete <code>{{.Model}}</code></h1>
+{{/* Say what went wrong, in the plain words the program already uses. */}}
+<p><strong>Could not do this.</strong> {{.Detail}}</p>
+{{/* A link back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* End of the versions. */}}
+{{end}}
+{{/* End of the panel. */}}
+</section>
+{{/* End of the content. */}}
+</main>
+{{/* The ticking timer needs the monitor's own script; it is included only when there is a timer to tick. */}}
+{{if .Seconds}}<script src="/countdown.js" defer></script>{{end}}
+</body>{{/* end of the visible page. */}}
+</html>{{/* end of the page. */}}
diff --git a/web/index.html b/web/index.html
index 40d4d70..1886788 100644
--- a/web/index.html
+++ b/web/index.html
@@ -155,6 +155,7 @@
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M9 13h6"/><path d="M9 17h6"/></svg></span><span><strong>Modelfile</strong>: shows a model&#39;s Modelfile, read-only</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h9"/><path d="M17 7h3"/><circle cx="15" cy="7" r="2"/><path d="M4 17h3"/><path d="M11 17h9"/><circle cx="9" cy="17" r="2"/></svg></span><span><strong>Inference parameters</strong>: view and modify them; only for models that are not loaded</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M7 15l4-5 3 3 5-7"/></svg></span><span><strong>Performance</strong>: before a model name; only for models that are not loaded</span></li>
+<li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16"/><path d="M9 7V4h6v3"/><path d="M6 7l1 13h10l1-13"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></span><span><strong>Delete</strong>: below the performance icon; asks first, and a deleted model stays in the table to restore</span></li>
 <li><span class="sym"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M7 21h10"/><path d="M4 7h16"/><path d="M4 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/><path d="M20 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/></svg></span><span><strong>Compare tested models</strong>: the button at the top right of this panel</span></li>
 </ul>
 {{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
@@ -213,6 +214,8 @@
 {{/* The model name is the row heading and stays visible while scrolling. */}}
 <th scope="row" class="stickycol">
 {{/* The performance icon comes before the name; a loaded model may be in use, so it gets an empty slot of the same width instead, and the names stay in line. */}}
+{{/* Two icons stacked in a fixed-width column: the performance icon on top (empty slot on a loaded model) and the delete icon just below it (for every model). */}}
+<span class="iconstack">
 {{if .Loaded}}<span class="gearslot" aria-hidden="true"></span>{{else}}
 {{/* A small form that sends the model name and the page token to the performance page, which changes nothing. */}}
 <form class="gearform" method="post" action="/performance">
@@ -232,6 +235,24 @@
 </form>
 {{/* End of the performance icon. */}}
 {{end}}
+{{/* A small form that sends the model name and the page token to the delete warning page, which changes nothing. */}}
+<form class="gearform" method="post" action="/delete">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{$.Token}}">
+{{/* The model name. */}}
+<input type="hidden" name="model" value="{{.Name}}">
+{{/* The area that opens the tip. */}}
+<span class="tipbox">
+{{/* The button: the symbol is hidden from screen readers, which read the label and the tip instead. */}}
+<button type="submit" class="gear gear-delete" aria-label="Delete {{.Name}}" aria-describedby="tipdel-{{.Name}}"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16"/><path d="M9 7V4h6v3"/><path d="M6 7l1 13h10l1-13"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></button>
+{{/* The tip. */}}
+<span class="tip tip-icon" role="tooltip" id="tipdel-{{.Name}}">Delete this model from this computer (it asks first)</span>
+{{/* End of the tip area. */}}
+</span>
+{{/* End of the form. */}}
+</form>
+{{/* End of the icon column. */}}
+</span>
 {{.Name}}</th>
 {{/* The state cell: a dot (solid green when loaded, an empty ring when not) plus the words, so colour is never the only signal. */}}
 <td>
@@ -319,6 +340,43 @@
 {{end}}
 {{/* End of the category loop. */}}
 {{end}}
+{{/* Models this monitor deleted and that are still gone: greyed rows with a Restore icon in the place of the delete icon. */}}
+{{if .Table.Deleted}}
+<tr class="grouprow">{{/* start of the heading row. */}}
+<th scope="colgroup" colspan="10"><strong>Deleted models</strong> <span class="muted">({{len .Table.Deleted}})</span></th>
+</tr>{{/* end of the heading row. */}}
+{{range .Table.Deleted}}
+{{/* A greyed row; it has no data-model, so the refresh script ignores it. */}}
+<tr class="ghostrow" data-deleted="{{.Name}}">
+<th scope="row" class="stickycol">
+{{/* The same icon column: an empty slot where the performance icon is, the restore icon where the delete icon is. */}}
+<span class="iconstack">
+<span class="gearslot" aria-hidden="true"></span>
+{{/* A small form that sends the model name and the page token to the restore page, which changes nothing. */}}
+<form class="gearform" method="post" action="/restore">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{$.Token}}">
+{{/* The model name. */}}
+<input type="hidden" name="model" value="{{.Name}}">
+{{/* The area that opens the tip. */}}
+<span class="tipbox">
+{{/* The button. */}}
+<button type="submit" class="gear gear-restore" aria-label="Restore {{.Name}}" aria-describedby="tiprestore-{{.Name}}"><svg class="ico" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><path d="M12 8v4l3 2"/></svg></button>
+{{/* The tip. */}}
+<span class="tip tip-icon" role="tooltip" id="tiprestore-{{.Name}}">Restore: how to download this model again</span>
+{{/* End of the tip area. */}}
+</span>
+{{/* End of the form. */}}
+</form>
+{{/* End of the icon column. */}}
+</span>
+{{/* The name is struck through; the line under it says when and how big. */}}
+<s>{{.Name}}</s><br><span class="muted ghostnote">deleted {{.WhenText}}, {{.SizeText}}</span></th>
+{{/* One wide cell for the rest of the row. */}}
+<td colspan="9" class="muted">Deleted. Restore downloads it again.</td>
+</tr>{{/* end of the greyed row. */}}
+{{end}}
+{{end}}
 {{/* End of the table body. */}}
 </tbody>
 {{/* End of the table. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
7229a574cd269e688a986f3283b3f5f12126758e3175267ded8a5e225cfc6396  control_test.go
306df43a2b6f5ae7d7a66af5982adb776d101c6db03d828f3b50126c69850060  delete.go
6510be5953a69a58f31fac7f6b2da25a305ba1b8c9983f20e835a3a0c070d7f4  delete_test.go
3f0200443a1798a7b492d36d12ea52e50853292a5788c5a63eaaa1c62251bd30  deletestore.go
cb1c0c5f8367d33e9df9da2baa7c94164fee80d6efbb3c58372810c8a694bc15  tableview.go
03972143c57ce6856dc770d2cb7f42d1f8db85610fc5556b776097123f025bbc  unload.go
d9eb1bc6aad67e71c3ad18109250d8f361fed4bbfab9f4ae4c2df72b33037502  web.go
00d3dd731b4306153e1f1bdf4001e632ddcb626568f5e371fa07b69c04a6a25b  web/app.css
7baf0d21bd62019a11ee81a95a4bdd0ea4cf9028a614f55b01d76a70140133fe  web/delete.html
0377ac08adf9a1450e88dcd6db21b6643babf78d046e5a60eb304ddbb25ebd47  web/index.html
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
