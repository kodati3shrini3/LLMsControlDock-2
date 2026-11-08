// Package main tells Go that this test file belongs to the same program as findllm.go.
package main

import (
	"regexp" // import lists the standard-library packages this test file uses.
	// io reads a reply body.
	"io"
	// net/http gives the status codes.
	"net/http"
	// net/url builds the form values.
	"net/url"
	// runtime says which system the test runs on.
	"runtime"
	// strings searches the page text.
	"strings"
	// sync/atomic reads the request counter safely.
	"sync/atomic"
	// testing is Go's built-in test framework.
	"testing"
	// unicode/utf8 counts characters of the help texts.
	"unicode/utf8"
) // end of imports

// TestParamsBillionsAndClasses checks the size labels and the plain-language size classes.
func TestParamsBillionsAndClasses(t *testing.T) {
	// The cases: label, billions, class.
	for _, c := range []struct {
		// label is the page's size label.
		label string
		// want is the expected billions.
		want float64
		// class is the expected class key.
		class string
	}{{"0.6b", 0.6, "tiny"}, {"350m", 0.35, "tiny"}, {"1b", 1, "tiny"}, {"1.7b", 1.7, "small"}, {"4b", 4, "small"}, {"8b", 8, "medium"}, {"14b", 14, "medium"}, {"30b", 30, "large"}, {"70b", 70, "huge"}, {"e4b", 4, "small"}} {
		// Read the label.
		got, ok := paramsBillions(c.label)
		// It must be readable and equal.
		if !ok || got != c.want {
			// Report.
			t.Errorf("paramsBillions(%q) = %v, %v; want %v", c.label, got, ok, c.want)
		} // end of the value check
		// The class.
		if k := paramClassOf(got); k != c.class {
			// Report.
			t.Errorf("class of %q = %q, want %q", c.label, k, c.class)
		} // end of the class check
	} // end of the case loop
	// Unreadable labels are refused, never guessed.
	for _, bad := range []string{"", "b", "x8b", "8x", "latest"} {
		// Read it.
		if _, ok := paramsBillions(bad); ok {
			// Report.
			t.Errorf("paramsBillions(%q) was accepted", bad)
		} // end of the check
	} // end of the bad loop
} // end of TestParamsBillionsAndClasses

// TestContextClasses checks the context lengths and the memory classes, including the boundaries.
func TestContextClasses(t *testing.T) {
	// The cases: text, class.
	for _, c := range []struct {
		// text is the page's context length.
		text string
		// class is the expected class key.
		class string
	}{{"4K", "short"}, {"8K", "medium"}, {"32K", "medium"}, {"40K", "long"}, {"128K", "long"}, {"256K", "verylong"}, {"1M", "verylong"}} {
		// Read it.
		k, ok := contextThousands(c.text)
		// It must be readable.
		if !ok {
			// Report.
			t.Errorf("contextThousands(%q) not readable", c.text)
			// Next.
			continue
		} // end of the read check
		// The class.
		if got := contextClassOf(k); got != c.class {
			// Report.
			t.Errorf("class of %q = %q, want %q", c.text, got, c.class)
		} // end of the class check
	} // end of the case loop
	// Unreadable text is refused.
	for _, bad := range []string{"", "K", "abcK", "12"} {
		// Read it.
		if _, ok := contextThousands(bad); ok {
			// Report.
			t.Errorf("contextThousands(%q) was accepted", bad)
		} // end of the check
	} // end of the bad loop
} // end of TestContextClasses

// TestPullsNumber checks the download counts used for sorting.
func TestPullsNumber(t *testing.T) {
	// The cases.
	for text, want := range map[string]float64{"120.9M": 120.9e6, "3.4K": 3400, "87": 87, "1.2B": 1.2e9, "": 0, "many": 0} {
		// Convert.
		if got := pullsNumber(text); got < want-1 || got > want+1 {
			// Report.
			t.Errorf("pullsNumber(%q) = %v, want %v", text, got, want)
		} // end of the compare
	} // end of the case loop
} // end of TestPullsNumber

