#!/usr/bin/env bash
# Script 93 (Find LLM, slice 3 of 4): tags on the home page and the saved offline copy of the library list. (1) Under each installed model's name the Installed models table now shows small plain-word tags: its size class (Tiny to Very large), its memory of a conversation (Short to Very long) and its abilities (Pictures, Audio, Tools, Thinking), all read from what Ollama reports; a figure Ollama does not report gives no tag. (2) A help line "How models are grouped" above the table explains them. (3) Every successful Find LLM search saves the library list, with the moment it was read, in the program's data folder; when ollama.com cannot be reached later, Find LLM shows that saved copy with a clear warning and its date, and says the versions and sizes cannot be checked. A damaged or empty copy is never shown. The About page and README say that the list is kept on this computer. Seven new tests; three older tests count one more help bubble. The version stays 0.31.0 until the Friday release.
# Run it from the project folder, on its own new branch that starts from feature/find-llm-page (never on main): cd ~/LLMsControlDock && git checkout feature/find-llm-page && git checkout -b feature/find-llm-tags && bash scripts/93-step56-model-tags-and-offline-list.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by scripts 87 to 92d), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["README.md"]="9b8e58541c8e8c66d3ecdd5a3c1d0e363cde936bdf60da21dc50adfe76f0c43d"
BEFORE["findllm.go"]="ae5317b44fa1a291a66a6c30f5e2800a199e4b1073b9fd7222c993da4ffa3354"
BEFORE["findllm_test.go"]="ebb5faa6a35d8e807fd490a46af4d31dfde32dd18911b12300ce6cc4f64d557b"
BEFORE["findtips.go"]="3d6793ebaee1c321cbdf8b07ac0b8b1f54652ee765913c1fdf9f42aeba6d9cc6"
BEFORE["perf_test.go"]="dac3db91024276247bc97b406809903c57ebd1d616093c7ffa19f783c350f917"
BEFORE["tableview.go"]="bdb30161ccca3a1c29916f39cd53d2ff1e76703cd90ab497caea1f81dc068511"
BEFORE["web/about.html"]="6bfa594538e128089729af1da5b4fe66d96dddbb17447e772fd0145f57d4e8d5"
BEFORE["web/app.css"]="e23f0d9ecae65643b81844ca611cc42b05ef8aef357ab41b9068ce086e5a89b5"
BEFORE["web/findllm.html"]="52ecd375c90f9b27e833236d38bd97d020729e7caf00b832b656cf193eddbd49"
BEFORE["web/index.html"]="563fbbdaca2ea0147ff36b74549d578113ab276e0d8a0732c7433988170e79b2"
BEFORE["webtable_test.go"]="36fe6d4330e6ad2e7c54ffffef4aaa46fe14c92b299829aade0e06cf7fafd622"
AFTER["README.md"]="a70175a98f9dccbbdcf2bcdc765e2247e932f981bc87b50a8d3ec29473323db3"
AFTER["findllm.go"]="d82871109e78f3a65e67b09316c8444a77cf4da785834a200e51826441865159"
AFTER["findllm_test.go"]="44f54d27e01107b6d00da54f6a176d35a5a2e30a6cf6757cd231ba863cd75975"
AFTER["findtips.go"]="84fc1270a2dd8830d9c5541baa8647f4365f8a9cc3d0492678de20486bf33807"
AFTER["perf_test.go"]="a5dedd6d5a413e5909f3ce803a1e9b6962480e3dd27b0c360755e60a8b36320c"
AFTER["tableview.go"]="1dfecf26da27cdf7c3fd13cf18f7d188a1a0ace4ea9b0e9938f578a114c96f11"
AFTER["web/about.html"]="429e536d1aac5ab6dcc03dca575bb3b12b85f05efc86f369e9f6c59d53145533"
AFTER["web/app.css"]="bb5b4c95098c4b3174b6258b0e79b622b238614b79050414869929e057a82cd8"
AFTER["web/findllm.html"]="98aea299b888a44b53dc72c5b4d09e3fa89f3c76949a7a312bf5b6945cc9a6ee"
AFTER["web/index.html"]="8f7b8cd834ead120620d4eb07a0c7ffdc0cebe5037e86b818eac1cec0733f287"
AFTER["webtable_test.go"]="fd50185cc06df35df7c991b696fde0efe1a58f053a887d056cff10b1e1e4b948"
AFTER["findcopy.go"]="96f834a2b8a665cede9614608c79608ca4f1d31184112a03abc618a080d9aa03"
AFTER["tags.go"]="0006f1b8ef856792751bb3199b8f47c773211606570b732fdb9ea54b9cd43ed5"

# Count of passed checks.
PASS=0
# Count of failed checks (the script stops at the first one).
FAIL=0
# pass prints one PASS line and counts it; it is only called after a real check succeeded.
pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
# fail prints one FAIL line, counts it, and stops the script at once.
fail() { echo "FAIL  $1"; FAIL=$((FAIL + 1)); echo "Result: $PASS passed, $FAIL failed"; exit 1; }
# sha prints the sha256 of one file.
sha() { sha256sum "$1" | cut -d' ' -f1; }

# Go to the top folder of the git project this script was started in.
cd "$(git rev-parse --show-toplevel)"
# The project must be the right one: its main.go and go.mod must be here.
[ -f main.go ] && [ -f go.mod ] || fail "this is not the project folder (main.go or go.mod missing)"
# Say where we are.
echo "Project folder: $(pwd)"

# The branch we are on.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# Never change main directly: every change goes through a branch and a pull request.
[ "$BRANCH" != "main" ] || fail "you are on main; create a branch first: git checkout feature/find-llm-page && git checkout -b feature/find-llm-tags"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Slice 2 (scripts 92 to 92d) must be in this branch: the page and its copy buttons exist.
[ -e findllm.go ] && grep -q 'copy.js' web/findllm.html && grep -q 'panelactions' web/index.html || fail "slice 2 (scripts 92 to 92d) is missing: this branch must start from feature/find-llm-page"
# Report it.
pass "slice 2 (the Find LLM page with its copy buttons) is in this branch"

