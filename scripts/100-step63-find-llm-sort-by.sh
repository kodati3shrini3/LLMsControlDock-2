#!/usr/bin/env bash
# Script 100 (Find LLM, Sort by): a new choice Sort by beside the Find LLM button, with Most downloaded (the default) and Name A to Z. Models that fit this computer stay first in both orders; the same order applies to the cloud models. The choice is kept after a search. Two new tests.
# Run it from the project folder, on the branch feature/find-llm-installed-speed (after script 99): cd ~/LLMsControlDock && bash scripts/100-step63-find-llm-sort-by.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 99), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm.go"]="bd99ffbdb89e79374a72c8deacffaddab70412d07545b4a8efc457e800636517"
BEFORE["findllm_test.go"]="0f26a856390d14224e678ba652d7ff875c590dcedb6c136c13b64c06cc841e96"
BEFORE["web/app.css"]="ffeef565330b0cacfd412468afef16f8d94af3f56191d1d478385bf7e942b4c3"
BEFORE["web/findllm.html"]="7976aaccb6efde1a199ed7a95739571e458c1708a527f0622dfafa34d87dd7d0"
AFTER["findllm.go"]="3570ba9e6e9db48978b4975b90ff43649512fc666974388b8583240c5ee53bf0"
AFTER["findllm_test.go"]="871058f40770318ce099e67a8c16b459c82f7024720e12506c90ea091f97f556"
AFTER["web/app.css"]="d0b7c9b4cc37d601a2598e3810d0a9b70abe3ff1674e825b5467b7c14bc3e05a"
AFTER["web/findllm.html"]="386596a57db902633eb0600cf176c266cebc380cd2277ea61827fca31f53b8ad"

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

# Script 99 must have been applied: the cloud heading exists.
grep -q 'class="cloudhead"' web/findllm.html || fail "script 99 must be applied first"
# Report it.
pass "script 99 (cloud heading) is applied"

