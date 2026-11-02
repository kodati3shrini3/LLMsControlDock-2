// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context gives the library check a request context.
	"context"
	// crypto/sha256 makes the fake library manifest fingerprint.
	"crypto/sha256"
	// encoding/hex writes it as text.
	"encoding/hex"
	// net/http/httptest runs the fake library.
	"net/http/httptest"
	// encoding/json builds the fake Ollama replies.
	"encoding/json"
	// net/http provides status codes and the handler type.
	"net/http"
	// net/url builds form values.
	"net/url"
	// os reads the saved file.
	"os"
	// path/filepath builds the file path.
	"path/filepath"
	// sort keeps the fake's reply stable.
	"sort"
	// strings searches the pages.
	"strings"
	// sync protects the fake's state.
	"sync"
	// testing is Go's test framework.
	"testing"
	// time stamps the fake models.
	"time"
) // end of imports

// delFake is a fake Ollama that really removes models when asked, so the tests can see the whole delete flow.
type delFake struct {
	// mu protects the fields below.
	mu sync.Mutex
	// sizes maps each installed model name to its size.
	sizes map[string]int64
	// loaded is the set of loaded model names.
	loaded map[string]bool
	// deleteCalls counts DELETE /api/delete requests.
	deleteCalls int
	// failDelete makes the delete request answer with a server error.
	failDelete bool
	// keepAfterDelete makes Ollama answer 200 but keep the model (to test the check afterwards).
	keepAfterDelete bool
	// digests overrides the fingerprint reported for a model (the default is "sha256:" plus the name).
	digests map[string]string
	// reg is the fake Ollama library this rig points the monitor at.
	reg *regFake
	// params maps a model name to the parameters text /api/show reports (a missing name reports none).
	params map[string]string
	// failShow makes /api/show answer with a server error.
	failShow bool
	// events lists "show" and "delete" in the order Ollama received them.
	events []string
} // end of delFake

// regFake is a fake Ollama library: for each manifest path it answers a status and a body, and it records every path it was asked for.
type regFake struct {
	// mu protects the fields below.
	mu sync.Mutex
	// status maps a path to the status to answer (a missing path answers 404).
	status map[string]int
	// body maps a path to the manifest text to answer.
	body map[string]string
	// paths lists every path that was asked for.
	paths []string
} // end of regFake

// manifestPath is the path the monitor asks for a model name such as "alpha:1b" in the official namespace.
func manifestPath(name, tag string) string {
	// The standard registry path.
	return "/v2/library/" + name + "/manifests/" + tag
} // end of manifestPath

// fingerprint is the sha256 of a manifest text, written as the library and Ollama write it.
func fingerprint(body string) string {
	// Hash it.
	sum := sha256.Sum256([]byte(body))
	// As text.
	return hex.EncodeToString(sum[:])
} // end of fingerprint

// setReg makes the fake library answer this status and body for a path.
func (g *regFake) setReg(path string, status int, body string) {
	// One at a time.
	g.mu.Lock()
	// Release at the end.
	defer g.mu.Unlock()
	// Remember it.
	g.status[path], g.body[path] = status, body
} // end of setReg

// asked returns the paths asked for so far.
func (g *regFake) asked() []string {
	// One at a time.
	g.mu.Lock()
	// Release at the end.
	defer g.mu.Unlock()
	// A copy.
	return append([]string(nil), g.paths...)
} // end of asked