// sampleModels is a small invented library list for the filter tests.
func sampleModels() []siteModel {
	// Six models of different kinds.
	return []siteModel{
		// A popular chat model with tools and thinking, three sizes.
		{Name: "alpha", Abilities: []string{"tools", "thinking"}, Sizes: []string{"0.6b", "8b", "70b"}, Pulls: "10M"},
		// A less popular chat model with pictures.
		{Name: "beta", Abilities: []string{"vision"}, Sizes: []string{"7b"}, Pulls: "2M"},
		// A search-and-similarity model without sizes.
		{Name: "gamma", Abilities: []string{"embedding"}, Pulls: "5M"},
		// A cloud model.
		{Name: "delta", Cloud: true, Abilities: []string{"tools"}, Sizes: []string{"7b"}, Pulls: "9M"},
		// A chat model whose size cannot be read.
		{Name: "epsilon", Pulls: "1M"},
		// A tiny chat model.
		{Name: "zeta", Sizes: []string{"350m"}, Pulls: "10M"},
	} // end of the list
} // end of sampleModels

// modelNames lists the model names of a result, in order.
func modelNames(ms []siteModel) string {
	// Collect.
	var out []string
	// Each model.
	for _, m := range ms {
		// Its name.
		out = append(out, m.Name)
	} // end of the loop
	// Joined.
	return strings.Join(out, ",")
} // end of modelNames

// TestFindCandidatesFilters checks the choices the list page can answer.
func TestFindCandidatesFilters(t *testing.T) {
	// The cases: the selection, the expected names in order, the cloud count and the no-size count.
	for _, c := range []struct {
		// name describes the case.
		name string
		// sel is the selection.
		sel findSelection
		// want is the expected names.
		want string
		// cloud and noSize are the expected counts.
		cloud, noSize int
	}{
		// Nothing ticked: everything except cloud, most downloaded first, equal counts by name.
		{"nothing", findSelection{}, "alpha,zeta,gamma,beta,epsilon", 1, 0},
		// Chat and writing leaves out the embedding model.
		{"chat", findSelection{Chat: true}, "alpha,zeta,beta,epsilon", 1, 0},
		// Two abilities must both be present.
		{"two abilities", findSelection{Abilities: map[string]bool{"tools": true, "thinking": true}}, "alpha", 1, 0},
		// A size class: any of the model's sizes in the class is enough; the two models without a readable size (gamma and epsilon) are counted.
		{"tiny", findSelection{Sizes: map[string]bool{"tiny": true}}, "alpha,zeta", 1, 2},
		// Another class.
		{"medium", findSelection{Sizes: map[string]bool{"medium": true}}, "alpha,beta", 1, 2},
		// Embedding on its own.
		{"embedding", findSelection{Abilities: map[string]bool{"embedding": true}}, "gamma", 1, 0},
	} {
		// Run the filter.
		got, noSize, cloud := findCandidates(sampleModels(), c.sel)
		// Compare the names.
		if modelNames(got) != c.want {
			// Report.
			t.Errorf("%s: got %s, want %s", c.name, modelNames(got), c.want)
		} // end of the names check
		// Compare the counts.
		if cloud != c.cloud || noSize != c.noSize {
			// Report.
			t.Errorf("%s: cloud=%d noSize=%d, want %d and %d", c.name, cloud, noSize, c.cloud, c.noSize)
		} // end of the counts check
	} // end of the case loop
} // end of TestFindCandidatesFilters

// TestVersionReason checks why a version does or does not fit.
func TestVersionReason(t *testing.T) {
	// A version of 1.6 GB with a 1M context.
	v := siteTag{Tag: "m:1b", SizeText: "1.6GB", SizeBytes: 1600000000, Context: "1M"}
	// It fits with plenty of room.
	if r := versionReason(v, findSelection{DiskGB: 10, MemGB: 8}); r != "" {
		// Report.
		t.Errorf("should fit, got %q", r)
	} // end of the fit check
	// Too little disk.
	if r := versionReason(v, findSelection{DiskGB: 1.0, MemGB: 8}); !strings.Contains(r, "disk") {
		// Report.
		t.Errorf("disk reason = %q", r)
	} // end of the disk check
	// Too little memory.
	if r := versionReason(v, findSelection{DiskGB: 10, MemGB: 1.0}); !strings.Contains(r, "memory") {
		// Report.
		t.Errorf("memory reason = %q", r)
	} // end of the memory check
	// Unknown figures are not checked at all.
	if r := versionReason(v, findSelection{DiskGB: -1, MemGB: -1}); r != "" {
		// Report.
		t.Errorf("unknown figures should not block, got %q", r)
	} // end of the unknown check
	// A chosen memory class that the version is not in.
	if r := versionReason(v, findSelection{DiskGB: -1, MemGB: -1, Contexts: map[string]bool{"short": true}}); !strings.Contains(r, "context") {
		// Report.
		t.Errorf("context reason = %q", r)
	} // end of the class check
	// A chosen class that it is in.
	if r := versionReason(v, findSelection{DiskGB: -1, MemGB: -1, Contexts: map[string]bool{"verylong": true}}); r != "" {
		// Report.
		t.Errorf("should fit the class, got %q", r)
	} // end of the in-class check
	// A version with no readable context length is left out of a context search, not guessed.
	if r := versionReason(siteTag{Tag: "m:x", SizeBytes: 1}, findSelection{DiskGB: -1, MemGB: -1, Contexts: map[string]bool{"long": true}}); r == "" {
		// Report.
		t.Error("an unknown context length passed a context search")
	} // end of the unknown-context check
} // end of TestVersionReason

