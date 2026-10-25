#!/usr/bin/env bash
# Script 47: adds the model comparison page (scales icon beside the heading Model, one row per tested model, inferred columns and plain-words findings).
# Stop at the first error, on unset variables, and on a failure inside a pipe.
set -euo pipefail
# Go to the project folder (OCC_DIR lets a test run use another copy).
cd "${OCC_DIR:-/home/kodati/OllamaControlCenter}"
# Refuse to run anywhere but on the feature branch for this change.
[ "$(git branch --show-current)" = "feature/model-comparison" ] || { echo "FAIL  not on feature/model-comparison"; exit 1; }
# The performance feature (merged earlier) must be there.
[ -f perf.go ] && grep -q 'perfclear' web/performance.html || { echo "FAIL  the performance feature is not in this branch"; exit 1; }
# Refuse to run twice.
if [ -f compare.go ]; then
  # Say so and stop.
  echo "FAIL  this change is already applied"; exit 1
fi
# A temporary file that holds the change as a patch.
PATCH_FILE="$(mktemp)"
# Remove the temporary files when the script ends, however it ends.
trap 'rm -f "$PATCH_FILE" "$PATCH_FILE.sums"' EXIT
# Write the patch text below into the temporary file; the quoted word stops the shell from touching any character in it.
cat > "$PATCH_FILE" <<'PATCH_END'
diff --git a/compare.go b/compare.go
new file mode 100644
index 0000000..8f338a8
--- /dev/null
+++ b/compare.go
@@ -0,0 +1,573 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// bytes builds the page in memory before it is sent.
+	"bytes"
+	// embed lets the page template be stored inside the executable.
+	_ "embed"
+	// fmt formats the figures.
+	"fmt"
+	// html/template builds the page and escapes every value.
+	"html/template"
+	// log records a real failure for the person running the program.
+	"log"
+	// net/http serves the page.
+	"net/http"
+	// sort puts the rows in order.
+	"sort"
+	// strings joins text.
+	"strings"
+) // end of imports
+
+// compareTemplateText is the page template, stored inside the executable at build time.
+//
+//go:embed web/compare.html
+var compareTemplateText string
+
+// wordsPerToken is the rough number of English words in one token (a common rule of thumb, not a measurement).
+const wordsPerToken = 0.75
+
+// compareTextHeadings are the column headings of the table of text models, in order.
+var compareTextHeadings = []string{"Model", "Tested on", "Answer speed", "Speed vs fastest", "Words per second", "Prompt reading speed", "Time to first word", "Total time", "Load time", "Load speed from disk", "Memory used", "Processor split", "Speed per GB of memory", "Machine busy"}
+
+// compareEmbedHeadings are the column headings of the table of embedding models, in order.
+var compareEmbedHeadings = []string{"Model", "Tested on", "Embedding time", "Speed vs fastest", "Load time", "Load speed from disk", "Memory used", "Processor split", "Vector length", "Machine busy"}
+
+// compareExtraHeadings are the headings that exist only on the comparison page and need their own tooltip (the others are shared with the performance page).
+var compareExtraHeadings = []string{"Tested on", "Speed vs fastest", "Words per second", "Load speed from disk", "Speed per GB of memory", "Machine busy"}
+
+// cmpRow is one model in a comparison table.
+type cmpRow struct {
+	// Cells are the values, one for each column.
+	Cells []string
+	// Busy is true when the run was made on a busy machine, so the row can be marked.
+	Busy bool
+} // end of cmpRow
+
+// cmpTable is one comparison table.
+type cmpTable struct {
+	// Title is the heading above the table.
+	Title string
+	// Note is one sentence under the heading.
+	Note string
+	// Cols are the column headings with their help bubbles.
+	Cols []tipView
+	// Rows are the models.
+	Rows []cmpRow
+} // end of cmpTable
+
+// comparePage is everything the comparison template needs.
+type comparePage struct {
+	// Theme is the colour scheme asked for in the address, or empty.
+	Theme string
+	// Token is the page token for the "Back" form.
+	Token string
+	// Tables are the comparison tables (text models, embedding models).
+	Tables []cmpTable
+	// Findings are plain sentences read out of the figures.
+	Findings []string
+	// Notes are cautions about how to read the table.
+	Notes []string
+	// Empty is true when no test is saved yet.
+	Empty bool
+	// SaveNote says where the figures come from, or why there is no file.
+	SaveNote string
+} // end of comparePage
+
+// latestRuns returns the newest run of each model and kind that used the given prompt version, and how many models were skipped because their newest run used another prompt.
+func (s *perfStore) latestRuns(promptVersion string) ([]perfRun, int) {
+	// One reader at a time.
+	s.mu.Lock()
+	// Release at the end.
+	defer s.mu.Unlock()
+	// Which model and kind pairs were seen already.
+	seen := map[string]bool{}
+	// The result.
+	var out []perfRun
+	// How many were skipped.
+	skipped := 0
+	// Walk from the newest to the oldest.
+	for i := len(s.runs) - 1; i >= 0; i-- {
+		// The run.
+		r := s.runs[i]
+		// A key for the model and kind.
+		key := r.Kind + "|" + r.Model
+		// The newest run of this model is the only one that counts.
+		if seen[key] {
+			// Skip the older ones.
+			continue
+		} // end of the repeat check
+		// Remember it.
+		seen[key] = true
+		// A run with another prompt cannot be compared with the rest.
+		if r.PromptVersion != promptVersion {
+			// Count it.
+			skipped++
+			// Leave it out.
+			continue
+		} // end of the prompt check
+		// Keep it.
+		out = append(out, r)
+	} // end of the loop
+	// Hand them back.
+	return out, skipped
+} // end of latestRuns
+
+// cmpGB turns bytes into decimal gigabytes (the unit Ollama and the rest of this program use).
+func cmpGB(b int64) float64 {
+	// Decimal gigabytes.
+	return float64(b) / 1e9
+} // end of cmpGB
+
+// cmpSplit writes the processor split of a run in a short form.
+func cmpSplit(r perfRun) string {
+	// Without a size there is nothing to split.
+	if r.ModelBytes <= 0 {
+		// Say so.
+		return "not reported"
+	} // end of the size check
+	// The share on the graphics card.
+	gpu := float64(r.GPUBytes) / float64(r.ModelBytes) * 100
+	// The text.
+	return fmt.Sprintf("%.0f%% graphics card, %.0f%% processor", gpu, 100-gpu)
+} // end of cmpSplit
+
+// cmpBusy writes the busy column of a run.
+func cmpBusy(r perfRun) string {
+	// A calm machine.
+	if !r.Busy {
+		// No.
+		return "no"
+	} // end of the check
+	// A busy one, with the reason when there is one.
+	if r.BusyReason != "" {
+		// Say why.
+		return "yes: " + r.BusyReason
+	} // end of the reason check
+	// Without a reason.
+	return "yes"
+} // end of cmpBusy
+
+// cmpLoadSpeed works out how fast the model was read in: its size divided by the cold load time.
+func cmpLoadSpeed(r perfRun) string {
+	// Both figures are needed.
+	if r.ModelBytes <= 0 || r.ColdLoadSec <= 0 {
+		// Say so.
+		return "not available"
+	} // end of the check
+	// Gigabytes per second.
+	return fmt.Sprintf("%.1f GB/s", cmpGB(r.ModelBytes)/r.ColdLoadSec)
+} // end of cmpLoadSpeed
+
+// cmpName writes the model name, with a note when Ollama no longer has the model.
+func cmpName(name string, installed map[string]bool, known bool) string {
+	// Only say it when the list of installed models was read.
+	if known && !installed[name] {
+		// Mark it.
+		return name + " (no longer installed)"
+	} // end of the check
+	// The plain name.
+	return name
+} // end of cmpName
+
+// buildCompare turns the latest saved runs into the page: two tables, the sentences read out of them, and the cautions.
+func buildCompare(runs []perfRun, skipped int, installed map[string]bool, known bool) comparePage {
+	// The page.
+	var p comparePage
+	// Nothing saved yet.
+	if len(runs) == 0 {
+		// Say so.
+		p.Empty = true
+		// Mention models left out because of another prompt.
+		if skipped > 0 {
+			// The note.
+			p.Notes = append(p.Notes, fmt.Sprintf("%d model(s) were tested with an older prompt version and cannot be compared with new tests; run their test again.", skipped))
+		} // end of the skipped check
+		// Nothing more to build.
+		return p
+	} // end of the empty check
+	// Split by kind.
+	var texts, embeds []perfRun
+	// Sort each run into its list.
+	for _, r := range runs {
+		// An embedding model.
+		if r.Kind == "embedding" {
+			// Its list.
+			embeds = append(embeds, r)
+		} else {
+			// The text models.
+			texts = append(texts, r)
+		} // end of the kind check
+	} // end of the split loop
+	// Fastest writer first; a model with no figure goes last.
+	sort.SliceStable(texts, func(i, j int) bool { return texts[i].AnswerSpeed > texts[j].AnswerSpeed })
+	// Fastest embedder first (the shortest time); a model with no figure goes last.
+	sort.SliceStable(embeds, func(i, j int) bool {
+		// A missing figure is the slowest.
+		if embeds[i].WarmTotalSec <= 0 {
+			// Not before the other.
+			return false
+		} // end of the first check
+		// A missing figure of the other goes after this one.
+		if embeds[j].WarmTotalSec <= 0 {
+			// This one first.
+			return true
+		} // end of the second check
+		// Shorter is faster.
+		return embeds[i].WarmTotalSec < embeds[j].WarmTotalSec
+	}) // end of the embedding sort
+	// Any busy run.
+	busy := 0
+	// Count them.
+	for _, r := range runs {
+		// A busy one.
+		if r.Busy {
+			// Count it.
+			busy++
+		} // end of the check
+	} // end of the count loop
+	// The table of text models.
+	if len(texts) > 0 {
+		// Its column headings.
+		t := cmpTable{Title: "Models that write text", Note: "Sorted by answer speed, fastest first. The same fixed prompt was used for every model. The table scrolls sideways."}
+		// Build the headings with their bubbles.
+		for i, h := range compareTextHeadings {
+			// A heading, with an element name that is unique on the page.
+			t.Cols = append(t.Cols, makeTip(fmt.Sprintf("tip-cmp-t-%d", i), h))
+		} // end of the heading loop
+		// The fastest figure is the reference.
+		fastest := texts[0].AnswerSpeed
+		// One row for each model.
+		for _, r := range texts {
+			// How it compares with the fastest.
+			vs := "not comparable"
+			// Work it out.
+			if r.AnswerSpeed > 0 && fastest > 0 {
+				// The fastest itself.
+				if r.AnswerSpeed >= fastest*0.995 {
+					// Say so.
+					vs = "fastest"
+				} else {
+					// How many times slower.
+					vs = fmt.Sprintf("%.1f× slower", fastest/r.AnswerSpeed)
+				} // end of the fastest check
+			} // end of the figure check
+			// Words per second, roughly.
+			words := "not available"
+			// Work it out.
+			if r.AnswerSpeed > 0 {
+				// About.
+				words = fmt.Sprintf("about %.0f", r.AnswerSpeed*wordsPerToken)
+			} // end of the words check
+			// Speed for each gigabyte of memory.
+			perGB := "not available"
+			// Work it out.
+			if r.AnswerSpeed > 0 && r.ModelBytes > 0 {
+				// Tokens per second per gigabyte.
+				perGB = fmt.Sprintf("%.1f tokens/s per GB", r.AnswerSpeed/cmpGB(r.ModelBytes))
+			} // end of the per-GB check
+			// Memory used.
+			mem := "not reported"
+			// Fill it in.
+			if r.ModelBytes > 0 {
+				// The size.
+				mem = formatSize(r.ModelBytes)
+			} // end of the memory check
+			// The row.
+			t.Rows = append(t.Rows, cmpRow{Busy: r.Busy, Cells: []string{
+				cmpName(r.Model, installed, known), r.Time.UTC().Format("2006-01-02 15:04 UTC"),
+				fmtSpeed(r.AnswerSpeed), vs, words, fmtSpeed(r.PromptSpeed), fmtSecs(r.WarmFirstWordSec), fmtSecs(r.WarmTotalSec),
+				fmtSecs(r.ColdLoadSec), cmpLoadSpeed(r), mem, cmpSplit(r), perGB, cmpBusy(r),
+			}}) // end of the row
+		} // end of the model loop
+		// Keep the table.
+		p.Tables = append(p.Tables, t)
+	} // end of the text table
+	// The table of embedding models.
+	if len(embeds) > 0 {
+		// Its title and note.
+		t := cmpTable{Title: "Embedding models", Note: "Sorted by embedding time, shortest first. Embedding models write no text, so they are never ranked against the models above. The table scrolls sideways."}
+		// Build the headings with their bubbles.
+		for i, h := range compareEmbedHeadings {
+			// A heading, with an element name that is unique on the page.
+			t.Cols = append(t.Cols, makeTip(fmt.Sprintf("tip-cmp-e-%d", i), h))
+		} // end of the heading loop
+		// The shortest time is the reference.
+		fastest := embeds[0].WarmTotalSec
+		// One row for each model.
+		for _, r := range embeds {
+			// How it compares with the fastest.
+			vs := "not comparable"
+			// Work it out.
+			if r.WarmTotalSec > 0 && fastest > 0 {
+				// The fastest itself.
+				if r.WarmTotalSec <= fastest*1.005 {
+					// Say so.
+					vs = "fastest"
+				} else {
+					// How many times slower.
+					vs = fmt.Sprintf("%.1f× slower", r.WarmTotalSec/fastest)
+				} // end of the fastest check
+			} // end of the figure check
+			// Memory used.
+			mem := "not reported"
+			// Fill it in.
+			if r.ModelBytes > 0 {
+				// The size.
+				mem = formatSize(r.ModelBytes)
+			} // end of the memory check
+			// The row.
+			t.Rows = append(t.Rows, cmpRow{Busy: r.Busy, Cells: []string{
+				cmpName(r.Model, installed, known), r.Time.UTC().Format("2006-01-02 15:04 UTC"),
+				fmtSecs(r.WarmTotalSec), vs, fmtSecs(r.ColdLoadSec), cmpLoadSpeed(r), mem, cmpSplit(r),
+				fmt.Sprintf("%d numbers", r.VectorLength), cmpBusy(r),
+			}}) // end of the row
+		} // end of the model loop
+		// Keep the table.
+		p.Tables = append(p.Tables, t)
+	} // end of the embedding table
+	// Sentences read out of the text models.
+	p.Findings = append(p.Findings, textFindings(texts)...)
+	// Sentences read out of the embedding models.
+	p.Findings = append(p.Findings, embedFindings(embeds)...)
+	// The standing cautions.
+	p.Notes = append(p.Notes,
+		"Only the latest test of each model is shown. Tests made under different machine conditions are not exactly comparable; the last column marks tests made on a busy machine.",
+		"Models of different sizes are not a fair race: a bigger model is expected to be slower. \"Speed per GB of memory\" and \"Speed vs fastest\" are guides, not verdicts.",
+		"\"Words per second\" is a rough guess (tokens × 0.75). \"Load speed from disk\" is the model size divided by the cold load time; it also includes start-up work, and a model that was still in the computer's file cache loads faster than a truly cold one.",
+	) // end of the standing cautions
+	// Models left out because of another prompt.
+	if skipped > 0 {
+		// The note.
+		p.Notes = append(p.Notes, fmt.Sprintf("%d model(s) were tested with an older prompt version and are left out; run their test again to include them.", skipped))
+	} // end of the skipped check
+	// A caution when some runs were busy.
+	if busy > 0 {
+		// The note.
+		p.Notes = append(p.Notes, fmt.Sprintf("%d of the shown test(s) were made while the machine looked busy; their figures are probably too low.", busy))
+	} // end of the busy check
+	// Hand the page back.
+	return p
+} // end of buildCompare
+
+// textFindings reads plain sentences out of the text-model runs (sorted by answer speed, fastest first).
+func textFindings(texts []perfRun) []string {
+	// With fewer than two models there is nothing to compare.
+	if len(texts) < 2 {
+		// Say what is missing.
+		return []string{"Only one text model has been tested. Test another one to compare."}
+	} // end of the count check
+	// The sentences.
+	var out []string
+	// The fastest and the slowest writer, among models with a figure.
+	var fast, slow *perfRun
+	// Look for them.
+	for i := range texts {
+		// A model with no figure cannot be ranked.
+		if texts[i].AnswerSpeed <= 0 {
+			// Skip it.
+			continue
+		} // end of the check
+		// The first one found is the fastest, because the list is sorted.
+		if fast == nil {
+			// Remember it.
+			fast = &texts[i]
+		} // end of the fastest check
+		// The last one found is the slowest.
+		slow = &texts[i]
+	} // end of the loop
+	// Two different models with a figure.
+	if fast != nil && slow != nil && fast != slow {
+		// The sentence.
+		out = append(out, fmt.Sprintf("%s writes fastest: %.1f tokens/s (about %.0f words per second). %s is the slowest at %.1f tokens/s, %.1f× slower.",
+			fast.Model, fast.AnswerSpeed, fast.AnswerSpeed*wordsPerToken, slow.Model, slow.AnswerSpeed, fast.AnswerSpeed/slow.AnswerSpeed))
+	} // end of the speed sentence
+	// The quickest and the slowest to load.
+	var quick, tardy *perfRun
+	// Look for them.
+	for i := range texts {
+		// A model with no figure cannot be ranked.
+		if texts[i].ColdLoadSec <= 0 {
+			// Skip it.
+			continue
+		} // end of the check
+		// The first candidate for both.
+		if quick == nil || texts[i].ColdLoadSec < quick.ColdLoadSec {
+			// The quicker one.
+			quick = &texts[i]
+		} // end of the quick check
+		// The slower one.
+		if tardy == nil || texts[i].ColdLoadSec > tardy.ColdLoadSec {
+			// The slowest one.
+			tardy = &texts[i]
+		} // end of the tardy check
+	} // end of the loop
+	// Two different models with a figure.
+	if quick != nil && tardy != nil && quick != tardy {
+		// The sentence.
+		out = append(out, fmt.Sprintf("%s loads quickest (%s from cold); %s needs %s.", quick.Model, fmtSecs(quick.ColdLoadSec), tardy.Model, fmtSecs(tardy.ColdLoadSec)))
+	} // end of the load sentence
+	// The model that uses the least memory, and the model that gives the most speed for its memory.
+	var small, thrifty *perfRun
+	// Look for them.
+	for i := range texts {
+		// A model with no size cannot be ranked.
+		if texts[i].ModelBytes <= 0 {
+			// Skip it.
+			continue
+		} // end of the check
+		// The smallest.
+		if small == nil || texts[i].ModelBytes < small.ModelBytes {
+			// Remember it.
+			small = &texts[i]
+		} // end of the small check
+		// A model with no speed cannot be thrifty.
+		if texts[i].AnswerSpeed <= 0 {
+			// Skip it.
+			continue
+		} // end of the speed check
+		// The most speed for each gigabyte.
+		if thrifty == nil || texts[i].AnswerSpeed/cmpGB(texts[i].ModelBytes) > thrifty.AnswerSpeed/cmpGB(thrifty.ModelBytes) {
+			// Remember it.
+			thrifty = &texts[i]
+		} // end of the thrifty check
+	} // end of the loop
+	// The memory sentence.
+	if small != nil {
+		// The sentence.
+		s := fmt.Sprintf("%s uses the least memory (%s).", small.Model, formatSize(small.ModelBytes))
+		// Add the thrifty model when it is another one.
+		if thrifty != nil && thrifty != small {
+			// The addition.
+			s += fmt.Sprintf(" %s gives the most speed for its memory (%.1f tokens/s per GB).", thrifty.Model, thrifty.AnswerSpeed/cmpGB(thrifty.ModelBytes))
+		} else if thrifty != nil {
+			// The same model.
+			s += fmt.Sprintf(" It also gives the most speed for its memory (%.1f tokens/s per GB).", thrifty.AnswerSpeed/cmpGB(thrifty.ModelBytes))
+		} // end of the thrifty check
+		// Keep it.
+		out = append(out, s)
+	} // end of the memory sentence
+	// Models that do not fit fully on the graphics card.
+	var spill []string
+	// Look for them.
+	for _, r := range texts {
+		// A known size and part of it outside the graphics card.
+		if r.ModelBytes > 0 && r.GPUBytes < r.ModelBytes {
+			// Name it.
+			spill = append(spill, r.Model)
+		} // end of the check
+	} // end of the loop
+	// The sentence.
+	if len(spill) > 0 {
+		// Say which ones.
+		out = append(out, "Not fully on the graphics card (so slower than they could be): "+strings.Join(spill, ", ")+".")
+	} // end of the spill sentence
+	// Hand them back.
+	return out
+} // end of textFindings
+
+// embedFindings reads plain sentences out of the embedding-model runs (sorted by time, shortest first).
+func embedFindings(embeds []perfRun) []string {
+	// With fewer than two models there is nothing to compare, and no sentence is needed for none at all.
+	if len(embeds) < 2 {
+		// Nothing to say; the table speaks for itself.
+		return nil
+	} // end of the count check
+	// The fastest and the slowest embedder, among models with a figure.
+	var fast, slow *perfRun
+	// Look for them.
+	for i := range embeds {
+		// A model with no figure cannot be ranked.
+		if embeds[i].WarmTotalSec <= 0 {
+			// Skip it.
+			continue
+		} // end of the check
+		// The first one found is the fastest.
+		if fast == nil {
+			// Remember it.
+			fast = &embeds[i]
+		} // end of the fastest check
+		// The last one found is the slowest.
+		slow = &embeds[i]
+	} // end of the loop
+	// Two different models with a figure.
+	if fast != nil && slow != nil && fast != slow {
+		// The sentence.
+		return []string{fmt.Sprintf("%s embeds fastest (%s). %s needs %s, %.1f× longer.", fast.Model, fmtSecs(fast.WarmTotalSec), slow.Model, fmtSecs(slow.WarmTotalSec), slow.WarmTotalSec/fast.WarmTotalSec)}
+	} // end of the sentence check
+	// Nothing to say.
+	return nil
+} // end of embedFindings
+
+// compareHandler serves the comparison page; it only reads the saved figures and changes nothing.
+func compareHandler(addr ollamaAddress, token string, store *perfStore) http.HandlerFunc {
+	// Read the template once, together with the shared help-bubble templates.
+	page := template.Must(template.New("compare").Parse(compareTemplateText + tipsTemplateText))
+	// The handler.
+	return func(w http.ResponseWriter, r *http.Request) {
+		// Limit the size of the form.
+		r.Body = http.MaxBytesReader(w, r.Body, 1024)
+		// Only the monitor's own page may ask.
+		if !sameOrigin(r) {
+			// Refuse.
+			http.Error(w, "request did not come from this page", http.StatusForbidden)
+			// Stop here.
+			return
+		} // end of the origin check
+		// Read the form.
+		if err := r.ParseForm(); err != nil {
+			// Refuse.
+			http.Error(w, "bad form", http.StatusBadRequest)
+			// Stop here.
+			return
+		} // end of the form check
+		// The page token must match.
+		if !tokenValid(token, r.PostFormValue("token")) {
+			// Refuse.
+			http.Error(w, "bad token", http.StatusForbidden)
+			// Stop here.
+			return
+		} // end of the token check
+		// Which models Ollama has now (an error only means the "no longer installed" note is left out).
+		installed := map[string]bool{}
+		// Read them.
+		list, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
+		// Fill the set.
+		for _, m := range list {
+			// One name.
+			installed[m.Name] = true
+		} // end of the loop
+		// The latest runs.
+		runs, skipped := store.latestRuns(perfPromptVersion)
+		// Build the page.
+		data := buildCompare(runs, skipped, installed, err == nil)
+		// Add what every page needs.
+		data.Theme, data.Token = themeFromRequest(r), token
+		// Where the figures live.
+		path, note := store.where()
+		// A file, or the reason there is none.
+		if path != "" {
+			// Say where.
+			data.SaveNote = "The figures come from " + path + "."
+		} else {
+			// The reason.
+			data.SaveNote = note
+		} // end of the path check
+		// Build the page in memory first, so a template error gives a clean 500 and not a half page.
+		var buf bytes.Buffer
+		// Run the template.
+		if err := page.Execute(&buf, data); err != nil {
+			// Log the real reason.
+			log.Printf("compare page error: %v", err)
+			// Send a plain 500.
+			http.Error(w, "internal error", http.StatusInternalServerError)
+			// Stop here.
+			return
+		} // end of the template check
+		// Tell the browser this is an HTML page.
+		w.Header().Set("Content-Type", "text/html; charset=utf-8")
+		// Send the finished page.
+		w.Write(buf.Bytes())
+	} // end of the handler
+} // end of compareHandler
diff --git a/compare_test.go b/compare_test.go
new file mode 100644
index 0000000..fede61d
--- /dev/null
+++ b/compare_test.go
@@ -0,0 +1,311 @@
+// Package main tells Go that this folder builds into a runnable program.
+package main
+
+import ( // import lists the standard-library packages this file uses.
+	// net/http gives the status codes.
+	"net/http"
+	// net/url builds the form values.
+	"net/url"
+	// path/filepath builds the path of a history file.
+	"path/filepath"
+	// strings searches the page text.
+	"strings"
+	// testing is Go's test framework.
+	"testing"
+	// time gives the time of a saved run.
+	"time"
+) // end of imports
+
+// cmpRun builds a saved text-model run with the figures of a real test.
+func cmpRun(model string, speed, load, bytes float64, gpuAll bool, when time.Time) perfRun {
+	// The run.
+	r := perfRun{Time: when, Model: model, Kind: "generate", PromptVersion: perfPromptVersion, Runs: 3, AnswerSpeed: speed, PromptSpeed: 1000, ColdLoadSec: load, WarmFirstWordSec: 0.3, WarmTotalSec: 1.1, ModelBytes: int64(bytes)}
+	// Fully on the graphics card, or only half.
+	if gpuAll {
+		// All of it.
+		r.GPUBytes = r.ModelBytes
+	} else {
+		// Half of it.
+		r.GPUBytes = r.ModelBytes / 2
+	} // end of the memory check
+	// Hand it back.
+	return r
+} // end of cmpRun
+
+// cmpEmbed builds a saved embedding-model run.
+func cmpEmbed(model string, secs, load float64, when time.Time) perfRun {
+	// The run.
+	return perfRun{Time: when, Model: model, Kind: "embedding", PromptVersion: perfPromptVersion, Runs: 3, WarmTotalSec: secs, ColdLoadSec: load, VectorLength: 1536, ModelBytes: 3000000000, GPUBytes: 3000000000}
+} // end of cmpEmbed
+
+// TestBuildCompareFigures checks every worked-out column and sentence against figures that can be done by hand.
+func TestBuildCompareFigures(t *testing.T) {
+	// A fixed time.
+	when := time.Date(2026, 10, 25, 18, 4, 0, 0, time.UTC)
+	// A quick small model, a slow big model that is partly on the processor and was measured on a busy machine, and two embedding models.
+	slow := cmpRun("qwen3.6:27b", 36, 7.03, 18.75e9, false, when)
+	// Mark the slow one busy.
+	slow.Busy, slow.BusyReason = true, "load 12 on 20 cores"
+	// The runs, in no particular order.
+	runs := []perfRun{slow, cmpRun("medgemma:latest", 80, 3.67, 3.83e9, true, when), cmpEmbed("emb-slow", 0.2, 2, when), cmpEmbed("emb-fast", 0.04, 1.86, when)}
+	// Build the page; only medgemma is installed now.
+	p := buildCompare(runs, 0, map[string]bool{"medgemma:latest": true, "emb-fast": true, "emb-slow": true}, true)
+	// Two tables.
+	if len(p.Tables) != 2 {
+		// Stop the test.
+		t.Fatalf("%d tables, want 2", len(p.Tables))
+	} // end of the table check
+	// The text table is sorted by speed: medgemma first.
+	text := p.Tables[0]
+	// The first row.
+	if !strings.HasPrefix(text.Rows[0].Cells[0], "medgemma:latest") || !strings.HasPrefix(text.Rows[1].Cells[0], "qwen3.6:27b") {
+		// Report the order.
+		t.Errorf("order: %q then %q", text.Rows[0].Cells[0], text.Rows[1].Cells[0])
+	} // end of the order check
+	// The columns of the text table match its headings.
+	for _, r := range text.Rows {
+		// One cell for each heading.
+		if len(r.Cells) != len(compareTextHeadings) || len(text.Cols) != len(compareTextHeadings) {
+			// Report the mismatch.
+			t.Fatalf("%d cells, %d columns, %d headings", len(r.Cells), len(text.Cols), len(compareTextHeadings))
+		} // end of the length check
+	} // end of the loop
+	// The worked-out cells of the first row, by column heading.
+	want := map[string]string{
+		// 80 tokens per second.
+		"Answer speed": "80.0 tokens/s",
+		// The fastest.
+		"Speed vs fastest": "fastest",
+		// 80 times 0.75.
+		"Words per second": "about 60",
+		// 3.83 GB in 3.67 s is 1.04 GB/s.
+		"Load speed from disk": "1.0 GB/s",
+		// 80 divided by 3.83.
+		"Speed per GB of memory": "20.9 tokens/s per GB",
+		// All on the graphics card.
+		"Processor split": "100% graphics card, 0% processor",
+		// A calm machine.
+		"Machine busy": "no",
+		// The date.
+		"Tested on": "2026-10-25 18:04 UTC",
+	} // end of the expectations
+	// Check the first row.
+	for i, h := range compareTextHeadings {
+		// A heading with an expectation.
+		if w, ok := want[h]; ok && text.Rows[0].Cells[i] != w {
+			// Report it.
+			t.Errorf("medgemma %q = %q, want %q", h, text.Rows[0].Cells[i], w)
+		} // end of the check
+	} // end of the loop
+	// The worked-out cells of the second row.
+	want2 := map[string]string{
+		// 80 divided by 36 is 2.2.
+		"Speed vs fastest": "2.2× slower",
+		// 36 times 0.75.
+		"Words per second": "about 27",
+		// 18.75 GB in 7.03 s is 2.67 GB/s.
+		"Load speed from disk": "2.7 GB/s",
+		// 36 divided by 18.75.
+		"Speed per GB of memory": "1.9 tokens/s per GB",
+		// Half on the graphics card.
+		"Processor split": "50% graphics card, 50% processor",
+		// Busy, with the reason.
+		"Machine busy": "yes: load 12 on 20 cores",
+		// Not installed any more.
+	} // end of the expectations
+	// Check the second row.
+	for i, h := range compareTextHeadings {
+		// A heading with an expectation.
+		if w, ok := want2[h]; ok && text.Rows[1].Cells[i] != w {
+			// Report it.
+			t.Errorf("qwen %q = %q, want %q", h, text.Rows[1].Cells[i], w)
+		} // end of the check
+	} // end of the loop
+	// The busy row is marked, the calm one is not.
+	if !text.Rows[1].Busy || text.Rows[0].Busy {
+		// Report it.
+		t.Errorf("busy marks wrong")
+	} // end of the busy check
+	// The model that Ollama no longer has is named as such.
+	if !strings.Contains(text.Rows[1].Cells[0], "(no longer installed)") || strings.Contains(text.Rows[0].Cells[0], "no longer") {
+		// Report it.
+		t.Errorf("installed marks wrong: %q / %q", text.Rows[0].Cells[0], text.Rows[1].Cells[0])
+	} // end of the installed check
+	// The embedding table is sorted by time: the fast one first, and the slow one is 5.0 times longer.
+	emb := p.Tables[1]
+	// The order and the comparison.
+	if emb.Rows[0].Cells[0] != "emb-fast" || emb.Rows[0].Cells[3] != "fastest" || emb.Rows[1].Cells[3] != "5.0× slower" {
+		// Report it.
+		t.Errorf("embedding rows: %v / %v", emb.Rows[0].Cells, emb.Rows[1].Cells)
+	} // end of the embedding check
+	// The sentences read out of the figures.
+	all := strings.Join(p.Findings, "\n")
+	// Each must be present.
+	for _, w := range []string{
+		// The fastest writer and the slowest.
+		"medgemma:latest writes fastest: 80.0 tokens/s (about 60 words per second). qwen3.6:27b is the slowest at 36.0 tokens/s, 2.2× slower.",
+		// The load sentence.
+		"medgemma:latest loads quickest (3.67 s from cold); qwen3.6:27b needs 7.03 s.",
+		// The memory sentence: the small model is also the thrifty one.
+		"medgemma:latest uses the least memory (3.8 GB). It also gives the most speed for its memory (20.9 tokens/s per GB).",
+		// The partly-on-processor warning.
+		"Not fully on the graphics card (so slower than they could be): qwen3.6:27b.",
+		// The embedding sentence.
+		"emb-fast embeds fastest (0.040 s). emb-slow needs 0.200 s, 5.0× longer.",
+	} {
+		// Look for it.
+		if !strings.Contains(all, w) {
+			// Report the gap.
+			t.Errorf("findings lack %q\n%s", w, all)
+		} // end of the check
+	} // end of the loop
+	// The notes warn about the busy test.
+	if !strings.Contains(strings.Join(p.Notes, "\n"), "1 of the shown test(s) were made while the machine looked busy") {
+		// Report it.
+		t.Errorf("no busy note: %v", p.Notes)
+	} // end of the note check
+} // end of TestBuildCompareFigures
+
+// TestBuildCompareEdges checks the cases with no figures, one model, and an old prompt.
+func TestBuildCompareEdges(t *testing.T) {
+	// Nothing saved.
+	if p := buildCompare(nil, 0, nil, false); !p.Empty || len(p.Tables) != 0 {
+		// Report it.
+		t.Errorf("empty page wrong: %+v", p)
+	} // end of the empty check
+	// Nothing usable, but one model left out.
+	if p := buildCompare(nil, 2, nil, false); !p.Empty || !strings.Contains(strings.Join(p.Notes, " "), "2 model(s) were tested with an older prompt") {
+		// Report it.
+		t.Errorf("skipped note missing: %+v", p)
+	} // end of the skipped check
+	// One text model only.
+	p := buildCompare([]perfRun{cmpRun("only:1b", 50, 2, 2e9, true, time.Now())}, 0, nil, false)
+	// A sentence asks for another test, and no "no longer installed" mark appears when the list was not read.
+	if !strings.Contains(strings.Join(p.Findings, " "), "Only one text model has been tested") || strings.Contains(p.Tables[0].Rows[0].Cells[0], "no longer") {
+		// Report it.
+		t.Errorf("single-model page wrong: %v / %q", p.Findings, p.Tables[0].Rows[0].Cells[0])
+	} // end of the single check
+	// A model with no speed figure shows plain words and never divides by zero.
+	z := cmpRun("zero:1b", 0, 0, 0, true, time.Now())
+	// Build with a normal model next to it.
+	p = buildCompare([]perfRun{cmpRun("ok:1b", 50, 2, 2e9, true, time.Now()), z}, 0, nil, false)
+	// The zero model is last and its worked-out cells are words.
+	row := p.Tables[0].Rows[1]
+	// Check the cells.
+	for i, h := range compareTextHeadings {
+		// The columns that need a speed or a size.
+		switch h {
+		// These cannot be worked out.
+		case "Words per second", "Load speed from disk", "Speed per GB of memory":
+			// They say so.
+			if row.Cells[i] != "not available" {
+				// Report it.
+				t.Errorf("zero model %q = %q", h, row.Cells[i])
+			} // end of the check
+		// The comparison.
+		case "Speed vs fastest":
+			// It says so.
+			if row.Cells[i] != "not comparable" {
+				// Report it.
+				t.Errorf("zero model %q = %q", h, row.Cells[i])
+			} // end of the check
+		} // end of the switch
+	} // end of the loop
+} // end of TestBuildCompareEdges
+
+// TestLatestRuns checks that only the newest run of each model counts, and that an old prompt version is left out.
+func TestLatestRuns(t *testing.T) {
+	// A store in a temporary folder.
+	s := openPerfStore(filepath.Join(t.TempDir(), "performance.json"), "")
+	// An old run and a newer run of one model.
+	old := cmpRun("a:1b", 10, 1, 1e9, true, time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC))
+	// The newer one.
+	newer := cmpRun("a:1b", 20, 1, 1e9, true, time.Date(2026, 10, 2, 0, 0, 0, 0, time.UTC))
+	// A model whose newest run used another prompt.
+	other := cmpRun("b:1b", 30, 1, 1e9, true, time.Date(2026, 10, 3, 0, 0, 0, 0, time.UTC))
+	// Another prompt version.
+	other.PromptVersion = "v0"
+	// Save them.
+	for _, r := range []perfRun{old, newer, other} {
+		// One run.
+		if err := s.add(r); err != nil {
+			// Stop the test.
+			t.Fatal(err)
+		} // end of the error check
+	} // end of the loop
+	// Ask.
+	got, skipped := s.latestRuns(perfPromptVersion)
+	// One model counts, one was skipped.
+	if len(got) != 1 || got[0].AnswerSpeed != 20 || skipped != 1 {
+		// Report it.
+		t.Errorf("latestRuns = %+v, skipped %d", got, skipped)
+	} // end of the check
+} // end of TestLatestRuns
+
+// TestCompareRoute checks the page through the real handler: saved test runs show up, the form rules hold, and the main page has the icon.
+func TestCompareRoute(t *testing.T) {
+	// A fake Ollama and a rig.
+	f := newPerfFake()
+	// Build the rig.
+	rig, _ := perfRig(t, f)
+	// Before any test the page says so.
+	res := post(t, rig.h, "/compare", url.Values{"token": {rig.token}}, fromThisPage)
+	// The reply.
+	empty := bodyOf(res)
+	// It is a page.
+	if res.StatusCode != http.StatusOK || !strings.Contains(empty, "No model has been through a performance test yet") {
+		// Report it.
+		t.Errorf("empty page: %d", res.StatusCode)
+	} // end of the empty check
+	// Two real tests: a text model and an embedding model.
+	perfPost(t, rig, "/performance/run", "chat:1b")
+	// The embedding model.
+	perfPost(t, rig, "/performance/run", "embed:1b")
+	// Ask again.
+	res = post(t, rig.h, "/compare", url.Values{"token": {rig.token}}, fromThisPage)
+	// The reply.
+	body := bodyOf(res)
+	// Both tables, the model names, headings with bubbles, and the findings section.
+	for _, w := range []string{"Models that write text", "Embedding models", "chat:1b", "embed:1b", ">Speed vs fastest<", ">Load speed from disk<", `id="tip-cmp-t-0"`, `id="tip-cmp-e-0"`, "Only one text model has been tested", "How to read this", "Back to the monitor"} {
+		// Look for it.
+		if !strings.Contains(body, w) {
+			// Report the gap.
+			t.Errorf("compare page lacks %q", w)
+		} // end of the check
+	} // end of the loop
+	// No element name appears twice.
+	for _, id := range []string{`id="tip-cmp-t-0"`, `id="tip-cmp-e-0"`} {
+		// Count it.
+		if strings.Count(body, id) != 1 {
+			// Report it.
+			t.Errorf("%s appears %d times", id, strings.Count(body, id))
+		} // end of the count check
+	} // end of the loop
+	// The page runs no script.
+	if strings.Contains(body, "<script") {
+		// Report it.
+		t.Errorf("the compare page has a script")
+	} // end of the script check
+	// A wrong token is refused.
+	if res := post(t, rig.h, "/compare", url.Values{"token": {"0123456789abcdef0123456789abcdef"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
+		// Report it.
+		t.Errorf("wrong token = %d", res.StatusCode)
+	} // end of the token check
+	// A request that did not come from this page is refused.
+	if res := post(t, rig.h, "/compare", url.Values{"token": {rig.token}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
+		// Report it.
+		t.Errorf("cross-site = %d", res.StatusCode)
+	} // end of the origin check
+	// A plain GET is not a route.
+	if status, _, _ := get(t, rig.h, http.MethodGet, "/compare"); status != http.StatusMethodNotAllowed && status != http.StatusNotFound {
+		// Report it.
+		t.Errorf("GET /compare = %d", status)
+	} // end of the GET check
+	// The main page has exactly one compare icon, in the header, with the tip the person asked for.
+	_, _, main := get(t, rig.h, http.MethodGet, "/")
+	// Count and look.
+	if strings.Count(main, `action="/compare"`) != 1 || !strings.Contains(main, "Compare models that have already been through a performance test") || strings.Index(main, `action="/compare"`) > strings.Index(main, "<tbody>") {
+		// Report it.
+		t.Errorf("main page icon wrong (count %d)", strings.Count(main, `action="/compare"`))
+	} // end of the icon check
+} // end of TestCompareRoute
diff --git a/tooltips.go b/tooltips.go
index 16406bb..0ac7e87 100644
--- a/tooltips.go
+++ b/tooltips.go
@@ -412,6 +412,60 @@ var helpTexts = map[string]tooltip{
 		// What it helps with.
 		Decide: "Whether another model still fits next to it.",
 	}, // end of Memory used
+	// The comparison page: when the test was made.
+	"Tested on": {
+		// What it tells you.
+		Plain: "The date and time of the saved test whose figures are shown.",
+		// A real case.
+		Example: "Only the latest test of each model is shown, so two rows can come from different days.",
+		// What it helps with.
+		Decide: "Whether the figures are recent enough to trust.",
+	}, // end of Tested on
+	// The comparison page: speed against the fastest model.
+	"Speed vs fastest": {
+		// What it tells you.
+		Plain: "How this model compares with the fastest model in the same table.",
+		// A real case from the test machine.
+		Example: "medgemma:latest writes 80 tokens/s and qwen3.6:27b 36, so the second is 2.2× slower.",
+		// What it helps with.
+		Decide: "Which model to pick when speed matters more than size.",
+	}, // end of Speed vs fastest
+	// The comparison page: rough words per second.
+	"Words per second": {
+		// What it tells you.
+		Plain: "A rough reading speed: the answer speed times 0.75, since a word is about three quarters of a token.",
+		// A real case from the test machine.
+		Example: "36 tokens/s is about 27 words per second, faster than a person reads.",
+		// What it helps with.
+		Decide: "Whether answers will feel instant or slow.",
+	}, // end of Words per second
+	// The comparison page: load speed.
+	"Load speed from disk": {
+		// What it tells you.
+		Plain: "The model's size divided by its cold load time: how fast it was brought into memory.",
+		// A real case from the test machine.
+		Example: "qwen3.6:27b: 18.8 GB (gigabytes) in 7.0 s is about 2.7 GB (gigabytes) a second.",
+		// What it helps with.
+		Decide: "How long a model keeps you waiting after it was unloaded.",
+	}, // end of Load speed from disk
+	// The comparison page: speed for each gigabyte of memory.
+	"Speed per GB of memory": {
+		// What it tells you.
+		Plain: "Answer speed divided by the memory the model uses: how much speed each gigabyte buys.",
+		// A real case from the test machine.
+		Example: "medgemma:latest: 80 tokens/s on 3.8 GB (gigabytes) is about 21 tokens/s for each GB (gigabytes).",
+		// What it helps with.
+		Decide: "Which model gives the most speed for the memory it takes.",
+	}, // end of Speed per GB of memory
+	// The comparison page: busy machine.
+	"Machine busy": {
+		// What it tells you.
+		Plain: "Whether the machine looked busy when the test ran. A busy machine makes the figures too low.",
+		// A real case.
+		Example: "A test made while another model was answering shows lower speeds than an idle machine.",
+		// What it helps with.
+		Decide: "Whether to repeat the test when the machine is idle.",
+	}, // end of Machine busy
 	// The performance page: change since the previous run.
 	"Change since the previous run": {
 		// What it tells you.
diff --git a/tooltips_test.go b/tooltips_test.go
index 395bf08..96ed4f1 100644
--- a/tooltips_test.go
+++ b/tooltips_test.go
@@ -32,6 +32,8 @@ func allHeadings() []string {
 	out = append(out, gearHeadings...)
 	// The performance page headings.
 	out = append(out, perfHeadings...)
+	// The comparison page headings that are not shared with other pages.
+	out = append(out, compareExtraHeadings...)
 	// Then the four categories, by their display names.
 	for c := categoryEmbedding; c <= categoryUnclassified; c++ {
 		// Add the category's heading text.
diff --git a/web.go b/web.go
index 74322cd..04782d0 100644
--- a/web.go
+++ b/web.go
@@ -109,7 +109,10 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	// Make the four performance handlers: the start page, the test run, and the two steps of clearing the saved results (the checks are in perfpage.go); the history lives in the person's configuration folder.
 	histPath, histNote := defaultHistoryPath()
 	// Open the saved results.
-	perfStart, perfRun, perfClearAsk, perfClearDo := perfHandlers(addr, token, openPerfStore(histPath, histNote))
+	// One history store, shared by the performance pages and the comparison page.
+	perfHistory := openPerfStore(histPath, histNote)
+	// The four handlers of the performance pages.
+	perfStart, perfRun, perfClearAsk, perfClearDo := perfHandlers(addr, token, perfHistory)
 	// Route: a POST request for "/performance" shows the performance page and changes nothing.
 	mux.HandleFunc("POST /performance", perfStart)
 	// Route: a POST request for "/performance/run" runs the test.
@@ -118,6 +121,8 @@ func newWebHandler(addr ollamaAddress, timeout time.Duration) http.Handler {
 	mux.HandleFunc("POST /performance/clear", perfClearAsk)
 	// Route: a POST request for "/performance/clear/confirm" removes them.
 	mux.HandleFunc("POST /performance/clear/confirm", perfClearDo)
+	// Route: a POST request for "/compare" shows the comparison of the tested models and changes nothing.
+	mux.HandleFunc("POST /compare", compareHandler(addr, token, perfHistory))
 	// Route: a GET request for "/countdown.js" sends the small script that makes the timers tick (only the message pages use it).
 	mux.HandleFunc("GET /countdown.js", countdownHandler)
 	// Route: a GET request for "/loading.js" sends the small script that shows the waiting message while a model loads (only the load warning page uses it).
diff --git a/web/app.css b/web/app.css
index 8eb9c32..d21d295 100644
--- a/web/app.css
+++ b/web/app.css
@@ -1147,3 +1147,25 @@ button.btn-plain {
   /* Page colour behind the rows. */
   background: var(--bg);
 } /* end of rule */
+
+/* The compare icon sits right after the word Model in the first heading. */
+.comparehead {
+  /* A little room after the heading text. */
+  margin-left: 0.4rem;
+  /* On the same line as the heading text. */
+  vertical-align: middle;
+} /* end of rule */
+
+/* The comparison table: long values such as the busy reason wrap instead of making the table very wide. */
+.comparetable td, .comparetable th {
+  /* Let long values wrap. */
+  white-space: normal;
+  /* A sensible width before wrapping. */
+  min-width: 6rem;
+} /* end of rule */
+
+/* Room between a comparison table and the heading that follows it. */
+.scrollbox + h2 {
+  /* A comfortable gap above the next heading. */
+  margin-top: 1.4rem;
+} /* end of rule */
diff --git a/web/compare.html b/web/compare.html
new file mode 100644
index 0000000..80b51ec
--- /dev/null
+++ b/web/compare.html
@@ -0,0 +1,67 @@
+{{/* Comparison page: the latest saved performance test of each model side by side. The comments are template comments, so they never reach the browser. */}}
+<!DOCTYPE html>
+{{/* lang tells screen readers which language the page is written in. */}}
+<html lang="en"{{if .Theme}} data-theme="{{.Theme}}"{{end}}>
+<head>{{/* start of the head. */}}
+{{/* Text encoding. */}}
+<meta charset="utf-8">
+{{/* Fit the page to the width of the screen on phones. */}}
+<meta name="viewport" content="width=device-width, initial-scale=1">
+{{/* The title shown on the browser tab. */}}
+<title>Compare models - OllamaControlCenter</title>
+{{/* Our one stylesheet. */}}
+<link rel="stylesheet" href="/app.css">
+</head>{{/* end of the head. */}}
+<body>{{/* start of the visible page. */}}
+{{/* The page content. */}}
+<main>
+{{/* A panel that holds the comparison. */}}
+<section class="panel">
+{{/* The page heading. */}}
+<h1>Compare models</h1>
+{{/* Nothing saved yet. */}}
+{{if .Empty}}
+<p>No model has been through a performance test yet. Use the chart icon 📈 before a model name on the monitor page to test one, then come back here.</p>
+{{range .Notes}}<p class="muted">{{.}}</p>{{end}}
+{{else}}
+{{/* What the figures say, in plain words. */}}
+{{if .Findings}}
+<h2>What the figures say</h2>
+<ul>
+{{range .Findings}}<li>{{.}}</li>{{end}}
+</ul>
+{{end}}
+{{/* One table for each kind of model. */}}
+{{range $t := .Tables}}
+<h2>{{$t.Title}}</h2>
+<p class="muted">{{$t.Note}}</p>
+{{/* The scroll box, reachable with Tab so keyboard users can scroll the table sideways. */}}
+<div class="scrollbox" tabindex="0" role="region" aria-label="{{$t.Title}}, scrolls sideways">
+<table class="models comparetable">
+{{/* The column headings, each with its help bubble; the first stays in view. */}}
+<thead><tr>{{range $i, $c := $t.Cols}}<th scope="col"{{if eq $i 0}} class="stickycol"{{end}}>{{template "tipbox" $c}}</th>{{end}}</tr></thead>
+<tbody>
+{{/* One row for each model; a busy test is marked with a symbol and words, never colour alone. */}}
+{{range $r := $t.Rows}}
+<tr>{{range $i, $c := $r.Cells}}{{if eq $i 0}}<th scope="row" class="stickycol">{{$c}}{{if $r.Busy}} <span aria-label="measured on a busy machine" title="measured on a busy machine">⚠</span>{{end}}</th>{{else}}<td>{{$c}}</td>{{end}}{{end}}</tr>
+{{end}}
+</tbody>
+</table>
+</div>
+{{end}}
+{{/* How to read the figures. */}}
+<h2>How to read this</h2>
+<ul>
+{{range .Notes}}<li>{{.}}</li>{{end}}
+</ul>
+{{end}}
+{{/* Where the figures come from. */}}
+{{if .SaveNote}}<p class="muted">{{.SaveNote}}</p>{{end}}
+{{/* The way back. */}}
+<p><a class="btn-plain" href="/">Back to the monitor</a></p>
+{{/* End of the panel. */}}
+</section>
+{{/* End of the content. */}}
+</main>
+</body>{{/* end of the visible page. */}}
+</html>{{/* end of the page. */}}
diff --git a/web/index.html b/web/index.html
index 44c0823..5f6e2e5 100644
--- a/web/index.html
+++ b/web/index.html
@@ -79,7 +79,7 @@
 {{/* Case 4: the table itself. */}}
 {{else}}
 {{/* A hint above the table so people know the dotted headings have help. */}}
-<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The page icon 📄 shows a model's Modelfile, read-only. The gear ⚙ below it opens the model's inference parameters; it appears only for models that are not loaded. The chart icon 📈 before a model name opens its performance page (a model that is loaded may be in use, so it has none). The table scrolls sideways.</p>
+<p class="muted">Point at a dotted heading, or press Tab to reach it, to see what it means. The page icon 📄 shows a model's Modelfile, read-only. The gear ⚙ below it opens the model's inference parameters; it appears only for models that are not loaded. The chart icon 📈 before a model name opens its performance page (a model that is loaded may be in use, so it has none). The scales icon ⚖ beside the heading Model compares the models that have been tested. The table scrolls sideways.</p>
 {{/* The scroll box: it can be reached with Tab, so keyboard users can scroll the table sideways. */}}
 <div class="scrollbox" tabindex="0" role="region" aria-label="Installed models table, scrolls sideways">
 {{/* The table. */}}
@@ -99,6 +99,23 @@
 <span class="tip" role="tooltip" id="{{$c.Tip.ID}}">{{template "tip" $c.Tip}}</span>
 {{/* End of the bubble area. */}}
 </div>
+{{/* In the first heading only: the compare icon, a small form that opens the comparison page and changes nothing. */}}
+{{if eq $i 0}}
+<form class="gearform comparehead" method="post" action="/compare">
+{{/* The page token proves the form comes from this monitor. */}}
+<input type="hidden" name="token" value="{{$.Token}}">
+{{/* The area that opens the tip. */}}
+<span class="tipbox">
+{{/* The button: the symbol is hidden from screen readers, which read the label and the tip instead. */}}
+<button type="submit" class="gear" aria-label="Compare models that have been tested" aria-describedby="tipcompare"><span aria-hidden="true">⚖</span></button>
+{{/* The tip. */}}
+<span class="tip tip-icon" role="tooltip" id="tipcompare">Compare models that have already been through a performance test</span>
+{{/* End of the tip area. */}}
+</span>
+{{/* End of the compare form. */}}
+</form>
+{{/* End of the first-column check. */}}
+{{end}}
 {{/* End of the heading cell. */}}
 </th>
 {{/* End of the column loop. */}}
PATCH_END
# Check that the patch fits the current files, without changing anything yet.
git apply --check "$PATCH_FILE" || { echo "FAIL  the patch does not fit these files"; exit 1; }
# Report the check.
echo "PASS  the patch fits"
# Apply the patch.
git apply "$PATCH_FILE"
# The fingerprints (sha256) the files must have after the change.
cat > "$PATCH_FILE.sums" <<'SUMS_END'
cef29512324a9f9e292b0327050f185768c92bad0fb1ab48b016385baa20ef89  compare.go
7253d89283eced6c8b10d4325247ce0d428e0da2de52b2be075ee0d662180f3c  compare_test.go
653989c570615de3167ece7e3480b8cc3cc5e331a9c682b16099f00326c764e9  tooltips.go
7d18438391e37e077b39039d71b854ee05229bb9fb1db16e28bd6d2c827add87  tooltips_test.go
05f9c70a4671750c27525d179edab15bf09984b1d27ff070d14a4b3749054044  web.go
db3d4bdbb099f853038423d3840370197618d4a65057246faedcf4521df08fc6  web/app.css
2cc52d8bb4f8fbe33710810712360299cb97ab7d3cdd770dc33d177c495fa6c7  web/compare.html
de1831fd5e89c375ecba16c4d7ea28163c964be1f85690f3b248c356aceeac5a  web/index.html
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
