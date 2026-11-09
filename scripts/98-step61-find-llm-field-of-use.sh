#!/usr/bin/env bash
# Script 98 (Find LLM, Field of use): a new group between What it should do and Model size. The person ticks the fields of use that matter: Healthcare and medicine, Code and software, SQL and data, Maths and science, Documents and OCR, Translation and languages, Safety and moderation. A model belongs to a field when its name, or the first 100 characters of its description in the official library, contain the field's keywords; this is a guess from words, not a certification, and the page says so, including that healthcare models are not validated for clinical use. The group has its own choice, Match ALL ticked (the default) or Match ANY ticked, on the right with visible explanations and very short tooltips, like What it should do. It applies to the local models and to the Cloud models section. Pharma, legal and finance are not included because the official list has no model for them. Four new tests.
# Run it from the project folder, on the branch feature/find-llm-installed-speed (the same branch as script 94, after script 97): cd ~/LLMsControlDock && bash scripts/98-step61-find-llm-field-of-use.sh
#
# Stop at the first error, on an unset variable, or on a failed step inside a pipe.
set -euo pipefail

# The expected sha256 of every file BEFORE the change (as left by script 97b), and of every file AFTER it.
declare -A BEFORE AFTER
BEFORE["findllm.go"]="4c6f9e468e6c67214a4fa27dca935d81a8681545ec6b0ab8acf2afbd0fd5f801"
BEFORE["findllm_test.go"]="93f0002fde712447ce3fb3bcc43bf008a8a27d0f17bf1e898f6598676e573c9c"
BEFORE["web/findllm.html"]="6c35723d3cd11977174de41a52b00239407ab45c4c019b50cdb0c2cf7aebf03b"
AFTER["findllm.go"]="bd99ffbdb89e79374a72c8deacffaddab70412d07545b4a8efc457e800636517"
AFTER["findllm_test.go"]="c508944db7c6e9ee374f5f95a4be9f61f9d19abba630f69062fb1f99a5435d9a"
AFTER["web/findllm.html"]="48c914887b1664b7b2b71c6d41c5c7458c489a635d1f79612b5977ce20f0aa6f"

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

# Script 97b must have been applied: the choice has its tooltips.
grep -q 'tip-mode-all' web/findllm.html || fail "script 97b must be applied first"
# Report it.
pass "script 97b (Match ALL or Match ANY with tooltips) is applied"

