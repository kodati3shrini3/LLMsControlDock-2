// Package main tells Go that this test file belongs to the same program as findllm.go.
package main

import ( // import lists the standard-library packages this test file uses.
	// encoding/json checks what is saved for a deleted model.
	"encoding/json"
	// fmt formats the mixed colour of the highlight test.
	"fmt"
	// html escapes a help text the way the page does.
	"html"
	// io reads a reply body.
	"io"
	// math raises the colour values to a power for the contrast figure.
	"math"
	// net/http gives the status codes.
	"net/http"
	// net/http/httptest starts the fake Ollama the new tests supply.
	"net/http/httptest"
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
		{Name: "delta", Cloud: true, Abilities: []string{"tools"}, Pulls: "9M"},
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
	list := listEntry("alpha", "An invented chat model.", "tools", "0.6b", "8b") + listEntry("cloudy", "Runs far away.", "cloud", "tools") + listEntry("embedder", "Turns text into numbers.", "embedding")
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
	for _, want := range []string{`<h2 id="found">Models found</h2>`, ollamaSite + "/library/alpha", "ollama pull alpha:0.6b", "<strong>Fits:</strong>", "<strong>Does not fit:</strong>", "needs 5.2 GB of disk space; you have 2.0 GB free", "1 model matches your choices", `<h2 id="cloudmodels" class="cloudhead">`, tipCloud, tipVersionFits, tipVersionNoFit, tipModelFits} {
		// Look for it in the page text with the character codes turned back into characters (the apostrophe is written as a code).
		if !strings.Contains(html.UnescapeString(body), want) {
			// Report.
			t.Errorf("the results lack %q", want)
		} // end of the look
	} // end of the loop
	// The embedding model is not listed at all.
	if strings.Contains(body, ">embedder<") {
		// Report.
		t.Error("the embedding model was listed")
	} // end of the embedding check
	// The cloud-only model is listed, but only in the cloud section (after its heading), and has no download command.
	if at, cloudAt := strings.Index(body, ">cloudy"), strings.Index(body, `<h2 id="cloudmodels" class="cloudhead">`); at < 0 || cloudAt < 0 || at < cloudAt || strings.Contains(body, "ollama pull cloudy") {
		// Report.
		t.Error("the cloud-only model is missing from the cloud section, or has a download command")
	} // end of the cloud check
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
	for _, want := range []string{`class="gear gear-file"`, `class="gear gear-params"`, `class="gear gear-delete"`, `class="ico sym-file"`, `class="ico sym-params"`, `class="ico sym-delete"`, `class="tagicon"`, `class="ico ico-big ico-find"`, `class="ico ico-big ico-compare"`} {
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
	for _, name := range []string{"icon-tag", "icon-delete", "icon-file", "icon-params", "icon-find", "icon-compare", "icon-cloud"} {
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

// rigWithOllama builds the handler and finds its page token, like newThemeRig, but for a fake Ollama the test supplies.
func rigWithOllama(t *testing.T, srv *httptest.Server) themeRig {
	// Mark this as a helper.
	t.Helper()
	// Build the handler once, because the token belongs to one handler.
	h := handlerFor(t, srv.URL)
	// Fetch the home page.
	_, _, body := get(t, h, http.MethodGet, "/")
	// Find the hidden token field.
	m := regexp.MustCompile(`name="token" value="([0-9a-f]{32})"`).FindStringSubmatch(body)
	// The page must carry a token.
	if m == nil {
		// Stop the test.
		t.Fatalf("no token found in the page")
	} // end of the token check
	// Hand back the pair.
	return themeRig{h: h, token: m[1]}
} // end of rigWithOllama

// seedTest saves one finished performance test for a model in the data folder the test uses, before the handler is built, so the handler loads it.
func seedTest(t *testing.T, r perfRun) {
	// Mark this as a helper.
	t.Helper()
	// The same file the program uses.
	path, _ := defaultHistoryPath()
	// Open it.
	store := openPerfStore(path, "")
	// Save the run.
	if err := store.add(r); err != nil {
		// A failure means the test is broken.
		t.Fatalf("could not save the test run: %v", err)
	} // end of the save check
} // end of seedTest

// TestSpeedNoteAndMarker checks the line shown for an installed version: the newest answer speed with its date, "not tested yet", the embedding wording, :latest matching, and no mark when Ollama could not be read.
func TestSpeedNoteAndMarker(t *testing.T) {
	// A memory-only store.
	store := openPerfStore("", "memory only")
	// An old and a newer test of the same version: the newer speed must win.
	store.add(perfRun{Time: time.Date(2026, 10, 1, 9, 0, 0, 0, time.UTC), Model: "alpha:0.6b", Kind: "generate", AnswerSpeed: 10})
	// The newer one.
	store.add(perfRun{Time: time.Date(2026, 11, 2, 13, 10, 0, 0, time.UTC), Model: "alpha:0.6b", Kind: "generate", AnswerSpeed: 42.34})
	// An embedding test.
	store.add(perfRun{Time: time.Date(2026, 11, 3, 8, 0, 0, 0, time.UTC), Model: "embedder:latest", Kind: "embedding"})
	// The installed list: a tested one, an untested one, an embedding one and a model without a tag.
	list := []installedModel{{Name: "alpha:0.6b"}, {Name: "alpha:8b"}, {Name: "embedder:latest"}, {Name: "plain"}}
	// The marker.
	mark := installedMarker(list, store, true)
	// The tested version: speed with one decimal, and a date.
	if ok, note := mark("alpha:0.6b"); !ok || !strings.HasPrefix(note, "Installed · 42.3 tokens per second · tested 2 Nov 2026") {
		// Report.
		t.Errorf("tested version: %v %q", ok, note)
	} // end of the tested check
	// The untested version.
	if ok, note := mark("alpha:8b"); !ok || note != "Installed, not tested yet" {
		// Report.
		t.Errorf("untested version: %v %q", ok, note)
	} // end of the untested check
	// The embedding model.
	if ok, note := mark("embedder:latest"); !ok || !strings.Contains(note, "embedding test saved") || !strings.Contains(note, "no answer speed") {
		// Report.
		t.Errorf("embedding model: %v %q", ok, note)
	} // end of the embedding check
	// A model installed without a tag matches the library's :latest.
	if ok, _ := mark("plain:latest"); !ok {
		// Report.
		t.Error("plain was not matched with plain:latest")
	} // end of the latest check
	// A version that is not installed gets no mark.
	if ok, note := mark("alpha:70b"); ok || note != "" {
		// Report.
		t.Errorf("not installed: %v %q", ok, note)
	} // end of the absent check
	// Ollama could not be read: no marker at all.
	if installedMarker(nil, store, false) != nil {
		// Report.
		t.Error("a marker was made although the installed list could not be read")
	} // end of the unread check
	// Installed versions come first inside a group and the order is kept otherwise.
	got := installedFirst([]versionView{{Tag: "a"}, {Tag: "b", Installed: true}, {Tag: "c"}, {Tag: "d", Installed: true}})
	// The tags in order.
	var order []string
	// Collect.
	for _, v := range got {
		// One tag.
		order = append(order, v.Tag)
	} // end of the collection
	// The expected order.
	if strings.Join(order, "") != "bdac" {
		// Report.
		t.Errorf("order %v, want b d a c", order)
	} // end of the order check
} // end of TestSpeedNoteAndMarker

// TestFindPageMarksInstalledVersions checks the page: installed versions are marked with their saved speed or "not tested yet", the explaining line is there, and a failing Ollama gives a clear note instead of silence.
func TestFindPageMarksInstalledVersions(t *testing.T) {
	// A throw-away data folder.
	isolateFindData(t)
	// An empty in-memory list.
	theListCache = listCache{}
	// Clear it again at the end.
	t.Cleanup(func() { theListCache = listCache{} })
	// A working fake library.
	fakeSite(t, findTestPages())
	// One saved test of the small version, with the current prompt, so the Compare page has a row.
	seedTest(t, perfRun{Time: time.Date(2026, 11, 2, 13, 10, 0, 0, time.UTC), Model: "alpha:0.6b", Kind: "generate", PromptVersion: perfPromptVersion, Runs: perfTimedRuns, AnswerSpeed: 42.3})
	// Both versions of alpha are installed.
	srv := fullOllama(t, []realRow{
		// The tested one.
		{"alpha:0.6b", 523000000, "2026-10-24T17:40:34.693006337Z", []string{"completion"}, "alpha", "0.6B", "Q4_K_M", 40960, 1024, ""},
		// The untested one.
		{"alpha:8b", 5200000000, "2026-10-24T17:40:34.693006337Z", []string{"completion"}, "alpha", "8B", "Q4_K_M", 131072, 4096, ""},
	}, `{"models":[]}`)
	// The rig.
	rig := rigWithOllama(t, srv)
	// Search with room for both versions.
	_, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"20"}, "mem_gb": {"32"}})
	// The tested version shows its speed and a date with a zone.
	if !strings.Contains(body, `<span class="installedmark">Installed &middot; 42.3 tokens per second &middot; tested 2 Nov 2026`) && !strings.Contains(body, "Installed · 42.3 tokens per second · tested 2 Nov 2026") {
		// Report.
		t.Error("the tested installed version does not show its speed and date")
	} // end of the tested check
	// The untested version says so.
	if !strings.Contains(body, `<span class="installedmark">Installed, not tested yet</span>`) {
		// Report.
		t.Error("the untested installed version is not marked")
	} // end of the untested check
	// The explaining line is there, and it points to the home page's Compare button instead of repeating it: no Compare form on this page.
	if !strings.Contains(body, "use the Compare tested models button on the home page") || strings.Contains(body, `action="/compare"`) {
		// Report.
		t.Error("the explaining line is missing, or a Compare form is on the Find LLM page")
	} // end of the explaining line check
	// The embedding model is not installed, so its version has no mark: exactly two marks on the page.
	if n := strings.Count(body, `class="installedmark"`); n != 2 {
		// Report.
		t.Errorf("%d marks, want 2", n)
	} // end of the count check
	// Nothing was installed or tested by the page: no request other than reads reached the fake Ollama (it only answers /api/tags, /api/version and /api/ps).
	// A second rig where nothing is installed: no marks and no explaining bar.
	srv2 := fullOllama(t, nil, `{"models":[]}`)
	// The rig.
	rig2 := rigWithOllama(t, srv2)
	// Search again.
	_, body2 := postFind(t, rig2, url.Values{"token": {rig2.token}, "ab_chat": {"on"}, "disk_gb": {"20"}, "mem_gb": {"32"}})
	// No marks and no bar.
	if strings.Contains(body2, `class="installedmark"`) || strings.Contains(body2, "marked <strong>Installed</strong>") {
		// Report.
		t.Error("marks appear although nothing is installed")
	} // end of the empty check
	// A third rig where Ollama fails: the page says so.
	srv3 := fakeOllama(t, replyWith(http.StatusInternalServerError, "boom"))
	// The rig.
	rig3 := rigWithOllama(t, srv3)
	// Search again.
	_, body3 := postFind(t, rig3, url.Values{"token": {rig3.token}, "ab_chat": {"on"}, "disk_gb": {"20"}, "mem_gb": {"32"}})
	// The note, and no marks.
	if !strings.Contains(body3, "The installed models could not be read just now") || strings.Contains(body3, `class="installedmark"`) {
		// Report.
		t.Error("a failing Ollama is not reported on the page")
	} // end of the failure check
} // end of TestFindPageMarksInstalledVersions

