// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this test file uses.
	// net/http gives the status codes and the request method names.
	"net/http"
	// net/url builds the form values.
	"net/url"
	// strings searches the page text.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// updatedSpan writes the update words the way the list page writes them, inside one entry.
func updatedSpan(words string) string {
	// The clock icon, the word Updated and the rounded age, as in the real markup.
	return "<span class=\"flex items-center\">\n<svg viewBox=\"0 0 24 24\"><path d=\"M12 6v6\"></path></svg>\n<span class=\"hidden sm:flex\">Updated&nbsp;</span>\n<span >" + words + "</span>\n</span>\n"
} // end of updatedSpan

// listEntryUpdated writes a list entry like listEntry, with the update words added before the end of its link; empty words leave the entry without them.
func listEntryUpdated(name, words string, labels ...string) string {
	// The normal entry.
	e := listEntry(name, "An invented model.", labels...)
	// No words: as it is.
	if words == "" {
		// Unchanged.
		return e
	} // end of the empty check
	// Put the words in before the end of the link.
	return strings.Replace(e, "</a>", updatedSpan(words)+"</a>", 1)
} // end of listEntryUpdated

// namesInOrder lists the names of models in the order given, joined by commas.
func namesInOrder(ms []siteModel) string {
	// The names.
	var out []string
	// Each model.
	for _, m := range ms {
		// One name.
		out = append(out, m.Name)
	} // end of the loop
	// As text.
	return strings.Join(out, ",")
} // end of namesInOrder

// TestParseSiteListReadsTheUpdateWords checks that the list reader keeps the update words of each model, leaves them empty when the page has none, and still reads the download count.
func TestParseSiteListReadsTheUpdateWords(t *testing.T) {
	// A page with one entry that has update words and one that has none.
	page := "<html><ul>" + listEntryUpdated("with", "6 days ago", "tools", "8b") + listEntryUpdated("without", "", "tools", "8b") + "</ul></html>"
	// Read it.
	models, err := parseSiteList(page)
	// A failure means the reader broke.
	if err != nil || len(models) != 2 {
		// Stop.
		t.Fatalf("parseSiteList: %v, %d models", err, len(models))
	} // end of the read check
	// The first model carries the words, and its download count is still read.
	if models[0].Updated != "6 days ago" || models[0].Pulls != "1.5M" {
		// Report.
		t.Errorf("first model: updated %q, pulls %q", models[0].Updated, models[0].Pulls)
	} // end of the first check
	// The second has no words.
	if models[1].Updated != "" {
		// Report.
		t.Errorf("second model: updated %q, want empty", models[1].Updated)
	} // end of the second check
} // end of TestParseSiteListReadsTheUpdateWords

// TestUpdatedHoursReadsTheWords checks how the update words become hours, and that unreadable words give -1.
func TestUpdatedHoursReadsTheWords(t *testing.T) {
	// Words and the hours they stand for (a day is 24, a week 168, a month 730, a year 8760 hours).
	for words, want := range map[string]int64{"an hour ago": 1, "6 days ago": 144, "1 week ago": 168, "2 weeks ago": 336, "1 month ago": 730, "3 months ago": 2190, "1 year ago": 8760, "": -1, "soon": -1, "just now": -1} {
		// Convert.
		if got := updatedHours(words); got != want {
			// Report.
			t.Errorf("updatedHours(%q) = %d, want %d", words, got, want)
		} // end of the check
	} // end of the loop
} // end of TestUpdatedHoursReadsTheWords

// TestUpdatedOrder checks the order Updated: new to old for local and cloud-only models: the more recent first, equal words by name, no words last.
func TestUpdatedOrder(t *testing.T) {
	// Local models with different update words, two with the same words, and one without words; the cloud-only ones are separate.
	models := []siteModel{
		{Name: "bravo", Updated: "1 month ago", Sizes: []string{"8b"}},
		{Name: "alpha", Updated: "1 month ago", Sizes: []string{"8b"}},
		{Name: "charlie", Updated: "6 days ago", Sizes: []string{"8b"}},
		{Name: "delta", Updated: "2 years ago", Sizes: []string{"8b"}},
		{Name: "echo", Sizes: []string{"8b"}},
		{Name: "foxtrot", Updated: "1 year ago", Sizes: []string{"8b"}},
		{Name: "zeta", Updated: "1 week ago", Cloud: true},
		{Name: "yankee", Updated: "1 week ago", Cloud: true},
		{Name: "xray", Updated: "1 month ago", Cloud: true},
	}
	// The local models.
	local, _, _ := findCandidates(models, findSelection{Sort: "updated"})
	// Check the order.
	if got := namesInOrder(local); got != "charlie,alpha,bravo,foxtrot,delta,echo" {
		// Report.
		t.Errorf("local updated order %q", got)
	} // end of the local check
	// The cloud-only models.
	cloud, _ := findCloudModels(models, findSelection{Sort: "updated"})
	// Check the order.
	if got := namesInOrder(cloud); got != "yankee,zeta,xray" {
		// Report.
		t.Errorf("cloud updated order %q", got)
	} // end of the cloud check
	// A saved copy made before the words existed: nothing has words, so the order is by name.
	old := []siteModel{{Name: "b", Sizes: []string{"8b"}}, {Name: "a", Sizes: []string{"8b"}}}
	// Order them.
	oldOrdered, _, _ := findCandidates(old, findSelection{Sort: "updated"})
	// Check it.
	if got := namesInOrder(oldOrdered); got != "a,b" {
		// Report.
		t.Errorf("order without any words %q, want a,b", got)
	} // end of the old copy check
} // end of TestUpdatedOrder

