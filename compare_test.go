// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// html unescapes the page text before it is compared.
	"html"
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

// cmpBase is the time of the newest test in the examples.
var cmpBase = time.Date(2026, 10, 27, 18, 4, 0, 0, time.UTC)

// okRun builds a saved chat-model run that is fair to compare: the same conditions as its neighbours, only the speed differs.
func okRun(model string, chars float64) perfRun {
	// The run, with figures that can be worked out by hand.
	return perfRun{Time: cmpBase, Model: model, Kind: "generate", OllamaVersion: "0.12.0", PromptVersion: perfPromptVersion, Family: "gemma3", ParameterSize: "4.3B", Quantization: "Q4_K_M", Runs: 3, AnswerSpeed: chars / 5, CharSpeed: chars, PromptSpeed: 1000, ColdLoadSec: 3, WarmFirstWordSec: 0.3, WarmTotalSec: 1.1, TokensOut: perfAnswerTokens, AnswerChars: 320, ModelBytes: 3_800_000_000, GPUBytes: 3_800_000_000, ContextLength: 8192}
} // end of okRun

// embRun builds a saved embedding-model run.
func embRun(model string, secs float64) perfRun {
	// The run.
	return perfRun{Time: cmpBase, Model: model, Kind: "embedding", OllamaVersion: "0.12.0", PromptVersion: perfPromptVersion, ParameterSize: "1.5B", Quantization: "F16", Runs: 3, WarmTotalSec: secs, ColdLoadSec: 2, VectorLength: 1536, ModelBytes: 3_000_000_000, GPUBytes: 3_000_000_000, ContextLength: 8192}
} // end of embRun

// groupOf finds the group with the given title.
func groupOf(t *testing.T, gs []cmpGroup, title string) cmpGroup {
	// Mark this as a helper.
	t.Helper()
	// Look at each group.
	for _, g := range gs {
		// A match.
		if g.Title == title {
			// Found.
			return g
		} // end of the match check
	} // end of the loop
	// A missing group is a test failure.
	t.Fatalf("no group %q in %v", title, groupTitles(gs))
	// Never reached.
	return cmpGroup{}
} // end of groupOf

// groupTitles lists the titles, for messages.
func groupTitles(gs []cmpGroup) []string {
	// The titles.
	var out []string
	// Collect them.
	for _, g := range gs {
		// One title.
		out = append(out, g.Title)
	} // end of the loop
	// The list.
	return out
} // end of groupTitles

// modelOf finds a model of a group by name.
func modelOf(t *testing.T, g cmpGroup, name string) cmpModel {
	// Mark this as a helper.
	t.Helper()
	// Look at each model.
	for _, m := range g.Models {
		// A match.
		if m.Run.Model == name {
			// Found.
			return m
		} // end of the match check
	} // end of the loop
	// A missing model is a test failure.
	t.Fatalf("no model %q in %q", name, g.Title)
	// Never reached.
	return cmpModel{}
} // end of modelOf

// TestParamSizeParsing checks that Ollama's size labels are read in every unit and that nonsense is refused.
func TestParamSizeParsing(t *testing.T) {
	// The cases.
	for _, c := range []struct {
		// The label.
		in string
		// The expected billions.
		want float64
		// Whether it can be read.
		ok bool
	}{
		// Millions.
		{"134.52M", 0.13452, true}, {"360M", 0.36, true},
		// Billions, with and without a fraction and with blanks and small letters.
		{"4.3B", 4.3, true}, {"7B", 7, true}, {" 27.4b ", 27.4, true}, {"8.0B", 8, true},
		// Thousands and trillions.
		{"500K", 0.0005, true}, {"1.8T", 1800, true},
		// Not readable.
		{"", 0, false}, {"B", 0, false}, {"abcB", 0, false}, {"4.3", 0, false}, {"-4B", 0, false}, {"0B", 0, false}, {"4.3X", 0, false},
	} {
		// Read it.
		got, ok := parseParamBillions(c.in)
		// It must match.
		if ok != c.ok || (ok && (got < c.want-1e-9 || got > c.want+1e-9)) {
			// Report it.
			t.Errorf("parseParamBillions(%q) = %v, %v; want %v, %v", c.in, got, ok, c.want, c.ok)
		} // end of the check
	} // end of the loop
} // end of TestParamSizeParsing