# Refuse to run twice: the field-of-use list exists when this change was applied before.
if grep -q 'var findDomains' findllm.go; then fail "findllm.go already has the fields of use: this script was already applied"; fi
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
index 130ef11..a8c33d3 100644
--- a/findllm.go
+++ b/findllm.go
@@ -18,6 +18,8 @@ import ( // import lists the standard-library packages this file uses.
 	"net/http"
 	// os reads the home folder and one environment variable.
 	"os"
+	// regexp matches the keywords that assign a model to a field of use.
+	"regexp"
 	// sort orders the results.
 	"sort"
 	// strconv turns typed text into numbers.
@@ -282,6 +284,10 @@ type findSelection struct {
 	Chat bool
 	// Abilities are the ticked abilities (tools, vision, audio, thinking, embedding).
 	Abilities map[string]bool
+	// Domains are the ticked fields of use (keys of findDomains); empty means no filter.
+	Domains map[string]bool
+	// DomainAny is true when the person chose "Match ANY ticked" for the fields of use; false (the default) is "Match ALL ticked".
+	DomainAny bool
 	// Any is true when the person chose "Match ANY ticked": a model needs at least one ticked ability; false (the default) is "Match ALL ticked": it needs every one.
 	Any bool
 	// Sizes are the ticked size classes (empty means any size).
@@ -320,13 +326,23 @@ func parseGB(text string) (float64, error) {
 // parseFindForm reads the form fields into a selection; problems lists what was typed wrongly.
 func parseFindForm(get func(string) string) (findSelection, []string) {
 	// Start empty.
-	sel := findSelection{Abilities: map[string]bool{}, Sizes: map[string]bool{}, Contexts: map[string]bool{}}
+	sel := findSelection{Abilities: map[string]bool{}, Domains: map[string]bool{}, Sizes: map[string]bool{}, Contexts: map[string]bool{}}
 	// The problems found.
 	var problems []string
 	// Chat and writing.
 	sel.Chat = get("ab_chat") == "on"
 	// Match ANY only when that exact choice was sent; anything else, or nothing, is the default Match ALL.
 	sel.Any = get("ab_mode") == "any"
+	// The same for the fields of use.
+	sel.DomainAny = get("dom_mode") == "any"
+	// Each known field of use that is ticked.
+	for _, d := range findDomains {
+		// Ticked.
+		if get("dom_"+d.Key) == "on" {
+			// Remember it.
+			sel.Domains[d.Key] = true
+		} // end of the tick check
+	} // end of the fields
 	// Each ability.
 	for _, k := range abilityKeys {
 		// Ticked.
@@ -373,6 +389,106 @@ func parseFindForm(get func(string) string) (findSelection, []string) {
 	return sel, problems
 } // end of parseFindForm
 
+// domainDef describes one field of use: how a model is assigned to it, from its name and from the first words of its description.
+type domainDef struct {
+	// Key is the short code in the form field name (dom_<key>).
+	Key string
+	// Label is the wording on the page.
+	Label string
+	// Tip is the very short help line; one line, no markup characters.
+	Tip string
+	// Name matches the library name of the model.
+	Name *regexp.Regexp
+	// Lead matches the first words of the description (the part that says what the model is for).
+	Lead *regexp.Regexp
+} // end of domainDef
+
+// domainLeadRunes is how many characters of the description count: the opening, which says what the model is for, not the long list of side abilities after it.
+const domainLeadRunes = 100
+
+// findDomains are the fields of use of the first version. Pharma, legal and finance are left out until the official list has models for them.
+var findDomains = []domainDef{
+	// Healthcare and medicine.
+	{"health", "Healthcare and medicine", "Medical models. Not validated for clinical use.",
+		regexp.MustCompile(`(?i)\bmed(llama|gemma|iton)`),
+		regexp.MustCompile(`(?i)\bmedical\b|\bmedicine\b|\bhealth(care)?\b|\bclinical\b|\bbiomedical\b|\bpatients?\b|\bdoctors?\b|\bdiagnos\w*`)},
+	// Code and software.
+	{"code", "Code and software", "Models made for writing and fixing code.",
+		regexp.MustCompile(`(?i)code|devstral`),
+		regexp.MustCompile(`(?i)\bcode (generation|completion|llm|language model|model|models)\b|\bcoding (model|models|agents|tasks)\b|\bcoding-focused\b|\bcode-specific\b|\bcode intelligence\b`)},
+	// SQL and data.
+	{"sql", "SQL and data", "Models that turn questions into SQL queries.",
+		regexp.MustCompile(`(?i)sql`),
+		regexp.MustCompile(`(?i)\bsql\b|\btext-to-sql\b`)},
+	// Maths and science.
+	{"math", "Maths and science", "Models made for maths problems and science.",
+		regexp.MustCompile(`(?i)math`),
+		regexp.MustCompile(`(?i)\bmath (language )?models?\b|\bmath problems\b|\bmath reasoning\b|\bscientific discovery\b|\btheorem`)},
+	// Documents and OCR.
+	{"docs", "Documents and OCR", "Models that read scans, pages and forms.",
+		regexp.MustCompile(`(?i)ocr|docling|nuextract|reader-lm`),
+		regexp.MustCompile(`(?i)\bocr\b|\binformation extraction\b|\bhtml (content )?to markdown\b|\bdocument understanding\b`)},
+	// Translation and languages.
+	{"lang", "Translation and languages", "Translation and models built for many languages.",
+		regexp.MustCompile(`(?i)translate|^aya|sailor`),
+		regexp.MustCompile(`(?i)\btranslat\w*|\bmultilingual\b|\bbilingual\b|\b\d+ languages\b|\b(chinese|korean|japanese|arabic|german) (dialogue|language)`)},
+	// Safety and moderation.
+	{"safety", "Safety and moderation", "Models that check prompts and answers for risk.",
+		regexp.MustCompile(`(?i)guard|shield|safeguard`),
+		regexp.MustCompile(`(?i)\bcontent safety\b|\bmoderat\w*|\bsafety (classification|reasoning)\b`)},
+} // end of findDomains
+
+// modelDomains returns the keys of the fields of use a model belongs to, judged from its name and the opening of its description. This is a guess from words, not a certification.
+func modelDomains(m siteModel) map[string]bool {
+	// The opening of the description, cut by characters so no letter is split.
+	lead := []rune(m.Description)
+	// Cut it.
+	if len(lead) > domainLeadRunes {
+		// Keep the opening.
+		lead = lead[:domainLeadRunes]
+	} // end of the cut
+	// The result.
+	out := map[string]bool{}
+	// Each field of use.
+	for _, d := range findDomains {
+		// The name or the opening matches.
+		if d.Name.MatchString(m.Name) || d.Lead.MatchString(string(lead)) {
+			// The model belongs to it.
+			out[d.Key] = true
+		} // end of the match
+	} // end of the fields
+	// Done.
+	return out
+} // end of modelDomains
+
+// domainMatch says whether a model satisfies the ticked fields of use: Match ALL (the default) needs every ticked field, Match ANY at least one; nothing ticked lets every model pass.
+func domainMatch(sel findSelection, m siteModel) bool {
+	// Nothing ticked: no filter.
+	if len(sel.Domains) == 0 {
+		// Every model passes.
+		return true
+	} // end of the empty check
+	// The fields of this model.
+	has := modelDomains(m)
+	// How many ticked fields the model belongs to.
+	hits := 0
+	// Count them.
+	for k := range sel.Domains {
+		// A hit.
+		if has[k] {
+			// One more.
+			hits++
+		} // end of the hit
+	} // end of the count
+	// Match ANY: one is enough.
+	if sel.DomainAny {
+		// At least one.
+		return hits > 0
+	} // end of the any check
+	// Match ALL: every ticked field.
+	return hits == len(sel.Domains)
+} // end of domainMatch
+
 // abilitiesMatch says whether a model with the abilities in has satisfies the ticks of "What it should do": with Match ALL (the default) every ticked item must hold, with Match ANY at least one; with nothing ticked every model passes. "Chat and writing" holds for a model that is not a search-and-similarity model.
 func abilitiesMatch(sel findSelection, has map[string]bool) bool {
 	// How many items are ticked and how many of them the model satisfies.
@@ -434,6 +550,11 @@ func findCandidates(models []siteModel, sel findSelection) (out []siteModel, noS
 			// Next.
 			continue
 		} // end of the ability check
+		// The ticked fields of use: all of them or any of them, as chosen.
+		if !domainMatch(sel, m) {
+			// Next.
+			continue
+		} // end of the field check
 		// Size classes: at least one of the model's sizes must be in a ticked class.
 		if len(sel.Sizes) > 0 {
 			// Whether any size matches, and whether any size could be read.
@@ -505,7 +626,7 @@ func findCloudModels(models []siteModel, sel findSelection) (out []siteModel, sk
 			has[a] = true
 		} // end of the fill
 		// The ticks of "What it should do": all of them or any of them, as chosen.
-		if abilitiesMatch(sel, has) {
+		if abilitiesMatch(sel, has) && domainMatch(sel, m) {
 			// Keep the match.
 			out = append(out, m)
 		} // end of the match check
@@ -858,6 +979,10 @@ type findPage struct {
 	Chat bool
 	// AnyMode is whether "Match ANY ticked" is chosen; false means "Match ALL ticked".
 	AnyMode bool
+	// Domains are the boxes of the fields of use.
+	Domains []domainTick
+	// DomainAnyMode is whether "Match ANY ticked" is chosen for the fields of use.
+	DomainAnyMode bool
 	// Disk and Mem are the typed numbers, as text.
 	Disk, Mem string
 	// DiskNote and MemNote explain where the numbers come from.
@@ -890,6 +1015,20 @@ type findPage struct {
 	InstalledNote string
 } // end of findPage
 
+// domainTick is one box of the fields of use.
+type domainTick struct {
+	// Name is the form field name.
+	Name string
+	// Label is the wording.
+	Label string
+	// Tip is the very short help line.
+	Tip string
+	// TipID is the id of its tooltip.
+	TipID string
+	// On is true when ticked.
+	On bool
+} // end of domainTick
+
 // findTick is one tick box.
 type findTick struct {
 	// Name is the form field name.
@@ -920,7 +1059,7 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 	// render draws the page for a selection.
 	render := func(w http.ResponseWriter, r *http.Request, sel findSelection, fm findMachine, problems []string, searched bool, results []resultView, cloudRes []resultView, cloudMore int, total, cloud, noSize int, errText, readAt, copyNote, instNote string, status int) {
 		// The tick boxes.
-		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, AnyMode: sel.Any, Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, InstalledNote: instNote, CloudResults: cloudRes, CloudMore: cloudMore, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
+		data := findPage{Theme: themeFromRequest(r), Size: sizeFromRequest(r), Token: token, Tips: tips, Chat: sel.Chat, AnyMode: sel.Any, DomainAnyMode: sel.DomainAny, Problems: problems, Searched: searched, Error: errText, ReadAt: readAt, CopyNote: copyNote, InstalledNote: instNote, CloudResults: cloudRes, CloudMore: cloudMore, Results: results, Summary: findSummary(len(results), total, cloud, noSize, readAt)}
 		// The abilities.
 		for _, k := range abilityKeys {
 			// One box.
@@ -936,6 +1075,11 @@ func findLLMHandlers(addr ollamaAddress, token string, store *perfStore) (http.H
 			// One box.
 			data.Contexts = append(data.Contexts, findTick{Name: "cx_" + c.Key, Label: c.Label, Range: c.Range, On: sel.Contexts[c.Key]})
 		} // end of the contexts
+		// The boxes of the fields of use.
+		for _, d := range findDomains {
+			// One box.
+			data.Domains = append(data.Domains, domainTick{Name: "dom_" + d.Key, Label: d.Label, Tip: d.Tip, TipID: "tip-dom-" + d.Key, On: sel.Domains[d.Key]})
+		} // end of the fields
 		// The typed numbers.
 		data.Disk, data.Mem = numberText(sel.DiskGB), numberText(sel.MemGB)
 		// Where the disk number comes from.
diff --git a/findllm_test.go b/findllm_test.go
index b9bef3b..68b63aa 100644
--- a/findllm_test.go
+++ b/findllm_test.go
@@ -1536,3 +1536,163 @@ func TestFindModeChoice(t *testing.T) {
 		t.Error("an unknown mode did not fall back to Match ALL")
 	} // end of the fallback check
 } // end of TestFindModeChoice
+
+// TestDomainDefinitions checks the house rules for the fields of use: unique keys, a label and a tooltip each, tooltips of one short line without markup characters.
+func TestDomainDefinitions(t *testing.T) {
+	// The keys seen so far.
+	seen := map[string]bool{}
+	// Each field of use.
+	for _, d := range findDomains {
+		// A key is used once.
+		if seen[d.Key] {
+			// Report.
+			t.Errorf("the key %q is used twice", d.Key)
+		} // end of the key check
+		// Remember it.
+		seen[d.Key] = true
+		// Label and tooltip are filled.
+		if strings.TrimSpace(d.Label) == "" || strings.TrimSpace(d.Tip) == "" {
+			// Report.
+			t.Errorf("%q has an empty label or tooltip", d.Key)
+		} // end of the filled check
+		// The tooltip follows the house rules.
+		if n := utf8.RuneCountInString(d.Tip); n > 130 || strings.ContainsAny(d.Tip, "<>{}\n") {
+			// Report.
+			t.Errorf("%q: tooltip %q is longer than 130 characters or has markup characters", d.Key, d.Tip)
+		} // end of the tooltip check
+	} // end of the loop
+} // end of TestDomainDefinitions
+
+// TestModelDomains checks the keyword assignment with real descriptions from the official library: each model lands in its fields, and models that only mention a word in passing, or only look like a keyword, do not.
+func TestModelDomains(t *testing.T) {
+	// The cases: real name and description (as read on 2026-11-08) and the expected fields.
+	for _, c := range []struct {
+		name, desc string
+		want       string
+	}{
+		{"medgemma", "MedGemma is a collection of Gemma 3 variants that are trained for performance on medical text and image comprehension.", "health"},
+		{"meditron", "Open-source medical large language model adapted from Llama 2 to the medical domain.", "health"},
+		{"sqlcoder", "SQLCoder is a code completion model fined-tuned on StarCoder for SQL generation tasks", "code,sql"},
+		{"duckdb-nsql", "7B parameter text-to-SQL model made by MotherDuck and Numbers Station.", "sql"},
+		{"mathstral", "MathΣtral: a 7B model designed for math reasoning and scientific discovery by Mistral AI.", "math"},
+		{"qwen2-math", "Qwen2 Math is a series of specialized math language models built upon the Qwen2 LLMs.", "math"},
+		{"glm-ocr", "GLM-OCR is a multimodal OCR model for complex document understanding, built on the GLM-V encoder-decoder architecture.", "docs"},
+		{"translategemma", "A new collection of open translation models built on Gemma 3, helping people communicate across 55 languages.", "lang"},
+		{"llama-guard3", "Llama Guard 3 is a series of models fine-tuned for content safety classification of LLM inputs and responses.", "safety"},
+		// A general model that lists coding among many abilities is not a code model.
+		{"qwen3.6", "Qwen3.6 delivers substantial upgrades in agentic coding and thinking preservation than previous Qwen models.", ""},
+		// A name that merely contains the letters aya is not the Aya family.
+		{"laya", "Laya is a 421M decision model from Convai Innovations, fine-tuned from ModernBERT-large.", ""},
+		// A model with no domain word at all.
+		{"gpt-oss", "OpenAI's open-weight models designed for powerful reasoning, agentic tasks, and versatile developer use cases.", ""},
+	} {
+		// The fields found, in the order of findDomains.
+		var got []string
+		// Each field.
+		for _, d := range findDomains {
+			// Found.
+			if modelDomains(siteModel{Name: c.name, Description: c.desc})[d.Key] {
+				// Remember it.
+				got = append(got, d.Key)
+			} // end of the found check
+		} // end of the loop
+		// Compare as text.
+		if g := strings.Join(got, ","); g != c.want {
+			// Report.
+			t.Errorf("%s: fields %q, want %q", c.name, g, c.want)
+		} // end of the compare
+	} // end of the cases
+} // end of TestModelDomains
+
+// TestDomainMatch checks the all-or-any rule for the fields of use, including nothing ticked.
+func TestDomainMatch(t *testing.T) {
+	// A model in two fields, and one in a single field.
+	sqlcoder := siteModel{Name: "sqlcoder", Description: "SQLCoder is a code completion model fined-tuned on StarCoder for SQL generation tasks"}
+	// The maths model.
+	maths := siteModel{Name: "qwen2-math", Description: "Qwen2 Math is a series of specialized math language models."}
+	// The cases.
+	for _, c := range []struct {
+		name string
+		sel  findSelection
+		m    siteModel
+		want bool
+	}{
+		{"nothing ticked", findSelection{}, maths, true},
+		{"all: both fields, model in both", findSelection{Domains: map[string]bool{"code": true, "sql": true}}, sqlcoder, true},
+		{"all: both fields, model in one", findSelection{Domains: map[string]bool{"code": true, "math": true}}, maths, false},
+		{"any: one of two", findSelection{DomainAny: true, Domains: map[string]bool{"code": true, "math": true}}, maths, true},
+		{"any: none of two", findSelection{DomainAny: true, Domains: map[string]bool{"health": true, "safety": true}}, maths, false},
+	} {
+		// The answer.
+		if got := domainMatch(c.sel, c.m); got != c.want {
+			// Report.
+			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
+		} // end of the answer check
+	} // end of the loop
+} // end of TestDomainMatch
+
+// TestFindDomainChoice checks the Field of use group on the page: the boxes, the default Match ALL, the visible explanation and the very short tooltips, the guess note, and that the ticks and the choice are kept after a search.
+func TestFindDomainChoice(t *testing.T) {
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
+	// The group starts at its legend.
+	i := strings.Index(form, "<strong>Field of use</strong>")
+	// It must exist.
+	if i < 0 {
+		// Stop here.
+		t.Fatal("the page lacks the Field of use group")
+	} // end of the group check
+	// The group itself.
+	box := form[i : i+strings.Index(form[i:], "</fieldset>")]
+	// Every field has a box and a tooltip that the box points to.
+	for _, d := range findDomains {
+		// The box and the tooltip.
+		if !strings.Contains(box, `name="dom_`+d.Key+`"`) || !strings.Contains(box, `id="tip-dom-`+d.Key+`">`+d.Tip) || !strings.Contains(box, `aria-describedby="tip-dom-`+d.Key+`"`) {
+			// Report.
+			t.Errorf("the group lacks the box or tooltip of %q", d.Key)
+		} // end of the field check
+	} // end of the loop
+	// Match ALL is the default and both choices exist.
+	if !strings.Contains(box, `name="dom_mode" value="all" checked`) || strings.Contains(box, `name="dom_mode" value="any" checked`) || !strings.Contains(box, `name="dom_mode" value="any"`) {
+		// Report.
+		t.Error("the choice is missing or the default is not Match ALL")
+	} // end of the radio check
+	// Visible explanations, the two very short tooltips and the guess note.
+	for _, want := range []string{"The model must fit every field you ticked.", "The model needs to fit at least one field you ticked.", `id="tip-dom-mode-all">All ticked fields needed.`, `id="tip-dom-mode-any">One ticked field is enough.`, "It is not a certification.", "Healthcare models are not validated for clinical use."} {
+		// Look for it.
+		if !strings.Contains(box, want) {
+			// Report.
+			t.Errorf("the group lacks the text %q", want)
+		} // end of the look
+	} // end of the loop
+	// No heading words are shown for the choice, only an accessible name.
+	if strings.Contains(strings.ReplaceAll(box, `aria-label="How the ticked fields combine"`, ""), "How the ticked fields combine") {
+		// Report.
+		t.Error("the words How the ticked fields combine are visible")
+	} // end of the heading check
+	// A search with a field ticked and Match ANY chosen: nothing in the fake library is a healthcare model, and both choices are kept.
+	_, body := postFind(t, rig, url.Values{"token": {rig.token}, "dom_health": {"on"}, "dom_mode": {"any"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
+	// No fake model is listed.
+	for _, d := range []string{"An invented chat model.", "Turns text into numbers.", "Runs far away."} {
+		// Look for it.
+		if strings.Contains(body, d) {
+			// Report.
+			t.Errorf("the healthcare filter lists %q", d)
+		} // end of the look
+	} // end of the loop
+	// The tick and the choice are kept.
+	if !strings.Contains(body, `name="dom_health" checked`) || !strings.Contains(body, `name="dom_mode" value="any" checked`) {
+		// Report.
+		t.Error("the ticked field or Match ANY is not kept after the search")
+	} // end of the kept check
+} // end of TestFindDomainChoice
diff --git a/web/findllm.html b/web/findllm.html
index e114356..864dad1 100644
--- a/web/findllm.html
+++ b/web/findllm.html
@@ -60,6 +60,25 @@
 </div>
 </div>
 </fieldset>
+{{/* The field of use: what the model was made for, guessed from the words in its name and description. */}}
+<fieldset class="findgroup">
+<legend><strong>Field of use</strong> <small class="muted">(none ticked: any field)</small></legend>
+{{/* Two columns: the fields on the left, the all-or-any choice on the right; on a narrow window the choice drops below. */}}
+<div class="abilitywrap">
+<div class="abilitylist">
+{{range .Domains}}<label class="tickrow"><input type="checkbox" name="{{.Name}}"{{if .On}} checked{{end}}> <span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.TipID}}">{{.Label}}</span><span class="tip" role="tooltip" id="{{.TipID}}">{{.Tip}}</span></span></label>
+{{end}}
+</div>
+{{/* How the ticked fields combine: always one of the two is chosen (Match ALL unless the person chose otherwise); visible text under each choice and a very short tooltip on each. */}}
+<div class="abilitymode" role="radiogroup" aria-label="How the ticked fields combine">
+<label class="tickrow"><input type="radio" name="dom_mode" value="all"{{if not .DomainAnyMode}} checked{{end}}> <span class="tipbox"><span class="help" tabindex="0" aria-describedby="tip-dom-mode-all"><strong>Match ALL ticked</strong></span><span class="tip" role="tooltip" id="tip-dom-mode-all">All ticked fields needed.</span></span> <small class="muted">(the default)</small></label>
+<p class="modeexplain"><small>The model must fit every field you ticked. Example: Code and software and SQL and data lists only models that fit both.</small></p>
+<label class="tickrow"><input type="radio" name="dom_mode" value="any"{{if .DomainAnyMode}} checked{{end}}> <span class="tipbox"><span class="help" tabindex="0" aria-describedby="tip-dom-mode-any"><strong>Match ANY ticked</strong></span><span class="tip" role="tooltip" id="tip-dom-mode-any">One ticked field is enough.</span></span></label>
+<p class="modeexplain"><small>The model needs to fit at least one field you ticked. Example: Healthcare and medicine and Code and software lists models that fit either one or both.</small></p>
+</div>
+</div>
+<p class="muted"><small>The field is guessed from the words in each model's name and description in the official library. It is not a certification. Healthcare models are not validated for clinical use.</small></p>
+</fieldset>
 {{/* How big the model may be. */}}
 <fieldset class="findgroup">
 <legend><span class="tipbox"><span class="help" tabindex="0" aria-describedby="{{.Tips.size.ID}}"><strong>Model size</strong></span><span class="tip" role="tooltip" id="{{.Tips.size.ID}}">{{template "tip" .Tips.size}}</span></span> <small class="muted">(none ticked: any size)</small></legend>
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
echo "NEXT  start bin/LLMsControlDock and open Find LLM and look at the new Field of use group (instructions follow in the chat)."
# Show what changed in the project folder.
git status --short
