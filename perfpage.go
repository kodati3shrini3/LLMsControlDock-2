// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// context carries the time limit of the clean-up.
	"context"
	// bytes builds the page in memory before it is sent.
	"bytes"
	// embed stores the page template inside the executable.
	_ "embed"
	// fmt builds formatted text.
	"fmt"
	// html/template builds the page and escapes every inserted text.
	"html/template"
	// log writes the real reason for an error for the person running the program.
	"log"
	// math measures the size of a change.
	"math"
	// net/http provides the request and response types.
	"net/http"
	// strings joins and searches text.
	"strings"
	// sync keeps two tests from running at the same time.
	"sync"
	// time stamps the safety copy of removed results.
	"time"
) // end of imports

// performanceTemplateText holds the performance pages, stored inside the executable at build time.
//
//go:embed web/performance.html
var performanceTemplateText string

// perfRow is one line of a table on the performance page.
type perfRow struct {
	// Tip is the help bubble of the indicator; its ID is empty when the row has only a plain label.
	Tip tipView
	// Label is the plain label used when there is no bubble.
	Label string
	// Cells are the values, one per column.
	Cells []string
} // end of perfRow

// perfGroup is one table with a heading.
type perfGroup struct {
	// Title is the heading of the table.
	Title string
	// Tip is the help bubble of the heading, when it has one.
	Tip tipView
	// Note is a sentence under the heading.
	Note string
	// Cols are the column headings after the first.
	Cols []string
	// Rows are the lines.
	Rows []perfRow
} // end of perfGroup

// perfPage is everything the performance pages can show.
type perfPage struct {
	// Theme is the saved colour theme, or empty to follow the system.
	Theme string
	// Size is the saved text size, medium, or empty for the browser's own size.
	Size string
	// Token is the page token every form carries.
	Token string
	// Kind chooses the version of the page.
	Kind string
	// Model is the model name.
	Model string
	// Detail is a plain reason on the error page.
	Detail string
	// Embedding is true for an embedding model.
	Embedding bool
	// Groups are the result tables.
	Groups []perfGroup
	// BusyReason is set when the machine looked busy.
	BusyReason string
	// LeftLoaded is true when the model could not be unloaded again.
	LeftLoaded bool
	// SaveNote says where the history is kept, or why it is not saved to a file.
	SaveNote string
	// HistoryCols are the column headings of the history table.
	HistoryCols []string
	// HistoryRows are the lines of the history table, newest first.
	HistoryRows [][]string
	// HistoryCount is how many runs are saved in all, for every model.
	HistoryCount int
	// Seconds is the rough time the test may take, in words.
	Duration string
	// Summaries are the lines of the "what you lose" table.
	Summaries []perfSummary
	// CompareNow is how many models "Compare tested models" lists now.
	CompareNow int
	// InCompare is true when the model is in that list now.
	InCompare bool
	// RemoveCount is how many results one removal takes away.
	RemoveCount int
	// OtherCount is how many results of other models would stay.
	OtherCount int
	// CopyPlan says, before removal, whether a safety copy will be kept.
	CopyPlan string
	// CopyPlanBad is true when no safety copy can be kept.
	CopyPlanBad bool
	// CopyFile is the full path of the safety copy that was kept, or empty.
	CopyFile string
	// CopyErr is why no safety copy was kept, or empty.
	CopyErr string
} // end of perfPage

// fmtSecs shows a time in seconds with sensible decimals; zero means not available.
func fmtSecs(v float64) string {
	// Not available.
	if v <= 0 {
		// Say so.
		return "not available"
	} // end of the check
	// Under a second: milliseconds' precision.
	if v < 1 {
		// Three decimals.
		return fmt.Sprintf("%.3f s", v)
	} // end of the small case
	// Under a hundred seconds: two decimals.
	if v < 100 {
		// Two decimals.
		return fmt.Sprintf("%.2f s", v)
	} // end of the middle case
	// Longer: whole seconds.
	return fmt.Sprintf("%.0f s", v)
} // end of fmtSecs

// fmtSpeed shows a speed in tokens per second; zero means not available.
func fmtSpeed(v float64) string {
	// Not available.
	if v <= 0 {
		// Say so.
		return "not available"
	} // end of the check
	// One decimal.
	return fmt.Sprintf("%.1f tokens/s", v)
} // end of fmtSpeed

