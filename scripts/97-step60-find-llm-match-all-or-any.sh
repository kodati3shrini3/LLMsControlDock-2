#!/usr/bin/env bash
# Script 97 (Find LLM, Match ALL or Match ANY): inside the box What it should do, on the right, the person now chooses how the ticked abilities combine. Match ALL ticked (the default) lists only models that do everything ticked; Match ANY ticked lists models that do at least one of them. The explanation is plain text on the page, not a tooltip. The choice is kept after a search, an unknown value counts as Match ALL, and it applies to the local models and to the Cloud models section alike. Two new tests; one existing test now ends its check where the highlight rules end.
# Run it from the project folder, on the branch feature/find-llm-installed-speed (the same branch as script 94, after script 96): cd ~/LLMsControlDock && bash scripts/97-step60-find-llm-match-all-or-any.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 96), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm.go"]="224f95382730348f1b377a0f2a8ab0c5cf357993eaa9ae6eaaf7f5707ce5893c"
BEFORE["findllm_test.go"]="1673b6d65c8e3fb7414acca196aed67b7e75c09119c3bfce66d5f17c44b4cac5"
BEFORE["web/app.css"]="3e85f03ca14b31ae9293b8d3498c45d740d506250b4302a78d76c4e873d34717"
BEFORE["web/findllm.html"]="0090ec62ecd5cf078e55a168037e8e4068a9160731bfa6919bdbbfb4f81e599b"
AFTER["findllm.go"]="4c6f9e468e6c67214a4fa27dca935d81a8681545ec6b0ab8acf2afbd0fd5f801"
AFTER["findllm_test.go"]="f915b2017d6dfa70ee32edcaef2ca2c59afe71b3ce4029d1b78dc415b69bab9e"
AFTER["web/app.css"]="b2faadd648a2c8f67d0ce62afe206ddb28fd5fe5a246e459dc86854374e29f98"
AFTER["web/findllm.html"]="b610114b3440338d1f4d2fb82748167643a554af622644734f9bc76a923402ea"

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
[ "$BRANCH" != "main" ] || fail "you are on main; use the branch feature/find-llm-installed-speed"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 96 must have been applied: the rule that colours the Find LLM icon exists.
grep -q '^\.ico-find {' web/app.css || fail "script 96 must be applied first"
# Report it.
pass "script 96 (button colours and hover) is applied"