// TestSizeClassBoundaries checks every edge between two classes, on both sides.
func TestSizeClassBoundaries(t *testing.T) {
	// The cases: the label and the expected class name.
	for label, want := range map[string]string{
		// Tiny.
		"134.52M": "Tiny (under 1B)", "999M": "Tiny (under 1B)",
		// Small begins at 1B and ends below 5B.
		"1B": "Small (1B to under 5B)", "4.3B": "Small (1B to under 5B)", "4.99B": "Small (1B to under 5B)",
		// Medium.
		"5B": "Medium (5B to under 12B)", "8B": "Medium (5B to under 12B)", "11.9B": "Medium (5B to under 12B)",
		// Large.
		"12B": "Large (12B to under 36B)", "27.4B": "Large (12B to under 36B)", "35.9B": "Large (12B to under 36B)",
		// Extra-large.
		"36B": "Extra-large (36B and over)", "70.6B": "Extra-large (36B and over)",
	} {
		// The class.
		idx, est := classifySize(label, 0)
		// A label gives an exact class.
		if est || idx < 0 || sizeClassNames[idx] != want {
			// Report it.
			t.Errorf("classifySize(%q) = %d, %v; want %q exact", label, idx, est, want)
		} // end of the check
	} // end of the loop
	// Five names for four limits.
	if len(sizeClassNames) != len(sizeLimits)+1 {
		// Report it.
		t.Errorf("%d names for %d limits", len(sizeClassNames), len(sizeLimits))
	} // end of the count check
	// Without a label the memory figure gives a marked estimate; without both nothing is known.
	if idx, est := classifySize("", 3_830_000_000); !est || sizeClassNames[idx] != "Medium (5B to under 12B)" {
		// Report it.
		t.Errorf("estimate = %d, %v", idx, est)
	} // end of the estimate check
	// Nothing known.
	if idx, est := classifySize("not a size", 0); idx != classUnknown || !est {
		// Report it.
		t.Errorf("unknown = %d, %v", idx, est)
	} // end of the unknown check
} // end of TestSizeClassBoundaries

// TestPrecisionOf checks the reading of Ollama's quantization levels.
func TestPrecisionOf(t *testing.T) {
	// The cases.
	for q, want := range map[string]int{"Q4_K_M": 4, "Q8_0": 8, "Q5_K_S": 5, "Q6_K": 6, "Q2_K": 2, "Q3_K_L": 3, "IQ3_XS": 3, "F16": 16, "BF16": 16, "F32": 32, "MXFP4": 4, "NVFP4": 4, "FP8": 8, "q4_k_m": 4, "": 0, "weird": 0, "Q": 0, "QX": 0} {
		// Read it.
		bits, label := precisionOf(q)
		// It must match.
		if bits != want {
			// Report it.
			t.Errorf("precisionOf(%q) bits = %d, want %d (%q)", q, bits, want, label)
		} // end of the check
	} // end of the loop
	// The label names the level.
	if _, l := precisionOf("Q4_K_M"); l != "4-bit (Q4_K_M)" {
		// Report it.
		t.Errorf("label = %q", l)
	} // end of the label check
	// An empty level says so.
	if _, l := precisionOf(""); l != "not reported" {
		// Report it.
		t.Errorf("empty label = %q", l)
	} // end of the empty check
} // end of TestPrecisionOf

// TestRankingInsideAGroup checks that like models are ranked by characters per second, with the right comparison text, headline and order.
func TestRankingInsideAGroup(t *testing.T) {
	// Three models of one class and one set of conditions, given in the wrong order.
	gs := groupRuns([]perfRun{okRun("b:4b", 200), okRun("c:4b", 100), okRun("a:4b", 300)}, nil, false)
	// One group.
	if len(gs) != 1 || gs[0].Title != "Chat · Small (1B to under 5B)" {
		// Stop the test.
		t.Fatalf("groups: %v", groupTitles(gs))
	} // end of the group check
	// The group.
	g := gs[0]
	// The order and the places.
	for i, want := range []string{"a:4b", "b:4b", "c:4b"} {
		// The model at this place.
		m := g.Models[i]
		// It must be the expected one with the expected rank.
		if m.Run.Model != want || m.Rank != i+1 || len(m.Reasons) != 0 {
			// Report it.
			t.Errorf("place %d: %s rank %d reasons %v", i+1, m.Run.Model, m.Rank, m.Reasons)
		} // end of the check
	} // end of the loop
	// Three ranked.
	if g.Ranked != 3 {
		// Report it.
		t.Errorf("ranked = %d", g.Ranked)
	} // end of the count check
	// The headline.
	if want := "a:4b writes fastest in this group (300 characters per second), compared like for like with 2 other models."; g.Headline != want {
		// Report it.
		t.Errorf("headline = %q", g.Headline)
	} // end of the headline check
	// The comparison cells: 300 against 200 is 1.5, against 100 is 3.0.
	for i, want := range []string{"#1, fastest", "#2, 1.5× slower", "#3, 3.0× slower"} {
		// The cell.
		if got := cmpVsFastest(g, g.Models[i]); got != want {
			// Report it.
			t.Errorf("vs fastest %d = %q, want %q", i, got, want)
		} // end of the check
	} // end of the loop
} // end of TestRankingInsideAGroup