// changeText compares this run with the previous one: the percentage and the words faster or slower.
func changeText(cur, prev float64, higherIsFaster bool) string {
	// Both figures are needed.
	if cur <= 0 || prev <= 0 {
		// Say so.
		return "not comparable"
	} // end of the check
	// The change in percent.
	pct := (cur - prev) / prev * 100
	// A tiny change is called no change.
	if math.Abs(pct) < 0.5 {
		// Say so.
		return "no change (within 0.5%)"
	} // end of the tiny case
	// Faster means a higher speed or a lower time.
	faster := (pct > 0) == higherIsFaster
	// The word.
	word := "slower"
	// Switch it for a faster run.
	if faster {
		// Faster.
		word = "faster"
	} // end of the word choice
	// The text.
	return fmt.Sprintf("%+.1f%% (%s)", pct, word)
} // end of changeText

// gbText shows decimal gigabytes with one decimal; zero means not reported.
func gbText(v float64) string {
	// Not reported.
	if v <= 0 {
		// Say so.
		return "not reported"
	} // end of the check
	// One decimal.
	return fmt.Sprintf("%.1f GB", v)
} // end of gbText

// machineRows builds the "machine condition" table rows from the two snapshots.
func machineRows(before, after machineSnapshot, other []string, tips map[string]tipView) []perfRow {
	// The rows.
	var rows []perfRow
	// cpu load text.
	load := func(s machineSnapshot) string {
		// Not reported.
		if s.Load1 < 0 {
			// Say so.
			return "not reported"
		} // end of the check
		// One decimal.
		return fmt.Sprintf("%.1f (last minute)", s.Load1)
	} // end of load
	// memory text.
	mem := func(s machineSnapshot) string {
		// Not reported.
		if s.MemTotalGB <= 0 {
			// Say so.
			return "not reported"
		} // end of the check
		// Free of total.
		return gbText(s.MemFreeGB) + " free of " + gbText(s.MemTotalGB)
	} // end of mem
	// swap text.
	swap := func(s machineSnapshot) string {
		// Not reported.
		if s.SwapUsedGB < 0 {
			// Say so.
			return "not reported"
		} // end of the check
		// Used of total.
		return fmt.Sprintf("%.1f GB of %.1f GB", s.SwapUsedGB, s.SwapTotalGB)
	} // end of swap
	// gpu text.
	gpu := func(s machineSnapshot) string {
		// No tool reported a card.
		if s.GPUName == "" {
			// Say so.
			return "not reported"
		} // end of the check
		// The name.
		t := s.GPUName
		// The busy percentage.
		if s.GPUUtil >= 0 {
			// Add it.
			t += fmt.Sprintf(", %d%% busy", s.GPUUtil)
		} // end of the util check
		// The memory, unless it is not reported.
		if s.GPUMemory != "" && !strings.Contains(s.GPUMemory, "N/A") {
			// Add it.
			t += ", memory " + s.GPUMemory
		} else {
			// Say so.
			t += ", memory not reported"
		} // end of the memory check
		// The text.
		return t
	} // end of gpu
	// The processor.
	cores := func(s machineSnapshot) string {
		// The count, and the name when known.
		t := fmt.Sprintf("%d", s.Cores)
		// The name.
		if s.CPUName != "" {
			// Add it.
			t += " (" + s.CPUName + ")"
		} // end of the name check
		// The text.
		return t
	} // end of cores
	// The other loaded models.
	others := "none"
	// Some were loaded.
	if len(other) > 0 {
		// List them.
		others = strings.Join(other, ", ")
	} // end of the check
	// The six rows, in the order of the plan.
	rows = append(rows,
		// Cores.
		perfRow{Tip: tips["CPU cores"], Cells: []string{cores(before), cores(after)}},
		// Load.
		perfRow{Tip: tips["CPU load"], Cells: []string{load(before), load(after)}},
		// Free memory.
		perfRow{Tip: tips["Memory free"], Cells: []string{mem(before), mem(after)}},
		// Swap.
		perfRow{Tip: tips["Swap in use"], Cells: []string{swap(before), swap(after)}},
		// Other models.
		perfRow{Tip: tips["Other models loaded"], Cells: []string{others, "-"}},
		// The graphics card.
		perfRow{Tip: tips["GPU"], Cells: []string{gpu(before), gpu(after)}},
	) // end of the rows
	// Hand them back.
	return rows
} // end of machineRows