// TestHybridCloudModelStays checks a model that carries the cloud label but also lists sizes (like gemma4 or gpt-oss): it is a candidate, its local versions are offered, and its cloud versions are dropped; a model whose versions are all cloud says so.
func TestHybridCloudModelStays(t *testing.T) {
	// The cloud-only model has no sizes; the hybrid has sizes too.
	models := []siteModel{
		{Name: "faraway", Cloud: true, Abilities: []string{"tools"}, Pulls: "9M"},
		{Name: "hybrid", Cloud: true, Abilities: []string{"tools"}, Sizes: []string{"4b", "31b"}, Pulls: "8M"},
	}
	// Apply no choices.
	got, _, cloud := findCandidates(models, findSelection{})
	// Only the hybrid stays; one cloud-only model is counted as left out.
	if modelNames(got) != "hybrid" || cloud != 1 {
		// Report.
		t.Errorf("got %s with %d cloud-only left out, want hybrid and 1", modelNames(got), cloud)
	} // end of the candidate check
	// The cloud version names Ollama uses.
	for tag, want := range map[string]bool{"hybrid:31b-cloud": true, "gpt-oss:cloud": true, "hybrid:4b": false, "cloudy:latest": false, "hybrid": false} {
		// Check each.
		if isCloudTag(tag) != want {
			// Report.
			t.Errorf("isCloudTag(%q) = %v, want %v", tag, !want, want)
		} // end of the name check
	} // end of the name loop
	// The versions: one local and one cloud.
	tags := []siteTag{{Tag: "hybrid:4b", SizeText: "2.0GB", SizeBytes: 2000000000, Context: "128K"}, {Tag: "hybrid:31b-cloud", Context: "256K"}}
	// Build the view.
	r := buildResult(models[1], tags, "", findSelection{DiskGB: -1, MemGB: -1}, nil)
	// Only the local version is listed.
	if len(r.Versions) != 1 || r.Versions[0].Tag != "hybrid:4b" || r.Unavailable != "" {
		// Report.
		t.Errorf("versions %+v, unavailable %q", r.Versions, r.Unavailable)
	} // end of the version check
	// All versions cloud: nothing to offer, and the page says why.
	r2 := buildResult(models[1], tags[1:], "", findSelection{DiskGB: -1, MemGB: -1}, nil)
	// The reason is given and no version is listed.
	if len(r2.Versions) != 0 || !strings.Contains(r2.Unavailable, "run on Ollama's servers") {
		// Report.
		t.Errorf("all-cloud result: versions %d, unavailable %q", len(r2.Versions), r2.Unavailable)
	} // end of the all-cloud check
} // end of TestHybridCloudModelStays

