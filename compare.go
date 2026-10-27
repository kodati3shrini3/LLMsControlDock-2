// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes builds the page in memory before it is sent.
	"bytes"
	// embed lets the page template be stored inside the executable.
	_ "embed"
	// fmt formats the figures.
	"fmt"
	// html/template builds the page and escapes every value.
	"html/template"
	// log records a real failure for the person running the program.
	"log"
	// net/http serves the page.
	"net/http"
	// sort puts the rows in order.
	"sort"
	// strings joins text.
	"strings"
) // end of imports

// compareTemplateText is the page template, stored inside the executable at build time.
//
//go:embed web/compare.html
var compareTemplateText string

// wordsPerToken is the rough number of English words in one token (a common rule of thumb, not a measurement).
const wordsPerToken = 0.75

// compareTextHeadings are the column headings of the table of text models, in order.
var compareTextHeadings = []string{"Model", "Tested on", "Answer speed", "Speed vs fastest", "Words per second", "Prompt reading speed", "Time to first word", "Total time", "Load time", "Load speed from disk", "Memory used", "Processor split", "Speed per GB of memory", "Machine busy"}

// compareEmbedHeadings are the column headings of the table of embedding models, in order.
var compareEmbedHeadings = []string{"Model", "Tested on", "Embedding time", "Speed vs fastest", "Load time", "Load speed from disk", "Memory used", "Processor split", "Vector length", "Machine busy"}

// compareExtraHeadings are the headings that exist only on the comparison page and need their own tooltip (the others are shared with the performance page).
var compareExtraHeadings = []string{"Tested on", "Speed vs fastest", "Words per second", "Load speed from disk", "Speed per GB of memory", "Machine busy"}

// cmpRow is one model in a comparison table.
type cmpRow struct {
	// Cells are the values, one for each column.
	Cells []string
	// Busy is true when the run was made on a busy machine, so the row can be marked.
	Busy bool
} // end of cmpRow

// cmpTable is one comparison table.
type cmpTable struct {
	// Title is the heading above the table.
	Title string
	// Note is one sentence under the heading.
	Note string
	// Cols are the column headings with their help bubbles.
	Cols []tipView
	// Rows are the models.
	Rows []cmpRow
} // end of cmpTable

// comparePage is everything the comparison template needs.
type comparePage struct {
	// Theme is the colour scheme asked for in the address, or empty.
	Theme string
	// Size is the saved text size, medium, or empty for the browser's own size.
	Size string
	// Token is the page token for the "Back" form.
	Token string
	// Tables are the comparison tables (text models, embedding models).
	Tables []cmpTable
	// Findings are plain sentences read out of the figures.
	Findings []string
	// Notes are cautions about how to read the table.
	Notes []string
	// Empty is true when no test is saved yet.
	Empty bool
	// SaveNote says where the figures come from, or why there is no file.
	SaveNote string
} // end of comparePage

// latestRuns returns the newest run of each model and kind that used the given prompt version, and how many models were skipped because their newest run used another prompt.
func (s *perfStore) latestRuns(promptVersion string) ([]perfRun, int) {
	// One reader at a time.
	s.mu.Lock()
	// Release at the end.
	defer s.mu.Unlock()
	// Which model and kind pairs were seen already.
	seen := map[string]bool{}
	// The result.
	var out []perfRun
	// How many were skipped.
	skipped := 0
	// Walk from the newest to the oldest.
	for i := len(s.runs) - 1; i >= 0; i-- {
		// The run.
		r := s.runs[i]
		// A key for the model and kind.
		key := r.Kind + "|" + r.Model
		// The newest run of this model is the only one that counts.
		if seen[key] {
			// Skip the older ones.
			continue
		} // end of the repeat check
		// Remember it.
		seen[key] = true
		// A run with another prompt cannot be compared with the rest.
		if r.PromptVersion != promptVersion {
			// Count it.
			skipped++
			// Leave it out.
			continue
		} // end of the prompt check
		// Keep it.
		out = append(out, r)
	} // end of the loop
	// Hand them back.
	return out, skipped
} // end of latestRuns

// testedModels says how many models have a saved test with the current prompt, which is the number of rows the comparison page would show.
func (s *perfStore) testedModels() int {
	// The latest runs of the current prompt.
	runs, _ := s.latestRuns(perfPromptVersion)
	// One for each model.
	return len(runs)
} // end of testedModels

// cmpGB turns bytes into decimal gigabytes (the unit Ollama and the rest of this program use).
func cmpGB(b int64) float64 {
	// Decimal gigabytes.
	return float64(b) / 1e9
} // end of cmpGB