// start runs the fake and returns its address.
func (f *delFake) start(t *testing.T) string {
	// Mark this as a helper.
	t.Helper()
	// The server.
	srv := fakeOllama(t, func(w http.ResponseWriter, r *http.Request) {
		// One request at a time.
		f.mu.Lock()
		// Release at the end.
		defer f.mu.Unlock()
		// Every reply is JSON.
		w.Header().Set("Content-Type", "application/json")
		// Choose by path.
		switch r.URL.Path {
		// The version, used by the main page check.
		case "/api/version":
			// A version.
			w.Write([]byte(`{"version":"0.34.4"}`))
		// The installed models.
		case "/api/tags":
			// Stable order.
			var names []string
			// Collect the names.
			for n := range f.sizes {
				// Add it.
				names = append(names, n)
			} // end of the loop
			// Sort them.
			sort.Strings(names)
			// Build the list.
			var list []map[string]any
			// One entry per model.
			for _, n := range names {
				// The fields the monitor reads.
				list = append(list, map[string]any{"name": n, "model": n, "size": f.sizes[n], "digest": f.digestOf(n), "modified_at": time.Now().Format(time.RFC3339), "details": map[string]any{"family": "test", "parameter_size": "1B", "quantization_level": "Q4"}})
			} // end of the loop
			// Send it.
			json.NewEncoder(w).Encode(map[string]any{"models": list})
		// The loaded models.
		case "/api/ps":
			// Build the list.
			var list []map[string]any
			// One entry per loaded model.
			for n := range f.loaded {
				// The fields the monitor reads.
				list = append(list, map[string]any{"name": n, "model": n, "size": f.sizes[n], "expires_at": time.Now().Add(90 * time.Minute).Format(time.RFC3339)})
			} // end of the loop
			// Send it.
			json.NewEncoder(w).Encode(map[string]any{"models": list})
		// The details of one model.
		case "/api/show":
			// Record the request.
			f.events = append(f.events, "show")
			// A failing server.
			if f.failShow {
				// Say so.
				w.WriteHeader(http.StatusInternalServerError)
				// Stop.
				return
			} // end of the failure case
			// Read the name.
			var req struct {
				// Model is the name.
				Model string `json:"model"`
			} // end of the request shape
			// Decode it.
			json.NewDecoder(r.Body).Decode(&req)
			// Unknown model.
			if _, ok := f.sizes[req.Model]; !ok {
				// Ollama answers 404.
				w.WriteHeader(http.StatusNotFound)
				// Stop.
				return
			} // end of the unknown case
			// The reply: parameters, a Modelfile and no model facts.
			json.NewEncoder(w).Encode(map[string]any{"parameters": f.params[req.Model], "modelfile": "FROM " + req.Model})
		// The delete request.
		case "/api/delete":
			// It must be a DELETE.
			if r.Method != http.MethodDelete {
				// Refuse like Ollama would.
				w.WriteHeader(http.StatusMethodNotAllowed)
				// Stop.
				return
			} // end of the method check
			// Count it.
			f.deleteCalls++
			// Record the order.
			f.events = append(f.events, "delete")
			// A failing server.
			if f.failDelete {
				// Say so.
				w.WriteHeader(http.StatusInternalServerError)
				// Stop.
				return
			} // end of the failure case
			// Read the name.
			var req struct {
				// Model is the name.
				Model string `json:"model"`
			} // end of the request shape
			// Decode it.
			json.NewDecoder(r.Body).Decode(&req)
			// Unknown model.
			if _, ok := f.sizes[req.Model]; !ok {
				// Ollama answers 404.
				w.WriteHeader(http.StatusNotFound)
				// Stop.
				return
			} // end of the unknown case
			// Remove it, unless the fake should pretend.
			if !f.keepAfterDelete {
				// Gone from disk.
				delete(f.sizes, req.Model)
				// Gone from memory too.
				delete(f.loaded, req.Model)
			} // end of the removal
			// Success.
			w.WriteHeader(http.StatusOK)
		// Anything else.
		default:
			// Not found.
			w.WriteHeader(http.StatusNotFound)
		} // end of the switch
	}) // end of the server
	// Hand back the address.
	return srv.URL
} // end of start

// delRig builds the monitor against a fake with two installed models (one loaded) and returns the rig, the fake and the folder of the saved files.
func delRig(t *testing.T) (themeRig, *delFake, string) {
	// Mark this as a helper.
	t.Helper()
	// Fixed machine facts.
	quietMachine(t)
	// A private folder for the saved files.
	dir := t.TempDir()
	// Use it as the config folder (the tests never learn the program's own path).
	old := userConfigDir
	// The replacement.
	// Keep the real lookups and put them back afterwards.
	saveFolderLookups(t)
	userConfigDir = func() (string, error) { return dir, nil }
	// Data and state follow the same fake folder.
	userDataDir, userStateDir = userConfigDir, userConfigDir
	// Put it back afterwards.
	t.Cleanup(func() { userConfigDir = old })
	// The fake library; every path answers 404 until a test says otherwise, and the real network is never used.
	g := &regFake{status: map[string]int{}, body: map[string]string{}}
	// The server.
	reg := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// One at a time.
		g.mu.Lock()
		// Release at the end.
		defer g.mu.Unlock()
		// Record the path.
		g.paths = append(g.paths, r.URL.Path)
		// The status for this path.
		st, ok := g.status[r.URL.Path]
		// Unknown paths are missing.
		if !ok {
			// 404.
			st = http.StatusNotFound
		} // end of the default
		// Send it.
		w.WriteHeader(st)
		// And the body.
		w.Write([]byte(g.body[r.URL.Path]))
	}))
	// Stop it at the end.
	t.Cleanup(reg.Close)
	// Point the monitor at it.
	oldReg := registryBase
	// The replacement.
	registryBase = reg.URL
	// Put it back afterwards.
	t.Cleanup(func() { registryBase = oldReg })
	// The fake with its models.
	f := &delFake{sizes: map[string]int64{"alpha:1b": 1300000000, "beta:7b": 4700000000}, loaded: map[string]bool{"beta:7b": true}, reg: g, params: map[string]string{"alpha:1b": "temperature                    0.7\nnum_ctx                        4096\nstop                           \"<end>\""}}
	// The monitor.
	h := handlerFor(t, f.start(t))
	// Read the main page to learn the token.
	_, _, body := get(t, h, http.MethodGet, "/")
	// Find the token.
	i := strings.Index(body, `name="token" value="`)
	// The page must carry one.
	if i < 0 {
		// Stop the test.
		t.Fatalf("no token found in the page")
	} // end of the token check
	// The token is 32 characters.
	tok := body[i+len(`name="token" value="`) : i+len(`name="token" value="`)+32]
	// Hand back everything.
	return themeRig{h: h, token: tok}, f, filepath.Join(dir, "OllamaControlCenter")
} // end of delRig

