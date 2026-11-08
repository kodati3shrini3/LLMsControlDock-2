// Package main tells Go that this test file belongs to the same program as findllm.go.
package main

import ( // import lists the standard-library packages this test file uses.
	// encoding/json checks what is saved for a deleted model.
	"encoding/json"
	// html escapes a help text the way the page does.
	"html"
	// io reads a reply body.
	"io"
	// math raises the colour values to a power for the contrast figure.
	"math"
	// net/http gives the status codes.
	"net/http"
	// net/url builds the form values.
	"net/url"
	// os checks and writes the saved copy.
	"os"
	// path/filepath builds the place of the saved copy.
	"path/filepath"
	// regexp finds the copy buttons.
	"regexp"
	// runtime says which system the test runs on.
	"runtime"
	// strconv reads the colour numbers.
	"strconv"
	// strings searches the page text.
	"strings"
	// sync/atomic reads the request counter safely.
	"sync/atomic"
	// testing is Go's built-in test framework.
	"testing"
	// time carries the moment of a reading.
	"time"
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
	// The saved library list goes to a throw-away folder, never to the real data folder.
	isolateFindData(t)
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
	if strings.Contains(body, ">Models found</h2>") || atomic.LoadInt32(hits) != 0 {
		// Report.
		t.Errorf("results shown or library asked before the button (hits=%d)", atomic.LoadInt32(hits))
	} // end of the check
} // end of TestFindPageShowsTheChoicesAndAsksNothing

// TestFindSearchShowsFitAndNoFit checks a whole search against a fake library.
func TestFindSearchShowsFitAndNoFit(t *testing.T) {
	// The saved library list goes to a throw-away folder, never to the real data folder.
	isolateFindData(t)
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
	for _, want := range []string{`<h2 id="found">Models found</h2>`, ollamaSite + "/library/alpha", "ollama pull alpha:0.6b", "<strong>Fits:</strong>", "<strong>Does not fit:</strong>", "needs 5.2 GB of disk space; you have 2.0 GB free", "1 model matches your choices", "1 cloud model (it runs on Ollama"} {
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
	// The saved library list goes to a throw-away folder, never to the real data folder.
	isolateFindData(t)
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
	// The library cannot be read and no copy was saved yet: the reason is shown and no model is listed.
	status, body = postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}})
	// A normal page with a warning.
	if status != http.StatusOK || !strings.Contains(body, "could not be read just now") || !strings.Contains(body, "No saved copy of the list exists yet") || strings.Contains(body, "findresult") {
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
	// The saved library list goes to a throw-away folder, never to the real data folder.
	isolateFindData(t)
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

// isolateFindData sends the data folder to a throw-away folder for one test, and forgets which reading was saved last.
func isolateFindData(t *testing.T) {
	// Mark this as a helper.
	t.Helper()
	// Put the real lookups back at the end.
	saveFolderLookups(t)
	// A new empty folder for this test.
	dir := t.TempDir()
	// The data folder lookup now points there.
	userDataDir = func() (string, error) { return dir, nil }
	// No reading was saved yet.
	copyState.mu.Lock()
	// Forget it.
	copyState.savedAt = time.Time{}
	// Let go.
	copyState.mu.Unlock()
} // end of isolateFindData

// TestOfflineCopyIsSavedAndShown checks that a live search saves the list, and that when ollama.com cannot be reached later the saved copy is shown with its date, a warning, and no versions.
func TestOfflineCopyIsSavedAndShown(t *testing.T) {
	// A throw-away data folder.
	isolateFindData(t)
	// An empty in-memory list.
	theListCache = listCache{}
	// Clear it again at the end.
	t.Cleanup(func() { theListCache = listCache{} })
	// A working fake library.
	fakeSite(t, findTestPages())
	// The rig.
	rig := newThemeRig(t)
	// A live search saves the copy.
	if status, _ := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"50"}, "mem_gb": {"16"}}); status != http.StatusOK {
		// Stop.
		t.Fatalf("live search: status %d", status)
	} // end of the live search
	// The file exists.
	if _, err := os.Stat(filepath.Join(dataRoot(), libraryCopyFolder, libraryCopyName)); err != nil {
		// Stop.
		t.Fatalf("the copy was not saved: %v", err)
	} // end of the file check
	// Now the library is down: forget the in-memory list and answer 404 for everything.
	theListCache = listCache{}
	// The fake library with no pages.
	hits := fakeSite(t, map[string]string{})
	// Search again.
	status, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"50"}, "mem_gb": {"16"}})
	// The page works.
	if status != http.StatusOK {
		// Stop.
		t.Fatalf("offline search: status %d", status)
	} // end of the status check
	// The model comes from the copy, the warning says so, and the date is shown.
	for _, want := range []string{"This is a saved copy of the library list from ", "so it may be out of date", ">alpha<", "details are not available right now"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report.
			t.Errorf("the offline page lacks %q", want)
		} // end of the look
	} // end of the loop
	// No version, no command, no copy button: nothing is guessed.
	for _, bad := range []string{"<code>ollama pull", "<strong>Fits:</strong>", "copybtn", "<script"} {
		// It must be absent.
		if strings.Contains(body, bad) {
			// Report.
			t.Errorf("the offline page has %q", bad)
		} // end of the check
	} // end of the loop
	// Only the list page was tried; the tags pages were not asked for while offline.
	if n := atomic.LoadInt32(hits); n != 1 {
		// Report.
		t.Errorf("%d requests while offline, want 1", n)
	} // end of the count check
} // end of TestOfflineCopyIsSavedAndShown

