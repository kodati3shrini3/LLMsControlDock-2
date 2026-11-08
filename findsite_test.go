// Package main tells Go that this test file belongs to the same program as findsite.go.
package main

import ( // import lists the standard-library packages this test file uses.
	// context gives the requests their context.
	"context"
	// net/http gives the fake website its handler type and the status codes.
	"net/http"
	// net/http/httptest makes a fake website, so no test touches the real network.
	"net/http/httptest"
	// os reads the optional real pages.
	"os"
	// path/filepath joins the folder of the real pages with a file name.
	"path/filepath"
	// reflect compares lists.
	"reflect"
	// strings builds and searches test pages.
	"strings"
	// sync/atomic counts requests safely.
	"sync/atomic"
	// testing is Go's built-in test framework.
	"testing"
	// time gives the fake clock.
	"time"
) // end of imports

// listEntry writes one entry the way the library list page does (same structure, invented content), with the given labels.
func listEntry(name, desc string, labels ...string) string {
	// The start of the entry, as the real page writes it.
	s := "<li  class=\"flex items-baseline border-b\">\n<a href=\"/library/" + name + "\" class=\"group\">\n<div  title=\"" + name + "\">\n<h2><span>" + name + "</span></h2>\n<p class=\"max-w-lg break-words text-neutral-800 text-md\">" + desc + "</p>\n</div>\n<div class=\"flex flex-wrap space-x-2\">\n"
	// Every label.
	for _, l := range labels {
		// One label.
		s += "<span  class=\"inline-flex items-center rounded-md bg-indigo-50 px-2\">" + l + "</span>\n"
	} // end of the label loop
	// The download count and the end of the entry.
	return s + "<span class=\"flex items-center\"><span >1.5M</span>\n<span class=\"hidden sm:flex\">&nbsp;Pulls</span></span>\n</a>\n</li>\n"
} // end of listEntry

// tagEntry writes one version block the way the tags page does (same structure, invented content).
func tagEntry(tag, size, context string) string {
	// The compact block with the pieces separated by bullets, as the real page writes them.
	body := "<span>" + tag + "</span>\n<span class=\"font-mono\">abc123def456</span> • " + size
	// The context part is optional.
	if context != "" {
		// Add it.
		body += " • " + context + " context window"
	} // end of the context part
	// The input part and the end of the block.
	return "<a href=\"/library/" + tag + "\" class=\"md:hidden flex flex-col\">\n" + body + " • Text input • 1 year ago\n</a>\n"
} // end of tagEntry

// TestParseSiteListReadsNamesAbilitiesSizesAndCloud checks what one list page gives.
func TestParseSiteListReadsNamesAbilitiesSizesAndCloud(t *testing.T) {
	// A page with three entries: a normal one, an embedding one without sizes, and a cloud one with an unknown label.
	page := "<html><ul>" + listEntry("alpha", "A &amp; B model.", "tools", "thinking", "0.6b", "8b") + listEntry("beta-embed", "Turns text into numbers.", "embedding") + listEntry("gamma", "Runs far away.", "cloud", "decision", "e4b", "vision") + "</ul></html>"
	// Read it.
	got, err := parseSiteList(page)
	// It must work.
	if err != nil {
		// Report.
		t.Fatalf("parseSiteList: %v", err)
	} // end of the error check
	// Three entries.
	if len(got) != 3 {
		// Report.
		t.Fatalf("got %d models, want 3", len(got))
	} // end of the count check
	// The first entry in full.
	want0 := siteModel{Name: "alpha", Description: "A & B model.", Abilities: []string{"tools", "thinking"}, Sizes: []string{"0.6b", "8b"}, Pulls: "1.5M"}
	// Compare.
	if !reflect.DeepEqual(got[0], want0) {
		// Report.
		t.Errorf("first model = %+v, want %+v", got[0], want0)
	} // end of the first check
	// The embedding model has no sizes and one ability.
	if !reflect.DeepEqual(got[1].Abilities, []string{"embedding"}) || len(got[1].Sizes) != 0 {
		// Report.
		t.Errorf("second model = %+v", got[1])
	} // end of the second check
	// The cloud model is marked, keeps its unknown label apart, and counts e4b as a size.
	if !got[2].Cloud || !reflect.DeepEqual(got[2].Other, []string{"decision"}) || !reflect.DeepEqual(got[2].Sizes, []string{"e4b"}) || !reflect.DeepEqual(got[2].Abilities, []string{"vision"}) {
		// Report.
		t.Errorf("third model = %+v", got[2])
	} // end of the third check
} // end of TestParseSiteListReadsNamesAbilitiesSizesAndCloud