// digestOf returns the fingerprint the fake reports for a model.
func (f *delFake) digestOf(n string) string {
	// An override wins.
	if d, ok := f.digests[n]; ok {
		// Use it.
		return d
	} // end of the override check
	// The default.
	return "sha256:" + n
} // end of digestOf

// calls returns the number of delete requests so far.
func (f *delFake) calls() int {
	// One at a time.
	f.mu.Lock()
	// Release at the end.
	defer f.mu.Unlock()
	// The number.
	return f.deleteCalls
} // end of calls

// TestDeleteIconsInTable checks that every model row has the delete form, below the performance icon, and that a loaded row keeps an empty slot for the performance icon.
func TestDeleteIconsInTable(t *testing.T) {
	// The rig.
	rig, _, _ := delRig(t)
	// The main page.
	_, _, body := get(t, rig.h, http.MethodGet, "/")
	// One delete form per model.
	if n := strings.Count(body, `action="/delete"`); n != 2 {
		// Report it.
		t.Errorf("%d delete forms, want 2", n)
	} // end of the count check
	// The tooltip text.
	if !strings.Contains(body, "Delete this model from this computer (it asks first)") {
		// Report it.
		t.Errorf("the delete tooltip is missing")
	} // end of the tip check
	// In the alpha row the performance form comes before the delete form.
	row := body[strings.Index(body, `data-model="alpha:1b"`):]
	// Where the two forms are.
	perf, del := strings.Index(row, `action="/performance"`), strings.Index(row, `action="/delete"`)
	// The order.
	if perf < 0 || del < 0 || perf > del {
		// Report it.
		t.Errorf("performance form at %d, delete form at %d: delete must come below performance", perf, del)
	} // end of the order check
	// The loaded row has no performance form but still a delete form.
	loaded := body[strings.Index(body, `data-model="beta:7b"`):]
	// Cut at the end of the row.
	loaded = loaded[:strings.Index(loaded, "</tr>")]
	// No performance form there.
	if strings.Contains(loaded, `action="/performance"`) {
		// Report it.
		t.Errorf("a loaded model must not offer the performance icon")
	} // end of the loaded check
	// But a delete form.
	if !strings.Contains(loaded, `action="/delete"`) {
		// Report it.
		t.Errorf("a loaded model must still offer the delete icon")
	} // end of the delete check
} // end of TestDeleteIconsInTable

// TestDeleteWarningChangesNothing checks the first step shows the warning and deletes nothing.
func TestDeleteWarningChangesNothing(t *testing.T) {
	// The rig.
	rig, f, _ := delRig(t)
	// Ask about the model that is not loaded.
	res := post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// The page.
	body := bodyOf(res)
	// It must be a normal page.
	if res.StatusCode != http.StatusOK {
		// Report it.
		t.Fatalf("status %d", res.StatusCode)
	} // end of the status check
	// The warning words and both choices.
	for _, want := range []string{"This removes the model from this computer", "1.3 GB", "Restore", `class="lossbox"`, "You lose your tuning.", "you must tune it again", "cannot be downloaded again", "Yes, delete it", "No, keep it", `action="/delete/confirm"`} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("the warning page lacks %q", want)
		} // end of the check
	} // end of the loop
	// No force form for a model that is not in use.
	if strings.Contains(body, "/delete/force") {
		// Report it.
		t.Errorf("the plain warning must not offer force delete")
	} // end of the force check
	// Nothing was deleted.
	if f.calls() != 0 {
		// Report it.
		t.Errorf("%d delete requests after only asking", f.calls())
	} // end of the call check
} // end of TestDeleteWarningChangesNothing

// TestDeleteBusyPage checks a loaded model gets the Hold / Force version and nothing is deleted.
func TestDeleteBusyPage(t *testing.T) {
	// The rig.
	rig, f, _ := delRig(t)
	// Ask about the loaded model.
	res := post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"beta:7b"}}, fromThisPage)
	// The page.
	body := bodyOf(res)
	// The words that matter.
	for _, want := range []string{"loaded right now, so it may be in use", "Hold: do not delete", "Force delete", `class="lossbox"`, `action="/delete/force"`, `name="typed"`, "unloads this model by itself in"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the gap.
			t.Errorf("the busy page lacks %q", want)
		} // end of the check
	} // end of the loop
	// The plain confirm form must not be there.
	if strings.Contains(body, "/delete/confirm") {
		// Report it.
		t.Errorf("a loaded model must not get the one-click confirm form")
	} // end of the confirm check
	// The ticking timer needs the script policy.
	if !strings.Contains(res.Header.Get("Content-Security-Policy"), "script-src 'self'") {
		// Report it.
		t.Errorf("the busy page has a timer but no script policy: %q", res.Header.Get("Content-Security-Policy"))
	} // end of the policy check
	// Nothing was deleted.
	if f.calls() != 0 {
		// Report it.
		t.Errorf("%d delete requests after only asking", f.calls())
	} // end of the call check
} // end of TestDeleteBusyPage