// TestParseFindForm checks the typed numbers and the ticks.
func TestParseFindForm(t *testing.T) {
	// A form with ticks and numbers, one with a decimal comma.
	v := url.Values{"ab_chat": {"on"}, "ab_tools": {"on"}, "sz_small": {"on"}, "cx_long": {"on"}, "disk_gb": {"12,5"}, "mem_gb": {""}}
	// Read it.
	sel, problems := parseFindForm(v.Get)
	// No problems.
	if len(problems) != 0 {
		// Report.
		t.Fatalf("problems: %v", problems)
	} // end of the problem check
	// The ticks and numbers.
	if !sel.Chat || !sel.Abilities["tools"] || !sel.Sizes["small"] || !sel.Contexts["long"] || sel.DiskGB != 12.5 || sel.MemGB != -1 {
		// Report.
		t.Errorf("selection = %+v", sel)
	} // end of the value check
	// Bad numbers are problems.
	for _, bad := range []string{"abc", "-3", "1000000", "1e3x"} {
		// Read it.
		_, problems := parseFindForm(url.Values{"disk_gb": {bad}}.Get)
		// One problem.
		if len(problems) != 1 {
			// Report.
			t.Errorf("disk %q: problems = %v", bad, problems)
		} // end of the problem check
	} // end of the bad loop
} // end of TestParseFindForm

// TestFindTipsAreCompleteAndShort checks the help texts follow the same house rules as the rest of the program.
func TestFindTipsAreCompleteAndShort(t *testing.T) {
	// Every bubble of the page has a text.
	for key, heading := range findTipHeadings {
		// Look it up.
		tip, ok := findTexts[heading]
		// It must exist.
		if !ok {
			// Report.
			t.Errorf("no help text for %q (%s)", heading, key)
			// Next.
			continue
		} // end of the lookup check
		// The limits of the other tooltips: plain 130, example 120, decide 100.
		for _, p := range []struct {
			// part names the part.
			part string
			// text is its content.
			text string
			// limit is the longest allowed length.
			limit int
		}{{"Plain", tip.Plain, 130}, {"Example", tip.Example, 120}, {"Decide", tip.Decide, 100}} {
			// Filled.
			if strings.TrimSpace(p.text) == "" {
				// Report.
				t.Errorf("%q: %s is empty", heading, p.part)
			} // end of the empty check
			// Short.
			if n := utf8.RuneCountInString(p.text); n > p.limit {
				// Report.
				t.Errorf("%q: %s is %d characters, the limit is %d", heading, p.part, n, p.limit)
			} // end of the length check
			// No markup characters.
			if strings.ContainsAny(p.text, "<>{}") {
				// Report.
				t.Errorf("%q: %s contains markup characters", heading, p.part)
			} // end of the markup check
		} // end of the part loop
		// The house rule on abbreviations: every one is followed by its full form in brackets.
		all := tip.Plain + " | " + tip.Example + " | " + tip.Decide
		// The abbreviations and their full forms.
		for abbr, full := range map[string]string{"GB": "gigabytes", "GPU": "graphics processing unit", "UTC": "coordinated universal time"} {
			// Every appearance must be an explained one.
			if strings.Count(all, abbr) != strings.Count(all, abbr+" ("+full+")") {
				// Report.
				t.Errorf("%q: %q is not explained every time", heading, abbr)
			} // end of the count check
		} // end of the abbreviation loop
	} // end of the bubble loop
} // end of TestFindTipsAreCompleteAndShort