# Refuse to run twice: the new files exist when the change was applied before.
if [ -e tags.go ] || [ -e findcopy.go ]; then fail "tags.go or findcopy.go exists: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# Every file to change must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the project is in another state than expected.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} files to change are the expected versions before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_93_END'
diff --git a/README.md b/README.md
index 3ab6f80..f78b230 100644
--- a/README.md
+++ b/README.md
@@ -19,7 +19,7 @@ A small program that watches an [Ollama](https://ollama.com) server and lets you
 - The page listens on this computer only (`127.0.0.1:8765`) unless you change that in Settings.
 - Only the program's own page can use the Stop and Unload buttons.
 - No prompt or response text is stored.
-- The only internet requests are read-only: a look-up of a model name in the public Ollama library before a delete; the public model list and version lists, read when you press Find LLM (your choices are not sent); and the optional `-check-links` command.
+- The only internet requests are read-only: a look-up of a model name in the public Ollama library before a delete; the public model list and version lists, read when you press Find LLM (your choices are not sent; the list is also kept in the program's data folder, so Find LLM can show it, dated, when the website cannot be reached); and the optional `-check-links` command.
 
 ## What is tested
 
diff --git a/findcopy.go b/findcopy.go
new file mode 100644
index 0000000..983de8e
--- /dev/null
+++ b/findcopy.go
@@ -0,0 +1,175 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// encoding/json writes and reads the saved copy.
+	"encoding/json"
+	// errors makes the "no copy" answer.
+	"errors"
+	// log reports a copy that could not be saved; the search itself carries on.
+	"log"
+	// os creates the folder and the file.
+	"os"
+	// path/filepath builds the file's place inside the data folder.
+	"path/filepath"
+	// sync lets only one search save at a time.
+	"sync"
+	// time carries the moment the list was read.
+	"time"
+) // end of imports
+
+// libraryCopyFolder and libraryCopyName say where the saved copy of the library list lives, inside the program's data folder.
+const (
+	// libraryCopyFolder is the sub-folder of the data folder.
+	libraryCopyFolder = "findLibrary"
+	// libraryCopyName is the file inside it.
+	libraryCopyName = "library-list.json"
+) // end of the names
+
+// errNoCopy is the answer when no copy has been saved yet, or the data folder is unknown.
+var errNoCopy = errors.New("no saved copy of the library list exists yet")
+
+// libraryCopy is what is saved: the moment the list was read from ollama.com and the list itself.
+type libraryCopy struct {
+	// ReadAt is when the list was read from the public website.
+	ReadAt time.Time `json:"read_at"`
+	// Models are the models of the list.
+	Models []siteModel `json:"models"`
+} // end of libraryCopy
+
+// copyState remembers which reading was saved last, so the same reading is not written again and again.
+var copyState struct {
+	// mu lets one search at a time touch the state.
+	mu sync.Mutex
+	// savedAt is the moment of the reading saved last.
+	savedAt time.Time
+} // end of copyState
+
+// libraryCopyPath is the place of the saved copy; empty when the data folder is unknown.
+func libraryCopyPath() string {
+	// The data folder.
+	root := dataRoot()
+	// Unknown: nothing can be saved or read.
+	if root == "" {
+		// No place.
+		return ""
+	} // end of the folder check
+	// The file inside the program's own sub-folder.
+	return filepath.Join(root, libraryCopyFolder, libraryCopyName)
+} // end of libraryCopyPath
+
+// saveLibraryCopy keeps the list that was just read, so Find LLM can show it, dated, when ollama.com cannot be reached later; it writes only when this reading is new, and it never stops a search: a failure is only logged.
+func saveLibraryCopy(models []siteModel, at time.Time) {
+	// One at a time.
+	copyState.mu.Lock()
+	// Let go at the end.
+	defer copyState.mu.Unlock()
+	// The same reading was saved already.
+	if at.Equal(copyState.savedAt) {
+		// Nothing to do.
+		return
+	} // end of the repeat check
+	// Where to write.
+	path := libraryCopyPath()
+	// No data folder: the copy stays out; say so once in the log.
+	if path == "" {
+		// Log it.
+		log.Printf("Find LLM: no data folder is known, so the library list is not saved for offline use")
+		// Stop.
+		return
+	} // end of the folder check
+	// The text to save.
+	body, err := json.Marshal(libraryCopy{ReadAt: at, Models: models})
+	// Not expected for plain text and numbers.
+	if err != nil {
+		// Log it.
+		log.Printf("Find LLM: the library list could not be prepared for saving: %v", err)
+		// Stop.
+		return
+	} // end of the encode check
+	// The folder, private to the person running the program.
+	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
+		// Log it.
+		log.Printf("Find LLM: the folder for the saved library list could not be made: %v", err)
+		// Stop.
+		return
+	} // end of the folder check
+	// Write to a temporary file first, so a power cut never leaves half a copy.
+	tmp, err := os.CreateTemp(filepath.Dir(path), "library-*.tmp")
+	// A failure.
+	if err != nil {
+		// Log it.
+		log.Printf("Find LLM: the saved library list could not be started: %v", err)
+		// Stop.
+		return
+	} // end of the temp check
+	// Remove the temporary file if something below fails.
+	defer os.Remove(tmp.Name())
+	// Write it.
+	if _, err := tmp.Write(body); err != nil {
+		// Close it.
+		tmp.Close()
+		// Log it.
+		log.Printf("Find LLM: the saved library list could not be written: %v", err)
+		// Stop.
+		return
+	} // end of the write check
+	// Finish the file.
+	if err := tmp.Close(); err != nil {
+		// Log it.
+		log.Printf("Find LLM: the saved library list could not be finished: %v", err)
+		// Stop.
+		return
+	} // end of the close check
+	// Private to this person.
+	if err := os.Chmod(tmp.Name(), 0o600); err != nil {
+		// Not fatal on systems without file modes (Windows): carry on.
+		log.Printf("Find LLM: the saved library list could not be made private: %v", err)
+	} // end of the mode check
+	// Put it in place in one step.
+	if err := os.Rename(tmp.Name(), path); err != nil {
+		// Log it.
+		log.Printf("Find LLM: the saved library list could not be put in place: %v", err)
+		// Stop.
+		return
+	} // end of the rename check
+	// Remember this reading.
+	copyState.savedAt = at
+} // end of saveLibraryCopy
+
+// loadLibraryCopy reads the saved copy and the moment its list was read; it says errNoCopy when there is none, and an error when the file is damaged, so a damaged copy is never shown.
+func loadLibraryCopy() ([]siteModel, time.Time, error) {
+	// Where it should be.
+	path := libraryCopyPath()
+	// Unknown folder.
+	if path == "" {
+		// None.
+		return nil, time.Time{}, errNoCopy
+	} // end of the folder check
+	// Read the file.
+	body, err := os.ReadFile(path)
+	// Not there.
+	if errors.Is(err, os.ErrNotExist) {
+		// None yet.
+		return nil, time.Time{}, errNoCopy
+	} // end of the missing check
+	// Another failure.
+	if err != nil {
+		// Report it.
+		return nil, time.Time{}, err
+	} // end of the read check
+	// Decode it.
+	var c libraryCopy
+	// A damaged file.
+	if err := json.Unmarshal(body, &c); err != nil {
+		// Report it.
+		return nil, time.Time{}, err
+	} // end of the decode check
+	// An empty list or no date cannot be shown honestly.
+	if len(c.Models) == 0 || c.ReadAt.IsZero() {
+		// Treat it as no copy.
+		return nil, time.Time{}, errNoCopy
+	} // end of the content check
+	// The copy.
+	return c.Models, c.ReadAt, nil
+} // end of loadLibraryCopy
diff --git a/findllm.go b/findllm.go
index 813d7e1..d2e0256 100644
--- a/findllm.go
+++ b/findllm.go
@@ -606,6 +606,8 @@ type findPage struct {
 	Results []resultView
 	// Summary is the sentence above the results: how many models match, which are shown, when the list was read, and what was left out.
 	Summary string
+	// CopyNote says that the list is a saved copy, with its date and why; empty when the list was read live.
+	CopyNote string
 	// ShowCopy is true when at least one version fits, so the page carries Copy buttons and the monitor's own copy script.
 	ShowCopy bool
 } // end of findPage
