#!/usr/bin/env bash
# Script 94 (Find LLM, slice 4): versions that are installed in Ollama are marked in the Find LLM results with their saved answer speed and the date of the test (tokens per second), or with "Installed, not tested yet". Installed versions are listed first, so they are never hidden among the "more versions". A line above the results explains the marks and points to the Compare tested models button on the home page (there is no second button on the Find LLM page). If Ollama cannot be read, the page says so and marks nothing. Nothing is installed or tested from this page. Also: subtle colours for the two buttons in the Installed models panel (teal magnifier on Find LLM, gold scales on Compare tested models), light and dark values at least 4.5:1, covered by the colour test. Two new tests; two existing tests were extended; web.go passes the saved results to the Find LLM handlers.
# Run it from the project folder, on the branch feature/find-llm-installed-speed (made from main after pull request #41): cd ~/LLMsControlDock && bash scripts/94-step57-find-llm-installed-speed.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by pull request #41, which contains scripts 91 to 93e), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm.go"]="d82871109e78f3a65e67b09316c8444a77cf4da785834a200e51826441865159"
BEFORE["findllm_test.go"]="bba01d9deaea0071f5f5a9ee348b6258597246a2131a01d4adb7aae4267e71ca"
BEFORE["web.go"]="305fcbb6ffd793b8311e6bcc98ece14a0b716669c8880a57f1034de655e01551"
BEFORE["control_test.go"]="b89ec860e7117d9a391b1ecd2395ec0c9aff9488526e550b96cb766d35babe69"
BEFORE["web/app.css"]="af63391bef443005975b09f9fef4e2b55c44e6c33f78386bceeb6684371904d7"
BEFORE["web/findllm.html"]="591f5413a391a06e195ab255751ea3a7793081b119db07f91b2f4e9a8fecb2fd"
BEFORE["web/index.html"]="33566ee36a94f081ec68a6e916c5f1b408cab0fcacf876da7875f6b1868975e5"
AFTER["findllm.go"]="65aa2518711dad525c1ab260d0af8031df571032e1b1cc3e47fe247ce2412f8b"
AFTER["findllm_test.go"]="b36132c86c3c8208a2a2558604f4e128f36d77767e26c5e9a9c8c9e43f28025e"
AFTER["web.go"]="fcb817500ff22def506cf40baa23ca70ea0fbeee6f2c702e217d6bafea39c76c"
AFTER["control_test.go"]="3c4095dc9f0958aecfd23314e51c77d1b0167baf4d028dfd43826c2366c89c09"
AFTER["web/app.css"]="582d1b4792d54c3cfb6f037cebbbc063b0b62b7e0a67ab514746e77f10837cc8"
AFTER["web/findllm.html"]="fa0257e9dc4100d6f4ab10abc99da4466456cbd1464e0274f48a1264be6195f9"
AFTER["web/index.html"]="f9f3b8f7245f73790d0f94a0efc4f075b78e48a874073e7439b9ff2bb0f150e2"

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

# The Find LLM work of pull request #41 must be in this tree: the jump mark of script 93e exists.
grep -q 'findllm/search#found' web/findllm.html || fail "the merged Find LLM work (pull request #41) is not in this tree; switch to a branch made from the updated main"
# Report it.
pass "the merged Find LLM work (scripts 91 to 93e) is in this tree"

# Refuse to run twice: the marker function exists when this change was applied before.
if grep -q 'installedMarker' findllm.go; then fail "findllm.go already has the installed marker: this script was already applied"; fi
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
diff --git a/control_test.go b/control_test.go
index da544ad..55f4fd1 100644
--- a/control_test.go
+++ b/control_test.go
@@ -417,7 +417,7 @@ func TestKeyAndDrawnIcons(t *testing.T) {
 		last = at
 	} // end of the loop
 	// The compare button has the bigger drawn scale.