// TestParseSiteListRefusesAChangedLayout checks that a page without entries, or with an entry without a name, is an error and not a short list.
func TestParseSiteListRefusesAChangedLayout(t *testing.T) {
	// A page with no entries at all.
	if _, err := parseSiteList("<html>nothing here</html>"); err != errLayout {
		// Report.
		t.Errorf("empty page: err = %v, want errLayout", err)
	} // end of the empty check
	// An entry that has no library link.
	if _, err := parseSiteList("<li  class=\"flex items-baseline\"><p>no link</p></li>"); err != errLayout {
		// Report.
		t.Errorf("nameless entry: err = %v, want errLayout", err)
	} // end of the nameless check
} // end of TestParseSiteListRefusesAChangedLayout

// TestParseSiteTagsReadsSizeContextAndInput checks what one tags page gives.
func TestParseSiteTagsReadsSizeContextAndInput(t *testing.T) {
	// A page with a repeated version and one without a context length.
	page := "<html>" + tagEntry("m:1b", "3.3GB", "128K") + tagEntry("m:350m", "708MB", "32K") + tagEntry("m:1b", "3.3GB", "128K") + tagEntry("m:odd", "12KB", "") + "</html>"
	// Read it.
	got, err := parseSiteTags(page)
	// It must work.
	if err != nil {
		// Report.
		t.Fatalf("parseSiteTags: %v", err)
	} // end of the error check
	// The repeat is dropped.
	if len(got) != 3 {
		// Report.
		t.Fatalf("got %d tags, want 3: %+v", len(got), got)
	} // end of the count check
	// The first version in full.
	want0 := siteTag{Tag: "m:1b", SizeText: "3.3GB", SizeBytes: 3300000000, Context: "128K", Input: "Text input"}
	// Compare.
	if got[0] != want0 {
		// Report.
		t.Errorf("first tag = %+v, want %+v", got[0], want0)
	} // end of the first check
	// The second version.
	if got[1].SizeBytes != 708000000 || got[1].Context != "32K" {
		// Report.
		t.Errorf("second tag = %+v", got[1])
	} // end of the second check
	// A missing context stays empty and is not invented.
	if got[2].Context != "" || got[2].SizeBytes != 12000 {
		// Report.
		t.Errorf("third tag = %+v", got[2])
	} // end of the third check
	// A page without versions is a layout error.
	if _, err := parseSiteTags("<html></html>"); err != errLayout {
		// Report.
		t.Errorf("empty tags page: err = %v, want errLayout", err)
	} // end of the empty check
} // end of TestParseSiteTagsReadsSizeContextAndInput

// TestSizeBytesUnits checks the unit conversion, including the rounding and an unknown unit.
func TestSizeBytesUnits(t *testing.T) {
	// The cases.
	for _, c := range []struct {
		// number and unit are the inputs.
		number, unit string
		// want is the expected bytes.
		want int64
	}{{"708", "MB", 708000000}, {"3.3", "GB", 3300000000}, {"1.5", "GB", 1500000000}, {"12", "KB", 12000}, {"1.2", "TB", 1200000000000}, {"5", "XB", 0}, {"x", "GB", 0}} {
		// Convert.
		if got := sizeBytes(c.number, c.unit); got != c.want {
			// Report.
			t.Errorf("sizeBytes(%q, %q) = %d, want %d", c.number, c.unit, got, c.want)
		} // end of the compare
	} // end of the case loop
} // end of TestSizeBytesUnits

// fakeSite starts a fake website with the given pages and points ollamaSite at it for the test; hits counts the requests it receives.
func fakeSite(t *testing.T, pages map[string]string) (hits *int32) {
	// Mark this as a helper.
	t.Helper()
	// The counter.
	hits = new(int32)
	// The fake server.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Count the request.
		atomic.AddInt32(hits, 1)
		// The reader must say who it is.
		if r.Header.Get("User-Agent") != "LLMsControlDock" {
			// Refuse an unknown client.
			http.Error(w, "unknown client", http.StatusForbidden)
			// Stop.
			return
		} // end of the client check
		// Find the page.
		body, ok := pages[r.URL.Path]
		// Unknown path.
		if !ok {
			// A normal "not found".
			http.NotFound(w, r)
			// Stop.
			return
		} // end of the path check
		// Send the page.
		_, _ = w.Write([]byte(body))
	}))
	// Stop it at the end of the test.
	t.Cleanup(srv.Close)
	// Point the reader at it, and restore the real address afterwards.
	old := ollamaSite
	// Use the fake.
	ollamaSite = srv.URL
	// Put the real address back.
	t.Cleanup(func() { ollamaSite = old })
	// The counter.
	return hits
} // end of fakeSite

