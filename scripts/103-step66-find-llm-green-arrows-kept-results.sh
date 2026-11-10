#!/usr/bin/env bash
# Script 103 (Find LLM page, four changes): (1) the headings Model size and Memory of a conversation end with "Matches ANY ticked"; (2) the Find LLM button is green, like the green button of the System check page; (3) the back arrow to the monitor also sits at the right end of the button row and at the bottom of the page; (4) the last successful search (choices and results) is kept in memory and shown again when the page is opened, until Find LLM is pressed again or the new button "Reset Find LLM search options" (shown only after a search) is pressed; the kept search is gone when the program stops. New tests for each.
# Run it from the project folder, on a new branch made from main (not on main): cd ~/LLMsControlDock && bash scripts/103-step66-find-llm-green-arrows-kept-results.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as on main after PR 44), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm.go"]="3570ba9e6e9db48978b4975b90ff43649512fc666974388b8583240c5ee53bf0"
BEFORE["findllm_test.go"]="5e29d708e54edb5fb9a6998a174e67192cb5f5faf8940bb5b312cdcf98f00d84"
BEFORE["web.go"]="fcb817500ff22def506cf40baa23ca70ea0fbeee6f2c702e217d6bafea39c76c"
BEFORE["web/app.css"]="b95cf563d010554c8c8fc8539edc46393c435d356ee10e3e458a698b181411e7"
BEFORE["web/findllm.html"]="fa60402eef612f594a47e81f0f23bc60025e5e8bbb16eee8b88741ac02402a61"
AFTER["findllm.go"]="340bbbae6dd919c637d49041db17a7f6e980f7870b3f78a41e10c77b1dac80a9"
AFTER["findllm_test.go"]="ee433ac3b76d9403adc166ab57d1738d753ef50004ab34cfc435d873b08d4220"
AFTER["web.go"]="d38f4b618ddf521d0090e4526272635a26760a63eaeb7be059c2584b9e11f6df"
AFTER["web/app.css"]="b26028a60974a7dcb59ec030a01cb959e0b6a540b32bc50a93292c958717c1ee"
AFTER["web/findllm.html"]="ec4a7a6414df1f403e01b274ef448a0871654c4f145c90f39457fa9ef41bc127"

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
[ "$BRANCH" != "main" ] || fail "you are on main; make a new branch first: git switch -c feature/find-llm-green-arrows-kept-results"
# Report the branch.
pass "on branch $BRANCH (not main)"

# The merged work must be here: the tooltip fix of script 102 exists.
grep -q '.tip:not(.tip-icon) {' web/app.css || fail "the merged tooltip fix (PR 44) must be here: update main first"
# Report it.
pass "the merged tooltip fix is here"

# Refuse to run twice: the reset handler exists when this change was applied before.
if grep -q 'findReset' web.go; then fail "web.go already has findReset: this script was already applied"; fi
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
index ef270ee..44e0795 100644
--- a/findllm.go
+++ b/findllm.go
@@ -1056,8 +1056,30 @@ type findTick struct {
 	Tip tipView
 } // end of findTick
 