// cmpSplit writes the processor split of a run in a short form.
func cmpSplit(r perfRun) string {
	// Without a size there is nothing to split.
	if r.ModelBytes <= 0 {
		// Say so.
		return "not reported"
	} // end of the size check
	// The share on the graphics card.
	gpu := float64(r.GPUBytes) / float64(r.ModelBytes) * 100
	// The text.
	return fmt.Sprintf("%.0f%% graphics card, %.0f%% processor", gpu, 100-gpu)
} // end of cmpSplit

// cmpBusy writes the busy column of a run.
func cmpBusy(r perfRun) string {
	// A calm machine.
	if !r.Busy {
		// No.
		return "no"
	} // end of the check
	// A busy one, with the reason when there is one.
	if r.BusyReason != "" {
		// Say why.
		return "yes: " + r.BusyReason
	} // end of the reason check
	// Without a reason.
	return "yes"
} // end of cmpBusy

// cmpLoadSpeed works out how fast the model was read in: its size divided by the cold load time.
func cmpLoadSpeed(r perfRun) string {
	// Both figures are needed.
	if r.ModelBytes <= 0 || r.ColdLoadSec <= 0 {
		// Say so.
		return "not available"
	} // end of the check
	// Gigabytes per second.
	return fmt.Sprintf("%.1f GB/s", cmpGB(r.ModelBytes)/r.ColdLoadSec)
} // end of cmpLoadSpeed

// cmpName writes the model name, with a note when Ollama no longer has the model.
func cmpName(name string, installed map[string]bool, known bool) string {
	// Only say it when the list of installed models was read.
	if known && !installed[name] {
		// Mark it.
		return name + " (no longer installed)"
	} // end of the check
	// The plain name.
	return name
} // end of cmpName