// TestResortViewsByUpdated checks the re-sort of models already shown, with and without the fitting ones kept first.
func TestResortViewsByUpdated(t *testing.T) {
	// A list: alpha is the oldest but fits; bravo and charlie do not fit, bravo is the most recent.
	list := func() []resultView {
		// A fresh copy each time.
		return []resultView{
			{Name: "alpha", Updated: "2 years ago", FitCount: 1},
			{Name: "charlie", Updated: "1 month ago"},
			{Name: "bravo", Updated: "1 week ago"},
		}
	} // end of list
	// The names of a list, in order.
	names := func(l []resultView) string {
		// Collect them.
		var out []string
		// Each view.
		for _, v := range l {
			// One name.
			out = append(out, v.Name)
		} // end of the loop
		// As text.
		return strings.Join(out, ",")
	} // end of names
	// With fit first: the fitting model stays ahead.
	l := list()
	// Sort.
	resortViews(l, "updated", true)
	// Check.
	if got := names(l); got != "alpha,bravo,charlie" {
		// Report.
		t.Errorf("updated, fit first: %q", got)
	} // end of the check
	// Without fit first (the cloud-only models): purely by the words.
	l = list()
	// Sort.
	resortViews(l, "updated", false)
	// Check.
	if got := names(l); got != "bravo,charlie,alpha" {
		// Report.
		t.Errorf("updated, no fit: %q", got)
	} // end of the check
} // end of TestResortViewsByUpdated

// TestFindSummaryNamesTheOrder checks that the sentence above a cut list says which models are shown, as the chosen order decides.
func TestFindSummaryNamesTheOrder(t *testing.T) {
	// Each order and the phrase it must produce.
	for order, want := range map[string]string{"downloads": "the 10 most downloaded are shown", "name": "the first 10 by name are shown", "updated": "the 10 most recently updated are shown"} {
		// Build it.
		got := findSummary(10, 42, 0, 0, order, "2026-11-19 09:00:00 CET (UTC+01:00)")
		// The phrase must be there.
		if !strings.Contains(got, want) {
			// Report.
			t.Errorf("order %q: %q lacks %q", order, got, want)
		} // end of the check
	} // end of the loop
} // end of TestFindSummaryNamesTheOrder

// TestUpdatedNote checks the note under the results: only for the Updated order, silent when nothing is listed, honest when no model has words.
func TestUpdatedNote(t *testing.T) {
	// Another order: no note.
	if n := updatedNote("name", []resultView{{Name: "a", Updated: "1 week ago"}}); n != "" {
		// Report.
		t.Errorf("name order note %q, want none", n)
	} // end of the other-order check
	// Nothing listed: no note.
	if n := updatedNote("updated", nil, nil); n != "" {
		// Report.
		t.Errorf("empty list note %q, want none", n)
	} // end of the empty check
	// Words present (in the cloud list too): the usual explanation, naming the rounding and the name order.
	n := updatedNote("updated", []resultView{{Name: "a"}}, []resultView{{Name: "b", Updated: "1 week ago"}})
	// Check it.
	for _, want := range []string{"update words ollama.com shows", "rounded", "name order", "comes last"} {
		// The phrase.
		if !strings.Contains(n, want) {
			// Report.
			t.Errorf("note %q lacks %q", n, want)
		} // end of the phrase check
	} // end of the phrase loop
	// No model has words: the note says so.
	if n := updatedNote("updated", []resultView{{Name: "a"}}); !strings.Contains(n, "No update words are available") {
		// Report.
		t.Errorf("no-words note %q", n)
	} // end of the no-words check
} // end of TestUpdatedNote

