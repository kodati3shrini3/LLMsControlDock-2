// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// net/http gives the status codes.
	"net/http"
	// net/url builds the form values.
	"net/url"
	// path/filepath builds the path of a history file.
	"path/filepath"
	// strings searches the page text.
	"strings"
	// testing is Go's test framework.
	"testing"
	// time gives the time of a saved run.
	"time"
) // end of imports

// cmpRun builds a saved text-model run with the figures of a real test.
func cmpRun(model string, speed, load, bytes float64, gpuAll bool, when time.Time) perfRun {
	// The run.
	r := perfRun{Time: when, Model: model, Kind: "generate", PromptVersion: perfPromptVersion, Runs: 3, AnswerSpeed: speed, PromptSpeed: 1000, ColdLoadSec: load, WarmFirstWordSec: 0.3, WarmTotalSec: 1.1, ModelBytes: int64(bytes)}
	// Fully on the graphics card, or only half.
	if gpuAll {
		// All of it.
		r.GPUBytes = r.ModelBytes
	} else {
		// Half of it.
		r.GPUBytes = r.ModelBytes / 2
	} // end of the memory check
	// Hand it back.
	return r
} // end of cmpRun

// cmpEmbed builds a saved embedding-model run.
func cmpEmbed(model string, secs, load float64, when time.Time) perfRun {
	// The run.
	return perfRun{Time: when, Model: model, Kind: "embedding", PromptVersion: perfPromptVersion, Runs: 3, WarmTotalSec: secs, ColdLoadSec: load, VectorLength: 1536, ModelBytes: 3000000000, GPUBytes: 3000000000}
} // end of cmpEmbed