// TestStateIconTexts checks the house rules for the state icons' tooltips: one short line of at most 130 characters, no markup characters, and different texts for the different states.
func TestStateIconTexts(t *testing.T) {
	// The five texts.
	texts := []string{tipCloud, tipModelFits, tipModelNoFit, tipVersionFits, tipVersionNoFit}
	// The texts seen so far, to catch two equal ones.
	seen := map[string]bool{}
	// Check each.
	for _, tx := range texts {
		// Not longer than 130 characters.
		if n := len([]rune(tx)); n > 130 {
			// Report.
			t.Errorf("%q has %d characters, want at most 130", tx, n)
		} // end of the length check
		// No markup characters.
		if strings.ContainsAny(tx, "<>&\"*_`#") {
			// Report.
			t.Errorf("%q has a markup character", tx)
		} // end of the markup check
		// Different from the others.
		if seen[tx] {
			// Report.
			t.Errorf("%q is used twice", tx)
		} // end of the twice check
		// Remember it.
		seen[tx] = true
	} // end of the loop
} // end of TestStateIconTexts

// TestStateIconsOnThePage checks the three icons on the results page: the cloud symbol on a cloud-only model, the check mark on a model and a version that can be installed, and the cross on a version and a model that cannot; every icon has its tooltip and a hidden name, and a size class removes the cloud section with an explanation.
func TestStateIconsOnThePage(t *testing.T) {
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
	// Room for the small version only.
	_, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"2"}, "mem_gb": {"8"}})
	// The page text with the character codes turned back.
	text := html.UnescapeString(body)
	// The model has a version that fits: check mark on the heading and on the small version, cross on the big one.
	for _, want := range []string{`state-fits" tabindex="0" role="img" aria-label="Can be installed" aria-describedby="tipstate-0"`, `aria-describedby="tipver-0-0"`, `state-nofit" tabindex="0" role="img" aria-label="Cannot be installed" aria-describedby="tipver-0-1"`, `state-cloud" tabindex="0" role="img" aria-label="Cloud model" aria-describedby="tipcloud-0"`} {
		// Look for it.
		if !strings.Contains(text, want) {
			// Report.
			t.Errorf("the page lacks %q", want)
		} // end of the look
	} // end of the loop
	// Every icon points at a tooltip that exists, and no tooltip name is used twice.
	for _, id := range []string{"tipstate-0", "tipver-0-0", "tipver-0-1", "tipcloud-0"} {
		// One tooltip with this name.
		if n := strings.Count(body, `id="`+id+`" role="tooltip"`) + strings.Count(body, `role="tooltip" id="`+id+`"`); n != 1 {
			// Report.
			t.Errorf("%d tooltips named %s, want 1", n, id)
		} // end of the name check
	} // end of the loop
	// With almost no room nothing fits: the model gets the cross.
	_, none := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "disk_gb": {"0.1"}, "mem_gb": {"0.1"}})
	// The model's own icon is the cross.
	if !strings.Contains(none, `state-nofit" tabindex="0" role="img" aria-label="Cannot be installed" aria-describedby="tipstate-0"`) {
		// Report.
		t.Error("a model with no version that fits has no cross")
	} // end of the cross check
	// A size class does not apply to cloud models: the section is gone and the summary says why.
	_, sized := postFind(t, rig, url.Values{"token": {rig.token}, "ab_chat": {"on"}, "sz_small": {"on"}, "disk_gb": {"2"}, "mem_gb": {"8"}})
	// No cloud section, and the reason.
	if strings.Contains(sized, `id="cloudmodels"`) || !strings.Contains(html.UnescapeString(sized), "not shown because you chose a size or a memory class") {
		// Report.
		t.Error("a size class should remove the cloud section and say why")
	} // end of the class check
} // end of TestStateIconsOnThePage