// TestFetchSiteTagsAndErrors checks the tags fetch, a missing page, a bad name that never reaches the network, and an oversized page.
func TestFetchSiteTagsAndErrors(t *testing.T) {
	// A fake website with one tags page and one oversized page.
	hits := fakeSite(t, map[string]string{
		// A normal tags page.
		"/library/granite4/tags": tagEntry("granite4:1b-h", "1.6GB", "1M"),
		// A page above the limit.
		"/library/huge/tags": strings.Repeat("x", findMaxPage+10),
	})
	// A normal read.
	tags, err := fetchSiteTags(context.Background(), "granite4")
	// It must work and give the version.
	if err != nil || len(tags) != 1 || tags[0].Tag != "granite4:1b-h" || tags[0].SizeText != "1.6GB" {
		// Report.
		t.Fatalf("fetchSiteTags = %+v, %v", tags, err)
	} // end of the normal check
	// A model the website does not have.
	if _, err := fetchSiteTags(context.Background(), "nothere"); err == nil || !strings.Contains(err.Error(), "404") {
		// Report.
		t.Errorf("missing model: err = %v, want a 404 error", err)
	} // end of the missing check
	// An oversized page is refused.
	if _, err := fetchSiteTags(context.Background(), "huge"); err == nil || !strings.Contains(err.Error(), "larger") {
		// Report.
		t.Errorf("oversized page: err = %v", err)
	} // end of the size check
	// Remember the number of requests so far.
	before := atomic.LoadInt32(hits)
	// A bad name must not reach the network.
	if _, err := fetchSiteTags(context.Background(), "a/b;c"); err == nil {
		// Report.
		t.Error("a bad name was accepted")
	} // end of the bad-name check
	// No request was made for it.
	if atomic.LoadInt32(hits) != before {
		// Report.
		t.Error("a bad name reached the network")
	} // end of the network check
} // end of TestFetchSiteTagsAndErrors

// TestLiveSiteListUsesTheSavedAnswerForAnHour checks the one-hour reuse and the refresh after it.
func TestLiveSiteListUsesTheSavedAnswerForAnHour(t *testing.T) {
	// Start with an empty saved answer, and leave it empty afterwards.
	theListCache = listCache{}
	// Clear it again at the end.
	t.Cleanup(func() { theListCache = listCache{} })
	// A fake website with a small list page.
	hits := fakeSite(t, map[string]string{"/library": listEntry("alpha", "d", "tools")})
	// The fake clock.
	clock := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
	// A clock function that returns the current fake time.
	now := func() time.Time { return clock }
	// First call: a real read.
	m, at, err := liveSiteList(context.Background(), now)
	// It must work and say when it was read.
	if err != nil || len(m) != 1 || !at.Equal(clock) {
		// Report.
		t.Fatalf("first call = %+v, %v, %v", m, at, err)
	} // end of the first check
	// Thirty minutes later: the saved answer, with its original time, and no new request.
	clock = clock.Add(30 * time.Minute)
	// Ask again.
	_, at2, err := liveSiteList(context.Background(), now)
	// It must be the saved one.
	if err != nil || at2.Equal(clock) || atomic.LoadInt32(hits) != 1 {
		// Report.
		t.Fatalf("second call: at=%v err=%v hits=%d", at2, err, atomic.LoadInt32(hits))
	} // end of the second check
	// Two hours after the start: a fresh read.
	clock = clock.Add(90 * time.Minute)
	// Ask again.
	_, at3, err := liveSiteList(context.Background(), now)
	// It must be new.
	if err != nil || !at3.Equal(clock) || atomic.LoadInt32(hits) != 2 {
		// Report.
		t.Fatalf("third call: at=%v err=%v hits=%d", at3, err, atomic.LoadInt32(hits))
	} // end of the third check
} // end of TestLiveSiteListUsesTheSavedAnswerForAnHour