-// findLLMHandlers makes the two handlers of the Find LLM page: the first shows the choices, the second reads the library and shows the models; the second asks the public website, and only the address of its page leaves this computer.
-func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.HandlerFunc, http.HandlerFunc) {
+// findKept is the last successful search, kept in memory only: it is gone when the program stops, so it is empty at every start.
+type findKept struct {
+	// sel holds the choices that were ticked and typed.
+	sel findSelection
+	// results are the models found, with their versions.
+	results []resultView
+	// cloudRes are the cloud-only models shown.
+	cloudRes []resultView
+	// cloudMore counts the cloud-only models that match but are not shown.
+	cloudMore int
+	// total, cloud and noSize are the counts the summary line needs.
+	total, cloud, noSize int
+	// readAt says when the list was read, with its zone.
+	readAt string
+	// copyNote and instNote are the notes that were shown with the results.
+	copyNote, instNote string
+} // end of findKept
+
+// findLLMHandlers makes the three handlers of the Find LLM page: the first shows the choices (or the kept results of the last search), the second reads the library and shows the models, the third forgets the kept search; the second asks the public website, and only the address of its page leaves this computer.
+func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.HandlerFunc, http.HandlerFunc, http.HandlerFunc) {
+	// keptMu guards kept, because requests run side by side.
+	var keptMu sync.Mutex
+	// kept is the last successful search; nil when there is none.
+	var kept *findKept
 	// Parse the template once.
 	page := template.Must(template.New("findllm").Parse(findLLMTemplateText + tipsTemplateText))
 	// Whether Ollama runs on this computer.
@@ -1198,6 +1220,17 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 	show := func(w http.ResponseWriter, r *http.Request) {
 		// Read the machine.
 		fm := readFindMachine(r.Context(), local)
+		// The last successful search, if there is one.
+		keptMu.Lock()
+		k := kept
+		keptMu.Unlock()
+		// Show it again, exactly as it was found, until a new search or the reset.
+		if k != nil {
+			// Draw the kept choices and results.
+			render(w, r, k.sel, fm, nil, true, k.results, k.cloudRes, k.cloudMore, k.total, k.cloud, k.noSize, "", k.readAt, k.copyNote, k.instNote, http.StatusOK)
+			// Done.
+			return
+		} // end of the kept check
 		// The starting choices: chat and writing, small and medium models, no ability or memory filter.
 		sel := findSelection{Chat: true, Abilities: map[string]bool{}, Sizes: map[string]bool{"small": true, "medium": true}, Contexts: map[string]bool{}, DiskGB: fm.DiskGB, MemGB: fm.MemGB}
 		// Draw.
@@ -1332,11 +1365,33 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 			// Say how many were left out.
 			cloudLeft = cloud
 		} // end of the class check
+		// The time the list was read, with its zone.
+		readAtText := at.Format("2006-01-02 15:04:05 MST (UTC-07:00)")
+		// Keep this search in memory, so a visit to the monitor and back shows it again.
+		keptMu.Lock()
+		kept = &findKept{sel: sel, results: results, cloudRes: cloudRes, cloudMore: cloudMore, total: len(cands), cloud: cloudLeft, noSize: noSize, readAt: readAtText, copyNote: copyNote, instNote: instNote}
+		keptMu.Unlock()
 		// Draw the results, with the time the list was read and its zone.
-		render(w, r, sel, fm, nil, true, results, cloudRes, cloudMore, len(cands), cloudLeft, noSize, "", at.Format("2006-01-02 15:04:05 MST (UTC-07:00)"), copyNote, instNote, http.StatusOK)
+		render(w, r, sel, fm, nil, true, results, cloudRes, cloudMore, len(cands), cloudLeft, noSize, "", readAtText, copyNote, instNote, http.StatusOK)
 	} // end of search
-	// Hand back both.
-	return show, search
+	// reset forgets the kept search and shows the starting choices again.
+	reset := func(w http.ResponseWriter, r *http.Request) {
+		// Only the page's own form may do this.
+		if !tokenValid(token, r.PostFormValue("token")) {
+			// Refuse.
+			http.Error(w, "forbidden", http.StatusForbidden)
+			// Stop.
+			return
+		} // end of the token check
+		// Forget the kept search.
+		keptMu.Lock()
+		kept = nil
+		keptMu.Unlock()
+		// Back to the page with the starting choices; a redirect keeps a reload from sending the form again.
+		http.Redirect(w, r, "/findllm", http.StatusSeeOther)
+	} // end of reset
+	// Hand back all three.
+	return show, search, reset
 } // end of findLLMHandlers
 
 // findSummary writes the sentence above the results in correct singular and plural.
