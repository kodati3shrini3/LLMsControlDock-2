#!/usr/bin/env bash
# Script 129 (Updated: new to old becomes the default order): on the Find LLM page the choice "Updated: new to old" is now the first one in Sort by and is selected by default, also when no choice or an unknown choice is sent (and after "Reset Find LLM search options"); "Most downloaded" and "Name A to Z" stay available and are kept when chosen. The sentence above a cut list names the order that is used. This script builds on script 128 and must be run AFTER it, on the same branch, before anything is committed. Version stays 0.33.0 until the release is made.
# Run it on the branch of script 128 (never main): cd ~/LLMsControlDock-2 && git branch --show-current && bash scripts/129-step91-updated-order-is-the-default.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the six files BEFORE this change (the state after script 128) and AFTER it; findsite.go does not change in this script.
declare -A BEFORE AFTER
BEFORE["findllm.go"]="50e69b3c226291bc679e1b15cdab63964727e91978700e6c85e434d12f3c9c4f"
BEFORE["findllm_test.go"]="92338220e892c0532d5e57ad6fbb421e2e6f7b2f1ae53d06743823f6189077d6"
BEFORE["findsite.go"]="c6fd1b280b2bf29caf668bf5e63d43207095fed625c46a85ce861bc3a7f04d71"
BEFORE["sortpick_test.go"]="3d919c4f30147e3c5c7302ada4acaf259e80e49ac88a231ecf2b226265293224"
BEFORE["web/findllm.html"]="afff22cd54734cb484e2a13e89518c698a35620ad8a2198192705f13f2de1be4"
BEFORE["findupdated_test.go"]="fcee04e2116cdf79515035d401bf57b15e6b349efe9fd9e3afee826cd56660a8"
AFTER["findllm.go"]="d1171a3ff50d7acc863be09c415a48109e07f3746a53f94f16747734ec034b51"
AFTER["findllm_test.go"]="ca14380cdb4d75ab0aaa28281cab6b6bdb2c8914e67d98461045c326e8abc6d4"
AFTER["findsite.go"]="c6fd1b280b2bf29caf668bf5e63d43207095fed625c46a85ce861bc3a7f04d71"
AFTER["sortpick_test.go"]="60e05938b9b9877fff6dba91360be272fb612c8c4426c25d1e6ef33dd1b78ccb"
AFTER["web/findllm.html"]="6307375d907f1f2e4397cfe3ee5e3a3dd77bf0e81e4d79dccb9ba13669667d74"
AFTER["findupdated_test.go"]="1859aeed7a0ec5b78054db581673a908b54498e271cbc9f53e0aad3f32869bd5"

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
[ "$BRANCH" != "main" ] || fail "you are on main; this script belongs on the branch of script 128 (feature/find-llm-sort-updated)"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Script 128 must have been applied (its new test file is the sign).
[ -e findupdated_test.go ] || fail "script 128 was not applied here: findupdated_test.go is missing"
# Report it.
pass "script 128 is applied"

