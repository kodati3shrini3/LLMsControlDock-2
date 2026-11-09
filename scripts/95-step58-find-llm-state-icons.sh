#!/usr/bin/env bash
# Script 95 (Find LLM, three state icons): every model and every version in the Find LLM results shows a symbol with a tooltip. A cloud-only model shows the cloud symbol (blue) and is listed in its own section, Cloud models, below the local models, with no download command; a model or version that can be installed here with your free disk space, memory and choices shows the check mark (green); one that cannot be installed shows the cross (red), with the reason written under the version as before. The words Fits and Does not fit stay beside the symbols, so the meaning never depends on a symbol or a colour alone. The model heading shows the check mark when at least one version fits, the cross when none does. When a size or memory class is ticked, the cloud section is left out and the summary says why. Two new tests; two existing tests were updated.
# Run it from the project folder, on the branch feature/find-llm-installed-speed (the same branch as script 94, after script 94): cd ~/LLMsControlDock && bash scripts/95-step58-find-llm-state-icons.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 94b), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm.go"]="d837d2eb4ffbb22cd0ec236f03c9e822b9ffeee0aab6684228ae49728db8fe51"
BEFORE["findllm_test.go"]="feb4730470de35ad28ebee803146a64f12ad6f1e5d7602964b3473ea98fcd157"
BEFORE["web/app.css"]="582d1b4792d54c3cfb6f037cebbbc063b0b62b7e0a67ab514746e77f10837cc8"
BEFORE["web/findllm.html"]="fa0257e9dc4100d6f4ab10abc99da4466456cbd1464e0274f48a1264be6195f9"
AFTER["findllm.go"]="224f95382730348f1b377a0f2a8ab0c5cf357993eaa9ae6eaaf7f5707ce5893c"
AFTER["findllm_test.go"]="a81b005c3a4a615b6a2ceccbb4102262c6b14670793a715f4498a83153044974"
AFTER["web/app.css"]="39b1b9c2131040e2e9198198c1cbed00bfe0ae80cb8d8ce92e02a7669b75b837"
AFTER["web/findllm.html"]="0090ec62ecd5cf078e55a168037e8e4068a9160731bfa6919bdbbfb4f81e599b"

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

# Script 94b must have been applied: the cloud-version check exists.
grep -q 'isCloudTag' findllm.go || fail "script 94b must be applied first"
# Report it.
pass "script 94b (models with local and cloud versions) is applied"

# Refuse to run twice: the icon tooltip text exists when this change was applied before.
if grep -q 'tipVersionFits' findllm.go; then fail "findllm.go already has the state icons: this script was already applied"; fi
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
index 27dd3f7..3e8d75a 100644
--- a/findllm.go
+++ b/findllm.go
@@ -41,6 +41,67 @@ const maxFindResults = 10
 // maxFindVersions is how many versions are listed under one model; the rest are counted.
 const maxFindVersions = 6
 