// mixHex mixes two #rrggbb colours: the share p (0 to 1) of a, the rest of b, as color-mix does in the sRGB space.
func mixHex(a, b string, p float64) string {
	// The result starts as the hash sign.
	out := "#"
	// Each of the red, green and blue pairs.
	for i := 1; i < 7; i += 2 {
		// The two channel values.
		x, _ := strconv.ParseInt(a[i:i+2], 16, 32)
		// The second colour's channel.
		y, _ := strconv.ParseInt(b[i:i+2], 16, 32)
		// The mixed channel, rounded.
		out += fmt.Sprintf("%02x", int(math.Round(float64(x)*p+float64(y)*(1-p))))
	} // end of the channel loop
	// The mixed colour.
	return out
} // end of mixHex

// TestButtonHighlightAndIconRules checks that every icon colour is really applied, that every kind of button has a highlight when pointed at or focused, that the highlight never touches the tooltips, and that the two button icons stay readable on the highlighted button.
func TestButtonHighlightAndIconRules(t *testing.T) {
	// The style sheet.
	_, _, css := get(t, handlerFor(t, fullOllama(t, realModels, realPsBody).URL), http.MethodGet, "/app.css")
	// Every icon colour that is defined must also be used by a rule: a defined but unused colour is the bug that hid the teal and the gold.
	for _, name := range regexp.MustCompile(`--(icon-[a-z]+): #`).FindAllStringSubmatch(css, -1) {
		// The use: the colour is read by a rule somewhere.
		if !strings.Contains(css, "var(--"+name[1]+")") {
			// Report.
			t.Errorf("--%s is defined but no rule uses it", name[1])
		} // end of the use check
	} // end of the loop
	// The two button icons have their own rules.
	for _, want := range []string{".ico-find {\n  /* The theme's teal; the symbol is drawn in the current colour. */\n  color: var(--icon-find);", ".ico-compare {\n  /* The theme's gold; the symbol is drawn in the current colour. */\n  color: var(--icon-compare);"} {
		// Look for it.
		if !strings.Contains(css, want) {
			// Report.
			t.Errorf("the style sheet lacks the rule %q", want[:12])
		} // end of the look
	} // end of the loop
	// Every kind of button: pointed at, and reached with the keyboard.
	for _, sel := range []string{".btn-plain", ".comparebtn", ".btn-solid", ".btn-load", ".btn-go", ".btn-danger", ".unload", ".load", ".switch", ".autobtn", ".gear", ".copybtn", ".backcircle"} {
		// The rule must name both states.
		for _, state := range []string{":hover", ":focus-visible"} {
			// Look for it.
			if !strings.Contains(css, sel+state) {
				// Report.
				t.Errorf("%s has no %s rule", sel, state)
			} // end of the look
		} // end of the state loop
	} // end of the loop
	// The highlight block starts at its own heading comment.
	i := strings.Index(css, "/* Button highlight:")
	// It must exist.
	if i < 0 {
		// Stop here.
		t.Fatal("the highlight block is missing")
	} // end of the block check
	// The block itself: it ends where the next, unrelated group of rules starts.
	block := css[i:]
	// Cut it there.
	if j := strings.Index(block, `/* "What it should do"`); j > 0 {
		// Keep only the highlight rules.
		block = block[:j]
	} // end of the cut
	// The highlight changes colours only: nothing that could hide, move or block a tooltip.
	for _, bad := range []string{"pointer-events", "overflow", "display:", "visibility", "position", "z-index", "opacity", "content:"} {
		// Look for it.
		if strings.Contains(block, bad) {
			// Report.
			t.Errorf("the highlight block contains %q, which could disturb the tooltips", bad)
		} // end of the look
	} // end of the loop
	// The tooltip rules are still there: they open on pointing and on focus.
	for _, want := range []string{".tipbox:hover > .tip", ".tipbox:focus-within > .tip"} {
		// Look for it.
		if !strings.Contains(css, want) {
			// Report.
			t.Errorf("the tooltip rule %q is gone", want)
		} // end of the look
	} // end of the loop
	// The panel colour, the text colour and the two icon colours, light then dark.
	for _, th := range []struct{ name, panel, bg, text, find, compare string }{{"light", "#f4f6f8", "#ffffff", "#1a1a1a", "#0a6b73", "#7a5f00"}, {"dark", "#1b1f24", "#121417", "#ececec", "#4fd1c5", "#e3c04d"}} {
		// The highlighted button: 8 percent of the text colour over the page or the panel.
		for _, under := range []string{th.panel, th.bg} {
			// The washed colour.
			hl := mixHex(th.text, under, 0.08)
			// Both icons.
			for _, c := range []string{th.find, th.compare} {
				// The ratio.
				if r := contrastOf(c, hl); r < 4.5 {
					// Report.
					t.Errorf("%s theme: icon %s on the highlighted button (%s) has contrast %.2f, want at least 4.5", th.name, c, hl, r)
				} // end of the ratio check
			} // end of the icon loop
		} // end of the background loop
	} // end of the theme loop
} // end of TestButtonHighlightAndIconRules