// TestDamagedCopyIsNeverShown checks that an unreadable or empty saved copy counts as no copy.
func TestDamagedCopyIsNeverShown(t *testing.T) {
	// A throw-away data folder.
	isolateFindData(t)
	// An empty in-memory list.
	theListCache = listCache{}
	// Clear it again at the end.
	t.Cleanup(func() { theListCache = listCache{} })
	// The library is down.
	fakeSite(t, map[string]string{})
	// The rig.
	rig := newThemeRig(t)
	// The folder and a damaged file.
	path := libraryCopyPath()
	// Make the folder.
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		// Stop.
		t.Fatalf("folder: %v", err)
	} // end of the folder check
	// The cases: broken text, an empty list, and a list without a date.
	for _, bad := range []string{"{not json", `{"read_at":"2026-11-08T20:36:00Z","models":[]}`, `{"models":[{"Name":"x"}]}`} {
		// Write it.
		if err := os.WriteFile(path, []byte(bad), 0o600); err != nil {
			// Stop.
			t.Fatalf("write: %v", err)
		} // end of the write check
		// Search.
		status, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}})
		// No model, and the plain reason.
		if status != http.StatusOK || strings.Contains(body, "findresult") || strings.Contains(body, "saved copy of the library list from") || !strings.Contains(body, "could not be read just now") {
			// Report.
			t.Errorf("damaged copy %q was used (status %d)", bad, status)
		} // end of the check
	} // end of the loop
} // end of TestDamagedCopyIsNeverShown

// TestInstalledTags checks the plain-word tags with the user's real models and with missing figures.
func TestInstalledTags(t *testing.T) {
	// The cases come from the real models and from a model with nothing reported.
	for _, c := range []struct {
		// m is the model.
		m installedModel
		// want are the tags in order.
		want []string
	}{
		// 27.4 billion, 128K tokens, pictures.
		{installedModel{Capabilities: []string{"completion", "vision"}, Details: modelDetails{ParameterSize: "27.4B", ContextLength: 131072}}, []string{"Large model", "Long memory", "Pictures"}},
		// 27.3 billion, 256K tokens, pictures, tools, thinking.
		{installedModel{Capabilities: []string{"completion", "vision", "tools", "thinking"}, Details: modelDetails{ParameterSize: "27.3B", ContextLength: 262144}}, []string{"Large model", "Very long memory", "Pictures", "Tools", "Thinking"}},
		// 8 billion, 128K, every ability in the fixed order.
		{installedModel{Capabilities: []string{"completion", "vision", "audio", "tools", "thinking"}, Details: modelDetails{ParameterSize: "8.0B", ContextLength: 131072}}, []string{"Medium model", "Long memory", "Pictures", "Audio", "Tools", "Thinking"}},
		// An embedding model: no ability tag, the group says it.
		{installedModel{Capabilities: []string{"embedding"}, Details: modelDetails{ParameterSize: "1.14B", ContextLength: 262144}}, []string{"Small model", "Very long memory"}},
		// A tiny model with a short memory, written in millions.
		{installedModel{Capabilities: []string{"completion"}, Details: modelDetails{ParameterSize: "350M", ContextLength: 2048}}, []string{"Tiny model", "Short memory"}},
		// Nothing reported: no tag at all, never a guess.
		{installedModel{}, nil},
	} {
		// Work it out.
		got := installedTags(c.m)
		// Compare.
		if strings.Join(got, "|") != strings.Join(c.want, "|") {
			// Report.
			t.Errorf("tags of %+v = %v, want %v", c.m.Details, got, c.want)
		} // end of the comparison
	} // end of the case loop
} // end of TestInstalledTags