// TestDeleteConfirmDeletesAndRemembers checks the full flow: delete, verify, remember in a private file, greyed row, restore page, forget.
func TestDeleteConfirmDeletesAndRemembers(t *testing.T) {
	// The rig.
	rig, f, dir := delRig(t)
	// Confirm the deletion.
	res := post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// The page.
	body := bodyOf(res)
	// It says done.
	if res.StatusCode != http.StatusOK || !strings.Contains(body, "Deleted <code>alpha:1b</code>") || !strings.Contains(body, "Done.") {
		// Report it.
		t.Fatalf("unexpected result page (status %d): %s", res.StatusCode, body)
	} // end of the done check
	// Exactly one request reached Ollama.
	if f.calls() != 1 {
		// Report it.
		t.Errorf("%d delete requests, want 1", f.calls())
	} // end of the call check
	// The file exists and only the owner may read it.
	info, err := os.Stat(filepath.Join(dir, deletedFolderName, deletedFileName))
	// It must exist.
	if err != nil {
		// Stop the test.
		t.Fatalf("no deleted-models file: %v", err)
	} // end of the file check
	// Owner only.
	if modesApply() && info.Mode().Perm() != 0o600 {
		// Report it.
		t.Errorf("file mode %o, want 600", info.Mode().Perm())
	} // end of the mode check
	// The main page now shows the greyed row with a restore form, and the model is not in the installed rows.
	_, _, page := get(t, rig.h, http.MethodGet, "/")
	// The things that must be there.
	for _, want := range []string{`data-deleted="alpha:1b"`, "<s>alpha:1b</s>", `action="/restore"`, "Restore: how to download this model again, and the parameters it had", "Deleted models", "1.3 GB"} {
		// Look for it.
		if !strings.Contains(page, want) {
			// Report the gap.
			t.Errorf("the main page lacks %q", want)
		} // end of the check
	} // end of the loop
	// The ghost row must not carry data-model (the refresh script compares those).
	if strings.Contains(page, `data-model="alpha:1b"`) {
		// Report it.
		t.Errorf("the greyed row must not look like a live model row")
	} // end of the ghost check
	// A second run of the warning says the model is gone.
	again := bodyOf(post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
	// The words.
	if !strings.Contains(again, "does not list this model any more") {
		// Report it.
		t.Errorf("deleting twice should say the model is gone: %s", again)
	} // end of the second check
	// The library has the model, so the restore page can show the command.
	f.reg.setReg(manifestPath("alpha", "1b"), http.StatusOK, "m-alpha")
	// The restore page shows the manual command.
	restore := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
	// The words.
	for _, want := range []string{"ollama pull alpha:1b", "latest version", `class="lossbox"`, "You lose your tuning.", "cannot be downloaded again", "docker exec &lt;container-name&gt; ollama pull alpha:1b", "kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull alpha:1b", "Directly on the computer"} {
		// Look for it.
		if !strings.Contains(restore, want) {
			// Report the gap.
			t.Errorf("the restore page lacks %q", want)
		} // end of the check
	} // end of the loop
	// Forget removes the greyed row.
	post(t, rig.h, "/restore/forget", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// The main page again.
	_, _, page = get(t, rig.h, http.MethodGet, "/")
	// No ghost any more.
	if strings.Contains(page, `data-deleted=`) {
		// Report it.
		t.Errorf("the greyed row is still there after forgetting")
	} // end of the forget check
} // end of TestDeleteConfirmDeletesAndRemembers

// TestDeleteConfirmRefusesLoadedModel checks the one-click confirm never deletes a model that became loaded after the warning.
func TestDeleteConfirmRefusesLoadedModel(t *testing.T) {
	// The rig.
	rig, f, _ := delRig(t)
	// The loaded model, sent to the plain confirm step as a stale page might.
	body := bodyOf(post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"beta:7b"}}, fromThisPage))
	// It must be sent back to the busy version.
	if !strings.Contains(body, "may be in use") {
		// Report it.
		t.Errorf("a loaded model reached the plain confirm step without a warning: %s", body)
	} // end of the page check
	// And nothing was deleted.
	if f.calls() != 0 {
		// Report it.
		t.Errorf("%d delete requests for a loaded model on the plain confirm step", f.calls())
	} // end of the call check
} // end of TestDeleteConfirmRefusesLoadedModel

// TestForceDeleteNeedsTheTypedName checks a wrong or missing name deletes nothing and the right one does.
func TestForceDeleteNeedsTheTypedName(t *testing.T) {
	// The rig.
	rig, f, _ := delRig(t)
	// Wrong names: empty, different, differing in case, with a space.
	for _, typed := range []string{"", "beta", "BETA:7B", "beta:7b "} {
		// Send it.
		body := bodyOf(post(t, rig.h, "/delete/force", url.Values{"token": {rig.token}, "model": {"beta:7b"}, "typed": {typed}}, fromThisPage))
		// The page says nothing was deleted.
		if !strings.Contains(body, "The name did not match, so nothing was deleted.") {
			// Report it.
			t.Errorf("typed %q: no mismatch message", typed)
		} // end of the message check
	} // end of the loop
	// Nothing reached Ollama.
	if f.calls() != 0 {
		// Report it.
		t.Fatalf("%d delete requests after wrong names", f.calls())
	} // end of the call check
	// The right name.
	body := bodyOf(post(t, rig.h, "/delete/force", url.Values{"token": {rig.token}, "model": {"beta:7b"}, "typed": {"beta:7b"}}, fromThisPage))
	// It worked.
	if !strings.Contains(body, "Done.") || f.calls() != 1 {
		// Report it.
		t.Errorf("force delete with the right name failed (calls %d): %s", f.calls(), body)
	} // end of the success check
} // end of TestForceDeleteNeedsTheTypedName