# Refuse to run twice: sortOrder is the sign of this script.
if grep -q 'func sortOrder' findllm.go; then fail "findllm.go already has sortOrder: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# Every file must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the file is not the expected version.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} files are the expected versions before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_129_END'
diff --git a/findllm.go b/findllm.go
index 6139eeb..87afb9d 100644
--- a/findllm.go
+++ b/findllm.go
@@ -306,7 +306,7 @@ type findSelection struct {
 	Chat bool
 	// Abilities are the ticked abilities (tools, vision, audio, thinking, embedding, decision).
 	Abilities map[string]bool
-	// Sort is how the models are ordered: "downloads" (the default, also when empty), "name" or "updated" (the most recently updated first).
+	// Sort is how the models are ordered: "updated" (the default, also when empty or unknown: the most recently updated first), "downloads" (most downloaded first) or "name" (A to Z); sortOrder turns any text into one of these three.
 	Sort string
 	// Domains are the ticked fields of use (keys of findDomains); empty means no filter.
 	Domains map[string]bool
@@ -357,17 +357,8 @@ func parseFindForm(get func(string) string) (findSelection, []string) {
 	sel.Chat = get("ab_chat") == "on"
 	// Match ANY only when that exact choice was sent; anything else, or nothing, is the default Match ALL.
 	sel.Any = get("ab_mode") == "any"
-	// The order of the results: Name A to Z or Updated only when that exact choice was sent; anything else is the default, most downloaded.
-	switch get("sort") {
-	// Name order.
-	case "name":
-		// Keep it.
-		sel.Sort = "name"
-	// Most recently updated first.
-	case "updated":
-		// Keep it.
-		sel.Sort = "updated"
-	} // end of the sort check
+	// The order of the results: Name A to Z or Most downloaded only when that exact choice was sent; anything else, or nothing, is the default, most recently updated first.
+	sel.Sort = sortOrder(get("sort"))
 	// The same for the fields of use.
 	sel.DomainAny = get("dom_mode") == "any"
 	// Each known field of use that is ticked.
@@ -524,6 +515,17 @@ func domainMatch(sel findSelection, m siteModel) bool {
 	return hits == len(sel.Domains)
 } // end of domainMatch
 
+// sortOrder turns the text of the Sort by choice into one of the three known orders: "name" (A to Z), "downloads" (most downloaded first), and for anything else, also an empty or unknown text, the default "updated" (the most recently updated first).
+func sortOrder(s string) string {
+	// The two orders that must be asked for by their exact words.
+	if s == "name" || s == "downloads" {
+		// Keep it.
+		return s
+	} // end of the exact-words check
+	// Everything else is the default.
+	return "updated"
+} // end of sortOrder
+
 // updatedBefore says whether a model updated aWords ago comes before one updated bWords ago: the more recent first, a model without readable update words last, equal words by name so the list is stable.
 func updatedBefore(aWords, aName, bWords, bName string) bool {
 	// The ages in hours; -1 means not known.
@@ -547,19 +549,21 @@ func updatedBefore(aWords, aName, bWords, bName string) bool {
 	return aName < bName
 } // end of updatedBefore
 
-// modelBefore says whether model a is listed before model b: by name for the choice Name A to Z, by update words for Updated, otherwise most downloaded first, with equal counts keeping the name order so the list is stable.
+// modelBefore says whether model a is listed before model b: by name for the choice Name A to Z, by download counts for Most downloaded (equal counts by name), otherwise, which is the default, by update words with the most recent first.
 func modelBefore(sel findSelection, a, b siteModel) bool {
-	// Most recently updated first.
-	if sel.Sort == "updated" {
+	// The chosen order, with an empty or unknown choice turned into the default.
+	order := sortOrder(sel.Sort)
+	// Most recently updated first (the default).
+	if order == "updated" {
 		// By the update words.
 		return updatedBefore(a.Updated, a.Name, b.Updated, b.Name)
 	} // end of the updated order
 	// Name A to Z.
-	if sel.Sort == "name" {
+	if order == "name" {
 		// By name.
 		return a.Name < b.Name
 	} // end of the name order
-	// The download counts.
+	// Most downloaded first: the download counts.
 	pa, pb := pullsNumber(a.Pulls), pullsNumber(b.Pulls)
 	// The higher count first.
 	if pa != pb {
@@ -669,7 +673,7 @@ func findCandidates(models []siteModel, sel findSelection) (out []siteModel, noS
 		// It passed.
 		out = append(out, m)
 	} // end of the model loop
-	// The chosen order: most downloaded first (the default), Name A to Z, or most recently updated first.
+	// The chosen order: most recently updated first (the default), Most downloaded, or Name A to Z.
 	sort.SliceStable(out, func(i, j int) bool {
 		// Compare as chosen.
 		return modelBefore(sel, out[i], out[j])
@@ -705,7 +709,7 @@ func findCloudModels(models []siteModel, sel findSelection) (out []siteModel, sk
 			out = append(out, m)
 		} // end of the match check
 	} // end of the model loop
-	// The chosen order: most downloaded first (the default), Name A to Z, or most recently updated first.
+	// The chosen order: most recently updated first (the default), Most downloaded, or Name A to Z.
 	sort.SliceStable(out, func(i, j int) bool {
 		// Compare as chosen.
 		return modelBefore(sel, out[i], out[j])
@@ -1308,7 +1312,7 @@ type findPage struct {
 	Domains []domainTick
 	// SortName is whether Name A to Z is chosen.
 	SortName bool
-	// SortUpdated is whether Updated: new to old is chosen; when neither this nor SortName is true, most downloaded is chosen.
+	// SortUpdated is whether Updated: new to old is chosen, which is the default; when neither this nor SortName is true, Most downloaded is chosen.
 	SortUpdated bool
 	// UpdatedNote explains the Updated order under the results (rounded words, ties by name); empty for the other orders.
 	UpdatedNote string
@@ -1416,7 +1420,7 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 	// render draws the page for a selection.
 	render := func(w http.ResponseWriter, r *http.Request, sel findSelection, fm findMachine, problems []string, searched bool, results []resultView, cloudRes []resultView, cloudMore int, total, cloud, noSize int, errText, readAt, copyNote, instNote string, status int) {
 		// The tick boxes.
-		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, AnyMode: sel.Any, DomainAnyMode: sel.DomainAny, SortName: sel.Sort == "name", SortUpdated: sel.Sort == "updated", UpdatedNote: updatedNote(sel.Sort, results, cloudRes), Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, InstalledNote: instNote, CloudResults: cloudRes, CloudMore: cloudMore, Results: results, Summary: findSummary(len(results), total, cloud, noSize, sel.Sort, readAt)}
+		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, AnyMode: sel.Any, DomainAnyMode: sel.DomainAny, SortName: sortOrder(sel.Sort) == "name", SortUpdated: sortOrder(sel.Sort) == "updated", UpdatedNote: updatedNote(sel.Sort, results, cloudRes), Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, InstalledNote: instNote, CloudResults: cloudRes, CloudMore: cloudMore, Results: results, Summary: findSummary(len(results), total, cloud, noSize, sel.Sort, readAt)}
 		// The abilities.
 		for _, k := range abilityKeys {
 			// One box.
@@ -1762,21 +1766,8 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 		keptMu.Lock()
 		// Only when there is a kept search.
 		if kept != nil {
-			// The new order: Name A to Z, most recently updated first or, by default, most downloaded.
-			switch r.PostFormValue("sort") {
-			// By name.
-			case "name":
-				// Keep it.
-				kept.sel.Sort = "name"
-			// By the update words.
-			case "updated":
-				// Keep it.
-				kept.sel.Sort = "updated"
-			// Anything else: by downloads.
-			default:
-				// The default.
-				kept.sel.Sort = "downloads"
-			} // end of the order choice
+			// The new order: Name A to Z, Most downloaded or, by default, most recently updated first.
+			kept.sel.Sort = sortOrder(r.PostFormValue("sort"))
 			// Sort the local models, keeping the ones with a fitting version first.
 			resortViews(kept.results, kept.sel.Sort, true)
 			// Sort the cloud-only models (they have no versions to fit).
@@ -1790,8 +1781,10 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 	return show, search, reset, resort
 } // end of findLLMHandlers
 
-// resortViews puts shown models in order again: order "name" is Name A to Z, "updated" is the most recently updated first (same words by name), anything else is most downloaded first (equal counts by name); with fitFirst a model that has a fitting version stays ahead of the others.
+// resortViews puts shown models in order again: order "name" is Name A to Z, "downloads" is most downloaded first (equal counts by name), anything else is the default, the most recently updated first (same words by name); with fitFirst a model that has a fitting version stays ahead of the others.
 func resortViews(list []resultView, order string, fitFirst bool) {
+	// An empty or unknown order is the default.
+	order = sortOrder(order)
 	// A stable sort, so equal models keep their places.
 	sort.SliceStable(list, func(i, j int) bool {
 		// Fitting models first, when asked.
@@ -1823,8 +1816,8 @@ func resortViews(list []resultView, order string, fitFirst bool) {
 
 // updatedNote explains the order Updated: new to old under the results; it is empty for the other orders and when no model is listed. It says so when no listed model carries update words (a saved copy made before this field existed has none).
 func updatedNote(order string, lists ...[]resultView) string {
-	// Only for the Updated order.
-	if order != "updated" {
+	// Only for the Updated order (the default, also for an empty or unknown order).
+	if sortOrder(order) != "updated" {
 		// Nothing to explain.
 		return ""
 	} // end of the order check
@@ -1870,19 +1863,19 @@ func findSummary(shown, total, cloud, noSize int, order, readAt string) string {
 	if shown < total {
 		// Say how many.
 		// What the shown ones are depends on the chosen order.
-		switch order {
+		switch sortOrder(order) {
 		// Name A to Z.
 		case "name":
 			// The first ones by name.
 			which = fmt.Sprintf("the first %d by name are shown", shown)
-		// Most recently updated first.
-		case "updated":
-			// The most recently updated ones.
-			which = fmt.Sprintf("the %d most recently updated are shown", shown)
-		// The default.
-		default:
+		// Most downloaded first.
+		case "downloads":
 			// The most downloaded ones.
 			which = fmt.Sprintf("the %d most downloaded are shown", shown)
+		// The default: most recently updated first.
+		default:
+			// The most recently updated ones.
+			which = fmt.Sprintf("the %d most recently updated are shown", shown)
 		} // end of the order check
 	} // end of the count check
 	// The verb agrees with the number.
diff --git a/findllm_test.go b/findllm_test.go
index 3d74fec..0164581 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -178,8 +178,12 @@ func TestFindCandidatesFilters(t *testing.T) {
 		// Embedding on its own.
 		{"embedding", findSelection{Abilities: map[string]bool{"embedding": true}}, "gamma", 1, 0},
 	} {
+		// The expected names below are in download order, so that order is asked for (the default order is by update words, which these models do not have).
+		sel := c.sel
+		// Most downloaded first.
+		sel.Sort = "downloads"
 		// Run the filter.
-		got, noSize, cloud := findCandidates(sampleModels(), c.sel)
+		got, noSize, cloud := findCandidates(sampleModels(), sel)
 		// Compare the names.
 		if modelNames(got) != c.want {
 			// Report.
@@ -1751,7 +1755,7 @@ func TestCloudHeadingAndNote(t *testing.T) {
 	} // end of the theme loop
 } // end of TestCloudHeadingAndNote
 
-// TestSortOrder checks the order of the candidates: most downloaded first by default (equal counts by name), and Name A to Z when chosen, for local models and for cloud models.
+// TestSortOrder checks the order of the candidates: most recently updated first by default (without update words: by name), most downloaded first when chosen (equal counts by name), and Name A to Z when chosen, for local models and for cloud models.
 func TestSortOrder(t *testing.T) {
 	// Three local models whose download order differs from their name order, and two cloud models.
 	models := []siteModel{
@@ -1773,13 +1777,20 @@ func TestSortOrder(t *testing.T) {
 		// As text.
 		return strings.Join(out, ",")
 	} // end of names
-	// The default: most downloaded first.
+	// The default is the update order; these models carry no update words, so they are in name order.
 	local, _, _ := findCandidates(models, findSelection{})
 	// Check it.
-	if got := names(local); got != "charlie,bravo,alpha" {
+	if got := names(local); got != "alpha,bravo,charlie" {
 		// Report.
-		t.Errorf("default local order %q, want charlie,bravo,alpha", got)
+		t.Errorf("default local order %q, want alpha,bravo,charlie", got)
 	} // end of the default check
+	// Most downloaded first, when chosen.
+	local, _, _ = findCandidates(models, findSelection{Sort: "downloads"})
+	// Check it.
+	if got := names(local); got != "charlie,bravo,alpha" {
+		// Report.
+		t.Errorf("downloads local order %q, want charlie,bravo,alpha", got)
+	} // end of the downloads check
 	// Name A to Z.
 	local, _, _ = findCandidates(models, findSelection{Sort: "name"})
 	// Check it.
@@ -1826,8 +1837,8 @@ func TestFindSortChoice(t *testing.T) {
 	rig := newThemeRig(t)
 	// The empty form page.
 	_, _, form := get(t, rig.h, http.MethodGet, "/findllm")
-	// The choice sits in the same paragraph as the button, with Most downloaded selected.
-	for _, want := range []string{`<p class="findaction"><button type="submit" class="btn-solid btn-go">Find LLM</button>`, `name="sort"`, `<option value="downloads" selected>Most downloaded</option>`, `<option value="name">Name A to Z</option>`, `Sort by <select class="keepselect" id="sortby" name="sort">`} {
+	// The choice sits in the same paragraph as the button, with Updated: new to old first and selected (the default).
+	for _, want := range []string{`<p class="findaction"><button type="submit" class="btn-solid btn-go">Find LLM</button>`, `name="sort"`, `<option value="updated" selected>Updated: new to old</option>`, `<option value="downloads">Most downloaded</option>`, `<option value="name">Name A to Z</option>`, `Sort by <select class="keepselect" id="sortby" name="sort">`} {
 		// Look for it.
 		if !strings.Contains(form, want) {
 			// Report.
@@ -1841,13 +1852,20 @@ func TestFindSortChoice(t *testing.T) {
 		// Report.
 		t.Error("Name A to Z is not kept after the search")
 	} // end of the kept check
-	// An unknown value falls back to the default.
+	// An unknown value falls back to the default, Updated: new to old.
 	_, odd := postFind(t, rig, url.Values{"token": {rig.token}, "sort": {"nonsense"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
 	// The default is selected.
-	if !strings.Contains(odd, `<option value="downloads" selected>Most downloaded</option>`) {
+	if !strings.Contains(odd, `<option value="updated" selected>Updated: new to old</option>`) {
 		// Report.
-		t.Error("an unknown sort value did not fall back to Most downloaded")
+		t.Error("an unknown sort value did not fall back to Updated: new to old")
 	} // end of the fallback check
+	// Most downloaded, when chosen, is kept.
+	_, dl := postFind(t, rig, url.Values{"token": {rig.token}, "sort": {"downloads"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
+	// Kept.
+	if !strings.Contains(dl, `<option value="downloads" selected>Most downloaded</option>`) || strings.Contains(dl, `<option value="updated" selected>`) {
+		// Report.
+		t.Error("Most downloaded is not kept after the search")
+	} // end of the downloads check
 } // end of TestFindSortChoice
 
 // TestFindKeptSearchAndReset: the last search is kept in memory (choices and results) and shown again when the page is opened; the Reset button appears only after a search and forgets it; a new program starts empty.
@@ -1908,10 +1926,10 @@ func TestFindKeptSearchAndReset(t *testing.T) {
 		// Report.
 		t.Errorf("reset = %d to %q, want 303 to /findllm", res.StatusCode, res.Header.Get("Location"))
 	} // end of the redirect check
-	// After the reset: the starting form again, no results, no Reset button, Most downloaded selected.
+	// After the reset: the starting form again, no results, no Reset button, Updated: new to old selected.
 	_, _, cleared := get(t, rig.h, http.MethodGet, "/findllm")
 	// Nothing kept.
-	if strings.Contains(cleared, "Reset Find LLM search options") || strings.Contains(cleared, "Models found") || !strings.Contains(cleared, `<option value="downloads" selected>Most downloaded</option>`) {
+	if strings.Contains(cleared, "Reset Find LLM search options") || strings.Contains(cleared, "Models found") || !strings.Contains(cleared, `<option value="updated" selected>Updated: new to old</option>`) {
 		// Report.
 		t.Error("the page after the reset still shows the kept search")
 	} // end of the cleared check
diff --git a/findupdated_test.go b/findupdated_test.go
index f30b6dd..3ef9001 100644
--- a/findupdated_test.go
+++ b/findupdated_test.go
@@ -223,12 +223,12 @@ func TestFindSearchSortsByUpdated(t *testing.T) {
 	})
 	// The rig.
 	rig := newThemeRig(t)
-	// The starting page offers the new choice.
+	// The starting page offers the choice, first in the list and selected: it is the default.
 	_, _, form := get(t, rig.h, http.MethodGet, "/findllm")
 	// Check it.
-	if !strings.Contains(form, `<option value="updated">Updated: new to old</option>`) || !strings.Contains(form, `<option value="downloads" selected>Most downloaded</option>`) {
+	if !strings.Contains(form, `<option value="updated" selected>Updated: new to old</option><option value="downloads">Most downloaded</option><option value="name">Name A to Z</option>`) {
 		// Report.
-		t.Error("the starting page lacks the Updated choice, or Most downloaded is not the default")
+		t.Error("the starting page does not offer Updated: new to old first and selected")
 	} // end of the choice check
 	// A search with the new order.
 	status, body := postFind(t, rig, url.Values{"token": {rig.token}, "sort": {"updated"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
@@ -254,6 +254,13 @@ func TestFindSearchSortsByUpdated(t *testing.T) {
 		// Report.
 		t.Error("the choice is not kept after the search, or the note is missing")
 	} // end of the kept check
+	// A search that sends no choice at all uses the default, the update order, and shows the note.
+	_, dflt := postFind(t, rig, url.Values{"token": {rig.token}, "disk_gb": {"100"}, "mem_gb": {"64"}})
+	// Check it.
+	if !(at(dflt, "bbb") > 0 && at(dflt, "bbb") < at(dflt, "ccc") && at(dflt, "ccc") < at(dflt, "aaa")) || !strings.Contains(dflt, "Models are ordered by the update words ollama.com shows") {
+		// Report.
+		t.Error("a search without a sort choice is not in the update order with its note")
+	} // end of the default check
 	// Re-sort the kept results by name: aaa, bbb, ccc, and the note goes away.
 	res := post(t, rig.h, "/findllm/resort", url.Values{"token": {rig.token}, "sort": {"name"}}, fromThisPage)
 	// Check the redirect.
@@ -283,3 +290,15 @@ func TestFindSearchSortsByUpdated(t *testing.T) {
 		t.Error("the re-sort by the update words did not give bbb, ccc, aaa with the choice kept")
 	} // end of the updated check
 } // end of TestFindSearchSortsByUpdated
+
+// TestSortOrderUsesTheUpdateOrderUnlessAskedOtherwise checks that only the exact words name and downloads change the order; an empty or unknown text is the default, Updated: new to old.
+func TestSortOrderUsesTheUpdateOrderUnlessAskedOtherwise(t *testing.T) {
+	// Each text and the order it gives.
+	for text, want := range map[string]string{"": "updated", "updated": "updated", "nonsense": "updated", "Name": "updated", "name": "name", "downloads": "downloads"} {
+		// Convert.
+		if got := sortOrder(text); got != want {
+			// Report.
+			t.Errorf("sortOrder(%q) = %q, want %q", text, got, want)
+		} // end of the check
+	} // end of the loop
+} // end of TestSortOrderUsesTheUpdateOrderUnlessAskedOtherwise
diff --git a/sortpick_test.go b/sortpick_test.go
index fc91792..e844774 100644
--- a/sortpick_test.go
+++ b/sortpick_test.go
@@ -120,7 +120,7 @@ func TestFindResortKeepsTheSearch(t *testing.T) {
 		t.Errorf("resort with a wrong token = %d, want 403", bad.StatusCode)
 	} // end of the check
 	// Still the default order after the refusal.
-	if _, _, still := get(t, rig.h, http.MethodGet, "/findllm"); !strings.Contains(still, `<option value="downloads" selected>`) {
+	if _, _, still := get(t, rig.h, http.MethodGet, "/findllm"); !strings.Contains(still, `<option value="updated" selected>`) {
 		// Report.
 		t.Error("a refused re-sort changed the order choice")
 	} // end of the check
@@ -141,7 +141,7 @@ func TestFindResortKeepsTheSearch(t *testing.T) {
 	// Back to the default order.
 	post(t, rig.h, "/findllm/resort", url.Values{"token": {rig.token}}, fromThisPage)
 	// Check.
-	if _, _, back := get(t, rig.h, http.MethodGet, "/findllm"); !strings.Contains(back, `<option value="downloads" selected>`) {
+	if _, _, back := get(t, rig.h, http.MethodGet, "/findllm"); !strings.Contains(back, `<option value="updated" selected>`) {
 		// Report.
 		t.Error("the default order did not come back")
 	} // end of the check
diff --git a/web/findllm.html b/web/findllm.html
index 759cac2..3d1f237 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -93,7 +93,7 @@
 </fieldset>
 {{/* The button: the first and only thing that reads the internet. */}}
 {{/* The button, with the order of the results beside it. */}}
-<p class="findaction"><button type="submit" class="btn-solid btn-go">Find LLM</button> <label class="sortpick" for="sortby">Sort by <select class="keepselect" id="sortby" name="sort"{{if .CanResort}} data-resort="/findllm/resort"{{end}}><option value="downloads"{{if not (or .SortName .SortUpdated)}} selected{{end}}>Most downloaded</option><option value="name"{{if .SortName}} selected{{end}}>Name A to Z</option><option value="updated"{{if .SortUpdated}} selected{{end}}>Updated: new to old</option></select></label>{{if .Searched}} <span class="tipbox"><button type="submit" class="btn-plain" formaction="/findllm/reset" formnovalidate aria-describedby="tip-reset">Reset Find LLM search options</button><span class="tip tip-icon" role="tooltip" id="tip-reset">Forget the last search and show the starting ticks.</span></span>{{end}} <span class="tipbox backhere"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback-row"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback-row">Back to the monitor</span></span></p>
+<p class="findaction"><button type="submit" class="btn-solid btn-go">Find LLM</button> <label class="sortpick" for="sortby">Sort by <select class="keepselect" id="sortby" name="sort"{{if .CanResort}} data-resort="/findllm/resort"{{end}}><option value="updated"{{if .SortUpdated}} selected{{end}}>Updated: new to old</option><option value="downloads"{{if not (or .SortName .SortUpdated)}} selected{{end}}>Most downloaded</option><option value="name"{{if .SortName}} selected{{end}}>Name A to Z</option></select></label>{{if .Searched}} <span class="tipbox"><button type="submit" class="btn-plain" formaction="/findllm/reset" formnovalidate aria-describedby="tip-reset">Reset Find LLM search options</button><span class="tip tip-icon" role="tooltip" id="tip-reset">Forget the last search and show the starting ticks.</span></span>{{end}} <span class="tipbox backhere"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback-row"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback-row">Back to the monitor</span></span></p>
 </form>
 {{/* The results appear only after the button was pressed. */}}
 {{if .Searched}}
OCC_PATCH_129_END
# First only CHECK that the patch fits; nothing is changed yet.
git apply --check "$PATCH_FILE" || fail "git apply --check refused the patch; nothing was changed"
# Report it.
pass "git apply --check: the patch fits"
# Now apply it for real.
git apply "$PATCH_FILE" || fail "git apply failed"
# Report it.
pass "patch applied"

# The patched files must be exactly what was tested in the sandbox.
for F in "${!AFTER[@]}"; do
  # A mismatch means something changed on the way.
  [ "$(sha "$F")" = "${AFTER[$F]}" ] || fail "$F has an unexpected sha256 after the change"
# End of the loop over the files.
done
# Report it.
pass "all ${#AFTER[@]} files have the expected sha256"

# Only the five expected tracked files may differ from the last commit (the same five as after script 128).
CHANGED="$(git diff --name-only | LC_ALL=C sort | tr '\n' ' ')"
# The expected list.
EXPECTED="findllm.go findllm_test.go findsite.go sortpick_test.go web/findllm.html "
# Anything else is a failure.
[ "$CHANGED" = "$EXPECTED" ] || fail "other files changed than expected: $CHANGED"
# Report it.
pass "only the expected five files differ from the last commit, plus the new test file"

# The key lines must be in place.
grep -q 'func sortOrder' findllm.go && grep -q '<option value="updated"{{if .SortUpdated}} selected{{end}}>Updated: new to old</option><option value="downloads"' web/findllm.html || fail "a key line of the change is missing"
# Report it.
pass "sortOrder and the new order of the choices are in place"

# gofmt lists files whose layout differs from the standard.
UNFORMATTED="$(gofmt -l .)"
# Anything listed is a failure.
[ -z "$UNFORMATTED" ] || fail "gofmt wants to change: $UNFORMATTED"
# Report it.
pass "gofmt: nothing to change"

# go vet looks for suspicious code (and compiles the tests).
go vet ./... || fail "go vet found a problem"
# Report it.
pass "go vet: clean"

# Run every test once; a timing failure of TestTableColumnOrder or TestDeleteConfirmRefusesLoadedModel is reported and not hidden.
go test -count=1 ./... || fail "go test failed (if only TestTableColumnOrder or TestDeleteConfirmRefusesLoadedModel failed, run the tests once more and tell Claude)"
# Report it.
pass "go test: all tests pass"

# Build the program for all six systems.
for TARGET in linux/amd64 linux/arm64 windows/amd64 windows/arm64 darwin/arm64 darwin/amd64; do
  # Split "windows/amd64" into the system and the processor.
  OS_NAME="${TARGET%/*}"
  # The processor part.
  ARCH_NAME="${TARGET#*/}"
  # Build to nowhere (/dev/null) just to see that it compiles.
  GOOS="$OS_NAME" GOARCH="$ARCH_NAME" CGO_ENABLED=0 go build -o /dev/null . || fail "build for $TARGET failed"
  # Report it.
  pass "program builds for $TARGET"
# End of the loop over the systems.
done

# The summary.
echo "Result: $PASS passed, $FAIL failed"
# What to do next.
echo "NEXT  test Sort by by hand (instructions follow in the chat), then commit and push."
# Show what changed in the project folder.
git status --short
