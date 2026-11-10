#!/usr/bin/env bash
# Script 104 (Find LLM page, Sort by): changing the Sort by choice while models are listed now puts the models already shown in the new order at once, with no new search and no new reading of ollama.com; a small script file (sortpick.js, only on a page that lists models) sends the form to the new re-sort address, and the kept search remembers the new order. Without the script, pressing Find LLM still applies the order as before. Tests follow.
# Run it from the project folder, on the branch feature/find-llm-green-arrows-kept-results (after scripts 103 and 103b): cd ~/LLMsControlDock && bash scripts/104-step67-find-llm-sort-by-resorts-results.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 103b), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm.go"]="340bbbae6dd919c637d49041db17a7f6e980f7870b3f78a41e10c77b1dac80a9"
BEFORE["findllm_test.go"]="593d60fd57ae4fca0de6bf229af973090e175730cfde0311ffa7d7ba15271c43"
BEFORE["web.go"]="d38f4b618ddf521d0090e4526272635a26760a63eaeb7be059c2584b9e11f6df"
BEFORE["web/findllm.html"]="1120893ee9823c48f259f06288f88849c60059a758b9268a5957a4ecec16fe83"
AFTER["findllm.go"]="ad2704751ec927dd5e0910393891c8ce152f134a69a9cd982aac165cf426acbb"
AFTER["findllm_test.go"]="af587df3b3a56282e654300562435c424d45fe1aae0eeee9780e06891bfa06e6"
AFTER["web.go"]="2e67258c7106deea5a706547c3c4b613a0d7522374f1353079a2ae5d15cce72b"
AFTER["web/findllm.html"]="832a170ecfa62cda60cbd212849f732181600569d0d307e967a66446057f1d3b"
AFTER["sortpick.go"]="2035dee59658909b42790799c4e9279fec6894981b40777e52b249b85ae58a48"
AFTER["sortpick_test.go"]="d3a63e057536a61bf588a3960f6af3bfe7b21ddd417b132abebdff1e641ff790"
AFTER["web/sortpick.js"]="ff6d53cb8aedf4a28b38916c55c163dfb8b39af3b416c9eecb285533159ff59a"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/find-llm-green-arrows-kept-results"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 103b must have been applied: the bottom arrow is shown only when models are listed.
grep -q 'only when models are listed' web/findllm.html || fail "scripts 103 and 103b must be applied first"
# Report it.
pass "scripts 103 and 103b are applied"

# Refuse to run twice: the new script file exists when this change was applied before.
if [ -e web/sortpick.js ]; then fail "web/sortpick.js already exists: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_94_END'
diff --git a/findllm.go b/findllm.go
index 44e0795..7539e55 100644
--- a/findllm.go
+++ b/findllm.go
@@ -1016,6 +1016,8 @@ type findPage struct {
 	Summary string
 	// CopyNote says that the list is a saved copy, with its date and why; empty when the list was read live.
 	CopyNote string
+	// CanResort is true when models are listed, so the Sort by choice re-sorts them at once (the page then carries the small sort script).
+	CanResort bool
 	// ShowCopy is true when at least one version fits, so the page carries Copy buttons and the monitor's own copy script.
 	ShowCopy bool
 	// CloudResults are the cloud-only models shown in their own section.
@@ -1074,8 +1076,8 @@ type findKept struct {
 	copyNote, instNote string
 } // end of findKept
 
-// findLLMHandlers makes the three handlers of the Find LLM page: the first shows the choices (or the kept results of the last search), the second reads the library and shows the models, the third forgets the kept search; the second asks the public website, and only the address of its page leaves this computer.
-func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.HandlerFunc, http.HandlerFunc, http.HandlerFunc) {
+// findLLMHandlers makes the four handlers of the Find LLM page: the first shows the choices (or the kept results of the last search), the second reads the library and shows the models, the third forgets the kept search, the fourth sorts the kept results again; the second asks the public website, and only the address of its page leaves this computer.
+func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.HandlerFunc, http.HandlerFunc, http.HandlerFunc, http.HandlerFunc) {
 	// keptMu guards kept, because requests run side by side.
 	var keptMu sync.Mutex
 	// kept is the last successful search; nil when there is none.
@@ -1193,6 +1195,8 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 				} // end of the fit check
 			} // end of the version loop
 		} // end of the model loop
+		// Models are listed: a change of the Sort by choice may re-sort them.
+		data.CanResort = searched && len(results)+len(cloudRes) > 0
 		// Build the page in memory first, so a template error gives a clean 500.
 		var buf bytes.Buffer
 		// Fill the template.