// TestDeleteFailuresAreHonest checks an Ollama failure, a 200 that did not remove the model, and an unknown model.
func TestDeleteFailuresAreHonest(t *testing.T) {
	// A server error.
	rig, f, dir := delRig(t)
	// Make the fake fail.
	f.failDelete = true
	// Confirm.
	body := bodyOf(post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
	// The plain reason.
	if !strings.Contains(body, "Could not do this.") || !strings.Contains(body, "status 500") {
		// Report it.
		t.Errorf("a failed delete was not reported: %s", body)
	} // end of the failure check
	// Nothing remembered.
	if _, err := os.Stat(filepath.Join(dir, deletedFolderName, deletedFileName)); err == nil {
		// Report it.
		t.Errorf("a failed delete was remembered as deleted")
	} // end of the memory check
	// A 200 that left the model installed.
	rig2, f2, _ := delRig(t)
	// Make the fake pretend.
	f2.keepAfterDelete = true
	// Confirm.
	body = bodyOf(post(t, rig2.h, "/delete/confirm", url.Values{"token": {rig2.token}, "model": {"alpha:1b"}}, fromThisPage))
	// The honest wording.
	if !strings.Contains(body, "still listed") || strings.Contains(body, "Done.") {
		// Report it.
		t.Errorf("a delete that did not take effect was reported as done: %s", body)
	} // end of the pretend check
	// And the table shows no greyed row.
	_, _, page := get(t, rig2.h, http.MethodGet, "/")
	// No ghost.
	if strings.Contains(page, `data-deleted=`) {
		// Report it.
		t.Errorf("a greyed row appeared for a model that is still installed")
	} // end of the ghost check
} // end of TestDeleteFailuresAreHonest

// TestDeleteRoutesAreGuarded checks the safety rules shared by every change route: POST only, same page only, right token, sensible model name.
func TestDeleteRoutesAreGuarded(t *testing.T) {
	// The rig.
	rig, f, _ := delRig(t)
	// Every delete and restore route.
	for _, path := range []string{"/delete", "/delete/confirm", "/delete/force", "/restore", "/restore/forget", "/restore/history"} {
		// A GET is not allowed.
		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed {
			// Report it.
			t.Errorf("GET %s = %d, want 405", path, status)
		} // end of the method check
		// A form from another site is refused.
		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "typed": {"alpha:1b"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
			// Report it.
			t.Errorf("cross-site POST %s = %d, want 403", path, res.StatusCode)
		} // end of the origin check
		// A wrong token is refused.
		if res := post(t, rig.h, path, url.Values{"token": {"wrong"}, "model": {"alpha:1b"}, "typed": {"alpha:1b"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
			// Report it.
			t.Errorf("bad token POST %s = %d, want 403", path, res.StatusCode)
		} // end of the token check
		// An empty name is refused.
		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {""}}, fromThisPage); res.StatusCode != http.StatusBadRequest {
			// Report it.
			t.Errorf("empty name POST %s = %d, want 400", path, res.StatusCode)
		} // end of the name check
		// A huge name is refused.
		if res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {strings.Repeat("a", 301)}}, fromThisPage); res.StatusCode != http.StatusBadRequest {
			// Report it.
			t.Errorf("long name POST %s = %d, want 400", path, res.StatusCode)
		} // end of the length check
	} // end of the route loop
	// None of that reached Ollama.
	if f.calls() != 0 {
		// Report it.
		t.Errorf("%d delete requests from refused forms", f.calls())
	} // end of the call check
} // end of TestDeleteRoutesAreGuarded

// TestRestoreOnlyForRememberedNames checks the restore page does not echo a command for a name the monitor never deleted, and a hostile name is escaped.
func TestRestoreOnlyForRememberedNames(t *testing.T) {
	// The rig.
	rig, _, _ := delRig(t)
	// A name that was never deleted, written to hurt if it were printed raw.
	evil := `x"><script>alert(1)</script>`
	// Ask.
	body := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {evil}}, fromThisPage))
	// No command and no raw script.
	if strings.Contains(body, "ollama pull") || strings.Contains(body, "<script>alert(1)") {
		// Report it.
		t.Errorf("the restore page printed an unknown or hostile name: %s", body)
	} // end of the echo check
} // end of TestRestoreOnlyForRememberedNames

