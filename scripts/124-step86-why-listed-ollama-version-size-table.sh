#!/usr/bin/env bash
# Script 124 (three result features on Find LLM): (1) every model shows a line "Matched your choices: ..." naming the ticks, fields of use, sizes and the typed disk and memory that made it qualify; (2) when the model's own page on ollama.com says "requires Ollama X or later" (the wording of the Clef page), the result says which Ollama version is needed and compares it with the running Ollama: older gives a warning with "How to update Ollama" (Windows or macOS, Linux install script, Docker), newer gives a calm note, unreadable gives a note that nothing can be compared; one more page is read per listed model, and when it cannot be read nothing is said; (3) a folded "Compare sizes" table per model lists the plain size versions (8b, 70b, 8x7b ...) smallest download first, with context and whether each fits this computer. Seven new tests. Program change, version 0.34.0 (work on the same branch as 122 and 123).
# Run it on the branch of scripts 122 and 123 (never main): cd ~/LLMsControlDock-2 && git switch feature/docker-it-flag && bash scripts/124-step86-why-listed-ollama-version-size-table.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of the five files BEFORE the change (as after script 123) and AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm.go"]="5d434b1ee4f0642f188538562e6ab749e3c8c5ef7eaec3516a0da9baccbbbdda"
BEFORE["findllm_test.go"]="e3343bc8f775d5ca4bb3fe4ed6c772e4694478f8d2ecc70e2dd97b1efd338788"
BEFORE["findsite.go"]="4fdac429efc680d353921fa1cb8f550378fb712f983b94c4ec553f58b0fd2f78"
BEFORE["web/findllm.html"]="d16800af454b559edf9f04c4650715950ca3976085af7b49edd687d1fbb74b3a"
BEFORE["findlabels_test.go"]="56321fabedfb1546215f390f42c7caeff355ed5d31bbf541af8605be97741c86"
AFTER["findllm.go"]="9db951a39fc073f5d933143af0722b709e2fc08819479e0efb1cdb8dfa57962d"
AFTER["findllm_test.go"]="f86bebe0a17bb30dd402c489a753de0787058dff42b7de672ae59e013aff933e"
AFTER["findsite.go"]="c27211e06889c512f6812eca0153745925c94049487af3dde7fee414aa2c5387"
AFTER["web/findllm.html"]="d831bedc552200f464b078847ba1b680fd8f436a083e8e25cf82af4eb9cbc8a3"
AFTER["findlabels_test.go"]="0990db1e496eb830333857f35f0cdc3824e48b5df44bf1aee314679f24e904d5"

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
[ "$BRANCH" != "main" ] || fail "you are on main; switch to the branch of scripts 122 and 123: git switch feature/docker-it-flag"
# Report the branch.
pass "on branch $BRANCH (not main)"

# Scripts 122 and 123 must be in.
grep -q 'docker exec -it' web/findllm.html && grep -q 'func unknownLabelNote' findsite.go && [ -e findlabels_test.go ] || fail "scripts 122 and 123 are not both in this branch; run them first"
# Report it.
pass "scripts 122 and 123 are in"

# Refuse to run twice.
if grep -q 'func qualifyReasons' findllm.go; then fail "findllm.go already has qualifyReasons: this script was already applied"; fi
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
cat > "$PATCH_FILE" <<'OCC_PATCH_124_END'
diff --git a/findlabels_test.go b/findlabels_test.go
index 81685da..60e5a59 100644
--- a/findlabels_test.go
+++ b/findlabels_test.go
@@ -301,3 +301,188 @@ func TestFindSearchHandlesDecisionMixturesAndUnknownLabels(t *testing.T) {
 		t.Error("the fake library was never asked")
 	} // end of the hits check
 } // end of TestFindSearchHandlesDecisionMixturesAndUnknownLabels