@@ -638,9 +640,9 @@ func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.H
 		tips[key] = makeFindTip("tip-find-"+key, heading)
 	} // end of the bubble loop
 	// render draws the page for a selection.
-	render := func(w http.ResponseWriter, r *http.Request, sel findSelection, fm findMachine, problems []string, searched bool, results []resultView, total, cloud, noSize int, errText, readAt string, status int) {
+	render := func(w http.ResponseWriter, r *http.Request, sel findSelection, fm findMachine, problems []string, searched bool, results []resultView, total, cloud, noSize int, errText, readAt, copyNote string, status int) {
 		// The tick boxes.
-		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
+		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
 		// The abilities.
 		for _, k := range abilityKeys {
 			// One box.
@@ -744,7 +746,7 @@ func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.H
 		// The starting choices: chat and writing, small and medium models, no ability or memory filter.
 		sel := findSelection{Chat: true, Abilities: map[string]bool{}, Sizes: map[string]bool{"small": true, "medium": true}, Contexts: map[string]bool{}, DiskGB: fm.DiskGB, MemGB: fm.MemGB}
 		// Draw.
-		render(w, r, sel, fm, nil, false, nil, 0, 0, 0, "", "", http.StatusOK)
+		render(w, r, sel, fm, nil, false, nil, 0, 0, 0, "", "", "", http.StatusOK)
 	} // end of show
 	// search reads the library and shows the models.
 	search := func(w http.ResponseWriter, r *http.Request) {
@@ -762,18 +764,32 @@ func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.H
 		// Typed wrongly: show the form again, read nothing.
 		if len(problems) > 0 {
 			// Draw with the problems.
-			render(w, r, sel, fm, problems, false, nil, 0, 0, 0, "", "", http.StatusBadRequest)
+			render(w, r, sel, fm, problems, false, nil, 0, 0, 0, "", "", "", http.StatusBadRequest)
 			// Stop.
 			return
 		} // end of the problem check
 		// Read the current list from the library.
 		models, at, err := liveSiteList(r.Context(), time.Now)
-		// It could not be read: say why, show no data.
+		// Whether the list is a saved copy, and the note that says so.
+		var copyNote string
+		// It could not be read live: use the saved copy, clearly dated, or say why nothing is shown.
 		if err != nil {
-			// Draw with the reason.
-			render(w, r, sel, fm, nil, true, nil, 0, 0, 0, "The Ollama library could not be read just now: "+err.Error()+". Nothing is shown rather than something that may be out of date.", "", http.StatusOK)
-			// Stop.
-			return
+			// The saved copy of the last successful reading.
+			saved, savedAt, cerr := loadLibraryCopy()
+			// No usable copy: say why, show no data.
+			if cerr != nil {
+				// Draw with the reason.
+				render(w, r, sel, fm, nil, true, nil, 0, 0, 0, "The Ollama library could not be read just now: "+err.Error()+". No saved copy of the list exists yet (one is saved after each successful search), so nothing is shown rather than something that may be out of date.", "", "", http.StatusOK)
+				// Stop.
+				return
+			} // end of the copy check
+			// Work with the copy.
+			models, at = saved, savedAt
+			// The note, with the reason and the date.
+			copyNote = "ollama.com could not be reached just now (" + err.Error() + "). This is a saved copy of the library list from " + at.Format("2006-01-02 15:04:05 MST (UTC-07:00)") + ", so it may be out of date. The versions and sizes of each model cannot be checked now; open the official page of a model to see them."
+		} else {
+			// A live reading is kept for the next time ollama.com cannot be reached.
+			saveLibraryCopy(models, at)
 		} // end of the read check
 		// Apply the choices the list can answer.
 		cands, noSize, cloud := findCandidates(models, sel)
@@ -800,6 +816,13 @@ func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.H
 			go func(i int) {
 				// Free the place and report done.
 				defer func() { <-gate; wg.Done() }()
+				// A saved copy means ollama.com is not reachable: do not wait for it again for every model.
+				if copyNote != "" {
+					// Never guess: the model is listed without versions.
+					results[i] = buildResult(shown[i], nil, "ollama.com could not be reached", sel)
+					// Done.
+					return
+				} // end of the copy check
 				// Read the tags page.
 				tags, terr := fetchSiteTags(r.Context(), shown[i].Name)
 				// A failure.
@@ -821,7 +844,7 @@ func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.H
 			return (results[i].FitCount > 0) && (results[j].FitCount == 0)
 		}) // end of the sort
 		// Draw the results, with the time the list was read and its zone.
-		render(w, r, sel, fm, nil, true, results, len(cands), cloud, noSize, "", at.Format("2006-01-02 15:04:05 MST (UTC-07:00)"), http.StatusOK)
+		render(w, r, sel, fm, nil, true, results, len(cands), cloud, noSize, "", at.Format("2006-01-02 15:04:05 MST (UTC-07:00)"), copyNote, http.StatusOK)
 	} // end of search
 	// Hand back both.
 	return show, search
diff --git a/findllm_test.go b/findllm_test.go
index bdb4699..2cd4e89 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -1,14 +1,21 @@
 // Package main tells Go that this test file belongs to the same program as findllm.go.
 package main
 
-import (
-	"regexp" // import lists the standard-library packages this test file uses.
+import ( // import lists the standard-library packages this test file uses.
+	// html escapes a help text the way the page does.
+	"html"
 	// io reads a reply body.
 	"io"
 	// net/http gives the status codes.
 	"net/http"
 	// net/url builds the form values.
 	"net/url"
+	// os checks and writes the saved copy.
+	"os"
+	// path/filepath builds the place of the saved copy.
+	"path/filepath"
+	// regexp finds the copy buttons.
+	"regexp"
 	// runtime says which system the test runs on.
 	"runtime"
 	// strings searches the page text.
@@ -17,6 +24,8 @@ import (
 	"sync/atomic"
 	// testing is Go's built-in test framework.
 	"testing"
+	// time carries the moment of a reading.
+	"time"
 	// unicode/utf8 counts characters of the help texts.
 	"unicode/utf8"
 ) // end of imports
@@ -346,6 +355,8 @@ func postFind(t *testing.T, rig themeRig, v url.Values) (int, string) {
 
 // TestFindPageShowsTheChoicesAndAsksNothing checks the page before any search.
 func TestFindPageShowsTheChoicesAndAsksNothing(t *testing.T) {
+	// The saved library list goes to a throw-away folder, never to the real data folder.
+	isolateFindData(t)
 	// A fake library; it must not be asked.
 	hits := fakeSite(t, findTestPages())
 	// The rig.
@@ -387,6 +398,8 @@ func TestFindPageShowsTheChoicesAndAsksNothing(t *testing.T) {
 
 // TestFindSearchShowsFitAndNoFit checks a whole search against a fake library.
 func TestFindSearchShowsFitAndNoFit(t *testing.T) {
+	// The saved library list goes to a throw-away folder, never to the real data folder.
+	isolateFindData(t)
 	// Start with an empty saved list.
 	theListCache = listCache{}
 	// Clear it again at the end.
@@ -429,6 +442,8 @@ func TestFindSearchShowsFitAndNoFit(t *testing.T) {
 
 // TestFindSearchRules checks the refusals: wrong token, bad number, library down.
 func TestFindSearchRules(t *testing.T) {
+	// The saved library list goes to a throw-away folder, never to the real data folder.
+	isolateFindData(t)
 	// Start with an empty saved list.
 	theListCache = listCache{}
 	// Clear it again at the end.
@@ -454,10 +469,10 @@ func TestFindSearchRules(t *testing.T) {
 		// Report.
 		t.Errorf("the library was asked %d times by refused forms", atomic.LoadInt32(hits))
 	} // end of the count check
-	// The library cannot be read: the reason is shown and no model is listed.
+	// The library cannot be read and no copy was saved yet: the reason is shown and no model is listed.
 	status, body = postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}})
 	// A normal page with a warning.
-	if status != http.StatusOK || !strings.Contains(body, "could not be read just now") || strings.Contains(body, "findresult") {
+	if status != http.StatusOK || !strings.Contains(body, "could not be read just now") || !strings.Contains(body, "No saved copy of the list exists yet") || strings.Contains(body, "findresult") {
 		// Report.
 		t.Errorf("library down: status %d", status)
 	} // end of the down check
@@ -515,6 +530,8 @@ func TestFindSummaryWording(t *testing.T) {
 
 // TestFindResultsHaveCopyButtons checks that a version that fits has Copy buttons for its three commands, that a version that does not fit has none, and that the script policy is only on when there is a button.
 func TestFindResultsHaveCopyButtons(t *testing.T) {
+	// The saved library list goes to a throw-away folder, never to the real data folder.
+	isolateFindData(t)
 	// Start with an empty saved list.
 	theListCache = listCache{}
 	// Clear it again at the end.
@@ -581,3 +598,171 @@ func TestFindResultsHaveCopyButtons(t *testing.T) {
 		t.Errorf("a page without a fitting version must carry no copy button, no script and the strict policy")
 	} // end of the check
 } // end of TestFindResultsHaveCopyButtons
+
+// isolateFindData sends the data folder to a throw-away folder for one test, and forgets which reading was saved last.
+func isolateFindData(t *testing.T) {
+	// Mark this as a helper.
+	t.Helper()
+	// Put the real lookups back at the end.
+	saveFolderLookups(t)
+	// A new empty folder for this test.
+	dir := t.TempDir()
+	// The data folder lookup now points there.
+	userDataDir = func() (string, error) { return dir, nil }
+	// No reading was saved yet.
+	copyState.mu.Lock()
+	// Forget it.
+	copyState.savedAt = time.Time{}
+	// Let go.
+	copyState.mu.Unlock()
+} // end of isolateFindData
+
+// TestOfflineCopyIsSavedAndShown checks that a live search saves the list, and that when ollama.com cannot be reached later the saved copy is shown with its date, a warning, and no versions.
+func TestOfflineCopyIsSavedAndShown(t *testing.T) {
+	// A throw-away data folder.
+	isolateFindData(t)
+	// An empty in-memory list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// A working fake library.
+	fakeSite(t, findTestPages())
+	// The rig.
+	rig := newThemeRig(t)
+	// A live search saves the copy.
+	if status, _ := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"50"}, "mem_gb": {"16"}}); status != http.StatusOK {
+		// Stop.
+		t.Fatalf("live search: status %d", status)
+	} // end of the live search
+	// The file exists.
+	if _, err := os.Stat(filepath.Join(dataRoot(), libraryCopyFolder, libraryCopyName)); err != nil {
+		// Stop.
+		t.Fatalf("the copy was not saved: %v", err)
+	} // end of the file check
+	// Now the library is down: forget the in-memory list and answer 404 for everything.
+	theListCache = listCache{}
+	// The fake library with no pages.
+	hits := fakeSite(t, map[string]string{})
+	// Search again.
+	status, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"50"}, "mem_gb": {"16"}})
+	// The page works.
+	if status != http.StatusOK {
+		// Stop.
+		t.Fatalf("offline search: status %d", status)
+	} // end of the status check
+	// The model comes from the copy, the warning says so, and the date is shown.
+	for _, want := range []string{"This is a saved copy of the library list from ", "so it may be out of date", ">alpha<", "details are not available right now"} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report.
+			t.Errorf("the offline page lacks %q", want)
+		} // end of the look
+	} // end of the loop
+	// No version, no command, no copy button: nothing is guessed.
+	for _, bad := range []string{"<code>ollama pull", "<strong>Fits:</strong>", "copybtn", "<script"} {
+		// It must be absent.
+		if strings.Contains(body, bad) {
+			// Report.
+			t.Errorf("the offline page has %q", bad)
+		} // end of the check
+	} // end of the loop
+	// Only the list page was tried; the tags pages were not asked for while offline.
+	if n := atomic.LoadInt32(hits); n != 1 {
+		// Report.
+		t.Errorf("%d requests while offline, want 1", n)
+	} // end of the count check
+} // end of TestOfflineCopyIsSavedAndShown
+
+// TestDamagedCopyIsNeverShown checks that an unreadable or empty saved copy counts as no copy.
+func TestDamagedCopyIsNeverShown(t *testing.T) {
+	// A throw-away data folder.
+	isolateFindData(t)
+	// An empty in-memory list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// The library is down.
+	fakeSite(t, map[string]string{})
+	// The rig.
+	rig := newThemeRig(t)
+	// The folder and a damaged file.
+	path := libraryCopyPath()
+	// Make the folder.
+	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
+		// Stop.
+		t.Fatalf("folder: %v", err)
+	} // end of the folder check
+	// The cases: broken text, an empty list, and a list without a date.
+	for _, bad := range []string{"{not json", `{"read_at":"2026-11-08T20:36:00Z","models":[]}`, `{"models":[{"Name":"x"}]}`} {
+		// Write it.
+		if err := os.WriteFile(path, []byte(bad), 0o600); err != nil {
+			// Stop.
+			t.Fatalf("write: %v", err)
+		} // end of the write check
+		// Search.
+		status, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}})
+		// No model, and the plain reason.
+		if status != http.StatusOK || strings.Contains(body, "findresult") || strings.Contains(body, "saved copy of the library list from") || !strings.Contains(body, "could not be read just now") {
+			// Report.
+			t.Errorf("damaged copy %q was used (status %d)", bad, status)
+		} // end of the check
+	} // end of the loop
+} // end of TestDamagedCopyIsNeverShown
+
+// TestInstalledTags checks the plain-word tags with the user's real models and with missing figures.
+func TestInstalledTags(t *testing.T) {
+	// The cases come from the real models and from a model with nothing reported.
+	for _, c := range []struct {
+		// m is the model.
+		m installedModel
+		// want are the tags in order.
+		want []string
+	}{
+		// 27.4 billion, 128K tokens, pictures.
+		{installedModel{Capabilities: []string{"completion", "vision"}, Details: modelDetails{ParameterSize: "27.4B", ContextLength: 131072}}, []string{"Large model", "Long memory", "Pictures"}},
+		// 27.3 billion, 256K tokens, pictures, tools, thinking.
+		{installedModel{Capabilities: []string{"completion", "vision", "tools", "thinking"}, Details: modelDetails{ParameterSize: "27.3B", ContextLength: 262144}}, []string{"Large model", "Very long memory", "Pictures", "Tools", "Thinking"}},
+		// 8 billion, 128K, every ability in the fixed order.
+		{installedModel{Capabilities: []string{"completion", "vision", "audio", "tools", "thinking"}, Details: modelDetails{ParameterSize: "8.0B", ContextLength: 131072}}, []string{"Medium model", "Long memory", "Pictures", "Audio", "Tools", "Thinking"}},
+		// An embedding model: no ability tag, the group says it.
+		{installedModel{Capabilities: []string{"embedding"}, Details: modelDetails{ParameterSize: "1.14B", ContextLength: 262144}}, []string{"Small model", "Very long memory"}},
+		// A tiny model with a short memory, written in millions.
+		{installedModel{Capabilities: []string{"completion"}, Details: modelDetails{ParameterSize: "350M", ContextLength: 2048}}, []string{"Tiny model", "Short memory"}},
+		// Nothing reported: no tag at all, never a guess.
+		{installedModel{}, nil},
+	} {
+		// Work it out.
+		got := installedTags(c.m)
+		// Compare.
+		if strings.Join(got, "|") != strings.Join(c.want, "|") {
+			// Report.
+			t.Errorf("tags of %+v = %v, want %v", c.m.Details, got, c.want)
+		} // end of the comparison
+	} // end of the case loop
+} // end of TestInstalledTags
+
+// TestHomePageShowsTagsAndTheGroupingHelp checks that the table shows the tags under the names and the help line.
+func TestHomePageShowsTagsAndTheGroupingHelp(t *testing.T) {
+	// The page with the six real models.
+	body := pageFor(t, fullOllama(t, realModels, realPsBody))
+	// The tags of one row, the help line and its text.
+	for _, want := range []string{`<span class="modeltags">`, `<span class="mtag">Large model</span>`, `<span class="mtag">Very long memory</span>`, `<span class="mtag">Thinking</span>`, "How models are grouped", html.EscapeString(findTexts["How models are grouped"].Plain)} {
+		// Look for it.
+		if !strings.Contains(body, want) {
+			// Report.
+			t.Errorf("the home page lacks %q", want)
+		} // end of the look
+	} // end of the loop
+	// An embedding row carries no ability tag.
+	row := body[strings.Index(body, `<tr data-model="rjmalagon/gte-qwen2-instruct:1.5b-f16"`):]
+	// Its heading cell.
+	cell := row[:strings.Index(row, "</th>")]
+	// No pictures, tools, audio or thinking there.
+	for _, no := range []string{">Pictures<", ">Tools<", ">Audio<", ">Thinking<"} {
+		// It must be absent.
+		if strings.Contains(cell, no) {
+			// Report.
+			t.Errorf("the embedding row has the tag %q", no)
+		} // end of the check
+	} // end of the loop
+} // end of TestHomePageShowsTagsAndTheGroupingHelp
diff --git a/findtips.go b/findtips.go
index 0484acb..683a2bd 100644
--- a/findtips.go
+++ b/findtips.go
@@ -33,6 +33,8 @@ var findTipHeadings = map[string]string{
 	"size": "Model size", "context": "Memory of a conversation",
 	// The two fixed ticks.
 	"supported": "Supported by Ollama", "installable": "Can be installed with Ollama",
+	// The help line above the Installed models table.
+	"grouped": "How models are grouped",
 } // end of findTipHeadings
 
 // findTexts are the help texts of the Find LLM page, in the same four-part form as the rest of the program: what it means, a real case, and what it helps you decide. Every example comes from the saved library pages of 2026-11-08 (CET).
