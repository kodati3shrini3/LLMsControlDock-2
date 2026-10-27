#!/usr/bin/env bash
# Script 69: the comparison page puts every model in a group (kind and size class), flags anything that makes a ranking unfair, explains how and why with verified references, carries a legal notice, and offers a PDF report and a CSV file. Version 0.14.0.
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/compare-groups" ] || { echo "FAIL  not on feature/compare-groups"; exit 1; }
# Script 68 must be part of this branch already (merged into main).
[ -e perfclear.go ] || { echo "FAIL  script 68 was not applied yet"; exit 1; }
# Refuse to run twice.
if [ -e compgroup.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/about.go b/about.go
index 17f6aaa..b2c82a8 100644
--- a/about.go
+++ b/about.go
@@ -26,7 +26,7 @@ import ( // import lists the packages this file uses.
 var aboutTemplateText string
 
 // appVersion is the version of Ollama Control Center; it is raised by hand when a release is made.
-const appVersion = "0.13.0"
+const appVersion = "0.14.0"
 
 // appDeveloper is the name of the developer, shown on the About page.
 const appDeveloper = "Shrinivas Kodati"
diff --git a/brand_test.go b/brand_test.go
index 0788f26..f5da207 100644
--- a/brand_test.go
+++ b/brand_test.go
@@ -113,7 +113,7 @@ func TestEveryExternalLinkIsSafe(t *testing.T) {
 	// All templates.
 	files, _ := filepath.Glob("web/*.html")
 	// A link to an outside address, written out or built by the template from a field that holds one.
-	link := regexp.MustCompile(`<a [^>]*href="(https?://[^"]*|\{\{\.(?:HeaderURL|FooterURL|CompanyURL|DeveloperProfile|Repository)\}\})"[^>]*>`)
+	link := regexp.MustCompile(`<a [^>]*href="(https?://[^"]*|\{\{\.(?:HeaderURL|FooterURL|CompanyURL|DeveloperProfile|Repository|URL)\}\})"[^>]*>`)
 	// How many were checked, so the test cannot pass by finding nothing.
 	checked := 0
 	// Go through the templates.
diff --git a/compare.go b/compare.go
index a335a06..570a45a 100644
--- a/compare.go
+++ b/compare.go
@@ -14,10 +14,6 @@ import ( // import lists the standard-library packages this file uses.
 	"log"
 	// net/http serves the page.
 	"net/http"
-	// sort puts the rows in order.
-	"sort"
-	// strings joins text.
-	"strings"
 ) // end of imports
 
 // compareTemplateText is the page template, stored inside the executable at build time.
@@ -25,37 +21,46 @@ import ( // import lists the standard-library packages this file uses.
 //go:embed web/compare.html
 var compareTemplateText string
 
-// wordsPerToken is the rough number of English words in one token (a common rule of thumb, not a measurement).
-const wordsPerToken = 0.75
+// compareTextHeadings are the column headings of a group of chat models, in order.
+var compareTextHeadings = []string{"Model", "Parameters", "Quantization", "Tested on", "Answer speed", "Characters per second", "Speed vs fastest", "Prompt reading speed", "Time to first word", "Total time", "Load time", "Load speed from disk", "Memory used", "Processor split", "Machine busy", "Fair to rank?"}
 
-// compareTextHeadings are the column headings of the table of text models, in order.
-var compareTextHeadings = []string{"Model", "Tested on", "Answer speed", "Speed vs fastest", "Words per second", "Prompt reading speed", "Time to first word", "Total time", "Load time", "Load speed from disk", "Memory used", "Processor split", "Speed per GB of memory", "Machine busy"}
-
-// compareEmbedHeadings are the column headings of the table of embedding models, in order.
-var compareEmbedHeadings = []string{"Model", "Tested on", "Embedding time", "Speed vs fastest", "Load time", "Load speed from disk", "Memory used", "Processor split", "Vector length", "Machine busy"}
+// compareEmbedHeadings are the column headings of the group of embedding models, in order.
+var compareEmbedHeadings = []string{"Model", "Quantization", "Tested on", "Embedding time", "Speed vs fastest", "Load time", "Load speed from disk", "Memory used", "Processor split", "Vector length", "Machine busy", "Fair to rank?"}
 
 // compareExtraHeadings are the headings that exist only on the comparison page and need their own tooltip (the others are shared with the performance page).
-var compareExtraHeadings = []string{"Tested on", "Speed vs fastest", "Words per second", "Load speed from disk", "Speed per GB of memory", "Machine busy"}
+var compareExtraHeadings = []string{"Tested on", "Speed vs fastest", "Characters per second", "Load speed from disk", "Machine busy", "Fair to rank?"}
 
 // cmpRow is one model in a comparison table.
 type cmpRow struct {
 	// Cells are the values, one for each column.
 	Cells []string
-	// Busy is true when the run was made on a busy machine, so the row can be marked.
+	// Busy is true when the run was made on a busy machine.
 	Busy bool
 } // end of cmpRow
 
-// cmpTable is one comparison table.
-type cmpTable struct {
-	// Title is the heading above the table.
+// howRow is one question of the "How and why" section with its answer; the numbers in brackets point to the reference list.
+type howRow struct {
+	// Question is what a reader may ask.
+	Question string
+	// Answer says how and why, in plain words.
+	Answer string
+} // end of howRow
+
+// cmpGroupView is one comparison group as the page draws it.
+type cmpGroupView struct {
+	// Title is the heading of the group.
 	Title string
-	// Note is one sentence under the heading.
-	Note string
+	// Why is the reason the models are compared together.
+	Why string
+	// Headline is the sentence about the fastest model, or empty.
+	Headline string
+	// Notes explain why there is no ranking, or that the model has no peer.
+	Notes []string
 	// Cols are the column headings with their help bubbles.
 	Cols []tipView
 	// Rows are the models.
 	Rows []cmpRow
-} // end of cmpTable
+} // end of cmpGroupView
 
 // comparePage is everything the comparison template needs.
 type comparePage struct {
@@ -63,18 +68,34 @@ type comparePage struct {
 	Theme string
 	// Size is the saved text size, medium, or empty for the browser's own size.
 	Size string
-	// Token is the page token for the "Back" form.
+	// Token is the page token for the forms.
 	Token string
-	// Tables are the comparison tables (text models, embedding models).
-	Tables []cmpTable
+	// Groups are the comparison groups.
+	Groups []cmpGroupView
 	// Findings are plain sentences read out of the figures.
 	Findings []string
-	// Notes are cautions about how to read the table.
+	// Notes are cautions about how to read the page.
 	Notes []string
 	// Empty is true when no test is saved yet.
 	Empty bool
 	// SaveNote says where the figures come from, or why there is no file.
 	SaveNote string
+	// NoticeShort is the short notice at the top.
+	NoticeShort string
+	// NoticeTitle is the heading of the full notice.
+	NoticeTitle string
+	// NoticeFull is the full notice, one paragraph per entry.
+	NoticeFull []string
+	// How is the "How and why this comparison was done" section.
+	How []howRow
+	// Refs is the verified reference list.
+	Refs []reference
+	// RefsChecked is the day the references were read.
+	RefsChecked string
+	// Models is how many models are shown, for the downloads.
+	Models int
+	// Data is the same groups in their raw form, for the CSV download.
+	Data []cmpGroup
 } // end of comparePage
 
 // latestRuns returns the newest run of each model and kind that used the given prompt version, and how many models were skipped because their newest run used another prompt.
@@ -170,21 +191,139 @@ func cmpLoadSpeed(r perfRun) string {
 	return fmt.Sprintf("%.1f GB/s", cmpGB(r.ModelBytes)/r.ColdLoadSec)
 } // end of cmpLoadSpeed
 
-// cmpName writes the model name, with a note when Ollama no longer has the model.
-func cmpName(name string, installed map[string]bool, known bool) string {
-	// Only say it when the list of installed models was read.
-	if known && !installed[name] {
-		// Mark it.
-		return name + " (no longer installed)"
+// cmpFair writes the "Fair to rank?" cell: yes, or no with every reason; symbols are for the page, plain words for the downloads.
+func cmpFair(m cmpModel, symbols bool) string {
+	// No reasons: the model can be ranked.
+	if len(m.Reasons) == 0 {
+		// With symbols for the page, plain words for downloads.
+		if symbols {
+			// The page form.
+			return "✓ Yes"
+		} // end of the symbol check
+		// The plain form.
+		return "Yes"
+	} // end of the fair check
+	// Join the reasons.
+	why := ""
+	// Go through them.
+	for i, r := range m.Reasons {
+		// A separator between reasons.
+		if i > 0 {
+			// Semicolon and space.
+			why += "; "
+		} // end of the separator check
+		// The reason.
+		why += r
+	} // end of the loop
+	// With symbols for the page, plain words for downloads.
+	if symbols {
+		// The page form.
+		return "⚠ No: " + why
+	} // end of the symbol check
+	// The plain form.
+	return "No: " + why
+} // end of cmpFair
+
+// cmpVsFastest writes the "Speed vs fastest" cell of one model inside its group.
+func cmpVsFastest(g cmpGroup, m cmpModel) string {
+	// A model outside the ranking.
+	if m.Rank == 0 {
+		// Say so.
+		return "not ranked"
+	} // end of the rank check
+	// The best model is first.
+	best := g.Models[0].Run
+	// The best model itself.
+	if m.Rank == 1 {
+		// Say so.
+		return "#1, fastest"
+	} // end of the first check
+	// The ratio, worked out from the figure the group is ranked by.
+	ratio := 0.0
+	// An embedding group: time against the shortest time.
+	if g.Embedding {
+		// Longer is slower.
+		if best.WarmTotalSec > 0 {
+			// The ratio.
+			ratio = m.Run.WarmTotalSec / best.WarmTotalSec
+		} // end of the figure check
+	} else if m.Run.CharSpeed > 0 {
+		// A chat group: the best speed against this speed.
+		ratio = best.CharSpeed / m.Run.CharSpeed
+	} // end of the kind check
+	// Without a ratio only the place is shown.
+	if ratio <= 0 {
+		// The place.
+		return fmt.Sprintf("#%d", m.Rank)
+	} // end of the ratio check
+	// The place and the ratio.
+	return fmt.Sprintf("#%d, %.1f× slower", m.Rank, ratio)
+} // end of cmpVsFastest
+
+// cmpMemory writes the memory cell.
+func cmpMemory(r perfRun) string {
+	// Not reported.
+	if r.ModelBytes <= 0 {
+		// Say so.
+		return "not reported"
+	} // end of the check
+	// The size.
+	return formatSize(r.ModelBytes)
+} // end of cmpMemory
+
+// cmpCharSpeed writes the characters-per-second cell.
+func cmpCharSpeed(r perfRun) string {
+	// Older tests did not count characters.
+	if r.CharSpeed <= 0 {
+		// Say so.
+		return "not saved (older test)"
 	} // end of the check
-	// The plain name.
-	return name
-} // end of cmpName
+	// A whole number is precise enough.
+	return fmt.Sprintf("%.0f chars/s", r.CharSpeed)
+} // end of cmpCharSpeed
+
+// groupRowCells writes the cells of one model, in the order of the group's headings.
+func groupRowCells(g cmpGroup, m cmpModel) []string {
+	// The test.
+	r := m.Run
+	// The date.
+	when := r.Time.UTC().Format("2006-01-02 15:04 UTC")
+	// An embedding group.
+	if g.Embedding {
+		// The cells.
+		return []string{m.Name, m.Quant, when, fmtSecs(r.WarmTotalSec), cmpVsFastest(g, m), fmtSecs(r.ColdLoadSec), cmpLoadSpeed(r), cmpMemory(r), cmpSplit(r), fmt.Sprintf("%d numbers", r.VectorLength), cmpBusy(r), cmpFair(m, true)}
+	} // end of the embedding case
+	// The cells of a chat model.
+	return []string{m.Name, m.Params, m.Quant, when, fmtSpeed(r.AnswerSpeed), cmpCharSpeed(r), cmpVsFastest(g, m), fmtSpeed(r.PromptSpeed), fmtSecs(r.WarmFirstWordSec), fmtSecs(r.WarmTotalSec), fmtSecs(r.ColdLoadSec), cmpLoadSpeed(r), cmpMemory(r), cmpSplit(r), cmpBusy(r), cmpFair(m, true)}
+} // end of groupRowCells
 
-// buildCompare turns the latest saved runs into the page: two tables, the sentences read out of them, and the cautions.
-func buildCompare(runs []perfRun, skipped int, installed map[string]bool, known bool) comparePage {
-	// The page.
-	var p comparePage
+// howRows writes the "How and why this comparison was done" section; the numbers in brackets are checked against the reference list by a test.
+func howRows() []howRow {
+	// The rows.
+	return []howRow{
+		// What is measured.
+		{"What is measured?", "How fast each model answers one request at a time (the single-stream case) and how much memory it uses. It does not measure the quality or safety of the answers, many users at once, or long documents. [4]"},
+		// How a test runs.
+		{"How is a test run?", fmt.Sprintf("Every model gets the same fixed prompt, the same planned answer length (%d tokens), temperature 0 and the same random seed. One warm-up run is thrown away, and the middle value (median) of %d timed runs is kept. [1][3]", perfAnswerTokens, perfTimedRuns)},
+		// Why characters.
+		{"Why characters per second?", "Models cut text into tokens in different ways, so tokens per second cannot be compared between models of different makers. One published method counts every model's tokens with a single common tokenizer [3]; this program counts the characters of the answer instead, which needs no extra software and is the same for every model. Tokens per second is still shown for information."},
+		// How groups are chosen.
+		{"How are the groups chosen?", "By kind (chat or embedding) and, for chat models, by size class, using the parameter count Ollama reports. The five size classes are this program's own choice, not an industry standard. If Ollama reports no size, the class is estimated from the memory the model used, and such a model is not ranked. Embedding models are a group of their own [6]."},
+		// What decides a rank.
+		{"What decides whether a row can be ranked?", fmt.Sprintf("A model is ranked only when nothing makes it unlike the rest of its group: the same precision as most of the group, a test made within %d hours of the newest one, the same Ollama version and context length, the whole model on the graphics card, a quiet machine, no other model loaded, a full-length answer and a saved character count. The last column gives the reasons. The %d-hour limit is this program's own rule.", cmpSameSittingHours, cmpSameSittingHours)},
+		// Why nothing is ranked across groups.
+		{"Why is nothing ranked across groups?", "Results gained under different conditions are not directly comparable. The MLPerf paper applies this to its own results [4], and NVIDIA's documentation says to compare results only when the definitions align [2]."},
+		// How the figures are worked out.
+		{"How are the figures worked out?", "From the figures Ollama reports with each reply: counts of tokens and durations in nanoseconds [5]. Answer speed is the answer tokens divided by the answer time. Characters per second is the characters of the answer divided by the answer time. These two formulas are this program's own calculations, and the time to the first word is measured by this program."},
+		// What is not covered.
+		{"What is not covered?", "The quality and safety of answers, many users at once, long prompts, and other computers. Read the notice at the end of this page before using any figure."},
+	} // end of the rows
+} // end of howRows
+
+// buildCompare turns the latest saved runs into the page: comparison groups with fairness flags, the sentences read out of them, the method, the references and the notice.
+func buildCompare(runs []perfRun, skipped int, installed map[string]modelDetails, known bool) comparePage {
+	// The page, with the parts that never change.
+	p := comparePage{NoticeShort: noticeShort, NoticeTitle: noticeTitle, NoticeFull: noticeFull, How: howRows(), Refs: compareReferences, RefsChecked: referencesChecked, Models: len(runs)}
 	// Nothing saved yet.
 	if len(runs) == 0 {
 		// Say so.
@@ -197,156 +336,64 @@ func buildCompare(runs []perfRun, skipped int, installed map[string]bool, known
 		// Nothing more to build.
 		return p
 	} // end of the empty check
-	// Split by kind.
-	var texts, embeds []perfRun
-	// Sort each run into its list.
-	for _, r := range runs {
-		// An embedding model.
-		if r.Kind == "embedding" {
-			// Its list.
-			embeds = append(embeds, r)
-		} else {
-			// The text models.
-			texts = append(texts, r)
-		} // end of the kind check
-	} // end of the split loop
-	// Fastest writer first; a model with no figure goes last.
-	sort.SliceStable(texts, func(i, j int) bool { return texts[i].AnswerSpeed > texts[j].AnswerSpeed })
-	// Fastest embedder first (the shortest time); a model with no figure goes last.
-	sort.SliceStable(embeds, func(i, j int) bool {
-		// A missing figure is the slowest.
-		if embeds[i].WarmTotalSec <= 0 {
-			// Not before the other.
-			return false
-		} // end of the first check
-		// A missing figure of the other goes after this one.
-		if embeds[j].WarmTotalSec <= 0 {
-			// This one first.
-			return true
-		} // end of the second check
-		// Shorter is faster.
-		return embeds[i].WarmTotalSec < embeds[j].WarmTotalSec
-	}) // end of the embedding sort
+	// The groups.
+	groups := groupRuns(runs, installed, known)
+	// Keep the raw groups for the downloads.
+	p.Data = groups
+	// The first sentence says how to read the page.
+	p.Findings = append(p.Findings, "Models are compared only inside their group, under like-for-like conditions. There is no single winner across the whole list. [1][2][4]")
 	// Any busy run.
 	busy := 0
-	// Count them.
-	for _, r := range runs {
-		// A busy one.
-		if r.Busy {
-			// Count it.
-			busy++
-		} // end of the check
-	} // end of the count loop
-	// The table of text models.
-	if len(texts) > 0 {
-		// Its column headings.
-		t := cmpTable{Title: "Models that write text", Note: "Sorted by answer speed, fastest first. The same fixed prompt was used for every model. The table scrolls sideways."}
-		// Build the headings with their bubbles.
-		for i, h := range compareTextHeadings {
-			// A heading, with an element name that is unique on the page.
-			t.Cols = append(t.Cols, makeTip(fmt.Sprintf("tip-cmp-t-%d", i), h))
+	// Build the view of each group.
+	for gi, g := range groups {
+		// The heading list of the group.
+		heads := compareTextHeadings
+		// The prefix of the element names.
+		prefix := "t"
+		// An embedding group has its own columns.
+		if g.Embedding {
+			// Its headings.
+			heads = compareEmbedHeadings
+			// Its prefix.
+			prefix = "e"
+		} // end of the embedding check
+		// The view.
+		v := cmpGroupView{Title: g.Title, Why: g.Why, Headline: g.Headline, Notes: g.Notes}
+		// The headings with their bubbles, with element names that are unique on the page.
+		for i, h := range heads {
+			// One heading.
+			v.Cols = append(v.Cols, makeTip(fmt.Sprintf("tip-cmp-%s%d-%d", prefix, gi, i), h))
 		} // end of the heading loop
-		// The fastest figure is the reference.
-		fastest := texts[0].AnswerSpeed
-		// One row for each model.
-		for _, r := range texts {
-			// How it compares with the fastest.
-			vs := "not comparable"
-			// Work it out.
-			if r.AnswerSpeed > 0 && fastest > 0 {
-				// The fastest itself.
-				if r.AnswerSpeed >= fastest*0.995 {
-					// Say so.
-					vs = "fastest"
-				} else {
-					// How many times slower.
-					vs = fmt.Sprintf("%.1f× slower", fastest/r.AnswerSpeed)
-				} // end of the fastest check
-			} // end of the figure check
-			// Words per second, roughly.
-			words := "not available"
-			// Work it out.
-			if r.AnswerSpeed > 0 {
-				// About.
-				words = fmt.Sprintf("about %.0f", r.AnswerSpeed*wordsPerToken)
-			} // end of the words check
-			// Speed for each gigabyte of memory.
-			perGB := "not available"
-			// Work it out.
-			if r.AnswerSpeed > 0 && r.ModelBytes > 0 {
-				// Tokens per second per gigabyte.
-				perGB = fmt.Sprintf("%.1f tokens/s per GB", r.AnswerSpeed/cmpGB(r.ModelBytes))
-			} // end of the per-GB check
-			// Memory used.
-			mem := "not reported"
-			// Fill it in.
-			if r.ModelBytes > 0 {
-				// The size.
-				mem = formatSize(r.ModelBytes)
-			} // end of the memory check
-			// The row.
-			t.Rows = append(t.Rows, cmpRow{Busy: r.Busy, Cells: []string{
-				cmpName(r.Model, installed, known), r.Time.UTC().Format("2006-01-02 15:04 UTC"),
-				fmtSpeed(r.AnswerSpeed), vs, words, fmtSpeed(r.PromptSpeed), fmtSecs(r.WarmFirstWordSec), fmtSecs(r.WarmTotalSec),
-				fmtSecs(r.ColdLoadSec), cmpLoadSpeed(r), mem, cmpSplit(r), perGB, cmpBusy(r),
-			}}) // end of the row
-		} // end of the model loop
-		// Keep the table.
-		p.Tables = append(p.Tables, t)
-	} // end of the text table
-	// The table of embedding models.
-	if len(embeds) > 0 {
-		// Its title and note.
-		t := cmpTable{Title: "Embedding models", Note: "Sorted by embedding time, shortest first. Embedding models write no text, so they are never ranked against the models above. The table scrolls sideways."}
-		// Build the headings with their bubbles.
-		for i, h := range compareEmbedHeadings {
-			// A heading, with an element name that is unique on the page.
-			t.Cols = append(t.Cols, makeTip(fmt.Sprintf("tip-cmp-e-%d", i), h))
-		} // end of the heading loop
-		// The shortest time is the reference.
-		fastest := embeds[0].WarmTotalSec
-		// One row for each model.
-		for _, r := range embeds {
-			// How it compares with the fastest.
-			vs := "not comparable"
-			// Work it out.
-			if r.WarmTotalSec > 0 && fastest > 0 {
-				// The fastest itself.
-				if r.WarmTotalSec <= fastest*1.005 {
-					// Say so.
-					vs = "fastest"
-				} else {
-					// How many times slower.
-					vs = fmt.Sprintf("%.1f× slower", r.WarmTotalSec/fastest)
-				} // end of the fastest check
-			} // end of the figure check
-			// Memory used.
-			mem := "not reported"
-			// Fill it in.
-			if r.ModelBytes > 0 {
-				// The size.
-				mem = formatSize(r.ModelBytes)
-			} // end of the memory check
-			// The row.
-			t.Rows = append(t.Rows, cmpRow{Busy: r.Busy, Cells: []string{
-				cmpName(r.Model, installed, known), r.Time.UTC().Format("2006-01-02 15:04 UTC"),
-				fmtSecs(r.WarmTotalSec), vs, fmtSecs(r.ColdLoadSec), cmpLoadSpeed(r), mem, cmpSplit(r),
-				fmt.Sprintf("%d numbers", r.VectorLength), cmpBusy(r),
-			}}) // end of the row
-		} // end of the model loop
-		// Keep the table.
-		p.Tables = append(p.Tables, t)
-	} // end of the embedding table
-	// Sentences read out of the text models.
-	p.Findings = append(p.Findings, textFindings(texts)...)
-	// Sentences read out of the embedding models.
-	p.Findings = append(p.Findings, embedFindings(embeds)...)
-	// The standing cautions.
-	p.Notes = append(p.Notes,
-		"Only the latest test of each model is shown. Tests made under different machine conditions are not exactly comparable; the last column marks tests made on a busy machine.",
-		"Models of different sizes are not a fair race: a bigger model is expected to be slower. \"Speed per GB of memory\" and \"Speed vs fastest\" are guides, not verdicts.",
-		"\"Words per second\" is a rough guess (tokens × 0.75). \"Load speed from disk\" is the model size divided by the cold load time; it also includes start-up work, and a model that was still in the computer's file cache loads faster than a truly cold one.",
-	) // end of the standing cautions
+		// The rows.
+		for _, m := range g.Models {
+			// One row.
+			v.Rows = append(v.Rows, cmpRow{Busy: m.Run.Busy, Cells: groupRowCells(g, m)})
+			// Count the busy tests.
+			if m.Run.Busy {
+				// One more.
+				busy++
+			} // end of the busy check
+		} // end of the row loop
+		// The sentence about the group.
+		switch {
+		// A ranked group.
+		case g.Headline != "":
+			// Name the winner.
+			p.Findings = append(p.Findings, g.Title+": "+g.Headline)
+		// A group with one model.
+		case len(g.Models) == 1:
+			// Say so.
+			p.Findings = append(p.Findings, g.Title+": only one model, so there is nothing to rank yet.")
+		// A group that cannot be ranked.
+		default:
+			// Say so.
+			p.Findings = append(p.Findings, g.Title+": no ranking yet, because fewer than two models can be compared like for like.")
+		} // end of the sentence switch
+		// Keep the group.
+		p.Groups = append(p.Groups, v)
+	} // end of the group loop
+	// The standing caution.
+	p.Notes = append(p.Notes, "Only the latest test of each model is shown. A row marked with a caution is shown for information but is not ranked.")
 	// Models left out because of another prompt.
 	if skipped > 0 {
 		// The note.
@@ -361,154 +408,63 @@ func buildCompare(runs []perfRun, skipped int, installed map[string]bool, known
 	return p
 } // end of buildCompare
 
-// textFindings reads plain sentences out of the text-model runs (sorted by answer speed, fastest first).
-func textFindings(texts []perfRun) []string {
-	// With fewer than two models there is nothing to compare.
-	if len(texts) < 2 {
-		// Say what is missing.
-		return []string{"Only one text model has been tested. Test another one to compare."}
-	} // end of the count check
-	// The sentences.
-	var out []string
-	// The fastest and the slowest writer, among models with a figure.
-	var fast, slow *perfRun
-	// Look for them.
-	for i := range texts {
-		// A model with no figure cannot be ranked.
-		if texts[i].AnswerSpeed <= 0 {
-			// Skip it.
-			continue
-		} // end of the check
-		// The first one found is the fastest, because the list is sorted.
-		if fast == nil {
-			// Remember it.
-			fast = &texts[i]
-		} // end of the fastest check
-		// The last one found is the slowest.
-		slow = &texts[i]
-	} // end of the loop
-	// Two different models with a figure.
-	if fast != nil && slow != nil && fast != slow {
-		// The sentence.
-		out = append(out, fmt.Sprintf("%s writes fastest: %.1f tokens/s (about %.0f words per second). %s is the slowest at %.1f tokens/s, %.1f× slower.",
-			fast.Model, fast.AnswerSpeed, fast.AnswerSpeed*wordsPerToken, slow.Model, slow.AnswerSpeed, fast.AnswerSpeed/slow.AnswerSpeed))
-	} // end of the speed sentence
-	// The quickest and the slowest to load.
-	var quick, tardy *perfRun
-	// Look for them.
-	for i := range texts {
-		// A model with no figure cannot be ranked.
-		if texts[i].ColdLoadSec <= 0 {
-			// Skip it.
-			continue
-		} // end of the check
-		// The first candidate for both.
-		if quick == nil || texts[i].ColdLoadSec < quick.ColdLoadSec {
-			// The quicker one.
-			quick = &texts[i]
-		} // end of the quick check
-		// The slower one.
-		if tardy == nil || texts[i].ColdLoadSec > tardy.ColdLoadSec {
-			// The slowest one.
-			tardy = &texts[i]
-		} // end of the tardy check
-	} // end of the loop
-	// Two different models with a figure.
-	if quick != nil && tardy != nil && quick != tardy {
-		// The sentence.
-		out = append(out, fmt.Sprintf("%s loads quickest (%s from cold); %s needs %s.", quick.Model, fmtSecs(quick.ColdLoadSec), tardy.Model, fmtSecs(tardy.ColdLoadSec)))
-	} // end of the load sentence
-	// The model that uses the least memory, and the model that gives the most speed for its memory.
-	var small, thrifty *perfRun
-	// Look for them.
-	for i := range texts {
-		// A model with no size cannot be ranked.
-		if texts[i].ModelBytes <= 0 {
-			// Skip it.
-			continue
-		} // end of the check
-		// The smallest.
-		if small == nil || texts[i].ModelBytes < small.ModelBytes {
-			// Remember it.
-			small = &texts[i]
-		} // end of the small check
-		// A model with no speed cannot be thrifty.
-		if texts[i].AnswerSpeed <= 0 {
-			// Skip it.
-			continue
-		} // end of the speed check
-		// The most speed for each gigabyte.
-		if thrifty == nil || texts[i].AnswerSpeed/cmpGB(texts[i].ModelBytes) > thrifty.AnswerSpeed/cmpGB(thrifty.ModelBytes) {
-			// Remember it.
-			thrifty = &texts[i]
-		} // end of the thrifty check
-	} // end of the loop
-	// The memory sentence.
-	if small != nil {
-		// The sentence.
-		s := fmt.Sprintf("%s uses the least memory (%s).", small.Model, formatSize(small.ModelBytes))
-		// Add the thrifty model when it is another one.
-		if thrifty != nil && thrifty != small {
-			// The addition.
-			s += fmt.Sprintf(" %s gives the most speed for its memory (%.1f tokens/s per GB).", thrifty.Model, thrifty.AnswerSpeed/cmpGB(thrifty.ModelBytes))
-		} else if thrifty != nil {
-			// The same model.
-			s += fmt.Sprintf(" It also gives the most speed for its memory (%.1f tokens/s per GB).", thrifty.AnswerSpeed/cmpGB(thrifty.ModelBytes))
-		} // end of the thrifty check
-		// Keep it.
-		out = append(out, s)
-	} // end of the memory sentence
-	// Models that do not fit fully on the graphics card.
-	var spill []string
-	// Look for them.
-	for _, r := range texts {
-		// A known size and part of it outside the graphics card.
-		if r.ModelBytes > 0 && r.GPUBytes < r.ModelBytes {
-			// Name it.
-			spill = append(spill, r.Model)
-		} // end of the check
+// gatherCompare reads the saved tests and the installed models and builds the page; the page, the PDF and the CSV all come from here, so they can never disagree.
+func gatherCompare(r *http.Request, addr ollamaAddress, store *perfStore) comparePage {
+	// What Ollama has now: its details tell the size and precision of every model that is still installed (an error only means the "no longer installed" note is left out).
+	installed := map[string]modelDetails{}
+	// Read them.
+	list, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
+	// Fill the map.
+	for _, m := range list {
+		// One model.
+		installed[m.Name] = m.Details
 	} // end of the loop
-	// The sentence.
-	if len(spill) > 0 {
-		// Say which ones.
-		out = append(out, "Not fully on the graphics card (so slower than they could be): "+strings.Join(spill, ", ")+".")
-	} // end of the spill sentence
-	// Hand them back.
-	return out
-} // end of textFindings
+	// The latest runs.
+	runs, skipped := store.latestRuns(perfPromptVersion)
+	// Build the page.
+	data := buildCompare(runs, skipped, installed, err == nil)
+	// Where the figures live.
+	path, note := store.where()
+	// A file, or the reason there is none.
+	if path != "" {
+		// Say where.
+		data.SaveNote = "The figures come from " + path + "."
+	} else {
+		// The reason.
+		data.SaveNote = note
+	} // end of the path check
+	// Hand it back.
+	return data
+} // end of gatherCompare
 
-// embedFindings reads plain sentences out of the embedding-model runs (sorted by time, shortest first).
-func embedFindings(embeds []perfRun) []string {
-	// With fewer than two models there is nothing to compare, and no sentence is needed for none at all.
-	if len(embeds) < 2 {
-		// Nothing to say; the table speaks for itself.
-		return nil
-	} // end of the count check
-	// The fastest and the slowest embedder, among models with a figure.
-	var fast, slow *perfRun
-	// Look for them.
-	for i := range embeds {
-		// A model with no figure cannot be ranked.
-		if embeds[i].WarmTotalSec <= 0 {
-			// Skip it.
-			continue
-		} // end of the check
-		// The first one found is the fastest.
-		if fast == nil {
-			// Remember it.
-			fast = &embeds[i]
-		} // end of the fastest check
-		// The last one found is the slowest.
-		slow = &embeds[i]
-	} // end of the loop
-	// Two different models with a figure.
-	if fast != nil && slow != nil && fast != slow {
-		// The sentence.
-		return []string{fmt.Sprintf("%s embeds fastest (%s). %s needs %s, %.1f× longer.", fast.Model, fmtSecs(fast.WarmTotalSec), slow.Model, fmtSecs(slow.WarmTotalSec), slow.WarmTotalSec/fast.WarmTotalSec)}
-	} // end of the sentence check
-	// Nothing to say.
-	return nil
-} // end of embedFindings
+// compareForm runs the checks every comparison request shares (same page, small form, valid token); ok is false after a refusal was sent.
+func compareForm(w http.ResponseWriter, r *http.Request, token string) bool {
+	// Limit the size of the form.
+	r.Body = http.MaxBytesReader(w, r.Body, 1024)
+	// Only the monitor's own page may ask.
+	if !sameOrigin(r) {
+		// Refuse.
+		http.Error(w, "request did not come from this page", http.StatusForbidden)
+		// Stop here.
+		return false
+	} // end of the origin check
+	// Read the form.
+	if err := r.ParseForm(); err != nil {
+		// Refuse.
+		http.Error(w, "bad form", http.StatusBadRequest)
+		// Stop here.
+		return false
+	} // end of the form check
+	// The page token must match.
+	if !tokenValid(token, r.PostFormValue("token")) {
+		// Refuse.
+		http.Error(w, "bad token", http.StatusForbidden)
+		// Stop here.
+		return false
+	} // end of the token check
+	// All checks passed.
+	return true
+} // end of compareForm
 
 // compareHandler serves the comparison page; it only reads the saved figures and changes nothing.
 func compareHandler(addr ollamaAddress, token string, store *perfStore) http.HandlerFunc {
@@ -516,56 +472,17 @@ func compareHandler(addr ollamaAddress, token string, store *perfStore) http.Han
 	page := template.Must(template.New("compare").Parse(compareTemplateText + tipsTemplateText))
 	// The handler.
 	return func(w http.ResponseWriter, r *http.Request) {
-		// Limit the size of the form.
-		r.Body = http.MaxBytesReader(w, r.Body, 1024)
-		// Only the monitor's own page may ask.
-		if !sameOrigin(r) {
-			// Refuse.
-			http.Error(w, "request did not come from this page", http.StatusForbidden)
-			// Stop here.
-			return
-		} // end of the origin check
-		// Read the form.
-		if err := r.ParseForm(); err != nil {
-			// Refuse.
-			http.Error(w, "bad form", http.StatusBadRequest)
-			// Stop here.
-			return
-		} // end of the form check
-		// The page token must match.
-		if !tokenValid(token, r.PostFormValue("token")) {
-			// Refuse.
-			http.Error(w, "bad token", http.StatusForbidden)
-			// Stop here.
+		// The shared checks.
+		if !compareForm(w, r, token) {
+			// A refusal was sent.
 			return
-		} // end of the token check
-		// Which models Ollama has now (an error only means the "no longer installed" note is left out).
-		installed := map[string]bool{}
-		// Read them.
-		list, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
-		// Fill the set.
-		for _, m := range list {
-			// One name.
-			installed[m.Name] = true
-		} // end of the loop
-		// The latest runs.
-		runs, skipped := store.latestRuns(perfPromptVersion)
-		// Build the page.
-		data := buildCompare(runs, skipped, installed, err == nil)
+		} // end of the checks
+		// Build the page data.
+		data := gatherCompare(r, addr, store)
 		// Add what every page needs.
 		data.Theme, data.Token = themeFromRequest(r), token
 		// The saved text size, from the cookie; empty means the browser's own size.
 		data.Size = sizeFromRequest(r)
-		// Where the figures live.
-		path, note := store.where()
-		// A file, or the reason there is none.
-		if path != "" {
-			// Say where.
-			data.SaveNote = "The figures come from " + path + "."
-		} else {
-			// The reason.
-			data.SaveNote = note
-		} // end of the path check
 		// Build the page in memory first, so a template error gives a clean 500 and not a half page.
 		var buf bytes.Buffer
 		// Run the template.
diff --git a/compare_test.go b/compare_test.go
index c134894..572f5bc 100644
--- a/compare_test.go
+++ b/compare_test.go
@@ -2,6 +2,8 @@
 package main
 
 import ( // import lists the standard-library packages this file uses.
+	// html unescapes the page text before it is compared.
+	"html"
 	// net/http gives the status codes.
 	"net/http"
 	// net/url builds the form values.
@@ -16,196 +18,645 @@ import ( // import lists the standard-library packages this file uses.
 	"time"
 ) // end of imports
 
-// cmpRun builds a saved text-model run with the figures of a real test.
-func cmpRun(model string, speed, load, bytes float64, gpuAll bool, when time.Time) perfRun {
-	// The run.
-	r := perfRun{Time: when, Model: model, Kind: "generate", PromptVersion: perfPromptVersion, Runs: 3, AnswerSpeed: speed, PromptSpeed: 1000, ColdLoadSec: load, WarmFirstWordSec: 0.3, WarmTotalSec: 1.1, ModelBytes: int64(bytes)}
-	// Fully on the graphics card, or only half.
-	if gpuAll {
-		// All of it.
-		r.GPUBytes = r.ModelBytes
-	} else {
-		// Half of it.
-		r.GPUBytes = r.ModelBytes / 2
-	} // end of the memory check
-	// Hand it back.
-	return r
-} // end of cmpRun
+// cmpBase is the time of the newest test in the examples.
+var cmpBase = time.Date(2026, 10, 27, 18, 4, 0, 0, time.UTC)
+
+// okRun builds a saved chat-model run that is fair to compare: the same conditions as its neighbours, only the speed differs.
+func okRun(model string, chars float64) perfRun {
+	// The run, with figures that can be worked out by hand.
+	return perfRun{Time: cmpBase, Model: model, Kind: "generate", OllamaVersion: "0.12.0", PromptVersion: perfPromptVersion, Family: "gemma3", ParameterSize: "4.3B", Quantization: "Q4_K_M", Runs: 3, AnswerSpeed: chars / 5, CharSpeed: chars, PromptSpeed: 1000, ColdLoadSec: 3, WarmFirstWordSec: 0.3, WarmTotalSec: 1.1, TokensOut: perfAnswerTokens, AnswerChars: 320, ModelBytes: 3_800_000_000, GPUBytes: 3_800_000_000, ContextLength: 8192}
+} // end of okRun
 
-// cmpEmbed builds a saved embedding-model run.
-func cmpEmbed(model string, secs, load float64, when time.Time) perfRun {
+// embRun builds a saved embedding-model run.
+func embRun(model string, secs float64) perfRun {
 	// The run.
-	return perfRun{Time: when, Model: model, Kind: "embedding", PromptVersion: perfPromptVersion, Runs: 3, WarmTotalSec: secs, ColdLoadSec: load, VectorLength: 1536, ModelBytes: 3000000000, GPUBytes: 3000000000}
-} // end of cmpEmbed
+	return perfRun{Time: cmpBase, Model: model, Kind: "embedding", OllamaVersion: "0.12.0", PromptVersion: perfPromptVersion, ParameterSize: "1.5B", Quantization: "F16", Runs: 3, WarmTotalSec: secs, ColdLoadSec: 2, VectorLength: 1536, ModelBytes: 3_000_000_000, GPUBytes: 3_000_000_000, ContextLength: 8192}
+} // end of embRun
+
+// groupOf finds the group with the given title.
+func groupOf(t *testing.T, gs []cmpGroup, title string) cmpGroup {
+	// Mark this as a helper.
+	t.Helper()
+	// Look at each group.
+	for _, g := range gs {
+		// A match.
+		if g.Title == title {
+			// Found.
+			return g
+		} // end of the match check
+	} // end of the loop
+	// A missing group is a test failure.
+	t.Fatalf("no group %q in %v", title, groupTitles(gs))
+	// Never reached.
+	return cmpGroup{}
+} // end of groupOf
+
+// groupTitles lists the titles, for messages.
+func groupTitles(gs []cmpGroup) []string {
+	// The titles.
+	var out []string
+	// Collect them.
+	for _, g := range gs {
+		// One title.
+		out = append(out, g.Title)
+	} // end of the loop
+	// The list.
+	return out
+} // end of groupTitles
+
+// modelOf finds a model of a group by name.
+func modelOf(t *testing.T, g cmpGroup, name string) cmpModel {
+	// Mark this as a helper.
+	t.Helper()
+	// Look at each model.
+	for _, m := range g.Models {
+		// A match.
+		if m.Run.Model == name {
+			// Found.
+			return m
+		} // end of the match check
+	} // end of the loop
+	// A missing model is a test failure.
+	t.Fatalf("no model %q in %q", name, g.Title)
+	// Never reached.
+	return cmpModel{}
+} // end of modelOf
+
+// TestParamSizeParsing checks that Ollama's size labels are read in every unit and that nonsense is refused.
+func TestParamSizeParsing(t *testing.T) {
+	// The cases.
+	for _, c := range []struct {
+		// The label.
+		in string
+		// The expected billions.
+		want float64
+		// Whether it can be read.
+		ok bool
+	}{
+		// Millions.
+		{"134.52M", 0.13452, true}, {"360M", 0.36, true},
+		// Billions, with and without a fraction and with blanks and small letters.
+		{"4.3B", 4.3, true}, {"7B", 7, true}, {" 27.4b ", 27.4, true}, {"8.0B", 8, true},
+		// Thousands and trillions.
+		{"500K", 0.0005, true}, {"1.8T", 1800, true},
+		// Not readable.
+		{"", 0, false}, {"B", 0, false}, {"abcB", 0, false}, {"4.3", 0, false}, {"-4B", 0, false}, {"0B", 0, false}, {"4.3X", 0, false},
+	} {
+		// Read it.
+		got, ok := parseParamBillions(c.in)
+		// It must match.
+		if ok != c.ok || (ok && (got < c.want-1e-9 || got > c.want+1e-9)) {
+			// Report it.
+			t.Errorf("parseParamBillions(%q) = %v, %v; want %v, %v", c.in, got, ok, c.want, c.ok)
+		} // end of the check
+	} // end of the loop
+} // end of TestParamSizeParsing
+
+// TestSizeClassBoundaries checks every edge between two classes, on both sides.
+func TestSizeClassBoundaries(t *testing.T) {
+	// The cases: the label and the expected class name.
+	for label, want := range map[string]string{
+		// Tiny.
+		"134.52M": "Tiny (under 1B)", "999M": "Tiny (under 1B)",
+		// Small begins at 1B and ends below 5B.
+		"1B": "Small (1B to under 5B)", "4.3B": "Small (1B to under 5B)", "4.99B": "Small (1B to under 5B)",
+		// Medium.
+		"5B": "Medium (5B to under 12B)", "8B": "Medium (5B to under 12B)", "11.9B": "Medium (5B to under 12B)",
+		// Large.
+		"12B": "Large (12B to under 36B)", "27.4B": "Large (12B to under 36B)", "35.9B": "Large (12B to under 36B)",
+		// Extra-large.
+		"36B": "Extra-large (36B and over)", "70.6B": "Extra-large (36B and over)",
+	} {
+		// The class.
+		idx, est := classifySize(label, 0)
+		// A label gives an exact class.
+		if est || idx < 0 || sizeClassNames[idx] != want {
+			// Report it.
+			t.Errorf("classifySize(%q) = %d, %v; want %q exact", label, idx, est, want)
+		} // end of the check
+	} // end of the loop
+	// Five names for four limits.
+	if len(sizeClassNames) != len(sizeLimits)+1 {
+		// Report it.
+		t.Errorf("%d names for %d limits", len(sizeClassNames), len(sizeLimits))
+	} // end of the count check
+	// Without a label the memory figure gives a marked estimate; without both nothing is known.
+	if idx, est := classifySize("", 3_830_000_000); !est || sizeClassNames[idx] != "Medium (5B to under 12B)" {
+		// Report it.
+		t.Errorf("estimate = %d, %v", idx, est)
+	} // end of the estimate check
+	// Nothing known.
+	if idx, est := classifySize("not a size", 0); idx != classUnknown || !est {
+		// Report it.
+		t.Errorf("unknown = %d, %v", idx, est)
+	} // end of the unknown check
+} // end of TestSizeClassBoundaries
+
+// TestPrecisionOf checks the reading of Ollama's quantization levels.
+func TestPrecisionOf(t *testing.T) {
+	// The cases.
+	for q, want := range map[string]int{"Q4_K_M": 4, "Q8_0": 8, "Q5_K_S": 5, "Q6_K": 6, "Q2_K": 2, "Q3_K_L": 3, "IQ3_XS": 3, "F16": 16, "BF16": 16, "F32": 32, "MXFP4": 4, "NVFP4": 4, "FP8": 8, "q4_k_m": 4, "": 0, "weird": 0, "Q": 0, "QX": 0} {
+		// Read it.
+		bits, label := precisionOf(q)
+		// It must match.
+		if bits != want {
+			// Report it.
+			t.Errorf("precisionOf(%q) bits = %d, want %d (%q)", q, bits, want, label)
+		} // end of the check
+	} // end of the loop
+	// The label names the level.
+	if _, l := precisionOf("Q4_K_M"); l != "4-bit (Q4_K_M)" {
+		// Report it.
+		t.Errorf("label = %q", l)
+	} // end of the label check
+	// An empty level says so.
+	if _, l := precisionOf(""); l != "not reported" {
+		// Report it.
+		t.Errorf("empty label = %q", l)
+	} // end of the empty check
+} // end of TestPrecisionOf
+
+// TestRankingInsideAGroup checks that like models are ranked by characters per second, with the right comparison text, headline and order.
+func TestRankingInsideAGroup(t *testing.T) {
+	// Three models of one class and one set of conditions, given in the wrong order.
+	gs := groupRuns([]perfRun{okRun("b:4b", 200), okRun("c:4b", 100), okRun("a:4b", 300)}, nil, false)
+	// One group.
+	if len(gs) != 1 || gs[0].Title != "Chat · Small (1B to under 5B)" {
+		// Stop the test.
+		t.Fatalf("groups: %v", groupTitles(gs))
+	} // end of the group check
+	// The group.
+	g := gs[0]
+	// The order and the places.
+	for i, want := range []string{"a:4b", "b:4b", "c:4b"} {
+		// The model at this place.
+		m := g.Models[i]
+		// It must be the expected one with the expected rank.
+		if m.Run.Model != want || m.Rank != i+1 || len(m.Reasons) != 0 {
+			// Report it.
+			t.Errorf("place %d: %s rank %d reasons %v", i+1, m.Run.Model, m.Rank, m.Reasons)
+		} // end of the check
+	} // end of the loop
+	// Three ranked.
+	if g.Ranked != 3 {
+		// Report it.
+		t.Errorf("ranked = %d", g.Ranked)
+	} // end of the count check
+	// The headline.
+	if want := "a:4b writes fastest in this group (300 characters per second), compared like for like with 2 other models."; g.Headline != want {
+		// Report it.
+		t.Errorf("headline = %q", g.Headline)
+	} // end of the headline check
+	// The comparison cells: 300 against 200 is 1.5, against 100 is 3.0.
+	for i, want := range []string{"#1, fastest", "#2, 1.5× slower", "#3, 3.0× slower"} {
+		// The cell.
+		if got := cmpVsFastest(g, g.Models[i]); got != want {
+			// Report it.
+			t.Errorf("vs fastest %d = %q, want %q", i, got, want)
+		} // end of the check
+	} // end of the loop
+} // end of TestRankingInsideAGroup
+
+// TestEveryConditionKeepsAModelOutOfTheRanking checks each flag alone: the odd model gets exactly that reason and no rank, and the two others are still ranked.
+func TestEveryConditionKeepsAModelOutOfTheRanking(t *testing.T) {
+	// The cases: a change to one run and the reason it must produce.
+	cases := []struct {
+		// A name for the message.
+		name string
+		// The change.
+		mutate func(r *perfRun)
+		// The text the reason must contain.
+		want string
+	}{
+		// A different precision.
+		{"precision", func(r *perfRun) { r.Quantization = "Q8_0" }, "different precision (8-bit; most models here use 4-bit)"},
+		// Precision not reported.
+		{"precision missing", func(r *perfRun) { r.Quantization = "" }, "precision not reported"},
+		// Tested days earlier.
+		{"older test", func(r *perfRun) { r.Time = cmpBase.Add(-48 * time.Hour) }, "tested more than 12 hours before the newest test in this group"},
+		// Another Ollama version.
+		{"version", func(r *perfRun) { r.OllamaVersion = "0.11.0" }, "different Ollama version (0.11.0; most use 0.12.0)"},
+		// Another context length.
+		{"context", func(r *perfRun) { r.ContextLength = 4096 }, "different context length (4096; most use 8192)"},
+		// Part on the processor.
+		{"processor split", func(r *perfRun) { r.GPUBytes = r.ModelBytes / 2 }, "part of the model ran on the processor, not only on the graphics card"},
+		// A busy machine.
+		{"busy", func(r *perfRun) { r.Busy = true }, "the machine looked busy"},
+		// Other models loaded.
+		{"other models", func(r *perfRun) { r.OtherLoaded = []string{"x:1b"} }, "other models were loaded during the test"},
+		// A short answer.
+		{"short answer", func(r *perfRun) { r.TokensOut = 40 }, "the answer was shorter than the planned 64 tokens"},
+		// No character count.
+		{"no characters", func(r *perfRun) { r.CharSpeed = 0 }, "no character count was saved (older test): test the model again"},
+	} // end of the cases
+	// Go through them.
+	for _, c := range cases {
+		// The odd run.
+		odd := okRun("odd:4b", 250)
+		// Apply the change.
+		c.mutate(&odd)
+		// Two normal runs and the odd one.
+		gs := groupRuns([]perfRun{okRun("a:4b", 300), okRun("b:4b", 200), odd}, nil, false)
+		// The group.
+		g := groupOf(t, gs, "Chat · Small (1B to under 5B)")
+		// The odd model.
+		m := modelOf(t, g, "odd:4b")
+		// It is not ranked and has exactly the expected reason.
+		if m.Rank != 0 || len(m.Reasons) != 1 || m.Reasons[0] != c.want {
+			// Report it.
+			t.Errorf("%s: rank %d reasons %q, want only %q", c.name, m.Rank, m.Reasons, c.want)
+		} // end of the odd check
+		// The other two are ranked 1 and 2.
+		if modelOf(t, g, "a:4b").Rank != 1 || modelOf(t, g, "b:4b").Rank != 2 || g.Ranked != 2 {
+			// Report it.
+			t.Errorf("%s: the others are not ranked 1 and 2", c.name)
+		} // end of the others check
+		// The odd model is listed after the ranked ones.
+		if g.Models[2].Run.Model != "odd:4b" {
+			// Report it.
+			t.Errorf("%s: order %v", c.name, g.Models[2].Run.Model)
+		} // end of the order check
+		// The cell says no and why.
+		if cell := cmpFair(m, true); !strings.HasPrefix(cell, "⚠ No: ") || !strings.Contains(cell, c.want) {
+			// Report it.
+			t.Errorf("%s: cell %q", c.name, cell)
+		} // end of the cell check
+	} // end of the loop
+	// The twelve-hour rule has an edge: eleven hours apart is still the same sitting.
+	near := okRun("near:4b", 250)
+	// Eleven hours earlier.
+	near.Time = cmpBase.Add(-11 * time.Hour)
+	// Build.
+	g := groupRuns([]perfRun{okRun("a:4b", 300), near}, nil, false)[0]
+	// Both ranked.
+	if g.Ranked != 2 {
+		// Report it.
+		t.Errorf("11 hours apart: ranked %d, want 2", g.Ranked)
+	} // end of the edge check
+	// And thirteen is not.
+	near.Time = cmpBase.Add(-13 * time.Hour)
+	// Build.
+	g = groupRuns([]perfRun{okRun("a:4b", 300), near}, nil, false)[0]
+	// Nobody is ranked: one model is left.
+	if g.Ranked != 0 {
+		// Report it.
+		t.Errorf("13 hours apart: ranked %d, want 0", g.Ranked)
+	} // end of the second edge check
+} // end of TestEveryConditionKeepsAModelOutOfTheRanking
 
-// TestBuildCompareFigures checks every worked-out column and sentence against figures that can be done by hand.
-func TestBuildCompareFigures(t *testing.T) {
-	// A fixed time.
-	when := time.Date(2026, 10, 25, 18, 4, 0, 0, time.UTC)
-	// A quick small model, a slow big model that is partly on the processor and was measured on a busy machine, and two embedding models.
-	slow := cmpRun("qwen3.6:27b", 36, 7.03, 18.75e9, false, when)
-	// Mark the slow one busy.
-	slow.Busy, slow.BusyReason = true, "load 12 on 20 cores"
-	// The runs, in no particular order.
-	runs := []perfRun{slow, cmpRun("medgemma:latest", 80, 3.67, 3.83e9, true, when), cmpEmbed("emb-slow", 0.2, 2, when), cmpEmbed("emb-fast", 0.04, 1.86, when)}
-	// Build the page; only medgemma is installed now.
-	p := buildCompare(runs, 0, map[string]bool{"medgemma:latest": true, "emb-fast": true, "emb-slow": true}, true)
-	// Two tables.
-	if len(p.Tables) != 2 {
+// TestNoRankingWithFewerThanTwoFairModels checks the explanation when only one model of a group can be compared.
+func TestNoRankingWithFewerThanTwoFairModels(t *testing.T) {
+	// One normal model and one that ran on the processor.
+	odd := okRun("odd:4b", 250)
+	// The split.
+	odd.GPUBytes = odd.ModelBytes / 2
+	// Build.
+	gs := groupRuns([]perfRun{okRun("a:4b", 300), odd}, nil, false)
+	// The group.
+	g := gs[0]
+	// Nobody has a rank and there is no headline.
+	if g.Ranked != 0 || g.Headline != "" || g.Models[0].Rank != 0 || g.Models[1].Rank != 0 {
+		// Report it.
+		t.Errorf("ranked %d headline %q", g.Ranked, g.Headline)
+	} // end of the check
+	// The note explains.
+	if len(g.Notes) != 1 || !strings.HasPrefix(g.Notes[0], "No ranking: fewer than two models") {
+		// Report it.
+		t.Errorf("notes %v", g.Notes)
+	} // end of the note check
+	// The page says the same in its findings.
+	p := buildCompare([]perfRun{okRun("a:4b", 300), odd}, 0, nil, false)
+	// The sentence.
+	if !strings.Contains(strings.Join(p.Findings, "\n"), "Chat · Small (1B to under 5B): no ranking yet, because fewer than two models can be compared like for like.") {
+		// Report it.
+		t.Errorf("findings %v", p.Findings)
+	} // end of the findings check
+} // end of TestNoRankingWithFewerThanTwoFairModels
+
+// TestGroupsBySizeAndKind checks that models land in the right groups, in order, and that every run is in exactly one group.
+func TestGroupsBySizeAndKind(t *testing.T) {
+	// A tiny, a small, a large and an extra-large chat model, two embedding models, and three that cannot be classified exactly.
+	tiny := okRun("tiny:135m", 900)
+	// Its size.
+	tiny.ParameterSize = "134.52M"
+	// A large model.
+	large := okRun("large:27b", 90)
+	// Its size.
+	large.ParameterSize = "27.4B"
+	// An extra-large model.
+	huge := okRun("huge:70b", 30)
+	// Its size.
+	huge.ParameterSize = "70.6B"
+	// A model with no label but a memory figure: estimated.
+	guess := okRun("guess:x", 100)
+	// No label.
+	guess.ParameterSize = ""
+	// A model with nothing at all.
+	blank := okRun("blank:x", 100)
+	// No label and no memory.
+	blank.ParameterSize, blank.ModelBytes, blank.GPUBytes = "", 0, 0
+	// The runs.
+	runs := []perfRun{okRun("small:4b", 200), embRun("emb-b", 0.2), huge, tiny, blank, large, embRun("emb-a", 0.04), guess}
+	// Group them.
+	gs := groupRuns(runs, nil, false)
+	// The order: tiny, small, medium (the guess), large, extra-large, unknown, embedding.
+	want := []string{"Chat · Tiny (under 1B)", "Chat · Small (1B to under 5B)", "Chat · Medium (5B to under 12B)", "Chat · Large (12B to under 36B)", "Chat · Extra-large (36B and over)", "Chat · size not known", "Embedding models"}
+	// Compare.
+	if got := groupTitles(gs); strings.Join(got, "|") != strings.Join(want, "|") {
 		// Stop the test.
-		t.Fatalf("%d tables, want 2", len(p.Tables))
-	} // end of the table check
-	// The text table is sorted by speed: medgemma first.
-	text := p.Tables[0]
-	// The first row.
-	if !strings.HasPrefix(text.Rows[0].Cells[0], "medgemma:latest") || !strings.HasPrefix(text.Rows[1].Cells[0], "qwen3.6:27b") {
-		// Report the order.
-		t.Errorf("order: %q then %q", text.Rows[0].Cells[0], text.Rows[1].Cells[0])
+		t.Fatalf("groups = %v\nwant     %v", got, want)
 	} // end of the order check
-	// The columns of the text table match its headings.
-	for _, r := range text.Rows {
-		// One cell for each heading.
-		if len(r.Cells) != len(compareTextHeadings) || len(text.Cols) != len(compareTextHeadings) {
-			// Report the mismatch.
-			t.Fatalf("%d cells, %d columns, %d headings", len(r.Cells), len(text.Cols), len(compareTextHeadings))
+	// Every run is in exactly one group: no orphans.
+	total := 0
+	// Count them.
+	for _, g := range gs {
+		// The members.
+		total += len(g.Models)
+	} // end of the loop
+	// It must equal the number of runs.
+	if total != len(runs) {
+		// Report it.
+		t.Errorf("%d models in groups, %d runs", total, len(runs))
+	} // end of the orphan check
+	// The estimated model says so and is not ranked.
+	m := modelOf(t, groupOf(t, gs, "Chat · Medium (5B to under 12B)"), "guess:x")
+	// Its reasons and note.
+	if m.Rank != 0 || !strings.Contains(strings.Join(m.Reasons, ";"), "size class only estimated from memory use") || !strings.Contains(m.Params, "class estimated from memory use") {
+		// Report it.
+		t.Errorf("estimated model: %+v", m)
+	} // end of the estimate check
+	// The unknown model says so.
+	u := modelOf(t, groupOf(t, gs, "Chat · size not known"), "blank:x")
+	// Its reasons.
+	if !strings.Contains(strings.Join(u.Reasons, ";"), "size class unknown") || u.Params != "not reported" {
+		// Report it.
+		t.Errorf("unknown model: %+v", u)
+	} // end of the unknown check
+	// The embedding group is ranked by time, shortest first, and says "embeds fastest".
+	e := groupOf(t, gs, "Embedding models")
+	// The order and the text.
+	if e.Models[0].Run.Model != "emb-a" || e.Models[0].Rank != 1 || e.Models[1].Rank != 2 || e.Headline != "emb-a embeds fastest in this group (0.040 s), compared like for like with 1 other model." {
+		// Report it.
+		t.Errorf("embedding group: %v / %q", e.Models[0].Run.Model, e.Headline)
+	} // end of the embedding check
+	// The comparison cell of the slow embedder: 0.2 against 0.04 is 5.0.
+	if got := cmpVsFastest(e, e.Models[1]); got != "#2, 5.0× slower" {
+		// Report it.
+		t.Errorf("embedding vs fastest = %q", got)
+	} // end of the cell check
+} // end of TestGroupsBySizeAndKind
+
+// TestSingleModelGroupsNameTheirNeighbour checks the note of a model that has no peer.
+func TestSingleModelGroupsNameTheirNeighbour(t *testing.T) {
+	// A tiny model alone, and a small group of two.
+	tiny := okRun("tiny:135m", 900)
+	// Its size.
+	tiny.ParameterSize = "134.52M"
+	// A large model alone.
+	large := okRun("large:27b", 90)
+	// Its size.
+	large.ParameterSize = "27.4B"
+	// Group them.
+	gs := groupRuns([]perfRun{tiny, okRun("a:4b", 300), okRun("b:4b", 200), large}, nil, false)
+	// The tiny group's note names the small group, which is the nearest.
+	tg := groupOf(t, gs, "Chat · Tiny (under 1B)")
+	// The note.
+	if len(tg.Notes) != 1 || !strings.Contains(tg.Notes[0], "Only model in this group") || !strings.Contains(tg.Notes[0], `The nearest group is "Chat · Small (1B to under 5B)"`) || !strings.Contains(tg.Notes[0], "not ranked against each other") {
+		// Report it.
+		t.Errorf("tiny note: %v", tg.Notes)
+	} // end of the tiny check
+	// The large group's nearest is the small group (two classes away; the tiny group is three away).
+	lg := groupOf(t, gs, "Chat · Large (12B to under 36B)")
+	// The note.
+	if len(lg.Notes) != 1 || !strings.Contains(lg.Notes[0], `"Chat · Small (1B to under 5B)"`) {
+		// Report it.
+		t.Errorf("large note: %v", lg.Notes)
+	} // end of the large check
+	// A lone model with no other chat group has no neighbour sentence.
+	only := groupRuns([]perfRun{okRun("a:4b", 300)}, nil, false)[0]
+	// The note.
+	if len(only.Notes) != 1 || strings.Contains(only.Notes[0], "nearest") {
+		// Report it.
+		t.Errorf("only note: %v", only.Notes)
+	} // end of the only check
+	// The page says there is nothing to rank yet.
+	p := buildCompare([]perfRun{okRun("a:4b", 300)}, 0, nil, false)
+	// The sentence.
+	if !strings.Contains(strings.Join(p.Findings, "\n"), "only one model, so there is nothing to rank yet.") {
+		// Report it.
+		t.Errorf("findings %v", p.Findings)
+	} // end of the sentence check
+} // end of TestSingleModelGroupsNameTheirNeighbour
+
+// TestDetailsComeFromTheTestFirstThenFromOllama checks which source wins for the size and the precision.
+func TestDetailsComeFromTheTestFirstThenFromOllama(t *testing.T) {
+	// A run that saved its details, and one that did not.
+	saved := okRun("saved:x", 100)
+	// The old run has none.
+	old := okRun("old:x", 100)
+	// Clear them.
+	old.ParameterSize, old.Quantization, old.Family = "", "", ""
+	// What Ollama says now about both.
+	now := map[string]modelDetails{"saved:x": {ParameterSize: "27B", QuantizationLevel: "Q8_0", Family: "other"}, "old:x": {ParameterSize: "8B", QuantizationLevel: "Q5_K_M", Family: "llama"}}
+	// The saved details win.
+	if d := resolveDetails(saved, now); d.ParameterSize != "4.3B" || d.QuantizationLevel != "Q4_K_M" || d.Family != "gemma3" {
+		// Report it.
+		t.Errorf("saved wins: %+v", d)
+	} // end of the saved check
+	// The live details fill the gaps.
+	if d := resolveDetails(old, now); d.ParameterSize != "8B" || d.QuantizationLevel != "Q5_K_M" || d.Family != "llama" {
+		// Report it.
+		t.Errorf("live fills: %+v", d)
+	} // end of the live check
+	// A model that is gone and saved nothing has nothing.
+	if d := resolveDetails(old, nil); d.ParameterSize != "" || d.QuantizationLevel != "" {
+		// Report it.
+		t.Errorf("nothing: %+v", d)
+	} // end of the nothing check
+	// The group of the old run is the Medium class because Ollama says 8B, and it is not an estimate.
+	gs := groupRuns([]perfRun{old}, now, true)
+	// The class.
+	if gs[0].Title != "Chat · Medium (5B to under 12B)" || gs[0].Models[0].ClassEstimated {
+		// Report it.
+		t.Errorf("group %q estimated %v", gs[0].Title, gs[0].Models[0].ClassEstimated)
+	} // end of the class check
+	// A model that Ollama no longer has is named as such (only when the list was read).
+	gone := groupRuns([]perfRun{okRun("gone:4b", 100)}, map[string]modelDetails{}, true)
+	// The name.
+	if !strings.HasSuffix(gone[0].Models[0].Name, "(no longer installed)") {
+		// Report it.
+		t.Errorf("name %q", gone[0].Models[0].Name)
+	} // end of the name check
+	// And not when the list could not be read.
+	unread := groupRuns([]perfRun{okRun("gone:4b", 100)}, nil, false)
+	// The name.
+	if strings.Contains(unread[0].Models[0].Name, "no longer") {
+		// Report it.
+		t.Errorf("name %q", unread[0].Models[0].Name)
+	} // end of the second name check
+} // end of TestDetailsComeFromTheTestFirstThenFromOllama
+
+// TestCompareCellsMatchTheHeadings checks every cell against its heading with figures that can be worked out by hand.
+func TestCompareCellsMatchTheHeadings(t *testing.T) {
+	// A chat group of two and an embedding group of two.
+	p := buildCompare([]perfRun{okRun("a:4b", 300), okRun("b:4b", 200), embRun("emb-a", 0.04), embRun("emb-b", 0.2)}, 0, map[string]modelDetails{"a:4b": {}, "b:4b": {}, "emb-a": {}, "emb-b": {}}, true)
+	// Two groups.
+	if len(p.Groups) != 2 {
+		// Stop the test.
+		t.Fatalf("%d groups", len(p.Groups))
+	} // end of the count check
+	// The chat group's cells by heading.
+	chat := p.Groups[0]
+	// One cell for each heading, and the headings are the declared ones.
+	for _, r := range chat.Rows {
+		// The lengths.
+		if len(r.Cells) != len(compareTextHeadings) || len(chat.Cols) != len(compareTextHeadings) {
+			// Stop the test.
+			t.Fatalf("%d cells, %d columns, %d headings", len(r.Cells), len(chat.Cols), len(compareTextHeadings))
 		} // end of the length check
 	} // end of the loop
-	// The worked-out cells of the first row, by column heading.
+	// The expected cells of the first row.
 	want := map[string]string{
-		// 80 tokens per second.
-		"Answer speed": "80.0 tokens/s",
-		// The fastest.
-		"Speed vs fastest": "fastest",
-		// 80 times 0.75.
-		"Words per second": "about 60",
-		// 3.83 GB in 3.67 s is 1.04 GB/s.
-		"Load speed from disk": "1.0 GB/s",
-		// 80 divided by 3.83.
-		"Speed per GB of memory": "20.9 tokens/s per GB",
+		// The name.
+		"Model": "a:4b",
+		// The size label.
+		"Parameters": "4.3B",
+		// The precision.
+		"Quantization": "4-bit (Q4_K_M)",
+		// The date.
+		"Tested on": "2026-10-27 18:04 UTC",
+		// 300 divided by 5 is 60.
+		"Answer speed": "60.0 tokens/s",
+		// The characters.
+		"Characters per second": "300 chars/s",
+		// The place.
+		"Speed vs fastest": "#1, fastest",
+		// 3.8 GB in 3 s is 1.27 GB/s.
+		"Load speed from disk": "1.3 GB/s",
 		// All on the graphics card.
 		"Processor split": "100% graphics card, 0% processor",
 		// A calm machine.
 		"Machine busy": "no",
-		// The date.
-		"Tested on": "2026-10-25 18:04 UTC",
+		// Fair.
+		"Fair to rank?": "✓ Yes",
 	} // end of the expectations
-	// Check the first row.
+	// Check them.
 	for i, h := range compareTextHeadings {
+		// The heading must match the bubble.
+		if chat.Cols[i].Title != h {
+			// Report it.
+			t.Errorf("column %d is %q, want %q", i, chat.Cols[i].Title, h)
+		} // end of the title check
 		// A heading with an expectation.
-		if w, ok := want[h]; ok && text.Rows[0].Cells[i] != w {
+		if w, ok := want[h]; ok && chat.Rows[0].Cells[i] != w {
 			// Report it.
-			t.Errorf("medgemma %q = %q, want %q", h, text.Rows[0].Cells[i], w)
-		} // end of the check
+			t.Errorf("%q = %q, want %q", h, chat.Rows[0].Cells[i], w)
+		} // end of the cell check
 	} // end of the loop
-	// The worked-out cells of the second row.
-	want2 := map[string]string{
-		// 80 divided by 36 is 2.2.
-		"Speed vs fastest": "2.2× slower",
-		// 36 times 0.75.
-		"Words per second": "about 27",
-		// 18.75 GB in 7.03 s is 2.67 GB/s.
-		"Load speed from disk": "2.7 GB/s",
-		// 36 divided by 18.75.
-		"Speed per GB of memory": "1.9 tokens/s per GB",
-		// Half on the graphics card.
-		"Processor split": "50% graphics card, 50% processor",
-		// Busy, with the reason.
-		"Machine busy": "yes: load 12 on 20 cores",
-		// Not installed any more.
-	} // end of the expectations
-	// Check the second row.
-	for i, h := range compareTextHeadings {
+	// The embedding group has its own headings.
+	emb := p.Groups[1]
+	// The lengths.
+	for _, r := range emb.Rows {
+		// One cell for each heading.
+		if len(r.Cells) != len(compareEmbedHeadings) || len(emb.Cols) != len(compareEmbedHeadings) {
+			// Stop the test.
+			t.Fatalf("%d cells, %d columns, %d headings", len(r.Cells), len(emb.Cols), len(compareEmbedHeadings))
+		} // end of the length check
+	} // end of the loop
+	// The slow embedder's cells.
+	slow := map[string]string{"Embedding time": "0.200 s", "Speed vs fastest": "#2, 5.0× slower", "Vector length": "1536 numbers", "Quantization": "16-bit (F16)", "Fair to rank?": "✓ Yes"}
+	// Check them.
+	for i, h := range compareEmbedHeadings {
 		// A heading with an expectation.
-		if w, ok := want2[h]; ok && text.Rows[1].Cells[i] != w {
+		if w, ok := slow[h]; ok && emb.Rows[1].Cells[i] != w {
 			// Report it.
-			t.Errorf("qwen %q = %q, want %q", h, text.Rows[1].Cells[i], w)
-		} // end of the check
-	} // end of the loop
-	// The busy row is marked, the calm one is not.
-	if !text.Rows[1].Busy || text.Rows[0].Busy {
-		// Report it.
-		t.Errorf("busy marks wrong")
-	} // end of the busy check
-	// The model that Ollama no longer has is named as such.
-	if !strings.Contains(text.Rows[1].Cells[0], "(no longer installed)") || strings.Contains(text.Rows[0].Cells[0], "no longer") {
-		// Report it.
-		t.Errorf("installed marks wrong: %q / %q", text.Rows[0].Cells[0], text.Rows[1].Cells[0])
-	} // end of the installed check
-	// The embedding table is sorted by time: the fast one first, and the slow one is 5.0 times longer.
-	emb := p.Tables[1]
-	// The order and the comparison.
-	if emb.Rows[0].Cells[0] != "emb-fast" || emb.Rows[0].Cells[3] != "fastest" || emb.Rows[1].Cells[3] != "5.0× slower" {
-		// Report it.
-		t.Errorf("embedding rows: %v / %v", emb.Rows[0].Cells, emb.Rows[1].Cells)
-	} // end of the embedding check
-	// The sentences read out of the figures.
-	all := strings.Join(p.Findings, "\n")
-	// Each must be present.
-	for _, w := range []string{
-		// The fastest writer and the slowest.
-		"medgemma:latest writes fastest: 80.0 tokens/s (about 60 words per second). qwen3.6:27b is the slowest at 36.0 tokens/s, 2.2× slower.",
-		// The load sentence.
-		"medgemma:latest loads quickest (3.67 s from cold); qwen3.6:27b needs 7.03 s.",
-		// The memory sentence: the small model is also the thrifty one.
-		"medgemma:latest uses the least memory (3.8 GB). It also gives the most speed for its memory (20.9 tokens/s per GB).",
-		// The partly-on-processor warning.
-		"Not fully on the graphics card (so slower than they could be): qwen3.6:27b.",
-		// The embedding sentence.
-		"emb-fast embeds fastest (0.040 s). emb-slow needs 0.200 s, 5.0× longer.",
-	} {
-		// Look for it.
-		if !strings.Contains(all, w) {
-			// Report the gap.
-			t.Errorf("findings lack %q\n%s", w, all)
-		} // end of the check
+			t.Errorf("embedding %q = %q, want %q", h, emb.Rows[1].Cells[i], w)
+		} // end of the cell check
 	} // end of the loop
-	// The notes warn about the busy test.
-	if !strings.Contains(strings.Join(p.Notes, "\n"), "1 of the shown test(s) were made while the machine looked busy") {
-		// Report it.
-		t.Errorf("no busy note: %v", p.Notes)
-	} // end of the note check
-} // end of TestBuildCompareFigures
+	// The tooltips of the headings are unique on the page.
+	seen := map[string]bool{}
+	// Go through all of them.
+	for _, g := range p.Groups {
+		// Every column.
+		for _, c := range g.Cols {
+			// A repeat.
+			if seen[c.ID] {
+				// Report it.
+				t.Errorf("element name %s appears twice", c.ID)
+			} // end of the repeat check
+			// Remember it.
+			seen[c.ID] = true
+		} // end of the column loop
+	} // end of the group loop
+} // end of TestCompareCellsMatchTheHeadings
 
-// TestBuildCompareEdges checks the cases with no figures, one model, and an old prompt.
+// TestBuildCompareEdges checks the cases with no figures and with an old prompt.
 func TestBuildCompareEdges(t *testing.T) {
-	// Nothing saved.
-	if p := buildCompare(nil, 0, nil, false); !p.Empty || len(p.Tables) != 0 {
+	// Nothing saved: the page still carries the notice.
+	p := buildCompare(nil, 0, nil, false)
+	// Empty, no groups, and the notice.
+	if !p.Empty || len(p.Groups) != 0 || p.NoticeShort != noticeShort || len(p.NoticeFull) != len(noticeFull) {
 		// Report it.
 		t.Errorf("empty page wrong: %+v", p)
 	} // end of the empty check
-	// Nothing usable, but one model left out.
+	// Nothing usable, but two models left out.
 	if p := buildCompare(nil, 2, nil, false); !p.Empty || !strings.Contains(strings.Join(p.Notes, " "), "2 model(s) were tested with an older prompt") {
 		// Report it.
 		t.Errorf("skipped note missing: %+v", p)
 	} // end of the skipped check
-	// One text model only.
-	p := buildCompare([]perfRun{cmpRun("only:1b", 50, 2, 2e9, true, time.Now())}, 0, nil, false)
-	// A sentence asks for another test, and no "no longer installed" mark appears when the list was not read.
-	if !strings.Contains(strings.Join(p.Findings, " "), "Only one text model has been tested") || strings.Contains(p.Tables[0].Rows[0].Cells[0], "no longer") {
-		// Report it.
-		t.Errorf("single-model page wrong: %v / %q", p.Findings, p.Tables[0].Rows[0].Cells[0])
-	} // end of the single check
-	// A model with no speed figure shows plain words and never divides by zero.
-	z := cmpRun("zero:1b", 0, 0, 0, true, time.Now())
-	// Build with a normal model next to it.
-	p = buildCompare([]perfRun{cmpRun("ok:1b", 50, 2, 2e9, true, time.Now()), z}, 0, nil, false)
-	// The zero model is last and its worked-out cells are words.
-	row := p.Tables[0].Rows[1]
-	// Check the cells.
+	// A busy run gives a caution.
+	busy := okRun("a:4b", 100)
+	// Busy.
+	busy.Busy = true
+	// Build.
+	if p := buildCompare([]perfRun{busy}, 1, nil, false); !strings.Contains(strings.Join(p.Notes, "\n"), "1 of the shown test(s) were made while the machine looked busy") || !strings.Contains(strings.Join(p.Notes, "\n"), "1 model(s) were tested with an older prompt version and are left out") {
+		// Report it.
+		t.Errorf("notes: %v", p.Notes)
+	} // end of the busy check
+	// A run with no figures at all shows words and never divides by zero.
+	zero := perfRun{Time: cmpBase, Model: "zero:x", Kind: "generate", PromptVersion: perfPromptVersion}
+	// Build next to a normal one.
+	p = buildCompare([]perfRun{okRun("ok:4b", 100), zero}, 0, nil, false)
+	// Find the zero model's row.
+	var row cmpRow
+	// Go through the groups.
+	for _, g := range p.Groups {
+		// Every row.
+		for _, r := range g.Rows {
+			// The zero model.
+			if strings.HasPrefix(r.Cells[0], "zero:x") {
+				// Keep it.
+				row = r
+			} // end of the match check
+		} // end of the row loop
+	} // end of the group loop
+	// It exists, is not ranked, and its figures are words.
+	if len(row.Cells) == 0 {
+		// Stop the test.
+		t.Fatalf("no row for the zero model")
+	} // end of the existence check
+	// The cells.
 	for i, h := range compareTextHeadings {
-		// The columns that need a speed or a size.
+		// The columns that need a figure.
 		switch h {
 		// These cannot be worked out.
-		case "Words per second", "Load speed from disk", "Speed per GB of memory":
+		case "Load speed from disk":
 			// They say so.
 			if row.Cells[i] != "not available" {
 				// Report it.
 				t.Errorf("zero model %q = %q", h, row.Cells[i])
 			} // end of the check
-		// The comparison.
+		// The characters.
+		case "Characters per second":
+			// They say so.
+			if row.Cells[i] != "not saved (older test)" {
+				// Report it.
+				t.Errorf("zero model %q = %q", h, row.Cells[i])
+			} // end of the check
+		// The place.
 		case "Speed vs fastest":
-			// It says so.
-			if row.Cells[i] != "not comparable" {
+			// Not ranked.
+			if row.Cells[i] != "not ranked" {
 				// Report it.
 				t.Errorf("zero model %q = %q", h, row.Cells[i])
 			} // end of the check
@@ -218,11 +669,17 @@ func TestLatestRuns(t *testing.T) {
 	// A store in a temporary folder.
 	s := openPerfStore(filepath.Join(t.TempDir(), "performance.json"), "")
 	// An old run and a newer run of one model.
-	old := cmpRun("a:1b", 10, 1, 1e9, true, time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC))
+	old := okRun("a:1b", 10)
+	// Its time.
+	old.Time = time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
 	// The newer one.
-	newer := cmpRun("a:1b", 20, 1, 1e9, true, time.Date(2026, 10, 2, 0, 0, 0, 0, time.UTC))
+	newer := okRun("a:1b", 20)
+	// Its time.
+	newer.Time = time.Date(2026, 10, 2, 0, 0, 0, 0, time.UTC)
 	// A model whose newest run used another prompt.
-	other := cmpRun("b:1b", 30, 1, 1e9, true, time.Date(2026, 10, 3, 0, 0, 0, 0, time.UTC))
+	other := okRun("b:1b", 30)
+	// Its time.
+	other.Time = time.Date(2026, 10, 3, 0, 0, 0, 0, time.UTC)
 	// Another prompt version.
 	other.PromptVersion = "v0"
 	// Save them.
@@ -236,7 +693,7 @@ func TestLatestRuns(t *testing.T) {
 	// Ask.
 	got, skipped := s.latestRuns(perfPromptVersion)
 	// One model counts, one was skipped.
-	if len(got) != 1 || got[0].AnswerSpeed != 20 || skipped != 1 {
+	if len(got) != 1 || got[0].CharSpeed != 20 || skipped != 1 {
 		// Report it.
 		t.Errorf("latestRuns = %+v, skipped %d", got, skipped)
 	} // end of the check
@@ -247,21 +704,26 @@ func TestLatestRuns(t *testing.T) {
 	} // end of the count check
 } // end of TestLatestRuns
 
-// TestCompareRoute checks the page through the real handler: saved test runs show up, the form rules hold, and the main page has the icon.
+// TestCompareRoute checks the page through the real handler: groups, flags, method, references, notice and downloads show up, the form rules hold, and the main page has the button.
 func TestCompareRoute(t *testing.T) {
 	// A fake Ollama and a rig.
 	f := newPerfFake()
 	// Build the rig.
 	rig, _ := perfRig(t, f)
-	// Before any test the page says so.
+	// Before any test the page says so, and still carries the notice.
 	res := post(t, rig.h, "/compare", url.Values{"token": {rig.token}}, fromThisPage)
 	// The reply.
 	empty := bodyOf(res)
 	// It is a page.
-	if res.StatusCode != http.StatusOK || !strings.Contains(empty, "No model has been through a performance test yet") {
+	if res.StatusCode != http.StatusOK || !strings.Contains(empty, "No model has been through a performance test yet") || !strings.Contains(html.UnescapeString(empty), noticeShort) {
 		// Report it.
 		t.Errorf("empty page: %d", res.StatusCode)
 	} // end of the empty check
+	// No download buttons without results.
+	if strings.Contains(empty, `action="/compare/pdf"`) {
+		// Report it.
+		t.Errorf("download button on an empty page")
+	} // end of the button check
 	// Two real tests: a text model and an embedding model.
 	perfPost(t, rig, "/performance/run", "chat:1b")
 	// The embedding model.
@@ -269,25 +731,69 @@ func TestCompareRoute(t *testing.T) {
 	// Ask again.
 	res = post(t, rig.h, "/compare", url.Values{"token": {rig.token}}, fromThisPage)
 	// The reply.
-	body := bodyOf(res)
-	// Both tables, the model names, headings with bubbles, and the findings section.
-	for _, w := range []string{"Models that write text", "Embedding models", "chat:1b", "embed:1b", ">Speed vs fastest<", ">Load speed from disk<", `id="tip-cmp-t-0"`, `id="tip-cmp-e-0"`, "Only one text model has been tested", "How to read this", "Back to the monitor"} {
+	raw := bodyOf(res)
+	// The text as a person reads it.
+	body := html.UnescapeString(raw)
+	// The parts of the page.
+	for _, w := range []string{"Compare models", "Important notice.", noticeShort, "Read the full notice", `action="/compare/pdf"`, `action="/compare/csv"`, "Download this comparison (PDF)", "Download the data (CSV)", "What the figures say", "Chat · Small (1B to under 5B)", "Embedding models", "Why this group:", "chat:1b", "embed:1b", ">Fair to rank?<", ">Characters per second<", "How to read this", "How and why this comparison was done", "References", noticeTitle, "Back to the monitor", referencesChecked} {
 		// Look for it.
 		if !strings.Contains(body, w) {
 			// Report the gap.
 			t.Errorf("compare page lacks %q", w)
 		} // end of the check
 	} // end of the loop
+	// Every method answer, every reference address and the whole notice are on the page.
+	for _, h := range howRows() {
+		// The question and the answer.
+		if !strings.Contains(body, h.Question) || !strings.Contains(body, h.Answer) {
+			// Report it.
+			t.Errorf("method row missing: %q", h.Question)
+		} // end of the check
+	} // end of the method loop
+	// The references.
+	for _, r := range compareReferences {
+		// The title, the address and the sentence of use.
+		for _, w := range []string{r.Title, r.URL, r.Used} {
+			// Look for it.
+			if !strings.Contains(body, w) {
+				// Report it.
+				t.Errorf("reference %d lacks %q", r.N, w)
+			} // end of the check
+		} // end of the part loop
+	} // end of the reference loop
+	// The notice.
+	for _, para := range noticeFull {
+		// The paragraph.
+		if !strings.Contains(body, para) {
+			// Report it.
+			t.Errorf("notice paragraph missing: %.40s", para)
+		} // end of the check
+	} // end of the notice loop
+	// Every reference link opens in a new window and says so for screen readers.
+	if n := strings.Count(raw, `rel="noopener noreferrer">`+"https://"); n != len(compareReferences) {
+		// Report it.
+		t.Errorf("%d safe reference links, want %d", n, len(compareReferences))
+	} // end of the link count
+	// The words for screen readers.
+	if n := strings.Count(raw, "(opens in a new window)"); n != len(compareReferences) {
+		// Report it.
+		t.Errorf("%d new-window notes, want %d", n, len(compareReferences))
+	} // end of the screen-reader count
+	// The notice is first: before the first group.
+	if strings.Index(body, "Important notice.") > strings.Index(body, "Chat · Small") {
+		// Report it.
+		t.Errorf("the notice is not above the first group")
+	} // end of the order check
 	// No element name appears twice.
-	for _, id := range []string{`id="tip-cmp-t-0"`, `id="tip-cmp-e-0"`} {
+	for _, id := range []string{`id="tip-cmp-t0-0"`, `id="tip-cmp-e1-0"`} {
 		// Count it.
-		if strings.Count(body, id) != 1 {
+		if strings.Count(raw, id) != 1 {
 			// Report it.
-			t.Errorf("%s appears %d times", id, strings.Count(body, id))
+			t.Errorf("%s appears %d times", id, strings.Count(raw, id))
 		} // end of the count check
 	} // end of the loop
 	// The page runs no script.
-	if strings.Contains(body, "<script") {
+	if strings.Contains(raw, "<script") {
 		// Report it.
 		t.Errorf("the compare page has a script")
 	} // end of the script check
diff --git a/compgroup.go b/compgroup.go
new file mode 100644
index 0000000..c746eb0
--- /dev/null
+++ b/compgroup.go
@@ -0,0 +1,660 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// fmt builds the sentences.
+	"fmt"
+	// sort puts models in order.
+	"sort"
+	// strconv reads the number in a size label such as 4.3B.
+	"strconv"
+	// strings cleans and compares text.
+	"strings"
+	// time compares the days of two tests.
+	"time"
+) // end of imports
+
+// sizeLimits are the upper edges, in billions of parameters, of the first four size classes; they are this program's own choice, not an industry standard, and the comparison page says so.
+var sizeLimits = []float64{1, 5, 12, 36}
+
+// sizeClassNames are the five size classes, from the smallest; the number of names is one more than the number of limits.
+var sizeClassNames = []string{"Tiny (under 1B)", "Small (1B to under 5B)", "Medium (5B to under 12B)", "Large (12B to under 36B)", "Extra-large (36B and over)"}
+
+// classUnknown marks a model whose size could not be worked out at all (no label and no memory figure).
+const classUnknown = -1
+
+// bytesPerBillion is the rough memory of one billion parameters at about 4 to 5 bits plus working space; it is only used to guess a size class when Ollama gave no size label, and every guess is marked as an estimate.
+const bytesPerBillion = 0.6e9
+
+// cmpSameSittingHours is how far apart, in hours, two tests of one group may be before the older one is flagged; it is this program's own rule.
+const cmpSameSittingHours = 12
+
+// parseParamBillions reads an Ollama size label such as 4.3B, 134.52M or 27.4B and returns the number of parameters in billions; false means the label could not be read.
+func parseParamBillions(label string) (float64, bool) {
+	// Remove blanks and use capital letters.
+	l := strings.ToUpper(strings.TrimSpace(label))
+	// An empty label has no size.
+	if len(l) < 2 {
+		// Not readable.
+		return 0, false
+	} // end of the length check
+	// The last letter says the unit.
+	unit := l[len(l)-1]
+	// The number in front of it.
+	num, err := strconv.ParseFloat(strings.TrimSpace(l[:len(l)-1]), 64)
+	// Not a number, or not a size.
+	if err != nil || num <= 0 {
+		// Not readable.
+		return 0, false
+	} // end of the number check
+	// Turn the unit into billions.
+	switch unit {
+	// Thousands.
+	case 'K':
+		// A thousand is a millionth of a billion.
+		return num / 1e6, true
+	// Millions.
+	case 'M':
+		// A million is a thousandth of a billion.
+		return num / 1e3, true
+	// Billions.
+	case 'B':
+		// Already billions.
+		return num, true
+	// Trillions.
+	case 'T':
+		// A trillion is a thousand billions.
+		return num * 1e3, true
+	} // end of the unit switch
+	// An unknown unit.
+	return 0, false
+} // end of parseParamBillions
+
+// sizeClassOf returns the index of the size class for a number of billions of parameters.
+func sizeClassOf(billions float64) int {
+	// Count the limits that the size has reached.
+	idx := 0
+	// Go through the limits.
+	for _, lim := range sizeLimits {
+		// At or above the limit: one class higher.
+		if billions >= lim {
+			// Next class.
+			idx++
+		} // end of the limit check
+	} // end of the loop
+	// The class.
+	return idx
+} // end of sizeClassOf
+
+// classifySize returns the size class of a model: from the size label when there is one, otherwise a guess from its memory figure (marked as estimated), otherwise classUnknown.
+func classifySize(label string, memBytes int64) (idx int, estimated bool) {
+	// An exact label wins.
+	if b, ok := parseParamBillions(label); ok {
+		// The class, not estimated.
+		return sizeClassOf(b), false
+	} // end of the label check
+	// Without a label, the memory figure gives a rough guess.
+	if memBytes > 0 {
+		// The class of the guessed size, marked as an estimate.
+		return sizeClassOf(float64(memBytes) / bytesPerBillion), true
+	} // end of the memory check
+	// Nothing to go on.
+	return classUnknown, true
+} // end of classifySize
+
+// precisionOf turns an Ollama quantization level such as Q4_K_M or F16 into its nominal number of bits and a short label; zero bits means it was not reported or not understood.
+func precisionOf(quant string) (int, string) {
+	// Clean the text.
+	q := strings.ToUpper(strings.TrimSpace(quant))
+	// Nothing reported.
+	if q == "" {
+		// Say so.
+		return 0, "not reported"
+	} // end of the empty check
+	// The formats that name their bits directly.
+	switch {
+	// Full 32-bit floating point.
+	case strings.HasPrefix(q, "F32"):
+		// 32 bits.
+		return 32, "32-bit (" + quant + ")"
+	// 16-bit floating point, in either flavour.
+	case strings.HasPrefix(q, "F16"), strings.HasPrefix(q, "BF16"):
+		// 16 bits.
+		return 16, "16-bit (" + quant + ")"
+	// The 4-bit floating-point formats.
+	case strings.HasPrefix(q, "MXFP4"), strings.HasPrefix(q, "NVFP4"), strings.HasPrefix(q, "FP4"):
+		// 4 bits.
+		return 4, "4-bit (" + quant + ")"
+	// The 8-bit floating-point format.
+	case strings.HasPrefix(q, "FP8"):
+		// 8 bits.
+		return 8, "8-bit (" + quant + ")"
+	} // end of the direct formats
+	// The Q and IQ families: the digit after the letters is the nominal number of bits.
+	rest := q
+	// The IQ family.
+	if strings.HasPrefix(rest, "IQ") {
+		// Drop the two letters.
+		rest = rest[2:]
+	} else if strings.HasPrefix(rest, "Q") {
+		// Drop the one letter.
+		rest = rest[1:]
+	} else {
+		// Not a family this program knows.
+		return 0, "not recognised (" + quant + ")"
+	} // end of the family check
+	// The first character must be a digit from 1 to 9.
+	if len(rest) > 0 && rest[0] >= '1' && rest[0] <= '9' {
+		// The number of bits.
+		bits := int(rest[0] - '0')
+		// The label.
+		return bits, fmt.Sprintf("%d-bit (%s)", bits, quant)
+	} // end of the digit check
+	// A family name without a digit.
+	return 0, "not recognised (" + quant + ")"
+} // end of precisionOf
+
+// cmpModel is one tested model inside a comparison group.
+type cmpModel struct {
+	// Run is the saved test.
+	Run perfRun
+	// Name is the model name, with a note when Ollama no longer has the model.
+	Name string
+	// Params is the size label, or a note that it is estimated or unknown.
+	Params string
+	// ClassIdx is the size class (classUnknown when nothing is known); embedding models do not use it.
+	ClassIdx int
+	// ClassEstimated is true when the class was guessed from memory use.
+	ClassEstimated bool
+	// Quant is the quantization label with its nominal bits.
+	Quant string
+	// Bits is the nominal number of bits (zero when unknown).
+	Bits int
+	// Reasons are the cautions that keep the model out of the ranking; empty means it can be ranked.
+	Reasons []string
+	// Rank is the place in the like-for-like ranking, or zero when the model is not ranked.
+	Rank int
+} // end of cmpModel
+
+// cmpGroup is one comparison group: models that may be compared with each other.
+type cmpGroup struct {
+	// Title is the heading, for example "Chat · Small (1B to under 5B)".
+	Title string
+	// Why says in plain words why these models are compared together, with reference markers.
+	Why string
+	// Embedding is true for the group of embedding models.
+	Embedding bool
+	// ClassIdx is the size class of a chat group.
+	ClassIdx int
+	// Models are the members, ranked ones first.
+	Models []cmpModel
+	// Ranked is how many models have a place in the ranking (zero or at least two).
+	Ranked int
+	// Headline is the sentence about the fastest model, or empty when there is no ranking.
+	Headline string
+	// Notes are extra sentences: why there is no ranking, or that the model has no peer.
+	Notes []string
+} // end of cmpGroup
+
+// modeInt returns the most common value among the numbers above zero; ties go to the higher number; zero when there are none.
+func modeInt(vals []int64) int64 {
+	// Count each value.
+	count := map[int64]int{}
+	// Go through the values.
+	for _, v := range vals {
+		// Zero means not reported.
+		if v > 0 {
+			// Count it.
+			count[v]++
+		} // end of the check
+	} // end of the loop
+	// The best value so far.
+	var best int64
+	// Its count.
+	bestN := 0
+	// Look at each counted value.
+	for v, n := range count {
+		// More common, or equally common and higher.
+		if n > bestN || (n == bestN && v > best) {
+			// Keep it.
+			best, bestN = v, n
+		} // end of the comparison
+	} // end of the loop
+	// The mode.
+	return best
+} // end of modeInt
+
+// modeString returns the most common non-empty text; ties go to the text that sorts last (so the newer version wins); empty when there is none.
+func modeString(vals []string) string {
+	// Count each value.
+	count := map[string]int{}
+	// Go through the values.
+	for _, v := range vals {
+		// Empty means not reported.
+		if v != "" {
+			// Count it.
+			count[v]++
+		} // end of the check
+	} // end of the loop
+	// The best value so far.
+	best := ""
+	// Its count.
+	bestN := 0
+	// Look at each counted value.
+	for v, n := range count {
+		// More common, or equally common and later in order.
+		if n > bestN || (n == bestN && v > best) {
+			// Keep it.
+			best, bestN = v, n
+		} // end of the comparison
+	} // end of the loop
+	// The mode.
+	return best
+} // end of modeString
+
+// resolveDetails picks what is known about a model: the details saved with the test come first, then what Ollama reports now.
+func resolveDetails(r perfRun, installed map[string]modelDetails) modelDetails {
+	// What the test saved.
+	d := modelDetails{Family: r.Family, ParameterSize: r.ParameterSize, QuantizationLevel: r.Quantization}
+	// A model that is still installed fills the gaps.
+	if now, ok := installed[r.Model]; ok {
+		// A missing size label.
+		if d.ParameterSize == "" {
+			// Use the live one.
+			d.ParameterSize = now.ParameterSize
+		} // end of the size check
+		// A missing quantization.
+		if d.QuantizationLevel == "" {
+			// Use the live one.
+			d.QuantizationLevel = now.QuantizationLevel
+		} // end of the quantization check
+		// A missing family.
+		if d.Family == "" {
+			// Use the live one.
+			d.Family = now.Family
+		} // end of the family check
+	} // end of the installed check
+	// What is known.
+	return d
+} // end of resolveDetails
+
+// speedKey is the figure a model is ranked by: characters per second for a chat model (higher is better), embedding time for an embedding model (lower is better, so it is negated to make higher better).
+func speedKey(r perfRun) float64 {
+	// An embedding model: the shorter time wins; a missing time is the worst.
+	if r.Kind == "embedding" {
+		// No figure.
+		if r.WarmTotalSec <= 0 {
+			// The worst possible.
+			return -1e18
+		} // end of the figure check
+		// Shorter is better.
+		return -r.WarmTotalSec
+	} // end of the embedding case
+	// A chat model: characters per second.
+	return r.CharSpeed
+} // end of speedKey
+
+// groupRuns sorts the latest runs into comparison groups, flags every condition that makes a row not comparable like for like, and ranks the models that have no flag. Every run lands in exactly one group.
+func groupRuns(runs []perfRun, installed map[string]modelDetails, known bool) []cmpGroup {
+	// The groups by key: the size class for chat models, -2 for the one group of embedding models.
+	byKey := map[int][]cmpModel{}
+	// Go through the runs.
+	for _, r := range runs {
+		// What is known about the model.
+		d := resolveDetails(r, installed)
+		// The model, with its name and notes.
+		m := cmpModel{Run: r, Name: r.Model}
+		// A model that Ollama no longer has gets a note (only when the list was read).
+		if known {
+			// Is it still there?
+			if _, ok := installed[r.Model]; !ok {
+				// Note it.
+				m.Name += " (no longer installed)"
+			} // end of the installed check
+		} // end of the known check
+		// The nominal precision.
+		m.Bits, m.Quant = precisionOf(d.QuantizationLevel)
+		// The size label to show.
+		m.Params = d.ParameterSize
+		// A chat model is grouped by size class.
+		key := -2
+		// Embedding models share one group.
+		if r.Kind != "embedding" {
+			// Work out the class.
+			m.ClassIdx, m.ClassEstimated = classifySize(d.ParameterSize, r.ModelBytes)
+			// The group key is the class.
+			key = m.ClassIdx
+		} else {
+			// The class is not used for embedding models.
+			m.ClassIdx = classUnknown
+		} // end of the kind check
+		// A size label that is empty gets a note.
+		if m.Params == "" {
+			// Say so.
+			m.Params = "not reported"
+		} // end of the label check
+		// An estimated class gets a note beside the label.
+		if m.ClassEstimated && key != classUnknown && r.Kind != "embedding" {
+			// Say that it is a guess.
+			m.Params += " (class estimated from memory use)"
+		} // end of the estimate note
+		// Put the model into its group.
+		byKey[key] = append(byKey[key], m)
+	} // end of the loop
+	// The keys in the order the groups are shown: chat classes from the smallest, then unknown, then embedding.
+	var keys []int
+	// Collect them.
+	for k := range byKey {
+		// One key.
+		keys = append(keys, k)
+	} // end of the loop
+	// Sort: classes 0..4 first, then unknown (-1), then embedding (-2).
+	sort.Slice(keys, func(i, j int) bool {
+		// A rank for each key.
+		return keyOrder(keys[i]) < keyOrder(keys[j])
+	}) // end of the sort
+	// The groups.
+	var groups []cmpGroup
+	// Build each group.
+	for _, k := range keys {
+		// The members.
+		g := buildGroup(k, byKey[k])
+		// Keep it.
+		groups = append(groups, g)
+	} // end of the loop
+	// Name the nearest neighbour of every group that has no peer, now that all groups are known.
+	for i := range groups {
+		// A group with a single model, which is not an embedding group.
+		if len(groups[i].Models) == 1 && !groups[i].Embedding {
+			// The note.
+			groups[i].Notes = append(groups[i].Notes, singleNote(groups, i))
+		} // end of the single check
+	} // end of the loop
+	// Hand them back.
+	return groups
+} // end of groupRuns
+
+// keyOrder gives the display order of a group key.
+func keyOrder(k int) int {
+	// Embedding models last.
+	if k == -2 {
+		// After everything.
+		return 1000
+	} // end of the embedding check
+	// Unknown size just before them.
+	if k == classUnknown {
+		// After the classes.
+		return 900
+	} // end of the unknown check
+	// The classes in their own order.
+	return k
+} // end of keyOrder
+
+// groupTitle writes the heading of a group.
+func groupTitle(key int) string {
+	// The embedding group.
+	if key == -2 {
+		// Its name.
+		return "Embedding models"
+	} // end of the embedding check
+	// Unknown size.
+	if key == classUnknown {
+		// Its name.
+		return "Chat · size not known"
+	} // end of the unknown check
+	// A size class.
+	return "Chat · " + sizeClassNames[key]
+} // end of groupTitle
+
+// groupWhy writes the plain-words reason that the models of a group are compared together; the numbers in brackets point to the reference list.
+func groupWhy(key int) string {
+	// Embedding models.
+	if key == -2 {
+		// Why they are separate.
+		return "Embedding models produce numbers, not text, and are benchmarked on their own tasks, so they are never ranked against chat models [6]. They are compared on the time they need for the same fixed text, under the same conditions [1][2]."
+	} // end of the embedding case
+	// Unknown size.
+	if key == classUnknown {
+		// Why this group exists.
+		return "Ollama did not report a size for these models and no memory figure was saved, so they cannot be placed in a size class. They are listed so that none is left out, but they are not ranked."
+	} // end of the unknown case
+	// A size class.
+	return "These are chat models of the same size class. A bigger model is expected to be slower, so models are compared only with models of similar size, run with the same prompt, answer length and settings [1][2]. The size-class limits are this program's own choice, not an industry standard."
+} // end of groupWhy
+
+// buildGroup turns the models of one group into a ranked group.
+func buildGroup(key int, models []cmpModel) cmpGroup {
+	// The group.
+	g := cmpGroup{Title: groupTitle(key), Why: groupWhy(key), Embedding: key == -2, ClassIdx: key}
+	// The reference conditions are the most common ones in the group.
+	var bits, ctx []int64
+	// The versions as text.
+	var vers []string
+	// The newest test.
+	var newest time.Time
+	// Collect them.
+	for _, m := range models {
+		// The precision.
+		bits = append(bits, int64(m.Bits))
+		// The context length.
+		ctx = append(ctx, m.Run.ContextLength)
+		// The version.
+		vers = append(vers, m.Run.OllamaVersion)
+		// The newest time.
+		if m.Run.Time.After(newest) {
+			// Keep it.
+			newest = m.Run.Time
+		} // end of the time check
+	} // end of the loop
+	// The most common precision, version and context.
+	refBits, refCtx, refVer := int(modeInt(bits)), modeInt(ctx), modeString(vers)
+	// The label of the reference precision.
+	_, refLabel := precisionOf("")
+	// Find a label for the reference bits from a model that has them.
+	for _, m := range models {
+		// A model with the reference precision.
+		if m.Bits == refBits && refBits > 0 {
+			// Its label, without the exact level, so the sentence reads well.
+			refLabel = fmt.Sprintf("%d-bit", refBits)
+			// Done.
+			break
+		} // end of the match
+	} // end of the loop
+	// Flag the conditions of every model.
+	for i := range models {
+		// A pointer keeps the changes.
+		m := &models[i]
+		// The conditions.
+		m.Reasons = reasonsFor(*m, key == -2, refBits, refLabel, refCtx, refVer, newest)
+	} // end of the loop
+	// The models without a flag can be ranked.
+	var fair []int
+	// Find them.
+	for i := range models {
+		// No reasons.
+		if len(models[i].Reasons) == 0 {
+			// Keep the index.
+			fair = append(fair, i)
+		} // end of the check
+	} // end of the loop
+	// Rank by speed, best first; a stable sort keeps the saved order for ties.
+	sort.SliceStable(fair, func(a, b int) bool { return speedKey(models[fair[a]].Run) > speedKey(models[fair[b]].Run) })
+	// A ranking needs at least two models that can be compared.
+	if len(fair) >= 2 {
+		// Number them.
+		for place, idx := range fair {
+			// Place 1 is the best.
+			models[idx].Rank = place + 1
+		} // end of the loop
+		// How many are ranked.
+		g.Ranked = len(fair)
+	} // end of the ranking
+	// Put the ranked models first, then the others by speed and name.
+	sort.SliceStable(models, func(a, b int) bool {
+		// Both ranked: by place.
+		if models[a].Rank > 0 && models[b].Rank > 0 {
+			// Lower place first.
+			return models[a].Rank < models[b].Rank
+		} // end of the both-ranked case
+		// A ranked model goes before an unranked one.
+		if (models[a].Rank > 0) != (models[b].Rank > 0) {
+			// The ranked one first.
+			return models[a].Rank > 0
+		} // end of the mixed case
+		// Both unranked: faster first.
+		if speedKey(models[a].Run) != speedKey(models[b].Run) {
+			// Higher is better.
+			return speedKey(models[a].Run) > speedKey(models[b].Run)
+		} // end of the speed case
+		// Then by name.
+		return models[a].Name < models[b].Name
+	}) // end of the sort
+	// The members.
+	g.Models = models
+	// The sentence about the winner, or why there is none.
+	g.Headline, g.Notes = groupSentences(g)
+	// The group.
+	return g
+} // end of buildGroup
+
+// reasonsFor lists the conditions that make one model not comparable like for like with the rest of its group.
+func reasonsFor(m cmpModel, embedding bool, refBits int, refLabel string, refCtx int64, refVer string, newest time.Time) []string {
+	// The list.
+	var out []string
+	// The run.
+	r := m.Run
+	// A guessed or unknown size class cannot support a like-for-like claim (embedding models are not grouped by size).
+	if !embedding && m.ClassIdx == classUnknown {
+		// Unknown.
+		out = append(out, "size class unknown (no size reported and no memory figure saved)")
+	} else if !embedding && m.ClassEstimated {
+		// A guess.
+		out = append(out, "size class only estimated from memory use")
+	} // end of the size check
+	// Precision.
+	if m.Bits == 0 {
+		// Not reported.
+		out = append(out, "precision not reported")
+	} else if refBits > 0 && m.Bits != refBits {
+		// A different precision.
+		out = append(out, fmt.Sprintf("different precision (%d-bit; most models here use %s)", m.Bits, refLabel))
+	} // end of the precision check
+	// A test made long before the newest one of the group.
+	if newest.Sub(r.Time) > cmpSameSittingHours*time.Hour {
+		// Say how the rule reads.
+		out = append(out, fmt.Sprintf("tested more than %d hours before the newest test in this group", cmpSameSittingHours))
+	} // end of the time check
+	// A different Ollama version.
+	if r.OllamaVersion != "" && refVer != "" && r.OllamaVersion != refVer {
+		// Name both.
+		out = append(out, fmt.Sprintf("different Ollama version (%s; most use %s)", r.OllamaVersion, refVer))
+	} // end of the version check
+	// A different context length.
+	if r.ContextLength > 0 && refCtx > 0 && r.ContextLength != refCtx {
+		// Name both.
+		out = append(out, fmt.Sprintf("different context length (%d; most use %d)", r.ContextLength, refCtx))
+	} // end of the context check
+	// Part of the model on the processor.
+	if r.ModelBytes > 0 && r.GPUBytes < r.ModelBytes {
+		// Say so.
+		out = append(out, "part of the model ran on the processor, not only on the graphics card")
+	} // end of the split check
+	// A busy machine.
+	if r.Busy {
+		// Say so.
+		out = append(out, "the machine looked busy")
+	} // end of the busy check
+	// Other models in memory.
+	if len(r.OtherLoaded) > 0 {
+		// Say so.
+		out = append(out, "other models were loaded during the test")
+	} // end of the others check
+	// The figure the ranking needs.
+	if embedding {
+		// A missing time.
+		if r.WarmTotalSec <= 0 {
+			// Say so.
+			out = append(out, "no embedding time was saved")
+		} // end of the time figure check
+	} else {
+		// A missing character count (tests made by older versions of this program).
+		if r.CharSpeed <= 0 {
+			// Say so, and what to do.
+			out = append(out, "no character count was saved (older test): test the model again")
+		} // end of the character check
+		// An answer that ended early did less work than planned.
+		if r.TokensOut > 0 && r.TokensOut < perfAnswerTokens {
+			// Say so.
+			out = append(out, fmt.Sprintf("the answer was shorter than the planned %d tokens", perfAnswerTokens))
+		} // end of the length check
+	} // end of the figure check
+	// The list.
+	return out
+} // end of reasonsFor
+
+// groupSentences writes the headline of a group (only when it is ranked) and the notes that explain why there is no ranking.
+func groupSentences(g cmpGroup) (string, []string) {
+	// A ranked group names its fastest model.
+	if g.Ranked >= 2 {
+		// The best model is first.
+		best := g.Models[0]
+		// How many others were compared with it fairly.
+		others := g.Ranked - 1
+		// The word for the others.
+		word := "models"
+		// One other.
+		if others == 1 {
+			// Singular.
+			word = "model"
+		} // end of the word check
+		// An embedding group.
+		if g.Embedding {
+			// The sentence.
+			return fmt.Sprintf("%s embeds fastest in this group (%s), compared like for like with %d other %s.", best.Name, fmtSecs(best.Run.WarmTotalSec), others, word), nil
+		} // end of the embedding case
+		// A chat group.
+		return fmt.Sprintf("%s writes fastest in this group (%.0f characters per second), compared like for like with %d other %s.", best.Name, best.Run.CharSpeed, others, word), nil
+	} // end of the ranked case
+	// A single model has no peer.
+	if len(g.Models) == 1 {
+		// The note about the neighbour is added later, when all groups are known.
+		return "", nil
+	} // end of the single case
+	// Several models, but fewer than two that can be compared.
+	return "", []string{"No ranking: fewer than two models in this group can be compared like for like. The flags in the last column say why; \"Re-test\" the models that can be fixed by testing them again."}
+} // end of groupSentences
+
+// singleNote writes the note for a group that has one model: no peer, and which group is nearest.
+func singleNote(groups []cmpGroup, i int) string {
+	// The start of the note.
+	note := "Only model in this group, so there is no like-for-like peer yet and it is shown without a rank."
+	// The nearest other chat group by size class.
+	best, bestDist := -1, 1<<30
+	// Look at the others.
+	for j, o := range groups {
+		// Not itself, and only chat groups with a real class.
+		if j == i || o.Embedding || o.ClassIdx < 0 || groups[i].ClassIdx < 0 {
+			// Skip.
+			continue
+		} // end of the skip check
+		// The distance in classes.
+		d := o.ClassIdx - groups[i].ClassIdx
+		// Make it positive.
+		if d < 0 {
+			// Flip the sign.
+			d = -d
+		} // end of the sign check
+		// Nearer, or equally near and smaller.
+		if d < bestDist || (d == bestDist && o.ClassIdx < groups[best].ClassIdx) {
+			// Keep it.
+			best, bestDist = j, d
+		} // end of the nearest check
+	} // end of the loop
+	// A neighbour exists.
+	if best >= 0 {
+		// Name it, without ranking across groups.
+		note += " The nearest group is \"" + groups[best].Title + "\"; models of different groups are not ranked against each other."
+	} // end of the neighbour check
+	// The note.
+	return note
+} // end of singleNote
diff --git a/compreport.go b/compreport.go
new file mode 100644
index 0000000..b86c3b2
--- /dev/null
+++ b/compreport.go
@@ -0,0 +1,319 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes builds the CSV in memory.
+	"bytes"
+	// encoding/csv writes correctly quoted CSV.
+	"encoding/csv"
+	// fmt formats numbers.
+	"fmt"
+	// net/http serves the downloads.
+	"net/http"
+	// strings cleans text.
+	"strings"
+	// time stamps the files.
+	"time"
+) // end of imports
+
+// pageSymbols are the signs used on the page that the PDF's built-in font cannot draw; the words after them say the same.
+var pageSymbols = strings.NewReplacer("✓ ", "", "⚠ ", "")
+
+// footerLine is the line printed under the notice on every page of the PDF.
+func footerLine(when time.Time) string {
+	// Program, version and time.
+	return fmt.Sprintf("OllamaControlCenter %s  -  made %s", appVersion, when.UTC().Format("2006-01-02 15:04 UTC"))
+} // end of footerLine
+
+// writeComparePDF turns the comparison page into a PDF; the full notice is on the first page and again at the end, and a short notice is at the foot of every page.
+func writeComparePDF(p comparePage, when time.Time) []byte {
+	// The document.
+	d := newPDF("OllamaControlCenter model comparison", p.NoticeShort, p.NoticeShort, footerLine(when), when)
+	// The title.
+	d.text("Model comparison", 18, true, 0)
+	// The origin.
+	d.text(fmt.Sprintf("Made by OllamaControlCenter %s on %s, from tests saved on this computer.", appVersion, when.UTC().Format("2006-01-02 15:04 UTC")), 9, false, 0)
+	// A little air.
+	d.gap(6)
+	// The full notice first, so nobody reads a figure before it.
+	d.text(p.NoticeTitle, 11, true, 0)
+	// Each paragraph.
+	for _, para := range p.NoticeFull {
+		// One paragraph.
+		d.text(para, 9, false, 0)
+		// A little air.
+		d.gap(3)
+	} // end of the notice loop
+	// A line.
+	d.rule()
+	// Nothing saved.
+	if p.Empty {
+		// Say so.
+		d.text("No model has been through a performance test yet.", 10, false, 0)
+		// The finished file.
+		return d.bytes()
+	} // end of the empty check
+	// The sentences read out of the figures.
+	d.gap(4)
+	// Keep the heading with its first lines.
+	d.keep(60)
+	// The heading.
+	d.text("What the figures say", 12, true, 0)
+	// Each sentence.
+	for _, f := range p.Findings {
+		// A bullet.
+		d.text("- "+pageSymbols.Replace(f), 9, false, 8)
+	} // end of the findings loop
+	// Every group.
+	for _, g := range p.Groups {
+		// Air above the group.
+		d.gap(8)
+		// Keep the heading with the reason under it.
+		d.keep(70)
+		// Its heading.
+		d.text(g.Title, 12, true, 0)
+		// Why it exists.
+		d.text("Why this group: "+g.Why, 9, false, 0)
+		// The fastest model.
+		if g.Headline != "" {
+			// In bold.
+			d.text(g.Headline, 9, true, 0)
+		} // end of the headline check
+		// The notes.
+		for _, n := range g.Notes {
+			// One note.
+			d.text(n, 9, false, 0)
+		} // end of the note loop
+		// Every model.
+		for _, r := range g.Rows {
+			// Air between models.
+			d.gap(4)
+			// Keep the name with its figures.
+			d.keep(60)
+			// The name in bold.
+			d.text(pageSymbols.Replace(r.Cells[0]), 10, true, 0)
+			// The other columns as "heading: value".
+			var parts []string
+			// Go through the columns after the name.
+			for i := 1; i < len(r.Cells) && i < len(g.Cols); i++ {
+				// One pair.
+				parts = append(parts, g.Cols[i].Title+": "+pageSymbols.Replace(r.Cells[i]))
+			} // end of the column loop
+			// Written as one wrapped paragraph.
+			d.text(strings.Join(parts, "  |  "), 8.5, false, 8)
+		} // end of the model loop
+	} // end of the group loop
+	// The cautions.
+	d.gap(8)
+	// Keep the heading with its first line.
+	d.keep(50)
+	// The heading.
+	d.text("How to read this", 12, true, 0)
+	// Each caution.
+	for _, n := range p.Notes {
+		// A bullet.
+		d.text("- "+n, 9, false, 8)
+	} // end of the notes loop
+	// The method.
+	d.gap(8)
+	// Keep the heading with the first question.
+	d.keep(70)
+	// The heading.
+	d.text("How and why this comparison was done", 12, true, 0)
+	// Each question.
+	for _, h := range p.How {
+		// The question.
+		d.gap(3)
+		// Keep the question with the start of its answer.
+		d.keep(48)
+		// In bold.
+		d.text(h.Question, 9.5, true, 0)
+		// The answer.
+		d.text(h.Answer, 9, false, 8)
+	} // end of the method loop
+	// The references.
+	d.gap(8)
+	// Keep the heading with the first entry.
+	d.keep(70)
+	// The heading.
+	d.text("References", 12, true, 0)
+	// Each source.
+	for _, r := range p.Refs {
+		// Air.
+		d.gap(3)
+		// Keep an entry together with its first lines.
+		d.keep(36)
+		// The entry.
+		d.text(fmt.Sprintf("[%d] %s. %s. %s. %s  Used here for: %s", r.N, r.Authors, r.Title, r.Where, r.URL, r.Used), 8.5, false, 0)
+	} // end of the reference loop
+	// When they were read.
+	d.gap(3)
+	// The sentence.
+	d.text("The addresses were opened and read on "+p.RefsChecked+". A web page can change or disappear later.", 8.5, false, 0)
+	// The notice again at the end.
+	d.gap(8)
+	// Keep the line, the heading and the first paragraph together.
+	d.keep(80)
+	// A line.
+	d.rule()
+	// Its heading.
+	d.text(p.NoticeTitle, 11, true, 0)
+	// Each paragraph.
+	for _, para := range p.NoticeFull {
+		// One paragraph.
+		d.text(para, 9, false, 0)
+		// A little air.
+		d.gap(3)
+	} // end of the notice loop
+	// The finished file.
+	return d.bytes()
+} // end of writeComparePDF
+
+// csvSafe stops a spreadsheet from running a cell as a formula: a cell that starts with one of the formula signs gets a quote in front.
+func csvSafe(s string) string {
+	// Nothing to guard.
+	if s == "" {
+		// As it is.
+		return s
+	} // end of the empty check
+	// The signs that start a formula in common spreadsheets.
+	switch s[0] {
+	// Equals, plus, minus, at sign, tab or carriage return.
+	case '=', '+', '-', '@', '\t', '\r':
+		// A quote in front makes it plain text.
+		return "'" + s
+	} // end of the switch
+	// As it is.
+	return s
+} // end of csvSafe
+
+// csvHeader is the header row of the data rows in the CSV, in order.
+var csvHeader = []string{"Group", "Model", "Kind", "Parameters", "Quantization", "Tested on (UTC)", "Answer tokens per second", "Answer characters per second", "Embedding time (s)", "Time to first word (s)", "Total time (s)", "Load time (s)", "Memory used (bytes)", "Share on graphics card (%)", "Machine busy", "Rank in group", "Fair to rank", "Reasons"}
+
+// writeCompareCSV writes the comparison as CSV: the short notice first, then the header and one row for each model, then the full notice and the references. The file starts with a UTF-8 mark so spreadsheets read the characters correctly.
+func writeCompareCSV(p comparePage, when time.Time) []byte {
+	// The file.
+	var buf bytes.Buffer
+	// The UTF-8 mark.
+	buf.WriteString("\xef\xbb\xbf")
+	// The writer.
+	w := csv.NewWriter(&buf)
+	// A first record that carries the notice, so it travels with the data.
+	w.Write([]string{"NOTICE", csvSafe(p.NoticeShort)})
+	// Where the file comes from.
+	w.Write([]string{"MADE BY", "OllamaControlCenter " + appVersion + " on " + when.UTC().Format("2006-01-02 15:04 UTC")})
+	// The header row.
+	w.Write(csvHeader)
+	// Every group.
+	for _, g := range p.Data {
+		// Every model.
+		for _, m := range g.Models {
+			// The run.
+			r := m.Run
+			// The kind in words.
+			kind := "chat"
+			// An embedding model.
+			if r.Kind == "embedding" {
+				// Its kind.
+				kind = "embedding"
+			} // end of the kind check
+			// The share on the graphics card, empty when unknown.
+			gpu := ""
+			// Work it out.
+			if r.ModelBytes > 0 {
+				// A percentage.
+				gpu = fmt.Sprintf("%.0f", float64(r.GPUBytes)/float64(r.ModelBytes)*100)
+			} // end of the share check
+			// The rank, empty when not ranked.
+			rank := ""
+			// A ranked model.
+			if m.Rank > 0 {
+				// The place.
+				rank = fmt.Sprint(m.Rank)
+			} // end of the rank check
+			// Fair or not.
+			fair := "yes"
+			// A model with reasons.
+			if len(m.Reasons) > 0 {
+				// Not fair.
+				fair = "no"
+			} // end of the fair check
+			// The row; text cells are guarded against formulas.
+			w.Write([]string{csvSafe(g.Title), csvSafe(m.Name), kind, csvSafe(m.Params), csvSafe(m.Quant), r.Time.UTC().Format("2006-01-02 15:04 UTC"),
+				csvNum(r.AnswerSpeed, 2), csvNum(r.CharSpeed, 2), csvEmbedTime(r), csvNum(r.WarmFirstWordSec, 3), csvNum(r.WarmTotalSec, 3), csvNum(r.ColdLoadSec, 3),
+				fmt.Sprint(r.ModelBytes), gpu, fmt.Sprint(r.Busy), rank, fair, csvSafe(strings.Join(m.Reasons, "; "))})
+		} // end of the model loop
+	} // end of the group loop
+	// The full notice after the data.
+	for _, para := range p.NoticeFull {
+		// One paragraph.
+		w.Write([]string{"NOTICE", csvSafe(para)})
+	} // end of the notice loop
+	// The references.
+	for _, r := range p.Refs {
+		// One source.
+		w.Write([]string{"REFERENCE", fmt.Sprintf("[%d] %s. %s. %s. %s", r.N, r.Authors, r.Title, r.Where, r.URL)})
+	} // end of the reference loop
+	// Flush what is buffered.
+	w.Flush()
+	// The file.
+	return buf.Bytes()
+} // end of writeCompareCSV
+
+// csvNum writes a number with a fixed number of decimals, or nothing when it is zero (not available).
+func csvNum(v float64, decimals int) string {
+	// Not available.
+	if v <= 0 {
+		// Empty.
+		return ""
+	} // end of the check
+	// The number.
+	return fmt.Sprintf("%.*f", decimals, v)
+} // end of csvNum
+
+// csvEmbedTime writes the embedding time for an embedding model and nothing for a chat model.
+func csvEmbedTime(r perfRun) string {
+	// Only for embedding models.
+	if r.Kind != "embedding" {
+		// Empty.
+		return ""
+	} // end of the kind check
+	// The time.
+	return csvNum(r.WarmTotalSec, 3)
+} // end of csvEmbedTime
+
+// compareDownloadHandlers return the handlers of the two downloads; both run the same checks as the page and only read the saved figures.
+func compareDownloadHandlers(addr ollamaAddress, token string, store *perfStore) (http.HandlerFunc, http.HandlerFunc) {
+	// serve builds one download: the render function turns the page data into the file bytes.
+	serve := func(contentType, extension string, render func(comparePage, time.Time) []byte) http.HandlerFunc {
+		// The handler.
+		return func(w http.ResponseWriter, r *http.Request) {
+			// The shared checks.
+			if !compareForm(w, r, token) {
+				// A refusal was sent.
+				return
+			} // end of the checks
+			// The figures.
+			data := gatherCompare(r, addr, store)
+			// Nothing to download.
+			if data.Empty {
+				// Say so plainly.
+				http.Error(w, "no test results are saved yet, so there is nothing to download", http.StatusConflict)
+				// Stop here.
+				return
+			} // end of the empty check
+			// The time of the file.
+			now := time.Now().UTC()
+			// The file.
+			body := render(data, now)
+			// The type.
+			w.Header().Set("Content-Type", contentType)
+			// Ask the browser to save it, under a name that carries the time.
+			w.Header().Set("Content-Disposition", `attachment; filename="OllamaControlCenter-comparison-`+now.Format("20060102-150405Z0700")+`.`+extension+`"`)
+			// Send it.
+			w.Write(body)
+		} // end of the handler
+	} // end of serve
+	// The PDF and the CSV.
+	return serve("application/pdf", "pdf", writeComparePDF), serve("text/csv; charset=utf-8", "csv", writeCompareCSV)
+} // end of compareDownloadHandlers
diff --git a/compreport_test.go b/compreport_test.go
new file mode 100644
index 0000000..313b395
--- /dev/null
+++ b/compreport_test.go
@@ -0,0 +1,409 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes reads the CSV.
+	"bytes"
+	// encoding/csv parses the CSV the program wrote.
+	"encoding/csv"
+	// net/http gives the status codes.
+	"net/http"
+	// net/url builds the form values.
+	"net/url"
+	// regexp checks the file name.
+	"regexp"
+	// strings joins and searches text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+	// time gives a fixed time.
+	"time"
+) // end of imports
+
+// reportRuns builds the runs of the report tests: two fair chat models, one that is not fair, a lone large model and two embedding models.
+func reportRuns() []perfRun {
+	// A model that ran partly on the processor.
+	odd := okRun("odd:4b", 250)
+	// The split.
+	odd.GPUBytes = odd.ModelBytes / 2
+	// A large model.
+	large := okRun("large:27b", 90)
+	// Its size.
+	large.ParameterSize = "27.4B"
+	// The runs.
+	return []perfRun{okRun("a:4b", 300), okRun("b:4b", 200), odd, large, embRun("emb-a", 0.04), embRun("emb-b", 0.2)}
+} // end of reportRuns
+
+// TestComparePDFCarriesEverything checks the PDF: valid structure, the notice at the start, at the end and in every footer, the groups, the flags, the method and the references.
+func TestComparePDFCarriesEverything(t *testing.T) {
+	// The page data and the file.
+	when := time.Date(2026, 10, 27, 19, 30, 0, 0, time.UTC)
+	// Build.
+	p := buildCompare(reportRuns(), 0, nil, false)
+	// The file.
+	data := writeComparePDF(p, when)
+	// Validate it.
+	bodies, footers := pdfCheck(t, data)
+	// The body text.
+	body := flat(bodies)
+	// The full notice must be there twice: first page and the end.
+	for _, para := range noticeFull {
+		// Normalise the paragraph the same way.
+		want := strings.Join(strings.Fields(para), " ")
+		// Twice.
+		if n := strings.Count(body, want); n != 2 {
+			// Report it.
+			t.Errorf("notice paragraph %.40q appears %d times, want 2", want, n)
+		} // end of the count check
+	} // end of the notice loop
+	// The notice comes before any figure, on the first page.
+	first := flat(bodies[:1])
+	// The first page holds the whole notice, and it comes before the first group in reading order.
+	if !strings.Contains(first, "Nothing here limits any liability that cannot be limited by law") || strings.Index(body, "Nothing here limits any liability that cannot be limited by law") > strings.Index(body, "Chat · Small (1B to under 5B)") {
+		// Report it.
+		t.Errorf("the first page does not hold the notice before the figures")
+	} // end of the first page check
+	// A short notice and the page number in every footer.
+	for i, f := range footers {
+		// The footer text.
+		text := flat([][]pdfTextLine{f})
+		// The checks.
+		if !strings.Contains(text, noticeShort) || !strings.Contains(text, "page "+string(rune('0'+i+1))+" of ") || !strings.Contains(text, "OllamaControlCenter "+appVersion) || !strings.Contains(text, "made 2026-10-27 19:30 UTC") {
+			// Report it.
+			t.Errorf("footer of page %d: %q", i+1, text)
+		} // end of the check
+	} // end of the footer loop
+	// The content.
+	for _, w := range []string{"Model comparison", "What the figures say", "Chat · Small (1B to under 5B)", "Chat · Large (12B to under 36B)", "Embedding models", "Why this group:", "a:4b writes fastest in this group (300 characters per second)", "Characters per second: 300 chars/s", "#2, 1.5× slower", "No: part of the model ran on the processor, not only on the graphics card", "Only model in this group", "emb-a embeds fastest in this group", "How and why this comparison was done", "References", "Loïc Magne", "A web page can change or disappear later."} {
+		// Look for it.
+		if !strings.Contains(body, w) {
+			// Report it.
+			t.Errorf("PDF lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// The symbols that the font cannot draw never appear, and no stray question mark replaces one.
+	for _, bad := range []string{"✓", "⚠", "?? "} {
+		// Present.
+		if strings.Contains(body, bad) {
+			// Report it.
+			t.Errorf("PDF contains %q", bad)
+		} // end of the check
+	} // end of the loop
+	// Every method answer and every reference address is in the file.
+	for _, h := range howRows() {
+		// The question and the answer.
+		if !strings.Contains(body, h.Question) || !strings.Contains(body, strings.Join(strings.Fields(h.Answer), " ")) {
+			// Report it.
+			t.Errorf("method row missing: %q", h.Question)
+		} // end of the check
+	} // end of the method loop
+	// The references.
+	for _, r := range compareReferences {
+		// The address and the title.
+		if !strings.Contains(body, r.URL) || !strings.Contains(body, r.Title) {
+			// Report it.
+			t.Errorf("reference %d missing", r.N)
+		} // end of the check
+	} // end of the reference loop
+	// An empty comparison still gives a valid file with the notice.
+	empty := writeComparePDF(buildCompare(nil, 0, nil, false), when)
+	// Validate it.
+	eb, _ := pdfCheck(t, empty)
+	// The notice and the sentence.
+	if text := flat(eb); !strings.Contains(text, "No model has been through a performance test yet.") || !strings.Contains(text, "No warranty and no liability.") {
+		// Report it.
+		t.Errorf("empty PDF: %.80s", text)
+	} // end of the empty check
+} // end of TestComparePDFCarriesEverything
+
+// TestCompareCSV checks the CSV: the notice first, the header, one row for each model with the right figures, the notice and the references after, and the guard against formulas.
+func TestCompareCSV(t *testing.T) {
+	// A model whose name would run as a formula in a spreadsheet.
+	evil := okRun("=cmd|' /C calc'!A0", 100)
+	// The runs.
+	runs := append(reportRuns(), evil)
+	// The page data and the file.
+	when := time.Date(2026, 10, 27, 19, 30, 0, 0, time.UTC)
+	// Build.
+	data := writeCompareCSV(buildCompare(runs, 0, nil, false), when)
+	// The UTF-8 mark.
+	if !bytes.HasPrefix(data, []byte("\xef\xbb\xbf")) {
+		// Stop the test.
+		t.Fatalf("no UTF-8 mark")
+	} // end of the mark check
+	// Parse it; the records have different lengths on purpose.
+	r := csv.NewReader(bytes.NewReader(bytes.TrimPrefix(data, []byte("\xef\xbb\xbf"))))
+	// Allow rows of different length.
+	r.FieldsPerRecord = -1
+	// Read everything.
+	recs, err := r.ReadAll()
+	// It must parse.
+	if err != nil {
+		// Stop the test.
+		t.Fatalf("not valid CSV: %v", err)
+	} // end of the parse check
+	// The notice comes first, then who made it, then the header.
+	if recs[0][0] != "NOTICE" || recs[0][1] != noticeShort || recs[1][0] != "MADE BY" || !strings.Contains(recs[1][1], "2026-10-27 19:30 UTC") || strings.Join(recs[2], "|") != strings.Join(csvHeader, "|") {
+		// Stop the test.
+		t.Fatalf("start of file: %v / %v / %v", recs[0], recs[1], recs[2])
+	} // end of the start check
+	// One data row for each model.
+	rows := recs[3 : 3+len(runs)]
+	// Every row has the header's width.
+	for _, row := range rows {
+		// The width.
+		if len(row) != len(csvHeader) {
+			// Stop the test.
+			t.Fatalf("row has %d fields: %v", len(row), row)
+		} // end of the width check
+	} // end of the loop
+	// The row of a:4b by header name.
+	col := map[string]int{}
+	// Index the header.
+	for i, h := range csvHeader {
+		// One column.
+		col[h] = i
+	} // end of the loop
+	// Find a row by model name.
+	find := func(name string) []string {
+		// Look at each row.
+		for _, row := range rows {
+			// A match.
+			if row[col["Model"]] == name {
+				// Found.
+				return row
+			} // end of the match check
+		} // end of the loop
+		// A missing row is a test failure.
+		t.Fatalf("no row for %q", name)
+		// Never reached.
+		return nil
+	} // end of find
+	// The fastest model.
+	a := find("a:4b")
+	// Its figures, worked out by hand.
+	for h, want := range map[string]string{"Group": "Chat · Small (1B to under 5B)", "Kind": "chat", "Parameters": "4.3B", "Quantization": "4-bit (Q4_K_M)", "Tested on (UTC)": "2026-10-27 18:04 UTC", "Answer tokens per second": "60.00", "Answer characters per second": "300.00", "Embedding time (s)": "", "Time to first word (s)": "0.300", "Total time (s)": "1.100", "Load time (s)": "3.000", "Memory used (bytes)": "3800000000", "Share on graphics card (%)": "100", "Machine busy": "false", "Rank in group": "1", "Fair to rank": "yes", "Reasons": ""} {
+		// The cell.
+		if got := a[col[h]]; got != want {
+			// Report it.
+			t.Errorf("a:4b %q = %q, want %q", h, got, want)
+		} // end of the check
+	} // end of the loop
+	// The model that ran partly on the processor.
+	o := find("odd:4b")
+	// Not fair, no rank, half on the graphics card, with the reason.
+	if o[col["Fair to rank"]] != "no" || o[col["Rank in group"]] != "" || o[col["Share on graphics card (%)"]] != "50" || o[col["Reasons"]] != "part of the model ran on the processor, not only on the graphics card" {
+		// Report it.
+		t.Errorf("odd row: %v", o)
+	} // end of the odd check
+	// An embedding model has its time and no characters.
+	e := find("emb-a")
+	// Its cells.
+	if e[col["Kind"]] != "embedding" || e[col["Embedding time (s)"]] != "0.040" || e[col["Answer characters per second"]] != "" || e[col["Group"]] != "Embedding models" || e[col["Rank in group"]] != "1" {
+		// Report it.
+		t.Errorf("embedding row: %v", e)
+	} // end of the embedding check
+	// The formula is made harmless.
+	if got := find("'=cmd|' /C calc'!A0")[col["Model"]]; !strings.HasPrefix(got, "'=") {
+		// Report it.
+		t.Errorf("formula not guarded: %q", got)
+	} // end of the formula check
+	// After the data: the full notice and the references.
+	var notices, refs int
+	// Count them.
+	for _, rec := range recs[3+len(runs):] {
+		// Notice rows.
+		if rec[0] == "NOTICE" {
+			// Count it.
+			notices++
+		} // end of the notice check
+		// Reference rows.
+		if rec[0] == "REFERENCE" {
+			// Count it, and check it holds the address.
+			refs++
+			// The address.
+			if !strings.Contains(rec[1], compareReferences[refs-1].URL) {
+				// Report it.
+				t.Errorf("reference row %d: %q", refs, rec[1])
+			} // end of the address check
+		} // end of the reference check
+	} // end of the loop
+	// All of them.
+	if notices != len(noticeFull) || refs != len(compareReferences) {
+		// Report it.
+		t.Errorf("%d notice rows, %d reference rows", notices, refs)
+	} // end of the count check
+} // end of TestCompareCSV
+
+// TestCSVSafe checks the guard against spreadsheet formulas.
+func TestCSVSafe(t *testing.T) {
+	// The cases.
+	for in, want := range map[string]string{"=1+1": "'=1+1", "+1": "'+1", "-1": "'-1", "@x": "'@x", "\tx": "'\tx", "\rx": "'\rx", "plain": "plain", "": "", "a=b": "a=b"} {
+		// Guard it.
+		if got := csvSafe(in); got != want {
+			// Report it.
+			t.Errorf("csvSafe(%q) = %q, want %q", in, got, want)
+		} // end of the check
+	} // end of the loop
+} // end of TestCSVSafe
+
+// TestCompareDownloadRoutes checks both downloads through the real handler: the files, the headers, the form rules and the empty case.
+func TestCompareDownloadRoutes(t *testing.T) {
+	// A fake Ollama and a rig.
+	f := newPerfFake()
+	// Build the rig.
+	rig, _ := perfRig(t, f)
+	// With nothing saved there is nothing to download.
+	for _, path := range []string{"/compare/pdf", "/compare/csv"} {
+		// Ask.
+		res := post(t, rig.h, path, url.Values{"token": {rig.token}}, fromThisPage)
+		// A conflict, with a plain message.
+		if res.StatusCode != http.StatusConflict || !strings.Contains(bodyOf(res), "nothing to download") {
+			// Report it.
+			t.Errorf("%s empty = %d", path, res.StatusCode)
+		} // end of the check
+	} // end of the loop
+	// Two real tests.
+	perfPost(t, rig, "/performance/run", "chat:1b")
+	// The embedding model.
+	perfPost(t, rig, "/performance/run", "embed:1b")
+	// The PDF.
+	res := post(t, rig.h, "/compare/pdf", url.Values{"token": {rig.token}}, fromThisPage)
+	// The status and the headers.
+	if res.StatusCode != http.StatusOK || res.Header.Get("Content-Type") != "application/pdf" || res.Header.Get("X-Content-Type-Options") != "nosniff" || res.Header.Get("Cache-Control") != "no-store" {
+		// Stop the test.
+		t.Fatalf("pdf: %d %v", res.StatusCode, res.Header)
+	} // end of the pdf header check
+	// The file name carries the time.
+	if cd := res.Header.Get("Content-Disposition"); !regexp.MustCompile(`^attachment; filename="OllamaControlCenter-comparison-\d{8}-\d{6}Z\.pdf"$`).MatchString(cd) {
+		// Report it.
+		t.Errorf("content disposition %q", cd)
+	} // end of the name check
+	// The file is valid and carries the notice and the real model names.
+	bodies, _ := pdfCheck(t, []byte(bodyOf(res)))
+	// The text.
+	text := flat(bodies)
+	// The checks.
+	for _, w := range []string{"chat:1b", "embed:1b", "Chat · Small (1B to under 5B)", "Embedding models", noticeFull[1]} {
+		// Missing.
+		if !strings.Contains(text, strings.Join(strings.Fields(w), " ")) {
+			// Report it.
+			t.Errorf("downloaded PDF lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// The characters of the fake's answer were counted: 18 characters in 1.6 s is 11.25 a second, and nothing of the answer text is in the file.
+	if !strings.Contains(text, "Characters per second: 11 chars/s") || strings.Contains(text, secretText) {
+		// Report it.
+		t.Errorf("character speed or secret text: %.200s", text)
+	} // end of the characters check
+	// The CSV.
+	res = post(t, rig.h, "/compare/csv", url.Values{"token": {rig.token}}, fromThisPage)
+	// The status and the headers.
+	if res.StatusCode != http.StatusOK || res.Header.Get("Content-Type") != "text/csv; charset=utf-8" || !regexp.MustCompile(`filename="OllamaControlCenter-comparison-\d{8}-\d{6}Z\.csv"`).MatchString(res.Header.Get("Content-Disposition")) {
+		// Stop the test.
+		t.Fatalf("csv: %d %v", res.StatusCode, res.Header)
+	} // end of the csv header check
+	// It parses and starts with the notice.
+	recs, err := func() ([][]string, error) {
+		// The body without the mark.
+		b := bytes.TrimPrefix([]byte(bodyOf(res)), []byte("\xef\xbb\xbf"))
+		// Parse.
+		r := csv.NewReader(bytes.NewReader(b))
+		// Different widths are fine.
+		r.FieldsPerRecord = -1
+		// Read.
+		return r.ReadAll()
+	}()
+	// A valid file with the notice first.
+	if err != nil || recs[0][0] != "NOTICE" || recs[0][1] != noticeShort {
+		// Stop the test.
+		t.Fatalf("csv start: %v %v", err, recs[:1])
+	} // end of the csv check
+	// The refusals are the same as for the page.
+	for _, path := range []string{"/compare/pdf", "/compare/csv"} {
+		// A wrong token.
+		if res := post(t, rig.h, path, url.Values{"token": {"0123456789abcdef0123456789abcdef"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
+			// Report it.
+			t.Errorf("%s wrong token = %d", path, res.StatusCode)
+		} // end of the token check
+		// A request from another site.
+		if res := post(t, rig.h, path, url.Values{"token": {rig.token}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
+			// Report it.
+			t.Errorf("%s cross-site = %d", path, res.StatusCode)
+		} // end of the origin check
+		// A plain GET.
+		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed && status != http.StatusNotFound {
+			// Report it.
+			t.Errorf("GET %s = %d", path, status)
+		} // end of the GET check
+	} // end of the loop
+	// The page offers exactly one of each button.
+	_, _, page := func() (int, http.Header, string) {
+		// Ask for the page.
+		r := post(t, rig.h, "/compare", url.Values{"token": {rig.token}}, fromThisPage)
+		// The parts.
+		return r.StatusCode, r.Header, bodyOf(r)
+	}()
+	// Count them.
+	if strings.Count(page, `action="/compare/pdf"`) != 1 || strings.Count(page, `action="/compare/csv"`) != 1 {
+		// Report it.
+		t.Errorf("download buttons: %d / %d", strings.Count(page, `action="/compare/pdf"`), strings.Count(page, `action="/compare/csv"`))
+	} // end of the button check
+} // end of TestCompareDownloadRoutes
+
+// TestPDFNeverLeavesAHeadingAloneAtTheFootOfAPage builds the report with many different lengths, so headings land at every height, and checks that no page ends with a heading, a question or a model name.
+func TestPDFNeverLeavesAHeadingAloneAtTheFootOfAPage(t *testing.T) {
+	// The report with a growing number of chat models.
+	for extra := 0; extra < 90; extra++ {
+		for pad := 0; pad < 6; pad++ { // finer steps: extra lines of padding move every heading by one line at a time
+			// The runs.
+			runs := reportRuns()
+			// More chat models of one group.
+			for i := 0; i < extra; i++ {
+				// A model with a name of its own.
+				runs = append(runs, okRun("filler-"+strings.Repeat("x", i%7)+string(rune('a'+i%26))+":4b", float64(100+i)))
+			} // end of the filler loop
+			// The page data and the file.
+			p := buildCompare(runs, 0, nil, false)
+			// Padding lines under the last group move every later heading down by one line each.
+			for k := 0; k < pad && len(p.Groups) > 0; k++ {
+				// One more short note.
+				p.Groups[len(p.Groups)-1].Notes = append(p.Groups[len(p.Groups)-1].Notes, "padding line")
+			} // end of the padding loop
+			// Validate and read it.
+			bodies, _ := pdfCheck(t, writeComparePDF(p, time.Date(2026, 10, 27, 19, 30, 0, 0, time.UTC)))
+			// The texts that are headings, questions or model names.
+			heads := map[string]bool{"What the figures say": true, "How to read this": true, "How and why this comparison was done": true, "References": true, noticeTitle: true}
+			// The group titles.
+			for _, g := range p.Groups {
+				// One title.
+				heads[g.Title] = true
+				// Every model name.
+				for _, r := range g.Rows {
+					// One name.
+					heads[r.Cells[0]] = true
+				} // end of the row loop
+			} // end of the group loop
+			// The questions.
+			for _, h := range p.How {
+				// One question.
+				heads[h.Question] = true
+			} // end of the question loop
+			// The last line of each page.
+			for i, page := range bodies {
+				// An empty page is not expected.
+				if len(page) == 0 {
+					// Report it.
+					t.Errorf("extra %d pad "+string(rune(48+pad))+": page %d is empty", extra, i+1)
+					// Next.
+					continue
+				} // end of the empty check
+				// The last line.
+				if last := page[len(page)-1].Text; heads[last] {
+					// Report it.
+					t.Errorf("extra %d pad "+string(rune(48+pad))+": page %d ends with the heading %q", extra, i+1, last)
+				} // end of the check
+			} // end of the page loop
+		} // end of the padding loop
+	} // end of the loop
+} // end of TestPDFNeverLeavesAHeadingAloneAtTheFootOfAPage
diff --git a/notice.go b/notice.go
new file mode 100644
index 0000000..9aa0776
--- /dev/null
+++ b/notice.go
@@ -0,0 +1,24 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+// LEGAL REVIEW: the wording of the notices below is a draft written without legal advice. It lives only in this file so that a qualified lawyer can replace it without touching any other code. A test checks that every page and download carries whatever text is here.
+
+// noticeShort is the one-paragraph notice shown at the top of the comparison page and in the footer of every page of the PDF.
+const noticeShort = "Informational only. These figures measure speed and memory use on one computer. They are not a clinical validation and must not be used to decide whether a model is suitable or safe for patient care."
+
+// noticeTitle is the heading of the full notice.
+const noticeTitle = "Notice and limitation of liability"
+
+// noticeFull is the full notice, one paragraph per entry; each starts with a short label so that it can be read in pieces.
+var noticeFull = []string{
+	// What the figures are.
+	"Purpose. The figures here are informational measurements of speed and memory use, made on one computer at the times shown, with a fixed test prompt. They say nothing about the quality, accuracy or safety of the answers a model gives.",
+	// What they must not be used for.
+	"Not for clinical use. They are not a clinical validation, a medical-device assessment, a regulatory submission or a certification, and must not be used to decide whether a model is suitable or safe for patient care or for any clinical, diagnostic or treatment decision.",
+	// Whose responsibility it is.
+	"Your responsibility. Results can differ on other hardware, software versions, settings or days. You are responsible for validating any model for your intended use, under the rules that apply to you.",
+	// The liability clause, using the names kept in about.go.
+	"No warranty and no liability. This software and these results are provided \"as is\", without warranty of any kind, express or implied. To the fullest extent permitted by applicable law, " + companyName + " (termgate.com), the developer (" + appDeveloper + ") and any contributors accept no liability for any loss, damage or decision arising from the use or misinterpretation of this software, these figures or any file made from them. Nothing here limits any liability that cannot be limited by law.",
+	// Third parties.
+	"Third parties. Names of benchmarks, models, products and publications belong to their owners. They are mentioned for reference only and do not mean that their owners endorse, or are connected with, this software or " + companyName + ".",
+} // end of noticeFull
diff --git a/notice_test.go b/notice_test.go
new file mode 100644
index 0000000..e723231
--- /dev/null
+++ b/notice_test.go
@@ -0,0 +1,65 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// strings searches the notice text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// TestNoticeSaysWhatItMustSay checks the notice for the points that protect the reader and the developer, so an edit cannot quietly remove one.
+func TestNoticeSaysWhatItMustSay(t *testing.T) {
+	// The short notice.
+	for _, w := range []string{"Informational only", "not a clinical validation", "patient care"} {
+		// Missing.
+		if !strings.Contains(noticeShort, w) {
+			// Report it.
+			t.Errorf("the short notice lacks %q", w)
+		} // end of the check
+	} // end of the short loop
+	// The full notice, as one text.
+	full := strings.Join(noticeFull, "\n")
+	// The points.
+	for _, w := range []string{
+		// It is about speed and memory only.
+		"speed and memory use", "quality, accuracy or safety",
+		// It is not for clinical use.
+		"not a clinical validation", "medical-device assessment", "regulatory submission", "certification", "patient care", "clinical, diagnostic or treatment decision",
+		// The reader is responsible.
+		"You are responsible for validating any model for your intended use",
+		// No warranty and no liability, naming the company, its site and the developer.
+		"\"as is\"", "without warranty of any kind", "To the fullest extent permitted by applicable law", companyName, "termgate.com", appDeveloper, "no liability", "misinterpretation", "contributors",
+		// The limit of the clause.
+		"Nothing here limits any liability that cannot be limited by law",
+		// Third parties.
+		"belong to their owners", "do not mean that their owners endorse",
+	} {
+		// Missing.
+		if !strings.Contains(full, w) {
+			// Report it.
+			t.Errorf("the full notice lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// Five paragraphs, each starting with its label.
+	if len(noticeFull) != 5 {
+		// Report it.
+		t.Errorf("%d notice paragraphs, want 5", len(noticeFull))
+	} // end of the count check
+	// The labels.
+	for i, label := range []string{"Purpose.", "Not for clinical use.", "Your responsibility.", "No warranty and no liability.", "Third parties."} {
+		// The start.
+		if !strings.HasPrefix(noticeFull[i], label) {
+			// Report it.
+			t.Errorf("paragraph %d does not start with %q", i, label)
+		} // end of the check
+	} // end of the loop
+	// The notice makes no claim to be a legal guarantee.
+	for _, bad := range []string{"guarantee", "legally binding", "fully protected"} {
+		// Present.
+		if strings.Contains(strings.ToLower(full), bad) {
+			// Report it.
+			t.Errorf("the notice must not say %q", bad)
+		} // end of the check
+	} // end of the loop
+} // end of TestNoticeSaysWhatItMustSay
diff --git a/pdf.go b/pdf.go
new file mode 100644
index 0000000..9957884
--- /dev/null
+++ b/pdf.go
@@ -0,0 +1,360 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes builds the file in memory.
+	"bytes"
+	// fmt formats numbers and text.
+	"fmt"
+	// strings splits and joins text.
+	"strings"
+	// time stamps the file.
+	"time"
+) // end of imports
+
+// The page is A4 portrait, measured in points (1/72 inch), with the origin at the bottom left.
+const (
+	// pdfPageW is the page width.
+	pdfPageW = 595.28
+	// pdfPageH is the page height.
+	pdfPageH = 841.89
+	// pdfMargin is the space left empty on the left, right and top.
+	pdfMargin = 56.0
+	// pdfBottom is the lowest line of body text; the footer sits under it.
+	pdfBottom = 78.0
+	// pdfLeading is the line height as a multiple of the font size.
+	pdfLeading = 1.3
+) // end of the page constants
+
+// pdfWinAnsi maps the few characters beyond plain ASCII and Latin-1 that this program writes to their code in the WinAnsi encoding of the built-in PDF fonts.
+var pdfWinAnsi = map[rune]byte{'€': 0x80, '‚': 0x82, 'ƒ': 0x83, '„': 0x84, '…': 0x85, '†': 0x86, '‡': 0x87, 'ˆ': 0x88, '‰': 0x89, 'Š': 0x8A, '‹': 0x8B, 'Œ': 0x8C, 'Ž': 0x8E, '‘': 0x91, '’': 0x92, '“': 0x93, '”': 0x94, '•': 0x95, '–': 0x96, '—': 0x97, '˜': 0x98, '™': 0x99, 'š': 0x9A, '›': 0x9B, 'œ': 0x9C, 'ž': 0x9E, 'Ÿ': 0x9F}
+
+// pdfByte returns the WinAnsi code of a character; characters that cannot be written become a question mark.
+func pdfByte(r rune) byte {
+	// A tab is written as a space.
+	if r == '\t' {
+		// One space.
+		return ' '
+	} // end of the tab check
+	// Plain printable ASCII.
+	if r >= 32 && r < 127 {
+		// The same code.
+		return byte(r)
+	} // end of the ASCII check
+	// Latin-1 letters and signs share their codes with WinAnsi.
+	if r >= 0xA0 && r <= 0xFF {
+		// The same code.
+		return byte(r)
+	} // end of the Latin-1 check
+	// The extra characters.
+	if b, ok := pdfWinAnsi[r]; ok {
+		// Their code.
+		return b
+	} // end of the extra check
+	// Anything else cannot be shown.
+	return '?'
+} // end of pdfByte
+
+// pdfEscape writes text as the inside of a PDF literal string: brackets and the backslash are escaped, and every code above ASCII is written as an octal escape, so the file stays plain ASCII.
+func pdfEscape(s string) string {
+	// The result.
+	var b strings.Builder
+	// Go through the characters.
+	for _, r := range s {
+		// The code in the font.
+		c := pdfByte(r)
+		// The three characters that have a meaning inside a string.
+		switch {
+		// A backslash, an opening or a closing bracket.
+		case c == '\\' || c == '(' || c == ')':
+			// Escape it.
+			b.WriteByte('\\')
+			// Then the character itself.
+			b.WriteByte(c)
+		// Anything outside printable ASCII.
+		case c < 32 || c > 126:
+			// Three octal digits.
+			fmt.Fprintf(&b, "\\%03o", c)
+		// Everything else is written as it is.
+		default:
+			// The character.
+			b.WriteByte(c)
+		} // end of the switch
+	} // end of the loop
+	// The text.
+	return b.String()
+} // end of pdfEscape
+
+// pdfWidth returns the width of a text in points at the given size.
+func pdfWidth(s string, size float64, bold bool) float64 {
+	// The table of the font.
+	table := &helveticaWidths
+	// The bold font.
+	if bold {
+		// Its table.
+		table = &helveticaBoldWidths
+	} // end of the bold check
+	// The sum of the widths in thousandths.
+	total := 0
+	// Go through the characters.
+	for _, r := range s {
+		// The code in the font.
+		c := int(pdfByte(r))
+		// Codes below 32 have no width; use the width of a typical letter.
+		w := 556
+		// A code with a table entry.
+		if c >= 32 && table[c-32] > 0 {
+			// Its width.
+			w = table[c-32]
+		} // end of the entry check
+		// Add it.
+		total += w
+	} // end of the loop
+	// Scale to the font size.
+	return float64(total) * size / 1000
+} // end of pdfWidth
+
+// pdfWrap breaks a text into lines that fit the width; a word longer than a line (such as a web address) is broken where it must be.
+func pdfWrap(text string, size float64, bold bool, width float64) []string {
+	// The lines.
+	var lines []string
+	// The line being built.
+	cur := ""
+	// Go through the words.
+	for _, word := range strings.Fields(text) {
+		// A word that is too long for any line is cut into pieces.
+		for pdfWidth(word, size, bold) > width {
+			// Make room: the current line is finished first.
+			if cur != "" {
+				// Keep it.
+				lines = append(lines, cur)
+				// Start again.
+				cur = ""
+			} // end of the flush check
+			// Find how many characters fit.
+			n := 0
+			// Grow until the width is reached.
+			for n < len(word) && pdfWidth(word[:n+1], size, bold) <= width {
+				// One more fits.
+				n++
+			} // end of the fit loop
+			// At least one character per line, so the loop always ends.
+			if n == 0 {
+				// Force one.
+				n = 1
+			} // end of the minimum check
+			// Keep the piece.
+			lines = append(lines, word[:n])
+			// The rest of the word.
+			word = word[n:]
+		} // end of the long-word loop
+		// The candidate line with the word added.
+		next := word
+		// With a space when the line is not empty.
+		if cur != "" {
+			// Join them.
+			next = cur + " " + word
+		} // end of the join check
+		// It fits.
+		if pdfWidth(next, size, bold) <= width {
+			// Keep it.
+			cur = next
+		} else {
+			// Finish the line and start a new one.
+			lines = append(lines, cur)
+			// The word starts the next line.
+			cur = word
+		} // end of the fit check
+	} // end of the word loop
+	// The last line.
+	if cur != "" {
+		// Keep it.
+		lines = append(lines, cur)
+	} // end of the last-line check
+	// The lines.
+	return lines
+} // end of pdfWrap
+
+// pdfDoc builds a small text-only PDF using the standard library alone.
+type pdfDoc struct {
+	// title is the document title stored in the file.
+	title string
+	// subject is the notice stored in the file's properties.
+	subject string
+	// footerNotice is printed at the foot of every page.
+	footerNotice string
+	// footerLine is printed under it, before the page number.
+	footerLine string
+	// created is the time stamp stored in the file.
+	created time.Time
+	// pages holds the drawing instructions of each finished page and of the current one.
+	pages []*bytes.Buffer
+	// y is the height of the next line on the current page.
+	y float64
+} // end of pdfDoc
+
+// newPDF starts a document with its first page.
+func newPDF(title, subject, footerNotice, footerLine string, created time.Time) *pdfDoc {
+	// The document.
+	d := &pdfDoc{title: title, subject: subject, footerNotice: footerNotice, footerLine: footerLine, created: created.UTC()}
+	// The first page.
+	d.newPage()
+	// Hand it back.
+	return d
+} // end of newPDF
+
+// newPage starts a new page.
+func (d *pdfDoc) newPage() {
+	// A fresh list of instructions.
+	d.pages = append(d.pages, &bytes.Buffer{})
+	// The first line goes under the top margin.
+	d.y = pdfPageH - pdfMargin
+} // end of newPage
+
+// line draws one line of text at the current height and moves down.
+func (d *pdfDoc) line(s string, size float64, bold bool, indent float64) {
+	// The step down.
+	step := size * pdfLeading
+	// Not enough room: a new page.
+	if d.y-step < pdfBottom {
+		// Start it.
+		d.newPage()
+	} // end of the room check
+	// The font name inside the page.
+	font := "F1"
+	// The bold font.
+	if bold {
+		// Its name.
+		font = "F2"
+	} // end of the bold check
+	// Move down to the baseline.
+	d.y -= step
+	// The drawing instruction: begin text, font and size, position, show, end text.
+	fmt.Fprintf(d.pages[len(d.pages)-1], "BT /%s %.1f Tf %.2f %.2f Td (%s) Tj ET\n", font, size, pdfMargin+indent, d.y, pdfEscape(s))
+} // end of line
+
+// text writes a paragraph, wrapped to the page width.
+func (d *pdfDoc) text(s string, size float64, bold bool, indent float64) {
+	// The width available.
+	width := pdfPageW - 2*pdfMargin - indent
+	// Each paragraph break in the text starts its own paragraph.
+	for _, para := range strings.Split(s, "\n") {
+		// An empty paragraph is a blank line.
+		if strings.TrimSpace(para) == "" {
+			// A gap.
+			d.gap(size * 0.6)
+			// Next.
+			continue
+		} // end of the blank check
+		// The lines of the paragraph.
+		for _, l := range pdfWrap(para, size, bold, width) {
+			// Draw each.
+			d.line(l, size, bold, indent)
+		} // end of the line loop
+	} // end of the paragraph loop
+} // end of text
+
+// keep starts a new page when less than the given height is left, so a heading is never left alone at the foot of a page.
+func (d *pdfDoc) keep(points float64) {
+	// Not enough room for the heading and the first lines under it.
+	if d.y-points < pdfBottom {
+		// Start the next page.
+		d.newPage()
+	} // end of the room check
+} // end of keep
+
+// gap leaves some empty space.
+func (d *pdfDoc) gap(points float64) {
+	// Move down; a page break happens by itself at the next line.
+	d.y -= points
+} // end of gap
+
+// rule draws a thin line across the page.
+func (d *pdfDoc) rule() {
+	// Room for the line.
+	if d.y-6 < pdfBottom {
+		// A new page.
+		d.newPage()
+	} // end of the room check
+	// Move down a little.
+	d.y -= 4
+	// The drawing instruction: line width, move, line, stroke.
+	fmt.Fprintf(d.pages[len(d.pages)-1], "0.5 w %.2f %.2f m %.2f %.2f l S\n", pdfMargin, d.y, pdfPageW-pdfMargin, d.y)
+	// Move down a little more.
+	d.y -= 4
+} // end of rule
+
+// footer draws the notice and the page number at the foot of one page.
+func (d *pdfDoc) footer(page *bytes.Buffer, n, total int) {
+	// The line above the footer.
+	fmt.Fprintf(page, "0.5 w %.2f 64 m %.2f 64 l S\n", pdfMargin, pdfPageW-pdfMargin)
+	// The notice, wrapped; at most three lines fit.
+	y := 54.0
+	// Go through its lines.
+	for _, l := range pdfWrap(d.footerNotice, 7, false, pdfPageW-2*pdfMargin) {
+		// One line.
+		fmt.Fprintf(page, "BT /F1 7 Tf %.2f %.2f Td (%s) Tj ET\n", pdfMargin, y, pdfEscape(l))
+		// Move down.
+		y -= 9
+	} // end of the line loop
+	// The program, the time and the page number.
+	fmt.Fprintf(page, "BT /F1 7 Tf %.2f %.2f Td (%s) Tj ET\n", pdfMargin, y-2, pdfEscape(fmt.Sprintf("%s  -  page %d of %d", d.footerLine, n, total)))
+} // end of footer
+
+// bytes finishes the document and returns the file.
+func (d *pdfDoc) bytes() []byte {
+	// The finished file.
+	var out bytes.Buffer
+	// Where each numbered object starts, for the cross-reference table.
+	var offsets []int
+	// obj writes one numbered object and remembers where it started.
+	obj := func(body string) {
+		// The start.
+		offsets = append(offsets, out.Len())
+		// The object, numbered from 1.
+		fmt.Fprintf(&out, "%d 0 obj\n%s\nendobj\n", len(offsets), body)
+	} // end of obj
+	// The header, with a comment of high bytes so tools treat the file as binary.
+	out.WriteString("%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
+	// The number of pages.
+	n := len(d.pages)
+	// Object 1: the catalog.
+	obj("<< /Type /Catalog /Pages 2 0 R /Lang (en) >>")
+	// The page objects come after the fixed objects 1 to 5: page i is object 6+2i, its content 7+2i.
+	var kids []string
+	// Collect the references.
+	for i := 0; i < n; i++ {
+		// One page.
+		kids = append(kids, fmt.Sprintf("%d 0 R", 6+2*i))
+	} // end of the loop
+	// Object 2: the list of pages.
+	obj(fmt.Sprintf("<< /Type /Pages /Kids [%s] /Count %d >>", strings.Join(kids, " "), n))
+	// Object 3: the regular font.
+	obj("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
+	// Object 4: the bold font.
+	obj("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
+	// Object 5: the document information.
+	obj(fmt.Sprintf("<< /Title (%s) /Subject (%s) /Producer (OllamaControlCenter %s) /Creator (OllamaControlCenter) /CreationDate (D:%s) >>", pdfEscape(d.title), pdfEscape(d.subject), appVersion, d.created.Format("20060102150405Z0700")))
+	// Each page and its content.
+	for i, page := range d.pages {
+		// The footer on this page.
+		d.footer(page, i+1, n)
+		// The page object: size, fonts and the content.
+		obj(fmt.Sprintf("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.2f %.2f] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents %d 0 R >>", pdfPageW, pdfPageH, 7+2*i))
+		// The content stream object.
+		obj(fmt.Sprintf("<< /Length %d >>\nstream\n%sendstream", page.Len(), page.String()))
+	} // end of the page loop
+	// Where the cross-reference table starts.
+	xref := out.Len()
+	// The table: one entry of exactly 20 bytes for each object, and the free entry 0.
+	fmt.Fprintf(&out, "xref\n0 %d\n0000000000 65535 f \n", len(offsets)+1)
+	// The entries.
+	for _, off := range offsets {
+		// Ten digits, a generation number, and "n" for in use.
+		fmt.Fprintf(&out, "%010d 00000 n \n", off)
+	} // end of the loop
+	// The trailer points at the catalog and the information, and at the table.
+	fmt.Fprintf(&out, "trailer\n<< /Size %d /Root 1 0 R /Info 5 0 R >>\nstartxref\n%d\n%%%%EOF\n", len(offsets)+1, xref)
+	// The file.
+	return out.Bytes()
+} // end of bytes
diff --git a/pdf_test.go b/pdf_test.go
new file mode 100644
index 0000000..36588e0
--- /dev/null
+++ b/pdf_test.go
@@ -0,0 +1,407 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes searches the file bytes.
+	"bytes"
+	// fmt builds expected texts.
+	"fmt"
+	// regexp reads the drawing instructions back.
+	"regexp"
+	// strconv reads the numbers back.
+	"strconv"
+	// strings joins and cleans text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+	// time gives a fixed time for the file.
+	"time"
+) // end of imports
+
+// pdfTextLine is one drawn line of text read back from a page: where it sits and what it says.
+type pdfTextLine struct {
+	// Y is the height of the line on the page.
+	Y float64
+	// Text is the line with the escapes undone.
+	Text string
+} // end of pdfTextLine
+
+// pdfLineRe finds one drawing instruction of text and captures the height and the string.
+var pdfLineRe = regexp.MustCompile(`(?m)^BT /F[12] [0-9.]+ Tf [0-9.]+ ([0-9.]+) Td \((.*)\) Tj ET$`)
+
+// pdfUnescape undoes the escapes of a PDF literal string.
+func pdfUnescape(s string) string {
+	// The result.
+	var b strings.Builder
+	// Walk the characters.
+	for i := 0; i < len(s); i++ {
+		// Not an escape.
+		if s[i] != '\\' {
+			// Copy it.
+			b.WriteByte(s[i])
+			// Next.
+			continue
+		} // end of the plain check
+		// An escape needs a next character.
+		if i+1 >= len(s) {
+			// Stop.
+			break
+		} // end of the end check
+		// An octal escape has three digits.
+		if s[i+1] >= '0' && s[i+1] <= '7' && i+4 <= len(s) {
+			// Read the code.
+			n, err := strconv.ParseUint(s[i+1:i+4], 8, 8)
+			// A good code.
+			if err == nil {
+				// The same code as a Latin-1 character, which is what the tests use.
+				b.WriteRune(rune(pdfLatin(byte(n))))
+				// Skip the digits.
+				i += 3
+				// Next.
+				continue
+			} // end of the code check
+		} // end of the octal check
+		// A plain escaped character.
+		b.WriteByte(s[i+1])
+		// Skip it.
+		i++
+	} // end of the loop
+	// The text.
+	return b.String()
+} // end of pdfUnescape
+
+// pdfLatin turns a WinAnsi code back into the character it stands for.
+func pdfLatin(c byte) rune {
+	// The extra characters.
+	for r, b := range pdfWinAnsi {
+		// A match.
+		if b == c {
+			// The character.
+			return r
+		} // end of the match check
+	} // end of the loop
+	// Everything else is the same as Latin-1.
+	return rune(c)
+} // end of pdfLatin
+
+// pdfCheck validates the structure of a file made by pdfDoc and returns the lines of every page (body and footer apart).
+func pdfCheck(t *testing.T, data []byte) (bodies [][]pdfTextLine, footers [][]pdfTextLine) {
+	// Mark this as a helper.
+	t.Helper()
+	// The header and the end.
+	if !bytes.HasPrefix(data, []byte("%PDF-1.4\n")) || !bytes.HasSuffix(data, []byte("%%EOF\n")) {
+		// Stop the test.
+		t.Fatalf("header or end marker wrong")
+	} // end of the marker check
+	// Where the cross-reference table starts.
+	i := bytes.LastIndex(data, []byte("startxref\n"))
+	// It must exist.
+	if i < 0 {
+		// Stop the test.
+		t.Fatalf("no startxref")
+	} // end of the startxref check
+	// The number after it.
+	var xref int
+	// Read it.
+	if _, err := fmt.Sscanf(string(data[i+len("startxref\n"):]), "%d", &xref); err != nil {
+		// Stop the test.
+		t.Fatalf("startxref number: %v", err)
+	} // end of the read check
+	// The table starts there.
+	if !bytes.HasPrefix(data[xref:], []byte("xref\n0 ")) {
+		// Stop the test.
+		t.Fatalf("startxref does not point at the table")
+	} // end of the table check
+	// The number of entries.
+	var count int
+	// Read it.
+	fmt.Sscanf(string(data[xref+len("xref\n0 "):]), "%d", &count)
+	// The first entry starts after the line "0 N\n".
+	line := bytes.IndexByte(data[xref+5:], '\n') + xref + 5 + 1
+	// Entry 0 is the free entry, exactly 20 bytes.
+	if string(data[line:line+20]) != "0000000000 65535 f \n" {
+		// Stop the test.
+		t.Fatalf("free entry wrong: %q", data[line:line+20])
+	} // end of the free entry check
+	// Every other entry points at its object.
+	for n := 1; n < count; n++ {
+		// The entry.
+		e := data[line+20*n : line+20*n+20]
+		// It must have the fixed shape.
+		if len(e) != 20 || e[10] != ' ' || e[16] != ' ' || e[17] != 'n' || e[19] != '\n' {
+			// Stop the test.
+			t.Fatalf("entry %d has the wrong shape: %q", n, e)
+		} // end of the shape check
+		// The offset.
+		off, err := strconv.Atoi(string(e[:10]))
+		// A number.
+		if err != nil {
+			// Stop the test.
+			t.Fatalf("entry %d offset: %v", n, err)
+		} // end of the number check
+		// The object must start there.
+		if !bytes.HasPrefix(data[off:], []byte(fmt.Sprintf("%d 0 obj\n", n))) {
+			// Stop the test.
+			t.Fatalf("object %d is not at offset %d", n, off)
+		} // end of the object check
+	} // end of the entry loop
+	// The trailer's size.
+	if !bytes.Contains(data[xref:], []byte(fmt.Sprintf("/Size %d /Root 1 0 R /Info 5 0 R", count))) {
+		// Stop the test.
+		t.Fatalf("trailer size wrong")
+	} // end of the trailer check
+	// The page count in the page tree equals the number of page objects.
+	pages := bytes.Count(data, []byte("/Type /Page /Parent"))
+	// The declared count.
+	if !bytes.Contains(data, []byte(fmt.Sprintf("/Count %d >>", pages))) || pages == 0 {
+		// Stop the test.
+		t.Fatalf("page count %d does not match /Count", pages)
+	} // end of the count check
+	// Every object is one of the 5 fixed ones plus a page and a content object for each page.
+	if count != 1+5+2*pages {
+		// Stop the test.
+		t.Fatalf("%d entries for %d pages", count, pages)
+	} // end of the object count check
+	// Every content stream: its declared length equals its real length, and its lines are read back.
+	re := regexp.MustCompile(`(?s)<< /Length (\d+) >>\nstream\n(.*?)endstream`)
+	// Go through the streams in order.
+	for _, m := range re.FindAllSubmatch(data, -1) {
+		// The declared length.
+		n, _ := strconv.Atoi(string(m[1]))
+		// It must match.
+		if n != len(m[2]) {
+			// Stop the test.
+			t.Fatalf("stream length %d, declared %d", len(m[2]), n)
+		} // end of the length check
+		// Only ASCII is written.
+		for _, c := range m[2] {
+			// A high or odd byte.
+			if c > 126 || (c < 32 && c != '\n') {
+				// Stop the test.
+				t.Fatalf("stream holds byte %d", c)
+			} // end of the byte check
+		} // end of the byte loop
+		// The lines of this page.
+		var body, foot []pdfTextLine
+		// Each drawn line.
+		for _, l := range pdfLineRe.FindAllSubmatch(m[2], -1) {
+			// The height.
+			y, _ := strconv.ParseFloat(string(l[1]), 64)
+			// The line.
+			pl := pdfTextLine{Y: y, Text: pdfUnescape(string(l[2]))}
+			// The footer is below the body area.
+			if y < pdfBottom-8 {
+				// Keep it apart.
+				foot = append(foot, pl)
+			} else {
+				// A body line.
+				body = append(body, pl)
+			} // end of the area check
+		} // end of the line loop
+		// Keep both.
+		bodies, footers = append(bodies, body), append(footers, foot)
+	} // end of the stream loop
+	// One stream per page.
+	if len(bodies) != pages {
+		// Stop the test.
+		t.Fatalf("%d streams for %d pages", len(bodies), pages)
+	} // end of the stream count check
+	// The pages.
+	return bodies, footers
+} // end of pdfCheck
+
+// flat joins the lines of pages into one text with single spaces.
+func flat(pages [][]pdfTextLine) string {
+	// The parts.
+	var parts []string
+	// Each page.
+	for _, p := range pages {
+		// Each line.
+		for _, l := range p {
+			// One line.
+			parts = append(parts, l.Text)
+		} // end of the line loop
+	} // end of the page loop
+	// One text.
+	return strings.Join(strings.Fields(strings.Join(parts, " ")), " ")
+} // end of flat
+
+// TestPDFEscapeAndEncoding checks the escapes and the character mapping.
+func TestPDFEscapeAndEncoding(t *testing.T) {
+	// The cases.
+	for in, want := range map[string]string{
+		// Brackets and the backslash are escaped.
+		"a(b)c\\d": `a\(b\)c\\d`,
+		// Latin-1 and WinAnsi characters become octal escapes.
+		"±·×": `\261\267\327`,
+		// The en dash and the typographic quotes.
+		"–“”’": `\226\223\224\222`,
+		// A tab is a space; a letter with an accent is Latin-1.
+		"a\tb": "a b", "Loïc": `Lo\357c`,
+		// A character the font cannot draw becomes a question mark.
+		"✓⚠": "??",
+	} {
+		// Escape it.
+		if got := pdfEscape(in); got != want {
+			// Report it.
+			t.Errorf("pdfEscape(%q) = %q, want %q", in, got, want)
+		} // end of the check
+	} // end of the loop
+	// Reading it back gives the original for everything the font can draw.
+	for _, s := range []string{"(termgate.com)", "1.5× slower", "Chat · Small", "Loïc", "a\\b"} {
+		// Round trip.
+		if got := pdfUnescape(pdfEscape(s)); got != s {
+			// Report it.
+			t.Errorf("round trip %q gave %q", s, got)
+		} // end of the check
+	} // end of the loop
+} // end of TestPDFEscapeAndEncoding
+
+// TestPDFWidthsMatchTheFontMetrics checks the width tables against well-known Helvetica values.
+func TestPDFWidthsMatchTheFontMetrics(t *testing.T) {
+	// The cases: text, bold, and the width of one character in 1/1000.
+	for _, c := range []struct {
+		// The character.
+		s string
+		// Bold or not.
+		bold bool
+		// The width.
+		want float64
+	}{
+		// Regular letters, a space and a digit.
+		{"A", false, 667}, {" ", false, 278}, {"i", false, 222}, {"0", false, 556}, {"W", false, 944},
+		// Bold letters.
+		{"A", true, 722}, {"i", true, 278}, {"W", true, 944},
+		// Signs.
+		{"±", false, 584}, {"·", false, 278}, {"×", false, 584},
+	} {
+		// Measured at size 1000, so the result is the table value.
+		if got := pdfWidth(c.s, 1000, c.bold); got != c.want {
+			// Report it.
+			t.Errorf("width of %q (bold %v) = %v, want %v", c.s, c.bold, got, c.want)
+		} // end of the check
+	} // end of the loop
+	// The tables have one entry for every code from 32 to 255.
+	if len(helveticaWidths) != 224 || len(helveticaBoldWidths) != 224 {
+		// Report it.
+		t.Errorf("table sizes %d, %d", len(helveticaWidths), len(helveticaBoldWidths))
+	} // end of the size check
+	// The size scales the width.
+	if got := pdfWidth("AA", 10, false); got != 13.34 {
+		// Report it.
+		t.Errorf("AA at 10 = %v", got)
+	} // end of the scale check
+} // end of TestPDFWidthsMatchTheFontMetrics
+
+// TestPDFWrapKeepsEveryWordWithinTheWidth checks the line breaking, including a long address.
+func TestPDFWrapKeepsEveryWordWithinTheWidth(t *testing.T) {
+	// A text with a long unbreakable address in it.
+	text := "See https://example.org/" + strings.Repeat("abcdefghij", 20) + " for the full text of the notice and the way it is written."
+	// Wrap at 200 points.
+	lines := pdfWrap(text, 9, false, 200)
+	// Every line fits.
+	for _, l := range lines {
+		// Too wide.
+		if w := pdfWidth(l, 9, false); w > 200.001 {
+			// Report it.
+			t.Errorf("line %q is %.1f wide", l, w)
+		} // end of the check
+	} // end of the loop
+	// Nothing is lost: all characters are still there, in order.
+	if got, want := strings.ReplaceAll(strings.Join(lines, ""), " ", ""), strings.ReplaceAll(text, " ", ""); got != want {
+		// Report it.
+		t.Errorf("text changed by wrapping")
+	} // end of the content check
+	// An empty text gives no lines.
+	if len(pdfWrap("   ", 9, false, 200)) != 0 {
+		// Report it.
+		t.Errorf("blank text gave lines")
+	} // end of the blank check
+	// A width smaller than one letter still ends.
+	if got := pdfWrap("abc", 9, false, 1); len(got) != 3 {
+		// Report it.
+		t.Errorf("tiny width gave %v", got)
+	} // end of the tiny check
+} // end of TestPDFWrapKeepsEveryWordWithinTheWidth
+
+// TestPDFStructureAndPaging checks a document of many lines: valid structure, several pages, a footer with the notice and the page number on each.
+func TestPDFStructureAndPaging(t *testing.T) {
+	// A document with a fixed time.
+	d := newPDF("Title (with brackets)", "Subject", "Informational only. Notice words.", "Program line", time.Date(2026, 10, 27, 19, 30, 5, 0, time.UTC))
+	// A heading and a lot of lines.
+	d.text("Heading", 18, true, 0)
+	// Many paragraphs.
+	for i := 0; i < 150; i++ {
+		// One paragraph.
+		d.text(fmt.Sprintf("Line number %d of the long document, written to fill the pages.", i), 10, false, 0)
+	} // end of the loop
+	// A rule.
+	d.rule()
+	// The file.
+	data := d.bytes()
+	// Validate it.
+	bodies, footers := pdfCheck(t, data)
+	// Several pages.
+	if len(bodies) < 3 {
+		// Stop the test.
+		t.Fatalf("%d pages, want at least 3", len(bodies))
+	} // end of the page check
+	// The footer of every page.
+	for i, f := range footers {
+		// Its text.
+		text := flat([][]pdfTextLine{f})
+		// The notice and the page number.
+		if !strings.Contains(text, "Informational only. Notice words.") || !strings.Contains(text, fmt.Sprintf("page %d of %d", i+1, len(bodies))) || !strings.Contains(text, "Program line") {
+			// Report it.
+			t.Errorf("footer of page %d: %q", i+1, text)
+		} // end of the check
+	} // end of the loop
+	// Every line of every body is inside the margins.
+	for _, p := range bodies {
+		// Each line.
+		for _, l := range p {
+			// Below the top margin and above the bottom.
+			if l.Y < pdfBottom || l.Y > pdfPageH-pdfMargin {
+				// Report it.
+				t.Errorf("line %q at height %.1f is outside the body area", l.Text, l.Y)
+			} // end of the check
+		} // end of the line loop
+	} // end of the page loop
+	// All 150 lines are present, in order.
+	all := flat(bodies)
+	// Each one.
+	last := -1
+	// Check the order.
+	for i := 0; i < 150; i++ {
+		// Find it after the previous one.
+		at := strings.Index(all, fmt.Sprintf("Line number %d of the long document", i))
+		// Missing or out of order.
+		if at < 0 || at <= last {
+			// Stop the test.
+			t.Fatalf("line %d missing or out of order", i)
+		} // end of the check
+		// Remember.
+		last = at
+	} // end of the loop
+	// The properties are in the file, with the brackets escaped.
+	if !bytes.Contains(data, []byte(`/Title (Title \(with brackets\))`)) || !bytes.Contains(data, []byte("/CreationDate (D:20261027193005Z)")) || !bytes.Contains(data, []byte("/Producer (OllamaControlCenter "+appVersion+")")) {
+		// Report it.
+		t.Errorf("document information wrong")
+	} // end of the information check
+	// The same document made twice is identical.
+	d2 := newPDF("Title (with brackets)", "Subject", "Informational only. Notice words.", "Program line", time.Date(2026, 10, 27, 19, 30, 5, 0, time.UTC))
+	// The same content.
+	d2.text("Heading", 18, true, 0)
+	// Many paragraphs.
+	for i := 0; i < 150; i++ {
+		// One paragraph.
+		d2.text(fmt.Sprintf("Line number %d of the long document, written to fill the pages.", i), 10, false, 0)
+	} // end of the loop
+	// A rule.
+	d2.rule()
+	// Identical.
+	if !bytes.Equal(data, d2.bytes()) {
+		// Report it.
+		t.Errorf("the same document gave different files")
+	} // end of the identical check
+} // end of TestPDFStructureAndPaging
diff --git a/pdfwidths.go b/pdfwidths.go
new file mode 100644
index 0000000..d6c5194
--- /dev/null
+++ b/pdfwidths.go
@@ -0,0 +1,66 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+// helveticaWidths holds the width of every character from code 32 to 255 in Helvetica, in 1/1000 of the font size (the standard Adobe font metrics of the built-in PDF font, copied from the ReportLab library's tables); zero means no character is defined at that code.
+var helveticaWidths = [224]int{
+	// Codes 32 to 47.
+	278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
+	// Codes 48 to 63.
+	556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
+	// Codes 64 to 79.
+	1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
+	// Codes 80 to 95.
+	667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
+	// Codes 96 to 111.
+	333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
+	// Codes 112 to 127.
+	556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584, 761,
+	// Codes 128 to 143.
+	556, 0, 222, 556, 333, 1000, 556, 556, 333, 1000, 667, 333, 1000, 0, 611, 0,
+	// Codes 144 to 159.
+	0, 222, 222, 333, 333, 350, 556, 1000, 333, 1000, 500, 333, 944, 0, 500, 667,
+	// Codes 160 to 175.
+	278, 333, 556, 556, 556, 556, 260, 556, 333, 737, 370, 556, 584, 333, 737, 333,
+	// Codes 176 to 191.
+	400, 584, 333, 333, 333, 556, 537, 278, 333, 333, 365, 556, 834, 834, 834, 611,
+	// Codes 192 to 207.
+	667, 667, 667, 667, 667, 667, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278,
+	// Codes 208 to 223.
+	722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611,
+	// Codes 224 to 239.
+	556, 556, 556, 556, 556, 556, 889, 500, 556, 556, 556, 556, 278, 278, 278, 278,
+	// Codes 240 to 255.
+	556, 556, 556, 556, 556, 556, 556, 584, 611, 556, 556, 556, 556, 500, 556, 500,
+} // end of helveticaWidths
+
+// helveticaBoldWidths holds the width of every character from code 32 to 255 in Helvetica-Bold, in 1/1000 of the font size (the standard Adobe font metrics of the built-in PDF font, copied from the ReportLab library's tables); zero means no character is defined at that code.
+var helveticaBoldWidths = [224]int{
+	// Codes 32 to 47.
+	278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278,
+	// Codes 48 to 63.
+	556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611,
+	// Codes 64 to 79.
+	975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778,
+	// Codes 80 to 95.
+	667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556,
+	// Codes 96 to 111.
+	333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,
+	// Codes 112 to 127.
+	611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584, 761,
+	// Codes 128 to 143.
+	556, 0, 278, 556, 500, 1000, 556, 556, 333, 1000, 667, 333, 1000, 0, 611, 0,
+	// Codes 144 to 159.
+	0, 278, 278, 500, 500, 350, 556, 1000, 333, 1000, 556, 333, 944, 0, 500, 667,
+	// Codes 160 to 175.
+	278, 333, 556, 556, 556, 556, 280, 556, 333, 737, 370, 556, 584, 333, 737, 333,
+	// Codes 176 to 191.
+	400, 584, 333, 333, 333, 611, 556, 278, 333, 333, 365, 556, 834, 834, 834, 611,
+	// Codes 192 to 207.
+	722, 722, 722, 722, 722, 722, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278,
+	// Codes 208 to 223.
+	722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611,
+	// Codes 224 to 239.
+	556, 556, 556, 556, 556, 556, 889, 556, 556, 556, 556, 556, 278, 278, 278, 278,
+	// Codes 240 to 255.
+	611, 611, 611, 611, 611, 611, 611, 584, 611, 611, 611, 611, 611, 556, 611, 556,
+} // end of helveticaBoldWidths
diff --git a/perf.go b/perf.go
index 942ff96..c38aa1d 100644
--- a/perf.go
+++ b/perf.go
@@ -26,6 +26,8 @@ import ( // import lists the standard-library packages this file uses.
 	"strings"
 	// time measures how long things take.
 	"time"
+	// unicode/utf8 counts the characters of an answer (only the count is kept, never the text).
+	"unicode/utf8"
 ) // end of imports
 
 // perfPromptVersion names the fixed prompt; saved runs carry it, so only runs with the same prompt are compared.
@@ -77,6 +79,8 @@ type perfFigures struct {
 	GotFirstWord bool
 	// VectorLength is the length of the first embedding vector (embedding models only).
 	VectorLength int
+	// AnswerChars is how many characters the model wrote, answer and reasoning together (only the count is kept, never the text).
+	AnswerChars int
 } // end of perfFigures
 
 // perfRun is one saved test: numbers and names only, never any text of a prompt or an answer. A zero in a speed or time field means "not available".
@@ -93,12 +97,22 @@ type perfRun struct {
 	Host string `json:"host"`
 	// PromptVersion names the fixed prompt.
 	PromptVersion string `json:"prompt_version"`
+	// Family is the model family Ollama reported when the test ran (empty in older results).
+	Family string `json:"family,omitempty"`
+	// ParameterSize is the size label Ollama reported when the test ran, for example 4.3B (empty in older results).
+	ParameterSize string `json:"parameter_size,omitempty"`
+	// Quantization is the compression level Ollama reported when the test ran, for example Q4_K_M (empty in older results).
+	Quantization string `json:"quantization,omitempty"`
 	// Runs is how many timed runs the medians come from.
 	Runs int `json:"runs"`
 	// AnswerSpeed is the median answer speed in tokens per second.
 	AnswerSpeed float64 `json:"answer_speed,omitempty"`
 	// PromptSpeed is the median prompt reading speed in tokens per second.
 	PromptSpeed float64 `json:"prompt_speed,omitempty"`
+	// CharSpeed is the median writing speed in characters per second; characters are counted the same way for every model, unlike tokens (zero in older results).
+	CharSpeed float64 `json:"char_speed,omitempty"`
+	// AnswerChars is the number of characters the model wrote in the last timed run, answer and reasoning together (a count only, never the text).
+	AnswerChars int64 `json:"answer_chars,omitempty"`
 	// ColdLoadSec is the load time of the warm-up run, which loaded the model.
 	ColdLoadSec float64 `json:"cold_load_sec,omitempty"`
 	// ColdFirstWordSec is the measured time to the first word of the warm-up run.
@@ -293,6 +307,8 @@ func runGenerate(ctx context.Context, base *url.URL, model string) (perfFigures,
 				// Say what it said, shortened.
 				return perfFigures{}, fmt.Errorf("Ollama stopped the test: %s", shortMessage(line))
 			} // end of the error check
+			// Count the characters the model wrote, answer and reasoning together, because the writing time covers both; only the number is kept.
+			f.AnswerChars += utf8.RuneCountInString(p.Response) + utf8.RuneCountInString(p.Thinking)
 			// The first piece of output, whether answer or reasoning, ends the wait for the first word.
 			if !f.GotFirstWord && (p.Response != "" || p.Thinking != "") {
 				// Remember how long it took.
@@ -361,11 +377,13 @@ func runEmbed(ctx context.Context, base *url.URL, model string) (perfFigures, er
 } // end of runEmbed
 
 // performTest runs the whole test on one model that is not loaded: one warm-up run (which loads it), then timed runs, then it reads what Ollama reports and unloads the model again. The result holds numbers only.
-func performTest(ctx context.Context, base *url.URL, model string, embedding bool, version string) (run perfRun, err error) {
+func performTest(ctx context.Context, base *url.URL, model string, embedding bool, version string, info modelDetails) (run perfRun, err error) {
 	// Is Ollama on this same computer? Only then do the machine figures describe it.
 	local := isLocalAddress(base)
 	// The result starts with the facts known before the test.
 	run = perfRun{Time: time.Now().UTC(), Model: model, Kind: "generate", OllamaVersion: version, Host: base.Host, PromptVersion: perfPromptVersion, Runs: perfTimedRuns}
+	// What Ollama says about the model, so the comparison can group it by size and precision later even when the model is gone.
+	run.Family, run.ParameterSize, run.Quantization = info.Family, info.ParameterSize, info.QuantizationLevel
 	// An embedding model is tested differently.
 	if embedding {
 		// Mark it.
@@ -442,11 +460,13 @@ func performTest(ctx context.Context, base *url.URL, model string, embedding boo
 		timed = append(timed, f)
 	} // end of the timed loop
 	// Collect each figure over the timed runs.
-	var answer, prompt, firstWord, total []float64
+	var answer, prompt, firstWord, total, chars []float64
 	// Go through the runs.
 	for _, f := range timed {
 		// Answer speed.
 		answer = append(answer, perSecond(f.EvalCount, f.EvalNs))
+		// Answer speed in characters per second (the same unit for every model).
+		chars = append(chars, perSecond(int64(f.AnswerChars), f.EvalNs))
 		// Prompt reading speed.
 		prompt = append(prompt, perSecond(f.PromptCount, f.PromptNs))
 		// First word, when one was seen.
@@ -459,6 +479,8 @@ func performTest(ctx context.Context, base *url.URL, model string, embedding boo
 	} // end of the loop
 	// The medians.
 	run.AnswerSpeed, run.PromptSpeed, run.WarmFirstWordSec, run.WarmTotalSec = median(answer), median(prompt), median(firstWord), median(total)
+	// The median speed in characters per second.
+	run.CharSpeed = median(chars)
 	// The cold figures.
 	run.ColdLoadSec = secs(cold.LoadNs)
 	// The cold first word.
@@ -470,6 +492,8 @@ func performTest(ctx context.Context, base *url.URL, model string, embedding boo
 	last := timed[len(timed)-1]
 	// Tokens in and out, and the vector length.
 	run.TokensIn, run.TokensOut, run.VectorLength = last.PromptCount, last.EvalCount, last.VectorLength
+	// The number of characters of the last answer.
+	run.AnswerChars = int64(last.AnswerChars)
 	// What Ollama reports about the loaded model.
 	if list, lerr := fetchLoaded(ctx, base, defaultCheckTimeout); lerr == nil {
 		// Find the tested model.
diff --git a/perf_test.go b/perf_test.go
index 3494246..c18497f 100644
--- a/perf_test.go
+++ b/perf_test.go
@@ -93,7 +93,7 @@ func (f *perfFake) start(t *testing.T) string {
 		// The installed models.
 		case "/api/tags":
 			// Four models: a chat model, a thinking model, an embedding model and one with no known ability.
-			w.Write([]byte(`{"models":[{"name":"chat:1b","size":3300000000,"details":{"family":"llama"},"capabilities":["completion"]},{"name":"think:1b","size":3300000000,"details":{"family":"llama"},"capabilities":["completion","thinking"]},{"name":"embed:1b","size":2000000000,"details":{"family":"bert"},"capabilities":["embedding"]},{"name":"odd:1b","size":1000,"details":{"family":"x"},"capabilities":[]}]}`))
+			w.Write([]byte(`{"models":[{"name":"chat:1b","size":3300000000,"details":{"family":"llama","parameter_size":"1.2B","quantization_level":"Q4_K_M"},"capabilities":["completion"]},{"name":"think:1b","size":3300000000,"details":{"family":"llama","parameter_size":"1.2B","quantization_level":"Q4_K_M"},"capabilities":["completion","thinking"]},{"name":"embed:1b","size":2000000000,"details":{"family":"bert","parameter_size":"335M","quantization_level":"F16"},"capabilities":["embedding"]},{"name":"odd:1b","size":1000,"details":{"family":"x"},"capabilities":[]}]}`))
 		// The loaded models.
 		case "/api/ps":
 			// Build the list from the fake's state.
diff --git a/perfpage.go b/perfpage.go
index fadc72b..33f9b1c 100644
--- a/perfpage.go
+++ b/perfpage.go
@@ -495,14 +495,14 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore, hist *hist
 		// Send the finished page.
 		w.Write(buf.Bytes())
 	} // end of show
-	// check runs the checks the start and the run share: the form, the model installed, not loaded, and able to be tested; ok is false after a page was shown.
-	check := func(w http.ResponseWriter, r *http.Request) (string, bool, bool) {
+	// check runs the checks the start and the run share: the form, the model installed, not loaded, and able to be tested; it also returns what Ollama says about the model; ok is false after a page was shown.
+	check := func(w http.ResponseWriter, r *http.Request) (string, bool, modelDetails, bool) {
 		// The form checks: same page, valid token, sensible model name.
 		name, ok := readModelForm(w, r, token)
 		// A refusal was already sent.
 		if !ok {
 			// Stop here.
-			return "", false, false
+			return "", false, modelDetails{}, false
 		} // end of the form checks
 		// Read the installed models now, not what the page showed earlier.
 		installed, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
@@ -511,7 +511,7 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore, hist *hist
 			// Show the plain reason.
 			show(w, r, http.StatusBadGateway, perfPage{Kind: "error", Model: name, Detail: err.Error()})
 			// Stop here.
-			return "", false, false
+			return "", false, modelDetails{}, false
 		} // end of the installed read check
 		// The model must exist.
 		m, found := findInstalled(installed, name)
@@ -520,7 +520,7 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore, hist *hist
 			// Say so.
 			show(w, r, http.StatusOK, perfPage{Kind: "notinstalled", Model: name})
 			// Stop here.
-			return "", false, false
+			return "", false, modelDetails{}, false
 		} // end of the installed check
 		// Read the loaded models.
 		loaded, err := fetchLoaded(r.Context(), addr.URL, defaultCheckTimeout)
@@ -529,30 +529,30 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore, hist *hist
 			// Show the plain reason.
 			show(w, r, http.StatusBadGateway, perfPage{Kind: "error", Model: name, Detail: err.Error()})
 			// Stop here.
-			return "", false, false
+			return "", false, modelDetails{}, false
 		} // end of the loaded read check
 		// A loaded model may be in use: the test is refused.
 		if _, ok := findLoaded(loaded, name); ok {
 			// Say so.
 			show(w, r, http.StatusOK, perfPage{Kind: "loaded", Model: name})
 			// Stop here.
-			return "", false, false
+			return "", false, modelDetails{}, false
 		} // end of the loaded check
 		// Which kind of test fits the model.
 		switch categorize(m.Capabilities) {
 		// Embedding models are tested by embedding.
 		case categoryEmbedding:
 			// An embedding test.
-			return name, true, true
+			return name, true, m.Details, true
 		// Models that write text.
 		case categoryText, categoryMultimodal:
 			// A generate test.
-			return name, false, true
+			return name, false, m.Details, true
 		} // end of the switch
 		// Anything else cannot be tested.
 		show(w, r, http.StatusOK, perfPage{Kind: "unsupported", Model: name})
 		// Stop here.
-		return "", false, false
+		return "", false, modelDetails{}, false
 	} // end of check
 	// historyFor fills the history part of a page for one model.
 	historyFor := func(p *perfPage, name string, embedding bool) {
@@ -581,7 +581,7 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore, hist *hist
 	// start is the first step: it explains the test and the risks, and shows earlier results; it changes nothing.
 	start := func(w http.ResponseWriter, r *http.Request) {
 		// The checks.
-		name, embedding, ok := check(w, r)
+		name, embedding, _, ok := check(w, r)
 		// A page was already shown.
 		if !ok {
 			// Stop here.
@@ -599,7 +599,7 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore, hist *hist
 	// run is the second step: it runs the test, saves the numbers and shows them.
 	run := func(w http.ResponseWriter, r *http.Request) {
 		// The checks.
-		name, embedding, ok := check(w, r)
+		name, embedding, info, ok := check(w, r)
 		// A page was already shown.
 		if !ok {
 			// Stop here.
@@ -624,7 +624,7 @@ func perfHandlers(addr ollamaAddress, token string, store *perfStore, hist *hist
 		// The Ollama version, for the record.
 		version := checkOllama(r.Context(), addr.URL, defaultCheckTimeout).Version
 		// Run the test.
-		res, err := performTest(r.Context(), addr.URL, name, embedding, version)
+		res, err := performTest(r.Context(), addr.URL, name, embedding, version, info)
 		// The test failed.
 		if err != nil {
 			// Show the plain reason; the model was unloaded again by the test itself.
diff --git a/references.go b/references.go
new file mode 100644
index 0000000..02428b0
--- /dev/null
+++ b/references.go
@@ -0,0 +1,115 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+// reference is one source that the comparison page cites. Every entry was opened and read, and its title, authors and address were copied from the page itself.
+type reference struct {
+	// N is the number shown in brackets in the text, starting at 1 without gaps.
+	N int
+	// Authors names the people or the organisation behind the source.
+	Authors string
+	// Title is the exact title of the source.
+	Title string
+	// Where says what kind of source it is and any version or date the page itself shows.
+	Where string
+	// URL is the exact address that was opened.
+	URL string
+	// Used says in one sentence what this page takes from the source.
+	Used string
+} // end of reference
+
+// referencesChecked is the day the addresses were opened and read, written the way the page shows it.
+const referencesChecked = "27 October 2026"
+
+// compareReferences is the verified list of sources. Nothing may be added unless the page behind it was opened and read, and a test keeps the list, the markers in the page text and the allowed addresses in step.
+var compareReferences = []reference{
+	// Source 1.
+	{
+		// Number.
+		N: 1,
+		// Authors as the page shows them.
+		Authors: "Vinh Nguyen, Wenwen Gao, Emily Apsey, Ganesh Kudleppanavar, Neelay Shah and Elias Bermudez (NVIDIA)",
+		// Title as the page shows it.
+		Title: "LLM Inference Benchmarking: Fundamental Concepts",
+		// Kind and date.
+		Where: "Blog article, 2 April 2025",
+		// Address.
+		URL: "https://developer.nvidia.com/blog/llm-benchmarking-fundamental-concepts",
+		// What we take from it.
+		Used: "Fix the workload and the sampling, leave the warm-up out, and match the test to the real use.",
+	}, // end of source 1
+	// Source 2.
+	{
+		// Number.
+		N: 2,
+		// Authors.
+		Authors: "NVIDIA",
+		// Title.
+		Title: "Metrics (LLM section of the NVIDIA NIM Benchmarking Documentation)",
+		// Kind and version.
+		Where: "Documentation, version 2.0.0 (Latest) when read",
+		// Address.
+		URL: "https://docs.nvidia.com/nim/benchmarking/llm/latest/metrics.html",
+		// What we take from it.
+		Used: "Definitions of the speed and delay figures, and the rule to compare results only when the definitions align.",
+	}, // end of source 2
+	// Source 3.
+	{
+		// Number.
+		N: 3,
+		// Authors.
+		Authors: "Artificial Analysis",
+		// Title.
+		Title: "Artificial Analysis Language Model API Performance Benchmarking Methodology",
+		// Kind and version.
+		Where: "Methodology page, version 2.2.0 (2 March 2026) in its version history",
+		// Address.
+		URL: "https://artificialanalysis.ai/methodology/performance-benchmarking",
+		// What we take from it.
+		Used: "The median of repeated runs, the same settings for every model, and one common way of counting tokens so that models with different tokenizers can be compared.",
+	}, // end of source 3
+	// Source 4.
+	{
+		// Number.
+		N: 4,
+		// Authors.
+		Authors: "Vijay Janapa Reddi and others",
+		// Title.
+		Title: "MLPerf Inference Benchmark",
+		// Kind and date.
+		Where: "arXiv preprint 1911.02549, version 2, 9 May 2020",
+		// Address.
+		URL: "https://arxiv.org/abs/1911.02549",
+		// What we take from it.
+		Used: "The one-query-at-a-time (single-stream) scenario, fixed rules for results that are to be compared, and the rule that results under different rules are not directly comparable.",
+	}, // end of source 4
+	// Source 5.
+	{
+		// Number.
+		N: 5,
+		// Authors.
+		Authors: "Ollama",
+		// Title.
+		Title: "Usage (Ollama API documentation)",
+		// Kind and date.
+		Where: "Documentation page",
+		// Address.
+		URL: "https://docs.ollama.com/api/usage",
+		// What we take from it.
+		Used: "The meaning of the timing and token-count fields that every figure here is worked out from; durations are in nanoseconds.",
+	}, // end of source 5
+	// Source 6.
+	{
+		// Number.
+		N: 6,
+		// Authors.
+		Authors: "Niklas Muennighoff, Nouamane Tazi, Loïc Magne and Nils Reimers",
+		// Title.
+		Title: "MTEB: Massive Text Embedding Benchmark",
+		// Kind and date.
+		Where: "arXiv preprint 2210.07316, version 3",
+		// Address.
+		URL: "https://arxiv.org/abs/2210.07316v3",
+		// What we take from it.
+		Used: "Embedding models are benchmarked on their own tasks, and no single embedding method wins on every task.",
+	}, // end of source 6
+} // end of compareReferences
diff --git a/references_test.go b/references_test.go
new file mode 100644
index 0000000..66e29c1
--- /dev/null
+++ b/references_test.go
@@ -0,0 +1,178 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// net/url checks the form of every address.
+	"net/url"
+	// regexp finds the reference markers in the text.
+	"regexp"
+	// strconv turns the marker numbers into integers.
+	"strconv"
+	// strings joins and searches text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+) // end of imports
+
+// verifiedAddresses are the exact addresses that were opened and read in the session that wrote the list; a source may only be added here after its page was read.
+var verifiedAddresses = map[int]string{
+	// NVIDIA blog article.
+	1: "https://developer.nvidia.com/blog/llm-benchmarking-fundamental-concepts",
+	// NVIDIA NIM metrics page.
+	2: "https://docs.nvidia.com/nim/benchmarking/llm/latest/metrics.html",
+	// Artificial Analysis methodology.
+	3: "https://artificialanalysis.ai/methodology/performance-benchmarking",
+	// MLPerf Inference paper.
+	4: "https://arxiv.org/abs/1911.02549",
+	// Ollama API usage page.
+	5: "https://docs.ollama.com/api/usage",
+	// MTEB paper.
+	6: "https://arxiv.org/abs/2210.07316v3",
+} // end of verifiedAddresses
+
+// referenceMarker finds a number in brackets, such as [3].
+var referenceMarker = regexp.MustCompile(`\[(\d+)\]`)
+
+// citingTexts gathers every piece of text on the comparison page that may carry a reference marker.
+func citingTexts() []string {
+	// The method answers.
+	var out []string
+	// Each row.
+	for _, h := range howRows() {
+		// The answer.
+		out = append(out, h.Answer)
+	} // end of the loop
+	// The reasons of every kind of group.
+	for _, k := range []int{0, 1, 2, 3, 4, classUnknown, -2} {
+		// The reason.
+		out = append(out, groupWhy(k))
+	} // end of the group loop
+	// The first sentence of the findings.
+	p := buildCompare([]perfRun{okRun("a:4b", 100)}, 0, nil, false)
+	// All findings.
+	out = append(out, p.Findings...)
+	// The cautions.
+	out = append(out, p.Notes...)
+	// The notice.
+	out = append(out, noticeShort)
+	// And the full notice.
+	out = append(out, noticeFull...)
+	// The texts.
+	return out
+} // end of citingTexts
+
+// TestReferenceListIsWellFormedAndVerified checks the list entry by entry: numbering, content and the exact verified addresses.
+func TestReferenceListIsWellFormedAndVerified(t *testing.T) {
+	// The list must not be empty and must match the verified set in size.
+	if len(compareReferences) == 0 || len(compareReferences) != len(verifiedAddresses) {
+		// Stop the test.
+		t.Fatalf("%d references, %d verified", len(compareReferences), len(verifiedAddresses))
+	} // end of the size check
+	// Addresses seen so far.
+	seen := map[string]bool{}
+	// Check each entry.
+	for i, r := range compareReferences {
+		// Numbers run from 1 without gaps.
+		if r.N != i+1 {
+			// Report it.
+			t.Errorf("entry %d has number %d", i, r.N)
+		} // end of the number check
+		// No field may be empty.
+		for name, v := range map[string]string{"authors": r.Authors, "title": r.Title, "where": r.Where, "url": r.URL, "used": r.Used} {
+			// An empty field.
+			if strings.TrimSpace(v) == "" {
+				// Report it.
+				t.Errorf("reference %d has an empty %s", r.N, name)
+			} // end of the check
+		} // end of the field loop
+		// The address must be exactly the one that was opened.
+		if r.URL != verifiedAddresses[r.N] {
+			// Report it.
+			t.Errorf("reference %d address %q is not the verified %q", r.N, r.URL, verifiedAddresses[r.N])
+		} // end of the address check
+		// The address must be a plain https address with a host, and no password, query tricks or fragment.
+		u, err := url.Parse(r.URL)
+		// A parse failure.
+		if err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" {
+			// Report it.
+			t.Errorf("reference %d address is not a plain https address: %q", r.N, r.URL)
+		} // end of the form check
+		// No address twice.
+		if seen[r.URL] {
+			// Report it.
+			t.Errorf("address %q appears twice", r.URL)
+		} // end of the repeat check
+		// Remember it.
+		seen[r.URL] = true
+	} // end of the loop
+	// The date of the reading is written the way the page shows it.
+	if !regexp.MustCompile(`^\d{1,2} [A-Z][a-z]+ 20\d\d$`).MatchString(referencesChecked) {
+		// Report it.
+		t.Errorf("referencesChecked = %q", referencesChecked)
+	} // end of the date check
+} // end of TestReferenceListIsWellFormedAndVerified
+
+// TestEveryMarkerPointsAtAReferenceAndEveryReferenceIsCited checks the text and the list agree in both directions.
+func TestEveryMarkerPointsAtAReferenceAndEveryReferenceIsCited(t *testing.T) {
+	// Which numbers are cited anywhere.
+	cited := map[int]bool{}
+	// Every text.
+	for _, text := range citingTexts() {
+		// Every marker in it.
+		for _, m := range referenceMarker.FindAllStringSubmatch(text, -1) {
+			// The number.
+			n, _ := strconv.Atoi(m[1])
+			// It must exist.
+			if n < 1 || n > len(compareReferences) {
+				// Report it.
+				t.Errorf("marker [%d] points at no reference in: %.60s", n, text)
+			} // end of the existence check
+			// Remember it.
+			cited[n] = true
+		} // end of the marker loop
+	} // end of the text loop
+	// Every reference must be cited at least once, so the list holds nothing that the text does not use.
+	for _, r := range compareReferences {
+		// Not cited.
+		if !cited[r.N] {
+			// Report it.
+			t.Errorf("reference %d is never cited", r.N)
+		} // end of the check
+	} // end of the loop
+	// The claims that must carry a source: the method rows about test design, token counting, groups and embedding models.
+	need := map[string][]string{
+		// How a test is run.
+		"How is a test run?": {"[1]", "[3]"},
+		// Why characters.
+		"Why characters per second?": {"[3]"},
+		// What is measured.
+		"What is measured?": {"[4]"},
+		// The figures come from Ollama.
+		"How are the figures worked out?": {"[5]"},
+		// Nothing across groups.
+		"Why is nothing ranked across groups?": {"[2]", "[4]"},
+		// Embedding models.
+		"How are the groups chosen?": {"[6]"},
+	} // end of the needs
+	// Check each.
+	for _, h := range howRows() {
+		// The markers needed here.
+		for _, m := range need[h.Question] {
+			// Missing.
+			if !strings.Contains(h.Answer, m) {
+				// Report it.
+				t.Errorf("%q lacks marker %s", h.Question, m)
+			} // end of the check
+		} // end of the marker loop
+	} // end of the row loop
+	// The statements that are the program's own choice say so in plain words.
+	own := strings.Join(citingTexts(), "\n")
+	// The words.
+	for _, w := range []string{"this program's own choice, not an industry standard", "this program's own rule", "these two formulas are this program's own calculations"} {
+		// Missing, ignoring case.
+		if !strings.Contains(strings.ToLower(own), w) {
+			// Report it.
+			t.Errorf("the page does not say %q", w)
+		} // end of the check
+	} // end of the loop
+} // end of TestEveryMarkerPointsAtAReferenceAndEveryReferenceIsCited
diff --git a/tooltips.go b/tooltips.go
index 0ac7e87..587b87e 100644
--- a/tooltips.go
+++ b/tooltips.go
@@ -421,24 +421,24 @@ var helpTexts = map[string]tooltip{
 		// What it helps with.
 		Decide: "Whether the figures are recent enough to trust.",
 	}, // end of Tested on
-	// The comparison page: speed against the fastest model.
+	// The comparison page: place in the ranking of the group.
 	"Speed vs fastest": {
 		// What it tells you.
-		Plain: "How this model compares with the fastest model in the same table.",
-		// A real case from the test machine.
-		Example: "medgemma:latest writes 80 tokens/s and qwen3.6:27b 36, so the second is 2.2× slower.",
+		Plain: "Its place among the like-for-like models of its group, and how many times slower than the first it is.",
+		// A real case.
+		Example: "#1, fastest leads its group. \"not ranked\" means a caution in the last column keeps the row out of the ranking.",
 		// What it helps with.
-		Decide: "Which model to pick when speed matters more than size.",
+		Decide: "Which model to pick when speed matters, without comparing unlike models.",
 	}, // end of Speed vs fastest
-	// The comparison page: rough words per second.
-	"Words per second": {
+	// The comparison page: speed in characters per second.
+	"Characters per second": {
 		// What it tells you.
-		Plain: "A rough reading speed: the answer speed times 0.75, since a word is about three quarters of a token.",
-		// A real case from the test machine.
-		Example: "36 tokens/s is about 27 words per second, faster than a person reads.",
+		Plain: "How many characters the model writes each second. Counted the same way for every model, so makers can be compared.",
+		// A real case.
+		Example: "Models cut text into tokens differently, so 40 tokens/s from two makers can differ; characters do not.",
 		// What it helps with.
-		Decide: "Whether answers will feel instant or slow.",
-	}, // end of Words per second
+		Decide: "Which model is really faster at writing the same kind of answer.",
+	}, // end of Characters per second
 	// The comparison page: load speed.
 	"Load speed from disk": {
 		// What it tells you.
@@ -448,15 +448,6 @@ var helpTexts = map[string]tooltip{
 		// What it helps with.
 		Decide: "How long a model keeps you waiting after it was unloaded.",
 	}, // end of Load speed from disk
-	// The comparison page: speed for each gigabyte of memory.
-	"Speed per GB of memory": {
-		// What it tells you.
-		Plain: "Answer speed divided by the memory the model uses: how much speed each gigabyte buys.",
-		// A real case from the test machine.
-		Example: "medgemma:latest: 80 tokens/s on 3.8 GB (gigabytes) is about 21 tokens/s for each GB (gigabytes).",
-		// What it helps with.
-		Decide: "Which model gives the most speed for the memory it takes.",
-	}, // end of Speed per GB of memory
 	// The comparison page: busy machine.
 	"Machine busy": {
 		// What it tells you.
@@ -466,6 +457,15 @@ var helpTexts = map[string]tooltip{
 		// What it helps with.
 		Decide: "Whether to repeat the test when the machine is idle.",
 	}, // end of Machine busy
+	// The comparison page: whether a row can be ranked.
+	"Fair to rank?": {
+		// What it tells you.
+		Plain: "Whether this test is like the others of its group. If not, the reasons are shown and the row is not ranked.",
+		// A real case.
+		Example: "A model tested two days before the others, or with a different precision, is not ranked.",
+		// What it helps with.
+		Decide: "Whether to trust a ranking, or to test the models again together.",
+	}, // end of Fair to rank
 	// The performance page: change since the previous run.
 	"Change since the previous run": {
 		// What it tells you.
diff --git a/web.go b/web.go
index d884447..d933256 100644
--- a/web.go
+++ b/web.go
@@ -171,6 +171,12 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	mux.HandleFunc("POST /performance/clear/model/confirm", perfClearOneDo)
 	// Route: a POST request for "/compare" shows the comparison of the tested models and changes nothing.
 	mux.HandleFunc("POST /compare", compareHandler(addr, token, perfHistory))
+	// The two downloads of the comparison: a PDF report and the data as CSV (both carry the notice; the checks are in compreport.go).
+	comparePDF, compareCSV := compareDownloadHandlers(addr, token, perfHistory)
+	// Route: a POST request for "/compare/pdf" sends the comparison as a PDF file.
+	mux.HandleFunc("POST /compare/pdf", comparePDF)
+	// Route: a POST request for "/compare/csv" sends the data as a CSV file.
+	mux.HandleFunc("POST /compare/csv", compareCSV)
 	// Route: a POST request for "/watch" pauses or resumes the automatic updates of the page.
 	mux.HandleFunc("POST /watch", watchHandler(token))
 	// The two steps of stopping the monitor.
diff --git a/web/app.css b/web/app.css
index 983ba0c..6e8aa52 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1844,3 +1844,83 @@ html[data-size="medium"] svg[width="22"] {
   /* No margins inside the row. */
   margin: 0;
 } /* end of rule */
+
+/* The comparison page: a bordered notice box that stands apart from the text around it, readable without colour. */
+.cmpnotice {
+  /* A clear outline. */
+  border: 1px solid var(--border);
+  /* The page background, so the box reads as a separate area. */
+  background: var(--bg);
+  /* Room inside the box. */
+  padding: 0.6rem 0.8rem;
+  /* Room around the box. */
+  margin: 1rem 0;
+} /* end of rule */
+
+/* Paragraphs inside the notice box sit close together. */
+.cmpnotice p {
+  /* A small gap. */
+  margin: 0.4rem 0;
+} /* end of rule */
+
+/* The bar above a group: a thick line on the left marks the start of a group. */
+.cmpgroup {
+  /* The thick line, in the accent colour that is also used for the categories. */
+  border-left: 6px solid var(--cat-accent);
+  /* Space between the line and the heading. */
+  padding-left: 0.8rem;
+  /* Room above and below. */
+  margin: 1.6rem 0 0.4rem;
+} /* end of rule */
+
+/* The heading inside the bar needs no outer space of its own. */
+.cmpgroup h2 {
+  /* No extra space. */
+  margin: 0;
+} /* end of rule */
+
+/* The line that says why the models of a group are compared together. */
+.cmpwhy {
+  /* The category colours, so it reads as part of the group. */
+  background: var(--cat-bg);
+  /* Text that is readable on that background in both themes. */
+  color: var(--cat-text);
+  /* Room inside. */
+  padding: 0.5rem 0.7rem;
+  /* Room around. */
+  margin: 0.4rem 0;
+} /* end of rule */
+
+/* The row of download buttons. */
+.cmpactions {
+  /* Side by side, wrapping on a narrow window. */
+  display: flex;
+  /* A gap between the buttons. */
+  gap: 0.6rem;
+  /* Wrap instead of overflowing. */
+  flex-wrap: wrap;
+  /* Line the buttons up. */
+  align-items: center;
+  /* Room above and below. */
+  margin: 0.6rem 0;
+} /* end of rule */
+
+/* A form that holds only a button needs no outer space. */
+.cmpactions form {
+  /* No space. */
+  margin: 0;
+} /* end of rule */
+
+/* The reference list: long addresses may break anywhere so nothing runs off the screen. */
+.cmprefs {
+  /* The "[n]" in each entry is the number, so the list adds none of its own. */
+  list-style: none;
+  /* No indent, because there is no list number to make room for. */
+  padding-left: 0;
+} /* end of rule */
+.cmprefs li {
+  /* Room between entries. */
+  margin: 0.45rem 0;
+  /* Break long addresses. */
+  overflow-wrap: anywhere;
+} /* end of rule */
diff --git a/web/compare.html b/web/compare.html
index 4c5be02..479a5f8 100644
--- a/web/compare.html
+++ b/web/compare.html
@@ -1,4 +1,4 @@
-{{/* Comparison page: the latest saved performance test of each model side by side. The comments are template comments, so they never reach the browser. */}}
+{{/* Comparison page: the latest saved performance test of each model, in groups that may be compared like for like, with the method, the references and the notice. The comments are template comments, so they never reach the browser. */}}
 <!DOCTYPE html>
 {{/* lang tells screen readers which language the page is written in. */}}
 <html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}{{if .Size}} data-size="{{.Size}}"{{end}}>
@@ -19,31 +19,42 @@
 <section class="panel">
 {{/* The page heading. */}}
 <h1>Compare models</h1>
+{{/* The short notice, always at the top, with a link to the full text at the bottom. */}}
+<div class="cmpnotice" role="note"><strong>Important notice.</strong> {{.NoticeShort}} <a href="#notice">Read the full notice</a>.</div>
 {{/* Nothing saved yet. */}}
 {{if .Empty}}
 <p>No model has been through a performance test yet. Use the chart icon before a model name on the monitor page to test one, then come back here.</p>
 {{range .Notes}}<p class="muted">{{.}}</p>{{end}}
 {{else}}
+{{/* The two downloads and the jump to the method; each download is a small form that changes nothing. */}}
+<div class="cmpactions">
+<form method="post" action="/compare/pdf"><input type="hidden" name="token" value="{{.Token}}"><button type="submit" class="btn-plain">Download this comparison (PDF)</button></form>
+<form method="post" action="/compare/csv"><input type="hidden" name="token" value="{{.Token}}"><button type="submit" class="btn-plain">Download the data (CSV)</button></form>
+<a class="btn-plain" href="#how">How and why this was done</a>
+</div>
 {{/* What the figures say, in plain words. */}}
-{{if .Findings}}
 <h2>What the figures say</h2>
 <ul>
 {{range .Findings}}<li>{{.}}</li>{{end}}
 </ul>
-{{end}}
-{{/* One table for each kind of model. */}}
-{{range $t := .Tables}}
-<h2>{{$t.Title}}</h2>
-<p class="muted">{{$t.Note}}</p>
+{{/* One block for each group of models that may be compared with each other. */}}
+{{range $g := .Groups}}
+<div class="cmpgroup"><h2>{{$g.Title}}</h2></div>
+{{/* Why these models are compared together. */}}
+<p class="cmpwhy"><strong>Why this group:</strong> {{$g.Why}}</p>
+{{/* The fastest model of the group, when there is a ranking. */}}
+{{if $g.Headline}}<p><strong>{{$g.Headline}}</strong></p>{{end}}
+{{/* Why there is no ranking, or that the model has no peer. */}}
+{{range $g.Notes}}<p class="muted">{{.}}</p>{{end}}
 {{/* The scroll box, reachable with Tab so keyboard users can scroll the table sideways. */}}
-<div class="scrollbox" tabindex="0" role="region" aria-label="{{$t.Title}}, scrolls sideways">
+<div class="scrollbox" tabindex="0" role="region" aria-label="{{$g.Title}}, scrolls sideways">
 <table class="models comparetable">
 {{/* The column headings, each with its help bubble; the first stays in view. */}}
-<thead><tr>{{range $i, $c := $t.Cols}}<th scope="col"{{if eq $i 0}} class="stickycol"{{end}}>{{template "tipbox" $c}}</th>{{end}}</tr></thead>
+<thead><tr>{{range $i, $c := $g.Cols}}<th scope="col"{{if eq $i 0}} class="stickycol"{{end}}>{{template "tipbox" $c}}</th>{{end}}</tr></thead>
 <tbody>
-{{/* One row for each model; a busy test is marked with a symbol and words, never colour alone. */}}
-{{range $r := $t.Rows}}
-<tr>{{range $i, $c := $r.Cells}}{{if eq $i 0}}<th scope="row" class="stickycol">{{$c}}{{if $r.Busy}} <span aria-label="measured on a busy machine" title="measured on a busy machine">⚠</span>{{end}}</th>{{else}}<td>{{$c}}</td>{{end}}{{end}}</tr>
+{{/* One row for each model. */}}
+{{range $r := $g.Rows}}
+<tr>{{range $i, $c := $r.Cells}}{{if eq $i 0}}<th scope="row" class="stickycol">{{$c}}</th>{{else}}<td>{{$c}}</td>{{end}}{{end}}</tr>
 {{end}}
 </tbody>
 </table>
@@ -54,7 +65,30 @@
 <ul>
 {{range .Notes}}<li>{{.}}</li>{{end}}
 </ul>
+{{/* The method: every answer carries numbers that point to the reference list. */}}
+<h2 id="how">How and why this comparison was done</h2>
+<table class="settingtable">
+<thead><tr><th scope="col">Question</th><th scope="col">Answer</th></tr></thead>
+<tbody>
+{{range .How}}
+<tr><th scope="row">{{.Question}}</th><td data-label="Answer">{{.Answer}}</td></tr>
+{{end}}
+</tbody>
+</table>
+{{/* The references: the sources the method is based on, each opened and read. */}}
+<h2 id="references">References</h2>
+<ol class="cmprefs">
+{{range .Refs}}
+<li id="ref{{.N}}">[{{.N}}] {{.Authors}}. <em>{{.Title}}</em>. {{.Where}}. <a href="{{.URL}}" target="_blank" rel="noopener noreferrer">{{.URL}}<span class="sr-only"> (opens in a new window)</span></a> Used here for: {{.Used}}</li>
 {{end}}
+</ol>
+<p class="muted">The addresses were opened and read on {{.RefsChecked}}. A web page can change or disappear later.</p>
+{{end}}
+{{/* The full notice. */}}
+<h2 id="notice">{{.NoticeTitle}}</h2>
+<div class="cmpnotice">
+{{range .NoticeFull}}<p>{{.}}</p>{{end}}
+</div>
 {{/* Where the figures come from. */}}
 {{if .SaveNote}}<p class="muted">{{.SaveNote}}</p>{{end}}
 {{/* The way back. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
ad0de53f936854dfad2c1f042063b2bfbeb568b9d112d3f2cf951b2b2a7e4ba2  about.go
e8a94857e1b6c72f5e47b0f902194fad0c4a8c431397ce13a309edbc1f440f6d  brand_test.go
2c398b3b86193a30d79de9ba44df9317a557c7538593a413d3872aee661c1eba  compare.go
2f6351e94d0dc1e9af0643af7a304e98d3fbb166c099f0b1cf07f635da481931  compare_test.go
4732c02a910c6d6817cbcc31dc9555db2772ce9716fb56a23f4a495b2d0d19e4  perf.go
38c0f0cc11bad748051f850be3e94eec0bd49adc7db12e7a73a4f702729e65f6  perf_test.go
2d74813b7836f2bc2fa48970a87d5d9ea976c8b5322194cda781190b50bac279  perfpage.go
b6088a9fe66ec43d467557fc4ec15858aa7633d338a4263ab3a75cc2e3a0151f  tooltips.go
0d12104ae7ce76872e40e90742c52f2956ae97bf0f34ef26b5d8650193183300  web.go
6998f3f1226ac33159824315d04a216332c845290491e37e7b3cc475b73ae0fc  web/app.css
0b1dc1700614e16ef013c7752e7d2272d93614b49727cf2e5aa10e230be4e112  web/compare.html
47d5b6eefedd1b05efdbfeb3173de582e2573d8b369f15d6be4ab5e8f6a7c0fa  compgroup.go
5dd0ab4d2d9b20b49c1e839646eb8631d82b04c5cbe8b3b1ef96f4ac9a222a85  compreport.go
5556e8d14f68285ffd1dd43661defbb9aafcf14855120a3a507fd39fcef92c55  compreport_test.go
197f83c590b41cf1ca612a19b6e88939bb99dff45c2df83f973217db631ebc00  notice.go
1113deba7a29e25a4cf43c564e2aca0928bcc73aba7bf8a92b70d4628d15495e  notice_test.go
e27f7d3d5d5a8b906cad794def3ba0a6fb38aa933e91e3338bcd28c322681d35  pdf.go
2a67f9ab4a379ace10ea2cc50d0b692a218313491f8cef7212c5bf59bf2b35a9  pdf_test.go
0285891162db3fc9fbfcea679edca298f7c9a9a12dd85e8acbddfa04da490b8c  pdfwidths.go
e3bf41c23b7420306fd133faa65d135d1fd8edaad52c6cffde10526a7a7be85c  references.go
db8c8b14047111da90c25e91c7a31370c23c060c9ba718dfdc065f7f9cc14fa9  references_test.go
SUMS_END
# Compare the real fingerprints with the expected ones.
if sha256sum --check --quiet "$PATCH_FILE.sums"; then
  # The files are exactly as tested.
  echo "PASS  the files are exactly the tested version"
else
  # Something differs; stop before testing.
  echo "FAIL  a file differs from the tested version"; exit 1
fi
# Check the formatting of the Go files (no output means all is well).
[ -z "$(gofmt -l .)" ] || { echo "FAIL  gofmt reports unformatted files"; gofmt -l .; exit 1; }
# Report the check.
echo "PASS  gofmt"
# Run Go's own checker for suspicious code.
go vet ./...
# Report the check.
echo "PASS  go vet"
# Run every test.
go test ./...
# Report the check.
echo "PASS  tests"
# Build the executable the same way as before.
CGO_ENABLED=0 go build -trimpath -o bin/OllamaControlCenter .
# Report the check.
echo "PASS  build"
# Stop any monitor that is still running the old build (a leftover one would keep showing the old page).
pkill -f "bin/OllamaControlCenter" || true
# Give it a moment to exit.
sleep 1
# Confirm that none is left.
if pgrep -f "bin/OllamaControlCenter" > /dev/null; then
  # Report it.
  echo "FAIL  an old monitor is still running"; exit 1
fi
# Report the check.
echo "PASS  no old monitor is running; start the new one with: ./bin/OllamaControlCenter"
# List the changed files; nothing is committed yet.
git status --short