@@ -1205,7 +1209,7 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 			return
 		} // end of the template check
 		// A page with Copy buttons may run the monitor's own script file, and nothing else.
-		if data.ShowCopy {
+		if data.ShowCopy || data.CanResort {
 			// Replace the strict policy by the one that allows the script file.
 			w.Header().Set("Content-Security-Policy", contentSecurityPolicyWithScript)
 		} // end of the script policy
@@ -1390,10 +1394,66 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 		// Back to the page with the starting choices; a redirect keeps a reload from sending the form again.
 		http.Redirect(w, r, "/findllm", http.StatusSeeOther)
 	} // end of reset
-	// Hand back all three.
-	return show, search, reset
+	// resort sorts the kept results again for the chosen order, without reading anything from the internet.
+	resort := func(w http.ResponseWriter, r *http.Request) {
+		// Only the page's own form may do this.
+		if !tokenValid(token, r.PostFormValue("token")) {
+			// Refuse.
+			http.Error(w, "forbidden", http.StatusForbidden)
+			// Stop.
+			return
+		} // end of the token check
+		// Change the kept search under the lock.
+		keptMu.Lock()
+		// Only when there is a kept search.
+		if kept != nil {
+			// The new order: Name A to Z or, by default, most downloaded.
+			if r.PostFormValue("sort") == "name" {
+				// By name.
+				kept.sel.Sort = "name"
+			} else {
+				// By downloads.
+				kept.sel.Sort = "downloads"
+			} // end of the order choice
+			// Sort the local models, keeping the ones with a fitting version first.
+			resortViews(kept.results, kept.sel.Sort == "name", true)
+			// Sort the cloud-only models (they have no versions to fit).
+			resortViews(kept.cloudRes, kept.sel.Sort == "name", false)
+		} // end of the kept check
+		keptMu.Unlock()
+		// Back to the page at the Sort by choice; a redirect keeps a reload from sending the form again.
+		http.Redirect(w, r, "/findllm#sortby", http.StatusSeeOther)
+	} // end of resort
+	// Hand back all four.
+	return show, search, reset, resort
 } // end of findLLMHandlers
 
+// resortViews puts shown models in order again: Name A to Z or most downloaded first (equal counts by name); with fitFirst a model that has a fitting version stays ahead of the others.
+func resortViews(list []resultView, byName, fitFirst bool) {
+	// A stable sort, so equal models keep their places.
+	sort.SliceStable(list, func(i, j int) bool {
+		// Fitting models first, when asked.
+		if fitFirst && (list[i].FitCount > 0) != (list[j].FitCount > 0) {
+			// The fitting one is first.
+			return list[i].FitCount > 0
+		} // end of the fit check
+		// By name.
+		if byName {
+			// A to Z.
+			return list[i].Name < list[j].Name
+		} // end of the name order
+		// The download counts.
+		pi, pj := pullsNumber(list[i].Pulls), pullsNumber(list[j].Pulls)
+		// The higher count first.
+		if pi != pj {
+			// Decide by count.
+			return pi > pj
+		} // end of the count check
+		// Then by name.
+		return list[i].Name < list[j].Name
+	}) // end of the sort
+} // end of resortViews
+
 // findSummary writes the sentence above the results in correct singular and plural.
 func findSummary(shown, total, cloud, noSize int, readAt string) string {
 	// Nothing matched.
diff --git a/findllm_test.go b/findllm_test.go
index d1c80c7..912e902 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -591,8 +591,8 @@ func TestFindResultsHaveCopyButtons(t *testing.T) {
 			t.Errorf("the results lack %q", want)
 		} // end of the look
 	} // end of the loop
-	// The script once, the status line for screen readers, and a policy that allows this address's scripts only.
-	if strings.Count(body, `<script src="/copy.js" defer></script>`) != 1 || strings.Count(body, "<script") != 1 || !strings.Contains(body, `id="copystatus"`) {
+	// The copy script once, the sort script once (and no other), the status line for screen readers, and a policy that allows this address's scripts only.
+	if strings.Count(body, `<script src="/copy.js" defer></script>`) != 1 || strings.Count(body, `<script src="/sortpick.js" defer></script>`) != 1 || strings.Count(body, "<script") != 2 || !strings.Contains(body, `id="copystatus"`) {
 		// Report.
 		t.Errorf("script or status line missing")
 	} // end of the script check
@@ -601,16 +601,16 @@ func TestFindResultsHaveCopyButtons(t *testing.T) {
 		// Report.
 		t.Errorf("policy %q", csp)
 	} // end of the policy check
-	// A search where nothing fits (no disk space at all) has no button, no script and the strict policy.
+	// A search where nothing fits (no disk space at all) has no copy button and no copy script (the sort script stays, because models are listed).
 	res2 := post(t, rig.h, "/findllm/search", url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"0.1"}, "mem_gb": {"0.1"}}, fromThisPage)
 	// Close it at the end.
 	defer res2.Body.Close()
 	// Read it.
 	raw2, _ := io.ReadAll(res2.Body)
 	// Nothing to copy.