// TestAbilitiesMatch checks the all-or-any rule for the ticks of "What it should do", including the empty case and the Chat and writing tick.
func TestAbilitiesMatch(t *testing.T) {
	// The cases: what is ticked, the mode, the model's abilities and the expected answer.
	for _, c := range []struct {
		name string
		sel  findSelection
		has  map[string]bool
		want bool
	}{
		// Nothing ticked: every model passes, in both modes.
		{"nothing ticked, all", findSelection{}, map[string]bool{"tools": true}, true},
		{"nothing ticked, any", findSelection{Any: true}, map[string]bool{}, true},
		// Two abilities, Match ALL: needs both.
		{"all: has both", findSelection{Abilities: map[string]bool{"tools": true, "vision": true}}, map[string]bool{"tools": true, "vision": true}, true},
		{"all: has one", findSelection{Abilities: map[string]bool{"tools": true, "vision": true}}, map[string]bool{"tools": true}, false},
		// Two abilities, Match ANY: one is enough, none is not.
		{"any: has one", findSelection{Any: true, Abilities: map[string]bool{"tools": true, "vision": true}}, map[string]bool{"tools": true}, true},
		{"any: has none", findSelection{Any: true, Abilities: map[string]bool{"tools": true, "vision": true}}, map[string]bool{"audio": true}, false},
		// Chat and writing with an ability, Match ALL: a chat model that also has the ability; an embedding model fails.
		{"all: chat and tools, chat model with tools", findSelection{Chat: true, Abilities: map[string]bool{"tools": true}}, map[string]bool{"tools": true}, true},
		{"all: chat and tools, embedding model", findSelection{Chat: true, Abilities: map[string]bool{"tools": true}}, map[string]bool{"embedding": true, "tools": true}, false},
		// Chat and writing with an ability, Match ANY: a chat model without the ability passes; an embedding model without it fails.
		{"any: chat or tools, chat model without tools", findSelection{Any: true, Chat: true, Abilities: map[string]bool{"tools": true}}, map[string]bool{}, true},
		{"any: chat or tools, embedding model without tools", findSelection{Any: true, Chat: true, Abilities: map[string]bool{"tools": true}}, map[string]bool{"embedding": true}, false},
	} {
		// The answer.
		if got := abilitiesMatch(c.sel, c.has); got != c.want {
			// Report.
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		} // end of the answer check
	} // end of the loop
} // end of TestAbilitiesMatch

// TestFindModeChoice checks the Match ALL or Match ANY choice on the page and in the search: it sits inside "What it should do", defaults to ALL, is explained in visible text under each option and also has a very short tooltip, is kept after a search, and changes the result.
func TestFindModeChoice(t *testing.T) {
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
	// The fieldset of "What it should do" up to its end.
	i := strings.Index(form, "<strong>What it should do</strong>")
	// It must exist.
	if i < 0 {
		// Stop here.
		t.Fatal("the page lacks the What it should do box")
	} // end of the box check
	// The box itself.
	box := form[i : i+strings.Index(form[i:], "</fieldset>")]
	// Both radio buttons are inside the box, ALL is ticked by default and ANY is not.
	if !strings.Contains(box, `name="ab_mode" value="all" checked`) || strings.Contains(box, `name="ab_mode" value="any" checked`) || !strings.Contains(box, `name="ab_mode" value="any"`) {
		// Report.
		t.Error("the choice is missing from the box or the default is not Match ALL")
	} // end of the radio check
	// The explanation of each choice is visible text in the box, outside any tooltip.
	for _, want := range []string{"Match ALL ticked", "Match ANY ticked", "The model must do everything you ticked.", "The model needs at least one of the things you ticked."} {
		// Look for it.
		if !strings.Contains(box, want) {
			// Report.
			t.Errorf("the box lacks the text %q", want)
		} // end of the look
	} // end of the loop
	// The visible explanations sit in their own paragraphs, not inside a tooltip bubble.
	for _, b := range regexp.MustCompile(`(?s)<span class="tip"[^>]*>.*?</span>`).FindAllString(box, -1) {
		// A bubble that holds a long explanation.
		if strings.Contains(b, "everything you ticked") || strings.Contains(b, "at least one of the things") {
			// Report.
			t.Error("a tooltip repeats the long explanation instead of staying very short")
		} // end of the bubble check
	} // end of the loop
	// The heading words take no room: the group keeps its name only as an aria-label for screen readers.
	if strings.Contains(strings.ReplaceAll(box, `aria-label="How the ticks combine"`, ""), "How the ticks combine") || !strings.Contains(box, `aria-label="How the ticks combine"`) {
		// Report.
		t.Error("the words How the ticks combine are visible, or the group lost its accessible name")
	} // end of the heading check
	// Each choice also has a very short tooltip: one line, at most 40 characters, no markup characters.
	for _, id := range []string{"tip-mode-all", "tip-mode-any"} {
		// The bubble with this id, and the word that points to it.
		m := regexp.MustCompile(`id="` + id + `">([^<]*)</span>`).FindStringSubmatch(box)
		// It must exist, and the label must point to it.
		if m == nil || !strings.Contains(box, `aria-describedby="`+id+`"`) {
			// Report and go on.
			t.Errorf("the choice has no tooltip %s", id)
			// Next.
			continue
		} // end of the bubble check
		// The text, as a person reads it.
		tx := html.UnescapeString(m[1])
		// Very short and clean.
		if n := utf8.RuneCountInString(tx); n == 0 || n > 40 || strings.ContainsAny(tx, "<>{}\n") {
			// Report.
			t.Errorf("%s text %q is empty, longer than 40 characters, or has markup characters", id, tx)
		} // end of the text check
	} // end of the bubble loop
	// The same search in both modes: tools or embedding is ticked (no model has both).
	base := url.Values{"token": {rig.token}, "ab_tools": {"on"}, "ab_embedding": {"on"}, "disk_gb": {"100"}, "mem_gb": {"64"}}
	// Match ALL (nothing sent for the mode): no model has both.
	_, all := postFind(t, rig, base)
	// None of the three fake models is listed.
	for _, d := range []string{"An invented chat model.", "Turns text into numbers.", "Runs far away."} {
		// Look for it.
		if strings.Contains(all, d) {
			// Report.
			t.Errorf("Match ALL lists a model (%q) that lacks one of the ticked abilities", d)
		} // end of the look
	} // end of the loop
	// Match ANY: a model with either ability.
	any := url.Values{}
	// Copy the fields.
	for k, v := range base {
		// One field.
		any[k] = v
	} // end of the copy
	// The choice.
	any.Set("ab_mode", "any")
	// Send it.
	_, anyBody := postFind(t, rig, any)
	// The local chat model, the embedding model and the cloud model are all listed.
	for _, d := range []string{"An invented chat model.", "Turns text into numbers.", "Runs far away."} {
		// Look for it.
		if !strings.Contains(anyBody, d) {
			// Report.
			t.Errorf("Match ANY does not list the model %q", d)
		} // end of the look
	} // end of the loop
	// The choice is kept after the search.
	if !strings.Contains(anyBody, `name="ab_mode" value="any" checked`) || strings.Contains(anyBody, `name="ab_mode" value="all" checked`) {
		// Report.
		t.Error("Match ANY is not kept after the search")
	} // end of the kept check
	// An unknown value falls back to the default.
	odd := url.Values{}
	// Copy the fields.
	for k, v := range base {
		// One field.
		odd[k] = v
	} // end of the copy
	// A value that is neither choice.
	odd.Set("ab_mode", "nonsense")
	// Send it.
	_, oddBody := postFind(t, rig, odd)
	// It behaves as Match ALL.
	if !strings.Contains(oddBody, `name="ab_mode" value="all" checked`) {
		// Report.
		t.Error("an unknown mode did not fall back to Match ALL")
	} // end of the fallback check
} // end of TestFindModeChoice