# Refuse to run twice: the all-or-any rule exists when this change was applied before.
if grep -q 'func abilitiesMatch' findllm.go; then fail "findllm.go already has the all-or-any rule: this script was already applied"; fi
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
index 3e8d75a..130ef11 100644
--- a/findllm.go
+++ b/findllm.go
@@ -280,8 +280,10 @@ func pullsNumber(text string) float64 {
 type findSelection struct {
 	// Chat is true when "Chat and writing" is ticked: the model is not a search-and-similarity model.
 	Chat bool
-	// Abilities are the ticked abilities (tools, vision, audio, thinking, embedding); a model must have all of them.
+	// Abilities are the ticked abilities (tools, vision, audio, thinking, embedding).
 	Abilities map[string]bool
+	// Any is true when the person chose "Match ANY ticked": a model needs at least one ticked ability; false (the default) is "Match ALL ticked": it needs every one.
+	Any bool
 	// Sizes are the ticked size classes (empty means any size).
 	Sizes map[string]bool
 	// Contexts are the ticked memory classes (empty means any).
@@ -323,6 +325,8 @@ func parseFindForm(get func(string) string) (findSelection, []string) {
 	var problems []string
 	// Chat and writing.
 	sel.Chat = get("ab_chat") == "on"
+	// Match ANY only when that exact choice was sent; anything else, or nothing, is the default Match ALL.
+	sel.Any = get("ab_mode") == "any"
 	// Each ability.
 	for _, k := range abilityKeys {
 		// Ticked.
@@ -369,6 +373,44 @@ func parseFindForm(get func(string) string) (findSelection, []string) {
 	return sel, problems
 } // end of parseFindForm
 
+// abilitiesMatch says whether a model with the abilities in has satisfies the ticks of "What it should do": with Match ALL (the default) every ticked item must hold, with Match ANY at least one; with nothing ticked every model passes. "Chat and writing" holds for a model that is not a search-and-similarity model.
+func abilitiesMatch(sel findSelection, has map[string]bool) bool {
+	// How many items are ticked and how many of them the model satisfies.
+	ticked, hits := 0, 0
+	// Chat and writing: holds when the model is not an embedding model.
+	if sel.Chat {
+		// One more ticked item.
+		ticked++
+		// Satisfied by a model that is not an embedding model.
+		if !has["embedding"] {
+			// One more hit.
+			hits++
+		} // end of the chat check
+	} // end of the chat item
+	// Each ticked ability.
+	for a := range sel.Abilities {
+		// One more ticked item.
+		ticked++
+		// The model has it.
+		if has[a] {
+			// One more hit.
+			hits++
+		} // end of the ability check
+	} // end of the ability loop
+	// Nothing ticked: no filter.
+	if ticked == 0 {
+		// Every model passes.
+		return true
+	} // end of the empty check
+	// Match ANY: one hit is enough.
+	if sel.Any {
+		// At least one.
+		return hits > 0
+	} // end of the any check
+	// Match ALL: every ticked item.
+	return hits == ticked
+} // end of abilitiesMatch
+
 // findCandidates applies the choices that the list page can answer: cloud-only models are left out, abilities and size classes are checked; the count of models without a readable size is returned when a size class is chosen. A model that carries the cloud label but also lists sizes (for example gemma4 or gpt-oss) has versions that run on this computer, so it stays; its cloud versions are dropped later, when its versions are listed.
 func findCandidates(models []siteModel, sel findSelection) (out []siteModel, noSize int, cloud int) {
 	// Look at every model.
@@ -387,26 +429,11 @@ func findCandidates(models []siteModel, sel findSelection) (out []siteModel, noS
 			// One ability.
 			has[a] = true
 		} // end of the fill
-		// Chat and writing: not a search-and-similarity model.
-		if sel.Chat && has["embedding"] {
-			// Skip.
-			continue
-		} // end of the chat check
-		// Every ticked ability must be present.
-		ok := true
-		// Check each.
-		for a := range sel.Abilities {
-			// Missing one.
-			if !has[a] {
-				// Not this model.
-				ok = false
-			} // end of the check
-		} // end of the ability loop
-		// Skip a model that lacks one.
-		if !ok {
+		// The ticks of "What it should do": all of them or any of them, as chosen.
+		if !abilitiesMatch(sel, has) {
 			// Next.
 			continue
-		} // end of the skip
+		} // end of the ability check
 		// Size classes: at least one of the model's sizes must be in a ticked class.
 		if len(sel.Sizes) > 0 {
 			// Whether any size matches, and whether any size could be read.
@@ -477,24 +504,9 @@ func findCloudModels(models []siteModel, sel findSelection) (out []siteModel, sk
 			// One ability.
 			has[a] = true
 		} // end of the fill
-		// Chat and writing: not a search-and-similarity model.
-		if sel.Chat && has["embedding"] {
-			// Skip.
-			continue
-		} // end of the chat check
-		// Every ticked ability must be present.
-		ok := true
-		// Check each.
-		for a := range sel.Abilities {
-			// Missing one.
-			if !has[a] {
-				// Not this model.
-				ok = false
-			} // end of the check
-		} // end of the ability loop
-		// Keep the match.
-		if ok {
-			// Add it.
+		// The ticks of "What it should do": all of them or any of them, as chosen.
+		if abilitiesMatch(sel, has) {
+			// Keep the match.
 			out = append(out, m)
 		} // end of the match check
 	} // end of the model loop
@@ -844,6 +856,8 @@ type findPage struct {
 	Sizes, Contexts []findTick
 	// Chat is whether "Chat and writing" is ticked.
 	Chat bool
+	// AnyMode is whether "Match ANY ticked" is chosen; false means "Match ALL ticked".
+	AnyMode bool
 	// Disk and Mem are the typed numbers, as text.
 	Disk, Mem string
 	// DiskNote and MemNote explain where the numbers come from.
@@ -906,7 +920,7 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 	// render draws the page for a selection.
 	render := func(w http.ResponseWriter, r *http.Request, sel findSelection, fm findMachine, problems []string, searched bool, results []resultView, cloudRes []resultView, cloudMore int, total, cloud, noSize int, errText, readAt, copyNote, instNote string, status int) {
 		// The tick boxes.
-		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, InstalledNote: instNote, CloudResults: cloudRes, CloudMore: cloudMore, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
+		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, AnyMode: sel.Any, Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, InstalledNote: instNote, CloudResults: cloudRes, CloudMore: cloudMore, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
 		// The abilities.
 		for _, k := range abilityKeys {
 			// One box.
diff --git a/findllm_test.go b/findllm_test.go
index 7bfd7d8..6811312 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -1341,8 +1341,13 @@ func TestButtonHighlightAndIconRules(t *testing.T) {
 		// Stop here.
 		t.Fatal("the highlight block is missing")
 	} // end of the block check
-	// The block itself.
+	// The block itself: it ends where the next, unrelated group of rules starts.
 	block := css[i:]
+	// Cut it there.
+	if j := strings.Index(block, `/* "What it should do"`); j > 0 {
+		// Keep only the highlight rules.
+		block = block[:j]
+	} // end of the cut
 	// The highlight changes colours only: nothing that could hide, move or block a tooltip.
 	for _, bad := range []string{"pointer-events", "overflow", "display:", "visibility", "position", "z-index", "opacity", "content:"} {
 		// Look for it.
@@ -1376,3 +1381,134 @@ func TestButtonHighlightAndIconRules(t *testing.T) {
 		} // end of the background loop
 	} // end of the theme loop
 } // end of TestButtonHighlightAndIconRules
+
+// TestAbilitiesMatch checks the all-or-any rule for the ticks of "What it should do", including the empty case and the Chat and writing tick.
+func TestAbilitiesMatch(t *testing.T) {
+	// The cases: what is ticked, the mode, the model's abilities and the expected answer.
+	for _, c := range []struct {
+		name string
+		sel  findSelection
+		has  map[string]bool
+		want bool
+	}{
+		// Nothing ticked: every model passes, in both modes.
+		{"nothing ticked, all", findSelection{}, map[string]bool{"tools": true}, true},
+		{"nothing ticked, any", findSelection{Any: true}, map[string]bool{}, true},
+		// Two abilities, Match ALL: needs both.
+		{"all: has both", findSelection{Abilities: map[string]bool{"tools": true, "vision": true}}, map[string]bool{"tools": true, "vision": true}, true},
+		{"all: has one", findSelection{Abilities: map[string]bool{"tools": true, "vision": true}}, map[string]bool{"tools": true}, false},
+		// Two abilities, Match ANY: one is enough, none is not.
+		{"any: has one", findSelection{Any: true, Abilities: map[string]bool{"tools": true, "vision": true}}, map[string]bool{"tools": true}, true},
+		{"any: has none", findSelection{Any: true, Abilities: map[string]bool{"tools": true, "vision": true}}, map[string]bool{"audio": true}, false},
+		// Chat and writing with an ability, Match ALL: a chat model that also has the ability; an embedding model fails.
+		{"all: chat and tools, chat model with tools", findSelection{Chat: true, Abilities: map[string]bool{"tools": true}}, map[string]bool{"tools": true}, true},
+		{"all: chat and tools, embedding model", findSelection{Chat: true, Abilities: map[string]bool{"tools": true}}, map[string]bool{"embedding": true, "tools": true}, false},
+		// Chat and writing with an ability, Match ANY: a chat model without the ability passes; an embedding model without it fails.
+		{"any: chat or tools, chat model without tools", findSelection{Any: true, Chat: true, Abilities: map[string]bool{"tools": true}}, map[string]bool{}, true},
+		{"any: chat or tools, embedding model without tools", findSelection{Any: true, Chat: true, Abilities: map[string]bool{"tools": true}}, map[string]bool{"embedding": true}, false},
+	} {
+		// The answer.
+		if got := abilitiesMatch(c.sel, c.has); got != c.want {
+			// Report.
+			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
+		} // end of the answer check
+	} // end of the loop
+} // end of TestAbilitiesMatch
+
+// TestFindModeChoice checks the Match ALL or Match ANY choice on the page and in the search: it sits inside "What it should do", defaults to ALL, is explained in plain text (not in a tooltip), is kept after a search, and changes the result.
+func TestFindModeChoice(t *testing.T) {
+	// The saved library list goes to a throw-away folder, never to the real data folder.
+	isolateFindData(t)
+	// Start with an empty saved list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// A fake library.
+	fakeSite(t, findTestPages())
+	// The rig.
+	rig := newThemeRig(t)
+	// The empty form page.
+	_, _, form := get(t, rig.h, http.MethodGet, "/findllm")
+	// The fieldset of "What it should do" up to its end.
+	i := strings.Index(form, "<strong>What it should do</strong>")
+	// It must exist.
+	if i < 0 {
+		// Stop here.
+		t.Fatal("the page lacks the What it should do box")
+	} // end of the box check
+	// The box itself.
+	box := form[i : i+strings.Index(form[i:], "</fieldset>")]
+	// Both radio buttons are inside the box, ALL is ticked by default and ANY is not.
+	if !strings.Contains(box, `name="ab_mode" value="all" checked`) || strings.Contains(box, `name="ab_mode" value="any" checked`) || !strings.Contains(box, `name="ab_mode" value="any"`) {
+		// Report.
+		t.Error("the choice is missing from the box or the default is not Match ALL")
+	} // end of the radio check
+	// The explanations are plain text in the box, never in a tooltip.
+	for _, want := range []string{"Match ALL ticked", "Match ANY ticked", "The model must do everything you ticked.", "The model needs at least one of the things you ticked."} {
+		// Look for it.
+		if !strings.Contains(box, want) {
+			// Report.
+			t.Errorf("the box lacks the text %q", want)
+		} // end of the look
+	} // end of the loop
+	// The two choices must be written outside any tooltip bubble: no bubble contains them.
+	for _, b := range regexp.MustCompile(`(?s)<span class="tip"[^>]*>.*?</span>`).FindAllString(box, -1) {
+		// A bubble that talks about the choice.
+		if strings.Contains(b, "Match ALL") || strings.Contains(b, "Match ANY") {
+			// Report.
+			t.Error("the explanation of the choice is inside a tooltip")
+		} // end of the bubble check
+	} // end of the loop
+	// The same search in both modes: tools or embedding is ticked (no model has both).
+	base := url.Values{"token": {rig.token}, "ab_tools": {"on"}, "ab_embedding": {"on"}, "disk_gb": {"100"}, "mem_gb": {"64"}}
+	// Match ALL (nothing sent for the mode): no model has both.
+	_, all := postFind(t, rig, base)
+	// None of the three fake models is listed.
+	for _, d := range []string{"An invented chat model.", "Turns text into numbers.", "Runs far away."} {
+		// Look for it.
+		if strings.Contains(all, d) {
+			// Report.
+			t.Errorf("Match ALL lists a model (%q) that lacks one of the ticked abilities", d)
+		} // end of the look
+	} // end of the loop
+	// Match ANY: a model with either ability.
+	any := url.Values{}
+	// Copy the fields.
+	for k, v := range base {
+		// One field.
+		any[k] = v
+	} // end of the copy
+	// The choice.
+	any.Set("ab_mode", "any")
+	// Send it.
+	_, anyBody := postFind(t, rig, any)
+	// The local chat model, the embedding model and the cloud model are all listed.
+	for _, d := range []string{"An invented chat model.", "Turns text into numbers.", "Runs far away."} {
+		// Look for it.
+		if !strings.Contains(anyBody, d) {
+			// Report.
+			t.Errorf("Match ANY does not list the model %q", d)
+		} // end of the look
+	} // end of the loop
+	// The choice is kept after the search.
+	if !strings.Contains(anyBody, `name="ab_mode" value="any" checked`) || strings.Contains(anyBody, `name="ab_mode" value="all" checked`) {
+		// Report.
+		t.Error("Match ANY is not kept after the search")
+	} // end of the kept check
+	// An unknown value falls back to the default.
+	odd := url.Values{}
+	// Copy the fields.
+	for k, v := range base {
+		// One field.
+		odd[k] = v
+	} // end of the copy
+	// A value that is neither choice.
+	odd.Set("ab_mode", "nonsense")
+	// Send it.
+	_, oddBody := postFind(t, rig, odd)
+	// It behaves as Match ALL.
+	if !strings.Contains(oddBody, `name="ab_mode" value="all" checked`) {
+		// Report.
+		t.Error("an unknown mode did not fall back to Match ALL")
+	} // end of the fallback check
+} // end of TestFindModeChoice
diff --git a/web/app.css b/web/app.css
index a4e9337..8682ec7 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2866,3 +2866,43 @@ html[data-size="medium"] svg[width="22"] {
   /* A little accent colour mixed into the panel colour. */
   background: color-mix(in srgb, var(--cat-accent) 12%, var(--panel));
 } /* end of rule */
+
+/* "What it should do": the ticks on the left and the all-or-any choice on the right; on a narrow window they stack. */
+.abilitywrap {
+  /* Side by side. */
+  display: flex;
+  /* Drop below each other when there is no room. */
+  flex-wrap: wrap;
+  /* Space between the two columns. */
+  gap: 1rem 2rem;
+} /* end of rule */
+
+/* The list of ticks takes the room it needs. */
+.abilitylist {
+  /* Grow a little, never shrink below the longest label. */
+  flex: 1 1 18rem;
+} /* end of rule */
+
+/* The all-or-any choice: a quiet box on the right, with a left line so it reads as a separate choice. */
+.abilitymode {
+  /* Needs about this much room for its explanation. */
+  flex: 1 1 20rem;
+  /* A line in the border colour separates it from the ticks. */
+  border-left: 2px solid var(--border);
+  /* Room between the line and the text. */
+  padding-left: 1rem;
+} /* end of rule */
+
+/* The small heading of the choice. */
+.abmodetitle {
+  /* Close to the first choice. */
+  margin: 0 0 0.3rem;
+} /* end of rule */
+
+/* The explanation under each choice: the secondary text colour, indented under the radio button. */
+.modeexplain {
+  /* Lines up under the words of the choice. */
+  margin: 0.1rem 0 0.5rem 1.5rem;
+  /* The secondary colour, readable in every theme. */
+  color: var(--muted);
+} /* end of rule */
diff --git a/web/findllm.html b/web/findllm.html
index 48a4423..4e7b06a 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -44,9 +44,23 @@
 {{/* What the model should be able to do. */}}
 <fieldset class="findgroup">
 <legend><strong>What it should do</strong></legend>
+{{/* Two columns: the ticks on the left, the all-or-any choice on the right; on a narrow window the choice drops below the ticks. */}}
+<div class="abilitywrap">
+<div class="abilitylist">
 <label class="tickrow"><input type="checkbox" name="ab_chat"{{if .Chat}} checked{{end}}> <span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.chat.ID}}">Chat and writing</span><span class="tip" role="tooltip" id="{{.Tips.chat.ID}}">{{template "tip" .Tips.chat}}</span></span></label>
 {{range .Abilities}}<label class="tickrow"><input type="checkbox" name="{{.Name}}"{{if .On}} checked{{end}}> <span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tip.ID}}">{{.Label}}</span><span class="tip" role="tooltip" id="{{.Tip.ID}}">{{template "tip" .Tip}}</span></span></label>
 {{end}}
+</div>
+{{/* How the ticks combine: always one of the two is chosen (Match ALL unless the person chose otherwise); the explanation is plain text on the page, not a tooltip. */}}
+<div class="abilitymode" role="radiogroup" aria-labelledby="abmodetitle">
+<p id="abmodetitle" class="abmodetitle"><strong>How the ticks combine</strong></p>
+<label class="tickrow"><input type="radio" name="ab_mode" value="all"{{if not .AnyMode}} checked{{end}}> <strong>Match ALL ticked</strong> <small class="muted">(the default)</small></label>
+<p class="modeexplain"><small>The model must do everything you ticked. Example: Uses tools and Understands pictures lists only models that do both.</small></p>
+<label class="tickrow"><input type="radio" name="ab_mode" value="any"{{if .AnyMode}} checked{{end}}> <strong>Match ANY ticked</strong></label>
+<p class="modeexplain"><small>The model needs at least one of the things you ticked. Example: Uses tools and Understands pictures lists models that do either one or both.</small></p>
+<p class="modeexplain"><small>With nothing ticked here, no ability is checked.</small></p>
+</div>
+</div>
 </fieldset>
 {{/* How big the model may be. */}}
 <fieldset class="findgroup">
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
echo "NEXT  start bin/LLMsControlDock and open Find LLM and look at the choice on the right of What it should do (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