// TestFreeDiskIsReadable checks the free-space reader on the systems that have one.
func TestFreeDiskIsReadable(t *testing.T) {
	// Only Linux, macOS and Windows have a reader.
	if runtime.GOOS != "linux" && runtime.GOOS != "darwin" && runtime.GOOS != "windows" {
		// Say why.
		t.Skip("no reader on this system")
	} // end of the system check
	// Ask about a temporary folder.
	free, err := osFreeDiskBytes(t.TempDir())
	// It must work and give a positive number.
	if err != nil || free == 0 {
		// Report.
		t.Errorf("osFreeDiskBytes = %d, %v", free, err)
	} // end of the check
} // end of TestFreeDiskIsReadable

// findTestPages are the pages of a fake library: a list with a cloud model, and tags pages.
func findTestPages() map[string]string {
	// The list page: a normal model, a cloud model, an embedding model.
	list := listEntry("alpha", "An invented chat model.", "tools", "0.6b", "8b") + listEntry("cloudy", "Runs far away.", "cloud", "tools", "8b") + listEntry("embedder", "Turns text into numbers.", "embedding")
	// The pages.
	return map[string]string{
		// The list.
		"/library": "<html><ul>" + list + "</ul></html>",
		// The tags of alpha: one small version that fits, one large that does not.
		"/library/alpha/tags": tagEntry("alpha:0.6b", "523MB", "40K") + tagEntry("alpha:8b", "5.2GB", "128K"),
		// The tags of the embedding model.
		"/library/embedder/tags": tagEntry("embedder:latest", "274MB", "2K"),
	} // end of the pages
} // end of findTestPages

// postFind sends the search form with the given values and returns the status and the body.
func postFind(t *testing.T, rig themeRig, v url.Values) (int, string) {
	// Mark this as a helper.
	t.Helper()
	// Send it as the page's own form.
	res := post(t, rig.h, "/findllm/search", v, fromThisPage)
	// Close the body at the end.
	defer res.Body.Close()
	// Read it.
	b, err := io.ReadAll(res.Body)
	// A failure means the test is broken.
	if err != nil {
		// Stop.
		t.Fatalf("read body: %v", err)
	} // end of the read check
	// The result.
	return res.StatusCode, string(b)
} // end of postFind

// TestFindPageShowsTheChoicesAndAsksNothing checks the page before any search.
func TestFindPageShowsTheChoicesAndAsksNothing(t *testing.T) {
	// A fake library; it must not be asked.
	hits := fakeSite(t, findTestPages())
	// The rig.
	rig := newThemeRig(t)
	// Ask for the page.
	status, _, body := get(t, rig.h, http.MethodGet, "/findllm")
	// It must be there.
	if status != http.StatusOK {
		// Report.
		t.Fatalf("status %d", status)
	} // end of the status check
	// The page has what the requirement lists.
	for _, want := range []string{"Find LLM", "Your computer (required)", "Free disk space", "Memory (GB, gigabytes)", "Graphics card", "Always on", "Supported by Ollama", "Can be installed with Ollama", "Chat and writing", "Uses tools", "Understands pictures", "Model size", "Memory of a conversation", `name="token"`, "installs nothing"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report.
			t.Errorf("the page lacks %q", want)
		} // end of the look
	} // end of the loop
	// The two fixed ticks are ticked and cannot be changed.
	if strings.Count(body, `type="checkbox" checked disabled`) != 2 {
		// Report.
		t.Error("the two fixed ticks are not ticked and greyed")
	} // end of the fixed check
	// Chat and writing, and the small and medium sizes, are ticked at the start.
	for _, want := range []string{`name="ab_chat" checked`, `name="sz_small" checked`, `name="sz_medium" checked`} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report.
			t.Errorf("default missing: %s", want)
		} // end of the look
	} // end of the loop
	// No results block, and no request to the library.
	if strings.Contains(body, "<h2>Models found</h2>") || atomic.LoadInt32(hits) != 0 {
		// Report.
		t.Errorf("results shown or library asked before the button (hits=%d)", atomic.LoadInt32(hits))
	} // end of the check
} // end of TestFindPageShowsTheChoicesAndAsksNothing