// buildCompare turns the latest saved runs into the page: two tables, the sentences read out of them, and the cautions.
func buildCompare(runs []perfRun, skipped int, installed map[string]bool, known bool) comparePage {
	// The page.
	var p comparePage
	// Nothing saved yet.
	if len(runs) == 0 {
		// Say so.
		p.Empty = true
		// Mention models left out because of another prompt.
		if skipped > 0 {
			// The note.
			p.Notes = append(p.Notes, fmt.Sprintf("%d model(s) were tested with an older prompt version and cannot be compared with new tests; run their test again.", skipped))
		} // end of the skipped check
		// Nothing more to build.
		return p
	} // end of the empty check
	// Split by kind.
	var texts, embeds []perfRun
	// Sort each run into its list.
	for _, r := range runs {
		// An embedding model.
		if r.Kind == "embedding" {
			// Its list.
			embeds = append(embeds, r)
		} else {
			// The text models.
			texts = append(texts, r)
		} // end of the kind check
	} // end of the split loop
	// Fastest writer first; a model with no figure goes last.
	sort.SliceStable(texts, func(i, j int) bool { return texts[i].AnswerSpeed > texts[j].AnswerSpeed })
	// Fastest embedder first (the shortest time); a model with no figure goes last.
	sort.SliceStable(embeds, func(i, j int) bool {
		// A missing figure is the slowest.
		if embeds[i].WarmTotalSec <= 0 {
			// Not before the other.
			return false
		} // end of the first check
		// A missing figure of the other goes after this one.
		if embeds[j].WarmTotalSec <= 0 {
			// This one first.
			return true
		} // end of the second check
		// Shorter is faster.
		return embeds[i].WarmTotalSec < embeds[j].WarmTotalSec
	}) // end of the embedding sort
	// Any busy run.
	busy := 0
	// Count them.
	for _, r := range runs {
		// A busy one.
		if r.Busy {
			// Count it.
			busy++
		} // end of the check
	} // end of the count loop
	// The table of text models.
	if len(texts) > 0 {
		// Its column headings.
		t := cmpTable{Title: "Models that write text", Note: "Sorted by answer speed, fastest first. The same fixed prompt was used for every model. The table scrolls sideways."}
		// Build the headings with their bubbles.
		for i, h := range compareTextHeadings {
			// A heading, with an element name that is unique on the page.
			t.Cols = append(t.Cols, makeTip(fmt.Sprintf("tip-cmp-t-%d", i), h))
		} // end of the heading loop
		// The fastest figure is the reference.
		fastest := texts[0].AnswerSpeed
		// One row for each model.
		for _, r := range texts {
			// How it compares with the fastest.
			vs := "not comparable"
			// Work it out.
			if r.AnswerSpeed > 0 && fastest > 0 {
				// The fastest itself.
				if r.AnswerSpeed >= fastest*0.995 {
					// Say so.
					vs = "fastest"
				} else {
					// How many times slower.
					vs = fmt.Sprintf("%.1f× slower", fastest/r.AnswerSpeed)
				} // end of the fastest check
			} // end of the figure check
			// Words per second, roughly.
			words := "not available"
			// Work it out.
			if r.AnswerSpeed > 0 {
				// About.
				words = fmt.Sprintf("about %.0f", r.AnswerSpeed*wordsPerToken)
			} // end of the words check
			// Speed for each gigabyte of memory.
			perGB := "not available"
			// Work it out.
			if r.AnswerSpeed > 0 && r.ModelBytes > 0 {
				// Tokens per second per gigabyte.
				perGB = fmt.Sprintf("%.1f tokens/s per GB", r.AnswerSpeed/cmpGB(r.ModelBytes))
			} // end of the per-GB check
			// Memory used.
			mem := "not reported"
			// Fill it in.
			if r.ModelBytes > 0 {
				// The size.
				mem = formatSize(r.ModelBytes)
			} // end of the memory check
			// The row.
			t.Rows = append(t.Rows, cmpRow{Busy: r.Busy, Cells: []string{
				cmpName(r.Model, installed, known), r.Time.UTC().Format("2006-01-02 15:04 UTC"),
				fmtSpeed(r.AnswerSpeed), vs, words, fmtSpeed(r.PromptSpeed), fmtSecs(r.WarmFirstWordSec), fmtSecs(r.WarmTotalSec),
				fmtSecs(r.ColdLoadSec), cmpLoadSpeed(r), mem, cmpSplit(r), perGB, cmpBusy(r),
			}}) // end of the row
		} // end of the model loop
		// Keep the table.
		p.Tables = append(p.Tables, t)
	} // end of the text table
	// The table of embedding models.
	if len(embeds) > 0 {
		// Its title and note.
		t := cmpTable{Title: "Embedding models", Note: "Sorted by embedding time, shortest first. Embedding models write no text, so they are never ranked against the models above. The table scrolls sideways."}
		// Build the headings with their bubbles.
		for i, h := range compareEmbedHeadings {
			// A heading, with an element name that is unique on the page.
			t.Cols = append(t.Cols, makeTip(fmt.Sprintf("tip-cmp-e-%d", i), h))
		} // end of the heading loop
		// The shortest time is the reference.
		fastest := embeds[0].WarmTotalSec
		// One row for each model.
		for _, r := range embeds {
			// How it compares with the fastest.
			vs := "not comparable"
			// Work it out.
			if r.WarmTotalSec > 0 && fastest > 0 {
				// The fastest itself.
				if r.WarmTotalSec <= fastest*1.005 {
					// Say so.
					vs = "fastest"
				} else {
					// How many times slower.
					vs = fmt.Sprintf("%.1f× slower", r.WarmTotalSec/fastest)
				} // end of the fastest check
			} // end of the figure check
			// Memory used.
			mem := "not reported"
			// Fill it in.
			if r.ModelBytes > 0 {
				// The size.
				mem = formatSize(r.ModelBytes)
			} // end of the memory check
			// The row.
			t.Rows = append(t.Rows, cmpRow{Busy: r.Busy, Cells: []string{
				cmpName(r.Model, installed, known), r.Time.UTC().Format("2006-01-02 15:04 UTC"),
				fmtSecs(r.WarmTotalSec), vs, fmtSecs(r.ColdLoadSec), cmpLoadSpeed(r), mem, cmpSplit(r),
				fmt.Sprintf("%d numbers", r.VectorLength), cmpBusy(r),
			}}) // end of the row
		} // end of the model loop
		// Keep the table.
		p.Tables = append(p.Tables, t)
	} // end of the embedding table
	// Sentences read out of the text models.
	p.Findings = append(p.Findings, textFindings(texts)...)
	// Sentences read out of the embedding models.
	p.Findings = append(p.Findings, embedFindings(embeds)...)
	// The standing cautions.
	p.Notes = append(p.Notes,
		"Only the latest test of each model is shown. Tests made under different machine conditions are not exactly comparable; the last column marks tests made on a busy machine.",
		"Models of different sizes are not a fair race: a bigger model is expected to be slower. \"Speed per GB of memory\" and \"Speed vs fastest\" are guides, not verdicts.",
		"\"Words per second\" is a rough guess (tokens × 0.75). \"Load speed from disk\" is the model size divided by the cold load time; it also includes start-up work, and a model that was still in the computer's file cache loads faster than a truly cold one.",
	) // end of the standing cautions
	// Models left out because of another prompt.
	if skipped > 0 {
		// The note.
		p.Notes = append(p.Notes, fmt.Sprintf("%d model(s) were tested with an older prompt version and are left out; run their test again to include them.", skipped))
	} // end of the skipped check
	// A caution when some runs were busy.
	if busy > 0 {
		// The note.
		p.Notes = append(p.Notes, fmt.Sprintf("%d of the shown test(s) were made while the machine looked busy; their figures are probably too low.", busy))
	} // end of the busy check
	// Hand the page back.
	return p
} // end of buildCompare