+
+// TestOllamaNeededReadsTheSentence checks the reader of the sentence "requires Ollama X or later" on a model page.
+func TestOllamaNeededReadsTheSentence(t *testing.T) {
+	// The cases: page text, expected version, whether a version is expected.
+	for _, c := range []struct {
+		// name describes the case.
+		name string
+		// text is the visible text of the page.
+		text string
+		// want is the expected version.
+		want string
+		// ok is whether a version is expected at all.
+		ok bool
+	}{
+		// The wording of the real Clef page: the first sentence counts, the cloud sentence does not.
+		{"clef", "Clef requires Ollama 0.35.1 or later. To use Clef in Ollama's cloud, use Ollama 0.40.6 or later.", "0.35.1", true},
+		// A leading v and the word newer.
+		{"v and newer", "This model requires Ollama v0.12.3 or newer to run.", "0.12.3", true},
+		// Two numbers become three.
+		{"two numbers", "It requires Ollama 0.35 or later.", "0.35.0", true},
+		// The Python library is not Ollama.
+		{"python library", "Use the Ollama Python library, version 0.6.3 or later:", "", false},
+		// A page that says nothing.
+		{"nothing", "nimble:latest 9.3GB 256K context window", "", false},
+	} {
+		// Read it.
+		got, ok := ollamaNeeded(c.text)
+		// Compare.
+		if got != c.want || ok != c.ok {
+			// Report.
+			t.Errorf("%s: got %q, %v; want %q, %v", c.name, got, ok, c.want, c.ok)
+		} // end of the compare
+	} // end of the case loop
+} // end of TestOllamaNeededReadsTheSentence
+
+// TestApplyOllamaNeed checks the three judgements: older, new enough, and not readable.
+func TestApplyOllamaNeed(t *testing.T) {
+	// Older: a warning state with the running version in the sentence.
+	var r resultView
+	// Judge it.
+	applyOllamaNeed(&r, "0.35.1", checkResult{Online: true, Version: "0.34.4"})
+	// Check.
+	if r.OllamaState != "old" || !strings.Contains(r.OllamaNote, "Needs Ollama 0.35.1 or newer") || !strings.Contains(r.OllamaNote, "Your Ollama is 0.34.4") {
+		// Report.
+		t.Errorf("old: %q %q", r.OllamaState, r.OllamaNote)
+	} // end of the old check
+	// New enough (a larger minor number is higher: 0.100.0 is newer than 0.35.1).
+	r = resultView{}
+	// Judge it.
+	applyOllamaNeed(&r, "0.35.1", checkResult{Online: true, Version: "0.100.0"})
+	// Check.
+	if r.OllamaState != "ok" || !strings.Contains(r.OllamaNote, "is new enough") {
+		// Report.
+		t.Errorf("ok: %q %q", r.OllamaState, r.OllamaNote)
+	} // end of the ok check
+	// Ollama not reachable: nothing can be compared, and the sentence says so.
+	r = resultView{}
+	// Judge it.
+	applyOllamaNeed(&r, "0.35.1", checkResult{})
+	// Check.
+	if r.OllamaState != "unknown" || !strings.Contains(r.OllamaNote, "could not read the version") {
+		// Report.
+		t.Errorf("unknown: %q %q", r.OllamaState, r.OllamaNote)
+	} // end of the unknown check
+} // end of TestApplyOllamaNeed
+
+// TestSizeRowsCompareThePlainSizes checks the size table: plain size tags only, latest dropped when it is another row, smallest download first, and no table for fewer than two rows.
+func TestSizeRowsCompareThePlainSizes(t *testing.T) {
+	// The versions of an invented model, in the page's order.
+	vs := []versionView{
+		{Tag: "m:latest", sizeBytes: 4_900_000_000, Size: "4.9GB"},
+		{Tag: "m:405b", sizeBytes: 243_000_000_000, Size: "243GB"},
+		{Tag: "m:8b", sizeBytes: 4_900_000_000, Size: "4.9GB"},
+		{Tag: "m:70b", sizeBytes: 43_000_000_000, Size: "43GB"},
+		{Tag: "m:8b-instruct-q2_K", sizeBytes: 3_200_000_000, Size: "3.2GB"},
+	}
+	// Build the rows.
+	rows := sizeRows(vs)
+	// The tags in order.
+	var tags []string
+	// Collect them.
+	for _, v := range rows {
+		// One tag.
+		tags = append(tags, v.Tag)
+	} // end of the loop
+	// Smallest first, latest and the quantized version left out.
+	if !reflect.DeepEqual(tags, []string{"m:8b", "m:70b", "m:405b"}) {
+		// Report.
+		t.Errorf("rows = %v", tags)
+	} // end of the check
+	// One plain size is not a comparison.
+	if got := sizeRows([]versionView{{Tag: "m:latest", sizeBytes: 1}, {Tag: "m:q4", sizeBytes: 2}}); got != nil {
+		// Report.
+		t.Errorf("a single row gave a table: %v", got)
+	} // end of the single check
+	// A latest that is the only version of its size stays, so two sizes still compare.
+	if got := sizeRows([]versionView{{Tag: "m:latest", sizeBytes: 1}, {Tag: "m:8b", sizeBytes: 2}}); len(got) != 2 {
+		// Report.
+		t.Errorf("latest of its own size was dropped: %v", got)
+	} // end of the latest check
+} // end of TestSizeRowsCompareThePlainSizes
+
+// TestQualifyReasonsNamesTheChoicesMatched checks the "Matched your choices" list.
+func TestQualifyReasonsNamesTheChoicesMatched(t *testing.T) {
+	// A model with tools and two sizes, and a code name.
+	m := siteModel{Name: "starcoder-x", Description: "A code generation model.", Abilities: []string{"tools"}, Sizes: []string{"3b", "15b"}}
+	// Chat, tools, the code field, the medium size class.
+	sel := findSelection{Chat: true, Abilities: map[string]bool{"tools": true, "vision": true}, Domains: map[string]bool{"code": true}, Sizes: map[string]bool{"medium": true}, Contexts: map[string]bool{}}
+	// The reasons.
+	got := qualifyReasons(m, sel)
+	// Vision is ticked but the model lacks it, so it is not listed; with the Medium class ticked neither 3b (small) nor 15b (large) counts.
+	want := []string{"Chat and writing", "Uses tools", "Field of use: Code and software"}
+	// Compare.
+	if !reflect.DeepEqual(got, want) {
+		// Report.
+		t.Errorf("reasons = %v, want %v", got, want)
+	} // end of the compare
+	// Tick the small class too: 3b qualifies.
+	sel.Sizes = map[string]bool{"small": true}
+	// The reasons again.
+	got = qualifyReasons(m, sel)
+	// The size line is there.
+	if got[len(got)-1] != "Size 3b (Small)" {
+		// Report.
+		t.Errorf("reasons = %v", got)
+	} // end of the size check
+	// Nothing ticked: nothing to say.
+	if got := qualifyReasons(m, findSelection{}); len(got) != 0 {
+		// Report.
+		t.Errorf("reasons without choices = %v", got)
+	} // end of the empty check
+} // end of TestQualifyReasonsNamesTheChoicesMatched
+
+// TestFindSearchShowsReasonsVersionFlagAndSizeTable runs a whole search against a fake library: the "Matched your choices" line, the warning for a model that needs a newer Ollama than the fake one (0.34.4) with the update help, the calm note for one that does not, and the size table.
+func TestFindSearchShowsReasonsVersionFlagAndSizeTable(t *testing.T) {
+	// The saved library list goes to a throw-away folder, never to the real data folder.
+	isolateFindData(t)
+	// Start with an empty saved list.
+	theListCache = listCache{}
+	// Clear it again at the end.
+	t.Cleanup(func() { theListCache = listCache{} })
+	// Two models with tools and two sizes each.
+	list := listEntry("newer", "Needs a newer Ollama.", "tools", "1b", "8b") + listEntry("older", "Runs on an older Ollama.", "tools", "1b", "8b")
+	// The pages: the model pages carry the sentence in some markup.
+	fakeSite(t, map[string]string{
+		"/library":            "<html><ul>" + list + "</ul></html>",
+		"/library/newer":      "<html><body><div><p>Newer <b>requires</b> Ollama 9.9.9 or later.</p></div></body></html>",
+		"/library/older":      "<html><body><p>Older requires Ollama 0.30.0 or later.</p></body></html>",
+		"/library/newer/tags": tagEntry("newer:1b", "700MB", "8K") + tagEntry("newer:8b", "5GB", "32K") + tagEntry("newer:latest", "5GB", "32K"),
+		"/library/older/tags": tagEntry("older:1b", "700MB", "8K") + tagEntry("older:8b", "5GB", "32K"),
+	})
+	// The rig (its fake Ollama reports version 0.34.4).
+	rig := newThemeRig(t)
+	// Tools ticked, plenty of disk and memory.
+	status, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_tools": {"on"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
+	// It must work.
+	if status != http.StatusOK {
+		// Report.
+		t.Fatalf("status %d: %s", status, body)
+	} // end of the status check
+	// The page text with the character codes turned back into characters.
+	text := html.UnescapeString(body)
+	// Each expected piece of the page.
+	for _, want := range []string{
+		// The reasons.
+		"Matched your choices:</strong> Uses tools", "A version fits 100.0 GB free disk and 64.0 GB memory",
+		// The warning for the model that needs a newer Ollama, with the update help.
+		"Needs Ollama 9.9.9 or newer", "Your Ollama is 0.34.4", "How to update Ollama", "docker pull ollama/ollama",
+		// The calm note for the other model.
+		"Needs Ollama 0.30.0 or newer (the model page says so); yours (0.34.4) is new enough.",
+		// The size table, with the rows in size order.
+		"Compare sizes (2 versions)",
+	} {
+		// Look for it.
+		if !strings.Contains(text, want) {
+			// Report.
+			t.Errorf("the results lack %q", want)
+		} // end of the look
+	} // end of the loop
+	// The update help is shown once: only the model that needs a newer Ollama has it.
+	if n := strings.Count(text, "How to update Ollama"); n != 1 {
+		// Report.
+		t.Errorf("the update help appears %d times, want 1", n)
+	} // end of the count check
+} // end of TestFindSearchShowsReasonsVersionFlagAndSizeTable
diff --git a/findllm.go b/findllm.go
index 2ee743e..c94bbb2 100644
--- a/findllm.go
+++ b/findllm.go
@@ -773,6 +773,16 @@ type resultView struct {
 	State string
 	// Icon is the symbol of the state with its tooltip.
 	Icon iconView
+	// Because lists the choices of the person that this model matched (empty when nothing was ticked).
+	Because []string
+	// SizeRows compare the plain size versions of the model by download size, smallest first (empty when there are fewer than two).
+	SizeRows []versionView
+	// NeedsOllama is the Ollama version the model page says the model needs (empty when the page says nothing).
+	NeedsOllama string
+	// OllamaState is old (the running Ollama is older), ok (new enough) or unknown (the running version could not be read); empty when NeedsOllama is empty.
+	OllamaState string
+	// OllamaNote is the sentence shown for it.
+	OllamaNote string
 } // end of resultView
 
 // isCloudTag says whether a version name is a cloud version: Ollama names them name:cloud or name:size-cloud.