+// maxFindCloud is how many cloud-only models are shown in the cloud section; the rest are counted.
+const maxFindCloud = 10
+
+// The texts of the state icons' tooltips. Each is one short line, at most 130 characters, with no markup characters.
+const (
+	// tipCloud is for a cloud model.
+	tipCloud = "Cloud model: runs on Ollama's servers, not on this computer, and may need an Ollama account. Nothing is downloaded here."
+	// tipModelFits is for a model with at least one version that fits.
+	tipModelFits = "At least one version of this model can be installed here with your choices."
+	// tipModelNoFit is for a model with no version that fits.
+	tipModelNoFit = "No version of this model can be installed here with your choices; the reasons are written under each version."
+	// tipVersionFits is for a version that fits.
+	tipVersionFits = "This version can be installed here: it fits your free disk space, memory and choices."
+	// tipVersionNoFit is for a version that does not fit.
+	tipVersionNoFit = "This version cannot be installed here with your choices; the reason is written under it."
+)
+
+// iconView is a state icon with its tooltip: Kind is fits, nofit or cloud (empty means no icon), Label is the hidden name for screen readers, ID names the tooltip, Text is the tooltip.
+type iconView struct {
+	// Kind picks the drawing and the colour.
+	Kind string
+	// Label is read by screen readers.
+	Label string
+	// ID links the icon to its tooltip.
+	ID string
+	// Text is the tooltip.
+	Text string
+} // end of iconView
+
+// modelIcon makes the icon of a model from its state: fits, nofit, cloud, or empty for none.
+func modelIcon(state, id string) iconView {
+	// By state.
+	switch state {
+	// At least one version fits.
+	case "fits":
+		// The check mark.
+		return iconView{Kind: "fits", Label: "Can be installed", ID: id, Text: tipModelFits}
+	// No version fits.
+	case "nofit":
+		// The cross.
+		return iconView{Kind: "nofit", Label: "Cannot be installed", ID: id, Text: tipModelNoFit}
+	// A cloud model.
+	case "cloud":
+		// The cloud.
+		return iconView{Kind: "cloud", Label: "Cloud model", ID: id, Text: tipCloud}
+	} // end of the state switch
+	// Unknown: no icon, never a guess.
+	return iconView{}
+} // end of modelIcon
+
+// versionIcon makes the icon of one version: the check mark when it fits, the cross when it does not.
+func versionIcon(fits bool, id string) iconView {
+	// Fits.
+	if fits {
+		// The check mark.
+		return iconView{Kind: "fits", Label: "Can be installed", ID: id, Text: tipVersionFits}
+	} // end of the fit check
+	// Does not fit.
+	return iconView{Kind: "nofit", Label: "Cannot be installed", ID: id, Text: tipVersionNoFit}
+} // end of versionIcon
+
 // findParallel is how many tags pages are read at the same time.
 const findParallel = 5
 
@@ -395,6 +456,70 @@ func findCandidates(models []siteModel, sel findSelection) (out []siteModel, noS
 	return out, noSize, cloud
 } // end of findCandidates
 