// textFindings reads plain sentences out of the text-model runs (sorted by answer speed, fastest first).
func textFindings(texts []perfRun) []string {
	// With fewer than two models there is nothing to compare.
	if len(texts) < 2 {
		// Say what is missing.
		return []string{"Only one text model has been tested. Test another one to compare."}
	} // end of the count check
	// The sentences.
	var out []string
	// The fastest and the slowest writer, among models with a figure.
	var fast, slow *perfRun
	// Look for them.
	for i := range texts {
		// A model with no figure cannot be ranked.
		if texts[i].AnswerSpeed <= 0 {
			// Skip it.
			continue
		} // end of the check
		// The first one found is the fastest, because the list is sorted.
		if fast == nil {
			// Remember it.
			fast = &texts[i]
		} // end of the fastest check
		// The last one found is the slowest.
		slow = &texts[i]
	} // end of the loop
	// Two different models with a figure.
	if fast != nil && slow != nil && fast != slow {
		// The sentence.
		out = append(out, fmt.Sprintf("%s writes fastest: %.1f tokens/s (about %.0f words per second). %s is the slowest at %.1f tokens/s, %.1f× slower.",
			fast.Model, fast.AnswerSpeed, fast.AnswerSpeed*wordsPerToken, slow.Model, slow.AnswerSpeed, fast.AnswerSpeed/slow.AnswerSpeed))
	} // end of the speed sentence
	// The quickest and the slowest to load.
	var quick, tardy *perfRun
	// Look for them.
	for i := range texts {
		// A model with no figure cannot be ranked.
		if texts[i].ColdLoadSec <= 0 {
			// Skip it.
			continue
		} // end of the check
		// The first candidate for both.
		if quick == nil || texts[i].ColdLoadSec < quick.ColdLoadSec {
			// The quicker one.
			quick = &texts[i]
		} // end of the quick check
		// The slower one.
		if tardy == nil || texts[i].ColdLoadSec > tardy.ColdLoadSec {
			// The slowest one.
			tardy = &texts[i]
		} // end of the tardy check
	} // end of the loop
	// Two different models with a figure.
	if quick != nil && tardy != nil && quick != tardy {
		// The sentence.
		out = append(out, fmt.Sprintf("%s loads quickest (%s from cold); %s needs %s.", quick.Model, fmtSecs(quick.ColdLoadSec), tardy.Model, fmtSecs(tardy.ColdLoadSec)))
	} // end of the load sentence
	// The model that uses the least memory, and the model that gives the most speed for its memory.
	var small, thrifty *perfRun
	// Look for them.
	for i := range texts {
		// A model with no size cannot be ranked.
		if texts[i].ModelBytes <= 0 {
			// Skip it.
			continue
		} // end of the check
		// The smallest.
		if small == nil || texts[i].ModelBytes < small.ModelBytes {
			// Remember it.
			small = &texts[i]
		} // end of the small check
		// A model with no speed cannot be thrifty.
		if texts[i].AnswerSpeed <= 0 {
			// Skip it.
			continue
		} // end of the speed check
		// The most speed for each gigabyte.
		if thrifty == nil || texts[i].AnswerSpeed/cmpGB(texts[i].ModelBytes) > thrifty.AnswerSpeed/cmpGB(thrifty.ModelBytes) {
			// Remember it.
			thrifty = &texts[i]
		} // end of the thrifty check
	} // end of the loop
	// The memory sentence.
	if small != nil {
		// The sentence.
		s := fmt.Sprintf("%s uses the least memory (%s).", small.Model, formatSize(small.ModelBytes))
		// Add the thrifty model when it is another one.
		if thrifty != nil && thrifty != small {
			// The addition.
			s += fmt.Sprintf(" %s gives the most speed for its memory (%.1f tokens/s per GB).", thrifty.Model, thrifty.AnswerSpeed/cmpGB(thrifty.ModelBytes))
		} else if thrifty != nil {
			// The same model.
			s += fmt.Sprintf(" It also gives the most speed for its memory (%.1f tokens/s per GB).", thrifty.AnswerSpeed/cmpGB(thrifty.ModelBytes))
		} // end of the thrifty check
		// Keep it.
		out = append(out, s)
	} // end of the memory sentence
	// Models that do not fit fully on the graphics card.
	var spill []string
	// Look for them.
	for _, r := range texts {
		// A known size and part of it outside the graphics card.
		if r.ModelBytes > 0 && r.GPUBytes < r.ModelBytes {
			// Name it.
			spill = append(spill, r.Model)
		} // end of the check
	} // end of the loop
	// The sentence.
	if len(spill) > 0 {
		// Say which ones.
		out = append(out, "Not fully on the graphics card (so slower than they could be): "+strings.Join(spill, ", ")+".")
	} // end of the spill sentence
	// Hand them back.
	return out
} // end of textFindings