@@ -908,10 +918,179 @@ func installedMarker(list []installedModel, store *perfStore, ok bool) func(stri
 	}
 } // end of installedMarker
 
+// classLabelOf returns the plain word of the size class with the given key.
+func classLabelOf(key string) string {
+	// Look it up.
+	for _, c := range paramClasses {
+		// The same key.
+		if c.Key == key {
+			// Its word.
+			return c.Label
+		} // end of the key check
+	} // end of the loop
+	// Not found: the key itself.
+	return key
+} // end of classLabelOf
+
+// qualifyReasons lists, in plain words, the choices of the person that this model matched, so the results say why a model is listed.
+func qualifyReasons(m siteModel, sel findSelection) []string {
+	// The abilities of the model, by label.
+	has := map[string]bool{}
+	// Fill it.
+	for _, a := range m.Abilities {
+		// One ability.
+		has[a] = true
+	} // end of the ability loop
+	// The reasons.
+	var out []string
+	// Chat and writing: the model is neither an embedding nor a decision model.
+	if sel.Chat && !has["embedding"] && !has["decision"] {
+		// The reason.
+		out = append(out, "Chat and writing")
+	} // end of the chat check
+	// The ticked abilities the model has, in the order of the page.
+	for _, k := range abilityKeys {
+		// Ticked and present.
+		if sel.Abilities[k] && has[k] {
+			// The plain word.
+			out = append(out, findAbilityLabels[k])
+		} // end of the ability check
+	} // end of the ability loop
+	// The ticked fields of use the model belongs to (a guess from its name and description).
+	fields := modelDomains(m)
+	// In the order of the page.
+	for _, d := range findDomains {
+		// Ticked and matched.
+		if sel.Domains[d.Key] && fields[d.Key] {
+			// The reason.
+			out = append(out, "Field of use: "+d.Label)
+		} // end of the field check
+	} // end of the field loop
+	// The sizes of the model that are in a ticked class.
+	for _, s := range m.Sizes {
+		// Readable and in a ticked class.
+		if b, ok := paramsBillions(s); ok && sel.Sizes[paramClassOf(b)] {
+			// For example: Size 8b (Medium).
+			out = append(out, "Size "+s+" ("+classLabelOf(paramClassOf(b))+")")
+		} // end of the size check
+	} // end of the size loop
+	// The memory-of-a-conversation classes apply to the versions, so the reason is general.
+	if len(sel.Contexts) > 0 {
+		// The reason.
+		out = append(out, "Memory of a conversation: only versions in your ticked classes fit")
+	} // end of the context check
+	// The reasons.
+	return out
+} // end of qualifyReasons
+
+// sizeRows compares the plain size versions of a model (tags such as 8b, 70b or 8x7b, and latest when it is a size of its own) by download size, smallest first; it returns nothing when there are fewer than two rows, because one row compares nothing.
+func sizeRows(all []versionView) []versionView {
+	// The rows.
+	var rows []versionView
+	// Look at every version.
+	for _, v := range all {
+		// The part after the colon.
+		part := strings.ToLower(v.Tag)
+		// Cut at the colon.
+		if i := strings.LastIndex(part, ":"); i >= 0 {
+			// The tag part.
+			part = part[i+1:]
+		} // end of the cut
+		// Only plain size tags and latest.
+		if part == "latest" || sizeLabel.MatchString(part) {
+			// Keep it.
+			rows = append(rows, v)
+		} // end of the tag check
+	} // end of the loop
+	// Latest is dropped when another row has exactly the same download size (it is that row).
+	var kept []versionView
+	// Check each row.
+	for _, v := range rows {
+		// Is this latest, and does another row have its size?
+		dup := false
+		// Only latest can be dropped.
+		if strings.HasSuffix(strings.ToLower(v.Tag), ":latest") && v.sizeBytes > 0 {
+			// Look for another row of the same size.
+			for _, o := range rows {
+				// A different tag with the same size.
+				if o.Tag != v.Tag && o.sizeBytes == v.sizeBytes {
+					// It is a duplicate.
+					dup = true
+				} // end of the same-size check
+			} // end of the other-row loop
+		} // end of the latest check
+		// Keep the others.
+		if !dup {
+			// Keep it.
+			kept = append(kept, v)
+		} // end of the keep check
+	} // end of the loop
+	// One row compares nothing.
+	if len(kept) < 2 {
+		// No table.
+		return nil
+	} // end of the count check
+	// Smallest first; rows without a size come last; equal sizes keep the tag order.
+	sort.SliceStable(kept, func(i, j int) bool {
+		// A row without a size goes last.
+		if (kept[i].sizeBytes == 0) != (kept[j].sizeBytes == 0) {
+			// The one with a size first.
+			return kept[i].sizeBytes != 0
+		} // end of the unknown-size check
+		// Smaller first.
+		if kept[i].sizeBytes != kept[j].sizeBytes {
+			// By size.
+			return kept[i].sizeBytes < kept[j].sizeBytes
+		} // end of the size check
+		// Then by tag.
+		return kept[i].Tag < kept[j].Tag
+	}) // end of the sort
+	// A long table keeps the six smallest and the six largest.
+	if len(kept) > 12 {
+		// Join the two ends.
+		kept = append(append([]versionView{}, kept[:6]...), kept[len(kept)-6:]...)
+	} // end of the cut
+	// The rows.
+	return kept
+} // end of sizeRows
+
+// applyOllamaNeed records on a result which Ollama version the model page says the model needs, and whether the running Ollama is new enough; run is the answer of the version check.
+func applyOllamaNeed(r *resultView, need string, run checkResult) {
+	// Keep the version.
+	r.NeedsOllama = need
+	// The version that is running, when it could be read.
+	cur, curOK := parseOllamaVersion(run.Version)
+	// The version needed (read before, so it is valid).
+	req, _ := parseOllamaVersion(need)
+	// Judge.
+	switch {
+	// The running version could not be read: say what is needed and that nothing can be compared.
+	case !run.Online || !curOK:
+		// Unknown.
+		r.OllamaState = "unknown"
+		// The sentence.
+		r.OllamaNote = "Needs Ollama " + need + " or newer (the model page on ollama.com says so). This monitor could not read the version of your Ollama, so it cannot say whether yours is new enough."
+	// Older than needed: pulling fails with "requires a newer version of Ollama".
+	case compareVersions(cur, req) < 0:
+		// Old.
+		r.OllamaState = "old"
+		// The sentence.
+		r.OllamaNote = "Needs Ollama " + need + " or newer (the model page on ollama.com says so). Your Ollama is " + run.Version + ", so downloading it would fail with \"requires a newer version of Ollama\". Update Ollama first."
+	// New enough.
+	default:
+		// Fine.
+		r.OllamaState = "ok"
+		// The sentence.
+		r.OllamaNote = "Needs Ollama " + need + " or newer (the model page says so); yours (" + run.Version + ") is new enough."
+	} // end of the judgement
+} // end of applyOllamaNeed
+
 // buildResult turns a model and its versions into the view; tags is nil when the tags page could not be read, and why says what went wrong.
 func buildResult(m siteModel, tags []siteTag, why string, sel findSelection, mark func(string) (bool, string)) resultView {
 	// The basic facts.
 	r := resultView{Name: m.Name, Description: m.Description, Abilities: strings.Join(m.Abilities, ", "), Sizes: strings.Join(m.Sizes, ", "), Pulls: m.Pulls, URL: ollamaSite + "/library/" + m.Name}
+	// Which choices of the person this model matched.
+	r.Because = qualifyReasons(m, sel)
 	// The tags page could not be read: say so, never guess.
 	if tags == nil {
 		// The reason.
@@ -970,6 +1149,25 @@ func buildResult(m siteModel, tags []siteTag, why string, sel findSelection, mar
 	sortVersions(fit)
 	// The same for the others.
 	sortVersions(nofit)
+	// The size comparison uses every plain size version, not only the ones listed below.
+	r.SizeRows = sizeRows(append(append([]versionView{}, fit...), nofit...))
+	// A model with a fitting version also matched the typed disk space and memory.
+	if r.FitCount > 0 && (sel.DiskGB >= 0 || sel.MemGB >= 0) {
+		// The figures that were used.
+		var figs []string
+		// The disk.
+		if sel.DiskGB >= 0 {
+			// For example: 3419.9 GB free disk.
+			figs = append(figs, findGBText(sel.DiskGB)+" free disk")
+		} // end of the disk check
+		// The memory.
+		if sel.MemGB >= 0 {
+			// For example: 130.7 GB memory.
+			figs = append(figs, findGBText(sel.MemGB)+" memory")
+		} // end of the memory check
+		// The reason.
+		r.Because = append(r.Because, "A version fits "+strings.Join(figs, " and "))
+	} // end of the disk and memory reason
 	// The versions that fit first, then the others; inside each group the installed ones come first, then the order above.
 	all := append(installedFirst(fit), installedFirst(nofit)...)
 	// Cut the list.
@@ -1367,6 +1565,8 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 		inst, instErr := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
 		// The marker for the versions (nil when the list could not be read).
 		mark := installedMarker(inst, store, instErr == nil)
+		// The version of the Ollama that is running, to judge the models that need a newer one.
+		runVer := checkOllama(r.Context(), addr.URL, defaultCheckTimeout)
 		// The results, filled side by side.
 		results := make([]resultView, len(shown))
 		// Wait for all of them.
@@ -1401,6 +1601,14 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 				} // end of the failure check
 				// The model with its versions.
 				results[i] = buildResult(shown[i], tags, "", sel, mark)
+				// The model's own page may say which Ollama version it needs; when the page cannot be read, nothing is said about it.
+				if txt, perr := fetchSiteModelText(r.Context(), shown[i].Name); perr == nil {
+					// A sentence of the kind "requires Ollama 0.35.1 or later".
+					if need, ok := ollamaNeeded(txt); ok {
+						// Record it and judge it against the running version.
+						applyOllamaNeed(&results[i], need, runVer)
+					} // end of the sentence check
+				} // end of the page check
 			}(i) // end of the goroutine
 		} // end of the model loop
 		// Wait.