// TestEveryConditionKeepsAModelOutOfTheRanking checks each flag alone: the odd model gets exactly that reason and no rank, and the two others are still ranked.
func TestEveryConditionKeepsAModelOutOfTheRanking(t *testing.T) {
	// The cases: a change to one run and the reason it must produce.
	cases := []struct {
		// A name for the message.
		name string
		// The change.
		mutate func(r *perfRun)
		// The text the reason must contain.
		want string
	}{
		// A different precision.
		{"precision", func(r *perfRun) { r.Quantization = "Q8_0" }, "different precision (8-bit; most models here use 4-bit)"},
		// Precision not reported.
		{"precision missing", func(r *perfRun) { r.Quantization = "" }, "precision not reported"},
		// Tested days earlier.
		{"older test", func(r *perfRun) { r.Time = cmpBase.Add(-48 * time.Hour) }, "tested more than 12 hours before the newest test in this group"},
		// Another Ollama version.
		{"version", func(r *perfRun) { r.OllamaVersion = "0.11.0" }, "different Ollama version (0.11.0; most use 0.12.0)"},
		// Another context length.
		{"context", func(r *perfRun) { r.ContextLength = 4096 }, "different context length (4096; most use 8192)"},
		// Part on the processor.
		{"processor split", func(r *perfRun) { r.GPUBytes = r.ModelBytes / 2 }, "part of the model ran on the processor, not only on the graphics card"},
		// A busy machine.
		{"busy", func(r *perfRun) { r.Busy = true }, "the machine looked busy"},
		// Other models loaded.
		{"other models", func(r *perfRun) { r.OtherLoaded = []string{"x:1b"} }, "other models were loaded during the test"},
		// A short answer.
		{"short answer", func(r *perfRun) { r.TokensOut = 40 }, "the answer was shorter than the planned 64 tokens"},
		// No character count.
		{"no characters", func(r *perfRun) { r.CharSpeed = 0 }, "no character count was saved (older test): test the model again"},
	} // end of the cases
	// Go through them.
	for _, c := range cases {
		// The odd run.
		odd := okRun("odd:4b", 250)
		// Apply the change.
		c.mutate(&odd)
		// Two normal runs and the odd one.
		gs := groupRuns([]perfRun{okRun("a:4b", 300), okRun("b:4b", 200), odd}, nil, false)
		// The group.
		g := groupOf(t, gs, "Chat · Small (1B to under 5B)")
		// The odd model.
		m := modelOf(t, g, "odd:4b")
		// It is not ranked and has exactly the expected reason.
		if m.Rank != 0 || len(m.Reasons) != 1 || m.Reasons[0] != c.want {
			// Report it.
			t.Errorf("%s: rank %d reasons %q, want only %q", c.name, m.Rank, m.Reasons, c.want)
		} // end of the odd check
		// The other two are ranked 1 and 2.
		if modelOf(t, g, "a:4b").Rank != 1 || modelOf(t, g, "b:4b").Rank != 2 || g.Ranked != 2 {
			// Report it.
			t.Errorf("%s: the others are not ranked 1 and 2", c.name)
		} // end of the others check
		// The listing order does not depend on the ranking: the same size is listed fastest first, so the odd model of 250 sits between the others unless its speed was changed.
		if c.name != "no characters" && c.name != "short answer" && g.Models[1].Run.Model != "odd:4b" {
			// Report it.
			t.Errorf("%s: order %v", c.name, g.Models[1].Run.Model)
		} // end of the order check
		// The cell says no and why.
		if cell := cmpFair(m, true); !strings.HasPrefix(cell, "⚠ No: ") || !strings.Contains(cell, c.want) {
			// Report it.
			t.Errorf("%s: cell %q", c.name, cell)
		} // end of the cell check
	} // end of the loop
	// The twelve-hour rule has an edge: eleven hours apart is still the same sitting.
	near := okRun("near:4b", 250)
	// Eleven hours earlier.
	near.Time = cmpBase.Add(-11 * time.Hour)
	// Build.
	g := groupRuns([]perfRun{okRun("a:4b", 300), near}, nil, false)[0]
	// Both ranked.
	if g.Ranked != 2 {
		// Report it.
		t.Errorf("11 hours apart: ranked %d, want 2", g.Ranked)
	} // end of the edge check
	// And thirteen is not.
	near.Time = cmpBase.Add(-13 * time.Hour)
	// Build.
	g = groupRuns([]perfRun{okRun("a:4b", 300), near}, nil, false)[0]
	// Nobody is ranked: one model is left.
	if g.Ranked != 0 {
		// Report it.
		t.Errorf("13 hours apart: ranked %d, want 0", g.Ranked)
	} // end of the second edge check
} // end of TestEveryConditionKeepsAModelOutOfTheRanking