// TestFindSearchSortsByUpdated checks the whole page: the choice exists, a search with it lists the most recently updated first, the choice is kept, the note appears, and the re-sort of kept results works.
func TestFindSearchSortsByUpdated(t *testing.T) {
	// The saved library list goes to a throw-away folder, never to the real data folder.
	isolateFindData(t)
	// Start with an empty in-memory list.
	theListCache = listCache{}
	// Clear it again at the end.
	t.Cleanup(func() { theListCache = listCache{} })
	// Three models: the most downloaded first in the list is the oldest update, so the two orders differ.
	list := listEntryUpdated("aaa", "2 years ago", "tools", "8b") + listEntryUpdated("bbb", "1 week ago", "tools", "8b") + listEntryUpdated("ccc", "1 month ago", "tools", "8b")
	// The pages.
	fakeSite(t, map[string]string{
		"/library":          "<html><ul>" + list + "</ul></html>",
		"/library/aaa/tags": tagEntry("aaa:8b", "5GB", "32K"),
		"/library/bbb/tags": tagEntry("bbb:8b", "5GB", "32K"),
		"/library/ccc/tags": tagEntry("ccc:8b", "5GB", "32K"),
	})
	// The rig.
	rig := newThemeRig(t)
	// The starting page offers the choice, first in the list and selected: it is the default.
	_, _, form := get(t, rig.h, http.MethodGet, "/findllm")
	// Check it.
	if !strings.Contains(form, `<option value="updated" selected>Updated: new to old</option><option value="downloads">Most downloaded</option><option value="name">Name A to Z</option>`) {
		// Report.
		t.Error("the starting page does not offer Updated: new to old first and selected")
	} // end of the choice check
	// A search with the new order.
	status, body := postFind(t, rig, url.Values{"token": {rig.token}, "sort": {"updated"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
	// It must work.
	if status != http.StatusOK {
		// Stop.
		t.Fatalf("status %d: %s", status, body)
	} // end of the status check
	// The position of a model's heading in the page.
	at := func(page, name string) int { return strings.Index(page, ">"+name+"<span class=\"sr-only\">") }
	// Each model must be listed.
	if at(body, "aaa") < 0 || at(body, "bbb") < 0 || at(body, "ccc") < 0 {
		// Stop.
		t.Fatal("a model is missing from the results")
	} // end of the listing check
	// The order: bbb (1 week), ccc (1 month), aaa (2 years).
	if !(at(body, "bbb") < at(body, "ccc") && at(body, "ccc") < at(body, "aaa")) {
		// Report.
		t.Error("the results are not in the order bbb, ccc, aaa")
	} // end of the order check
	// The choice is kept, and the note is shown.
	if !strings.Contains(body, `<option value="updated" selected>Updated: new to old</option>`) || strings.Contains(body, `<option value="downloads" selected>`) || !strings.Contains(body, "Models are ordered by the update words ollama.com shows") {
		// Report.
		t.Error("the choice is not kept after the search, or the note is missing")
	} // end of the kept check
	// A search that sends no choice at all uses the default, the update order, and shows the note.
	_, dflt := postFind(t, rig, url.Values{"token": {rig.token}, "disk_gb": {"100"}, "mem_gb": {"64"}})
	// Check it.
	if !(at(dflt, "bbb") > 0 && at(dflt, "bbb") < at(dflt, "ccc") && at(dflt, "ccc") < at(dflt, "aaa")) || !strings.Contains(dflt, "Models are ordered by the update words ollama.com shows") {
		// Report.
		t.Error("a search without a sort choice is not in the update order with its note")
	} // end of the default check
	// Re-sort the kept results by name: aaa, bbb, ccc, and the note goes away.
	res := post(t, rig.h, "/findllm/resort", url.Values{"token": {rig.token}, "sort": {"name"}}, fromThisPage)
	// Check the redirect.
	if res.StatusCode != http.StatusSeeOther {
		// Report.
		t.Fatalf("resort status %d", res.StatusCode)
	} // end of the redirect check
	// The page again.
	_, _, byName := get(t, rig.h, http.MethodGet, "/findllm")
	// Check it.
	if !(at(byName, "aaa") < at(byName, "bbb") && at(byName, "bbb") < at(byName, "ccc")) || strings.Contains(byName, "Models are ordered by the update words") {
		// Report.
		t.Error("the re-sort by name did not give aaa, bbb, ccc without the note")
	} // end of the name check
	// Re-sort the kept results by the update words again.
	res = post(t, rig.h, "/findllm/resort", url.Values{"token": {rig.token}, "sort": {"updated"}}, fromThisPage)
	// Check the redirect.
	if res.StatusCode != http.StatusSeeOther {
		// Report.
		t.Fatalf("resort status %d", res.StatusCode)
	} // end of the redirect check
	// The page again.
	_, _, again := get(t, rig.h, http.MethodGet, "/findllm")
	// Check it.
	if !(at(again, "bbb") < at(again, "ccc") && at(again, "ccc") < at(again, "aaa")) || !strings.Contains(again, `<option value="updated" selected>`) {
		// Report.
		t.Error("the re-sort by the update words did not give bbb, ccc, aaa with the choice kept")
	} // end of the updated check
} // end of TestFindSearchSortsByUpdated

// TestSortOrderUsesTheUpdateOrderUnlessAskedOtherwise checks that only the exact words name and downloads change the order; an empty or unknown text is the default, Updated: new to old.
func TestSortOrderUsesTheUpdateOrderUnlessAskedOtherwise(t *testing.T) {
	// Each text and the order it gives.
	for text, want := range map[string]string{"": "updated", "updated": "updated", "nonsense": "updated", "Name": "updated", "name": "name", "downloads": "downloads"} {
		// Convert.
		if got := sortOrder(text); got != want {
			// Report.
			t.Errorf("sortOrder(%q) = %q, want %q", text, got, want)
		} // end of the check
	} // end of the loop
} // end of TestSortOrderUsesTheUpdateOrderUnlessAskedOtherwise