// buildGroups builds the four result tables of a run; prev is the previous run of the same model and prompt, or nil.
func buildGroups(run perfRun, prev *perfRun, tips map[string]tipView) []perfGroup {
	// The groups.
	var groups []perfGroup
	// Group A: measured by the test.
	a := perfGroup{Title: "Measured by the test", Cols: []string{"Result", "Detail"}}
	// An embedding model.
	if run.Kind == "embedding" {
		// A note: no text is written.
		a.Note = "An embedding model writes no text, so answer speed and prompt reading speed do not apply to it."
		// The rows.
		a.Rows = append(a.Rows,
			// Embedding time.
			perfRow{Tip: tips["Embedding time"], Cells: []string{fmtSecs(run.WarmTotalSec), fmt.Sprintf("median of %d timed runs, model already loaded", run.Runs)}},
			// Load time.
			perfRow{Tip: tips["Load time"], Cells: []string{fmtSecs(run.ColdLoadSec), "cold: the warm-up run loaded the model from disk"}},
			// Tokens.
			perfRow{Tip: tips["Tokens counted"], Cells: []string{fmt.Sprintf("%d in", run.TokensIn), "the same fixed text every time (version " + run.PromptVersion + ")"}},
			// Vector.
			perfRow{Tip: tips["Vector length"], Cells: []string{fmt.Sprintf("%d numbers", run.VectorLength), "one vector per text"}},
		) // end of the rows
	} else {
		// A chat model: the first word shows warm and cold.
		first := fmtSecs(run.WarmFirstWordSec)
		// The cold detail.
		firstDetail := "warm (model loaded)"
		// Add the cold figure when there is one.
		if run.ColdFirstWordSec > 0 {
			// Cold includes loading.
			firstDetail += "; cold: " + fmtSecs(run.ColdFirstWordSec)
		} // end of the cold check
		// The rows.
		a.Rows = append(a.Rows,
			// Answer speed.
			perfRow{Tip: tips["Answer speed"], Cells: []string{fmtSpeed(run.AnswerSpeed), fmt.Sprintf("median of %d timed runs", run.Runs)}},
			// Prompt reading speed.
			perfRow{Tip: tips["Prompt reading speed"], Cells: []string{fmtSpeed(run.PromptSpeed), fmt.Sprintf("median of %d timed runs", run.Runs)}},
			// Load time.
			perfRow{Tip: tips["Load time"], Cells: []string{fmtSecs(run.ColdLoadSec), "cold: the warm-up run loaded the model from disk"}},
			// Total time.
			perfRow{Tip: tips["Total time"], Cells: []string{fmtSecs(run.WarmTotalSec), fmt.Sprintf("median of %d timed runs, model already loaded", run.Runs)}},
			// First word.
			perfRow{Tip: tips["Time to first word"], Cells: []string{first, firstDetail}},
			// Tokens.
			perfRow{Tip: tips["Tokens counted"], Cells: []string{fmt.Sprintf("%d in, %d out", run.TokensIn, run.TokensOut), "the same fixed prompt every time (version " + run.PromptVersion + ")"}},
		) // end of the rows
	} // end of the kind check
	// Add group A.
	groups = append(groups, a)
	// Group B: reported by Ollama.
	b := perfGroup{Title: "Reported by Ollama about the loaded model", Cols: []string{"Result", "Detail"}}
	// The processor split needs the memory figures.
	split, splitDetail := "not reported", ""
	// Work it out.
	if run.ModelBytes > 0 {
		// The graphics share.
		gpuPct := float64(run.GPUBytes) / float64(run.ModelBytes) * 100
		// The text.
		split = fmt.Sprintf("%.0f%% graphics card, %.0f%% processor and main memory", gpuPct, 100-gpuPct)
		// The detail.
		splitDetail = "from the memory Ollama reports"
	} // end of the split check
	// The memory text.
	memText := "not reported"
	// Known.
	if run.ModelBytes > 0 {
		// Use the same size format as the tables.
		memText = formatSize(run.ModelBytes)
	} // end of the memory check
	// The context text.
	ctxText := "not reported"
	// Known.
	if run.ContextLength > 0 {
		// The number.
		ctxText = fmt.Sprintf("%d", run.ContextLength)
	} // end of the context check
	// The rows.
	b.Rows = append(b.Rows,
		// Split.
		perfRow{Tip: tips["Processor split"], Cells: []string{split, splitDetail}},
		// Memory.
		perfRow{Tip: tips["Memory used"], Cells: []string{memText, "as Ollama reports it"}},
		// Context.
		perfRow{Tip: tips["Loaded context length"], Cells: []string{ctxText, "the context the model was loaded with"}},
	) // end of the rows
	// Add group B.
	groups = append(groups, b)
	// Group C: compared with the previous run.
	c := perfGroup{Title: "Change since the previous run", Tip: tips["Change since the previous run"]}
	// No earlier run.
	if prev == nil {
		// Say so.
		c.Note = "No earlier test of this model with the same prompt is saved, so there is nothing to compare yet."
	} else {
		// The columns.
		c.Cols = []string{"This run", "Previous run", "Change"}
		// The previous run's date.
		c.Note = "The previous run was made on " + formatTime(prev.Time) + "."
		// An embedding model compares its time only.
		if run.Kind == "embedding" {
			// One row.
			c.Rows = append(c.Rows, perfRow{Label: "Embedding time", Cells: []string{fmtSecs(run.WarmTotalSec), fmtSecs(prev.WarmTotalSec), changeText(run.WarmTotalSec, prev.WarmTotalSec, false)}})
		} else {
			// Three rows.
			c.Rows = append(c.Rows,
				// Answer speed: higher is faster.
				perfRow{Label: "Answer speed", Cells: []string{fmtSpeed(run.AnswerSpeed), fmtSpeed(prev.AnswerSpeed), changeText(run.AnswerSpeed, prev.AnswerSpeed, true)}},
				// Prompt speed: higher is faster.
				perfRow{Label: "Prompt reading speed", Cells: []string{fmtSpeed(run.PromptSpeed), fmtSpeed(prev.PromptSpeed), changeText(run.PromptSpeed, prev.PromptSpeed, true)}},
				// Total time: lower is faster.
				perfRow{Label: "Total time", Cells: []string{fmtSecs(run.WarmTotalSec), fmtSecs(prev.WarmTotalSec), changeText(run.WarmTotalSec, prev.WarmTotalSec, false)}},
			) // end of the rows
		} // end of the kind check
	} // end of the previous check
	// Add group C.
	groups = append(groups, c)
	// Group D: the machine.
	d := perfGroup{Title: "Machine condition during the test", Cols: []string{"Before the test", "With the model loaded"}}
	// Ollama on another computer: only the note.
	if !run.Before.Local {
		// The note.
		d.Note = run.Before.Note
		// The other models are still known from Ollama itself.
		others := "none"
		// Some were loaded.
		if len(run.OtherLoaded) > 0 {
			// List them.
			others = strings.Join(run.OtherLoaded, ", ")
		} // end of the check
		// One row.
		d.Rows = append(d.Rows, perfRow{Tip: tips["Other models loaded"], Cells: []string{others, "-"}})
	} else {
		// The rows.
		d.Rows = machineRows(run.Before, run.After, run.OtherLoaded, tips)
	} // end of the local check
	// Add group D.
	groups = append(groups, d)
	// Hand them back.
	return groups
} // end of buildGroups