// TestInstalledAgainHidesTheGhost checks a model pulled back by hand makes its greyed row disappear.
func TestInstalledAgainHidesTheGhost(t *testing.T) {
	// The rig.
	rig, f, _ := delRig(t)
	// Delete alpha.
	post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// Somebody pulls it again.
	f.mu.Lock()
	// It is installed again.
	f.sizes["alpha:1b"] = 1300000000
	// Release.
	f.mu.Unlock()
	// The main page.
	_, _, page := get(t, rig.h, http.MethodGet, "/")
	// No greyed row, and a normal row.
	if strings.Contains(page, `data-deleted=`) || !strings.Contains(page, `data-model="alpha:1b"`) {
		// Report it.
		t.Errorf("a model that is installed again still shows as deleted")
	} // end of the check
} // end of TestInstalledAgainHidesTheGhost

// TestDeletedStoreFile checks the file rules: a missing file is fine, a damaged one is left alone, and the path sits next to the performance history.
func TestDeletedStoreFile(t *testing.T) {
	// A private folder.
	dir := t.TempDir()
	// With a performanceCompare results folder, the new folder sits beside it, in the project folder.
	if got := deletedPathFor(filepath.Join(dir, "performanceCompare", "performance.json")); got != filepath.Join(dir, "deletedHistory", deletedFileName) {
		// Report it.
		t.Errorf("path %q is not in the deletedHistory folder beside performanceCompare", got)
	} // end of the path check
	// With another results folder, the new folder sits beside the results file.
	if got := deletedPathFor(filepath.Join(dir, "OllamaControlCenter", "performance.json")); got != filepath.Join(dir, "OllamaControlCenter", "deletedHistory", deletedFileName) {
		// Report it.
		t.Errorf("path %q for the fallback folder", got)
	} // end of the fallback check
	// No history path means memory only.
	if deletedPathFor("") != "" {
		// Report it.
		t.Errorf("an empty history path must give an empty path")
	} // end of the memory check
	// A damaged file.
	bad := filepath.Join(dir, "bad.json")
	// Write garbage.
	os.WriteFile(bad, []byte("{not json"), 0o600)
	// Open it.
	s := openDeletedStore(bad)
	// It is kept in memory only, with a note, and the file is untouched.
	if s.path != "" || s.note == "" {
		// Report it.
		t.Errorf("a damaged file was not handled: path %q note %q", s.path, s.note)
	} // end of the damaged check
	// Adding still works in memory.
	if err := s.add(deletedModel{Name: "m:1", DeletedAt: time.Now()}); err != nil || len(s.list()) != 1 {
		// Report it.
		t.Errorf("memory-only add failed: %v", err)
	} // end of the add check
	// The garbage is still there.
	if data, _ := os.ReadFile(bad); string(data) != "{not json" {
		// Report it.
		t.Errorf("the damaged file was overwritten")
	} // end of the untouched check
	// A good round trip.
	good := filepath.Join(dir, "sub", "good.json")
	// Open (missing is fine).
	g := openDeletedStore(good)
	// Add two, the second replaces nothing, a repeat replaces the first.
	g.add(deletedModel{Name: "a:1", Size: 1, DeletedAt: time.Now().Add(-time.Hour)})
	// Second model.
	g.add(deletedModel{Name: "b:1", Size: 2, DeletedAt: time.Now()})
	// Repeat of the first.
	g.add(deletedModel{Name: "a:1", Size: 3, DeletedAt: time.Now().Add(time.Minute)})
	// Open again from disk.
	again := openDeletedStore(good)
	// Two entries, newest first, with the new size.
	l := again.list()
	// Check.
	if len(l) != 2 || l[0].Name != "a:1" || l[0].Size != 3 {
		// Report it.
		t.Errorf("round trip gave %+v", l)
	} // end of the round-trip check
} // end of TestDeletedStoreFile

// TestLibraryPath checks how a model name becomes a library path, and that odd names never reach the network.
func TestLibraryPath(t *testing.T) {
	// Each case: name, expected repo, expected tag, expected ok.
	for _, c := range []struct {
		// name is the model name.
		name string
		// repo is the expected library path.
		repo string
		// tag is the expected tag.
		tag string
		// ok is whether the name belongs to the Ollama library.
		ok bool
	}{
		{"smollm2:135m", "library/smollm2", "135m", true},
		{"gemma4", "library/gemma4", "latest", true},
		{"rjmalagon/gte-qwen2-instruct:1.5b-f16", "rjmalagon/gte-qwen2-instruct", "1.5b-f16", true},
		{"hf.co/NeoRoth/nemotron-3-embed-1b-gguf:F16", "", "", false},
		{"hf.co/x:F16", "", "", false},
		{"a/b/c:1", "", "", false},
		{"../etc/passwd", "", "", false},
		{"x:ta g", "", "", false},
		{"x:", "", "", false},
		{"", "", "", false},
		{"a?b=c:1", "", "", false},
	} { // end of the cases
		// Run it.
		repo, tag, ok := libraryPath(c.name)
		// Compare.
		if repo != c.repo || tag != c.tag || ok != c.ok {
			// Report it.
			t.Errorf("libraryPath(%q) = %q, %q, %v; want %q, %q, %v", c.name, repo, tag, ok, c.repo, c.tag, c.ok)
		} // end of the compare
	} // end of the loop
} // end of TestLibraryPath

