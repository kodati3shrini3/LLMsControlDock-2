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
	// path/filepath names the folder of the saved results.
	"path/filepath"
) // end of imports

// compareTemplateText is the page template, stored inside the executable at build time.
//
//go:embed web/compare.html
var compareTemplateText string

// compareTextHeadings are the column headings of a group of chat models, in order.
var compareTextHeadings = []string{"Model", "Parameters", "Quantization", "Tested on", "Answer speed", "Characters per second", "Speed vs fastest", "Prompt reading speed", "Time to first word", "Total time", "Load time", "Load speed from disk", "Memory used", "Processor split", "Machine busy", "Fair to rank?"}

// compareEmbedHeadings are the column headings of the group of embedding models, in order.
var compareEmbedHeadings = []string{"Model", "Quantization", "Tested on", "Embedding time", "Speed vs fastest", "Load time", "Load speed from disk", "Memory used", "Processor split", "Vector length", "Machine busy", "Fair to rank?"}

// compareExtraHeadings are the headings that exist only on the comparison page and need their own tooltip (the others are shared with the performance page).
var compareExtraHeadings = []string{"Tested on", "Speed vs fastest", "Characters per second", "Load speed from disk", "Machine busy", "Fair to rank?"}

// cmpRow is one model in a comparison table.
type cmpRow struct {
	// Cells are the values, one for each column.
	Cells []string
	// Busy is true when the run was made on a busy machine.
	Busy bool
} // end of cmpRow

// howRow is one question of the "How and why" section with its answer; the numbers in brackets point to the reference list.
type howRow struct {
	// Question is what a reader may ask.
	Question string
	// Answer says how and why, in plain words.
	Answer string
} // end of howRow

// cmpGroupView is one comparison group as the page draws it.
type cmpGroupView struct {
	// Title is the heading of the group.
	Title string
	// Why is the reason the models are compared together.
	Why string
	// Headline is the sentence about the fastest model, or empty.
	Headline string
	// Notes explain why there is no ranking, or that the model has no peer.
	Notes []string
	// Cols are the column headings with their help bubbles.
	Cols []tipView
	// Rows are the models.
	Rows []cmpRow
	// Retest holds the names of the models of this group that Ollama still has, when there are at least two; the button of the group re-test passes them on.
	Retest []string
} // end of cmpGroupView