// TestBuildCompareFigures checks every worked-out column and sentence against figures that can be done by hand.
func TestBuildCompareFigures(t *testing.T) {
	// A fixed time.
	when := time.Date(2026, 10, 25, 18, 4, 0, 0, time.UTC)
	// A quick small model, a slow big model that is partly on the processor and was measured on a busy machine, and two embedding models.
	slow := cmpRun("qwen3.6:27b", 36, 7.03, 18.75e9, false, when)
	// Mark the slow one busy.
	slow.Busy, slow.BusyReason = true, "load 12 on 20 cores"
	// The runs, in no particular order.
	runs := []perfRun{slow, cmpRun("medgemma:latest", 80, 3.67, 3.83e9, true, when), cmpEmbed("emb-slow", 0.2, 2, when), cmpEmbed("emb-fast", 0.04, 1.86, when)}
	// Build the page; only medgemma is installed now.
	p := buildCompare(runs, 0, map[string]bool{"medgemma:latest": true, "emb-fast": true, "emb-slow": true}, true)
	// Two tables.
	if len(p.Tables) != 2 {
		// Stop the test.
		t.Fatalf("%d tables, want 2", len(p.Tables))
	} // end of the table check
	// The text table is sorted by speed: medgemma first.
	text := p.Tables[0]
	// The first row.
	if !strings.HasPrefix(text.Rows[0].Cells[0], "medgemma:latest") || !strings.HasPrefix(text.Rows[1].Cells[0], "qwen3.6:27b") {
		// Report the order.
		t.Errorf("order: %q then %q", text.Rows[0].Cells[0], text.Rows[1].Cells[0])
	} // end of the order check
	// The columns of the text table match its headings.
	for _, r := range text.Rows {
		// One cell for each heading.
		if len(r.Cells) != len(compareTextHeadings) || len(text.Cols) != len(compareTextHeadings) {
			// Report the mismatch.
			t.Fatalf("%d cells, %d columns, %d headings", len(r.Cells), len(text.Cols), len(compareTextHeadings))
		} // end of the length check
	} // end of the loop
	// The worked-out cells of the first row, by column heading.
	want := map[string]string{
		// 80 tokens per second.
		"Answer speed": "80.0 tokens/s",
		// The fastest.
		"Speed vs fastest": "fastest",
		// 80 times 0.75.
		"Words per second": "about 60",
		// 3.83 GB in 3.67 s is 1.04 GB/s.
		"Load speed from disk": "1.0 GB/s",
		// 80 divided by 3.83.
		"Speed per GB of memory": "20.9 tokens/s per GB",
		// All on the graphics card.
		"Processor split": "100% graphics card, 0% processor",
		// A calm machine.
		"Machine busy": "no",
		// The date.
		"Tested on": "2026-10-25 18:04 UTC",
	} // end of the expectations
	// Check the first row.
	for i, h := range compareTextHeadings {
		// A heading with an expectation.
		if w, ok := want[h]; ok && text.Rows[0].Cells[i] != w {
			// Report it.
			t.Errorf("medgemma %q = %q, want %q", h, text.Rows[0].Cells[i], w)
		} // end of the check
	} // end of the loop
	// The worked-out cells of the second row.
	want2 := map[string]string{
		// 80 divided by 36 is 2.2.
		"Speed vs fastest": "2.2× slower",
		// 36 times 0.75.
		"Words per second": "about 27",
		// 18.75 GB in 7.03 s is 2.67 GB/s.
		"Load speed from disk": "2.7 GB/s",
		// 36 divided by 18.75.
		"Speed per GB of memory": "1.9 tokens/s per GB",
		// Half on the graphics card.
		"Processor split": "50% graphics card, 50% processor",
		// Busy, with the reason.
		"Machine busy": "yes: load 12 on 20 cores",
		// Not installed any more.
	} // end of the expectations
	// Check the second row.
	for i, h := range compareTextHeadings {
		// A heading with an expectation.
		if w, ok := want2[h]; ok && text.Rows[1].Cells[i] != w {
			// Report it.
			t.Errorf("qwen %q = %q, want %q", h, text.Rows[1].Cells[i], w)
		} // end of the check
	} // end of the loop
	// The busy row is marked, the calm one is not.
	if !text.Rows[1].Busy || text.Rows[0].Busy {
		// Report it.
		t.Errorf("busy marks wrong")
	} // end of the busy check
	// The model that Ollama no longer has is named as such.
	if !strings.Contains(text.Rows[1].Cells[0], "(no longer installed)") || strings.Contains(text.Rows[0].Cells[0], "no longer") {
		// Report it.
		t.Errorf("installed marks wrong: %q / %q", text.Rows[0].Cells[0], text.Rows[1].Cells[0])
	} // end of the installed check
	// The embedding table is sorted by time: the fast one first, and the slow one is 5.0 times longer.
	emb := p.Tables[1]
	// The order and the comparison.
	if emb.Rows[0].Cells[0] != "emb-fast" || emb.Rows[0].Cells[3] != "fastest" || emb.Rows[1].Cells[3] != "5.0× slower" {
		// Report it.
		t.Errorf("embedding rows: %v / %v", emb.Rows[0].Cells, emb.Rows[1].Cells)
	} // end of the embedding check
	// The sentences read out of the figures.
	all := strings.Join(p.Findings, "\n")
	// Each must be present.
	for _, w := range []string{
		// The fastest writer and the slowest.
		"medgemma:latest writes fastest: 80.0 tokens/s (about 60 words per second). qwen3.6:27b is the slowest at 36.0 tokens/s, 2.2× slower.",
		// The load sentence.
		"medgemma:latest loads quickest (3.67 s from cold); qwen3.6:27b needs 7.03 s.",
		// The memory sentence: the small model is also the thrifty one.
		"medgemma:latest uses the least memory (3.8 GB). It also gives the most speed for its memory (20.9 tokens/s per GB).",
		// The partly-on-processor warning.
		"Not fully on the graphics card (so slower than they could be): qwen3.6:27b.",
		// The embedding sentence.
		"emb-fast embeds fastest (0.040 s). emb-slow needs 0.200 s, 5.0× longer.",
	} {
		// Look for it.
		if !strings.Contains(all, w) {
			// Report the gap.
			t.Errorf("findings lack %q\n%s", w, all)
		} // end of the check
	} // end of the loop
	// The notes warn about the busy test.
	if !strings.Contains(strings.Join(p.Notes, "\n"), "1 of the shown test(s) were made while the machine looked busy") {
		// Report it.
		t.Errorf("no busy note: %v", p.Notes)
	} // end of the note check
} // end of TestBuildCompareFigures