// TestCheckLibraryStates checks every answer the library check can give.
func TestCheckLibraryStates(t *testing.T) {
	// The rig starts the fake library.
	_, f, _ := delRig(t)
	// The manifest text and its fingerprint.
	body := "manifest-of-alpha"
	// The path for alpha:1b.
	p := manifestPath("alpha", "1b")
	// The context.
	ctx := context.Background()
	// Missing: nothing configured gives 404.
	if got := checkLibrary(ctx, "alpha:1b", "sha256:"+fingerprint(body)); got != libMissing {
		// Report it.
		t.Errorf("unconfigured path = %q, want missing", got)
	} // end of the missing check
	// Same fingerprint, written with and without the prefix and in upper case.
	f.reg.setReg(p, http.StatusOK, body)
	// Each style.
	for _, have := range []string{"sha256:" + fingerprint(body), fingerprint(body), strings.ToUpper(fingerprint(body))} {
		// Compare.
		if got := checkLibrary(ctx, "alpha:1b", have); got != libSame {
			// Report it.
			t.Errorf("same fingerprint %q gave %q", have, got)
		} // end of the compare
	} // end of the loop
	// A different fingerprint.
	if got := checkLibrary(ctx, "alpha:1b", "sha256:deadbeef"); got != libDifferent {
		// Report it.
		t.Errorf("other fingerprint gave %q, want different", got)
	} // end of the different check
	// A server error is not understood, so it is unknown, never "missing".
	f.reg.setReg(p, http.StatusInternalServerError, "oops")
	// Check.
	if got := checkLibrary(ctx, "alpha:1b", "x"); got != libUnknown {
		// Report it.
		t.Errorf("500 gave %q, want unknown", got)
	} // end of the 500 check
	// An empty 200 is not a manifest.
	f.reg.setReg(p, http.StatusOK, "")
	// Check.
	if got := checkLibrary(ctx, "alpha:1b", "x"); got != libUnknown {
		// Report it.
		t.Errorf("empty 200 gave %q, want unknown", got)
	} // end of the empty check
	// A huge body is refused.
	f.reg.setReg(p, http.StatusOK, strings.Repeat("a", maxManifest+10))
	// Check.
	if got := checkLibrary(ctx, "alpha:1b", "x"); got != libUnknown {
		// Report it.
		t.Errorf("huge body gave %q, want unknown", got)
	} // end of the huge check
	// An unreachable library is unknown.
	old := registryBase
	// A closed port.
	registryBase = "http://127.0.0.1:1"
	// Check.
	got := checkLibrary(ctx, "alpha:1b", "x")
	// Restore.
	registryBase = old
	// Compare.
	if got != libUnknown {
		// Report it.
		t.Errorf("unreachable library gave %q, want unknown", got)
	} // end of the unreachable check
	// Names from other sources are never sent anywhere.
	before := len(f.reg.asked())
	// Check.
	if got := checkLibrary(ctx, "hf.co/NeoRoth/x:F16", "x"); got != libOther {
		// Report it.
		t.Errorf("hf.co name gave %q, want other", got)
	} // end of the other check
	// No request was made.
	if len(f.reg.asked()) != before {
		// Report it.
		t.Errorf("a name from another source was sent to the library")
	} // end of the request check
} // end of TestCheckLibraryStates

// TestDeletePageLibraryNotes checks the caution before deleting, for each answer, on both versions of the page.
func TestDeletePageLibraryNotes(t *testing.T) {
	// Each case: how the library answers, and the words that must appear.
	for _, c := range []struct {
		// name labels the case.
		name string
		// status and body are the library's answer for alpha:1b.
		status int
		// body is the manifest text.
		body string
		// have is the fingerprint the fake Ollama reports for alpha:1b ("" keeps the default).
		have string
		// want is the text that must be on the warning page.
		want string
		// class is the bar that must be used.
		class string
	}{
		{"same", 200, "m-alpha", "sha256:" + fingerprint("m-alpha"), "has this exact version", "goodnote"},
		{"different", 200, "m-newer", "", "has a different version of this name than yours", `class="warn"`},
		{"missing", 404, "", "", "does not have this name, so it cannot be restored. Deleting it is permanent.", `class="warn"`},
		{"unknown", 500, "", "", "Could not check the Ollama library just now", `class="warn"`},
	} { // end of the cases
		// A fresh rig for each case.
		rig, f, _ := delRig(t)
		// The library's answer.
		f.reg.setReg(manifestPath("alpha", "1b"), c.status, c.body)
		// The fingerprint the installed copy has.
		if c.have != "" {
			// Set it.
			f.digests = map[string]string{"alpha:1b": c.have}
		} // end of the override
		// Ask about the model that is not loaded.
		body := bodyOf(post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
		// The words and the bar.
		if !strings.Contains(body, c.want) || !strings.Contains(body, c.class) {
			// Report it.
			t.Errorf("%s: the warning page lacks %q / %q", c.name, c.want, c.class)
		} // end of the check
		// Only the model name was sent to the library.
		if got := f.reg.asked(); len(got) != 1 || got[0] != manifestPath("alpha", "1b") {
			// Report it.
			t.Errorf("%s: library was asked %v", c.name, got)
		} // end of the privacy check
	} // end of the loop
	// The busy version (a loaded model) carries the note too.
	rig, f, _ := delRig(t)
	// Library has no beta.
	_ = f
	// Ask.
	body := bodyOf(post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"beta:7b"}}, fromThisPage))
	// The note.
	if !strings.Contains(body, "does not have this name") || !strings.Contains(body, "may be in use") {
		// Report it.
		t.Errorf("the busy page lacks the library note")
	} // end of the busy check
} // end of TestDeletePageLibraryNotes

