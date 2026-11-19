#!/usr/bin/env bash
# Script 128 (Sort by: Updated, new to old): the Find LLM page gets a third choice in Sort by, "Updated: new to old". The list page of ollama.com writes, for every model, when it was last updated in rounded words ("6 days ago", "1 month ago", "2 years ago"; no exact date); the reader now keeps these words, and the new order lists the most recently updated model first, models with the same words by name A to Z, and a model without words last. The sentence above a cut list says which models are shown for the chosen order; a note under the results explains the rounding. No extra request to ollama.com is made (the words are on the list page that is read anyway), and a saved copy of the list made by an older version simply has no words (the note says so). Version stays 0.33.0 until the release is made.
# Run it on a NEW branch made from the updated main (never main): cd ~/LLMsControlDock-2 && git switch main && git pull && git switch -c feature/find-llm-sort-updated && bash scripts/128-step90-find-llm-sort-updated.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the five existing files BEFORE the change (as on main after pull request 59) and of all six files AFTER it (the sixth, findupdated_test.go, is new).
declare -A BEFORE AFTER
BEFORE["findllm.go"]="8398a24fe9af421689e4a7fce0e7dedce415ac0fee876407f6df6f8689b4d296"
BEFORE["findllm_test.go"]="f86bebe0a17bb30dd402c489a753de0787058dff42b7de672ae59e013aff933e"
BEFORE["findsite.go"]="c27211e06889c512f6812eca0153745925c94049487af3dde7fee414aa2c5387"
BEFORE["sortpick_test.go"]="d3a63e057536a61bf588a3960f6af3bfe7b21ddd417b132abebdff1e641ff790"
BEFORE["web/findllm.html"]="d728d77623479592b86ecd40ab6c042eed432b84497ad5391c3af5809054e503"
AFTER["findllm.go"]="50e69b3c226291bc679e1b15cdab63964727e91978700e6c85e434d12f3c9c4f"
AFTER["findllm_test.go"]="92338220e892c0532d5e57ad6fbb421e2e6f7b2f1ae53d06743823f6189077d6"
AFTER["findsite.go"]="c6fd1b280b2bf29caf668bf5e63d43207095fed625c46a85ce861bc3a7f04d71"
AFTER["sortpick_test.go"]="3d919c4f30147e3c5c7302ada4acaf259e80e49ac88a231ecf2b226265293224"
AFTER["web/findllm.html"]="afff22cd54734cb484e2a13e89518c698a35620ad8a2198192705f13f2de1be4"
AFTER["findupdated_test.go"]="fcee04e2116cdf79515035d401bf57b15e6b349efe9fd9e3afee826cd56660a8"

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
[ "$BRANCH" != "main" ] || fail "you are on main; make a branch first: git switch -c feature/find-llm-sort-updated"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Pull request 59 must be in (the unknown-label notice is its last piece).
grep -q 'unknownLabelNote' findsite.go || fail "pull request 59 is not in this branch; run git pull on main first"
# Report it.
pass "pull request 59 is in"

# Refuse to run twice: the new test file is the sign.
if [ -e findupdated_test.go ]; then fail "findupdated_test.go exists: this script was already applied"; fi
# Report it.
pass "this change is not applied yet"

# Every existing file must be exactly the version the patch was made against.
for F in "${!BEFORE[@]}"; do
  # A mismatch means the file is not the expected version.
  [ "$(sha "$F")" = "${BEFORE[$F]}" ] || fail "$F is not the expected version (sha256 differs); tell Claude which state you are in"
# End of the loop over the files.
done
# Report it.
pass "all ${#BEFORE[@]} existing files are the expected versions before the change"

