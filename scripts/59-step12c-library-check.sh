#!/usr/bin/env bash
# Script 59: before deleting, the monitor asks the public Ollama library (read-only, model name only) whether the model can be restored; the restore page says whether the library copy is identical, different or missing.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/delete-model" ] || { echo "FAIL  not on feature/delete-model"; exit 1; }
# Script 58 must be applied first.
grep -q 'tune them again' web/delete.html || { echo "FAIL  script 58 was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e library.go ]; then
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
index ba35352..9fe982d 100644
--- a/delete.go
+++ b/delete.go
@@ -75,6 +75,12 @@ type deletePage struct {
 	Detail string
 	// Note carries a warning that does not stop the work (for example, the list could not be saved).
 	Note string
+	// LibText is what the check of the Ollama library found, in words (empty when no check was made).
+	LibText string
+	// LibClass is "ok" for good news and "warn" for a caution; it decides how the note is drawn.
+	LibClass string
+	// ShowPull is false when the library has no such model, so the page does not offer a command that must fail.
+	ShowPull bool
 	// Theme is the saved theme choice, as on the main page.
 	Theme string
 	// Token is the page token for the forms on this page.
@@ -156,6 +162,17 @@ func deleteHandlers(addr ollamaAddress, token string, store *deletedStore) (ask,
 		// Build the page data.
 		return deletePage{Kind: "busy", Model: name, SizeText: formatSize(size), Remaining: remainingText(time.Now(), exp, expOK), Seconds: remainingSeconds(time.Now(), exp, expOK), Mismatch: mismatch}
 	} // end of busyPage
+	// withLib asks the Ollama library, read-only, about this model and adds the answer in words to the page; phase is "delete" or "restore". Only the model name leaves this computer.
+	withLib := func(r *http.Request, p deletePage, name, digest, phase string) deletePage {
+		// Ask the library.
+		state := checkLibrary(r.Context(), name, digest)
+		// Word the answer.
+		p.LibText, p.LibClass = libraryNote(state, phase)
+		// A command that is certain to fail is not offered.
+		p.ShowPull = state != libMissing
+		// Hand the page back.
+		return p
+	} // end of withLib
 	// look asks Ollama, right now, what is installed and what is loaded; the loaded entry has an empty name when the model is not loaded. It shows the error or "gone" page itself when it cannot go on, and then returns false.
 	look := func(w http.ResponseWriter, r *http.Request, name string) (installedModel, loadedModel, bool) {
 		// What is installed.
@@ -244,12 +261,12 @@ func deleteHandlers(addr ollamaAddress, token string, store *deletedStore) (ask,
 		// Loaded means it may be in use: Hold or Force delete.
 		if l.Name == name {
 			// Show the busy version.
-			show(w, r, http.StatusOK, busyPage(name, m.Size, l, false))
+			show(w, r, http.StatusOK, withLib(r, busyPage(name, m.Size, l, false), name, m.Digest, "delete"))
 			// Stop here.
 			return
 		} // end of the loaded case
 		// Not loaded: the normal warning.
-		show(w, r, http.StatusOK, deletePage{Kind: "confirm", Model: name, SizeText: formatSize(m.Size)})
+		show(w, r, http.StatusOK, withLib(r, deletePage{Kind: "confirm", Model: name, SizeText: formatSize(m.Size)}, name, m.Digest, "delete"))
 	} // end of ask
 	// confirm is the second step for a model that is not loaded; if it has been loaded meanwhile, it goes back to the busy version.
 	confirm = func(w http.ResponseWriter, r *http.Request) {
@@ -270,7 +287,7 @@ func deleteHandlers(addr ollamaAddress, token string, store *deletedStore) (ask,
 		// Loaded in the meantime: this button must not delete it.
 		if l.Name == name {
 			// Show the busy version.
-			show(w, r, http.StatusOK, busyPage(name, m.Size, l, false))
+			show(w, r, http.StatusOK, withLib(r, busyPage(name, m.Size, l, false), name, m.Digest, "delete"))
 			// Stop here.
 			return
 		} // end of the loaded case
@@ -298,10 +315,10 @@ func deleteHandlers(addr ollamaAddress, token string, store *deletedStore) (ask,
 			// Show the busy version again with a note; if it is no longer loaded, show the normal warning.
 			if l.Name == name {
 				// Busy again.
-				show(w, r, http.StatusOK, busyPage(name, m.Size, l, true))
+				show(w, r, http.StatusOK, withLib(r, busyPage(name, m.Size, l, true), name, m.Digest, "delete"))
 			} else { // the other case
 				// Normal warning.
-				show(w, r, http.StatusOK, deletePage{Kind: "confirm", Model: name, SizeText: formatSize(m.Size)})
+				show(w, r, http.StatusOK, withLib(r, deletePage{Kind: "confirm", Model: name, SizeText: formatSize(m.Size)}, name, m.Digest, "delete"))
 			} // end of the loaded check
 			// Stop here.
 			return
@@ -328,7 +345,7 @@ func deleteHandlers(addr ollamaAddress, token string, store *deletedStore) (ask,
 			return
 		} // end of the unknown case
 		// Show the information page.
-		show(w, r, http.StatusOK, deletePage{Kind: "restore", Model: d.Name, SizeText: formatSize(d.Size), Digest: d.Digest, When: d.DeletedAt.Local().Format("2 Jan 2006 15:04 MST")})
+		show(w, r, http.StatusOK, withLib(r, deletePage{Kind: "restore", Model: d.Name, SizeText: formatSize(d.Size), Digest: d.Digest, When: d.DeletedAt.Local().Format("2 Jan 2006 15:04 MST")}, d.Name, d.Digest, "restore"))
 	} // end of restore
 	// forget removes the greyed row, without touching Ollama.
 	forget = func(w http.ResponseWriter, r *http.Request) {
diff --git a/delete_test.go b/delete_test.go
index b31a17d..1a65d51 100644
--- a/delete_test.go
+++ b/delete_test.go
@@ -2,6 +2,14 @@
 package main
 
 import ( // import lists the standard-library packages this file uses.
+	// context gives the library check a request context.
+	"context"
+	// crypto/sha256 makes the fake library manifest fingerprint.
+	"crypto/sha256"
+	// encoding/hex writes it as text.
+	"encoding/hex"
+	// net/http/httptest runs the fake library.
+	"net/http/httptest"
 	// encoding/json builds the fake Ollama replies.
 	"encoding/json"
 	// net/http provides status codes and the handler type.
@@ -38,8 +46,58 @@ type delFake struct {
 	failDelete bool
 	// keepAfterDelete makes Ollama answer 200 but keep the model (to test the check afterwards).
 	keepAfterDelete bool
+	// digests overrides the fingerprint reported for a model (the default is "sha256:" plus the name).
+	digests map[string]string
+	// reg is the fake Ollama library this rig points the monitor at.
+	reg *regFake
 } // end of delFake
 
+// regFake is a fake Ollama library: for each manifest path it answers a status and a body, and it records every path it was asked for.
+type regFake struct {
+	// mu protects the fields below.
+	mu sync.Mutex
+	// status maps a path to the status to answer (a missing path answers 404).
+	status map[string]int
+	// body maps a path to the manifest text to answer.
+	body map[string]string
+	// paths lists every path that was asked for.
+	paths []string
+} // end of regFake
+
+// manifestPath is the path the monitor asks for a model name such as "alpha:1b" in the official namespace.
+func manifestPath(name, tag string) string {
+	// The standard registry path.
+	return "/v2/library/" + name + "/manifests/" + tag
+} // end of manifestPath
+
+// fingerprint is the sha256 of a manifest text, written as the library and Ollama write it.
+func fingerprint(body string) string {
+	// Hash it.
+	sum := sha256.Sum256([]byte(body))
+	// As text.
+	return hex.EncodeToString(sum[:])
+} // end of fingerprint
+
+// setReg makes the fake library answer this status and body for a path.
+func (g *regFake) setReg(path string, status int, body string) {
+	// One at a time.
+	g.mu.Lock()
+	// Release at the end.
+	defer g.mu.Unlock()
+	// Remember it.
+	g.status[path], g.body[path] = status, body
+} // end of setReg
+
+// asked returns the paths asked for so far.
+func (g *regFake) asked() []string {
+	// One at a time.
+	g.mu.Lock()
+	// Release at the end.
+	defer g.mu.Unlock()
+	// A copy.
+	return append([]string(nil), g.paths...)
+} // end of asked
+
 // start runs the fake and returns its address.
 func (f *delFake) start(t *testing.T) string {
 	// Mark this as a helper.
@@ -74,7 +132,7 @@ func (f *delFake) start(t *testing.T) string {
 			// One entry per model.
 			for _, n := range names {
 				// The fields the monitor reads.
-				list = append(list, map[string]any{"name": n, "model": n, "size": f.sizes[n], "digest": "sha256:" + n, "modified_at": time.Now().Format(time.RFC3339), "details": map[string]any{"family": "test", "parameter_size": "1B", "quantization_level": "Q4"}})
+				list = append(list, map[string]any{"name": n, "model": n, "size": f.sizes[n], "digest": f.digestOf(n), "modified_at": time.Now().Format(time.RFC3339), "details": map[string]any{"family": "test", "parameter_size": "1B", "quantization_level": "Q4"}})
 			} // end of the loop
 			// Send it.
 			json.NewEncoder(w).Encode(map[string]any{"models": list})
@@ -154,8 +212,38 @@ func delRig(t *testing.T) (themeRig, *delFake, string) {
 	userConfigDir = func() (string, error) { return dir, nil }
 	// Put it back afterwards.
 	t.Cleanup(func() { userConfigDir = old })
+	// The fake library; every path answers 404 until a test says otherwise, and the real network is never used.
+	g := &regFake{status: map[string]int{}, body: map[string]string{}}
+	// The server.
+	reg := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
+		// One at a time.
+		g.mu.Lock()
+		// Release at the end.
+		defer g.mu.Unlock()
+		// Record the path.
+		g.paths = append(g.paths, r.URL.Path)
+		// The status for this path.
+		st, ok := g.status[r.URL.Path]
+		// Unknown paths are missing.
+		if !ok {
+			// 404.
+			st = http.StatusNotFound
+		} // end of the default
+		// Send it.
+		w.WriteHeader(st)
+		// And the body.
+		w.Write([]byte(g.body[r.URL.Path]))
+	}))
+	// Stop it at the end.
+	t.Cleanup(reg.Close)
+	// Point the monitor at it.
+	oldReg := registryBase
+	// The replacement.
+	registryBase = reg.URL
+	// Put it back afterwards.
+	t.Cleanup(func() { registryBase = oldReg })
 	// The fake with its models.
-	f := &delFake{sizes: map[string]int64{"alpha:1b": 1300000000, "beta:7b": 4700000000}, loaded: map[string]bool{"beta:7b": true}}
+	f := &delFake{sizes: map[string]int64{"alpha:1b": 1300000000, "beta:7b": 4700000000}, loaded: map[string]bool{"beta:7b": true}, reg: g}
 	// The monitor.
 	h := handlerFor(t, f.start(t))
 	// Read the main page to learn the token.
@@ -173,6 +261,17 @@ func delRig(t *testing.T) (themeRig, *delFake, string) {
 	return themeRig{h: h, token: tok}, f, filepath.Join(dir, "OllamaControlCenter")
 } // end of delRig
 
+// digestOf returns the fingerprint the fake reports for a model.
+func (f *delFake) digestOf(n string) string {
+	// An override wins.
+	if d, ok := f.digests[n]; ok {
+		// Use it.
+		return d
+	} // end of the override check
+	// The default.
+	return "sha256:" + n
+} // end of digestOf
+
 // calls returns the number of delete requests so far.
 func (f *delFake) calls() int {
 	// One at a time.
@@ -342,6 +441,8 @@ func TestDeleteConfirmDeletesAndRemembers(t *testing.T) {
 		// Report it.
 		t.Errorf("deleting twice should say the model is gone: %s", again)
 	} // end of the second check
+	// The library has the model, so the restore page can show the command.
+	f.reg.setReg(manifestPath("alpha", "1b"), http.StatusOK, "m-alpha")
 	// The restore page shows the manual command.
 	restore := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
 	// The words.
@@ -577,3 +678,210 @@ func TestDeletedStoreFile(t *testing.T) {
 		t.Errorf("round trip gave %+v", l)
 	} // end of the round-trip check
 } // end of TestDeletedStoreFile
+
+// TestLibraryPath checks how a model name becomes a library path, and that odd names never reach the network.
+func TestLibraryPath(t *testing.T) {
+	// Each case: name, expected repo, expected tag, expected ok.
+	for _, c := range []struct {
+		// name is the model name.
+		name string
+		// repo is the expected library path.
+		repo string
+		// tag is the expected tag.
+		tag string
+		// ok is whether the name belongs to the Ollama library.
+		ok bool
+	}{
+		{"smollm2:135m", "library/smollm2", "135m", true},
+		{"gemma4", "library/gemma4", "latest", true},
+		{"rjmalagon/gte-qwen2-instruct:1.5b-f16", "rjmalagon/gte-qwen2-instruct", "1.5b-f16", true},
+		{"hf.co/NeoRoth/nemotron-3-embed-1b-gguf:F16", "", "", false},
+		{"hf.co/x:F16", "", "", false},
+		{"a/b/c:1", "", "", false},
+		{"../etc/passwd", "", "", false},
+		{"x:ta g", "", "", false},
+		{"x:", "", "", false},
+		{"", "", "", false},
+		{"a?b=c:1", "", "", false},
+	} { // end of the cases
+		// Run it.
+		repo, tag, ok := libraryPath(c.name)
+		// Compare.
+		if repo != c.repo || tag != c.tag || ok != c.ok {
+			// Report it.
+			t.Errorf("libraryPath(%q) = %q, %q, %v; want %q, %q, %v", c.name, repo, tag, ok, c.repo, c.tag, c.ok)
+		} // end of the compare
+	} // end of the loop
+} // end of TestLibraryPath
+
+// TestCheckLibraryStates checks every answer the library check can give.
+func TestCheckLibraryStates(t *testing.T) {
+	// The rig starts the fake library.
+	_, f, _ := delRig(t)
+	// The manifest text and its fingerprint.
+	body := "manifest-of-alpha"
+	// The path for alpha:1b.
+	p := manifestPath("alpha", "1b")
+	// The context.
+	ctx := context.Background()
+	// Missing: nothing configured gives 404.
+	if got := checkLibrary(ctx, "alpha:1b", "sha256:"+fingerprint(body)); got != libMissing {
+		// Report it.
+		t.Errorf("unconfigured path = %q, want missing", got)
+	} // end of the missing check
+	// Same fingerprint, written with and without the prefix and in upper case.
+	f.reg.setReg(p, http.StatusOK, body)
+	// Each style.
+	for _, have := range []string{"sha256:" + fingerprint(body), fingerprint(body), strings.ToUpper(fingerprint(body))} {
+		// Compare.
+		if got := checkLibrary(ctx, "alpha:1b", have); got != libSame {
+			// Report it.
+			t.Errorf("same fingerprint %q gave %q", have, got)
+		} // end of the compare
+	} // end of the loop
+	// A different fingerprint.
+	if got := checkLibrary(ctx, "alpha:1b", "sha256:deadbeef"); got != libDifferent {
+		// Report it.
+		t.Errorf("other fingerprint gave %q, want different", got)
+	} // end of the different check
+	// A server error is not understood, so it is unknown, never "missing".
+	f.reg.setReg(p, http.StatusInternalServerError, "oops")
+	// Check.
+	if got := checkLibrary(ctx, "alpha:1b", "x"); got != libUnknown {
+		// Report it.
+		t.Errorf("500 gave %q, want unknown", got)
+	} // end of the 500 check
+	// An empty 200 is not a manifest.
+	f.reg.setReg(p, http.StatusOK, "")
+	// Check.
+	if got := checkLibrary(ctx, "alpha:1b", "x"); got != libUnknown {
+		// Report it.
+		t.Errorf("empty 200 gave %q, want unknown", got)
+	} // end of the empty check
+	// A huge body is refused.
+	f.reg.setReg(p, http.StatusOK, strings.Repeat("a", maxManifest+10))
+	// Check.
+	if got := checkLibrary(ctx, "alpha:1b", "x"); got != libUnknown {
+		// Report it.
+		t.Errorf("huge body gave %q, want unknown", got)
+	} // end of the huge check
+	// An unreachable library is unknown.
+	old := registryBase
+	// A closed port.
+	registryBase = "http://127.0.0.1:1"
+	// Check.
+	got := checkLibrary(ctx, "alpha:1b", "x")
+	// Restore.
+	registryBase = old
+	// Compare.
+	if got != libUnknown {
+		// Report it.
+		t.Errorf("unreachable library gave %q, want unknown", got)
+	} // end of the unreachable check
+	// Names from other sources are never sent anywhere.
+	before := len(f.reg.asked())
+	// Check.
+	if got := checkLibrary(ctx, "hf.co/NeoRoth/x:F16", "x"); got != libOther {
+		// Report it.
+		t.Errorf("hf.co name gave %q, want other", got)
+	} // end of the other check
+	// No request was made.
+	if len(f.reg.asked()) != before {
+		// Report it.
+		t.Errorf("a name from another source was sent to the library")
+	} // end of the request check
+} // end of TestCheckLibraryStates
+
+// TestDeletePageLibraryNotes checks the caution before deleting, for each answer, on both versions of the page.
+func TestDeletePageLibraryNotes(t *testing.T) {
+	// Each case: how the library answers, and the words that must appear.
+	for _, c := range []struct {
+		// name labels the case.
+		name string
+		// status and body are the library's answer for alpha:1b.
+		status int
+		// body is the manifest text.
+		body string
+		// have is the fingerprint the fake Ollama reports for alpha:1b ("" keeps the default).
+		have string
+		// want is the text that must be on the warning page.
+		want string
+		// class is the bar that must be used.
+		class string
+	}{
+		{"same", 200, "m-alpha", "sha256:" + fingerprint("m-alpha"), "has this exact version", "goodnote"},
+		{"different", 200, "m-newer", "", "has a different version of this name than yours", `class="warn"`},
+		{"missing", 404, "", "", "does not have this name, so it cannot be restored. Deleting it is permanent.", `class="warn"`},
+		{"unknown", 500, "", "", "Could not check the Ollama library just now", `class="warn"`},
+	} { // end of the cases
+		// A fresh rig for each case.
+		rig, f, _ := delRig(t)
+		// The library's answer.
+		f.reg.setReg(manifestPath("alpha", "1b"), c.status, c.body)
+		// The fingerprint the installed copy has.
+		if c.have != "" {
+			// Set it.
+			f.digests = map[string]string{"alpha:1b": c.have}
+		} // end of the override
+		// Ask about the model that is not loaded.
+		body := bodyOf(post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+		// The words and the bar.
+		if !strings.Contains(body, c.want) || !strings.Contains(body, c.class) {
+			// Report it.
+			t.Errorf("%s: the warning page lacks %q / %q", c.name, c.want, c.class)
+		} // end of the check
+		// Only the model name was sent to the library.
+		if got := f.reg.asked(); len(got) != 1 || got[0] != manifestPath("alpha", "1b") {
+			// Report it.
+			t.Errorf("%s: library was asked %v", c.name, got)
+		} // end of the privacy check
+	} // end of the loop
+	// The busy version (a loaded model) carries the note too.
+	rig, f, _ := delRig(t)
+	// Library has no beta.
+	_ = f
+	// Ask.
+	body := bodyOf(post(t, rig.h, "/delete", url.Values{"token": {rig.token}, "model": {"beta:7b"}}, fromThisPage))
+	// The note.
+	if !strings.Contains(body, "does not have this name") || !strings.Contains(body, "may be in use") {
+		// Report it.
+		t.Errorf("the busy page lacks the library note")
+	} // end of the busy check
+} // end of TestDeletePageLibraryNotes
+
+// TestRestorePageLibraryNotes checks the restore page re-asks the library at that moment and hides the command when it would fail.
+func TestRestorePageLibraryNotes(t *testing.T) {
+	// The rig.
+	rig, f, _ := delRig(t)
+	// The library has the same version when deleting.
+	f.digests = map[string]string{"alpha:1b": "sha256:" + fingerprint("m-alpha")}
+	// The answer.
+	f.reg.setReg(manifestPath("alpha", "1b"), 200, "m-alpha")
+	// Delete it.
+	post(t, rig.h, "/delete/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
+	// Restore page while the library still has the same version.
+	body := bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// Identical copy, command shown.
+	if !strings.Contains(body, "still has this exact version") || !strings.Contains(body, "ollama pull alpha:1b") {
+		// Report it.
+		t.Errorf("restore page (same) wrong: %s", body)
+	} // end of the same check
+	// The library now has a newer build.
+	f.reg.setReg(manifestPath("alpha", "1b"), 200, "m-newer")
+	// Ask again.
+	body = bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// A different version, command still shown.
+	if !strings.Contains(body, "now has a different version") || !strings.Contains(body, "ollama pull alpha:1b") {
+		// Report it.
+		t.Errorf("restore page (different) wrong: %s", body)
+	} // end of the different check
+	// The library dropped the model.
+	f.reg.setReg(manifestPath("alpha", "1b"), 404, "")
+	// Ask again.
+	body = bodyOf(post(t, rig.h, "/restore", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage))
+	// A clear statement and no command that must fail.
+	if !strings.Contains(body, "cannot be restored from there") || strings.Contains(body, "ollama pull") {
+		// Report it.
+		t.Errorf("restore page (missing) wrong: %s", body)
+	} // end of the missing check
+} // end of TestRestorePageLibraryNotes
diff --git a/library.go b/library.go
new file mode 100644
index 0000000..8d19551
--- /dev/null
+++ b/library.go
@@ -0,0 +1,206 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// context lets the check be cancelled when the browser goes away.
+	"context"
+	// crypto/sha256 computes the fingerprint of the library's manifest, the same way Ollama does for the model ID.
+	"crypto/sha256"
+	// encoding/hex writes the fingerprint as text.
+	"encoding/hex"
+	// io reads a limited part of the reply.
+	"io"
+	// net/http sends the read-only question to the library.
+	"net/http"
+	// regexp checks that every part of a model name is made only of safe characters.
+	"regexp"
+	// strings splits and compares names.
+	"strings"
+	// time limits how long the question may take.
+	"time"
+) // end of imports
+
+// registryBase is the address of the public Ollama library; a variable so tests can point it at a fake and never touch the real network.
+var registryBase = "https://registry.ollama.ai"
+
+// libraryTimeout is how long the monitor waits for the library; a slow or missing internet connection must not freeze the delete page.
+const libraryTimeout = 6 * time.Second
+
+// maxManifest is the biggest library reply that is read; a real manifest is a few kilobytes.
+const maxManifest = 1 << 20
+
+// Library states: what the check found out.
+const (
+	// libSame means the library has this name and its fingerprint equals the one the person has (or had).
+	libSame = "same"
+	// libDifferent means the library has this name, but with another fingerprint (a newer build, or the local copy was changed).
+	libDifferent = "different"
+	// libMissing means the library answered that it has no such name and tag.
+	libMissing = "missing"
+	// libUnknown means the library could not be asked, or gave an answer that is not understood.
+	libUnknown = "unknown"
+	// libOther means the name does not belong to the Ollama library (another host such as hf.co), so it was not asked.
+	libOther = "other"
+) // end of constants
+
+// namePart is the characters one part of a model name may contain; anything else is never put into an address.
+var namePart = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)
+
+// libraryPath turns a model name into the library address path, for example "smollm2:135m" into "library/smollm2" and "135m"; ok is false for names from other sources.
+func libraryPath(name string) (repo, tag string, ok bool) {
+	// The tag is whatever follows the last colon of the last part; no colon means "latest".
+	tag = "latest"
+	// Work on a copy of the name.
+	base := name
+	// The last slash separates the parts; the colon must come after it to belong to the tag.
+	if i := strings.LastIndex(base, ":"); i >= 0 && i > strings.LastIndex(base, "/") {
+		// The tag.
+		tag = base[i+1:]
+		// The name without the tag.
+		base = base[:i]
+	} // end of the tag split
+	// The parts of the name.
+	parts := strings.Split(base, "/")
+	// A single part belongs to the official "library" namespace; two parts are a user namespace; more mean another host or a deeper path.
+	switch len(parts) {
+	// One part.
+	case 1:
+		// Official models live under "library".
+		parts = []string{"library", parts[0]}
+	// Two parts: a first part with a dot or colon is a host name, not a user.
+	case 2:
+		// A host name such as hf.co.
+		if strings.ContainsAny(parts[0], ".:") {
+			// Not the Ollama library.
+			return "", "", false
+		} // end of the host check
+	// Anything else.
+	default:
+		// Not the Ollama library.
+		return "", "", false
+	} // end of the switch
+	// Every part, and the tag, must be made of safe characters only.
+	for _, p := range append(append([]string{}, parts...), tag) {
+		// Reject empty or odd parts.
+		if !namePart.MatchString(p) {
+			// Never build an address from it.
+			return "", "", false
+		} // end of the character check
+	} // end of the loop
+	// Hand back the path and the tag.
+	return parts[0] + "/" + parts[1], tag, true
+} // end of libraryPath
+
+// normalDigest removes a leading "sha256:" and lower-cases the rest, so fingerprints written in different styles compare equal.
+func normalDigest(d string) string {
+	// Without the prefix, in lower case.
+	return strings.ToLower(strings.TrimPrefix(strings.TrimSpace(d), "sha256:"))
+} // end of normalDigest
+
+// checkLibrary asks the Ollama library, read-only, whether it has this model name and whether its fingerprint equals have; only the model name leaves this computer.
+func checkLibrary(ctx context.Context, name, have string) string {
+	// Names from other sources are not sent anywhere.
+	repo, tag, ok := libraryPath(name)
+	// Not the Ollama library.
+	if !ok {
+		// Say so.
+		return libOther
+	} // end of the source check
+	// Build the request address: the standard registry path for a manifest.
+	target := registryBase + "/v2/" + repo + "/manifests/" + tag
+	// A request that stops with the browser's request or after the timeout.
+	ctx, cancel := context.WithTimeout(ctx, libraryTimeout)
+	// Release the timer at the end.
+	defer cancel()
+	// Create the request.
+	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
+	// A failure here means the address could not be built.
+	if err != nil {
+		// Unknown.
+		return libUnknown
+	} // end of the request check
+	// Ask for the manifest in the format Ollama itself uses.
+	req.Header.Set("Accept", "application/vnd.docker.distribution.manifest.v2+json")
+	// Say who is asking.
+	req.Header.Set("User-Agent", "OllamaControlCenter")
+	// Send it.
+	resp, err := http.DefaultClient.Do(req)
+	// No answer: no internet, or the library is down.
+	if err != nil {
+		// Unknown.
+		return libUnknown
+	} // end of the send check
+	// Close the reply at the end.
+	defer resp.Body.Close()
+	// The library says it has no such name or tag.
+	if resp.StatusCode == http.StatusNotFound {
+		// Missing.
+		return libMissing
+	} // end of the 404 case
+	// Anything but a normal answer is not understood.
+	if resp.StatusCode != http.StatusOK {
+		// Unknown.
+		return libUnknown
+	} // end of the status check
+	// Read the manifest, but never more than the limit.
+	data, err := io.ReadAll(io.LimitReader(resp.Body, maxManifest+1))
+	// A broken or oversized reply.
+	if err != nil || len(data) > maxManifest || len(data) == 0 {
+		// Unknown.
+		return libUnknown
+	} // end of the read check
+	// The fingerprint of the manifest is what Ollama shows as the model ID and reports as "digest".
+	sum := sha256.Sum256(data)
+	// Compare it with the one we have.
+	if hex.EncodeToString(sum[:]) == normalDigest(have) {
+		// Identical.
+		return libSame
+	} // end of the same case
+	// Another fingerprint.
+	return libDifferent
+} // end of checkLibrary
+
+// libraryNote words what the check found, for the delete page (phase "delete") or the restore page (phase "restore"); class is "ok" for good news and "warn" otherwise.
+func libraryNote(state, phase string) (text, class string) {
+	// Choose by state.
+	switch state {
+	// Same fingerprint.
+	case libSame:
+		// Good news, in the right tense.
+		if phase == "delete" {
+			// Before deleting.
+			return "Good: the Ollama library has this exact version, so Restore can bring back an identical copy.", "ok"
+		} // end of the delete wording
+		// After deleting.
+		return "The Ollama library still has this exact version, so a download brings back an identical copy.", "ok"
+	// Other fingerprint.
+	case libDifferent:
+		// Before deleting.
+		if phase == "delete" {
+			// Careful wording: either newer, or changed here.
+			return "Careful: the Ollama library has a different version of this name than yours (a newer one, or yours was changed here, for example by editing its parameters). Restore would give you the library's version, not this exact copy.", "warn"
+		} // end of the delete wording
+		// After deleting.
+		return "The Ollama library now has a different version of this name than the one you deleted (probably a newer one, or yours had been changed here), so a download gives you the library's version.", "warn"
+	// Not in the library.
+	case libMissing:
+		// Before deleting.
+		if phase == "delete" {
+			// The strong caution.
+			return "Careful: the Ollama library does not have this name, so it cannot be restored. Deleting it is permanent.", "warn"
+		} // end of the delete wording
+		// After deleting.
+		return "The Ollama library does not have this name, so a download will fail. This model cannot be restored from there.", "warn"
+	// Another source.
+	case libOther:
+		// Same wording for both phases.
+		return "This model comes from outside the Ollama library (another site, or made on this computer), so the monitor cannot check whether it can be restored. Treat deleting it as permanent.", "warn"
+	} // end of the switch
+	// Not known.
+	if phase == "delete" {
+		// Before deleting.
+		return "Could not check the Ollama library just now (no internet?), so it is not known whether this model can be restored.", "warn"
+	} // end of the delete wording
+	// After deleting.
+	return "Could not check the Ollama library just now. The command below will tell you if the model is not available.", "warn"
+} // end of libraryNote
diff --git a/web/app.css b/web/app.css
index 4175d1e..098a03f 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1426,3 +1426,13 @@ a.btn-load {
   /* Space above. */
   margin-top: 1.6rem;
 } /* end of rule */
+
+/* Good news in a delete or restore page: a bar in the good colour, like the warning bar but green. */
+.goodnote {
+  /* A thick bar in the good colour. */
+  border-left: 6px solid var(--ok);
+  /* Room between the bar and the text. */
+  padding: 0.4rem 0.8rem;
+  /* A light panel behind it, as for the warning. */
+  background: var(--bg);
+} /* end of rule */
diff --git a/web/delete.html b/web/delete.html
index b0842c8..3f5bd4f 100644
--- a/web/delete.html
+++ b/web/delete.html
@@ -23,6 +23,8 @@
 <h1>Delete <code>{{.Model}}</code>?</h1>
 {{/* The warning bar. */}}
 <p class="warn" role="alert"><strong>This removes the model from this computer.</strong></p>
+{{/* What the check of the Ollama library found: good news or a caution. */}}
+{{if .LibText}}<p class="{{if eq .LibClass "ok"}}goodnote{{else}}warn{{end}}" role="{{if eq .LibClass "ok"}}status{{else}}alert{{end}}">{{.LibText}}</p>{{end}}
 {{/* The consequences, one by one. */}}
 <ul>
 {{/* Disk space. */}}
@@ -63,6 +65,8 @@
 <h1>Delete <code>{{.Model}}</code>?</h1>
 {{/* The warning bar. */}}
 <p class="warn" role="alert"><strong>This model is loaded right now, so it may be in use.</strong></p>
+{{/* What the check of the Ollama library found: good news or a caution. */}}
+{{if .LibText}}<p class="{{if eq .LibClass "ok"}}goodnote{{else}}warn{{end}}" role="{{if eq .LibClass "ok"}}status{{else}}alert{{end}}">{{.LibText}}</p>{{end}}
 {{/* What the monitor can and cannot see. */}}
 <p>This monitor cannot see whether an application is using it at this moment. Deleting a model that is in use can make that application fail or behave unexpectedly.</p>
 {{/* What happens by itself. */}}
@@ -117,16 +121,20 @@
 <h1>Restore <code>{{.Model}}</code></h1>
 {{/* What is remembered. */}}
 <p>Deleted on {{.When}}. Size then: <strong>{{.SizeText}}</strong>.{{if .Digest}} Fingerprint then: <code>{{.Digest}}</code>.{{end}}</p>
+{{/* What the check of the Ollama library found: good news or a caution. */}}
+{{if .LibText}}<p class="{{if eq .LibClass "ok"}}goodnote{{else}}warn{{end}}" role="{{if eq .LibClass "ok"}}status{{else}}alert{{end}}">{{.LibText}}</p>{{end}}
 {{/* What Restore means. */}}
 <p>Restoring means downloading the model again from the Ollama library. You get the latest version of this name, which may differ from the one that was deleted.</p>
 {{/* The lost tuning. */}}
 <p><strong>Inference parameters you changed are not restored.</strong> The model comes back as a fresh copy, so tune them again.</p>
 {{/* Models that cannot come back. */}}
 <p>A model you made yourself (from a Modelfile or an import) cannot be downloaded again.</p>
+{{if .ShowPull}}
 {{/* The manual way, until the in-page download arrives. */}}
 <p>For now, run this in a terminal on the computer that runs Ollama:</p>
 {{/* The command. */}}
 <pre><code>ollama pull {{.Model}}</code></pre>
+{{end}}
 {{/* What happens afterwards. */}}
 <p class="muted">When the download is finished, this model appears in the table again and the greyed row disappears.</p>
 {{/* The two choices side by side. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
771eb520f06c50f5a6880d35ee7d7c248a0f8051e71d26c501d42f99cf475c71  delete.go
9e7942c940eb618b874f357a47491cd10e672de0560ab8162b4b9b6d5e65d780  delete_test.go
47f9e6a1b2d8d99d0e84986812e762f6881d75dea30c9f78a49a480acf81d20f  library.go
c628b0050203cfab7baf5ede48628c7bd8bd6c9d570aae4ed4d1f925ef4e93a7  web/app.css
7319fc17f480974cb663f389ae504a8d71966209514ac51efc4b958ee571829a  web/delete.html
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