-	if !strings.Contains(body, `<svg class="ico ico-big"`) {
+	if !strings.Contains(body, `<svg class="ico ico-big ico-compare"`) {
 		// Report it.
 		t.Errorf("the compare button has no big drawn icon")
 	} // end of the compare check
diff --git a/findllm.go b/findllm.go
index d2e0256..2159b01 100644
--- a/findllm.go
+++ b/findllm.go
@@ -450,6 +450,10 @@ type versionView struct {
 	Fits bool
 	// Reason says why it does not fit.
 	Reason string
+	// Installed is true when this exact version is installed in Ollama now.
+	Installed bool
+	// Note is the line shown for an installed version: its saved answer speed with the date of the test, or that it was not tested yet (empty when not installed).
+	Note string
 } // end of versionView
 
 // resultView is one model as the page shows it.
@@ -474,8 +478,90 @@ type resultView struct {
 	Unavailable string
 } // end of resultView
 
+// installedFirst puts the installed versions before the others and keeps the order inside each part, so an installed version is never hidden among "more versions".
+func installedFirst(vs []versionView) []versionView {
+	// The two parts.
+	var have, other []versionView
+	// Sort each version into its part.
+	for _, v := range vs {
+		// Installed ones go first.
+		if v.Installed {
+			// Keep it.
+			have = append(have, v)
+		} else {
+			// The rest.
+			other = append(other, v)
+		} // end of the part check
+	} // end of the loop
+	// Installed first.
+	return append(have, other...)
+} // end of installedFirst
+
+// installedName makes a model name comparable: Ollama writes a model without a tag as name:latest.
+func installedName(name string) string {
+	// No tag part: it is the latest one.
+	if !strings.Contains(name, ":") {
+		// Add the tag Ollama adds.
+		return name + ":latest"
+	} // end of the tag check
+	// Already complete.
+	return name
+} // end of installedName
+
+// speedNote writes the line for an installed version from the saved tests: the newest answer speed with the date, or that it was not tested yet. An embedding model has no answer speed; it says so when an embedding test is saved.
+func speedNote(store *perfStore, name string) string {
+	// No saved tests at all.
+	if store == nil {
+		// Never guess.
+		return "Installed, not tested yet"
+	} // end of the store check
+	// The chat tests, newest first.
+	for _, r := range store.forModel(name, "generate") {
+		// The newest one that measured a speed.
+		if r.AnswerSpeed > 0 {
+			// The speed and the date, with the computer's own time zone.
+			return "Installed \u00b7 " + strconv.FormatFloat(r.AnswerSpeed, 'f', 1, 64) + " tokens per second \u00b7 tested " + r.Time.Local().Format("2 Jan 2006 15:04 MST")
+		} // end of the speed check
+	} // end of the loop
+	// An embedding model is tested differently and writes no answers.
+	if emb := store.forModel(name, "embedding"); len(emb) > 0 {
+		// Say what was tested.
+		return "Installed \u00b7 embedding test saved " + emb[0].Time.Local().Format("2 Jan 2006 15:04 MST") + " (no answer speed for embedding models)"
+	} // end of the embedding check
+	// Nothing saved for this version.
+	return "Installed, not tested yet"
+} // end of speedNote
+
+// installedMarker makes the function that says, for a version name, whether it is installed and what to show; a nil list (Ollama could not be read) gives nil, so nothing is marked.
+func installedMarker(list []installedModel, store *perfStore, ok bool) func(string) (bool, string) {
+	// Ollama could not be read: mark nothing rather than guess.
+	if !ok {
+		// No marker.
+		return nil
+	} // end of the read check
+	// The installed names, in the complete form.
+	have := map[string]string{}
+	// Walk the list.
+	for _, m := range list {
+		// Keep the name as Ollama wrote it, for the saved tests.
+		have[installedName(m.Name)] = m.Name
+	} // end of the loop
+	// The marker.
+	return func(tag string) (bool, string) {
+		// The installed model of that name, if any.
+		name, found := have[installedName(tag)]
+		// Not installed.
+		if !found {
+			// No mark.
+			return false, ""
+		} // end of the found check
+		// Installed: the line from the saved tests.
+		return true, speedNote(store, name)
+	}
+} // end of installedMarker
+
 // buildResult turns a model and its versions into the view; tags is nil when the tags page could not be read, and why says what went wrong.
-func buildResult(m siteModel, tags []siteTag, why string, sel findSelection) resultView {
+func buildResult(m siteModel, tags []siteTag, why string, sel findSelection, mark func(string) (bool, string)) resultView {
 	// The basic facts.
 	r := resultView{Name: m.Name, Description: m.Description, Abilities: strings.Join(m.Abilities, ", "), Sizes: strings.Join(m.Sizes, ", "), Pulls: m.Pulls, URL: ollamaSite + "/library/" + m.Name}
 	// The tags page could not be read: say so, never guess.
@@ -491,6 +577,11 @@ func buildResult(m siteModel, tags []siteTag, why string, sel findSelection) res
 	for _, t := range tags {
 		// Its view.
 		v := versionView{Tag: t.Tag, Command: "ollama pull " + t.Tag, Size: t.SizeText, Context: t.Context, Input: t.Input}
+		// Whether this version is installed here, and what the saved tests say about it.
+		if mark != nil {
+			// Ask the marker.
+			v.Installed, v.Note = mark(t.Tag)
+		} // end of the marker check
 		// Why it does not fit, if it does not.
 		v.Reason = versionReason(t, sel)
 		// Fits when there is no reason.
@@ -506,8 +597,8 @@ func buildResult(m siteModel, tags []siteTag, why string, sel findSelection) res
 	} // end of the version loop
 	// The count that fit.
 	r.FitCount = len(fit)
-	// The versions that fit first, then the others; the order inside each is the page's order.
-	all := append(fit, nofit...)
+	// The versions that fit first, then the others; inside each group the installed ones come first, then the page's order.
+	all := append(installedFirst(fit), installedFirst(nofit)...)
 	// Cut the list.
 	if len(all) > maxFindVersions {
 		// Count the rest.
@@ -610,6 +701,10 @@ type findPage struct {
 	CopyNote string
 	// ShowCopy is true when at least one version fits, so the page carries Copy buttons and the monitor's own copy script.
 	ShowCopy bool
+	// InstalledCount is how many of the listed versions are installed here.
+	InstalledCount int
+	// InstalledNote says that the installed models could not be read, so no version is marked (empty when they could).
+	InstalledNote string
 } // end of findPage
 
 // findTick is one tick box.
@@ -627,7 +722,7 @@ type findTick struct {
 } // end of findTick
 
 // findLLMHandlers makes the two handlers of the Find LLM page: the first shows the choices, the second reads the library and shows the models; the second asks the public website, and only the address of its page leaves this computer.
-func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.HandlerFunc) {
+func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.HandlerFunc, http.HandlerFunc) {
 	// Parse the template once.
 	page := template.Must(template.New("findllm").Parse(findLLMTemplateText + tipsTemplateText))
 	// Whether Ollama runs on this computer.
@@ -640,9 +735,9 @@ func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.H
 		tips[key] = makeFindTip("tip-find-"+key, heading)
 	} // end of the bubble loop
 	// render draws the page for a selection.
-	render := func(w http.ResponseWriter, r *http.Request, sel findSelection, fm findMachine, problems []string, searched bool, results []resultView, total, cloud, noSize int, errText, readAt, copyNote string, status int) {
+	render := func(w http.ResponseWriter, r *http.Request, sel findSelection, fm findMachine, problems []string, searched bool, results []resultView, total, cloud, noSize int, errText, readAt, copyNote, instNote string, status int) {
 		// The tick boxes.
-		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
+		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, InstalledNote: instNote, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
 		// The abilities.
 		for _, k := range abilityKeys {
 			// One box.
@@ -709,6 +804,11 @@ func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.H
 		for _, res := range data.Results {
 			// Look at each version.
 			for _, v := range res.Versions {
+				// Count the installed versions.
+				if v.Installed {
+					// One more.
+					data.InstalledCount++
+				} // end of the installed count
 				// One that fits is enough.
 				if v.Fits {
 					// Show the buttons.
@@ -746,7 +846,7 @@ func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.H
 		// The starting choices: chat and writing, small and medium models, no ability or memory filter.
 		sel := findSelection{Chat: true, Abilities: map[string]bool{}, Sizes: map[string]bool{"small": true, "medium": true}, Contexts: map[string]bool{}, DiskGB: fm.DiskGB, MemGB: fm.MemGB}
 		// Draw.
-		render(w, r, sel, fm, nil, false, nil, 0, 0, 0, "", "", "", http.StatusOK)
+		render(w, r, sel, fm, nil, false, nil, 0, 0, 0, "", "", "", "", http.StatusOK)
 	} // end of show
 	// search reads the library and shows the models.
 	search := func(w http.ResponseWriter, r *http.Request) {
@@ -764,7 +864,7 @@ func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.H
 		// Typed wrongly: show the form again, read nothing.
 		if len(problems) > 0 {
 			// Draw with the problems.
-			render(w, r, sel, fm, problems, false, nil, 0, 0, 0, "", "", "", http.StatusBadRequest)
+			render(w, r, sel, fm, problems, false, nil, 0, 0, 0, "", "", "", "", http.StatusBadRequest)
 			// Stop.
 			return
 		} // end of the problem check
@@ -779,7 +879,7 @@ func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.H
 			// No usable copy: say why, show no data.
 			if cerr != nil {
 				// Draw with the reason.
-				render(w, r, sel, fm, nil, true, nil, 0, 0, 0, "The Ollama library could not be read just now: "+err.Error()+". No saved copy of the list exists yet (one is saved after each successful search), so nothing is shown rather than something that may be out of date.", "", "", http.StatusOK)
+				render(w, r, sel, fm, nil, true, nil, 0, 0, 0, "The Ollama library could not be read just now: "+err.Error()+". No saved copy of the list exists yet (one is saved after each successful search), so nothing is shown rather than something that may be out of date.", "", "", "", http.StatusOK)
 				// Stop.
 				return
 			} // end of the copy check
@@ -800,6 +900,10 @@ func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.H
 			// Keep the most downloaded.
 			shown = shown[:maxFindResults]
 		} // end of the cut
+		// What is installed here now, so installed versions can be marked; if Ollama cannot be read, nothing is marked and the page says so.
+		inst, instErr := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
+		// The marker for the versions (nil when the list could not be read).
+		mark := installedMarker(inst, store, instErr == nil)
 		// The results, filled side by side.
 		results := make([]resultView, len(shown))
 		// Wait for all of them.
@@ -819,7 +923,7 @@ func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.H
 				// A saved copy means ollama.com is not reachable: do not wait for it again for every model.
 				if copyNote != "" {
 					// Never guess: the model is listed without versions.
-					results[i] = buildResult(shown[i], nil, "ollama.com could not be reached", sel)
+					results[i] = buildResult(shown[i], nil, "ollama.com could not be reached", sel, mark)
 					// Done.
 					return
 				} // end of the copy check
@@ -828,12 +932,12 @@ func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.H
 				// A failure.
 				if terr != nil {
 					// Never guess: the model is listed without versions.
-					results[i] = buildResult(shown[i], nil, terr.Error(), sel)
+					results[i] = buildResult(shown[i], nil, terr.Error(), sel, mark)
 					// Done.
 					return
 				} // end of the failure check
 				// The model with its versions.
-				results[i] = buildResult(shown[i], tags, "", sel)
+				results[i] = buildResult(shown[i], tags, "", sel, mark)
 			}(i) // end of the goroutine
 		} // end of the model loop
 		// Wait.
@@ -843,8 +947,15 @@ func findLLMHandlers(addr ollamaAddress, token string) (http.HandlerFunc, http.H
 			// A model that fits somewhere comes first.
 			return (results[i].FitCount > 0) && (results[j].FitCount == 0)
 		}) // end of the sort
+		// When the installed models could not be read, say so, because then no version is marked (not needed for a saved copy, which shows no versions).
+		var instNote string
+		// The reading failed while versions are shown.
+		if instErr != nil && copyNote == "" {
+			// The reason, in plain words.
+			instNote = "The installed models could not be read just now (" + instErr.Error() + "), so installed versions are not marked."
+		} // end of the note check
 		// Draw the results, with the time the list was read and its zone.
-		render(w, r, sel, fm, nil, true, results, len(cands), cloud, noSize, "", at.Format("2006-01-02 15:04:05 MST (UTC-07:00)"), copyNote, http.StatusOK)
+		render(w, r, sel, fm, nil, true, results, len(cands), cloud, noSize, "", at.Format("2006-01-02 15:04:05 MST (UTC-07:00)"), copyNote, instNote, http.StatusOK)
 	} // end of search
 	// Hand back both.
 	return show, search
diff --git a/findllm_test.go b/findllm_test.go
index 11f07d8..8258e28 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -12,6 +12,8 @@ import ( // import lists the standard-library packages this test file uses.
 	"math"
 	// net/http gives the status codes.
 	"net/http"
+	// net/http/httptest starts the fake Ollama the new tests supply.
+	"net/http/httptest"
 	// net/url builds the form values.
 	"net/url"
 	// os checks and writes the saved copy.
@@ -916,7 +918,7 @@ func TestIconColours(t *testing.T) {
 	// The page with the six real models and the key open.
 	_, _, body := get(t, handlerFor(t, fullOllama(t, realModels, realPsBody).URL), http.MethodGet, "/?key=open")
 	// The classes: Modelfile and parameters buttons, the delete button, and the three key symbols.
-	for _, want := range []string{`class="gear gear-file"`, `class="gear gear-params"`, `class="gear gear-delete"`, `class="ico sym-file"`, `class="ico sym-params"`, `class="ico sym-delete"`, `class="tagicon"`} {
+	for _, want := range []string{`class="gear gear-file"`, `class="gear gear-params"`, `class="gear gear-delete"`, `class="ico sym-file"`, `class="ico sym-params"`, `class="ico sym-delete"`, `class="tagicon"`, `class="ico ico-big ico-find"`, `class="ico ico-big ico-compare"`} {
 		// Look for it.
 		if !strings.Contains(body, want) {
 			// Report.
@@ -928,7 +930,7 @@ func TestIconColours(t *testing.T) {
 	// The page and panel backgrounds: light, then dark.
 	bgs := map[string][]string{"light": {"#ffffff", "#f4f6f8"}, "dark": {"#121417", "#1b1f24"}}
 	// Each icon colour appears three times: light, dark by system choice, dark by saved choice.
-	for _, name := range []string{"icon-tag", "icon-delete", "icon-file", "icon-params"} {
+	for _, name := range []string{"icon-tag", "icon-delete", "icon-file", "icon-params", "icon-find", "icon-compare"} {
 		// Every value written for it.
 		vals := regexp.MustCompile(`--`+name+`: (#[0-9a-f]{6});`).FindAllStringSubmatch(css, -1)
 		// Three values.
@@ -998,3 +1000,165 @@ func TestFindSearchJumpsToTheAnswer(t *testing.T) {
 		t.Error("the problem page has no single jump target on the problem box")
 	} // end of the problem check
 } // end of TestFindSearchJumpsToTheAnswer
+
+// rigWithOllama builds the handler and finds its page token, like newThemeRig, but for a fake Ollama the test supplies.
+func rigWithOllama(t *testing.T, srv *httptest.Server) themeRig {
+	// Mark this as a helper.
+	t.Helper()
+	// Build the handler once, because the token belongs to one handler.
+	h := handlerFor(t, srv.URL)
+	// Fetch the home page.
+	_, _, body := get(t, h, http.MethodGet, "/")
+	// Find the hidden token field.
+	m := regexp.MustCompile(`name="token" value="([0-9a-f]{32})"`).FindStringSubmatch(body)
+	// The page must carry a token.
+	if m == nil {
+		// Stop the test.
+		t.Fatalf("no token found in the page")
+	} // end of the token check
+	// Hand back the pair.
+	return themeRig{h: h, token: m[1]}
+} // end of rigWithOllama
+
+// seedTest saves one finished performance test for a model in the data folder the test uses, before the handler is built, so the handler loads it.
+func seedTest(t *testing.T, r perfRun) {
+	// Mark this as a helper.
+	t.Helper()
+	// The same file the program uses.
+	path, _ := defaultHistoryPath()
+	// Open it.
+	store := openPerfStore(path, "")
+	// Save the run.
+	if err := store.add(r); err != nil {
+		// A failure means the test is broken.
+		t.Fatalf("could not save the test run: %v", err)
+	} // end of the save check
+} // end of seedTest
+
+// TestSpeedNoteAndMarker checks the line shown for an installed version: the newest answer speed with its date, "not tested yet", the embedding wording, :latest matching, and no mark when Ollama could not be read.
+func TestSpeedNoteAndMarker(t *testing.T) {
+	// A memory-only store.
+	store := openPerfStore("", "memory only")
+	// An old and a newer test of the same version: the newer speed must win.
+	store.add(perfRun{Time: time.Date(2026, 10, 1, 9, 0, 0, 0, time.UTC), Model: "alpha:0.6b", Kind: "generate", AnswerSpeed: 10})
+	// The newer one.
+	store.add(perfRun{Time: time.Date(2026, 11, 2, 13, 10, 0, 0, time.UTC), Model: "alpha:0.6b", Kind: "generate", AnswerSpeed: 42.34})
+	// An embedding test.
+	store.add(perfRun{Time: time.Date(2026, 11, 3, 8, 0, 0, 0, time.UTC), Model: "embedder:latest", Kind: "embedding"})
+	// The installed list: a tested one, an untested one, an embedding one and a model without a tag.
+	list := []installedModel{{Name: "alpha:0.6b"}, {Name: "alpha:8b"}, {Name: "embedder:latest"}, {Name: "plain"}}
+	// The marker.
+	mark := installedMarker(list, store, true)
+	// The tested version: speed with one decimal, and a date.
+	if ok, note := mark("alpha:0.6b"); !ok || !strings.HasPrefix(note, "Installed · 42.3 tokens per second · tested 2 Nov 2026") {
+		// Report.
+		t.Errorf("tested version: %v %q", ok, note)
+	} // end of the tested check
+	// The untested version.
+	if ok, note := mark("alpha:8b"); !ok || note != "Installed, not tested yet" {
+		// Report.
+		t.Errorf("untested version: %v %q", ok, note)
+	} // end of the untested check
+	// The embedding model.
+	if ok, note := mark("embedder:latest"); !ok || !strings.Contains(note, "embedding test saved") || !strings.Contains(note, "no answer speed") {
+		// Report.
+		t.Errorf("embedding model: %v %q", ok, note)
+	} // end of the embedding check
+	// A model installed without a tag matches the library's :latest.
+	if ok, _ := mark("plain:latest"); !ok {
+		// Report.
+		t.Error("plain was not matched with plain:latest")
+	} // end of the latest check
+	// A version that is not installed gets no mark.
+	if ok, note := mark("alpha:70b"); ok || note != "" {
+		// Report.
+		t.Errorf("not installed: %v %q", ok, note)
+	} // end of the absent check
+	// Ollama could not be read: no marker at all.
+	if installedMarker(nil, store, false) != nil {
+		// Report.
+		t.Error("a marker was made although the installed list could not be read")
+	} // end of the unread check
+	// Installed versions come first inside a group and the order is kept otherwise.
+	got := installedFirst([]versionView{{Tag: "a"}, {Tag: "b", Installed: true}, {Tag: "c"}, {Tag: "d", Installed: true}})
+	// The tags in order.
+	var order []string
+	// Collect.
+	for _, v := range got {
+		// One tag.
+		order = append(order, v.Tag)
+	} // end of the collection
+	// The expected order.
+	if strings.Join(order, "") != "bdac" {
+		// Report.
+		t.Errorf("order %v, want b d a c", order)
+	} // end of the order check
+} // end of TestSpeedNoteAndMarker
+
+// TestFindPageMarksInstalledVersions checks the page: installed versions are marked with their saved speed or "not tested yet", the explaining line is there, and a failing Ollama gives a clear note instead of silence.
+func TestFindPageMarksInstalledVersions(t *testing.T) {
+	// A throw-away data folder.
+	isolateFindData(t)
+	// An empty in-memory list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// A working fake library.
+	fakeSite(t, findTestPages())
+	// One saved test of the small version, with the current prompt, so the Compare page has a row.
+	seedTest(t, perfRun{Time: time.Date(2026, 11, 2, 13, 10, 0, 0, time.UTC), Model: "alpha:0.6b", Kind: "generate", PromptVersion: perfPromptVersion, Runs: perfTimedRuns, AnswerSpeed: 42.3})
+	// Both versions of alpha are installed.
+	srv := fullOllama(t, []realRow{
+		// The tested one.
+		{"alpha:0.6b", 523000000, "2026-10-24T17:40:34.693006337Z", []string{"completion"}, "alpha", "0.6B", "Q4_K_M", 40960, 1024, ""},
+		// The untested one.
+		{"alpha:8b", 5200000000, "2026-10-24T17:40:34.693006337Z", []string{"completion"}, "alpha", "8B", "Q4_K_M", 131072, 4096, ""},
+	}, `{"models":[]}`)
+	// The rig.
+	rig := rigWithOllama(t, srv)
+	// Search with room for both versions.
+	_, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"20"}, "mem_gb": {"32"}})
+	// The tested version shows its speed and a date with a zone.
+	if !strings.Contains(body, `<span class="installedmark">Installed &middot; 42.3 tokens per second &middot; tested 2 Nov 2026`) && !strings.Contains(body, "Installed · 42.3 tokens per second · tested 2 Nov 2026") {
+		// Report.
+		t.Error("the tested installed version does not show its speed and date")
+	} // end of the tested check
+	// The untested version says so.
+	if !strings.Contains(body, `<span class="installedmark">Installed, not tested yet</span>`) {
+		// Report.
+		t.Error("the untested installed version is not marked")
+	} // end of the untested check
+	// The explaining line is there, and it points to the home page's Compare button instead of repeating it: no Compare form on this page.
+	if !strings.Contains(body, "use the Compare tested models button on the home page") || strings.Contains(body, `action="/compare"`) {
+		// Report.
+		t.Error("the explaining line is missing, or a Compare form is on the Find LLM page")
+	} // end of the explaining line check
+	// The embedding model is not installed, so its version has no mark: exactly two marks on the page.
+	if n := strings.Count(body, `class="installedmark"`); n != 2 {
+		// Report.
+		t.Errorf("%d marks, want 2", n)
+	} // end of the count check
+	// Nothing was installed or tested by the page: no request other than reads reached the fake Ollama (it only answers /api/tags, /api/version and /api/ps).
+	// A second rig where nothing is installed: no marks and no explaining bar.
+	srv2 := fullOllama(t, nil, `{"models":[]}`)
+	// The rig.
+	rig2 := rigWithOllama(t, srv2)
+	// Search again.
+	_, body2 := postFind(t, rig2, url.Values{"token": {rig2.token}, "ab_chat": {"on"}, "disk_gb": {"20"}, "mem_gb": {"32"}})
+	// No marks and no bar.
+	if strings.Contains(body2, `class="installedmark"`) || strings.Contains(body2, "marked <strong>Installed</strong>") {
+		// Report.
+		t.Error("marks appear although nothing is installed")
+	} // end of the empty check
+	// A third rig where Ollama fails: the page says so.
+	srv3 := fakeOllama(t, replyWith(http.StatusInternalServerError, "boom"))
+	// The rig.
+	rig3 := rigWithOllama(t, srv3)
+	// Search again.
+	_, body3 := postFind(t, rig3, url.Values{"token": {rig3.token}, "ab_chat": {"on"}, "disk_gb": {"20"}, "mem_gb": {"32"}})
+	// The note, and no marks.
+	if !strings.Contains(body3, "The installed models could not be read just now") || strings.Contains(body3, `class="installedmark"`) {
+		// Report.
+		t.Error("a failing Ollama is not reported on the page")
+	} // end of the failure check
+} // end of TestFindPageMarksInstalledVersions
diff --git a/web/app.css b/web/app.css
index e64163f..fdaf229 100644
--- a/web/app.css
+++ b/web/app.css
@@ -28,6 +28,10 @@
   --icon-file: #1f5fa8;
   /* The inference parameters symbol. */
   --icon-params: #6d3fb5;
+  /* The Find LLM button's magnifier: teal. */
+  --icon-find: #0a6b73;
+  /* The Compare tested models button's scales: gold. */
+  --icon-compare: #7a5f00;
   /* Category row accent bar on the left edge (contrast 6.4:1 on the page). */
   --cat-accent: #1f5fa8;
   /* Tell the browser to draw its own controls in light colours. */
@@ -63,6 +67,8 @@
     --icon-delete: #ff8a80;
     --icon-file: #7fb2f0;
     --icon-params: #b79af0;
+    --icon-find: #4fd1c5;
+    --icon-compare: #e3c04d;
     /* Category row accent bar on the left edge (contrast 8.4:1 on the page). */
     --cat-accent: #7fb2f0;
     /* Tell the browser to draw its own controls in dark colours. */
@@ -97,6 +103,8 @@
   --icon-delete: #ff8a80;
   --icon-file: #7fb2f0;
   --icon-params: #b79af0;
+  --icon-find: #4fd1c5;
+  --icon-compare: #e3c04d;
   /* Category row accent bar on the left edge (contrast 8.4:1 on the page). */
   --cat-accent: #7fb2f0;
   /* Tell the browser to draw its own controls in dark colours. */
@@ -2710,3 +2718,9 @@ html[data-size="medium"] svg[width="22"] {
   /* Mixed with the text colour. */
   color: color-mix(in srgb, var(--icon-params) 65%, var(--text));
 } /* end of rule */
+
+/* The mark on an installed version in the Find LLM results: bold, so it stands out from the size and context text without relying on colour. */
+.installedmark {
+  /* Bolder than the text around it. */
+  font-weight: 600;
+} /* end of rule */
diff --git a/web/findllm.html b/web/findllm.html
index 3677579..13f5c38 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -69,6 +69,12 @@
 {{if .Error}}<p class="warn" role="alert"><strong>&#9888;</strong> {{.Error}}</p>{{else}}
 {{if .CopyNote}}<p class="warn" role="alert"><strong>&#9888;</strong> {{.CopyNote}}</p>{{end}}
 <p class="muted" role="status">{{.Summary}}</p>
+{{/* The installed models could not be read: say so, because then no version is marked. */}}
+{{if .InstalledNote}}<p class="warn" role="status"><strong>&#9888;</strong> {{.InstalledNote}}</p>{{end}}
+{{/* Installed versions are marked; this line explains the marks. */}}
+{{if .InstalledCount}}
+<p class="muted">Versions you already have are marked <strong>Installed</strong>, with the answer speed from your saved performance test. Nothing is tested or installed from this page. To compare tested models, use the Compare tested models button on the home page.</p>
+{{end}}
 {{/* The numbers $ri and $vi make every command on the page get its own name, so each Copy button finds its own command. */}}
 {{range $ri, $r := .Results}}
 <div class="findresult">
@@ -78,7 +84,7 @@
 {{if .Unavailable}}<p class="warn">{{.Unavailable}}. Open the official page above for its versions.</p>{{else}}
 {{if eq .FitCount 0}}<p class="warn">None of its versions fit your choices. The versions are listed below with the reason.</p>{{end}}
 <ul class="findversions">
-{{range $vi, $v := .Versions}}<li{{if not .Fits}} class="nofit"{{end}}>{{if .Fits}}<strong>Fits:</strong> <code id="cmd-{{$ri}}-{{$vi}}-local">{{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-local" hidden aria-label="Copy command: directly on the computer"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button>{{else}}<strong>Does not fit:</strong> <code>{{.Command}}</code>{{end}} &middot; {{if .Size}}{{.Size}}{{else}}size not shown{{end}}{{if .Context}} &middot; {{.Context}} context{{end}}{{if .Input}} &middot; {{.Input}}{{end}}{{if .Reason}}<br><small>{{.Reason}}</small>{{end}}
+{{range $vi, $v := .Versions}}<li{{if not .Fits}} class="nofit"{{end}}>{{if .Fits}}<strong>Fits:</strong> <code id="cmd-{{$ri}}-{{$vi}}-local">{{.Command}}</code> <button type="button" class="copybtn" data-target="cmd-{{$ri}}-{{$vi}}-local" hidden aria-label="Copy command: directly on the computer"><svg class="copyicon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false"><rect x="5" y="5" width="9" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2h-6A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><span class="copylabel">Copy</span></button>{{else}}<strong>Does not fit:</strong> <code>{{.Command}}</code>{{end}} &middot; {{if .Size}}{{.Size}}{{else}}size not shown{{end}}{{if .Context}} &middot; {{.Context}} context{{end}}{{if .Input}} &middot; {{.Input}}{{end}}{{if .Installed}} &middot; <span class="installedmark">{{.Note}}</span>{{end}}{{if .Reason}}<br><small>{{.Reason}}</small>{{end}}
 {{if .Fits}}
 {{/* The command depends on where Ollama runs; the monitor cannot know that, so Docker and Kubernetes are offered too, folded away until wanted. */}}
 <details class="othercmds"><summary>Docker or Kubernetes</summary>
diff --git a/web/index.html b/web/index.html
index e3274d4..fc2023d 100644
--- a/web/index.html
+++ b/web/index.html
@@ -303,7 +303,7 @@
 {{/* The area that opens the tip. */}}
 <span class="tipbox">
 {{/* The button: the symbol is hidden from screen readers, which read the words. */}}
-<button type="submit" class="btn-plain comparebtn" aria-describedby="tipfindllm"><svg class="ico ico-big" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg> Find LLM</button>
+<button type="submit" class="btn-plain comparebtn" aria-describedby="tipfindllm"><svg class="ico ico-big ico-find" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg> Find LLM</button>
 {{/* The tip. */}}
 <span class="tip tip-icon" role="tooltip" id="tipfindllm">Find LLM: lists only models that Ollama supports and can install; installs nothing</span>
 {{/* End of the tip area. */}}
@@ -322,7 +322,7 @@
 {{/* The area that opens the tip. */}}
 <span class="tipbox">
 {{/* The button: the symbol is hidden from screen readers, which read the words. */}}
-<button type="submit" class="btn-plain comparebtn" aria-describedby="tipcompare"><svg class="ico ico-big" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M7 21h10"/><path d="M4 7h16"/><path d="M4 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/><path d="M20 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/></svg> Compare tested models ({{.CompareCount}})</button>
+<button type="submit" class="btn-plain comparebtn" aria-describedby="tipcompare"><svg class="ico ico-big ico-compare" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M7 21h10"/><path d="M4 7h16"/><path d="M4 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/><path d="M20 7l-2.5 7a3.5 3.5 0 0 0 5 0z"/></svg> Compare tested models ({{.CompareCount}})</button>
 {{/* The tip. */}}
 <span class="tip tip-icon" role="tooltip" id="tipcompare">Compare models that have already been through a performance test</span>
 {{/* End of the tip area. */}}
diff --git a/web.go b/web.go
index 370483b..d0ad5bf 100644
--- a/web.go
+++ b/web.go
@@ -180,12 +180,6 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	}) // end of the icon route
 	// Route: a GET request for "/about" shows the read-only About page (see about.go).
 	mux.HandleFunc("GET /about", aboutHandler())
-	// Make the two Find LLM handlers: the page with the choices, and the search that reads the public library (see findllm.go).
-	findShow, findSearch := findLLMHandlers(addr, token)
-	// Route: a GET request for "/findllm" shows the choices and asks nothing from the internet.
-	mux.HandleFunc("GET /findllm", findShow)
-	// Route: a POST request for "/findllm/search" reads the library list and shows the matching models.
-	mux.HandleFunc("POST /findllm/search", findSearch)
 	// Make the two Settings handlers: the first shows the page, the second saves the form (see settingspage.go).
 	settingsShow, settingsSave := settingsHandlers(addr, mon, token)
 	// Route: a GET request for "/settings" shows the Settings page.
@@ -230,6 +224,12 @@ func newWebHandlerWith(addr ollamaAddress, timeout time.Duration, mon *monitor)
 	// Open the saved results.
 	// One history store, shared by the performance pages and the comparison page.
 	perfHistory := openPerfStore(histPath, histNote)
+	// Make the two Find LLM handlers: the page with the choices, and the search that reads the public library (see findllm.go); the search marks installed versions with their saved speed, so it gets the saved results.
+	findShow, findSearch := findLLMHandlers(addr, token, perfHistory)
+	// Route: a GET request for "/findllm" shows the choices and asks nothing from the internet.
+	mux.HandleFunc("GET /findllm", findShow)
+	// Route: a POST request for "/findllm/search" reads the library list and shows the matching models.
+	mux.HandleFunc("POST /findllm/search", findSearch)
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
echo "NEXT  start bin/LLMsControlDock and press Find LLM and look for the Installed marks and the two coloured icons (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