// TestDomainDefinitions checks the house rules for the fields of use: unique keys, a label and a tooltip each, tooltips of one short line without markup characters.
func TestDomainDefinitions(t *testing.T) {
	// The keys seen so far.
	seen := map[string]bool{}
	// Each field of use.
	for _, d := range findDomains {
		// A key is used once.
		if seen[d.Key] {
			// Report.
			t.Errorf("the key %q is used twice", d.Key)
		} // end of the key check
		// Remember it.
		seen[d.Key] = true
		// Label and tooltip are filled.
		if strings.TrimSpace(d.Label) == "" || strings.TrimSpace(d.Tip) == "" {
			// Report.
			t.Errorf("%q has an empty label or tooltip", d.Key)
		} // end of the filled check
		// The tooltip follows the house rules.
		if n := utf8.RuneCountInString(d.Tip); n > 130 || strings.ContainsAny(d.Tip, "<>{}\n") {
			// Report.
			t.Errorf("%q: tooltip %q is longer than 130 characters or has markup characters", d.Key, d.Tip)
		} // end of the tooltip check
	} // end of the loop
} // end of TestDomainDefinitions

// TestModelDomains checks the keyword assignment with real descriptions from the official library: each model lands in its fields, and models that only mention a word in passing, or only look like a keyword, do not.
func TestModelDomains(t *testing.T) {
	// The cases: real name and description (as read on 2026-11-08) and the expected fields.
	for _, c := range []struct {
		name, desc string
		want       string
	}{
		{"medgemma", "MedGemma is a collection of Gemma 3 variants that are trained for performance on medical text and image comprehension.", "health"},
		{"meditron", "Open-source medical large language model adapted from Llama 2 to the medical domain.", "health"},
		{"sqlcoder", "SQLCoder is a code completion model fined-tuned on StarCoder for SQL generation tasks", "code,sql"},
		{"duckdb-nsql", "7B parameter text-to-SQL model made by MotherDuck and Numbers Station.", "sql"},
		{"mathstral", "MathΣtral: a 7B model designed for math reasoning and scientific discovery by Mistral AI.", "math"},
		{"qwen2-math", "Qwen2 Math is a series of specialized math language models built upon the Qwen2 LLMs.", "math"},
		{"glm-ocr", "GLM-OCR is a multimodal OCR model for complex document understanding, built on the GLM-V encoder-decoder architecture.", "docs"},
		{"translategemma", "A new collection of open translation models built on Gemma 3, helping people communicate across 55 languages.", "lang"},
		{"llama-guard3", "Llama Guard 3 is a series of models fine-tuned for content safety classification of LLM inputs and responses.", "safety"},
		// A general model that lists coding among many abilities is not a code model.
		{"qwen3.6", "Qwen3.6 delivers substantial upgrades in agentic coding and thinking preservation than previous Qwen models.", ""},
		// A name that merely contains the letters aya is not the Aya family.
		{"laya", "Laya is a 421M decision model from Convai Innovations, fine-tuned from ModernBERT-large.", ""},
		// A model with no domain word at all.
		{"gpt-oss", "OpenAI's open-weight models designed for powerful reasoning, agentic tasks, and versatile developer use cases.", ""},
	} {
		// The fields found, in the order of findDomains.
		var got []string
		// Each field.
		for _, d := range findDomains {
			// Found.
			if modelDomains(siteModel{Name: c.name, Description: c.desc})[d.Key] {
				// Remember it.
				got = append(got, d.Key)
			} // end of the found check
		} // end of the loop
		// Compare as text.
		if g := strings.Join(got, ","); g != c.want {
			// Report.
			t.Errorf("%s: fields %q, want %q", c.name, g, c.want)
		} // end of the compare
	} // end of the cases
} // end of TestModelDomains