// TestHomePageShowsTagsAndTheGroupingHelp checks that the table shows the tags under the names and the help line.
func TestHomePageShowsTagsAndTheGroupingHelp(t *testing.T) {
	// The page with the six real models.
	body := pageFor(t, fullOllama(t, realModels, realPsBody))
	// The tags of one row, the help line and its text.
	for _, want := range []string{`<span class="modeltags">`, `<span class="mtag">Large model</span>`, `<span class="mtag">Very long memory</span>`, `<span class="mtag">Thinking</span>`, "How models are grouped", html.EscapeString(findTexts["How models are grouped"].Plain)} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report.
			t.Errorf("the home page lacks %q", want)
		} // end of the look
	} // end of the loop
	// An embedding row carries no ability tag.
	row := body[strings.Index(body, `<tr data-model="rjmalagon/gte-qwen2-instruct:1.5b-f16"`):]
	// Its heading cell.
	cell := row[:strings.Index(row, "</th>")]
	// No pictures, tools, audio or thinking there.
	for _, no := range []string{">Pictures<", ">Tools<", ">Audio<", ">Thinking<"} {
		// It must be absent.
		if strings.Contains(cell, no) {
			// Report.
			t.Errorf("the embedding row has the tag %q", no)
		} // end of the check
	} // end of the loop
} // end of TestHomePageShowsTagsAndTheGroupingHelp

// TestDeletedTags checks the tags of a deleted model: from what was saved at deletion, otherwise from the saved tests, never from the name.
func TestDeletedTags(t *testing.T) {
	// Saved tests know the size and memory of one model only.
	facts := func(name string) (string, int64, bool) {
		// Only this model was tested.
		if name == "tested:1b" {
			// Its facts.
			return "1.1B", 8192, true
		} // end of the name check
		// Nothing for the others.
		return "", 0, false
	} // end of facts
	// The cases.
	for _, c := range []struct {
		// d is the remembered model.
		d deletedModel
		// want are the tags in order.
		want []string
	}{
		// Saved at deletion by this version: all three kinds of tag.
		{deletedModel{Name: "a:27b", ParameterSize: "27.3B", ContextLength: 262144, Capabilities: []string{"completion", "vision", "tools"}}, []string{"Large model", "Very long memory", "Pictures", "Tools"}},
		// Saved by an earlier version, but tested: size and memory only, no abilities.
		{deletedModel{Name: "tested:1b"}, []string{"Small model", "Medium memory"}},
		// Saved by an earlier version and never tested: nothing, and the name is not used to guess ("135m" is in it).
		{deletedModel{Name: "smollm2:135m"}, nil},
		// What was saved wins over the tests.
		{deletedModel{Name: "tested:1b", ParameterSize: "8.0B", ContextLength: 131072}, []string{"Medium model", "Long memory"}},
	} {
		// Work it out.
		got := deletedTags(c.d, facts)
		// Compare.
		if strings.Join(got, "|") != strings.Join(c.want, "|") {
			// Report.
			t.Errorf("tags of %s = %v, want %v", c.d.Name, got, c.want)
		} // end of the comparison
	} // end of the case loop
	// No tests at all (nil lookup) is the same as nothing known.
	if got := deletedTags(deletedModel{Name: "x:1b"}, nil); got != nil {
		// Report.
		t.Errorf("tags without any facts = %v", got)
	} // end of the nil check
} // end of TestDeletedTags