// TestNoRankingWithFewerThanTwoFairModels checks the explanation when only one model of a group can be compared.
func TestNoRankingWithFewerThanTwoFairModels(t *testing.T) {
	// One normal model and one that ran on the processor.
	odd := okRun("odd:4b", 250)
	// The split.
	odd.GPUBytes = odd.ModelBytes / 2
	// Build.
	gs := groupRuns([]perfRun{okRun("a:4b", 300), odd}, nil, false)
	// The group.
	g := gs[0]
	// Nobody has a rank and there is no headline.
	if g.Ranked != 0 || g.Headline != "" || g.Models[0].Rank != 0 || g.Models[1].Rank != 0 {
		// Report it.
		t.Errorf("ranked %d headline %q", g.Ranked, g.Headline)
	} // end of the check
	// The note explains.
	if len(g.Notes) != 1 || !strings.HasPrefix(g.Notes[0], "No ranking: fewer than two models") {
		// Report it.
		t.Errorf("notes %v", g.Notes)
	} // end of the note check
	// The page says the same in its findings.
	p := buildCompare([]perfRun{okRun("a:4b", 300), odd}, 0, nil, false)
	// The sentence.
	if !strings.Contains(strings.Join(p.Findings, "\n"), "Chat · Small (1B to under 5B): no ranking yet, because fewer than two models can be compared like for like.") {
		// Report it.
		t.Errorf("findings %v", p.Findings)
	} // end of the findings check
} // end of TestNoRankingWithFewerThanTwoFairModels

// TestGroupsBySizeAndKind checks that models land in the right groups, in order, and that every run is in exactly one group.
func TestGroupsBySizeAndKind(t *testing.T) {
	// A tiny, a small, a large and an extra-large chat model, two embedding models, and three that cannot be classified exactly.
	tiny := okRun("tiny:135m", 900)
	// Its size.
	tiny.ParameterSize = "134.52M"
	// A large model.
	large := okRun("large:27b", 90)
	// Its size.
	large.ParameterSize = "27.4B"
	// An extra-large model.
	huge := okRun("huge:70b", 30)
	// Its size.
	huge.ParameterSize = "70.6B"
	// A model with no label but a memory figure: estimated.
	guess := okRun("guess:x", 100)
	// No label.
	guess.ParameterSize = ""
	// A model with nothing at all.
	blank := okRun("blank:x", 100)
	// No label and no memory.
	blank.ParameterSize, blank.ModelBytes, blank.GPUBytes = "", 0, 0
	// The runs.
	runs := []perfRun{okRun("small:4b", 200), embRun("emb-b", 0.2), huge, tiny, blank, large, embRun("emb-a", 0.04), guess}
	// Group them.
	gs := groupRuns(runs, nil, false)
	// The order, largest first: extra-large, large, medium (the guess), small, tiny, then unknown, then embedding.
	want := []string{"Chat · Extra-large (36B and over)", "Chat · Large (12B to under 36B)", "Chat · Medium (5B to under 12B)", "Chat · Small (1B to under 5B)", "Chat · Tiny (under 1B)", "Chat · size not known", "Embedding models"}
	// Compare.
	if got := groupTitles(gs); strings.Join(got, "|") != strings.Join(want, "|") {
		// Stop the test.
		t.Fatalf("groups = %v\nwant     %v", got, want)
	} // end of the order check
	// Every run is in exactly one group: no orphans.
	total := 0
	// Count them.
	for _, g := range gs {
		// The members.
		total += len(g.Models)
	} // end of the loop
	// It must equal the number of runs.
	if total != len(runs) {
		// Report it.
		t.Errorf("%d models in groups, %d runs", total, len(runs))
	} // end of the orphan check
	// The estimated model says so and is not ranked.
	m := modelOf(t, groupOf(t, gs, "Chat · Medium (5B to under 12B)"), "guess:x")
	// Its reasons and note.
	if m.Rank != 0 || !strings.Contains(strings.Join(m.Reasons, ";"), "size class only estimated from memory use") || !strings.Contains(m.Params, "class estimated from memory use") {
		// Report it.
		t.Errorf("estimated model: %+v", m)
	} // end of the estimate check
	// The unknown model says so.
	u := modelOf(t, groupOf(t, gs, "Chat · size not known"), "blank:x")
	// Its reasons.
	if !strings.Contains(strings.Join(u.Reasons, ";"), "size class unknown") || u.Params != "not reported" {
		// Report it.
		t.Errorf("unknown model: %+v", u)
	} // end of the unknown check
	// The embedding group is ranked by time, shortest first, and says "embeds fastest".
	e := groupOf(t, gs, "Embedding models")
	// The order and the text.
	if e.Models[0].Run.Model != "emb-a" || e.Models[0].Rank != 1 || e.Models[1].Rank != 2 || e.Headline != "emb-a embeds fastest in this group (0.040 s), compared like for like with 1 other model." {
		// Report it.
		t.Errorf("embedding group: %v / %q", e.Models[0].Run.Model, e.Headline)
	} // end of the embedding check
	// The comparison cell of the slow embedder: 0.2 against 0.04 is 5.0.
	if got := cmpVsFastest(e, e.Models[1]); got != "#2, 5.0× slower" {
		// Report it.
		t.Errorf("embedding vs fastest = %q", got)
	} // end of the cell check
} // end of TestGroupsBySizeAndKind