// comparePage is everything the comparison template needs.
type comparePage struct {
	// Theme is the colour scheme asked for in the address, or empty.
	Theme string
	// Size is the saved text size, medium, or empty for the browser's own size.
	Size string
	// Token is the page token for the forms.
	Token string
	// Groups are the comparison groups.
	Groups []cmpGroupView
	// Findings are plain sentences read out of the figures.
	Findings []string
	// Notes are cautions about how to read the page.
	Notes []string
	// Empty is true when no test is saved yet.
	Empty bool
	// SaveNote says where the figures come from, or why there is no file.
	SaveNote string
	// NoticeShort is the short notice at the top.
	NoticeShort string
	// NoticeTitle is the heading of the full notice.
	NoticeTitle string
	// NoticeFull is the full notice, one paragraph per entry.
	NoticeFull []string
	// How is the "How and why this comparison was done" section.
	How []howRow
	// Refs is the verified reference list.
	Refs []reference
	// RefsChecked is the day the references were read.
	RefsChecked string
	// Models is how many models are shown, for the downloads.
	Models int
	// Data is the same groups in their raw form, for the CSV download.
	Data []cmpGroup
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

// cmpFair writes the "Fair to rank?" cell: yes, or no with every reason; symbols are for the page, plain words for the downloads.
func cmpFair(m cmpModel, symbols bool) string {
	// No reasons: the model can be ranked.
	if len(m.Reasons) == 0 {
		// With symbols for the page, plain words for downloads.
		if symbols {
			// The page form.
			return "✓ Yes"
		} // end of the symbol check
		// The plain form.
		return "Yes"
	} // end of the fair check
	// Join the reasons.
	why := ""
	// Go through them.
	for i, r := range m.Reasons {
		// A separator between reasons.
		if i > 0 {
			// Semicolon and space.
			why += "; "
		} // end of the separator check
		// The reason.
		why += r
	} // end of the loop
	// With symbols for the page, plain words for downloads.
	if symbols {
		// The page form.
		return "⚠ No: " + why
	} // end of the symbol check
	// The plain form.
	return "No: " + why
} // end of cmpFair

// cmpVsFastest writes the "Speed vs fastest" cell of one model inside its group.
func cmpVsFastest(g cmpGroup, m cmpModel) string {
	// A model outside the ranking.
	if m.Rank == 0 {
		// Say so.
		return "not ranked"
	} // end of the rank check
	// The best model is the one in first place.
	best := cmpBest(g.Models).Run
	// The best model itself.
	if m.Rank == 1 {
		// Say so.
		return "#1, fastest"
	} // end of the first check
	// The ratio, worked out from the figure the group is ranked by.
	ratio := 0.0
	// An embedding group: time against the shortest time.
	if g.Embedding {
		// Longer is slower.
		if best.WarmTotalSec > 0 {
			// The ratio.
			ratio = m.Run.WarmTotalSec / best.WarmTotalSec
		} // end of the figure check
	} else if m.Run.CharSpeed > 0 {
		// A chat group: the best speed against this speed.
		ratio = best.CharSpeed / m.Run.CharSpeed
	} // end of the kind check
	// Without a ratio only the place is shown.
	if ratio <= 0 {
		// The place.
		return fmt.Sprintf("#%d", m.Rank)
	} // end of the ratio check
	// The place and the ratio.
	return fmt.Sprintf("#%d, %.1f× slower", m.Rank, ratio)
} // end of cmpVsFastest

// cmpMemory writes the memory cell.
func cmpMemory(r perfRun) string {
	// Not reported.
	if r.ModelBytes <= 0 {
		// Say so.
		return "not reported"
	} // end of the check
	// The size.
	return formatSize(r.ModelBytes)
} // end of cmpMemory

// cmpCharSpeed writes the characters-per-second cell.
func cmpCharSpeed(r perfRun) string {
	// Older tests did not count characters.
	if r.CharSpeed <= 0 {
		// Say so.
		return "not saved (older test)"
	} // end of the check
	// A whole number is precise enough.
	return fmt.Sprintf("%.0f chars/s", r.CharSpeed)
} // end of cmpCharSpeed

// groupRowCells writes the cells of one model, in the order of the group's headings.
func groupRowCells(g cmpGroup, m cmpModel) []string {
	// The test.
	r := m.Run
	// The date.
	when := r.Time.UTC().Format("2006-01-02 15:04 UTC")
	// An embedding group.
	if g.Embedding {
		// The cells.
		return []string{m.Name, m.Quant, when, fmtSecs(r.WarmTotalSec), cmpVsFastest(g, m), fmtSecs(r.ColdLoadSec), cmpLoadSpeed(r), cmpMemory(r), cmpSplit(r), fmt.Sprintf("%d numbers", r.VectorLength), cmpBusy(r), cmpFair(m, true)}
	} // end of the embedding case
	// The cells of a chat model.
	return []string{m.Name, m.Params, m.Quant, when, fmtSpeed(r.AnswerSpeed), cmpCharSpeed(r), cmpVsFastest(g, m), fmtSpeed(r.PromptSpeed), fmtSecs(r.WarmFirstWordSec), fmtSecs(r.WarmTotalSec), fmtSecs(r.ColdLoadSec), cmpLoadSpeed(r), cmpMemory(r), cmpSplit(r), cmpBusy(r), cmpFair(m, true)}
} // end of groupRowCells

// howRows writes the "How and why this comparison was done" section; the numbers in brackets are checked against the reference list by a test.
func howRows() []howRow {
	// The rows.
	return []howRow{
		// What is measured.
		{"What is measured?", "How fast each model answers one request at a time (the single-stream case) and how much memory it uses. It does not measure the quality or safety of the answers, many users at once, or long documents. [4]"},
		// How a test runs.
		{"How is a test run?", fmt.Sprintf("Every model gets the same fixed prompt, the same planned answer length (%d tokens), temperature 0 and the same random seed. One warm-up run is thrown away, and the middle value (median) of %d timed runs is kept. [1][3]", perfAnswerTokens, perfTimedRuns)},
		// Why characters.
		{"Why characters per second?", "Models cut text into tokens in different ways, so tokens per second cannot be compared between models of different makers. One published method counts every model's tokens with a single common tokenizer [3]; this program counts the characters of the answer instead, which needs no extra software and is the same for every model. Tokens per second is still shown for information."},
		// How groups are chosen.
		{"How are the groups chosen?", "By kind (chat or embedding) and, for chat models, by size class, using the parameter count Ollama reports. The five size classes are this program's own choice, not an industry standard. If Ollama reports no size, the class is estimated from the memory the model used, and such a model is not ranked. Embedding models are a group of their own [6]."},
		// What decides a rank.
		{"What decides whether a row can be ranked?", fmt.Sprintf("A model is ranked only when nothing makes it unlike the rest of its group: the same precision as most of the group, a test made within %d hours of the newest one, the same Ollama version and context length, the whole model on the graphics card, a quiet machine, no other model loaded, a full-length answer and a saved character count. The last column gives the reasons. The %d-hour limit is this program's own rule.", cmpSameSittingHours, cmpSameSittingHours)},
		// Why nothing is ranked across groups.
		{"Why is nothing ranked across groups?", "Results gained under different conditions are not directly comparable. The MLPerf paper applies this to its own results [4], and NVIDIA's documentation says to compare results only when the definitions align [2]."},
		// How the figures are worked out.
		{"How are the figures worked out?", "From the figures Ollama reports with each reply: counts of tokens and durations in nanoseconds [5]. Answer speed is the answer tokens divided by the answer time. Characters per second is the characters of the answer divided by the answer time. These two formulas are this program's own calculations, and the time to the first word is measured by this program."},
		// What is not covered.
		{"What is not covered?", "The quality and safety of answers, many users at once, long prompts, and other computers. Read the notice at the end of this page before using any figure."},
	} // end of the rows
} // end of howRows

// buildCompare turns the latest saved runs into the page: comparison groups with fairness flags, the sentences read out of them, the method, the references and the notice.
func buildCompare(runs []perfRun, skipped int, installed map[string]modelDetails, known bool) comparePage {
	// The page, with the parts that never change.
	p := comparePage{NoticeShort: noticeShort, NoticeTitle: noticeTitle, NoticeFull: noticeFull, How: howRows(), Refs: compareReferences, RefsChecked: referencesChecked, Models: len(runs)}
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
	// The groups.
	groups := groupRuns(runs, installed, known)
	// Keep the raw groups for the downloads.
	p.Data = groups
	// The first sentence says how to read the page.
	p.Findings = append(p.Findings, "Models are compared only inside their group, under like-for-like conditions. There is no single winner across the whole list. [1][2][4]")
	// Any busy run.
	busy := 0
	// Build the view of each group.
	for gi, g := range groups {
		// The heading list of the group.
		heads := compareTextHeadings
		// The prefix of the element names.
		prefix := "t"
		// An embedding group has its own columns.
		if g.Embedding {
			// Its headings.
			heads = compareEmbedHeadings
			// Its prefix.
			prefix = "e"
		} // end of the embedding check
		// The view.
		v := cmpGroupView{Title: g.Title, Why: g.Why, Headline: g.Headline, Notes: g.Notes}
		// The headings with their bubbles, with element names that are unique on the page.
		for i, h := range heads {
			// One heading.
			v.Cols = append(v.Cols, makeTip(fmt.Sprintf("tip-cmp-%s%d-%d", prefix, gi, i), h))
		} // end of the heading loop
		// The rows.
		for _, m := range g.Models {
			// One row.
			v.Rows = append(v.Rows, cmpRow{Busy: m.Run.Busy, Cells: groupRowCells(g, m)})
			// A model Ollama still has can be tested again; one that is gone cannot.
			if _, still := installed[m.Run.Model]; known && still {
				// Keep its real name (the shown name may carry a note).
				v.Retest = append(v.Retest, m.Run.Model)
			} // end of the installed check
			// Count the busy tests.
			if m.Run.Busy {
				// One more.
				busy++
			} // end of the busy check
		} // end of the row loop
		// The sentence about the group.
		switch {
		// A ranked group.
		case g.Headline != "":
			// Name the winner.
			p.Findings = append(p.Findings, g.Title+": "+g.Headline)
		// A group with one model.
		case len(g.Models) == 1:
			// Say so.
			p.Findings = append(p.Findings, g.Title+": only one model, so there is nothing to rank yet.")
		// A group that cannot be ranked.
		default:
			// Say so.
			p.Findings = append(p.Findings, g.Title+": no ranking yet, because fewer than two models can be compared like for like.")
		} // end of the sentence switch
		// The button needs at least two models to be worth a group run.
		if len(v.Retest) < 2 {
			// No button for this group.
			v.Retest = nil
		} // end of the count check
		// Keep the group.
		p.Groups = append(p.Groups, v)
	} // end of the group loop
	// The standing caution.
	p.Notes = append(p.Notes, "Only the latest test of each model is shown. A row marked with a caution is shown for information but is not ranked.")
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

// gatherCompare reads the saved tests and the installed models and builds the page; the page, the PDF and the CSV all come from here, so they can never disagree.
func gatherCompare(r *http.Request, addr ollamaAddress, store *perfStore) comparePage {
	// What Ollama has now: its details tell the size and precision of every model that is still installed (an error only means the "no longer installed" note is left out).
	installed := map[string]modelDetails{}
	// Read them.
	list, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
	// Fill the map.
	for _, m := range list {
		// One model.
		installed[m.Name] = m.Details
	} // end of the loop
	// The latest runs.
	runs, skipped := store.latestRuns(perfPromptVersion)
	// Build the page.
	data := buildCompare(runs, skipped, installed, err == nil)
	// Where the figures live.
	path, note := store.where()
	// A file, or the reason there is none.
	if path != "" {
		// Say where.
		data.SaveNote = "The figures come from " + path + ". Each PDF or CSV you save here is written by the program into the folder " + filepath.Dir(path) + "; the browser asks for no place."
	} else {
		// The reason.
		data.SaveNote = note
	} // end of the path check
	// Hand it back.
	return data
} // end of gatherCompare

// compareForm runs the checks every comparison request shares (same page, small form, valid token); ok is false after a refusal was sent.
func compareForm(w http.ResponseWriter, r *http.Request, token string) bool {
	// Limit the size of the form.
	r.Body = http.MaxBytesReader(w, r.Body, 1024)
	// Only the monitor's own page may ask.
	if !sameOrigin(r) {
		// Refuse.
		http.Error(w, "request did not come from this page", http.StatusForbidden)
		// Stop here.
		return false
	} // end of the origin check
	// Read the form.
	if err := r.ParseForm(); err != nil {
		// Refuse.
		http.Error(w, "bad form", http.StatusBadRequest)
		// Stop here.
		return false
	} // end of the form check
	// The page token must match.
	if !tokenValid(token, r.PostFormValue("token")) {
		// Refuse.
		http.Error(w, "bad token", http.StatusForbidden)
		// Stop here.
		return false
	} // end of the token check
	// All checks passed.
	return true
} // end of compareForm

// compareHandler serves the comparison page; it only reads the saved figures and changes nothing.
func compareHandler(addr ollamaAddress, token string, store *perfStore) http.HandlerFunc {
	// Read the template once, together with the shared help-bubble templates.
	page := template.Must(template.New("compare").Parse(compareTemplateText + tipsTemplateText))
	// The handler.
	return func(w http.ResponseWriter, r *http.Request) {
		// The shared checks.
		if !compareForm(w, r, token) {
			// A refusal was sent.
			return
		} // end of the checks
		// Build the page data.
		data := gatherCompare(r, addr, store)
		// Add what every page needs.
		data.Theme, data.Token = themeFromRequest(r), token
		// The saved text size, from the cookie; empty means the browser's own size.
		data.Size = sizeFromRequest(r)
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