// TestDeletedModelFileKeepsTheFacts checks that the new facts are saved in the file, and that a file written by an earlier version still loads.
func TestDeletedModelFileKeepsTheFacts(t *testing.T) {
	// Write and read back a model with facts.
	body, err := json.Marshal(deletedModel{Name: "a:27b", ParameterSize: "27.3B", ContextLength: 262144, Capabilities: []string{"completion", "vision"}})
	// A failure means the test is broken.
	if err != nil {
		// Stop.
		t.Fatalf("marshal: %v", err)
	} // end of the marshal check
	// Read it back.
	var back deletedModel
	// Decode.
	if err := json.Unmarshal(body, &back); err != nil || back.ParameterSize != "27.3B" || back.ContextLength != 262144 || len(back.Capabilities) != 2 {
		// Report.
		t.Errorf("facts lost: %+v (%v)", back, err)
	} // end of the read-back check
	// An entry of an earlier version has none of the new keys.
	var old deletedModel
	// Decode it.
	if err := json.Unmarshal([]byte(`{"name":"smollm2:135m","digest":"d","size":271000000,"deleted_at":"2026-10-27T21:37:00Z"}`), &old); err != nil || old.Name != "smollm2:135m" || old.ParameterSize != "" || old.ContextLength != 0 || old.Capabilities != nil {
		// Report.
		t.Errorf("old entry not read cleanly: %+v (%v)", old, err)
	} // end of the old-entry check
	// A model without facts writes none of the new keys.
	plain, _ := json.Marshal(deletedModel{Name: "x:1b"})
	// They must be absent.
	if strings.Contains(string(plain), "parameter_size") || strings.Contains(string(plain), "capabilities") || strings.Contains(string(plain), "context_length") {
		// Report.
		t.Errorf("empty facts were written: %s", plain)
	} // end of the absence check
} // end of TestDeletedModelFileKeepsTheFacts

// TestPerfLastFacts checks that the newest recorded size and memory of a model come from its saved tests.
func TestPerfLastFacts(t *testing.T) {
	// A store with three runs of one model and one of another.
	s := &perfStore{runs: []perfRun{
		// The oldest run has a size and a memory.
		{Model: "m:1b", ParameterSize: "1.0B", ContextLength: 4096},
		// A run of another model.
		{Model: "other:7b", ParameterSize: "7.0B", ContextLength: 32768},
		// A newer run that recorded only the size.
		{Model: "m:1b", ParameterSize: "1.1B"},
	}}
	// The newest size, and the memory from the older run that had it.
	if p, c, ok := s.lastFacts("m:1b"); !ok || p != "1.1B" || c != 4096 {
		// Report.
		t.Errorf("lastFacts = %q, %d, %v", p, c, ok)
	} // end of the check
	// A model with no run.
	if _, _, ok := s.lastFacts("never:1b"); ok {
		// Report.
		t.Error("lastFacts found facts for an untested model")
	} // end of the absence check
} // end of TestPerfLastFacts

// contrastOf gives the WCAG contrast ratio of two colours written as #rrggbb.
func contrastOf(a, b string) float64 {
	// The relative luminance of one colour.
	lum := func(hex string) float64 {
		// The three channels.
		var c [3]float64
		// Read each.
		for i := 0; i < 3; i++ {
			// Two hex digits.
			v, err := strconv.ParseUint(hex[1+2*i:3+2*i], 16, 8)
			// A bad colour means the test is broken.
			if err != nil {
				// Stop with a clear value.
				return -1
			} // end of the parse check
			// Scale to 0..1.
			s := float64(v) / 255
			// The sRGB curve.
			if s <= 0.03928 {
				// The straight part.
				c[i] = s / 12.92
			} else {
				// The curved part.
				c[i] = math.Pow((s+0.055)/1.055, 2.4)
			} // end of the curve
		} // end of the channel loop
		// The weights of the three channels.
		return 0.2126*c[0] + 0.7152*c[1] + 0.0722*c[2]
	} // end of lum
	// The two luminances.
	la, lb := lum(a), lum(b)
	// The lighter one first.
	if la < lb {
		// Swap.
		la, lb = lb, la
	} // end of the swap
	// The ratio.
	return (la + 0.05) / (lb + 0.05)
} // end of contrastOf