# The temporary file for the patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary file at the end, whatever happens.
trap 'rm -f "$PATCH_FILE"' EXIT
# Write the embedded patch into the temporary file; the quoted marker stops the shell from changing anything inside.
cat > "$PATCH_FILE" <<'OCC_PATCH_128_END'
diff --git a/findllm.go b/findllm.go
index 6c4d13a..6139eeb 100644
--- a/findllm.go
+++ b/findllm.go
@@ -306,7 +306,7 @@ type findSelection struct {
 	Chat bool
 	// Abilities are the ticked abilities (tools, vision, audio, thinking, embedding, decision).
 	Abilities map[string]bool
-	// Sort is how the models are ordered: "downloads" (the default, also when empty) or "name".
+	// Sort is how the models are ordered: "downloads" (the default, also when empty), "name" or "updated" (the most recently updated first).
 	Sort string
 	// Domains are the ticked fields of use (keys of findDomains); empty means no filter.
 	Domains map[string]bool
@@ -357,10 +357,16 @@ func parseFindForm(get func(string) string) (findSelection, []string) {
 	sel.Chat = get("ab_chat") == "on"
 	// Match ANY only when that exact choice was sent; anything else, or nothing, is the default Match ALL.
 	sel.Any = get("ab_mode") == "any"
-	// The order of the results: Name A to Z only when that exact choice was sent; anything else is the default, most downloaded.
-	if get("sort") == "name" {
-		// Name order.
+	// The order of the results: Name A to Z or Updated only when that exact choice was sent; anything else is the default, most downloaded.
+	switch get("sort") {
+	// Name order.
+	case "name":
+		// Keep it.
 		sel.Sort = "name"
+	// Most recently updated first.
+	case "updated":
+		// Keep it.
+		sel.Sort = "updated"
 	} // end of the sort check
 	// The same for the fields of use.
 	sel.DomainAny = get("dom_mode") == "any"
@@ -518,8 +524,36 @@ func domainMatch(sel findSelection, m siteModel) bool {
 	return hits == len(sel.Domains)
 } // end of domainMatch
 
-// modelBefore says whether model a is listed before model b: by name for the choice Name A to Z, otherwise most downloaded first, with equal counts keeping the name order so the list is stable.
+// updatedBefore says whether a model updated aWords ago comes before one updated bWords ago: the more recent first, a model without readable update words last, equal words by name so the list is stable.
+func updatedBefore(aWords, aName, bWords, bName string) bool {
+	// The ages in hours; -1 means not known.
+	ha, hb := updatedHours(aWords), updatedHours(bWords)
+	// Different ages decide.
+	if ha != hb {
+		// A model with no age goes after one with an age.
+		if ha < 0 {
+			// a is after b.
+			return false
+		} // end of the a check
+		// A model with no age goes after one with an age.
+		if hb < 0 {
+			// a is before b.
+			return true
+		} // end of the b check
+		// The smaller age is the more recent update.
+		return ha < hb
+	} // end of the age check
+	// The same words: by name.
+	return aName < bName
+} // end of updatedBefore
+
+// modelBefore says whether model a is listed before model b: by name for the choice Name A to Z, by update words for Updated, otherwise most downloaded first, with equal counts keeping the name order so the list is stable.
 func modelBefore(sel findSelection, a, b siteModel) bool {
+	// Most recently updated first.
+	if sel.Sort == "updated" {
+		// By the update words.
+		return updatedBefore(a.Updated, a.Name, b.Updated, b.Name)
+	} // end of the updated order
 	// Name A to Z.
 	if sel.Sort == "name" {
 		// By name.
@@ -635,7 +669,7 @@ func findCandidates(models []siteModel, sel findSelection) (out []siteModel, noS
 		// It passed.
 		out = append(out, m)
 	} // end of the model loop
-	// The chosen order: most downloaded first (the default) or Name A to Z.
+	// The chosen order: most downloaded first (the default), Name A to Z, or most recently updated first.
 	sort.SliceStable(out, func(i, j int) bool {
 		// Compare as chosen.
 		return modelBefore(sel, out[i], out[j])
@@ -671,7 +705,7 @@ func findCloudModels(models []siteModel, sel findSelection) (out []siteModel, sk
 			out = append(out, m)
 		} // end of the match check
 	} // end of the model loop
-	// The chosen order: most downloaded first (the default) or Name A to Z.
+	// The chosen order: most downloaded first (the default), Name A to Z, or most recently updated first.
 	sort.SliceStable(out, func(i, j int) bool {
 		// Compare as chosen.
 		return modelBefore(sel, out[i], out[j])
@@ -683,7 +717,7 @@ func findCloudModels(models []siteModel, sel findSelection) (out []siteModel, sk
 // cloudView makes the view of a cloud-only model: no versions are read for it, because nothing is downloaded.
 func cloudView(m siteModel) resultView {
 	// The basic facts, with the cloud state.
-	return resultView{Name: m.Name, Description: m.Description, Abilities: strings.Join(m.Abilities, ", "), Pulls: m.Pulls, URL: ollamaSite + "/library/" + m.Name, State: "cloud"}
+	return resultView{Name: m.Name, Description: m.Description, Abilities: strings.Join(m.Abilities, ", "), Pulls: m.Pulls, Updated: m.Updated, URL: ollamaSite + "/library/" + m.Name, State: "cloud"}
 } // end of cloudView
 
 // versionReason says why a version does not fit this computer; empty text means it fits.
@@ -765,6 +799,8 @@ type resultView struct {
 	Abilities, Sizes string
 	// Pulls is the download count as written on the page.
 	Pulls string
+	// Updated is how long ago ollama.com says the model was updated, for example "1 month ago" (empty when not shown); the Updated order uses it.
+	Updated string
 	// URL is the official model page.
 	URL string
 	// Versions are the versions listed (the ones that fit first).
@@ -1104,7 +1140,7 @@ func applyOllamaNeed(r *resultView, need string, run checkResult) {
 // buildResult turns a model and its versions into the view; tags is nil when the tags page could not be read, and why says what went wrong.
 func buildResult(m siteModel, tags []siteTag, why string, sel findSelection, mark func(string) (bool, string)) resultView {
 	// The basic facts.
-	r := resultView{Name: m.Name, Description: m.Description, Abilities: strings.Join(m.Abilities, ", "), Sizes: strings.Join(m.Sizes, ", "), Pulls: m.Pulls, URL: ollamaSite + "/library/" + m.Name}
+	r := resultView{Name: m.Name, Description: m.Description, Abilities: strings.Join(m.Abilities, ", "), Sizes: strings.Join(m.Sizes, ", "), Pulls: m.Pulls, Updated: m.Updated, URL: ollamaSite + "/library/" + m.Name}
 	// Which choices of the person this model matched.
 	r.Because = qualifyReasons(m, sel)
 	// The tags page could not be read: say so, never guess.
@@ -1270,8 +1306,12 @@ type findPage struct {
 	AnyMode bool
 	// Domains are the boxes of the fields of use.
 	Domains []domainTick
-	// SortName is whether Name A to Z is chosen; false means most downloaded.
+	// SortName is whether Name A to Z is chosen.
 	SortName bool
+	// SortUpdated is whether Updated: new to old is chosen; when neither this nor SortName is true, most downloaded is chosen.
+	SortUpdated bool
+	// UpdatedNote explains the Updated order under the results (rounded words, ties by name); empty for the other orders.
+	UpdatedNote string
 	// DomainAnyMode is whether "Match ANY ticked" is chosen for the fields of use.
 	DomainAnyMode bool
 	// Disk and Mem are the typed numbers, as text.
@@ -1376,7 +1416,7 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 	// render draws the page for a selection.
 	render := func(w http.ResponseWriter, r *http.Request, sel findSelection, fm findMachine, problems []string, searched bool, results []resultView, cloudRes []resultView, cloudMore int, total, cloud, noSize int, errText, readAt, copyNote, instNote string, status int) {
 		// The tick boxes.
-		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, AnyMode: sel.Any, DomainAnyMode: sel.DomainAny, SortName: sel.Sort == "name", Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, InstalledNote: instNote, CloudResults: cloudRes, CloudMore: cloudMore, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
+		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, AnyMode: sel.Any, DomainAnyMode: sel.DomainAny, SortName: sel.Sort == "name", SortUpdated: sel.Sort == "updated", UpdatedNote: updatedNote(sel.Sort, results, cloudRes), Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, InstalledNote: instNote, CloudResults: cloudRes, CloudMore: cloudMore, Results: results, Summary: findSummary(len(results), total, cloud, noSize, sel.Sort, readAt)}
 		// The abilities.
 		for _, k := range abilityKeys {
 			// One box.
@@ -1584,7 +1624,7 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 		shown := cands
 		// Cut the list.
 		if len(shown) > maxFindResults {
-			// Keep the most downloaded.
+			// Keep the first ones of the chosen order.
 			shown = shown[:maxFindResults]
 		} // end of the cut
 		// What is installed here now, so installed versions can be marked; if Ollama cannot be read, nothing is marked and the page says so.
@@ -1665,7 +1705,7 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 		cloudModels, cloudSkipped := findCloudModels(models, sel)
 		// How many are shown and how many are only counted.
 		var cloudRes []resultView
-		// The most downloaded ones.
+		// The first ones of the chosen order.
 		for i, m := range cloudModels {
 			// Stop at the limit.
 			if i >= maxFindCloud {
@@ -1722,18 +1762,25 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 		keptMu.Lock()
 		// Only when there is a kept search.
 		if kept != nil {
-			// The new order: Name A to Z or, by default, most downloaded.
-			if r.PostFormValue("sort") == "name" {
-				// By name.
+			// The new order: Name A to Z, most recently updated first or, by default, most downloaded.
+			switch r.PostFormValue("sort") {
+			// By name.
+			case "name":
+				// Keep it.
 				kept.sel.Sort = "name"
-			} else {
-				// By downloads.
+			// By the update words.
+			case "updated":
+				// Keep it.
+				kept.sel.Sort = "updated"
+			// Anything else: by downloads.
+			default:
+				// The default.
 				kept.sel.Sort = "downloads"
 			} // end of the order choice
 			// Sort the local models, keeping the ones with a fitting version first.
-			resortViews(kept.results, kept.sel.Sort == "name", true)
+			resortViews(kept.results, kept.sel.Sort, true)
 			// Sort the cloud-only models (they have no versions to fit).
-			resortViews(kept.cloudRes, kept.sel.Sort == "name", false)
+			resortViews(kept.cloudRes, kept.sel.Sort, false)
 		} // end of the kept check
 		keptMu.Unlock()
 		// Back to the page at the Sort by choice; a redirect keeps a reload from sending the form again.
@@ -1743,8 +1790,8 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 	return show, search, reset, resort
 } // end of findLLMHandlers
 
-// resortViews puts shown models in order again: Name A to Z or most downloaded first (equal counts by name); with fitFirst a model that has a fitting version stays ahead of the others.
-func resortViews(list []resultView, byName, fitFirst bool) {
+// resortViews puts shown models in order again: order "name" is Name A to Z, "updated" is the most recently updated first (same words by name), anything else is most downloaded first (equal counts by name); with fitFirst a model that has a fitting version stays ahead of the others.
+func resortViews(list []resultView, order string, fitFirst bool) {
 	// A stable sort, so equal models keep their places.
 	sort.SliceStable(list, func(i, j int) bool {
 		// Fitting models first, when asked.
@@ -1753,10 +1800,15 @@ func resortViews(list []resultView, byName, fitFirst bool) {
 			return list[i].FitCount > 0
 		} // end of the fit check
 		// By name.
-		if byName {
+		if order == "name" {
 			// A to Z.
 			return list[i].Name < list[j].Name
 		} // end of the name order
+		// By the update words.
+		if order == "updated" {
+			// The more recent first.
+			return updatedBefore(list[i].Updated, list[i].Name, list[j].Updated, list[j].Name)
+		} // end of the updated order
 		// The download counts.
 		pi, pj := pullsNumber(list[i].Pulls), pullsNumber(list[j].Pulls)
 		// The higher count first.
@@ -1769,8 +1821,44 @@ func resortViews(list []resultView, byName, fitFirst bool) {
 	}) // end of the sort
 } // end of resortViews
 
+// updatedNote explains the order Updated: new to old under the results; it is empty for the other orders and when no model is listed. It says so when no listed model carries update words (a saved copy made before this field existed has none).
+func updatedNote(order string, lists ...[]resultView) string {
+	// Only for the Updated order.
+	if order != "updated" {
+		// Nothing to explain.
+		return ""
+	} // end of the order check
+	// How many models are listed and how many of them carry readable update words.
+	total, known := 0, 0
+	// Each list (local and cloud-only).
+	for _, l := range lists {
+		// Each model.
+		for _, v := range l {
+			// One more model.
+			total++
+			// It carries update words.
+			if updatedHours(v.Updated) >= 0 {
+				// One more with words.
+				known++
+			} // end of the words check
+		} // end of the model loop
+	} // end of the list loop
+	// No model is listed: nothing to explain.
+	if total == 0 {
+		// Empty.
+		return ""
+	} // end of the empty check
+	// No model has update words: say why the order is the name order.
+	if known == 0 {
+		// The honest reason.
+		return "No update words are available for these models (a saved copy of the list made by an older version of this program has none), so they are in name order."
+	} // end of the none check
+	// The usual explanation.
+	return "Models are ordered by the update words ollama.com shows for each model, such as \"1 month ago\", the most recent first. The words are rounded and give no exact date, so models with the same words are in name order, and a model without update words comes last."
+} // end of updatedNote
+
 // findSummary writes the sentence above the results in correct singular and plural.
-func findSummary(shown, total, cloud, noSize int, readAt string) string {
+func findSummary(shown, total, cloud, noSize int, order, readAt string) string {
 	// Nothing matched.
 	if total == 0 {
 		// Say so, with the same facts.
@@ -1781,7 +1869,21 @@ func findSummary(shown, total, cloud, noSize int, readAt string) string {
 	// Fewer shown than matching.
 	if shown < total {
 		// Say how many.
-		which = fmt.Sprintf("the %d most downloaded are shown", shown)
+		// What the shown ones are depends on the chosen order.
+		switch order {
+		// Name A to Z.
+		case "name":
+			// The first ones by name.
+			which = fmt.Sprintf("the first %d by name are shown", shown)
+		// Most recently updated first.
+		case "updated":
+			// The most recently updated ones.
+			which = fmt.Sprintf("the %d most recently updated are shown", shown)
+		// The default.
+		default:
+			// The most downloaded ones.
+			which = fmt.Sprintf("the %d most downloaded are shown", shown)
+		} // end of the order check
 	} // end of the count check
 	// The verb agrees with the number.
 	verb := "match"
diff --git a/findllm_test.go b/findllm_test.go
index 0c61886..3d74fec 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -531,7 +531,7 @@ func TestFindSummaryWording(t *testing.T) {
 		{0, 0, 1, 1, []string{"No model matches your choices.", "1 cloud model (it runs", "1 model that shows no size was left out"}},
 	} {
 		// Build it.
-		got := findSummary(c.shown, c.total, c.cloud, c.noSize, "2026-11-08 20:36:00 CET (UTC+01:00)")
+		got := findSummary(c.shown, c.total, c.cloud, c.noSize, "downloads", "2026-11-08 20:36:00 CET (UTC+01:00)")
 		// Each phrase.
 		for _, w := range c.want {
 			// Look for it.
diff --git a/findsite.go b/findsite.go
index 622ef7e..2e01ea2 100644
--- a/findsite.go
+++ b/findsite.go
@@ -59,6 +59,8 @@ type siteModel struct {
 	Other []string
 	// Pulls is the download count as the page writes it, for example "120.9M".
 	Pulls string
+	// Updated is how long ago the model was updated, as the list page writes it, for example "1 month ago"; empty when not shown (also in a saved copy made before this field existed). The page gives no exact date.
+	Updated string
 } // end of siteModel
 
 // siteTag is one downloadable version of a model as its tags page shows it.
@@ -94,6 +96,9 @@ var entryBadge = regexp.MustCompile(`<span\s+class="inline-flex[^"]*"[^>]*>([^<]
 // entryPulls finds the download count inside one entry.
 var entryPulls = regexp.MustCompile(`<span >([^<]+)</span>\s*<span class="hidden sm:flex">&nbsp;Pulls`)
 
+// entryUpdated finds the update words ("6 days ago", "1 month ago") inside one entry.
+var entryUpdated = regexp.MustCompile(`Updated&nbsp;</span>\s*<span >([^<]+)</span>`)
+
 // sizeLabel recognises a size label such as 0.6b, 350m, 8b, e4b or a mixture such as 8x7b (8 parts of 7 billion).
 var sizeLabel = regexp.MustCompile(`^(?:[0-9]+x)?e?[0-9]+(\.[0-9]+)?[mb]$`)
 
@@ -156,6 +161,11 @@ func parseSiteList(page string) ([]siteModel, error) {
 			// As written.
 			m.Pulls = strings.TrimSpace(pl[1])
 		} // end of the pulls
+		// The update words are optional.
+		if u := entryUpdated.FindStringSubmatch(p); u != nil {
+			// As written, without extra spaces.
+			m.Updated = strings.TrimSpace(html.UnescapeString(u[1]))
+		} // end of the update words
 		// Add the model.
 		out = append(out, m)
 	} // end of the entry loop
@@ -215,6 +225,19 @@ var tagContext = regexp.MustCompile(`([0-9]+(?:\.[0-9]+)?[KM]?) context window`)
 // tagAge finds the update age such as "1 year ago", "3 weeks ago" or "an hour ago".
 var tagAge = regexp.MustCompile(`\b(\d+|an?) (second|minute|hour|day|week|month|year)s? ago\b`)
 
+// updatedHours turns the update words of a model ("6 days ago") into hours; empty or unreadable words give -1, which is listed last.
+func updatedHours(words string) int64 {
+	// Find the number and the unit.
+	a := tagAge.FindStringSubmatch(words)
+	// Nothing readable.
+	if a == nil {
+		// Not known.
+		return -1
+	} // end of the read check
+	// The same rounding as for the versions.
+	return ageHours(a[1], a[2])
+} // end of updatedHours
+
 // ageHours turns the words of an age into hours, rounded the way the words are; unreadable words give -1.
 func ageHours(count, unit string) int64 {
 	// "a" and "an" mean one.
diff --git a/findupdated_test.go b/findupdated_test.go
new file mode 100644
index 0000000..f30b6dd
--- /dev/null
+++ b/findupdated_test.go
@@ -0,0 +1,285 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this test file uses.
+	// net/http gives the status codes and the request method names.
+	"net/http"
+	// net/url builds the form values.
+	"net/url"
+	// strings searches the page text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// updatedSpan writes the update words the way the list page writes them, inside one entry.
+func updatedSpan(words string) string {
+	// The clock icon, the word Updated and the rounded age, as in the real markup.
+	return "<span class=\"flex items-center\">\n<svg viewBox=\"0 0 24 24\"><path d=\"M12 6v6\"></path></svg>\n<span class=\"hidden sm:flex\">Updated&nbsp;</span>\n<span >" + words + "</span>\n</span>\n"
+} // end of updatedSpan
+
+// listEntryUpdated writes a list entry like listEntry, with the update words added before the end of its link; empty words leave the entry without them.
+func listEntryUpdated(name, words string, labels ...string) string {
+	// The normal entry.
+	e := listEntry(name, "An invented model.", labels...)
+	// No words: as it is.
+	if words == "" {
+		// Unchanged.
+		return e
+	} // end of the empty check
+	// Put the words in before the end of the link.
+	return strings.Replace(e, "</a>", updatedSpan(words)+"</a>", 1)
+} // end of listEntryUpdated
+
+// namesInOrder lists the names of models in the order given, joined by commas.
+func namesInOrder(ms []siteModel) string {
+	// The names.
+	var out []string
+	// Each model.
+	for _, m := range ms {
+		// One name.
+		out = append(out, m.Name)
+	} // end of the loop
+	// As text.
+	return strings.Join(out, ",")
+} // end of namesInOrder
+
+// TestParseSiteListReadsTheUpdateWords checks that the list reader keeps the update words of each model, leaves them empty when the page has none, and still reads the download count.
+func TestParseSiteListReadsTheUpdateWords(t *testing.T) {
+	// A page with one entry that has update words and one that has none.
+	page := "<html><ul>" + listEntryUpdated("with", "6 days ago", "tools", "8b") + listEntryUpdated("without", "", "tools", "8b") + "</ul></html>"
+	// Read it.
+	models, err := parseSiteList(page)
+	// A failure means the reader broke.
+	if err != nil || len(models) != 2 {
+		// Stop.
+		t.Fatalf("parseSiteList: %v, %d models", err, len(models))
+	} // end of the read check
+	// The first model carries the words, and its download count is still read.
+	if models[0].Updated != "6 days ago" || models[0].Pulls != "1.5M" {
+		// Report.
+		t.Errorf("first model: updated %q, pulls %q", models[0].Updated, models[0].Pulls)
+	} // end of the first check
+	// The second has no words.
+	if models[1].Updated != "" {
+		// Report.
+		t.Errorf("second model: updated %q, want empty", models[1].Updated)
+	} // end of the second check
+} // end of TestParseSiteListReadsTheUpdateWords
+
+// TestUpdatedHoursReadsTheWords checks how the update words become hours, and that unreadable words give -1.
+func TestUpdatedHoursReadsTheWords(t *testing.T) {
+	// Words and the hours they stand for (a day is 24, a week 168, a month 730, a year 8760 hours).
+	for words, want := range map[string]int64{"an hour ago": 1, "6 days ago": 144, "1 week ago": 168, "2 weeks ago": 336, "1 month ago": 730, "3 months ago": 2190, "1 year ago": 8760, "": -1, "soon": -1, "just now": -1} {
+		// Convert.
+		if got := updatedHours(words); got != want {
+			// Report.
+			t.Errorf("updatedHours(%q) = %d, want %d", words, got, want)
+		} // end of the check
+	} // end of the loop
+} // end of TestUpdatedHoursReadsTheWords
+
+// TestUpdatedOrder checks the order Updated: new to old for local and cloud-only models: the more recent first, equal words by name, no words last.
+func TestUpdatedOrder(t *testing.T) {
+	// Local models with different update words, two with the same words, and one without words; the cloud-only ones are separate.
+	models := []siteModel{
+		{Name: "bravo", Updated: "1 month ago", Sizes: []string{"8b"}},
+		{Name: "alpha", Updated: "1 month ago", Sizes: []string{"8b"}},
+		{Name: "charlie", Updated: "6 days ago", Sizes: []string{"8b"}},
+		{Name: "delta", Updated: "2 years ago", Sizes: []string{"8b"}},
+		{Name: "echo", Sizes: []string{"8b"}},
+		{Name: "foxtrot", Updated: "1 year ago", Sizes: []string{"8b"}},
+		{Name: "zeta", Updated: "1 week ago", Cloud: true},
+		{Name: "yankee", Updated: "1 week ago", Cloud: true},
+		{Name: "xray", Updated: "1 month ago", Cloud: true},
+	}
+	// The local models.
+	local, _, _ := findCandidates(models, findSelection{Sort: "updated"})
+	// Check the order.
+	if got := namesInOrder(local); got != "charlie,alpha,bravo,foxtrot,delta,echo" {
+		// Report.
+		t.Errorf("local updated order %q", got)
+	} // end of the local check
+	// The cloud-only models.
+	cloud, _ := findCloudModels(models, findSelection{Sort: "updated"})
+	// Check the order.
+	if got := namesInOrder(cloud); got != "yankee,zeta,xray" {
+		// Report.
+		t.Errorf("cloud updated order %q", got)
+	} // end of the cloud check
+	// A saved copy made before the words existed: nothing has words, so the order is by name.
+	old := []siteModel{{Name: "b", Sizes: []string{"8b"}}, {Name: "a", Sizes: []string{"8b"}}}
+	// Order them.
+	oldOrdered, _, _ := findCandidates(old, findSelection{Sort: "updated"})
+	// Check it.
+	if got := namesInOrder(oldOrdered); got != "a,b" {
+		// Report.
+		t.Errorf("order without any words %q, want a,b", got)
+	} // end of the old copy check
+} // end of TestUpdatedOrder
+
+// TestResortViewsByUpdated checks the re-sort of models already shown, with and without the fitting ones kept first.
+func TestResortViewsByUpdated(t *testing.T) {
+	// A list: alpha is the oldest but fits; bravo and charlie do not fit, bravo is the most recent.
+	list := func() []resultView {
+		// A fresh copy each time.
+		return []resultView{
+			{Name: "alpha", Updated: "2 years ago", FitCount: 1},
+			{Name: "charlie", Updated: "1 month ago"},
+			{Name: "bravo", Updated: "1 week ago"},
+		}
+	} // end of list
+	// The names of a list, in order.
+	names := func(l []resultView) string {
+		// Collect them.
+		var out []string
+		// Each view.
+		for _, v := range l {
+			// One name.
+			out = append(out, v.Name)
+		} // end of the loop
+		// As text.
+		return strings.Join(out, ",")
+	} // end of names
+	// With fit first: the fitting model stays ahead.
+	l := list()
+	// Sort.
+	resortViews(l, "updated", true)
+	// Check.
+	if got := names(l); got != "alpha,bravo,charlie" {
+		// Report.
+		t.Errorf("updated, fit first: %q", got)
+	} // end of the check
+	// Without fit first (the cloud-only models): purely by the words.
+	l = list()
+	// Sort.
+	resortViews(l, "updated", false)
+	// Check.
+	if got := names(l); got != "bravo,charlie,alpha" {
+		// Report.
+		t.Errorf("updated, no fit: %q", got)
+	} // end of the check
+} // end of TestResortViewsByUpdated
+
+// TestFindSummaryNamesTheOrder checks that the sentence above a cut list says which models are shown, as the chosen order decides.
+func TestFindSummaryNamesTheOrder(t *testing.T) {
+	// Each order and the phrase it must produce.
+	for order, want := range map[string]string{"downloads": "the 10 most downloaded are shown", "name": "the first 10 by name are shown", "updated": "the 10 most recently updated are shown"} {
+		// Build it.
+		got := findSummary(10, 42, 0, 0, order, "2026-11-19 09:00:00 CET (UTC+01:00)")
+		// The phrase must be there.
+		if !strings.Contains(got, want) {
+			// Report.
+			t.Errorf("order %q: %q lacks %q", order, got, want)
+		} // end of the check
+	} // end of the loop
+} // end of TestFindSummaryNamesTheOrder
+
+// TestUpdatedNote checks the note under the results: only for the Updated order, silent when nothing is listed, honest when no model has words.
+func TestUpdatedNote(t *testing.T) {
+	// Another order: no note.
+	if n := updatedNote("name", []resultView{{Name: "a", Updated: "1 week ago"}}); n != "" {
+		// Report.
+		t.Errorf("name order note %q, want none", n)
+	} // end of the other-order check
+	// Nothing listed: no note.
+	if n := updatedNote("updated", nil, nil); n != "" {
+		// Report.
+		t.Errorf("empty list note %q, want none", n)
+	} // end of the empty check
+	// Words present (in the cloud list too): the usual explanation, naming the rounding and the name order.
+	n := updatedNote("updated", []resultView{{Name: "a"}}, []resultView{{Name: "b", Updated: "1 week ago"}})
+	// Check it.
+	for _, want := range []string{"update words ollama.com shows", "rounded", "name order", "comes last"} {
+		// The phrase.
+		if !strings.Contains(n, want) {
+			// Report.
+			t.Errorf("note %q lacks %q", n, want)
+		} // end of the phrase check
+	} // end of the phrase loop
+	// No model has words: the note says so.
+	if n := updatedNote("updated", []resultView{{Name: "a"}}); !strings.Contains(n, "No update words are available") {
+		// Report.
+		t.Errorf("no-words note %q", n)
+	} // end of the no-words check
+} // end of TestUpdatedNote
+
+// TestFindSearchSortsByUpdated checks the whole page: the choice exists, a search with it lists the most recently updated first, the choice is kept, the note appears, and the re-sort of kept results works.
+func TestFindSearchSortsByUpdated(t *testing.T) {
+	// The saved library list goes to a throw-away folder, never to the real data folder.
+	isolateFindData(t)
+	// Start with an empty in-memory list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// Three models: the most downloaded first in the list is the oldest update, so the two orders differ.
+	list := listEntryUpdated("aaa", "2 years ago", "tools", "8b") + listEntryUpdated("bbb", "1 week ago", "tools", "8b") + listEntryUpdated("ccc", "1 month ago", "tools", "8b")
+	// The pages.
+	fakeSite(t, map[string]string{
+		"/library":          "<html><ul>" + list + "</ul></html>",
+		"/library/aaa/tags": tagEntry("aaa:8b", "5GB", "32K"),
+		"/library/bbb/tags": tagEntry("bbb:8b", "5GB", "32K"),
+		"/library/ccc/tags": tagEntry("ccc:8b", "5GB", "32K"),
+	})
+	// The rig.
+	rig := newThemeRig(t)
+	// The starting page offers the new choice.
+	_, _, form := get(t, rig.h, http.MethodGet, "/findllm")
+	// Check it.
+	if !strings.Contains(form, `<option value="updated">Updated: new to old</option>`) || !strings.Contains(form, `<option value="downloads" selected>Most downloaded</option>`) {
+		// Report.
+		t.Error("the starting page lacks the Updated choice, or Most downloaded is not the default")
+	} // end of the choice check
+	// A search with the new order.
+	status, body := postFind(t, rig, url.Values{"token": {rig.token}, "sort": {"updated"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
+	// It must work.
+	if status != http.StatusOK {
+		// Stop.
+		t.Fatalf("status %d: %s", status, body)
+	} // end of the status check
+	// The position of a model's heading in the page.
+	at := func(page, name string) int { return strings.Index(page, ">"+name+"<span class=\"sr-only\">") }
+	// Each model must be listed.
+	if at(body, "aaa") < 0 || at(body, "bbb") < 0 || at(body, "ccc") < 0 {
+		// Stop.
+		t.Fatal("a model is missing from the results")
+	} // end of the listing check
+	// The order: bbb (1 week), ccc (1 month), aaa (2 years).
+	if !(at(body, "bbb") < at(body, "ccc") && at(body, "ccc") < at(body, "aaa")) {
+		// Report.
+		t.Error("the results are not in the order bbb, ccc, aaa")
+	} // end of the order check
+	// The choice is kept, and the note is shown.
+	if !strings.Contains(body, `<option value="updated" selected>Updated: new to old</option>`) || strings.Contains(body, `<option value="downloads" selected>`) || !strings.Contains(body, "Models are ordered by the update words ollama.com shows") {
+		// Report.
+		t.Error("the choice is not kept after the search, or the note is missing")
+	} // end of the kept check
+	// Re-sort the kept results by name: aaa, bbb, ccc, and the note goes away.
+	res := post(t, rig.h, "/findllm/resort", url.Values{"token": {rig.token}, "sort": {"name"}}, fromThisPage)
+	// Check the redirect.
+	if res.StatusCode != http.StatusSeeOther {
+		// Report.
+		t.Fatalf("resort status %d", res.StatusCode)
+	} // end of the redirect check
+	// The page again.
+	_, _, byName := get(t, rig.h, http.MethodGet, "/findllm")
+	// Check it.
+	if !(at(byName, "aaa") < at(byName, "bbb") && at(byName, "bbb") < at(byName, "ccc")) || strings.Contains(byName, "Models are ordered by the update words") {
+		// Report.
+		t.Error("the re-sort by name did not give aaa, bbb, ccc without the note")
+	} // end of the name check
+	// Re-sort the kept results by the update words again.
+	res = post(t, rig.h, "/findllm/resort", url.Values{"token": {rig.token}, "sort": {"updated"}}, fromThisPage)
+	// Check the redirect.
+	if res.StatusCode != http.StatusSeeOther {
+		// Report.
+		t.Fatalf("resort status %d", res.StatusCode)
+	} // end of the redirect check
+	// The page again.
+	_, _, again := get(t, rig.h, http.MethodGet, "/findllm")
+	// Check it.
+	if !(at(again, "bbb") < at(again, "ccc") && at(again, "ccc") < at(again, "aaa")) || !strings.Contains(again, `<option value="updated" selected>`) {
+		// Report.
+		t.Error("the re-sort by the update words did not give bbb, ccc, aaa with the choice kept")
+	} // end of the updated check
+} // end of TestFindSearchSortsByUpdated
diff --git a/sortpick_test.go b/sortpick_test.go
index d4cb0fb..fc91792 100644
--- a/sortpick_test.go
+++ b/sortpick_test.go
@@ -39,7 +39,7 @@ func TestResortViewsOrder(t *testing.T) {
 	// Most downloaded with fit first: the fitting ones by downloads (ties by name), then the rest.
 	l := list()
 	// Sort.
-	resortViews(l, false, true)
+	resortViews(l, "downloads", true)
 	// Check.
 	if got := names(l); got != "bravo,alpha,delta,charlie" {
 		// Report.
@@ -48,7 +48,7 @@ func TestResortViewsOrder(t *testing.T) {
 	// Name A to Z with fit first.
 	l = list()
 	// Sort.
-	resortViews(l, true, true)
+	resortViews(l, "name", true)
 	// Check.
 	if got := names(l); got != "alpha,bravo,delta,charlie" {
 		// Report.
@@ -57,14 +57,14 @@ func TestResortViewsOrder(t *testing.T) {
 	// Cloud models have no fit grouping: by downloads, then by name.
 	l = list()
 	// Sort.
-	resortViews(l, false, false)
+	resortViews(l, "downloads", false)
 	// Check.
 	if got := names(l); got != "charlie,bravo,alpha,delta" {
 		// Report.
 		t.Errorf("downloads, no fit: %q", got)
 	} // end of the check
 	// And by name.
-	resortViews(l, true, false)
+	resortViews(l, "name", false)
 	// Check.
 	if got := names(l); got != "alpha,bravo,charlie,delta" {
 		// Report.
diff --git a/web/findllm.html b/web/findllm.html
index 6ae1ad9..759cac2 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -93,7 +93,7 @@
 </fieldset>
 {{/* The button: the first and only thing that reads the internet. */}}
 {{/* The button, with the order of the results beside it. */}}
-<p class="findaction"><button type="submit" class="btn-solid btn-go">Find LLM</button> <label class="sortpick" for="sortby">Sort by <select class="keepselect" id="sortby" name="sort"{{if .CanResort}} data-resort="/findllm/resort"{{end}}><option value="downloads"{{if not .SortName}} selected{{end}}>Most downloaded</option><option value="name"{{if .SortName}} selected{{end}}>Name A to Z</option></select></label>{{if .Searched}} <span class="tipbox"><button type="submit" class="btn-plain" formaction="/findllm/reset" formnovalidate aria-describedby="tip-reset">Reset Find LLM search options</button><span class="tip tip-icon" role="tooltip" id="tip-reset">Forget the last search and show the starting ticks.</span></span>{{end}} <span class="tipbox backhere"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback-row"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback-row">Back to the monitor</span></span></p>
+<p class="findaction"><button type="submit" class="btn-solid btn-go">Find LLM</button> <label class="sortpick" for="sortby">Sort by <select class="keepselect" id="sortby" name="sort"{{if .CanResort}} data-resort="/findllm/resort"{{end}}><option value="downloads"{{if not (or .SortName .SortUpdated)}} selected{{end}}>Most downloaded</option><option value="name"{{if .SortName}} selected{{end}}>Name A to Z</option><option value="updated"{{if .SortUpdated}} selected{{end}}>Updated: new to old</option></select></label>{{if .Searched}} <span class="tipbox"><button type="submit" class="btn-plain" formaction="/findllm/reset" formnovalidate aria-describedby="tip-reset">Reset Find LLM search options</button><span class="tip tip-icon" role="tooltip" id="tip-reset">Forget the last search and show the starting ticks.</span></span>{{end}} <span class="tipbox backhere"><a class="backcircle" href="/" aria-label="Back to the monitor" aria-describedby="tipback-row"><svg class="ico" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M11 6l-6 6 6 6"/></svg></a><span class="tip tip-icon" role="tooltip" id="tipback-row">Back to the monitor</span></span></p>
 </form>
 {{/* The results appear only after the button was pressed. */}}
 {{if .Searched}}
@@ -105,6 +105,7 @@
 {{if .InstalledNote}}<p class="warn" role="status"><strong>&#9888;</strong> {{.InstalledNote}}</p>{{end}}
 {{/* The update ages are copied from ollama.com, which gives only words, no exact date. */}}
 {{if .AgeNote}}<p class="muted"><small>Under each model the versions are listed with the most recently updated first, then the smaller download first (installed versions stay on top). The update age is copied from ollama.com, which gives only rounded words such as "1 year ago", not an exact date; versions with the same words are ordered by size.</small></p>{{end}}
+{{if .UpdatedNote}}<p class="muted"><small>{{.UpdatedNote}}</small></p>{{end}}
 {{/* Installed versions are marked; this line explains the marks. */}}
 {{if .InstalledCount}}
 <p class="muted">Versions you already have are marked <strong>Installed</strong>, with the answer speed from your saved performance test. Nothing is tested or installed from this page. To compare tested models, use the Compare tested models button on the home page.</p>
OCC_PATCH_128_END
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
pass "all ${#AFTER[@]} changed or new files have the expected sha256"

# Only the five expected tracked files may be changed.
CHANGED="$(git diff --name-only | LC_ALL=C sort | tr '\n' ' ')"
# The expected list.
EXPECTED="findllm.go findllm_test.go findsite.go sortpick_test.go web/findllm.html "
# Anything else is a failure.
[ "$CHANGED" = "$EXPECTED" ] || fail "other files changed than expected: $CHANGED"
# Report it.
pass "only the five expected files changed, plus the new findupdated_test.go"

# The key lines must be in place.
grep -q 'Updated: new to old' web/findllm.html && grep -q 'func updatedBefore' findllm.go && grep -q 'entryUpdated' findsite.go || fail "a key line of the change is missing"
# Report it.
pass "the Updated choice, the order rule and the reader of the update words are in place"

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
echo "NEXT  test the new Sort by choice by hand (instructions follow in the chat), then commit and push."
# Show what changed in the project folder.
git status --short