// TestFindSearchShowsFitAndNoFit checks a whole search against a fake library.
func TestFindSearchShowsFitAndNoFit(t *testing.T) {
	// Start with an empty saved list.
	theListCache = listCache{}
	// Clear it again at the end.
	t.Cleanup(func() { theListCache = listCache{} })
	// A fake library.
	hits := fakeSite(t, findTestPages())
	// The rig.
	rig := newThemeRig(t)
	// Chat and writing, 2 GB of disk, 8 GB of memory.
	status, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"2"}, "mem_gb": {"8"}})
	// It must work.
	if status != http.StatusOK {
		// Report.
		t.Fatalf("status %d: %s", status, body)
	} // end of the status check
	// The model, its official link, the small version that fits with its command, and the large one with the reason.
	for _, want := range []string{"<h2>Models found</h2>", ollamaSite + "/library/alpha", "ollama pull alpha:0.6b", "<strong>Fits:</strong>", "<strong>Does not fit:</strong>", "needs 5.2 GB of disk space; you have 2.0 GB free", "1 model matches your choices", "1 cloud model (it runs on Ollama"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report.
			t.Errorf("the results lack %q", want)
		} // end of the look
	} // end of the loop
	// The cloud model and the embedding model are not listed.
	if strings.Contains(body, ">cloudy<") || strings.Contains(body, ">embedder<") {
		// Report.
		t.Error("a cloud or embedding model was listed")
	} // end of the absence check
	// One list page and one tags page were read.
	if n := atomic.LoadInt32(hits); n != 2 {
		// Report.
		t.Errorf("%d requests, want 2", n)
	} // end of the count check
	// The reading time carries a zone.
	if !strings.Contains(body, "UTC") {
		// Report.
		t.Error("the reading time has no zone")
	} // end of the zone check
} // end of TestFindSearchShowsFitAndNoFit

// TestFindSearchRules checks the refusals: wrong token, bad number, library down.
func TestFindSearchRules(t *testing.T) {
	// Start with an empty saved list.
	theListCache = listCache{}
	// Clear it again at the end.
	t.Cleanup(func() { theListCache = listCache{} })
	// A fake library with no pages at all: every request is a 404.
	hits := fakeSite(t, map[string]string{})
	// The rig.
	rig := newThemeRig(t)
	// A wrong token is refused and nothing is read.
	if status, _ := postFind(t, rig, url.Values{"token": {"wrong"}}); status != http.StatusForbidden {
		// Report.
		t.Errorf("wrong token: status %d", status)
	} // end of the token check
	// A bad number is shown as a problem and nothing is read.
	status, body := postFind(t, rig, url.Values{"token": {rig.token}, "disk_gb": {"lots"}})
	// Bad request, with the problem.
	if status != http.StatusBadRequest || !strings.Contains(body, "Free disk space") {
		// Report.
		t.Errorf("bad number: status %d", status)
	} // end of the number check
	// Nothing reached the library so far.
	if atomic.LoadInt32(hits) != 0 {
		// Report.
		t.Errorf("the library was asked %d times by refused forms", atomic.LoadInt32(hits))
	} // end of the count check
	// The library cannot be read: the reason is shown and no model is listed.
	status, body = postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}})
	// A normal page with a warning.
	if status != http.StatusOK || !strings.Contains(body, "could not be read just now") || strings.Contains(body, "findresult") {
		// Report.
		t.Errorf("library down: status %d", status)
	} // end of the down check
	// A plain GET on the search address is not a route.
	if status, _, _ := get(t, rig.h, http.MethodGet, "/findllm/search"); status == http.StatusOK {
		// Report.
		t.Error("GET /findllm/search was accepted")
	} // end of the GET check
} // end of TestFindSearchRules

// TestHomePageHasTheFindLLMButton checks the entry point.
func TestHomePageHasTheFindLLMButton(t *testing.T) {
	// The rig.
	rig := newThemeRig(t)
	// The home page.
	_, _, body := get(t, rig.h, http.MethodGet, "/")
	// The button (in the Installed models panel, beside Compare tested models) and its tooltip.
	for _, want := range []string{`action="/findllm"`, "Find LLM", "installs nothing"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report.
			t.Errorf("the home page lacks %q", want)
		} // end of the look
	} // end of the loop
} // end of TestHomePageHasTheFindLLMButton