// TestIconColours checks that the four icons carry their colour classes, in the table and in the key, and that every icon colour reads at least 4.5:1 on the page and panel backgrounds of both themes.
func TestIconColours(t *testing.T) {
	// The page with the six real models and the key open.
	_, _, body := get(t, handlerFor(t, fullOllama(t, realModels, realPsBody).URL), http.MethodGet, "/?key=open")
	// The classes: Modelfile and parameters buttons, the delete button, and the three key symbols.
	for _, want := range []string{`class="gear gear-file"`, `class="gear gear-params"`, `class="gear gear-delete"`, `class="ico sym-file"`, `class="ico sym-params"`, `class="ico sym-delete"`, `class="tagicon"`} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report.
			t.Errorf("the page lacks %q", want)
		} // end of the look
	} // end of the loop
	// The style sheet.
	_, _, css := get(t, handlerFor(t, fullOllama(t, realModels, realPsBody).URL), http.MethodGet, "/app.css")
	// The page and panel backgrounds: light, then dark.
	bgs := map[string][]string{"light": {"#ffffff", "#f4f6f8"}, "dark": {"#121417", "#1b1f24"}}
	// Each icon colour appears three times: light, dark by system choice, dark by saved choice.
	for _, name := range []string{"icon-tag", "icon-delete", "icon-file", "icon-params"} {
		// Every value written for it.
		vals := regexp.MustCompile(`--`+name+`: (#[0-9a-f]{6});`).FindAllStringSubmatch(css, -1)
		// Three values.
		if len(vals) != 3 {
			// Stop with this one.
			t.Errorf("--%s has %d values, want 3", name, len(vals))
			// Next colour.
			continue
		} // end of the count check
		// The first is light, the other two are dark.
		for i, v := range vals {
			// Which backgrounds apply.
			which := "dark"
			// The first value.
			if i == 0 {
				// Light.
				which = "light"
			} // end of the choice
			// Check against both backgrounds.
			for _, bg := range bgs[which] {
				// The ratio.
				if r := contrastOf(v[1], bg); r < 4.5 {
					// Report.
					t.Errorf("--%s %s on %s (%s theme) has contrast %.2f, want at least 4.5", name, v[1], bg, which, r)
				} // end of the ratio check
			} // end of the background loop
		} // end of the value loop
	} // end of the colour loop
} // end of TestIconColours

// TestFindSearchJumpsToTheAnswer checks that after the button is pressed the browser scrolls to the answer: the form sends to the address with #found, and the answer page (the models found, or the list of problems) has exactly one element with that id.
func TestFindSearchJumpsToTheAnswer(t *testing.T) {
	// The saved library list goes to a throw-away folder, never to the real data folder.
	isolateFindData(t)
	// Start with an empty saved list.
	theListCache = listCache{}
	// Clear it again at the end.
	t.Cleanup(func() { theListCache = listCache{} })
	// A fake library.
	fakeSite(t, findTestPages())
	// The rig.
	rig := newThemeRig(t)
	// The empty form page.
	_, _, form := get(t, rig.h, http.MethodGet, "/findllm")
	// The form must send to the address with the jump mark.
	if !strings.Contains(form, `action="/findllm/search#found"`) {
		// Report.
		t.Error("the form does not send to /findllm/search#found")
	} // end of the form check
	// No answer yet, so nothing to jump to.
	if strings.Count(form, `id="found"`) != 0 {
		// Report.
		t.Error("the empty form page already has the jump target")
	} // end of the empty page check
	// A search that works: the heading Models found is the target.
	_, ok := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"2"}, "mem_gb": {"8"}})
	// Exactly one target, and it is the heading.
	if strings.Count(ok, `id="found"`) != 1 || !strings.Contains(ok, `<h2 id="found">Models found</h2>`) {
		// Report.
		t.Error("the answer page has no single jump target on the Models found heading")
	} // end of the answer check
	// A search with a bad number: the problem box is the target.
	_, bad := postFind(t, rig, url.Values{"token": {rig.token}, "disk_gb": {"lots"}})
	// Exactly one target, and it is the problem box.
	if strings.Count(bad, `id="found"`) != 1 || !strings.Contains(bad, `<div class="warn" id="found" role="alert">`) {
		// Report.
		t.Error("the problem page has no single jump target on the problem box")
	} // end of the problem check
} // end of TestFindSearchJumpsToTheAnswer