// historyTable builds the history table of one model: headings and lines, newest first, at most 20 lines.
func historyTable(runs []perfRun, kind string) ([]string, [][]string) {
	// The headings.
	cols := []string{"Date", "Answer speed", "Prompt reading speed", "Load time (cold)", "Total time", "Machine busy?"}
	// An embedding model has other columns.
	if kind == "embedding" {
		// Its headings.
		cols = []string{"Date", "Embedding time", "Load time (cold)", "Tokens in", "Vector length", "Machine busy?"}
	} // end of the kind check
	// The lines.
	var rows [][]string
	// Go through the runs, newest first, at most twenty.
	for i, r := range runs {
		// Stop after twenty.
		if i >= 20 {
			// Enough.
			break
		} // end of the limit check
		// The busy cell: a symbol and words, so colour is never the only signal.
		busy := "no"
		// Busy.
		if r.Busy {
			// Say so.
			busy = "⚠ yes"
		} // end of the busy check
		// The line.
		if kind == "embedding" {
			// An embedding line.
			rows = append(rows, []string{formatTime(r.Time), fmtSecs(r.WarmTotalSec), fmtSecs(r.ColdLoadSec), fmt.Sprintf("%d", r.TokensIn), fmt.Sprintf("%d", r.VectorLength), busy})
		} else {
			// A chat line.
			rows = append(rows, []string{formatTime(r.Time), fmtSpeed(r.AnswerSpeed), fmtSpeed(r.PromptSpeed), fmtSecs(r.ColdLoadSec), fmtSecs(r.WarmTotalSec), busy})
		} // end of the line choice
	} // end of the loop
	// Hand them back.
	return cols, rows
} // end of historyTable