-	if strings.Contains(string(raw2), "copybtn") || strings.Contains(string(raw2), "<script") || strings.Contains(res2.Header.Get("Content-Security-Policy"), "script-src") {
+	if strings.Contains(string(raw2), "copybtn") || strings.Contains(string(raw2), "/copy.js") || strings.Count(string(raw2), "<script") > 1 {
 		// Report.
-		t.Errorf("a page without a fitting version must carry no copy button, no script and the strict policy")
+		t.Errorf("a page without a fitting version must carry no copy button and no copy script")
 	} // end of the check
 } // end of TestFindResultsHaveCopyButtons
 
@@ -674,7 +674,7 @@ func TestOfflineCopyIsSavedAndShown(t *testing.T) {
 		} // end of the look
 	} // end of the loop
 	// No version, no command, no copy button: nothing is guessed.
-	for _, bad := range []string{"<code>ollama pull", "<strong>Fits:</strong>", "copybtn", "<script"} {
+	for _, bad := range []string{"<code>ollama pull", "<strong>Fits:</strong>", "copybtn", "/copy.js"} {
 		// It must be absent.
 		if strings.Contains(body, bad) {
 			// Report.
diff --git a/sortpick.go b/sortpick.go
new file mode 100644
index 0000000..176b667
--- /dev/null
+++ b/sortpick.go
@@ -0,0 +1,22 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// embed lets the script file be stored inside the executable (the blank name means we only need its side effect).
+	_ "embed"
+	// net/http provides requests and status codes.
+	"net/http"
+) // end of imports
+
+// sortPickJS is the small script behind the Sort by choice of the Find LLM page, stored inside the executable at build time.
+//
+//go:embed web/sortpick.js
+var sortPickJS []byte
+
+// sortPickHandler sends the script file.
+func sortPickHandler(w http.ResponseWriter, r *http.Request) {
+	// Tell the browser this is JavaScript.
+	w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
+	// Send it.
+	w.Write(sortPickJS)
+} // end of sortPickHandler
diff --git a/sortpick_test.go b/sortpick_test.go
new file mode 100644
index 0000000..d4cb0fb
--- /dev/null
+++ b/sortpick_test.go
@@ -0,0 +1,203 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages the tests use.
+	// net/http gives the method names and status codes.
+	"net/http"
+	// net/url builds the form values.
+	"net/url"
+	// strings searches the page text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// TestResortViewsOrder checks the new order of shown models for both choices, with and without the fit-first grouping.
+func TestResortViewsOrder(t *testing.T) {
+	// The names of a list, in order.
+	names := func(l []resultView) string {
+		// Collect them.
+		var out []string
+		// Each model.
+		for _, v := range l {
+			// One name.
+			out = append(out, v.Name)
+		} // end of the loop
+		// As text.
+		return strings.Join(out, ",")
+	} // end of names
+	// A list: bravo and alpha fit, charlie does not but has the most downloads, delta ties with alpha.
+	list := func() []resultView {
+		// A fresh copy each time.
+		return []resultView{
+			{Name: "charlie", Pulls: "12M"},
+			{Name: "bravo", Pulls: "2M", FitCount: 1},
+			{Name: "delta", Pulls: "900K", FitCount: 1},
+			{Name: "alpha", Pulls: "900K", FitCount: 1},
+		}
+	} // end of list
+	// Most downloaded with fit first: the fitting ones by downloads (ties by name), then the rest.
+	l := list()
+	// Sort.
+	resortViews(l, false, true)
+	// Check.
+	if got := names(l); got != "bravo,alpha,delta,charlie" {
+		// Report.
+		t.Errorf("downloads, fit first: %q", got)
+	} // end of the check
+	// Name A to Z with fit first.
+	l = list()
+	// Sort.
+	resortViews(l, true, true)
+	// Check.
+	if got := names(l); got != "alpha,bravo,delta,charlie" {
+		// Report.
+		t.Errorf("name, fit first: %q", got)
+	} // end of the check
+	// Cloud models have no fit grouping: by downloads, then by name.
+	l = list()
+	// Sort.
+	resortViews(l, false, false)
+	// Check.
+	if got := names(l); got != "charlie,bravo,alpha,delta" {
+		// Report.
+		t.Errorf("downloads, no fit: %q", got)
+	} // end of the check
+	// And by name.
+	resortViews(l, true, false)
+	// Check.
+	if got := names(l); got != "alpha,bravo,charlie,delta" {
+		// Report.
+		t.Errorf("name, no fit: %q", got)
+	} // end of the check
+} // end of TestResortViewsOrder
+
+// TestFindResortKeepsTheSearch checks the whole round trip: the choice carries the re-sort address and the script only when models are listed, a wrong token is refused, a re-sort changes the kept order choice without a new reading of the library, and without a kept search it just goes back to the page.
+func TestFindResortKeepsTheSearch(t *testing.T) {
+	// The saved library list goes to a throw-away folder.
+	isolateFindData(t)
+	// Start with an empty saved list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// A fake library, with a counter of the pages read.
+	hits := fakeSite(t, findTestPages())
+	// The rig (a new program: nothing is kept).
+	rig := newThemeRig(t)
+	// Before any search: no re-sort address, no script.
+	_, _, first := get(t, rig.h, http.MethodGet, "/findllm")
+	// Check.
+	if strings.Contains(first, "data-resort") || strings.Contains(first, "/sortpick.js") {
+		// Report.
+		t.Error("the starting page carries the re-sort address or script")
+	} // end of the check
+	// A re-sort with no kept search goes back to the page and changes nothing.
+	res := post(t, rig.h, "/findllm/resort", url.Values{"token": {rig.token}, "sort": {"name"}}, fromThisPage)
+	// Check.
+	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/findllm#sortby" {
+		// Report.
+		t.Errorf("resort without a search = %d to %q", res.StatusCode, res.Header.Get("Location"))
+	} // end of the check
+	// A search with the default order.
+	_, found := postFind(t, rig, url.Values{"token": {rig.token}, "disk_gb": {"100"}, "mem_gb": {"64"}})
+	// The results page has the re-sort address and the script, once.
+	if !strings.Contains(found, `data-resort="/findllm/resort"`) || strings.Count(found, `<script src="/sortpick.js" defer></script>`) != 1 {
+		// Report.
+		t.Fatal("the results page lacks the re-sort address or the script")
+	} // end of the check
+	// The script must be allowed by the page's security policy.
+	r2 := post(t, rig.h, "/findllm/search", url.Values{"token": {rig.token}}, fromThisPage)
+	// Check.
+	if csp := r2.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe-inline") {
+		// Report.
+		t.Errorf("policy on the results page: %q", csp)
+	} // end of the check
+	// Count the library reads so far.
+	before := *hits
+	// A wrong token is refused.
+	if bad := post(t, rig.h, "/findllm/resort", url.Values{"token": {"wrong"}, "sort": {"name"}}, fromThisPage); bad.StatusCode != http.StatusForbidden {
+		// Report.
+		t.Errorf("resort with a wrong token = %d, want 403", bad.StatusCode)
+	} // end of the check
+	// Still the default order after the refusal.
+	if _, _, still := get(t, rig.h, http.MethodGet, "/findllm"); !strings.Contains(still, `<option value="downloads" selected>`) {
+		// Report.
+		t.Error("a refused re-sort changed the order choice")
+	} // end of the check
+	// A real re-sort to Name A to Z.
+	res = post(t, rig.h, "/findllm/resort", url.Values{"token": {rig.token}, "sort": {"name"}}, fromThisPage)
+	// It redirects back to the Sort by choice.
+	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/findllm#sortby" {
+		// Report.
+		t.Errorf("resort = %d to %q", res.StatusCode, res.Header.Get("Location"))
+	} // end of the check
+	// The page now shows Name A to Z and still the results.
+	_, _, named := get(t, rig.h, http.MethodGet, "/findllm")
+	// Check.
+	if !strings.Contains(named, `<option value="name" selected>Name A to Z</option>`) || !strings.Contains(named, "Models found") {
+		// Report.
+		t.Error("after the re-sort the page lacks the new choice or the results")
+	} // end of the check
+	// Back to the default order.
+	post(t, rig.h, "/findllm/resort", url.Values{"token": {rig.token}}, fromThisPage)
+	// Check.
+	if _, _, back := get(t, rig.h, http.MethodGet, "/findllm"); !strings.Contains(back, `<option value="downloads" selected>`) {
+		// Report.
+		t.Error("the default order did not come back")
+	} // end of the check
+	// Nothing was read from the library again.
+	if *hits != before {
+		// Report.
+		t.Errorf("library pages read: %d before, %d after the re-sorts", before, *hits)
+	} // end of the check
+	// A search with no match has no re-sort address.
+	_, none := postFind(t, rig, url.Values{"token": {rig.token}, "ab_embedding": {"on"}, "ab_tools": {"on"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
+	// Check.
+	if strings.Contains(none, "data-resort") || strings.Contains(none, "/sortpick.js") {
+		// Report.
+		t.Error("a page with no models carries the re-sort address or script")
+	} // end of the check
+} // end of TestFindResortKeepsTheSearch
+
+// TestSortPickScriptIsServedAndHarmless checks the script is sent as JavaScript, only on GET, and does nothing but send the page's own form to the re-sort address.
+func TestSortPickScriptIsServedAndHarmless(t *testing.T) {
+	// A rig.
+	rig := newThemeRig(t)
+	// Fetch the script.
+	status, header, body := get(t, rig.h, http.MethodGet, "/sortpick.js")
+	// Found and typed as JavaScript.
+	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/javascript") || !strings.Contains(body, "data-resort") {
+		// Report.
+		t.Fatalf("status %d, type %q", status, header.Get("Content-Type"))
+	} // end of the check
+	// Only GET is allowed.
+	if res := post(t, rig.h, "/sortpick.js", url.Values{}, fromThisPage); res.StatusCode != http.StatusMethodNotAllowed {
+		// Report.
+		t.Errorf("POST /sortpick.js = %d, want 405", res.StatusCode)
+	} // end of the check
+	// Nothing that sends data away, runs text as code, writes markup or opens an address.
+	for _, bad := range []string{"fetch(", "XMLHttpRequest", "sendBeacon", "WebSocket", "eval(", "new Function", "innerHTML", "outerHTML", "document.write", "http://", "https://", "location", "import("} {
+		// Present.
+		if strings.Contains(body, bad) {
+			// Report.
+			t.Errorf("the sort script must not contain %q", bad)
+		} // end of the check
+	} // end of the loop
+	// Every code line carries a comment on the line above it or ends a block.
+	lines := strings.Split(body, "\n")
+	// Check from the second line.
+	for i := 1; i < len(lines); i++ {
+		// The trimmed line.
+		l := strings.TrimSpace(lines[i])
+		// Blank lines, comments and lines that close a block need nothing.
+		if l == "" || strings.HasPrefix(l, "//") || strings.HasPrefix(l, "}") {
+			// Fine.
+			continue
+		} // end of the skip check
+		// The line above must be a comment.
+		if !strings.HasPrefix(strings.TrimSpace(lines[i-1]), "//") {
+			// Report.
+			t.Errorf("sortpick.js line %d has no comment above it: %q", i+1, l)
+		} // end of the comment check
+	} // end of the line loop
+} // end of TestSortPickScriptIsServedAndHarmless
diff --git a/web/findllm.html b/web/findllm.html
index c161c2d..075fd3e 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -93,7 +93,7 @@
 </fieldset>
 {{/* The button: the first and only thing that reads the internet. */}}
 {{/* The button, with the order of the results beside it. */}}
-<p class="findaction"><button type="submit" class="btn-solid btn-go">Find LLM</button> <label class="sortpick" for="sortby">Sort by <select class="keepselect" id="sortby" name="sort"><option value="downloads"{{if not .SortName}} selected{{end}}>Most downloaded</option><option value="name"{{if .SortName}} selected{{end}}>Name A to Z</option></select></label>{{if .Searched}} <span class="tipbox"><button type="submit" class="btn-plain" formaction="/findllm/reset" formnovalidate aria-describedby="tip-reset">Reset Find LLM search options</button><span class="tip tip-icon" role="tooltip" id="tip-reset">Forget the last search and show the starting ticks.</span></span>{{end}} <span class="tipbox backhere"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback-row"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback-row">Back to the monitor</span></span></p>
+<p class="findaction"><button type="submit" class="btn-solid btn-go">Find LLM</button> <label class="sortpick" for="sortby">Sort by <select class="keepselect" id="sortby" name="sort"{{if .CanResort}} data-resort="/findllm/resort"{{end}}><option value="downloads"{{if not .SortName}} selected{{end}}>Most downloaded</option><option value="name"{{if .SortName}} selected{{end}}>Name A to Z</option></select></label>{{if .Searched}} <span class="tipbox"><button type="submit" class="btn-plain" formaction="/findllm/reset" formnovalidate aria-describedby="tip-reset">Reset Find LLM search options</button><span class="tip tip-icon" role="tooltip" id="tip-reset">Forget the last search and show the starting ticks.</span></span>{{end}} <span class="tipbox backhere"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback-row"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback-row">Back to the monitor</span></span></p>
 </form>
 {{/* The results appear only after the button was pressed. */}}
 {{if .Searched}}
@@ -161,6 +161,7 @@
 </section>
 </main>
 {{if .ShowCopy}}<script src="/copy.js" defer></script>{{end}}
+{{if .CanResort}}<script src="/sortpick.js" defer></script>{{end}}
 </body>
 </html>
 {{/* A state icon with its tooltip: the check mark (can be installed), the cross (cannot be installed) or the cloud (runs on Ollama's servers). The words next to it say the same, so the symbol is never the only signal. */}}
diff --git a/web/sortpick.js b/web/sortpick.js
new file mode 100644
index 0000000..6357727
--- /dev/null
+++ b/web/sortpick.js
@@ -0,0 +1,17 @@
+// Sort by choice on the Find LLM page: when the person changes it while models are listed, the page sends the form to the re-sort address, so the models already shown are put in the new order at once (nothing is read from the internet).
+(function () {
+  // The choice carries the re-sort address only when models are listed.
+  var pick = document.querySelector('select[data-resort]');
+  // Nothing to do without it.
+  if (!pick || !pick.form) {
+    // Stop here.
+    return;
+  }
+  // When the person picks another order.
+  pick.addEventListener('change', function () {
+    // Send the form to the re-sort address instead of the search address.
+    pick.form.action = pick.getAttribute('data-resort');
+    // Send it now (this skips the form checks, which do not matter for a sort).
+    pick.form.submit();
+  });
+})();
diff --git a/web.go b/web.go
index f2fe6b4..cdfa48e 100644
--- a/web.go
+++ b/web.go
@@ -225,13 +225,15 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	// One history store, shared by the performance pages and the comparison page.
 	perfHistory := openPerfStore(histPath, histNote)
 	// Make the three Find LLM handlers: the page with the choices (or the kept results), the search that reads the public library, and the reset that forgets the kept search (see findllm.go); the search marks installed versions with their saved speed, so it gets the saved results.
-	findShow, findSearch, findReset := findLLMHandlers(addr, token, perfHistory)
+	findShow, findSearch, findReset, findResort := findLLMHandlers(addr, token, perfHistory)
 	// Route: a GET request for "/findllm" shows the choices and asks nothing from the internet.
 	mux.HandleFunc("GET /findllm", findShow)
 	// Route: a POST request for "/findllm/search" reads the library list and shows the matching models.
 	mux.HandleFunc("POST /findllm/search", findSearch)
 	// Route: a POST request for "/findllm/reset" forgets the kept search and shows the starting choices.
 	mux.HandleFunc("POST /findllm/reset", findReset)
+	// Route: a POST to "/findllm/resort" sorts the kept results again for the chosen order (no new search).
+	mux.HandleFunc("POST /findllm/resort", findResort)
 	// An older version kept the list of deleted models next to the results; bring it to the new folder first.
 	if msg := moveOldDeletedFile(histPath); msg != "" {
 		// Say so in the log; the list is then simply empty until the file can be moved.
@@ -303,6 +305,8 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	mux.HandleFunc("GET /countdown.js", countdownHandler)
 	// Route: a GET request for "/copy.js" sends the small script behind the copy buttons next to commands (only the restore page uses it).
 	mux.HandleFunc("GET /copy.js", copyHandler)
+	// Route: a GET request for "/sortpick.js" sends the small script that re-sorts the Find LLM results when the Sort by choice changes.
+	mux.HandleFunc("GET /sortpick.js", sortPickHandler)
 	// Route: a GET request for "/loading.js" sends the small script that shows the waiting message while a model loads (only the load warning page uses it).
 	mux.HandleFunc("GET /loading.js", loadingHandler)
 	// Route: a GET request for "/attention.js" sends the small script that opens the problem dialog (only the System check page uses it, and only when it found a problem).
OCC_PATCH_94_END
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
echo "NEXT  start bin/LLMsControlDock and look at Find LLM before and after a search (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