diff --git a/findllm_test.go b/findllm_test.go
index 367e791..0c61886 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -443,10 +443,10 @@ func TestFindSearchShowsFitAndNoFit(t *testing.T) {
 		// Report.
 		t.Error("the cloud-only model is missing from the cloud section, or has a download command")
 	} // end of the cloud check
-	// One list page and one tags page were read.
-	if n := atomic.LoadInt32(hits); n != 2 {
+	// One list page, one tags page and one model page (for a sentence about the Ollama version it needs) were read.
+	if n := atomic.LoadInt32(hits); n != 3 {
 		// Report.
-		t.Errorf("%d requests, want 2", n)
+		t.Errorf("%d requests, want 3", n)
 	} // end of the count check
 	// The reading time carries a zone.
 	if !strings.Contains(body, "UTC") {
diff --git a/findsite.go b/findsite.go
index bbc6a79..622ef7e 100644
--- a/findsite.go
+++ b/findsite.go
@@ -409,6 +409,52 @@ func fetchSiteTags(ctx context.Context, model string) ([]siteTag, error) {
 	return parseSiteTags(page)
 } // end of fetchSiteTags
 
+// fetchSiteModelText reads the main page of one library model and returns its visible text (tags removed, entities turned into characters, blanks collapsed), so a sentence can be found whatever markup surrounds it.
+func fetchSiteModelText(ctx context.Context, model string) (string, error) {
+	// Only plain names are asked for.
+	if !namePart.MatchString(model) {
+		// Never build an address from it.
+		return "", errors.New("not a plain model name")
+	} // end of the name check
+	// Read the page.
+	page, err := fetchSitePage(ctx, "/library/"+model)
+	// A failure.
+	if err != nil {
+		// Report it.
+		return "", err
+	} // end of the fetch check
+	// Remove the tags, turn the entities back into characters and collapse the blanks.
+	return strings.Join(strings.Fields(html.UnescapeString(htmlTag.ReplaceAllString(page, " "))), " "), nil
+} // end of fetchSiteModelText
+
+// needsOllama finds the sentence a model page writes when the model needs a newer Ollama, for example "Clef requires Ollama 0.35.1 or later."; only the first sentence with "requires Ollama" counts, so a sentence about the cloud version ("use Ollama 0.40.6 or later") is not mixed in.
+var needsOllama = regexp.MustCompile(`(?i)\brequires\s+Ollama\s+v?([0-9]+\.[0-9]+(?:\.[0-9]+)?)\s+or\s+(?:later|newer|above|higher)`)
+
+// ollamaNeeded returns the Ollama version the page text says the model needs, written as three numbers (0.35 becomes 0.35.0); false means the page says nothing of the kind.
+func ollamaNeeded(pageText string) (string, bool) {
+	// The first sentence of the kind.
+	m := needsOllama.FindStringSubmatch(pageText)
+	// None.
+	if m == nil {
+		// Nothing to report.
+		return "", false
+	} // end of the match check
+	// The version as written.
+	v := m[1]
+	// Two numbers become three.
+	if strings.Count(v, ".") == 1 {
+		// Add the patch number.
+		v += ".0"
+	} // end of the two-number case
+	// It must read as a version (the same reader the System check uses).
+	if _, ok := parseOllamaVersion(v); !ok {
+		// Not usable.
+		return "", false
+	} // end of the version check
+	// The version.
+	return v, true
+} // end of ollamaNeeded
+
 // listCache keeps the last answer of the list page for a while.
 type listCache struct {
 	// mu keeps two pages from changing it at the same time.
diff --git a/web/findllm.html b/web/findllm.html
index 10bd747..242d71a 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -115,6 +115,16 @@
 <h3><a href="{{.URL}}" target="_blank" rel="noopener noreferrer">{{.Name}}<span class="sr-only"> (opens in a new window)</span></a> {{template "stateicon" .Icon}}</h3>
 <p>{{.Description}}</p>
 <p class="muted"><small>Abilities: {{if .Abilities}}{{.Abilities}}{{else}}none listed{{end}} &middot; Sizes: {{if .Sizes}}{{.Sizes}}{{else}}none listed{{end}} &middot; Downloads: {{.Pulls}}</small></p>
+{{/* Which of the person's choices this model matched. */}}
+{{if .Because}}<p class="muted"><small><strong>Matched your choices:</strong> {{range $bi, $b := .Because}}{{if $bi}} &middot; {{end}}{{$b}}{{end}}</small></p>{{end}}
+{{/* The Ollama version the model page says the model needs, judged against the running Ollama. */}}
+{{if .OllamaNote}}<p class="{{if eq .OllamaState "old"}}warn{{else}}muted{{end}}" role="status">{{if eq .OllamaState "old"}}<strong>&#9888;</strong> {{end}}{{.OllamaNote}}</p>
+{{if eq .OllamaState "old"}}<details class="othercmds"><summary>How to update Ollama</summary>
+<table class="cmds"><tbody>
+<tr><th scope="row">Windows or macOS</th><td>Click the Ollama icon in the taskbar or menu bar and choose Restart to update, or download the latest version from the official download page, https://ollama.com/download</td></tr>
+<tr><th scope="row">Linux (install script)</th><td><code>curl -fsSL https://ollama.com/install.sh | sh</code></td></tr>
+<tr><th scope="row">In Docker</th><td><code>docker pull ollama/ollama</code>, then stop and remove the container (<code>docker stop &lt;container-name&gt;</code> and <code>docker rm &lt;container-name&gt;</code>) and start it again with the same <code>docker run</code> command, including the same <code>-v</code> volume, so the downloaded models stay. The command is on https://docs.ollama.com/docker</td></tr>
+</tbody></table></details>{{end}}{{end}}
 {{if .Unavailable}}<p class="warn">{{.Unavailable}}. Open the official page above for its versions.</p>{{else}}
 {{if eq .FitCount 0}}<p class="warn">None of its versions fit your choices. The versions are listed below with the reason.</p>{{end}}
 <ul class="findversions">
@@ -132,6 +142,11 @@
 {{end}}
 </ul>
 {{if .More}}<p class="muted"><small>{{.More}} more versions are on the official page.</small></p>{{end}}
+{{/* A simple comparison of the plain size versions, smallest download first. */}}
+{{if .SizeRows}}<details class="othercmds"><summary>Compare sizes ({{len .SizeRows}} versions)</summary>
+<table class="cmds"><thead><tr><th scope="col">Version</th><th scope="col">Download</th><th scope="col">Context</th><th scope="col">On this computer</th></tr></thead><tbody>
+{{range .SizeRows}}<tr><td><code>{{.Tag}}</code>{{if .Installed}} <strong>Installed</strong>{{end}}</td><td>{{if .Size}}{{.Size}}{{else}}not shown{{end}}</td><td>{{if .Context}}{{.Context}}{{else}}not shown{{end}}</td><td>{{if .Fits}}fits{{else}}{{.Reason}}{{end}}</td></tr>
+{{end}}</tbody></table></details>{{end}}
 {{end}}
 </div>
 {{end}}
OCC_PATCH_124_END
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
pass "all ${#AFTER[@]} changed files have the expected sha256"

# The key lines must be in the program and the page.
grep -q 'func qualifyReasons' findllm.go && grep -q 'func applyOllamaNeed' findllm.go && grep -q 'func sizeRows' findllm.go && grep -q 'Compare sizes' web/findllm.html && grep -q 'Matched your choices' web/findllm.html || fail "a key line of the change is missing"
# Report it.
pass "the three features are in the program and the page"

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

# Run every test once; the delete-confirm test failed once without a known cause, so a single failure of exactly that test is reported and not hidden.
go test -count=1 ./... || fail "go test failed (if only TestDeleteConfirmRefusesLoadedModel failed, tell Claude)"
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
echo "NEXT  try the page by hand (instructions follow in the chat), then commit and push everything."
# Show what changed in the project folder.
git status --short