// TestDomainMatch checks the all-or-any rule for the fields of use, including nothing ticked.
func TestDomainMatch(t *testing.T) {
	// A model in two fields, and one in a single field.
	sqlcoder := siteModel{Name: "sqlcoder", Description: "SQLCoder is a code completion model fined-tuned on StarCoder for SQL generation tasks"}
	// The maths model.
	maths := siteModel{Name: "qwen2-math", Description: "Qwen2 Math is a series of specialized math language models."}
	// The cases.
	for _, c := range []struct {
		name string
		sel  findSelection
		m    siteModel
		want bool
	}{
		{"nothing ticked", findSelection{}, maths, true},
		{"all: both fields, model in both", findSelection{Domains: map[string]bool{"code": true, "sql": true}}, sqlcoder, true},
		{"all: both fields, model in one", findSelection{Domains: map[string]bool{"code": true, "math": true}}, maths, false},
		{"any: one of two", findSelection{DomainAny: true, Domains: map[string]bool{"code": true, "math": true}}, maths, true},
		{"any: none of two", findSelection{DomainAny: true, Domains: map[string]bool{"health": true, "safety": true}}, maths, false},
	} {
		// The answer.
		if got := domainMatch(c.sel, c.m); got != c.want {
			// Report.
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		} // end of the answer check
	} // end of the loop
} // end of TestDomainMatch