# Refuse to run twice: the sort function exists when this change was applied before.
if grep -q 'func modelBefore' findllm.go; then fail "findllm.go already has modelBefore: this script was already applied"; fi
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
index a8c33d3..ef270ee 100644
--- a/findllm.go
+++ b/findllm.go
@@ -284,6 +284,8 @@ type findSelection struct {
 	Chat bool
 	// Abilities are the ticked abilities (tools, vision, audio, thinking, embedding).
 	Abilities map[string]bool
+	// Sort is how the models are ordered: "downloads" (the default, also when empty) or "name".
+	Sort string
 	// Domains are the ticked fields of use (keys of findDomains); empty means no filter.
 	Domains map[string]bool
 	// DomainAny is true when the person chose "Match ANY ticked" for the fields of use; false (the default) is "Match ALL ticked".
@@ -333,6 +335,11 @@ func parseFindForm(get func(string) string) (findSelection, []string) {
 	sel.Chat = get("ab_chat") == "on"
 	// Match ANY only when that exact choice was sent; anything else, or nothing, is the default Match ALL.
 	sel.Any = get("ab_mode") == "any"
+	// The order of the results: Name A to Z only when that exact choice was sent; anything else is the default, most downloaded.
+	if get("sort") == "name" {
+		// Name order.
+		sel.Sort = "name"
+	} // end of the sort check
 	// The same for the fields of use.
 	sel.DomainAny = get("dom_mode") == "any"
 	// Each known field of use that is ticked.
@@ -489,6 +496,24 @@ func domainMatch(sel findSelection, m siteModel) bool {
 	return hits == len(sel.Domains)
 } // end of domainMatch
 
+// modelBefore says whether model a is listed before model b: by name for the choice Name A to Z, otherwise most downloaded first, with equal counts keeping the name order so the list is stable.
+func modelBefore(sel findSelection, a, b siteModel) bool {
+	// Name A to Z.
+	if sel.Sort == "name" {
+		// By name.
+		return a.Name < b.Name
+	} // end of the name order
+	// The download counts.
+	pa, pb := pullsNumber(a.Pulls), pullsNumber(b.Pulls)
+	// The higher count first.
+	if pa != pb {
+		// Decide by count.
+		return pa > pb
+	} // end of the count check
+	// Then by name.
+	return a.Name < b.Name
+} // end of modelBefore
+
 // abilitiesMatch says whether a model with the abilities in has satisfies the ticks of "What it should do": with Match ALL (the default) every ticked item must hold, with Match ANY at least one; with nothing ticked every model passes. "Chat and writing" holds for a model that is not a search-and-similarity model.
 func abilitiesMatch(sel findSelection, has map[string]bool) bool {
 	// How many items are ticked and how many of them the model satisfies.
@@ -588,17 +613,10 @@ func findCandidates(models []siteModel, sel findSelection) (out []siteModel, noS
 		// It passed.
 		out = append(out, m)
 	} // end of the model loop
-	// Most downloaded first; equal counts keep the name order, so the list is stable.
+	// The chosen order: most downloaded first (the default) or Name A to Z.
 	sort.SliceStable(out, func(i, j int) bool {
-		// Compare the download counts.
-		pi, pj := pullsNumber(out[i].Pulls), pullsNumber(out[j].Pulls)
-		// The higher count first.
-		if pi != pj {
-			// Decide by count.
-			return pi > pj
-		} // end of the count check
-		// Then by name.
-		return out[i].Name < out[j].Name
+		// Compare as chosen.
+		return modelBefore(sel, out[i], out[j])
 	}) // end of the sort
 	// The result.
 	return out, noSize, cloud
@@ -631,17 +649,10 @@ func findCloudModels(models []siteModel, sel findSelection) (out []siteModel, sk
 			out = append(out, m)
 		} // end of the match check
 	} // end of the model loop
-	// Most downloaded first; equal counts keep the name order.
+	// The chosen order: most downloaded first (the default) or Name A to Z.
 	sort.SliceStable(out, func(i, j int) bool {
-		// Compare the download counts.
-		pi, pj := pullsNumber(out[i].Pulls), pullsNumber(out[j].Pulls)
-		// The higher count first.
-		if pi != pj {
-			// Decide by count.
-			return pi > pj
-		} // end of the count check
-		// Then by name.
-		return out[i].Name < out[j].Name
+		// Compare as chosen.
+		return modelBefore(sel, out[i], out[j])
 	}) // end of the sort
 	// The result.
 	return out, false
@@ -981,6 +992,8 @@ type findPage struct {
 	AnyMode bool
 	// Domains are the boxes of the fields of use.
 	Domains []domainTick
+	// SortName is whether Name A to Z is chosen; false means most downloaded.
+	SortName bool
 	// DomainAnyMode is whether "Match ANY ticked" is chosen for the fields of use.
 	DomainAnyMode bool
 	// Disk and Mem are the typed numbers, as text.
@@ -1059,7 +1072,7 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 	// render draws the page for a selection.
 	render := func(w http.ResponseWriter, r *http.Request, sel findSelection, fm findMachine, problems []string, searched bool, results []resultView, cloudRes []resultView, cloudMore int, total, cloud, noSize int, errText, readAt, copyNote, instNote string, status int) {
 		// The tick boxes.
-		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, AnyMode: sel.Any, DomainAnyMode: sel.DomainAny, Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, InstalledNote: instNote, CloudResults: cloudRes, CloudMore: cloudMore, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
+		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, AnyMode: sel.Any, DomainAnyMode: sel.DomainAny, SortName: sel.Sort == "name", Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, InstalledNote: instNote, CloudResults: cloudRes, CloudMore: cloudMore, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
 		// The abilities.
 		for _, k := range abilityKeys {
 			// One box.
diff --git a/findllm_test.go b/findllm_test.go
index 4b93cef..fb32626 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -1750,3 +1750,102 @@ func TestCloudHeadingAndNote(t *testing.T) {
 		} // end of the cloud ratio check
 	} // end of the theme loop
 } // end of TestCloudHeadingAndNote
+
+// TestSortOrder checks the order of the candidates: most downloaded first by default (equal counts by name), and Name A to Z when chosen, for local models and for cloud models.
+func TestSortOrder(t *testing.T) {
+	// Three local models whose download order differs from their name order, and two cloud models.
+	models := []siteModel{
+		{Name: "bravo", Pulls: "2M", Sizes: []string{"8b"}},
+		{Name: "alpha", Pulls: "900K", Sizes: []string{"8b"}},
+		{Name: "charlie", Pulls: "12M", Sizes: []string{"8b"}},
+		{Name: "zeta", Pulls: "5M", Cloud: true},
+		{Name: "echo", Pulls: "50M", Cloud: true},
+	}
+	// The names of a list, in order.
+	names := func(ms []siteModel) string {
+		// Collect them.
+		var out []string
+		// Each model.
+		for _, m := range ms {
+			// One name.
+			out = append(out, m.Name)
+		} // end of the loop
+		// As text.
+		return strings.Join(out, ",")
+	} // end of names
+	// The default: most downloaded first.
+	local, _, _ := findCandidates(models, findSelection{})
+	// Check it.
+	if got := names(local); got != "charlie,bravo,alpha" {
+		// Report.
+		t.Errorf("default local order %q, want charlie,bravo,alpha", got)
+	} // end of the default check
+	// Name A to Z.
+	local, _, _ = findCandidates(models, findSelection{Sort: "name"})
+	// Check it.
+	if got := names(local); got != "alpha,bravo,charlie" {
+		// Report.
+		t.Errorf("name local order %q, want alpha,bravo,charlie", got)
+	} // end of the name check
+	// The cloud models, default.
+	cloud, _ := findCloudModels(models, findSelection{})
+	// Check it.
+	if got := names(cloud); got != "echo,zeta" {
+		// Report.
+		t.Errorf("default cloud order %q, want echo,zeta", got)
+	} // end of the cloud default check
+	// The cloud models, by name.
+	cloud, _ = findCloudModels(models, findSelection{Sort: "name"})
+	// Check it.
+	if got := names(cloud); got != "echo,zeta" {
+		// Report.
+		t.Errorf("name cloud order %q, want echo,zeta", got)
+	} // end of the cloud name check
+	// Equal download counts keep the name order.
+	tie := []siteModel{{Name: "b", Pulls: "1M", Sizes: []string{"8b"}}, {Name: "a", Pulls: "1M", Sizes: []string{"8b"}}}
+	// The default order of the tie.
+	local, _, _ = findCandidates(tie, findSelection{})
+	// Check it.
+	if got := names(local); got != "a,b" {
+		// Report.
+		t.Errorf("tie order %q, want a,b", got)
+	} // end of the tie check
+} // end of TestSortOrder
+
+// TestFindSortChoice checks the Sort by choice beside the Find LLM button: it is there, Most downloaded is the default, a very short tooltip explains it, an unknown value counts as the default, and Name A to Z is kept after a search.
+func TestFindSortChoice(t *testing.T) {
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
+	// The choice sits in the same paragraph as the button, with Most downloaded selected.
+	for _, want := range []string{`<p class="findaction"><button type="submit" class="btn-solid">Find LLM</button>`, `name="sort"`, `<option value="downloads" selected>Most downloaded</option>`, `<option value="name">Name A to Z</option>`, `id="tip-sortby">Models that fit this computer stay first.`} {
+		// Look for it.
+		if !strings.Contains(form, want) {
+			// Report.
+			t.Errorf("the page lacks %q", want)
+		} // end of the look
+	} // end of the loop
+	// A search with Name A to Z: the choice is kept.
+	_, body := postFind(t, rig, url.Values{"token": {rig.token}, "sort": {"name"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
+	// Kept.
+	if !strings.Contains(body, `<option value="name" selected>Name A to Z</option>`) || strings.Contains(body, `<option value="downloads" selected>`) {
+		// Report.
+		t.Error("Name A to Z is not kept after the search")
+	} // end of the kept check
+	// An unknown value falls back to the default.
+	_, odd := postFind(t, rig, url.Values{"token": {rig.token}, "sort": {"nonsense"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
+	// The default is selected.
+	if !strings.Contains(odd, `<option value="downloads" selected>Most downloaded</option>`) {
+		// Report.
+		t.Error("an unknown sort value did not fall back to Most downloaded")
+	} // end of the fallback check
+} // end of TestFindSortChoice
diff --git a/web/app.css b/web/app.css
index 6aaea00..3a20dfd 100644
--- a/web/app.css
+++ b/web/app.css
@@ -2938,3 +2938,25 @@ html[data-size="medium"] svg[width="22"] {
   /* A little larger than the text around it. */
   font-size: 1.05em;
 } /* end of rule */
+
+/* The button and the order choice side by side, level with each other. */
+.findaction {
+  /* In one row. */
+  display: flex;
+  /* Level with each other. */
+  align-items: center;
+  /* Drop below the button on a narrow window. */
+  flex-wrap: wrap;
+  /* Space between the button and the choice. */
+  gap: 0.6rem 1rem;
+} /* end of rule */
+
+/* The label and the list of the order choice. */
+.sortpick {
+  /* In one row. */
+  display: inline-flex;
+  /* Level with each other. */
+  align-items: center;
+  /* Space between the words and the list. */
+  gap: 0.4rem;
+} /* end of rule */
diff --git a/web/findllm.html b/web/findllm.html
index 621f808..848872f 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -92,7 +92,8 @@
 {{end}}
 </fieldset>
 {{/* The button: the first and only thing that reads the internet. */}}
-<p><button type="submit" class="btn-solid">Find LLM</button></p>
+{{/* The button, with the order of the results beside it. */}}
+<p class="findaction"><button type="submit" class="btn-solid">Find LLM</button> <label class="sortpick" for="sortby"><span class="tipbox"><span class="help" tabindex="0" aria-describedby="tip-sortby">Sort by</span><span class="tip" role="tooltip" id="tip-sortby">Models that fit this computer stay first.</span></span> <select class="keepselect" id="sortby" name="sort"><option value="downloads"{{if not .SortName}} selected{{end}}>Most downloaded</option><option value="name"{{if .SortName}} selected{{end}}>Name A to Z</option></select></label></p>
 </form>
 {{/* The results appear only after the button was pressed. */}}
 {{if .Searched}}
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
echo "NEXT  start bin/LLMsControlDock, open Find LLM and look at the Sort by choice beside the Find LLM button (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