// TestLiveSiteListKeepsTheOldAnswerWhenTheWebsiteFails checks that a failed or changed page does not wipe the saved answer.
func TestLiveSiteListKeepsTheOldAnswerWhenTheWebsiteFails(t *testing.T) {
	// Start empty and leave empty.
	theListCache = listCache{}
	// Clear at the end.
	t.Cleanup(func() { theListCache = listCache{} })
	// A fake website whose list page is first good.
	pages := map[string]string{"/library": listEntry("alpha", "d", "tools")}
	// Start it.
	fakeSite(t, pages)
	// The fake clock.
	clock := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
	// The clock function.
	now := func() time.Time { return clock }
	// A good first read.
	if _, _, err := liveSiteList(context.Background(), now); err != nil {
		// Report.
		t.Fatalf("first read: %v", err)
	} // end of the first check
	// The website now changes its layout.
	pages["/library"] = "<html>redesigned</html>"
	// Two hours later the saved answer is too old, so a new read is tried.
	clock = clock.Add(2 * time.Hour)
	// Ask again.
	if _, _, err := liveSiteList(context.Background(), now); err != errLayout {
		// Report.
		t.Fatalf("changed layout: err = %v, want errLayout", err)
	} // end of the layout check
	// The old answer is still stored, so the caller can show it labelled with its date.
	if len(theListCache.models) != 1 || !theListCache.at.Equal(time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)) {
		// Report.
		t.Errorf("the saved answer was lost: %d models, read at %v", len(theListCache.models), theListCache.at)
	} // end of the stored check
} // end of TestLiveSiteListKeepsTheOldAnswerWhenTheWebsiteFails

// TestRealPagesIfProvided reads the real pages saved by script 90, when the folder is named in FINDLLM_PAGES; it is skipped otherwise, so no test needs the pages and none are stored in the project.
func TestRealPagesIfProvided(t *testing.T) {
	// The folder of the saved pages.
	dir := os.Getenv("FINDLLM_PAGES")
	// Not given: skip.
	if dir == "" {
		// Say why.
		t.Skip("FINDLLM_PAGES is not set")
	} // end of the skip
	// Read the list page.
	list, err := os.ReadFile(filepath.Join(dir, "_listing.model.html"))
	// It must exist.
	if err != nil {
		// Report.
		t.Fatalf("list page: %v", err)
	} // end of the read check
	// Parse it.
	models, err := parseSiteList(string(list))
	// It must work.
	if err != nil || len(models) < 100 {
		// Report.
		t.Fatalf("real list page: %d models, %v", len(models), err)
	} // end of the parse check
	// Find the two helper models.
	var granite, qwen *siteModel
	// Look at each.
	for i := range models {
		// Granite.
		if models[i].Name == "granite4" {
			// Keep it.
			granite = &models[i]
		} // end of granite
		// Qwen3.
		if models[i].Name == "qwen3" {
			// Keep it.
			qwen = &models[i]
		} // end of qwen
	} // end of the look
	// Both must be there.
	if granite == nil || qwen == nil {
		// Report.
		t.Fatal("granite4 or qwen3 is missing from the real list page")
	} // end of the presence check
	// Granite lists a 1b size and the tools ability.
	if !contains(granite.Sizes, "1b") || !contains(granite.Abilities, "tools") {
		// Report.
		t.Errorf("granite4 = %+v", *granite)
	} // end of the granite check
	// Read the Granite tags page.
	tagsPage, err := os.ReadFile(filepath.Join(dir, "granite4.tags.html"))
	// It must exist.
	if err != nil {
		// Report.
		t.Fatalf("tags page: %v", err)
	} // end of the read check
	// Parse it.
	tags, err := parseSiteTags(string(tagsPage))
	// It must work.
	if err != nil {
		// Report.
		t.Fatalf("real tags page: %v", err)
	} // end of the parse check
	// The version chosen as the default helper must be there with its size.
	found := false
	// Look at each version.
	for _, tg := range tags {
		// The chosen one.
		if tg.Tag == "granite4:1b-h" && tg.SizeText == "1.6GB" && tg.Context == "1M" {
			// Found it.
			found = true
		} // end of the compare
	} // end of the look
	// It must be found.
	if !found {
		// Report.
		t.Errorf("granite4:1b-h with 1.6GB and 1M was not found in %+v", tags)
	} // end of the found check
} // end of TestRealPagesIfProvided

// contains reports whether the list holds the word.
func contains(list []string, want string) bool {
	// Look at each.
	for _, s := range list {
		// A match.
		if s == want {
			// Found.
			return true
		} // end of the match
	} // end of the loop
	// Not found.
	return false
} // end of contains