// perfHandlers builds the six handlers: the start page (changes nothing), the run, the two steps of clearing all saved results, and the two steps of clearing one model's results; the history folder receives a safety copy of whatever is removed.
func perfHandlers(addr ollamaAddress, token string, store *perfStore, hist *historyStore) (http.HandlerFunc, http.HandlerFunc, http.HandlerFunc, http.HandlerFunc, http.HandlerFunc, http.HandlerFunc) {
	// Read the template once, together with the shared help-bubble templates; Must stops the program at start-up if it is broken, which a test would catch first.
	page := template.Must(template.New("performance").Parse(performanceTemplateText + tipsTemplateText))
	// The help bubbles never change, so build them once, each with an element name that is unique on the page.
	tips := map[string]tipView{}
	// One for each indicator, and the loaded context column that is shared with the Loaded table.
	for i, h := range append(append([]string{}, perfHeadings...), "Loaded context length") {
		// Build it.
		tips[h] = makeTip(fmt.Sprintf("tip-perf-%d", i), h)
	} // end of the loop
	// Only one test may run at a time: two would disturb each other's figures.
	var runLock sync.Mutex
	// show builds the page in memory first, so a template error produces a clean 500 and not a half page.
	show := func(w http.ResponseWriter, r *http.Request, status int, data perfPage) {
		// Add what every version needs.
		data.Theme, data.Token = themeFromRequest(r), token
		// The saved text size, from the cookie; empty means the browser's own size.
		data.Size = sizeFromRequest(r)
		// Build the page.
		var buf bytes.Buffer
		// Run the template.
		if err := page.Execute(&buf, data); err != nil {
			// Log the real reason for the person running the program.
			log.Printf("performance page error: %v", err)
			// Send a plain 500 without details.
			http.Error(w, "internal error", http.StatusInternalServerError)
			// Stop here.
			return
		} // end of the template check
		// The start page may run the monitor's own waiting-message script, and nothing else.
		if data.Kind == "start" {
			// Replace the strict policy by the one that allows the script file.
			w.Header().Set("Content-Security-Policy", contentSecurityPolicyWithScript)
		} // end of the script policy
		// Tell the browser this is an HTML page.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// Send the status line.
		w.WriteHeader(status)
		// Send the finished page.
		w.Write(buf.Bytes())
	} // end of show
	// check runs the checks the start and the run share: the form, the model installed, not loaded, and able to be tested; it also returns what Ollama says about the model; ok is false after a page was shown.
	check := func(w http.ResponseWriter, r *http.Request) (string, bool, modelDetails, bool) {
		// The form checks: same page, valid token, sensible model name.
		name, ok := readModelForm(w, r, token)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return "", false, modelDetails{}, false
		} // end of the form checks
		// Read the installed models now, not what the page showed earlier.
		installed, err := fetchInstalled(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, perfPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return "", false, modelDetails{}, false
		} // end of the installed read check
		// The model must exist.
		m, found := findInstalled(installed, name)
		// Not installed.
		if !found {
			// Say so.
			show(w, r, http.StatusOK, perfPage{Kind: "notinstalled", Model: name})
			// Stop here.
			return "", false, modelDetails{}, false
		} // end of the installed check
		// Read the loaded models.
		loaded, err := fetchLoaded(r.Context(), addr.URL, defaultCheckTimeout)
		// Ollama could not be read.
		if err != nil {
			// Show the plain reason.
			show(w, r, http.StatusBadGateway, perfPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return "", false, modelDetails{}, false
		} // end of the loaded read check
		// A loaded model may be in use: the test is refused.
		if _, ok := findLoaded(loaded, name); ok {
			// Say so.
			show(w, r, http.StatusOK, perfPage{Kind: "loaded", Model: name})
			// Stop here.
			return "", false, modelDetails{}, false
		} // end of the loaded check
		// Which kind of test fits the model.
		switch categorize(m.Capabilities) {
		// Embedding models are tested by embedding.
		case categoryEmbedding:
			// An embedding test.
			return name, true, m.Details, true
		// Models that write text.
		case categoryText, categoryMultimodal:
			// A generate test.
			return name, false, m.Details, true
		} // end of the switch
		// Anything else cannot be tested.
		show(w, r, http.StatusOK, perfPage{Kind: "unsupported", Model: name})
		// Stop here.
		return "", false, modelDetails{}, false
	} // end of check
	// historyFor fills the history part of a page for one model.
	historyFor := func(p *perfPage, name string, embedding bool) {
		// The kind.
		kind := "generate"
		// An embedding model.
		if embedding {
			// Its kind.
			kind = "embedding"
		} // end of the kind check
		// The table.
		p.HistoryCols, p.HistoryRows = historyTable(store.forModel(name, kind), kind)
		// The count of all saved runs.
		p.HistoryCount = store.count()
		// Where the history lives.
		path, note := store.where()
		// A file, or the reason there is none.
		if path != "" {
			// Say where.
			p.SaveNote = "Results are saved in " + path + " (numbers only; the last " + fmt.Sprint(maxHistoryRuns) + " runs are kept)."
		} else {
			// The reason.
			p.SaveNote = note
		} // end of the path check
	} // end of historyFor
	// start is the first step: it explains the test and the risks, and shows earlier results; it changes nothing.
	start := func(w http.ResponseWriter, r *http.Request) {
		// The checks.
		name, embedding, _, ok := check(w, r)
		// A page was already shown.
		if !ok {
			// Stop here.
			return
		} // end of the checks
		// The page.
		p := perfPage{Kind: "start", Model: name, Embedding: embedding, Duration: "usually under a minute; a very large model can take several minutes to load"}
		// What the machine looks like now: a busy machine gets a warning.
		p.BusyReason = busyReason(snapshotMachine(r.Context(), isLocalAddress(addr.URL)))
		// The history.
		historyFor(&p, name, embedding)
		// Show it.
		show(w, r, http.StatusOK, p)
	} // end of start
	// run is the second step: it runs the test, saves the numbers and shows them.
	run := func(w http.ResponseWriter, r *http.Request) {
		// The checks.
		name, embedding, info, ok := check(w, r)
		// A page was already shown.
		if !ok {
			// Stop here.
			return
		} // end of the checks
		// Only one test at a time.
		if !runLock.TryLock() {
			// Say so.
			show(w, r, http.StatusOK, perfPage{Kind: "running", Model: name})
			// Stop here.
			return
		} // end of the lock check
		// Release it when done.
		defer runLock.Unlock()
		// Tell the Stop page that a test is running, and how to undo it: unload the model the test loaded.
		defer activeWork.begin("a performance test of "+name+" (Stop cancels it and unloads the model first)", func(ctx context.Context) {
			// Ask Ollama to unload the model; the answer does not matter here.
			unloadModel(ctx, addr.URL, name, defaultCheckTimeout)
			// Wait until it is really gone, within the time limit.
			waitUntilGone(ctx, addr.URL, name, defaultCheckTimeout)
		})()
		// The Ollama version, for the record.
		version := checkOllama(r.Context(), addr.URL, defaultCheckTimeout).Version
		// Run the test.
		res, err := performTest(r.Context(), addr.URL, name, embedding, version, info)
		// The test failed.
		if err != nil {
			// Show the plain reason; the model was unloaded again by the test itself.
			show(w, r, http.StatusBadGateway, perfPage{Kind: "error", Model: name, Detail: err.Error(), LeftLoaded: res.LeftLoaded})
			// Stop here.
			return
		} // end of the failure check
		// The previous run of the same model, kind and prompt, found before this one is added.
		var prev *perfRun
		// Newest first.
		for _, old := range store.forModel(name, res.Kind) {
			// Only runs with the same prompt are comparable.
			if old.PromptVersion == res.PromptVersion {
				// Keep a copy.
				o := old
				// This is it.
				prev = &o
				// Stop looking.
				break
			} // end of the prompt check
		} // end of the loop
		// Save the numbers.
		saveErr := store.add(res)
		// The page.
		p := perfPage{Kind: "result", Model: name, Embedding: embedding, Groups: buildGroups(res, prev, tips), BusyReason: res.BusyReason, LeftLoaded: res.LeftLoaded}
		// The history.
		historyFor(&p, name, embedding)
		// A save problem is told plainly.
		if saveErr != nil {
			// Say so.
			p.SaveNote = "The result could not be saved to the file (" + saveErr.Error() + "), so it is kept only until the monitor stops."
		} // end of the save check
		// Show it.
		show(w, r, http.StatusOK, p)
	} // end of run
	// clearAsk is the first step of clearing everything: it shows what would be lost and changes nothing.
	clearAsk := func(w http.ResponseWriter, r *http.Request) {
		// The form checks.
		name, ok := readModelForm(w, r, token)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the form checks
		// Whether a safety copy can be kept.
		plan, bad := removalPlan(hist)
		// Show the question with its consequences.
		show(w, r, http.StatusOK, perfPage{Kind: "clearask", Model: name, HistoryCount: store.count(), Summaries: store.summaries("", name), CompareNow: store.testedModels(), RemoveCount: store.countModel(name), CopyPlan: plan, CopyPlanBad: bad})
	} // end of clearAsk
	// clearDo is the second step: it keeps a copy, then removes every saved run.
	clearDo := func(w http.ResponseWriter, r *http.Request) {
		// The form checks.
		name, ok := readModelForm(w, r, token)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the form checks
		// Everything that is about to go.
		runs := store.all()
		// Keep a copy first; a failure is reported but does not stop the confirmed removal.
		file, copyErr := keepCopy(hist, "", runs, time.Now())
		// Remove everything.
		if err := store.clear(); err != nil {
			// Say why.
			show(w, r, http.StatusInternalServerError, perfPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the clear check
		// Say it is done.
		show(w, r, http.StatusOK, perfPage{Kind: "cleared", Model: name, RemoveCount: len(runs), CopyFile: file, CopyErr: copyErr})
	} // end of clearDo
	// clearOneAsk is the first step of clearing one model's results: it shows what would be lost and changes nothing.
	clearOneAsk := func(w http.ResponseWriter, r *http.Request) {
		// The form checks.
		name, ok := readModelForm(w, r, token)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the form checks
		// How many results this model has.
		n := store.countModel(name)
		// Nothing saved for it.
		if n == 0 {
			// Say so.
			show(w, r, http.StatusOK, perfPage{Kind: "clearonenone", Model: name})
			// Stop here.
			return
		} // end of the empty check
		// Whether a safety copy can be kept.
		plan, bad := removalPlan(hist)
		// Show the question with its consequences.
		show(w, r, http.StatusOK, perfPage{Kind: "clearoneask", Model: name, RemoveCount: n, OtherCount: store.count() - n, Summaries: store.summaries(name, name), InCompare: store.inCompare(name), CopyPlan: plan, CopyPlanBad: bad})
	} // end of clearOneAsk
	// clearOneDo is the second step: it keeps a copy, then removes the results of this model only.
	clearOneDo := func(w http.ResponseWriter, r *http.Request) {
		// The form checks.
		name, ok := readModelForm(w, r, token)
		// A refusal was already sent.
		if !ok {
			// Stop here.
			return
		} // end of the form checks
		// Keep a copy first; a failure is reported but does not stop the confirmed removal.
		file, copyErr := keepCopy(hist, name, store.runsOf(name), time.Now())
		// Remove this model's results.
		n, err := store.removeModel(name)
		// A failure to save.
		if err != nil {
			// Say why.
			show(w, r, http.StatusInternalServerError, perfPage{Kind: "error", Model: name, Detail: err.Error()})
			// Stop here.
			return
		} // end of the remove check
		// Say it is done.
		show(w, r, http.StatusOK, perfPage{Kind: "clearonedone", Model: name, RemoveCount: n, CopyFile: file, CopyErr: copyErr})
	} // end of clearOneDo
	// Hand the six handlers back.
	return start, run, clearAsk, clearDo, clearOneAsk, clearOneDo
} // end of perfHandlers