// embedFindings reads plain sentences out of the embedding-model runs (sorted by time, shortest first).
func embedFindings(embeds []perfRun) []string {
	// With fewer than two models there is nothing to compare, and no sentence is needed for none at all.
	if len(embeds) < 2 {
		// Nothing to say; the table speaks for itself.
		return nil
	} // end of the count check
	// The fastest and the slowest embedder, among models with a figure.
	var fast, slow *perfRun
	// Look for them.
	for i := range embeds {
		// A model with no figure cannot be ranked.
		if embeds[i].WarmTotalSec <= 0 {
			// Skip it.
			continue
		} // end of the check
		// The first one found is the fastest.
		if fast == nil {
			// Remember it.
			fast = &embeds[i]
		} // end of the fastest check
		// The last one found is the slowest.
		slow = &embeds[i]
	} // end of the loop
	// Two different models with a figure.
	if fast != nil && slow != nil && fast != slow {
		// The sentence.
		return []string{fmt.Sprintf("%s embeds fastest (%s). %s needs %s, %.1f× longer.", fast.Model, fmtSecs(fast.WarmTotalSec), slow.Model, fmtSecs(slow.WarmTotalSec), slow.WarmTotalSec/fast.WarmTotalSec)}
	} // end of the sentence check
	// Nothing to say.
	return nil
} // end of embedFindings

// compareHandler serves the comparison page; it only reads the saved figures and changes nothing.
func compareHandler(addr ollamaAddress, token string, store *perfStore) http.HandlerFunc {
	// Read the template once, together with the shared help-bubble templates.
	page := template.Must(template.New("compare").Parse(compareTemplateText + tipsTemplateText))
	// The handler.
	return func(w http.ResponseWriter, r *http.Request) {
		// Limit the size of the form.
		r.Body = http.MaxBytesReader(w, r.Body, 1024)
		// Only the monitor's own page may ask.
		if !sameOrigin(r) {
			// Refuse.
			http.Error(w, "request did not come from this page", http.StatusForbidden)
			// Stop here.
			return
		} // end of the origin check
		// Read the form.
		if err := r.ParseForm(); err != nil {
			// Refuse.
			http.Error(w, "bad form", http.StatusBadRequest)
			// Stop here.
			return
		} // end of the form check
		// The page token must match.
		if !tokenValid(token, r.PostFormValue("token")) {
			// Refuse.
			http.Error(w, "bad token", http.StatusForbidden)
			// Stop here.
			return
		} // end of the token check
		// Which models Ollama has now (an error only means the "no longer installed" note is left out).
		installed := map[string]bool{}
		// Read them.
		list, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
		// Fill the set.
		for _, m := range list {
			// One name.
			installed[m.Name] = true
		} // end of the loop
		// The latest runs.
		runs, skipped := store.latestRuns(perfPromptVersion)
		// Build the page.
		data := buildCompare(runs, skipped, installed, err == nil)
		// Add what every page needs.
		data.Theme, data.Token = themeFromRequest(r), token
		// The saved text size, from the cookie; empty means the browser's own size.
		data.Size = sizeFromRequest(r)
		// Where the figures live.
		path, note := store.where()
		// A file, or the reason there is none.
		if path != "" {
			// Say where.
			data.SaveNote = "The figures come from " + path + "."
		} else {
			// The reason.
			data.SaveNote = note
		} // end of the path check
		// Build the page in memory first, so a template error gives a clean 500 and not a half page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason.
			log.Printf("compare page error: %v", err)
			// Send a plain 500.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// Tell the browser this is an HTML page.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the finished page.
		w.Write(buf.Bytes())
	} // end of the handler
} // end of compareHandler