+// findCloudModels returns the cloud-only models that match the ticked abilities, most downloaded first, for the cloud section; skipped is true when a size or memory class is ticked, because those classes describe this computer and do not apply to a model that runs on Ollama's servers (its size is not listed either).
+func findCloudModels(models []siteModel, sel findSelection) (out []siteModel, skipped bool) {
+	// A class describes what runs on this computer: leave the cloud models out of such a search.
+	if len(sel.Sizes) > 0 || len(sel.Contexts) > 0 {
+		// Say that they were left out.
+		return nil, true
+	} // end of the class check
+	// Look at every model.
+	for _, m := range models {
+		// Only cloud-only models: the cloud label and no local size.
+		if !m.Cloud || len(m.Sizes) > 0 {
+			// Next.
+			continue
+		} // end of the cloud-only check
+		// The model's abilities as a set.
+		has := map[string]bool{}
+		// Fill it.
+		for _, a := range m.Abilities {
+			// One ability.
+			has[a] = true
+		} // end of the fill
+		// Chat and writing: not a search-and-similarity model.
+		if sel.Chat && has["embedding"] {
+			// Skip.
+			continue
+		} // end of the chat check
+		// Every ticked ability must be present.
+		ok := true
+		// Check each.
+		for a := range sel.Abilities {
+			// Missing one.
+			if !has[a] {
+				// Not this model.
+				ok = false
+			} // end of the check
+		} // end of the ability loop
+		// Keep the match.
+		if ok {
+			// Add it.
+			out = append(out, m)
+		} // end of the match check
+	} // end of the model loop
+	// Most downloaded first; equal counts keep the name order.
+	sort.SliceStable(out, func(i, j int) bool {
+		// Compare the download counts.
+		pi, pj := pullsNumber(out[i].Pulls), pullsNumber(out[j].Pulls)
+		// The higher count first.
+		if pi != pj {
+			// Decide by count.
+			return pi > pj
+		} // end of the count check
+		// Then by name.
+		return out[i].Name < out[j].Name
+	}) // end of the sort
+	// The result.
+	return out, false
+} // end of findCloudModels
+
+// cloudView makes the view of a cloud-only model: no versions are read for it, because nothing is downloaded.
+func cloudView(m siteModel) resultView {
+	// The basic facts, with the cloud state.
+	return resultView{Name: m.Name, Description: m.Description, Abilities: strings.Join(m.Abilities, ", "), Pulls: m.Pulls, URL: ollamaSite + "/library/" + m.Name, State: "cloud"}
+} // end of cloudView
+
 // versionReason says why a version does not fit this computer; empty text means it fits.
 func versionReason(t siteTag, sel findSelection) string {
 	// The size in gigabytes (decimal), when the page showed one.
@@ -454,6 +579,8 @@ type versionView struct {
 	Installed bool
 	// Note is the line shown for an installed version: its saved answer speed with the date of the test, or that it was not tested yet (empty when not installed).
 	Note string
+	// Icon is the can-be-installed or cannot-be-installed symbol with its tooltip.
+	Icon iconView
 } // end of versionView
 
 // resultView is one model as the page shows it.
@@ -476,6 +603,10 @@ type resultView struct {
 	FitCount int
 	// Unavailable says the tags page could not be read (empty when it was).
 	Unavailable string
+	// State is fits (at least one version fits), nofit (none does), cloud (runs on Ollama's servers) or empty (not known).
+	State string
+	// Icon is the symbol of the state with its tooltip.
+	Icon iconView
 } // end of resultView
 
 // isCloudTag says whether a version name is a cloud version: Ollama names them name:cloud or name:size-cloud.
@@ -617,11 +748,20 @@ func buildResult(m siteModel, tags []siteTag, why string, sel findSelection, mar
 	if len(fit)+len(nofit) == 0 {
 		// Say so; the template adds the pointer to the official page.
 		r.Unavailable = "all its versions run on Ollama's servers (cloud), not on this computer"
+		// It is a cloud model after all.
+		r.State = "cloud"
 		// Done.
 		return r
 	} // end of the empty check
 	// The count that fit.
 	r.FitCount = len(fit)
+	// The state of the model: at least one version fits, or none does.
+	r.State = "nofit"
+	// At least one fits.
+	if r.FitCount > 0 {
+		// The check mark state.
+		r.State = "fits"
+	} // end of the state choice
 	// The versions that fit first, then the others; inside each group the installed ones come first, then the page's order.
 	all := append(installedFirst(fit), installedFirst(nofit)...)
 	// Cut the list.
@@ -726,6 +866,10 @@ type findPage struct {
 	CopyNote string
 	// ShowCopy is true when at least one version fits, so the page carries Copy buttons and the monitor's own copy script.
 	ShowCopy bool
+	// CloudResults are the cloud-only models shown in their own section.
+	CloudResults []resultView
+	// CloudMore counts the cloud-only models that match but are not shown.
+	CloudMore int
 	// InstalledCount is how many of the listed versions are installed here.
 	InstalledCount int
 	// InstalledNote says that the installed models could not be read, so no version is marked (empty when they could).
@@ -760,9 +904,9 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 		tips[key] = makeFindTip("tip-find-"+key, heading)
 	} // end of the bubble loop
 	// render draws the page for a selection.
-	render := func(w http.ResponseWriter, r *http.Request, sel findSelection, fm findMachine, problems []string, searched bool, results []resultView, total, cloud, noSize int, errText, readAt, copyNote, instNote string, status int) {
+	render := func(w http.ResponseWriter, r *http.Request, sel findSelection, fm findMachine, problems []string, searched bool, results []resultView, cloudRes []resultView, cloudMore int, total, cloud, noSize int, errText, readAt, copyNote, instNote string, status int) {
 		// The tick boxes.
-		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, InstalledNote: instNote, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
+		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, InstalledNote: instNote, CloudResults: cloudRes, CloudMore: cloudMore, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
 		// The abilities.
 		for _, k := range abilityKeys {
 			// One box.
@@ -825,6 +969,21 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 			// Say so.
 			data.GPU = "Not found by the graphics tool; models would run on the processor"
 		} // end of the graphics note
+		// The state icons, each with its own tooltip name, so no two tooltips share a name.
+		for ri := range data.Results {
+			// The model's icon.
+			data.Results[ri].Icon = modelIcon(data.Results[ri].State, fmt.Sprintf("tipstate-%d", ri))
+			// Each version's icon.
+			for vi := range data.Results[ri].Versions {
+				// One version.
+				data.Results[ri].Versions[vi].Icon = versionIcon(data.Results[ri].Versions[vi].Fits, fmt.Sprintf("tipver-%d-%d", ri, vi))
+			} // end of the version loop
+		} // end of the model loop
+		// The cloud section's icons.
+		for ci := range data.CloudResults {
+			// One cloud model.
+			data.CloudResults[ci].Icon = modelIcon("cloud", fmt.Sprintf("tipcloud-%d", ci))
+		} // end of the cloud loop
 		// Copy buttons are offered only next to versions that fit.
 		for _, res := range data.Results {
 			// Look at each version.
@@ -871,7 +1030,7 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 		// The starting choices: chat and writing, small and medium models, no ability or memory filter.
 		sel := findSelection{Chat: true, Abilities: map[string]bool{}, Sizes: map[string]bool{"small": true, "medium": true}, Contexts: map[string]bool{}, DiskGB: fm.DiskGB, MemGB: fm.MemGB}
 		// Draw.
-		render(w, r, sel, fm, nil, false, nil, 0, 0, 0, "", "", "", "", http.StatusOK)
+		render(w, r, sel, fm, nil, false, nil, nil, 0, 0, 0, 0, "", "", "", "", http.StatusOK)
 	} // end of show
 	// search reads the library and shows the models.
 	search := func(w http.ResponseWriter, r *http.Request) {
@@ -889,7 +1048,7 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 		// Typed wrongly: show the form again, read nothing.
 		if len(problems) > 0 {
 			// Draw with the problems.
-			render(w, r, sel, fm, problems, false, nil, 0, 0, 0, "", "", "", "", http.StatusBadRequest)
+			render(w, r, sel, fm, problems, false, nil, nil, 0, 0, 0, 0, "", "", "", "", http.StatusBadRequest)
 			// Stop.
 			return
 		} // end of the problem check
@@ -904,7 +1063,7 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 			// No usable copy: say why, show no data.
 			if cerr != nil {
 				// Draw with the reason.
-				render(w, r, sel, fm, nil, true, nil, 0, 0, 0, "The Ollama library could not be read just now: "+err.Error()+". No saved copy of the list exists yet (one is saved after each successful search), so nothing is shown rather than something that may be out of date.", "", "", "", http.StatusOK)
+				render(w, r, sel, fm, nil, true, nil, nil, 0, 0, 0, 0, "The Ollama library could not be read just now: "+err.Error()+". No saved copy of the list exists yet (one is saved after each successful search), so nothing is shown rather than something that may be out of date.", "", "", "", http.StatusOK)
 				// Stop.
 				return
 			} // end of the copy check
@@ -979,8 +1138,31 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 			// The reason, in plain words.
 			instNote = "The installed models could not be read just now (" + instErr.Error() + "), so installed versions are not marked."
 		} // end of the note check
+		// The cloud-only models get their own section: no versions are read for them, because nothing is downloaded.
+		cloudModels, cloudSkipped := findCloudModels(models, sel)
+		// How many are shown and how many are only counted.
+		var cloudRes []resultView
+		// The most downloaded ones.
+		for i, m := range cloudModels {
+			// Stop at the limit.
+			if i >= maxFindCloud {
+				// The rest are counted.
+				break
+			} // end of the limit check
+			// One more.
+			cloudRes = append(cloudRes, cloudView(m))
+		} // end of the cloud loop
+		// The ones not shown.
+		cloudMore := len(cloudModels) - len(cloudRes)
+		// Cloud-only models count as "left out" only when a size or memory class was ticked, which does not apply to them; otherwise they are shown below.
+		cloudLeft := 0
+		// A class was ticked.
+		if cloudSkipped {
+			// Say how many were left out.
+			cloudLeft = cloud
+		} // end of the class check
 		// Draw the results, with the time the list was read and its zone.
-		render(w, r, sel, fm, nil, true, results, len(cands), cloud, noSize, "", at.Format("2006-01-02 15:04:05 MST (UTC-07:00)"), copyNote, instNote, http.StatusOK)
+		render(w, r, sel, fm, nil, true, results, cloudRes, cloudMore, len(cands), cloudLeft, noSize, "", at.Format("2006-01-02 15:04:05 MST (UTC-07:00)"), copyNote, instNote, http.StatusOK)
 	} // end of search
 	// Hand back both.
 	return show, search
@@ -1020,11 +1202,11 @@ func findLeftOut(cloud, noSize int) string {
 	// One.
 	case cloud == 1:
 		// Singular.
-		s += " 1 cloud model (it runs on Ollama's servers, not on this computer) is left out."
+		s += " 1 cloud model (it runs on Ollama's servers, not on this computer) is not shown because you chose a size or a memory class, which does not apply to it."
 	// Several.
 	case cloud > 1:
 		// Plural.
-		s += fmt.Sprintf(" %d cloud models (they run on Ollama's servers, not on this computer) are left out.", cloud)
+		s += fmt.Sprintf(" %d cloud models (they run on Ollama's servers, not on this computer) are not shown because you chose a size or a memory class, which does not apply to them.", cloud)
 	} // end of the cloud switch
 	// Models without a readable size.
 	switch {
diff --git a/findllm_test.go b/findllm_test.go
index ea1697c..d744686 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -424,18 +424,23 @@ func TestFindSearchShowsFitAndNoFit(t *testing.T) {
 		t.Fatalf("status %d: %s", status, body)
 	} // end of the status check
 	// The model, its official link, the small version that fits with its command, and the large one with the reason.
-	for _, want := range []string{`<h2 id="found">Models found</h2>`, ollamaSite + "/library/alpha", "ollama pull alpha:0.6b", "<strong>Fits:</strong>", "<strong>Does not fit:</strong>", "needs 5.2 GB of disk space; you have 2.0 GB free", "1 model matches your choices", "1 cloud model (it runs on Ollama"} {
-		// Look for it.
-		if !strings.Contains(body, want) {
+	for _, want := range []string{`<h2 id="found">Models found</h2>`, ollamaSite + "/library/alpha", "ollama pull alpha:0.6b", "<strong>Fits:</strong>", "<strong>Does not fit:</strong>", "needs 5.2 GB of disk space; you have 2.0 GB free", "1 model matches your choices", `<h2 id="cloudmodels">Cloud models</h2>`, tipCloud, tipVersionFits, tipVersionNoFit, tipModelFits} {
+		// Look for it in the page text with the character codes turned back into characters (the apostrophe is written as a code).
+		if !strings.Contains(html.UnescapeString(body), want) {
 			// Report.
 			t.Errorf("the results lack %q", want)
 		} // end of the look
 	} // end of the loop
-	// The cloud model and the embedding model are not listed.
-	if strings.Contains(body, ">cloudy<") || strings.Contains(body, ">embedder<") {
+	// The embedding model is not listed at all.
+	if strings.Contains(body, ">embedder<") {
 		// Report.
-		t.Error("a cloud or embedding model was listed")
-	} // end of the absence check
+		t.Error("the embedding model was listed")
+	} // end of the embedding check
+	// The cloud-only model is listed, but only in the cloud section (after its heading), and has no download command.
+	if at, cloudAt := strings.Index(body, ">cloudy"), strings.Index(body, `<h2 id="cloudmodels">`); at < 0 || cloudAt < 0 || at < cloudAt || strings.Contains(body, "ollama pull cloudy") {
+		// Report.
+		t.Error("the cloud-only model is missing from the cloud section, or has a download command")
+	} // end of the cloud check
 	// One list page and one tags page were read.
 	if n := atomic.LoadInt32(hits); n != 2 {
 		// Report.
@@ -930,7 +935,7 @@ func TestIconColours(t *testing.T) {
 	// The page and panel backgrounds: light, then dark.
 	bgs := map[string][]string{"light": {"#ffffff", "#f4f6f8"}, "dark": {"#121417", "#1b1f24"}}
 	// Each icon colour appears three times: light, dark by system choice, dark by saved choice.
-	for _, name := range []string{"icon-tag", "icon-delete", "icon-file", "icon-params", "icon-find", "icon-compare"} {
+	for _, name := range []string{"icon-tag", "icon-delete", "icon-file", "icon-params", "icon-find", "icon-compare", "icon-cloud"} {
 		// Every value written for it.
 		vals := regexp.MustCompile(`--`+name+`: (#[0-9a-f]{6});`).FindAllStringSubmatch(css, -1)
 		// Three values.
@@ -1202,3 +1207,79 @@ func TestHybridCloudModelStays(t *testing.T) {
 		t.Errorf("all-cloud result: versions %d, unavailable %q", len(r2.Versions), r2.Unavailable)
 	} // end of the all-cloud check
 } // end of TestHybridCloudModelStays
+
+// TestStateIconTexts checks the house rules for the state icons' tooltips: one short line of at most 130 characters, no markup characters, and different texts for the different states.
+func TestStateIconTexts(t *testing.T) {
+	// The five texts.
+	texts := []string{tipCloud, tipModelFits, tipModelNoFit, tipVersionFits, tipVersionNoFit}
+	// The texts seen so far, to catch two equal ones.
+	seen := map[string]bool{}
+	// Check each.
+	for _, tx := range texts {
+		// Not longer than 130 characters.
+		if n := len([]rune(tx)); n > 130 {
+			// Report.
+			t.Errorf("%q has %d characters, want at most 130", tx, n)
+		} // end of the length check
+		// No markup characters.
+		if strings.ContainsAny(tx, "<>&\"*_`#") {
+			// Report.
+			t.Errorf("%q has a markup character", tx)
+		} // end of the markup check
+		// Different from the others.
+		if seen[tx] {
+			// Report.
+			t.Errorf("%q is used twice", tx)
+		} // end of the twice check
+		// Remember it.
+		seen[tx] = true
+	} // end of the loop
+} // end of TestStateIconTexts
+
+// TestStateIconsOnThePage checks the three icons on the results page: the cloud symbol on a cloud-only model, the check mark on a model and a version that can be installed, and the cross on a version and a model that cannot; every icon has its tooltip and a hidden name, and a size class removes the cloud section with an explanation.
+func TestStateIconsOnThePage(t *testing.T) {
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
+	// Room for the small version only.
+	_, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"2"}, "mem_gb": {"8"}})
+	// The page text with the character codes turned back.
+	text := html.UnescapeString(body)
+	// The model has a version that fits: check mark on the heading and on the small version, cross on the big one.
+	for _, want := range []string{`state-fits" tabindex="0" role="img" aria-label="Can be installed" aria-describedby="tipstate-0"`, `aria-describedby="tipver-0-0"`, `state-nofit" tabindex="0" role="img" aria-label="Cannot be installed" aria-describedby="tipver-0-1"`, `state-cloud" tabindex="0" role="img" aria-label="Cloud model" aria-describedby="tipcloud-0"`} {
+		// Look for it.
+		if !strings.Contains(text, want) {
+			// Report.
+			t.Errorf("the page lacks %q", want)
+		} // end of the look
+	} // end of the loop
+	// Every icon points at a tooltip that exists, and no tooltip name is used twice.
+	for _, id := range []string{"tipstate-0", "tipver-0-0", "tipver-0-1", "tipcloud-0"} {
+		// One tooltip with this name.
+		if n := strings.Count(body, `id="`+id+`" role="tooltip"`) + strings.Count(body, `role="tooltip" id="`+id+`"`); n != 1 {
+			// Report.
+			t.Errorf("%d tooltips named %s, want 1", n, id)
+		} // end of the name check
+	} // end of the loop
+	// With almost no room nothing fits: the model gets the cross.
+	_, none := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"0.1"}, "mem_gb": {"0.1"}})
+	// The model's own icon is the cross.
+	if !strings.Contains(none, `state-nofit" tabindex="0" role="img" aria-label="Cannot be installed" aria-describedby="tipstate-0"`) {
+		// Report.
+		t.Error("a model with no version that fits has no cross")
+	} // end of the cross check
+	// A size class does not apply to cloud models: the section is gone and the summary says why.
+	_, sized := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "sz_small": {"on"}, "disk_gb": {"2"}, "mem_gb": {"8"}})
+	// No cloud section, and the reason.
+	if strings.Contains(sized, `id="cloudmodels"`) || !strings.Contains(html.UnescapeString(sized), "not shown because you chose a size or a memory class") {
+		// Report.
+		t.Error("a size class should remove the cloud section and say why")
+	} // end of the class check
+} // end of TestStateIconsOnThePage
diff --git a/web/app.css b/web/app.css
index fdaf229..7f33c13 100644
--- a/web/app.css
+++ b/web/app.css
@@ -32,6 +32,8 @@
   --icon-find: #0a6b73;
   /* The Compare tested models button's scales: gold. */
   --icon-compare: #7a5f00;
+  /* The cloud symbol in the Find LLM results: blue. */
+  --icon-cloud: #1565a8;
   /* Category row accent bar on the left edge (contrast 6.4:1 on the page). */
   --cat-accent: #1f5fa8;
   /* Tell the browser to draw its own controls in light colours. */
@@ -69,6 +71,7 @@
     --icon-params: #b79af0;
     --icon-find: #4fd1c5;
     --icon-compare: #e3c04d;
+    --icon-cloud: #86c5f2;
     /* Category row accent bar on the left edge (contrast 8.4:1 on the page). */
     --cat-accent: #7fb2f0;
     /* Tell the browser to draw its own controls in dark colours. */
@@ -105,6 +108,7 @@
   --icon-params: #b79af0;
   --icon-find: #4fd1c5;
   --icon-compare: #e3c04d;
+  --icon-cloud: #86c5f2;
   /* Category row accent bar on the left edge (contrast 8.4:1 on the page). */
   --cat-accent: #7fb2f0;
   /* Tell the browser to draw its own controls in dark colours. */
@@ -1116,7 +1120,7 @@ button.btn-plain {
 } /* end of rule */
 
 /* Every icon box is its own anchor: the name is private to each box, so a bubble finds only its own icon. */
-.gearform .tipbox, .comparebar .tipbox, .controls .tipbox, .lookstack .tipbox, .detailsbar .tipbox, .backtop, .brandwho .tipbox {
+.gearform .tipbox, .findresult .tipbox, .comparebar .tipbox, .controls .tipbox, .lookstack .tipbox, .detailsbar .tipbox, .backtop, .brandwho .tipbox {
   /* The name the bubble uses to find this box. */
   anchor-name: --tipicon;
   /* Keep the name inside this box, so the boxes of other rows never get mixed up. */
@@ -2724,3 +2728,43 @@ html[data-size="medium"] svg[width="22"] {
   /* Bolder than the text around it. */
   font-weight: 600;
 } /* end of rule */
+
+/* The state icons in the Find LLM results: a small symbol beside the model name or the version, with a tooltip. */
+.stateicon {
+  /* A box in the line, so it sits level with the words. */
+  display: inline-flex;
+  /* Centre the symbol in the box. */
+  align-items: center;
+  /* Level with the letters. */
+  vertical-align: -3px;
+  /* A hand with a question mark would suggest a button; the symbol is only information. */
+  cursor: help;
+} /* end of rule */
+
+/* Can be installed: the good colour. */
+.state-fits {
+  /* The same green as the other good signs. */
+  color: var(--ok);
+} /* end of rule */
+
+/* Cannot be installed: the problem colour. */
+.state-nofit {
+  /* The same red as the other problem signs. */
+  color: var(--bad);
+} /* end of rule */
+
+/* A cloud model: soft blue. */
+.state-cloud {
+  /* The cloud colour. */
+  color: var(--icon-cloud);
+} /* end of rule */
+
+/* A clear ring for keyboard users. */
+.stateicon:focus-visible {
+  /* A ring around the symbol. */
+  outline: 3px solid var(--text);
+  /* A gap between symbol and ring. */
+  outline-offset: 2px;
+  /* Rounded like the other rings. */
+  border-radius: 0.3rem;
+} /* end of rule */
diff --git a/web/findllm.html b/web/findllm.html
index 13f5c38..48a4423 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -78,13 +78,13 @@
 {{/* The numbers $ri and $vi make every command on the page get its own name, so each Copy button finds its own command. */}}
 {{range $ri, $r := .Results}}
 <div class="findresult">
-<h3><a href="{{.URL}}" target="_blank" rel="noopener noreferrer">{{.Name}}<span class="sr-only"> (opens in a new window)</span></a></h3>
+<h3><a href="{{.URL}}" target="_blank" rel="noopener noreferrer">{{.Name}}<span class="sr-only"> (opens in a new window)</span></a> {{template "stateicon" .Icon}}</h3>
 <p>{{.Description}}</p>
 <p class="muted"><small>Abilities: {{if .Abilities}}{{.Abilities}}{{else}}none listed{{end}} &middot; Sizes: {{if .Sizes}}{{.Sizes}}{{else}}none listed{{end}} &middot; Downloads: {{.Pulls}}</small></p>
 {{if .Unavailable}}<p class="warn">{{.Unavailable}}. Open the official page above for its versions.</p>{{else}}
 {{if eq .FitCount 0}}<p class="warn">None of its versions fit your choices. The versions are listed below with the reason.</p>{{end}}
 <ul class="findversions">
-{{range $vi, $v := .Versions}}<li{{if not .Fits}} class="nofit"{{end}}>{{if .Fits}}<strong>Fits:</strong> <code id="cmd-{{$ri}}-{{$vi}}-local">{{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-local" hidden aria-label="Copy command: directly on the computer"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button>{{else}}<strong>Does not fit:</strong> <code>{{.Command}}</code>{{end}} &middot; {{if .Size}}{{.Size}}{{else}}size not shown{{end}}{{if .Context}} &middot; {{.Context}} context{{end}}{{if .Input}} &middot; {{.Input}}{{end}}{{if .Installed}} &middot; <span class="installedmark">{{.Note}}</span>{{end}}{{if .Reason}}<br><small>{{.Reason}}</small>{{end}}
+{{range $vi, $v := .Versions}}<li{{if not .Fits}} class="nofit"{{end}}>{{template "stateicon" .Icon}} {{if .Fits}}<strong>Fits:</strong> <code id="cmd-{{$ri}}-{{$vi}}-local">{{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-local" hidden aria-label="Copy command: directly on the computer"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button>{{else}}<strong>Does not fit:</strong> <code>{{.Command}}</code>{{end}} &middot; {{if .Size}}{{.Size}}{{else}}size not shown{{end}}{{if .Context}} &middot; {{.Context}} context{{end}}{{if .Input}} &middot; {{.Input}}{{end}}{{if .Installed}} &middot; <span class="installedmark">{{.Note}}</span>{{end}}{{if .Reason}}<br><small>{{.Reason}}</small>{{end}}
 {{if .Fits}}
 {{/* The command depends on where Ollama runs; the monitor cannot know that, so Docker and Kubernetes are offered too, folded away until wanted. */}}
 <details class="othercmds"><summary>Docker or Kubernetes</summary>
@@ -101,6 +101,19 @@
 {{end}}
 </div>
 {{end}}
+{{/* The cloud-only models: no versions are read and nothing is downloaded, so there is no fit check, only the cloud symbol with its tooltip. */}}
+{{if .CloudResults}}
+<h2 id="cloudmodels">Cloud models</h2>
+<p class="muted">These models run on Ollama's servers, not on this computer, so your free disk space and memory do not apply to them. Nothing is downloaded. They may need an Ollama account.</p>
+{{range .CloudResults}}
+<div class="findresult">
+<h3><a href="{{.URL}}" target="_blank" rel="noopener noreferrer">{{.Name}}<span class="sr-only"> (opens in a new window)</span></a> {{template "stateicon" .Icon}}</h3>
+<p>{{.Description}}</p>
+<p class="muted"><small>Abilities: {{if .Abilities}}{{.Abilities}}{{else}}none listed{{end}} &middot; Downloads: {{.Pulls}}</small></p>
+</div>
+{{end}}
+{{if .CloudMore}}<p class="muted"><small>{{.CloudMore}} more cloud models match; they are on the official library page.</small></p>{{end}}
+{{end}}
 {{end}}
 {{end}}
 {{if .ShowCopy}}
@@ -113,3 +126,5 @@
 {{if .ShowCopy}}<script src="/copy.js" defer></script>{{end}}
 </body>
 </html>
+{{/* A state icon with its tooltip: the check mark (can be installed), the cross (cannot be installed) or the cloud (runs on Ollama's servers). The words next to it say the same, so the symbol is never the only signal. */}}
+{{define "stateicon"}}{{if .Kind}}<span class="tipbox"><span class="stateicon state-{{.Kind}}" tabindex="0" role="img" aria-label="{{.Label}}" aria-describedby="{{.ID}}"><svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{{if eq .Kind "fits"}}<circle cx="12" cy="12" r="9"/><path d="M8 12.5l2.7 2.7L16 9.5"/>{{else if eq .Kind "nofit"}}<circle cx="12" cy="12" r="9"/><path d="M9 9l6 6"/><path d="M15 9l-6 6"/>{{else}}<path d="M7 18h10a4 4 0 0 0 .6-7.95A5.5 5.5 0 0 0 7.1 9.2 4.4 4.4 0 0 0 7 18z"/>{{end}}</svg></span><span class="tip tip-icon" role="tooltip" id="{{.ID}}">{{.Text}}</span></span>{{end}}{{end}}
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
echo "NEXT  start bin/LLMsControlDock and press Find LLM and look at the check mark, cross and cloud symbols (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