// TestRestorePageLibraryNotes checks the restore page re-asks the library at that moment and hides the command when it would fail.
func TestRestorePageLibraryNotes(t *testing.T) {
	// The rig.
	rig, f, _ := delRig(t)
	// The library has the same version when deleting.
	f.digests = map[string]string{"alpha:1b": "sha256:" + fingerprint("m-alpha")}
	// The answer.
	f.reg.setReg(manifestPath("alpha", "1b"), 200, "m-alpha")
	// Delete it.
	post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// Restore page while the library still has the same version.
	body := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
	// Identical copy, command shown.
	if !strings.Contains(body, "still has this exact version") || !strings.Contains(body, "ollama pull alpha:1b") {
		// Report it.
		t.Errorf("restore page (same) wrong: %s", body)
	} // end of the same check
	// The library now has a newer build.
	f.reg.setReg(manifestPath("alpha", "1b"), 200, "m-newer")
	// Ask again.
	body = bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
	// A different version, command still shown.
	if !strings.Contains(body, "now has a different version") || !strings.Contains(body, "ollama pull alpha:1b") {
		// Report it.
		t.Errorf("restore page (different) wrong: %s", body)
	} // end of the different check
	// The library dropped the model.
	f.reg.setReg(manifestPath("alpha", "1b"), 404, "")
	// Ask again.
	body = bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
	// A clear statement and no command that must fail.
	if !strings.Contains(body, "cannot be restored from there") || strings.Contains(body, "ollama pull") {
		// Report it.
		t.Errorf("restore page (missing) wrong: %s", body)
	} // end of the missing check
} // end of TestRestorePageLibraryNotes

// TestOldDeletedFileMovesToTheNewFolder checks that the list written by an earlier version is moved, never overwritten, and that nothing happens when there is nothing to move.
func TestOldDeletedFileMovesToTheNewFolder(t *testing.T) {
	// A project folder with a performanceCompare folder, as on the real machine.
	root := t.TempDir()
	// The results file path.
	hist := filepath.Join(root, "performanceCompare", "performance.json")
	// The folder must exist.
	if err := os.MkdirAll(filepath.Dir(hist), 0o700); err != nil {
		// Stop the test.
		t.Fatal(err)
	} // end of the folder check
	// Nothing to move yet.
	if msg := moveOldDeletedFile(hist); msg != "" {
		// Report it.
		t.Errorf("message %q with nothing to move", msg)
	} // end of the empty check
	// An old file from an earlier version.
	oldFile := filepath.Join(root, "performanceCompare", deletedFileName)
	// Write it.
	if err := os.WriteFile(oldFile, []byte("old"), 0o600); err != nil {
		// Stop the test.
		t.Fatal(err)
	} // end of the write check
	// Move it.
	if msg := moveOldDeletedFile(hist); msg != "" {
		// Report it.
		t.Fatalf("message %q", msg)
	} // end of the move check
	// The new place holds it, the old place is empty.
	newFile := filepath.Join(root, "deletedHistory", deletedFileName)
	// Read the new file.
	if b, err := os.ReadFile(newFile); err != nil || string(b) != "old" {
		// Report it.
		t.Errorf("new file %q, error %v", b, err)
	} // end of the content check
	// The old file is gone.
	if _, err := os.Stat(oldFile); err == nil {
		// Report it.
		t.Errorf("the old file is still there")
	} // end of the old-file check
	// The new folder is private.
	if st, err := os.Stat(filepath.Dir(newFile)); err != nil || (modesApply() && st.Mode().Perm() != 0o700) {
		// Report it.
		t.Errorf("folder mode %v, error %v", st, err)
	} // end of the mode check
	// A second old file never overwrites the new one.
	if err := os.WriteFile(oldFile, []byte("second"), 0o600); err != nil {
		// Stop the test.
		t.Fatal(err)
	} // end of the write check
	// Try again.
	moveOldDeletedFile(hist)
	// The new file keeps its content.
	if b, _ := os.ReadFile(newFile); string(b) != "old" {
		// Report it.
		t.Errorf("the new file was overwritten: %q", b)
	} // end of the overwrite check
	// The second old file stays where it is.
	if b, _ := os.ReadFile(oldFile); string(b) != "second" {
		// Report it.
		t.Errorf("the old file was changed: %q", b)
	} // end of the stay check
	// A memory-only store has nothing to move.
	if moveOldDeletedFile("") != "" {
		// Report it.
		t.Errorf("a message for a memory-only store")
	} // end of the memory check
} // end of TestOldDeletedFileMovesToTheNewFolder