// TestFindDomainChoice checks the Field of use group on the page: the boxes, the default Match ALL, the visible explanation and the very short tooltips, the guess note, and that the ticks and the choice are kept after a search.
func TestFindDomainChoice(t *testing.T) {
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
	// The group starts at its legend.
	i := strings.Index(form, "<strong>Field of use</strong>")
	// It must exist.
	if i < 0 {
		// Stop here.
		t.Fatal("the page lacks the Field of use group")
	} // end of the group check
	// The group itself.
	box := form[i : i+strings.Index(form[i:], "</fieldset>")]
	// Every field has a box and a tooltip that the box points to.
	for _, d := range findDomains {
		// The box and the tooltip.
		if !strings.Contains(box, `name="dom_`+d.Key+`"`) || !strings.Contains(box, `id="tip-dom-`+d.Key+`">`+d.Tip) || !strings.Contains(box, `aria-describedby="tip-dom-`+d.Key+`"`) {
			// Report.
			t.Errorf("the group lacks the box or tooltip of %q", d.Key)
		} // end of the field check
	} // end of the loop
	// Match ALL is the default and both choices exist.
	if !strings.Contains(box, `name="dom_mode" value="all" checked`) || strings.Contains(box, `name="dom_mode" value="any" checked`) || !strings.Contains(box, `name="dom_mode" value="any"`) {
		// Report.
		t.Error("the choice is missing or the default is not Match ALL")
	} // end of the radio check
	// Visible explanations, the two very short tooltips and the guess note.
	for _, want := range []string{"The model must fit every field you ticked.", "The model needs to fit at least one field you ticked.", `id="tip-dom-mode-all">All ticked fields needed.`, `id="tip-dom-mode-any">One ticked field is enough.`, "It is not a certification.", "Healthcare models are not validated for clinical use."} {
		// Look for it.
		if !strings.Contains(box, want) {
			// Report.
			t.Errorf("the group lacks the text %q", want)
		} // end of the look
	} // end of the loop
	// No heading words are shown for the choice, only an accessible name.
	if strings.Contains(strings.ReplaceAll(box, `aria-label="How the ticked fields combine"`, ""), "How the ticked fields combine") {
		// Report.
		t.Error("the words How the ticked fields combine are visible")
	} // end of the heading check
	// A search with a field ticked and Match ANY chosen: nothing in the fake library is a healthcare model, and both choices are kept.
	_, body := postFind(t, rig, url.Values{"token": {rig.token}, "dom_health": {"on"}, "dom_mode": {"any"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
	// No fake model is listed.
	for _, d := range []string{"An invented chat model.", "Turns text into numbers.", "Runs far away."} {
		// Look for it.
		if strings.Contains(body, d) {
			// Report.
			t.Errorf("the healthcare filter lists %q", d)
		} // end of the look
	} // end of the loop
	// The tick and the choice are kept.
	if !strings.Contains(body, `name="dom_health" checked`) || !strings.Contains(body, `name="dom_mode" value="any" checked`) {
		// Report.
		t.Error("the ticked field or Match ANY is not kept after the search")
	} // end of the kept check
} // end of TestFindDomainChoice

// TestCloudHeadingAndNote checks that the Cloud models section catches the eye: a large symbol in the heading, sized from the text, and a framed note with bold key phrases, readable in light and dark themes.
func TestCloudHeadingAndNote(t *testing.T) {
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
	// A search that brings the cloud model: tools, no size, no memory class.
	_, body := postFind(t, rig, url.Values{"token": {rig.token}, "ab_tools": {"on"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
	// The heading holds the symbol, hidden from screen readers, and the words.
	if !strings.Contains(body, `<h2 id="cloudmodels" class="cloudhead"><svg class="cloudbig"`) || !strings.Contains(body, `aria-hidden="true"`) || !strings.Contains(body, "<span>Cloud models</span></h2>") {
		// Report.
		t.Error("the Cloud models heading lacks its large symbol")
	} // end of the heading check
	// The note is a framed note with the three key phrases in bold.
	for _, want := range []string{`<p class="cloudnote" role="note">`, "<strong>These models run on Ollama's servers, not on this computer,</strong>", "<strong>Nothing is downloaded.</strong>", "<strong>They may need an Ollama account.</strong>", "so your free disk space and memory do not apply to them."} {
		// Look for it, as a person reads it.
		if !strings.Contains(html.UnescapeString(body), want) {
			// Report.
			t.Errorf("the note lacks %q", want)
		} // end of the look
	} // end of the loop
	// The style sheet.
	_, _, css := get(t, rig.h, http.MethodGet, "/app.css")
	// The three rules exist, and the symbol is sized from the text.
	for _, want := range []string{".cloudhead {", ".cloudbig {", "width: 1.7em;", ".cloudnote {", "border-left: 6px solid var(--icon-cloud);"} {
		// Look for it.
		if !strings.Contains(css, want) {
			// Report.
			t.Errorf("the style sheet lacks %q", want)
		} // end of the look
	} // end of the loop
	// The note's text must stay readable on its tint: the tint is 12 percent of the cloud colour over the panel colour.
	for _, th := range []struct{ name, panel, text, cloud string }{{"light", "#f4f6f8", "#1a1a1a", "#1565a8"}, {"dark", "#1b1f24", "#ececec", "#86c5f2"}} {
		// The tinted background.
		bg := mixHex(th.cloud, th.panel, 0.12)
		// The ratio of the text on it.
		if r := contrastOf(th.text, bg); r < 7 {
			// Report.
			t.Errorf("%s theme: note text on its tint has contrast %.2f, want at least 7", th.name, r)
		} // end of the ratio check
		// The cloud colour on the panel, for the symbol and the bar.
		if r := contrastOf(th.cloud, th.panel); r < 4.5 {
			// Report.
			t.Errorf("%s theme: cloud colour on the panel has contrast %.2f, want at least 4.5", th.name, r)
		} // end of the cloud ratio check
	} // end of the theme loop
} // end of TestCloudHeadingAndNote

// TestSortOrder checks the order of the candidates: most downloaded first by default (equal counts by name), and Name A to Z when chosen, for local models and for cloud models.
func TestSortOrder(t *testing.T) {
	// Three local models whose download order differs from their name order, and two cloud models.
	models := []siteModel{
		{Name: "bravo", Pulls: "2M", Sizes: []string{"8b"}},
		{Name: "alpha", Pulls: "900K", Sizes: []string{"8b"}},
		{Name: "charlie", Pulls: "12M", Sizes: []string{"8b"}},
		{Name: "zeta", Pulls: "5M", Cloud: true},
		{Name: "echo", Pulls: "50M", Cloud: true},
	}
	// The names of a list, in order.
	names := func(ms []siteModel) string {
		// Collect them.
		var out []string
		// Each model.
		for _, m := range ms {
			// One name.
			out = append(out, m.Name)
		} // end of the loop
		// As text.
		return strings.Join(out, ",")
	} // end of names
	// The default: most downloaded first.
	local, _, _ := findCandidates(models, findSelection{})
	// Check it.
	if got := names(local); got != "charlie,bravo,alpha" {
		// Report.
		t.Errorf("default local order %q, want charlie,bravo,alpha", got)
	} // end of the default check
	// Name A to Z.
	local, _, _ = findCandidates(models, findSelection{Sort: "name"})
	// Check it.
	if got := names(local); got != "alpha,bravo,charlie" {
		// Report.
		t.Errorf("name local order %q, want alpha,bravo,charlie", got)
	} // end of the name check
	// The cloud models, default.
	cloud, _ := findCloudModels(models, findSelection{})
	// Check it.
	if got := names(cloud); got != "echo,zeta" {
		// Report.
		t.Errorf("default cloud order %q, want echo,zeta", got)
	} // end of the cloud default check
	// The cloud models, by name.
	cloud, _ = findCloudModels(models, findSelection{Sort: "name"})
	// Check it.
	if got := names(cloud); got != "echo,zeta" {
		// Report.
		t.Errorf("name cloud order %q, want echo,zeta", got)
	} // end of the cloud name check
	// Equal download counts keep the name order.
	tie := []siteModel{{Name: "b", Pulls: "1M", Sizes: []string{"8b"}}, {Name: "a", Pulls: "1M", Sizes: []string{"8b"}}}
	// The default order of the tie.
	local, _, _ = findCandidates(tie, findSelection{})
	// Check it.
	if got := names(local); got != "a,b" {
		// Report.
		t.Errorf("tie order %q, want a,b", got)
	} // end of the tie check
} // end of TestSortOrder

// TestFindSortChoice checks the Sort by choice beside the Find LLM button: it is there, Most downloaded is the default, a very short tooltip explains it, an unknown value counts as the default, and Name A to Z is kept after a search.
func TestFindSortChoice(t *testing.T) {
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
	// The choice sits in the same paragraph as the button, with Most downloaded selected.
	for _, want := range []string{`<p class="findaction"><button type="submit" class="btn-solid">Find LLM</button>`, `name="sort"`, `<option value="downloads" selected>Most downloaded</option>`, `<option value="name">Name A to Z</option>`, `Sort by <select class="keepselect" id="sortby" name="sort">`} {
		// Look for it.
		if !strings.Contains(form, want) {
			// Report.
			t.Errorf("the page lacks %q", want)
		} // end of the look
	} // end of the loop
	// A search with Name A to Z: the choice is kept.
	_, body := postFind(t, rig, url.Values{"token": {rig.token}, "sort": {"name"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
	// Kept.
	if !strings.Contains(body, `<option value="name" selected>Name A to Z</option>`) || strings.Contains(body, `<option value="downloads" selected>`) {
		// Report.
		t.Error("Name A to Z is not kept after the search")
	} // end of the kept check
	// An unknown value falls back to the default.
	_, odd := postFind(t, rig, url.Values{"token": {rig.token}, "sort": {"nonsense"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
	// The default is selected.
	if !strings.Contains(odd, `<option value="downloads" selected>Most downloaded</option>`) {
		// Report.
		t.Error("an unknown sort value did not fall back to Most downloaded")
	} // end of the fallback check
} // end of TestFindSortChoice