// TestSingleModelGroupsNameTheirNeighbour checks the note of a model that has no peer.
func TestSingleModelGroupsNameTheirNeighbour(t *testing.T) {
	// A tiny model alone, and a small group of two.
	tiny := okRun("tiny:135m", 900)
	// Its size.
	tiny.ParameterSize = "134.52M"
	// A large model alone.
	large := okRun("large:27b", 90)
	// Its size.
	large.ParameterSize = "27.4B"
	// Group them.
	gs := groupRuns([]perfRun{tiny, okRun("a:4b", 300), okRun("b:4b", 200), large}, nil, false)
	// The tiny group's note names the small group, which is the nearest.
	tg := groupOf(t, gs, "Chat · Tiny (under 1B)")
	// The note.
	if len(tg.Notes) != 1 || !strings.Contains(tg.Notes[0], "Only model in this group") || !strings.Contains(tg.Notes[0], `The nearest group is "Chat · Small (1B to under 5B)"`) || !strings.Contains(tg.Notes[0], "not ranked against each other") {
		// Report it.
		t.Errorf("tiny note: %v", tg.Notes)
	} // end of the tiny check
	// The large group's nearest is the small group (two classes away; the tiny group is three away).
	lg := groupOf(t, gs, "Chat · Large (12B to under 36B)")
	// The note.
	if len(lg.Notes) != 1 || !strings.Contains(lg.Notes[0], `"Chat · Small (1B to under 5B)"`) {
		// Report it.
		t.Errorf("large note: %v", lg.Notes)
	} // end of the large check
	// A lone model with no other chat group has no neighbour sentence.
	only := groupRuns([]perfRun{okRun("a:4b", 300)}, nil, false)[0]
	// The note.
	if len(only.Notes) != 1 || strings.Contains(only.Notes[0], "nearest") {
		// Report it.
		t.Errorf("only note: %v", only.Notes)
	} // end of the only check
	// The page says there is nothing to rank yet.
	p := buildCompare([]perfRun{okRun("a:4b", 300)}, 0, nil, false)
	// The sentence.
	if !strings.Contains(strings.Join(p.Findings, "\n"), "only one model, so there is nothing to rank yet.") {
		// Report it.
		t.Errorf("findings %v", p.Findings)
	} // end of the sentence check
} // end of TestSingleModelGroupsNameTheirNeighbour

// TestDetailsComeFromTheTestFirstThenFromOllama checks which source wins for the size and the precision.
func TestDetailsComeFromTheTestFirstThenFromOllama(t *testing.T) {
	// A run that saved its details, and one that did not.
	saved := okRun("saved:x", 100)
	// The old run has none.
	old := okRun("old:x", 100)
	// Clear them.
	old.ParameterSize, old.Quantization, old.Family = "", "", ""
	// What Ollama says now about both.
	now := map[string]modelDetails{"saved:x": {ParameterSize: "27B", QuantizationLevel: "Q8_0", Family: "other"}, "old:x": {ParameterSize: "8B", QuantizationLevel: "Q5_K_M", Family: "llama"}}
	// The saved details win.
	if d := resolveDetails(saved, now); d.ParameterSize != "4.3B" || d.QuantizationLevel != "Q4_K_M" || d.Family != "gemma3" {
		// Report it.
		t.Errorf("saved wins: %+v", d)
	} // end of the saved check
	// The live details fill the gaps.
	if d := resolveDetails(old, now); d.ParameterSize != "8B" || d.QuantizationLevel != "Q5_K_M" || d.Family != "llama" {
		// Report it.
		t.Errorf("live fills: %+v", d)
	} // end of the live check
	// A model that is gone and saved nothing has nothing.
	if d := resolveDetails(old, nil); d.ParameterSize != "" || d.QuantizationLevel != "" {
		// Report it.
		t.Errorf("nothing: %+v", d)
	} // end of the nothing check
	// The group of the old run is the Medium class because Ollama says 8B, and it is not an estimate.
	gs := groupRuns([]perfRun{old}, now, true)
	// The class.
	if gs[0].Title != "Chat · Medium (5B to under 12B)" || gs[0].Models[0].ClassEstimated {
		// Report it.
		t.Errorf("group %q estimated %v", gs[0].Title, gs[0].Models[0].ClassEstimated)
	} // end of the class check
	// A model that Ollama no longer has is named as such (only when the list was read).
	gone := groupRuns([]perfRun{okRun("gone:4b", 100)}, map[string]modelDetails{}, true)
	// The name.
	if !strings.HasSuffix(gone[0].Models[0].Name, "(no longer installed)") {
		// Report it.
		t.Errorf("name %q", gone[0].Models[0].Name)
	} // end of the name check
	// And not when the list could not be read.
	unread := groupRuns([]perfRun{okRun("gone:4b", 100)}, nil, false)
	// The name.
	if strings.Contains(unread[0].Models[0].Name, "no longer") {
		// Report it.
		t.Errorf("name %q", unread[0].Models[0].Name)
	} // end of the second name check
} // end of TestDetailsComeFromTheTestFirstThenFromOllama