// TestBuildCompareEdges checks the cases with no figures, one model, and an old prompt.
func TestBuildCompareEdges(t *testing.T) {
	// Nothing saved.
	if p := buildCompare(nil, 0, nil, false); !p.Empty || len(p.Tables) != 0 {
		// Report it.
		t.Errorf("empty page wrong: %+v", p)
	} // end of the empty check
	// Nothing usable, but one model left out.
	if p := buildCompare(nil, 2, nil, false); !p.Empty || !strings.Contains(strings.Join(p.Notes, " "), "2 model(s) were tested with an older prompt") {
		// Report it.
		t.Errorf("skipped note missing: %+v", p)
	} // end of the skipped check
	// One text model only.
	p := buildCompare([]perfRun{cmpRun("only:1b", 50, 2, 2e9, true, time.Now())}, 0, nil, false)
	// A sentence asks for another test, and no "no longer installed" mark appears when the list was not read.
	if !strings.Contains(strings.Join(p.Findings, " "), "Only one text model has been tested") || strings.Contains(p.Tables[0].Rows[0].Cells[0], "no longer") {
		// Report it.
		t.Errorf("single-model page wrong: %v / %q", p.Findings, p.Tables[0].Rows[0].Cells[0])
	} // end of the single check
	// A model with no speed figure shows plain words and never divides by zero.
	z := cmpRun("zero:1b", 0, 0, 0, true, time.Now())
	// Build with a normal model next to it.
	p = buildCompare([]perfRun{cmpRun("ok:1b", 50, 2, 2e9, true, time.Now()), z}, 0, nil, false)
	// The zero model is last and its worked-out cells are words.
	row := p.Tables[0].Rows[1]
	// Check the cells.
	for i, h := range compareTextHeadings {
		// The columns that need a speed or a size.
		switch h {
		// These cannot be worked out.
		case "Words per second", "Load speed from disk", "Speed per GB of memory":
			// They say so.
			if row.Cells[i] != "not available" {
				// Report it.
				t.Errorf("zero model %q = %q", h, row.Cells[i])
			} // end of the check
		// The comparison.
		case "Speed vs fastest":
			// It says so.
			if row.Cells[i] != "not comparable" {
				// Report it.
				t.Errorf("zero model %q = %q", h, row.Cells[i])
			} // end of the check
		} // end of the switch
	} // end of the loop
} // end of TestBuildCompareEdges

// TestLatestRuns checks that only the newest run of each model counts, and that an old prompt version is left out.
func TestLatestRuns(t *testing.T) {
	// A store in a temporary folder.
	s := openPerfStore(filepath.Join(t.TempDir(), "performance.json"), "")
	// An old run and a newer run of one model.
	old := cmpRun("a:1b", 10, 1, 1e9, true, time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC))
	// The newer one.
	newer := cmpRun("a:1b", 20, 1, 1e9, true, time.Date(2026, 10, 2, 0, 0, 0, 0, time.UTC))
	// A model whose newest run used another prompt.
	other := cmpRun("b:1b", 30, 1, 1e9, true, time.Date(2026, 10, 3, 0, 0, 0, 0, time.UTC))
	// Another prompt version.
	other.PromptVersion = "v0"
	// Save them.
	for _, r := range []perfRun{old, newer, other} {
		// One run.
		if err := s.add(r); err != nil {
			// Stop the test.
			t.Fatal(err)
		} // end of the error check
	} // end of the loop
	// Ask.
	got, skipped := s.latestRuns(perfPromptVersion)
	// One model counts, one was skipped.
	if len(got) != 1 || got[0].AnswerSpeed != 20 || skipped != 1 {
		// Report it.
		t.Errorf("latestRuns = %+v, skipped %d", got, skipped)
	} // end of the check
	// The number shown on the main page's button is the number of models that would be compared.
	if n := s.testedModels(); n != 1 {
		// Report it.
		t.Errorf("testedModels = %d, want 1", n)
	} // end of the count check
} // end of TestLatestRuns