diff --git a/findllm_test.go b/findllm_test.go
index cafdf44..815efb1 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -1827,7 +1827,7 @@ func TestFindSortChoice(t *testing.T) {
 	// The empty form page.
 	_, _, form := get(t, rig.h, http.MethodGet, "/findllm")
 	// The choice sits in the same paragraph as the button, with Most downloaded selected.
-	for _, want := range []string{`<p class="findaction"><button type="submit" class="btn-solid">Find LLM</button>`, `name="sort"`, `<option value="downloads" selected>Most downloaded</option>`, `<option value="name">Name A to Z</option>`, `Sort by <select class="keepselect" id="sortby" name="sort">`} {
+	for _, want := range []string{`<p class="findaction"><button type="submit" class="btn-solid btn-go">Find LLM</button>`, `name="sort"`, `<option value="downloads" selected>Most downloaded</option>`, `<option value="name">Name A to Z</option>`, `Sort by <select class="keepselect" id="sortby" name="sort">`} {
 		// Look for it.
 		if !strings.Contains(form, want) {
 			// Report.
@@ -1849,3 +1849,131 @@ func TestFindSortChoice(t *testing.T) {
 		t.Error("an unknown sort value did not fall back to Most downloaded")
 	} // end of the fallback check
 } // end of TestFindSortChoice
+
+// TestFindKeptSearchAndReset: the last search is kept in memory (choices and results) and shown again when the page is opened; the Reset button appears only after a search and forgets it; a new program starts empty.
+func TestFindKeptSearchAndReset(t *testing.T) {
+	// The saved library list goes to a throw-away folder, never to the real data folder.
+	isolateFindData(t)
+	// Start with an empty saved list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// A fake library.
+	fakeSite(t, findTestPages())
+	// The rig (a new program: nothing is kept).
+	rig := newThemeRig(t)
+	// Before any search: the starting form, no results, no Reset button.
+	_, _, first := get(t, rig.h, http.MethodGet, "/findllm")
+	// The checks.
+	if strings.Contains(first, "Reset Find LLM search options") || strings.Contains(first, "Models found") {
+		// Report.
+		t.Error("the page before any search shows a Reset button or results")
+	} // end of the first check
+	// A search with Name A to Z.
+	_, found := postFind(t, rig, url.Values{"token": {rig.token}, "sort": {"name"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
+	// The results page has the Reset button and the results.
+	if !strings.Contains(found, "Reset Find LLM search options") || !strings.Contains(found, "Models found") {
+		// Report.
+		t.Fatal("the results page lacks the Reset button or the results")
+	} // end of the found check
+	// Back to the monitor and back again: the page shows the same results and choices.
+	_, _, again := get(t, rig.h, http.MethodGet, "/findllm")
+	// What must be there.
+	for _, want := range []string{"Reset Find LLM search options", "Models found", `<option value="name" selected>Name A to Z</option>`, `value="100.0"`, `value="64.0"`} {
+		// Look for it.
+		if !strings.Contains(again, want) {
+			// Report.
+			t.Errorf("the reopened page lacks %q", want)
+		} // end of the look
+	} // end of the loop
+	// The results are the same as the first time (the part after the heading "Models found").
+	if i, j := strings.Index(found, "Models found"), strings.Index(again, "Models found"); i < 0 || j < 0 || !strings.Contains(again[j:], "<h3>") && strings.Contains(found[i:], "<h3>") {
+		// Report.
+		t.Error("the reopened page does not show the kept models")
+	} // end of the same-results check
+	// A reset with a wrong token is refused and keeps the search.
+	if res := post(t, rig.h, "/findllm/reset", url.Values{"token": {"wrong"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
+		// Report.
+		t.Errorf("reset with a wrong token = %d, want 403", res.StatusCode)
+	} // end of the token check
+	// The page still shows the kept search.
+	if _, _, still := get(t, rig.h, http.MethodGet, "/findllm"); !strings.Contains(still, "Models found") {
+		// Report.
+		t.Error("a refused reset forgot the search")
+	} // end of the still check
+	// A real reset redirects back to the page.
+	res := post(t, rig.h, "/findllm/reset", url.Values{"token": {rig.token}}, fromThisPage)
+	// Redirect to the page.
+	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/findllm" {
+		// Report.
+		t.Errorf("reset = %d to %q, want 303 to /findllm", res.StatusCode, res.Header.Get("Location"))
+	} // end of the redirect check
+	// After the reset: the starting form again, no results, no Reset button, Most downloaded selected.
+	_, _, cleared := get(t, rig.h, http.MethodGet, "/findllm")
+	// Nothing kept.
+	if strings.Contains(cleared, "Reset Find LLM search options") || strings.Contains(cleared, "Models found") || !strings.Contains(cleared, `<option value="downloads" selected>Most downloaded</option>`) {
+		// Report.
+		t.Error("the page after the reset still shows the kept search")
+	} // end of the cleared check
+	// A search that could not run (typed wrongly) is not kept.
+	postFind(t, rig, url.Values{"token": {rig.token}, "disk_gb": {"not a number"}})
+	// The page is still the starting form.
+	if _, _, after := get(t, rig.h, http.MethodGet, "/findllm"); strings.Contains(after, "Models found") {
+		// Report.
+		t.Error("a search with a typing mistake was kept")
+	} // end of the mistake check
+} // end of TestFindKeptSearchAndReset
+
+// TestFindPageHeadingsButtonAndArrows: the two range groups say Matches ANY ticked, the Find LLM button has the green of the System check page, and the back arrow is at the top, at the right end of the button row and at the bottom.
+func TestFindPageHeadingsButtonAndArrows(t *testing.T) {
+	// The saved library list goes to a throw-away folder, never to the real data folder.
+	isolateFindData(t)
+	// A fake library, which must not be asked.
+	fakeSite(t, findTestPages())
+	// The rig.
+	rig := newThemeRig(t)
+	// The empty form page.
+	_, _, form := get(t, rig.h, http.MethodGet, "/findllm")
+	// The note after each of the two range headings.
+	if n := strings.Count(form, `<small class="anynote">Matches ANY ticked</small>`); n != 2 {
+		// Report.
+		t.Errorf("Matches ANY ticked appears %d times, want 2", n)
+	} // end of the note check
+	// The note follows the group wording.
+	for _, want := range []string{"(none ticked: any size)</small> <small class=\"anynote\">", "(none ticked: any length)</small> <small class=\"anynote\">"} {
+		// Look for it.
+		if !strings.Contains(form, want) {
+			// Report.
+			t.Errorf("the page lacks %q", want)
+		} // end of the look
+	} // end of the loop
+	// The button uses the same classes as the green button of the System check page.
+	_, _, check := get(t, rig.h, http.MethodGet, "/systemcheck")
+	// The System check page has its green button.
+	if !strings.Contains(check, `class="btn-solid btn-go"`) || !strings.Contains(form, `<button type="submit" class="btn-solid btn-go">Find LLM</button>`) {
+		// Report.
+		t.Error("the Find LLM button does not use the green button classes")
+	} // end of the button check
+	// Three back arrows: top, button row, bottom.
+	if n := strings.Count(form, `aria-label="Back to the monitor"`); n != 3 {
+		// Report.
+		t.Errorf("%d back arrows, want 3", n)
+	} // end of the count check
+	// Their bubbles have different ids.
+	for _, id := range []string{`id="tipback"`, `id="tipback-row"`, `id="tipback-bottom"`} {
+		// Look for it.
+		if !strings.Contains(form, id) {
+			// Report.
+			t.Errorf("the page lacks %s", id)
+		} // end of the look
+	} // end of the loop
+	// The row arrow is inside the button row, after the order choice; the bottom one is after the last block of the page.
+	row := strings.Index(form, `<p class="findaction">`)
+	// Where the row arrow is, and where the bottom arrow is.
+	rowArrow, bottom := strings.Index(form, `id="tipback-row"`), strings.Index(form, `<p class="backbottom">`)
+	// Order.
+	if row < 0 || rowArrow < row || bottom < rowArrow {
+		// Report.
+		t.Errorf("the arrows are in the wrong places (row %d, row arrow %d, bottom %d)", row, rowArrow, bottom)
+	} // end of the order check
+} // end of TestFindPageHeadingsButtonAndArrows
diff --git a/web/app.css b/web/app.css
index 5cc4190..bca9fa0 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2973,22 +2973,48 @@ html[data-size="medium"] svg[width="22"] {
   font-size: 1.05em;
 } /* end of rule */
 
-/* The button and the order choice on one line; plain inline layout. */
+/* The button row: the Find LLM button, the order choice, the reset button, and the back arrow at the right end. */
 .findaction {
-  /* Space above and below the line, as in a paragraph. */
-  line-height: 2.6;
+  /* The parts sit in a row. */
+  display: flex;
+  /* On a narrow window the parts wrap to the next line. */
+  flex-wrap: wrap;
+  /* Level with each other. */
+  align-items: center;
+  /* Space between the parts, across and down. */
+  gap: 0.5rem 1rem;
 } /* end of rule */
 
-/* The label and the list of the order choice. */
-.sortpick {
-  /* Next to the button, wrapping below it on a narrow window. */
-  display: inline-block;
-  /* Space between the button and the choice. */
-  margin-left: 1rem;
+/* The back arrow in the button row goes to the right end. */
+.findaction .backhere {
+  /* Push it to the right end of the row. */
+  margin-left: auto;
 } /* end of rule */
 
-/* The tags help line inside the row has the same space above and below as the twistie, so both sit level. */
-.keyrow .groupedhelp {
-  /* Same space as the twistie line. */
-  margin: 0.4rem 0 0.75rem;
+/* The back arrow at the bottom of the page, at the right end. */
+.backbottom {
+  /* To the right end. */
+  text-align: right;
+  /* Space above, so it is not glued to the last result. */
+  margin: 1.2rem 0 0;
+} /* end of rule */
+
+/* The two extra back arrows: the bubble ends at the right edge of the arrow, like the one at the top. */
+.backhere .tip-icon {
+  /* No left anchor. */
+  left: auto;
+  /* Its right edge lines up with the arrow. */
+  right: anchor(right);
+  /* As wide as its words. */
+  width: max-content;
+  /* Never wider than the normal bubble. */
+  max-width: min(26rem, 92vw);
+} /* end of rule */
+
+/* "Matches ANY ticked" after the heading of a group whose ticks always mean any of them. */
+.anynote {
+  /* A little bolder than the grey words next to it, so it is noticed. */
+  font-weight: 600;
+  /* The normal text colour. */
+  color: var(--text);
 } /* end of rule */
diff --git a/web/findllm.html b/web/findllm.html
index ba53f0b..dec5460 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -81,19 +81,19 @@
 </fieldset>
 {{/* How big the model may be. */}}
 <fieldset class="findgroup">
-<legend><span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.size.ID}}"><strong>Model size</strong></span><span class="tip" role="tooltip" id="{{.Tips.size.ID}}">{{template "tip" .Tips.size}}</span></span> <small class="muted">(none ticked: any size)</small></legend>
+<legend><span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.size.ID}}"><strong>Model size</strong></span><span class="tip" role="tooltip" id="{{.Tips.size.ID}}">{{template "tip" .Tips.size}}</span></span> <small class="muted">(none ticked: any size)</small> <small class="anynote">Matches ANY ticked</small></legend>
 {{range .Sizes}}<label class="tickrow"><input type="checkbox" name="{{.Name}}"{{if .On}} checked{{end}}> {{.Label}} <small class="muted">({{.Range}})</small></label>
 {{end}}
 </fieldset>
 {{/* How much the model remembers of a conversation. */}}
 <fieldset class="findgroup">
-<legend><span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.context.ID}}"><strong>Memory of a conversation</strong></span><span class="tip" role="tooltip" id="{{.Tips.context.ID}}">{{template "tip" .Tips.context}}</span></span> <small class="muted">(none ticked: any length)</small></legend>
+<legend><span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.context.ID}}"><strong>Memory of a conversation</strong></span><span class="tip" role="tooltip" id="{{.Tips.context.ID}}">{{template "tip" .Tips.context}}</span></span> <small class="muted">(none ticked: any length)</small> <small class="anynote">Matches ANY ticked</small></legend>
 {{range .Contexts}}<label class="tickrow"><input type="checkbox" name="{{.Name}}"{{if .On}} checked{{end}}> {{.Label}} <small class="muted">({{.Range}})</small></label>
 {{end}}
 </fieldset>
 {{/* The button: the first and only thing that reads the internet. */}}
 {{/* The button, with the order of the results beside it. */}}
-<p class="findaction"><button type="submit" class="btn-solid">Find LLM</button> <label class="sortpick" for="sortby">Sort by <select class="keepselect" id="sortby" name="sort"><option value="downloads"{{if not .SortName}} selected{{end}}>Most downloaded</option><option value="name"{{if .SortName}} selected{{end}}>Name A to Z</option></select></label></p>
+<p class="findaction"><button type="submit" class="btn-solid btn-go">Find LLM</button> <label class="sortpick" for="sortby">Sort by <select class="keepselect" id="sortby" name="sort"><option value="downloads"{{if not .SortName}} selected{{end}}>Most downloaded</option><option value="name"{{if .SortName}} selected{{end}}>Name A to Z</option></select></label>{{if .Searched}} <span class="tipbox"><button type="submit" class="btn-plain" formaction="/findllm/reset" formnovalidate aria-describedby="tip-reset">Reset Find LLM search options</button><span class="tip tip-icon" role="tooltip" id="tip-reset">Forget the last search and show the starting ticks.</span></span>{{end}} <span class="tipbox backhere"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback-row"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback-row">Back to the monitor</span></span></p>
 </form>
 {{/* The results appear only after the button was pressed. */}}
 {{if .Searched}}
@@ -154,6 +154,8 @@
 <p class="muted"><small>The command must run where Ollama runs, because the model is stored there. The Copy button only copies the text; you paste it into the terminal yourself. The Kubernetes line has not been tested on a real cluster.</small></p>
 <p id="copystatus" class="sr-only" role="status" aria-live="polite"></p>
 {{end}}
+{{/* The back arrow again at the bottom of the page. */}}
+<p class="backbottom"><span class="tipbox backhere"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback-bottom"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback-bottom">Back to the monitor</span></span></p>
 </section>
 </main>
 {{if .ShowCopy}}<script src="/copy.js" defer></script>{{end}}
diff --git a/web.go b/web.go
index d0ad5bf..f2fe6b4 100644
--- a/web.go
+++ b/web.go
@@ -224,12 +224,14 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	// Open the saved results.
 	// One history store, shared by the performance pages and the comparison page.
 	perfHistory := openPerfStore(histPath, histNote)
-	// Make the two Find LLM handlers: the page with the choices, and the search that reads the public library (see findllm.go); the search marks installed versions with their saved speed, so it gets the saved results.
-	findShow, findSearch := findLLMHandlers(addr, token, perfHistory)
+	// Make the three Find LLM handlers: the page with the choices (or the kept results), the search that reads the public library, and the reset that forgets the kept search (see findllm.go); the search marks installed versions with their saved speed, so it gets the saved results.
+	findShow, findSearch, findReset := findLLMHandlers(addr, token, perfHistory)
 	// Route: a GET request for "/findllm" shows the choices and asks nothing from the internet.
 	mux.HandleFunc("GET /findllm", findShow)
 	// Route: a POST request for "/findllm/search" reads the library list and shows the matching models.
 	mux.HandleFunc("POST /findllm/search", findSearch)
+	// Route: a POST request for "/findllm/reset" forgets the kept search and shows the starting choices.
+	mux.HandleFunc("POST /findllm/reset", findReset)
 	// An older version kept the list of deleted models next to the results; bring it to the new folder first.
 	if msg := moveOldDeletedFile(histPath); msg != "" {
 		// Say so in the log; the list is then simply empty until the file can be moved.
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
echo "NEXT  start bin/LLMsControlDock and open Find LLM (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