// TestCompareCellsMatchTheHeadings checks every cell against its heading with figures that can be worked out by hand.
func TestCompareCellsMatchTheHeadings(t *testing.T) {
	// A chat group of two and an embedding group of two.
	p := buildCompare([]perfRun{okRun("a:4b", 300), okRun("b:4b", 200), embRun("emb-a", 0.04), embRun("emb-b", 0.2)}, 0, map[string]modelDetails{"a:4b": {}, "b:4b": {}, "emb-a": {}, "emb-b": {}}, true)
	// Two groups.
	if len(p.Groups) != 2 {
		// Stop the test.
		t.Fatalf("%d groups", len(p.Groups))
	} // end of the count check
	// The chat group's cells by heading.
	chat := p.Groups[0]
	// One cell for each heading, and the headings are the declared ones.
	for _, r := range chat.Rows {
		// The lengths.
		if len(r.Cells) != len(compareTextHeadings) || len(chat.Cols) != len(compareTextHeadings) {
			// Stop the test.
			t.Fatalf("%d cells, %d columns, %d headings", len(r.Cells), len(chat.Cols), len(compareTextHeadings))
		} // end of the length check
	} // end of the loop
	// The expected cells of the first row.
	want := map[string]string{
		// The name.
		"Model": "a:4b",
		// The size label.
		"Parameters": "4.3B",
		// The precision.
		"Quantization": "4-bit (Q4_K_M)",
		// The date.
		"Tested on": "2026-10-27 18:04 UTC",
		// 300 divided by 5 is 60.
		"Answer speed": "60.0 tokens/s",
		// The characters.
		"Characters per second": "300 chars/s",
		// The place.
		"Speed vs fastest": "#1, fastest",
		// 3.8 GB in 3 s is 1.27 GB/s.
		"Load speed from disk": "1.3 GB/s",
		// All on the graphics card.
		"Processor split": "100% graphics card, 0% processor",
		// A calm machine.
		"Machine busy": "no",
		// Fair.
		"Fair to rank?": "✓ Yes",
	} // end of the expectations
	// Check them.
	for i, h := range compareTextHeadings {
		// The heading must match the bubble.
		if chat.Cols[i].Title != h {
			// Report it.
			t.Errorf("column %d is %q, want %q", i, chat.Cols[i].Title, h)
		} // end of the title check
		// A heading with an expectation.
		if w, ok := want[h]; ok && chat.Rows[0].Cells[i] != w {
			// Report it.
			t.Errorf("%q = %q, want %q", h, chat.Rows[0].Cells[i], w)
		} // end of the cell check
	} // end of the loop
	// The embedding group has its own headings.
	emb := p.Groups[1]
	// The lengths.
	for _, r := range emb.Rows {
		// One cell for each heading.
		if len(r.Cells) != len(compareEmbedHeadings) || len(emb.Cols) != len(compareEmbedHeadings) {
			// Stop the test.
			t.Fatalf("%d cells, %d columns, %d headings", len(r.Cells), len(emb.Cols), len(compareEmbedHeadings))
		} // end of the length check
	} // end of the loop
	// The slow embedder's cells.
	slow := map[string]string{"Embedding time": "0.200 s", "Speed vs fastest": "#2, 5.0× slower", "Vector length": "1536 numbers", "Quantization": "16-bit (F16)", "Fair to rank?": "✓ Yes"}
	// Check them.
	for i, h := range compareEmbedHeadings {
		// A heading with an expectation.
		if w, ok := slow[h]; ok && emb.Rows[1].Cells[i] != w {
			// Report it.
			t.Errorf("embedding %q = %q, want %q", h, emb.Rows[1].Cells[i], w)
		} // end of the cell check
	} // end of the loop
	// The tooltips of the headings are unique on the page.
	seen := map[string]bool{}
	// Go through all of them.
	for _, g := range p.Groups {
		// Every column.
		for _, c := range g.Cols {
			// A repeat.
			if seen[c.ID] {
				// Report it.
				t.Errorf("element name %s appears twice", c.ID)
			} // end of the repeat check
			// Remember it.
			seen[c.ID] = true
		} // end of the column loop
	} // end of the group loop
} // end of TestCompareCellsMatchTheHeadings