// TestCompareRoute checks the page through the real handler: saved test runs show up, the form rules hold, and the main page has the icon.
func TestCompareRoute(t *testing.T) {
	// A fake Ollama and a rig.
	f := newPerfFake()
	// Build the rig.
	rig, _ := perfRig(t, f)
	// Before any test the page says so.
	res := post(t, rig.h, "/compare", url.Values{"token": {rig.token}}, fromThisPage)
	// The reply.
	empty := bodyOf(res)
	// It is a page.
	if res.StatusCode != http.StatusOK || !strings.Contains(empty, "No model has been through a performance test yet") {
		// Report it.
		t.Errorf("empty page: %d", res.StatusCode)
	} // end of the empty check
	// Two real tests: a text model and an embedding model.
	perfPost(t, rig, "/performance/run", "chat:1b")
	// The embedding model.
	perfPost(t, rig, "/performance/run", "embed:1b")
	// Ask again.
	res = post(t, rig.h, "/compare", url.Values{"token": {rig.token}}, fromThisPage)
	// The reply.
	body := bodyOf(res)
	// Both tables, the model names, headings with bubbles, and the findings section.
	for _, w := range []string{"Models that write text", "Embedding models", "chat:1b", "embed:1b", ">Speed vs fastest<", ">Load speed from disk<", `id="tip-cmp-t-0"`, `id="tip-cmp-e-0"`, "Only one text model has been tested", "How to read this", "Back to the monitor"} {
		// Look for it.
		if !strings.Contains(body, w) {
			// Report the gap.
			t.Errorf("compare page lacks %q", w)
		} // end of the check
	} // end of the loop
	// No element name appears twice.
	for _, id := range []string{`id="tip-cmp-t-0"`, `id="tip-cmp-e-0"`} {
		// Count it.
		if strings.Count(body, id) != 1 {
			// Report it.
			t.Errorf("%s appears %d times", id, strings.Count(body, id))
		} // end of the count check
	} // end of the loop
	// The page runs no script.
	if strings.Contains(body, "<script") {
		// Report it.
		t.Errorf("the compare page has a script")
	} // end of the script check
	// A wrong token is refused.
	if res := post(t, rig.h, "/compare", url.Values{"token": {"0123456789abcdef0123456789abcdef"}}, fromThisPage); res.StatusCode != http.StatusForbidden {
		// Report it.
		t.Errorf("wrong token = %d", res.StatusCode)
	} // end of the token check
	// A request that did not come from this page is refused.
	if res := post(t, rig.h, "/compare", url.Values{"token": {rig.token}}, map[string]string{"Sec-Fetch-Site": "cross-site"}); res.StatusCode != http.StatusForbidden {
		// Report it.
		t.Errorf("cross-site = %d", res.StatusCode)
	} // end of the origin check
	// A plain GET is not a route.
	if status, _, _ := get(t, rig.h, http.MethodGet, "/compare"); status != http.StatusMethodNotAllowed && status != http.StatusNotFound {
		// Report it.
		t.Errorf("GET /compare = %d", status)
	} // end of the GET check
	// The main page has exactly one compare button, above the table, with the number of tested models and the tip the person asked for.
	_, _, main := get(t, rig.h, http.MethodGet, "/")
	// Count and look.
	if strings.Count(main, `action="/compare"`) != 1 || !strings.Contains(main, "Compare models that have already been through a performance test") || strings.Index(main, `action="/compare"`) > strings.Index(main, `<table class="models">`) || !strings.Contains(main, "Compare tested models (2)") {
		// Report it.
		t.Errorf("main page button wrong (count %d)", strings.Count(main, `action="/compare"`))
	} // end of the icon check
} // end of TestCompareRoute