@@ -46,6 +48,15 @@ var findTexts = map[string]tooltip{
 		// What it helps with.
 		Decide: "Which model to try next, before you download anything.",
 	}, // end of Find LLM
+	// How models are grouped.
+	"How models are grouped": {
+		// What it means.
+		Plain: "Models sit in groups by what they can do. The tags under a name give its size and how much text it keeps in mind.",
+		// A real case.
+		Example: "gemma4:e4b shows Medium model, Long memory, Pictures, Audio, Tools, Thinking and sits under images or audio.",
+		// What it helps with.
+		Decide: "Which installed model suits a job, without reading the numbers.",
+	}, // end of How models are grouped
 	// Free disk space.
 	"Free disk space": {
 		// What it means.
diff --git a/perf_test.go b/perf_test.go
index 81ef129..15793eb 100644
--- a/perf_test.go
+++ b/perf_test.go
@@ -1043,6 +1043,11 @@ func TestMainPagePerformanceIcon(t *testing.T) {
 	row := body[strings.Index(body, `<tr data-model="embed:1b"`):]
 	// The cell of the row heading.
 	cell := row[:strings.Index(row, "</th>")]
+	// The plain-word tags (slice 3) come after the name; the order check below is about the icon and the name only.
+	if i := strings.Index(cell, `<span class="modeltags">`); i >= 0 {
+		// Cut the tags off.
+		cell = cell[:i]
+	} // end of the tags cut
 	// Everything must be in the cell, and the name must come last.
 	for _, want := range []string{`action="/performance"`, `aria-label="Performance of embed:1b"`, `id="tipperf-embed:1b"`, "Performance: see how fast this model runs on this machine", `<svg class="ico"`} {
 		// Look for it.
diff --git a/tableview.go b/tableview.go
index 613014d..be848a9 100644
--- a/tableview.go
+++ b/tableview.go
@@ -67,6 +67,8 @@ type rowView struct {
 	TimerSeconds int
 	// TimerExpired is true when the unload time has arrived but Ollama still lists the model; the page asks again soon.
 	TimerExpired bool
+	// Tags are the plain-word tags under the name: size class, memory of a conversation and abilities.
+	Tags []string
 } // end of rowView
 
 // groupView is one category section.
@@ -119,6 +121,8 @@ type tableView struct {
 	Groups []groupView
 	// Deleted are the models this monitor deleted and that are not installed now; they are drawn greyed out at the end of the table.
 	Deleted []deletedRow
+	// GroupedTip is the help bubble "How models are grouped", shown above the table.
+	GroupedTip tipView
 } // end of tableView
 
 // makeTip looks up the help text for a heading and attaches the element name.
@@ -199,7 +203,7 @@ func buildTableViewAt(installed []installedModel, loaded []loadedModel, now time
 	// Mark each model as loaded or not, then sort into category sections (both from the terminal version).
 	groups := groupRows(combine(installed, loaded))
 	// Start the view with the total.
-	view := tableView{Total: len(installed)}
+	view := tableView{Total: len(installed), GroupedTip: makeFindTip("tip-grouped", "How models are grouped")}
 	// One heading per column, in the fixed order.
 	for i, title := range installedColumns {
 		// Add the heading with its bubble.
@@ -225,7 +229,7 @@ func buildTableViewAt(installed []installedModel, loaded []loadedModel, now time
 				timer, timerSecs, timerExpired = timerFor(byName[m.Name], now)
 			} // end of the timer
 			// Add the row: the name first, then the nine cells in the same order and formats as the terminal table.
-			gv.Rows = append(gv.Rows, rowView{Name: m.Name, Loaded: r.Loaded, StateWord: stateWord(r.Loaded), Timer: timer, TimerSeconds: timerSecs, TimerExpired: timerExpired, Cells: []string{
+			gv.Rows = append(gv.Rows, rowView{Name: m.Name, Tags: installedTags(m), Loaded: r.Loaded, StateWord: stateWord(r.Loaded), Timer: timer, TimerSeconds: timerSecs, TimerExpired: timerExpired, Cells: []string{
 				// Loaded or not, symbol plus words.
 				stateText(r.Loaded),
 				// Size on disk.
diff --git a/tags.go b/tags.go
new file mode 100644
index 0000000..5a33a79
--- /dev/null
+++ b/tags.go
@@ -0,0 +1,75 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+// abilityTagWords are the short words shown as tags for the abilities Ollama reports; embedding is left out because the group heading already says it.
+var abilityTagWords = []struct {
+	// Key is the word Ollama uses in its capability list.
+	Key string
+	// Word is the short word shown.
+	Word string
+}{
+	// Pictures.
+	{"vision", "Pictures"},
+	// Audio.
+	{"audio", "Audio"},
+	// Tools.
+	{"tools", "Tools"},
+	// Step-by-step thinking.
+	{"thinking", "Thinking"},
+} // end of abilityTagWords
+
+// installedTags gives the plain-word tags of one installed model: its size class, its memory-of-a-conversation class, and its abilities; a figure Ollama did not report gives no tag, never a guess.
+func installedTags(m installedModel) []string {
+	// The tags so far.
+	var tags []string
+	// The size class, from the parameter size Ollama reports (such as 27.3B).
+	if b, ok := paramsBillions(m.Details.ParameterSize); ok {
+		// Find the class and add its label.
+		tags = append(tags, paramClassLabel(paramClassOf(b))+" model")
+	} // end of the size check
+	// The memory of a conversation: Ollama reports tokens, and the library pages count a K as 1024 tokens (128K is 131072), so the same unit is used here.
+	if m.Details.ContextLength > 0 {
+		// Thousands of tokens.
+		k := float64(m.Details.ContextLength) / 1024
+		// Find the class and add its label.
+		tags = append(tags, contextClassLabel(contextClassOf(k))+" memory")
+	} // end of the memory check
+	// The abilities, in a fixed order.
+	for _, a := range abilityTagWords {
+		// Only the ones the model reports.
+		if hasCapability(m.Capabilities, a.Key) {
+			// Add the word.
+			tags = append(tags, a.Word)
+		} // end of the ability check
+	} // end of the ability loop
+	// The tags.
+	return tags
+} // end of installedTags
+
+// paramClassLabel gives the plain word of a size class key.
+func paramClassLabel(key string) string {
+	// Look the key up in the approved table.
+	for _, c := range paramClasses {
+		// A match.
+		if c.Key == key {
+			// The word.
+			return c.Label
+		} // end of the match check
+	} // end of the loop
+	// Not reached for a key from paramClassOf.
+	return key
+} // end of paramClassLabel
+
+// contextClassLabel gives the plain word of a memory class key.
+func contextClassLabel(key string) string {
+	// Look the key up in the approved table.
+	for _, c := range contextClasses {
+		// A match.
+		if c.Key == key {
+			// The word.
+			return c.Label
+		} // end of the match check
+	} // end of the loop
+	// Not reached for a key from contextClassOf.
+	return key
+} // end of contextClassLabel
diff --git a/web/about.html b/web/about.html
index 304968d..5eb50b2 100644
--- a/web/about.html
+++ b/web/about.html
@@ -42,7 +42,7 @@
 {{/* Where the source lives. */}}
 <tr><th scope="row">Source code</th><td><a href="{{.Repository}}" target="_blank" rel="noopener noreferrer">{{.Repository}}<span class="sr-only"> (opens in a new window)</span></a> (private repository; opens only for its owner)</td></tr>
 {{/* Where the data goes. */}}
-<tr><th scope="row">Privacy</th><td>Runs only on this computer. The requests to the outside are read-only and go to the public Ollama website only: the optional check of a model's name before it is deleted, and, when you press Find LLM, a read of the public model list and of the version lists of the first ten models. Nothing about you or your choices is sent. Links to the developer's sites open in a new window only when you click them; nothing is sent to them before that.</td></tr>
+<tr><th scope="row">Privacy</th><td>Runs only on this computer. The requests to the outside are read-only and go to the public Ollama website only: the optional check of a model's name before it is deleted, and, when you press Find LLM, a read of the public model list and of the version lists of the first ten models. The model list is also kept in this program's data folder on this computer, so that Find LLM can show it, with its date, when the website cannot be reached. Nothing about you or your choices is sent. Links to the developer's sites open in a new window only when you click them; nothing is sent to them before that.</td></tr>
 {{/* The licence. */}}
 <tr><th scope="row">Licence</th><td><a href="{{.LicenceURL}}" target="_blank" rel="noopener noreferrer">{{.Licence}}<span class="sr-only"> (opens in a new window)</span></a>. {{.Copyright}}</td></tr>
 {{/* End of the table. */}}
diff --git a/web/app.css b/web/app.css
index b487faf..c77f328 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2604,3 +2604,33 @@ html[data-size="medium"] svg[width="22"] {
   /* Smaller than the text beside it. */
   font-size: 0.9rem;
 } /* end of rule */
+
+/* The tags under a model name sit on their own line and wrap on a narrow window. */
+.modeltags {
+  /* Chips side by side. */
+  display: flex;
+  /* Wrap when the column is narrow. */
+  flex-wrap: wrap;
+  /* Space between the chips. */
+  gap: 0.25rem;
+  /* A little room above, and none below. */
+  margin-top: 0.25rem;
+} /* end of rule */
+
+/* One tag: a small outlined chip in normal weight, so the model name stays the strongest thing in the cell. */
+.mtag {
+  /* Small text. */
+  font-size: 0.75rem;
+  /* Normal weight, even inside the bold row heading. */
+  font-weight: 400;
+  /* A thin outline. */
+  border: 1px solid var(--border);
+  /* Round corners. */
+  border-radius: 0.6rem;
+  /* Room inside. */
+  padding: 0 0.45rem;
+  /* The muted text colour. */
+  color: var(--muted);
+  /* A chip never breaks in the middle. */
+  white-space: nowrap;
+} /* end of rule */
diff --git a/web/findllm.html b/web/findllm.html
index 1f60ba2..83c1f3b 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -67,6 +67,7 @@
 {{if .Searched}}
 <h2>Models found</h2>
 {{if .Error}}<p class="warn" role="alert"><strong>&#9888;</strong> {{.Error}}</p>{{else}}
+{{if .CopyNote}}<p class="warn" role="alert"><strong>&#9888;</strong> {{.CopyNote}}</p>{{end}}
 <p class="muted" role="status">{{.Summary}}</p>
 {{/* The numbers $ri and $vi make every command on the page get its own name, so each Copy button finds its own command. */}}
 {{range $ri, $r := .Results}}
diff --git a/web/index.html b/web/index.html
index 2299dfb..9b77344 100644
--- a/web/index.html
+++ b/web/index.html
@@ -357,6 +357,8 @@
 {{else}}
 <p class="keytoggle" id="key"><a href="/?key=open#key"><span aria-hidden="true">&#9656;</span> Key to the symbols <span class="keyhint">(click to show)</span></a></p>
 {{end}}
+{{/* The help line for the tags under the model names. */}}
+<p class="muted groupedhelp">Tags under each name: <span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Table.GroupedTip.ID}}">How models are grouped</span><span class="tip" role="tooltip" id="{{.Table.GroupedTip.ID}}">{{template "tip" .Table.GroupedTip}}</span></span></p>
 {{/* The key itself, drawn only while it is open. */}}
 {{if .KeyOpen}}
 <ul class="legend muted" aria-label="How to read this table">
@@ -465,7 +467,9 @@
 </form>
 {{/* End of the icon column. */}}
 </span>
-{{.Name}}</th>
+{{.Name}}
+{{/* The plain-word tags under the name: size, memory of a conversation and abilities; a figure Ollama did not report gives no tag. */}}
+{{if .Tags}}<span class="modeltags">{{range .Tags}}<span class="mtag">{{.}}</span>{{end}}</span>{{end}}</th>
 {{/* The state cell: a dot (solid green when loaded, an empty ring when not) plus the words, so colour is never the only signal. */}}
 <td>
 {{/* Two small icons stacked in a fixed-width column, centred above each other: the Modelfile page icon on top (for every model) and the gear just below it (only for a model that is not loaded; on a loaded row the Modelfile icon is alone, level with the delete icon of the first column). */}}
diff --git a/webtable_test.go b/webtable_test.go
index efd8a99..3f81668 100644
--- a/webtable_test.go
+++ b/webtable_test.go
@@ -134,10 +134,10 @@ func TestTablePageRealModels(t *testing.T) {
 func TestTableHelpForEveryHeading(t *testing.T) {
 	// Fake Ollama with the six real models.
 	body := pageFor(t, fullOllama(t, realModels, realPsBody))
-	// Ten column bubbles, two category bubbles and the bubbles of the API health and Event log headings; the short tips of the row icons are counted apart.
-	if n := strings.Count(body, `role="tooltip"`) - strings.Count(body, `class="tip tip-icon"`); n != 16 {
+	// Ten column bubbles, two category bubbles, the bubbles of the API health and Event log headings and the bubble "How models are grouped"; the short tips of the row icons are counted apart.
+	if n := strings.Count(body, `role="tooltip"`) - strings.Count(body, `class="tip tip-icon"`); n != 17 {
 		// Report the difference.
-		t.Errorf("%d bubbles, want 16", n)
+		t.Errorf("%d bubbles, want 17", n)
 	} // end of the bubble count
 	// Every column title must be a focusable heading.
 	for _, col := range installedColumns {
@@ -155,9 +155,9 @@ func TestTableHelpForEveryHeading(t *testing.T) {
 	// Find every aria-describedby value.
 	refs := regexp.MustCompile(`aria-describedby="([^"]+)"`).FindAllStringSubmatch(body, -1)
 	// There must be one per bubble (the row icons have their own, counted apart).
-	if n := len(refs) - strings.Count(body, `class="tip tip-icon"`); n != 16 {
+	if n := len(refs) - strings.Count(body, `class="tip tip-icon"`); n != 17 {
 		// Report the difference.
-		t.Errorf("%d aria-describedby attributes, want 16", n)
+		t.Errorf("%d aria-describedby attributes, want 17", n)
 	} // end of the reference count
 	// Each one must point at an element that exists.
 	for _, m := range refs {
@@ -188,8 +188,8 @@ func TestTableAccessibility(t *testing.T) {
 		{`scope="colgroup"`, 2},
 		// The scroll box is a labelled region that the keyboard can reach.
 		{`role="region"`, 2},
-		// Fourteen headings (ten columns, two categories, API health and Event log) plus the two scroll boxes (models and event log) can take the focus.
-		{`tabindex="0"`, 18},
+		// Fifteen headings (ten columns, two categories, API health, Event log and "How models are grouped") plus the two scroll boxes (models and event log) can take the focus.
+		{`tabindex="0"`, 19},
 	} { // end of the list
 		// Count it.
 		if n := strings.Count(body, c.text); n != c.want {
OCC_PATCH_93_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched and new files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} changed or new files have the expected sha256"

# gofmt lists files whose layout differs from the standard.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code.
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once.
go test -count=1 ./... || fail "go test failed"
# Report it.
pass "go test: all tests pass"

# Build the program for this computer, as the project always does (no C compiler: CGO_ENABLED=0; -trimpath removes folder names).
CGO_ENABLED=0 go build -trimpath -o bin/LLMsControlDock . || fail "go build failed"
# Report it.
pass "build for this computer: bin/LLMsControlDock"

# Compile (without keeping the result) for all six systems; nothing here uses GitHub Actions.
for TARGET in linux/arm64 linux/amd64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Compile; the output goes to /dev/null because only errors matter.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -trimpath -o /dev/null . || fail "compile for $TARGET failed"
  # Report it.
  pass "compile for $TARGET"
# End of the loop over the systems.
done


# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  start bin/LLMsControlDock and look at the tags under the model names (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