// TestFindSummaryWording checks singular and plural in the sentence above the results.
func TestFindSummaryWording(t *testing.T) {
	// The cases: shown, total, cloud, noSize and the words that must appear.
	for _, c := range []struct {
		// shown, total, cloud and noSize are the inputs.
		shown, total, cloud, noSize int
		// want are the phrases that must appear.
		want []string
	}{
		// One model, nothing left out.
		{1, 1, 0, 0, []string{"1 model matches your choices; all are shown.", "20:36:00 CET (UTC+01:00)"}},
		// Many models, some not shown, cloud and size left out.
		{10, 42, 24, 3, []string{"42 models match your choices; the 10 most downloaded are shown.", "24 cloud models (they run on Ollama's servers", "3 models that show no size were left out"}},
		// None.
		{0, 0, 1, 1, []string{"No model matches your choices.", "1 cloud model (it runs", "1 model that shows no size was left out"}},
	} {
		// Build it.
		got := findSummary(c.shown, c.total, c.cloud, c.noSize, "2026-11-08 20:36:00 CET (UTC+01:00)")
		// Each phrase.
		for _, w := range c.want {
			// Look for it.
			if !strings.Contains(got, w) {
				// Report.
				t.Errorf("summary %q lacks %q", got, w)
			} // end of the look
		} // end of the phrase loop
	} // end of the case loop
} // end of TestFindSummaryWording

// TestFindResultsHaveCopyButtons checks that a version that fits has Copy buttons for its three commands, that a version that does not fit has none, and that the script policy is only on when there is a button.
func TestFindResultsHaveCopyButtons(t *testing.T) {
	// Start with an empty saved list.
	theListCache = listCache{}
	// Clear it again at the end.
	t.Cleanup(func() { theListCache = listCache{} })
	// A fake library.
	fakeSite(t, findTestPages())
	// The rig.
	rig := newThemeRig(t)
	// A search where one version fits and one does not.
	res := post(t, rig.h, "/findllm/search", url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"2"}, "mem_gb": {"8"}}, fromThisPage)
	// Close the body at the end.
	defer res.Body.Close()
	// Read it.
	raw, err := io.ReadAll(res.Body)
	// A failure means the test is broken.
	if err != nil {
		// Stop.
		t.Fatalf("read body: %v", err)
	} // end of the read check
	// The page text.
	body := string(raw)
	// Every button names a command that is on the page, and the five of the fitting version are there.
	buttons := regexp.MustCompile(`<button type="button" class="copybtn" data-target="([a-z0-9-]+)" hidden aria-label="Copy command: [^"]+">`).FindAllStringSubmatch(body, -1)
	// Five commands: local, Docker, Docker name, Kubernetes, Kubernetes pod.
	if len(buttons) != 5 {
		// Stop.
		t.Fatalf("%d copy buttons, want 5", len(buttons))
	} // end of the count check
	// Each target exists exactly once as a command.
	for _, b := range buttons {
		// The command element.
		if strings.Count(body, `<code id="`+b[1]+`">`) != 1 {
			// Report.
			t.Errorf("button %q has no single command to copy", b[1])
		} // end of the target check
	} // end of the loop
	// The three ways of running the pull, for the version that fits.
	for _, want := range []string{">ollama pull alpha:0.6b</code>", ">docker exec &lt;container-name&gt; ollama pull alpha:0.6b</code>", ">kubectl exec -n &lt;namespace&gt; &lt;pod-name&gt; -- ollama pull alpha:0.6b</code>"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report.
			t.Errorf("the results lack %q", want)
		} // end of the look
	} // end of the loop
	// The script once, the status line for screen readers, and a policy that allows this address's scripts only.
	if strings.Count(body, `<script src="/copy.js" defer></script>`) != 1 || strings.Count(body, "<script") != 1 || !strings.Contains(body, `id="copystatus"`) {
		// Report.
		t.Errorf("script or status line missing")
	} // end of the script check
	// The policy.
	if csp := res.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe-inline") || strings.Contains(csp, "unsafe-eval") {
		// Report.
		t.Errorf("policy %q", csp)
	} // end of the policy check
	// A search where nothing fits (no disk space at all) has no button, no script and the strict policy.
	res2 := post(t, rig.h, "/findllm/search", url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"0.1"}, "mem_gb": {"0.1"}}, fromThisPage)
	// Close it at the end.
	defer res2.Body.Close()
	// Read it.
	raw2, _ := io.ReadAll(res2.Body)
	// Nothing to copy.
	if strings.Contains(string(raw2), "copybtn") || strings.Contains(string(raw2), "<script") || strings.Contains(res2.Header.Get("Content-Security-Policy"), "script-src") {
		// Report.
		t.Errorf("a page without a fitting version must carry no copy button, no script and the strict policy")
	} // end of the check
} // end of TestFindResultsHaveCopyButtons