// TestBuildCompareEdges checks the cases with no figures and with an old prompt.
func TestBuildCompareEdges(t *testing.T) {
	// Nothing saved: the page still carries the notice.
	p := buildCompare(nil, 0, nil, false)
	// Empty, no groups, and the notice.
	if !p.Empty || len(p.Groups) != 0 || p.NoticeShort != noticeShort || len(p.NoticeFull) != len(noticeFull) {
		// Report it.
		t.Errorf("empty page wrong: %+v", p)
	} // end of the empty check
	// Nothing usable, but two models left out.
	if p := buildCompare(nil, 2, nil, false); !p.Empty || !strings.Contains(strings.Join(p.Notes, " "), "2 model(s) were tested with an older prompt") {
		// Report it.
		t.Errorf("skipped note missing: %+v", p)
	} // end of the skipped check
	// A busy run gives a caution.
	busy := okRun("a:4b", 100)
	// Busy.
	busy.Busy = true
	// Build.
	if p := buildCompare([]perfRun{busy}, 1, nil, false); !strings.Contains(strings.Join(p.Notes, "\n"), "1 of the shown test(s) were made while the machine looked busy") || !strings.Contains(strings.Join(p.Notes, "\n"), "1 model(s) were tested with an older prompt version and are left out") {
		// Report it.
		t.Errorf("notes: %v", p.Notes)
	} // end of the busy check
	// A run with no figures at all shows words and never divides by zero.
	zero := perfRun{Time: cmpBase, Model: "zero:x", Kind: "generate", PromptVersion: perfPromptVersion}
	// Build next to a normal one.
	p = buildCompare([]perfRun{okRun("ok:4b", 100), zero}, 0, nil, false)
	// Find the zero model's row.
	var row cmpRow
	// Go through the groups.
	for _, g := range p.Groups {
		// Every row.
		for _, r := range g.Rows {
			// The zero model.
			if strings.HasPrefix(r.Cells[0], "zero:x") {
				// Keep it.
				row = r
			} // end of the match check
		} // end of the row loop
	} // end of the group loop
	// It exists, is not ranked, and its figures are words.
	if len(row.Cells) == 0 {
		// Stop the test.
		t.Fatalf("no row for the zero model")
	} // end of the existence check
	// The cells.
	for i, h := range compareTextHeadings {
		// The columns that need a figure.
		switch h {
		// These cannot be worked out.
		case "Load speed from disk":
			// They say so.
			if row.Cells[i] != "not available" {
				// Report it.
				t.Errorf("zero model %q = %q", h, row.Cells[i])
			} // end of the check
		// The characters.
		case "Characters per second":
			// They say so.
			if row.Cells[i] != "not saved (older test)" {
				// Report it.
				t.Errorf("zero model %q = %q", h, row.Cells[i])
			} // end of the check
		// The place.
		case "Speed vs fastest":
			// Not ranked.
			if row.Cells[i] != "not ranked" {
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
	old := okRun("a:1b", 10)
	// Its time.
	old.Time = time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	// The newer one.
	newer := okRun("a:1b", 20)
	// Its time.
	newer.Time = time.Date(2026, 10, 2, 0, 0, 0, 0, time.UTC)
	// A model whose newest run used another prompt.
	other := okRun("b:1b", 30)
	// Its time.
	other.Time = time.Date(2026, 10, 3, 0, 0, 0, 0, time.UTC)
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
	if len(got) != 1 || got[0].CharSpeed != 20 || skipped != 1 {
		// Report it.
		t.Errorf("latestRuns = %+v, skipped %d", got, skipped)
	} // end of the check
	// The number shown on the main page's button is the number of models that would be compared.
	if n := s.testedModels(); n != 1 {
		// Report it.
		t.Errorf("testedModels = %d, want 1", n)
	} // end of the count check
} // end of TestLatestRuns

// TestCompareRoute checks the page through the real handler: groups, flags, method, references, notice and downloads show up, the form rules hold, and the main page has the button.
func TestCompareRoute(t *testing.T) {
	// A fake Ollama and a rig.
	f := newPerfFake()
	// Build the rig.
	rig, _ := perfRig(t, f)
	// Before any test the page says so, and still carries the notice.
	res := post(t, rig.h, "/compare", url.Values{"token": {rig.token}}, fromThisPage)
	// The reply.
	empty := bodyOf(res)
	// It is a page.
	if res.StatusCode != http.StatusOK || !strings.Contains(empty, "No model has been through a performance test yet") || !strings.Contains(html.UnescapeString(empty), noticeShort) {
		// Report it.
		t.Errorf("empty page: %d", res.StatusCode)
	} // end of the empty check
	// No download buttons without results.
	if strings.Contains(empty, `action="/compare/pdf"`) {
		// Report it.
		t.Errorf("download button on an empty page")
	} // end of the button check
	// Two real tests: a text model and an embedding model.
	perfPost(t, rig, "/performance/run", "chat:1b")
	// The embedding model.
	perfPost(t, rig, "/performance/run", "embed:1b")
	// Ask again.
	res = post(t, rig.h, "/compare", url.Values{"token": {rig.token}}, fromThisPage)
	// The reply.
	raw := bodyOf(res)
	// The text as a person reads it.
	body := html.UnescapeString(raw)
	// The parts of the page.
	for _, w := range []string{"Compare models", "Important notice.", noticeShort, "Read the full notice", `action="/compare/pdf"`, `action="/compare/csv"`, "Save this comparison as PDF", "Save the data as CSV", "What the figures say", "Chat · Small (1B to under 5B)", "Embedding models", "Why this group:", "chat:1b", "embed:1b", ">Fair to rank?<", ">Characters per second<", "How to read this", "How and why this comparison was done", "References", noticeTitle, "Back to the monitor", referencesChecked} {
		// Look for it.
		if !strings.Contains(body, w) {
			// Report the gap.
			t.Errorf("compare page lacks %q", w)
		} // end of the check
	} // end of the loop
	// Every method answer, every reference address and the whole notice are on the page.
	for _, h := range howRows() {
		// The question and the answer.
		if !strings.Contains(body, h.Question) || !strings.Contains(body, h.Answer) {
			// Report it.
			t.Errorf("method row missing: %q", h.Question)
		} // end of the check
	} // end of the method loop
	// The references.
	for _, r := range compareReferences {
		// The title, the address and the sentence of use.
		for _, w := range []string{r.Title, r.URL, r.Used} {
			// Look for it.
			if !strings.Contains(body, w) {
				// Report it.
				t.Errorf("reference %d lacks %q", r.N, w)
			} // end of the check
		} // end of the part loop
	} // end of the reference loop
	// The notice.
	for _, para := range noticeFull {
		// The paragraph.
		if !strings.Contains(body, para) {
			// Report it.
			t.Errorf("notice paragraph missing: %.40s", para)
		} // end of the check
	} // end of the notice loop
	// Every reference link opens in a new window and says so for screen readers.
	if n := strings.Count(raw, `rel="noopener noreferrer">`+"https://"); n != len(compareReferences) {
		// Report it.
		t.Errorf("%d safe reference links, want %d", n, len(compareReferences))
	} // end of the link count
	// The words for screen readers.
	if n := strings.Count(raw, "(opens in a new window)"); n != len(compareReferences) {
		// Report it.
		t.Errorf("%d new-window notes, want %d", n, len(compareReferences))
	} // end of the screen-reader count
	// The notice is first: before the first group.
	if strings.Index(body, "Important notice.") > strings.Index(body, "Chat · Small") {
		// Report it.
		t.Errorf("the notice is not above the first group")
	} // end of the order check
	// No element name appears twice.
	for _, id := range []string{`id="tip-cmp-t0-0"`, `id="tip-cmp-e1-0"`} {
		// Count it.
		if strings.Count(raw, id) != 1 {
			// Report it.
			t.Errorf("%s appears %d times", id, strings.Count(raw, id))
		} // end of the count check
	} // end of the loop
	// The page runs no script.
	if strings.Contains(raw, "<script") {
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

// TestModelsAreListedLargestFirst checks that inside a group the larger model comes first whatever the speed, that equal sizes go fastest first, and that the headline still names the fastest ranked model.
func TestModelsAreListedLargestFirst(t *testing.T) {
	// Three models of the Small class with different sizes; the smallest is the fastest.
	big := okRun("big:4b", 100)
	// Its size.
	big.ParameterSize = "4.9B"
	// A middle model.
	mid := okRun("mid:3b", 150)
	// Its size.
	mid.ParameterSize = "3.2B"
	// The smallest and fastest.
	low := okRun("low:2b", 400)
	// Its size.
	low.ParameterSize = "1.5B"
	// A model of the same size as mid but faster.
	twin := okRun("twin:3b", 180)
	// Its size.
	twin.ParameterSize = "3.2B"
	// Group them.
	gs := groupRuns([]perfRun{low, mid, big, twin}, nil, false)
	// The group.
	g := groupOf(t, gs, "Chat · Small (1B to under 5B)")
	// The names in listed order.
	var got []string
	// Collect them.
	for _, m := range g.Models {
		// One name.
		got = append(got, m.Run.Model)
	} // end of the loop
	// Largest first; the twins fastest first.
	if strings.Join(got, ",") != "big:4b,twin:3b,mid:3b,low:2b" {
		// Report it.
		t.Errorf("order %v", got)
	} // end of the order check
	// The fastest is named in the headline although it is listed last.
	if !strings.HasPrefix(g.Headline, "low:2b writes fastest") {
		// Report it.
		t.Errorf("headline %q", g.Headline)
	} // end of the headline check
	// The cells agree: the listed-first model is the slowest.
	if cell := cmpVsFastest(g, g.Models[0]); !strings.HasPrefix(cell, "#4, 4.0× slower") {
		// Report it.
		t.Errorf("cell %q", cell)
	} // end of the cell check
} // end of TestModelsAreListedLargestFirst
