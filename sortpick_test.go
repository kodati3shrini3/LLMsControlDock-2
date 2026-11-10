// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages the tests use.
	// net/http gives the method names and status codes.
	"net/http"
	// net/url builds the form values.
	"net/url"
	// strings searches the page text.
	"strings"
	// testing is Go's test framework.
	"testing"
) // end of imports

// TestResortViewsOrder checks the new order of shown models for both choices, with and without the fit-first grouping.
func TestResortViewsOrder(t *testing.T) {
	// The names of a list, in order.
	names := func(l []resultView) string {
		// Collect them.
		var out []string
		// Each model.
		for _, v := range l {
			// One name.
			out = append(out, v.Name)
		} // end of the loop
		// As text.
		return strings.Join(out, ",")
	} // end of names
	// A list: bravo and alpha fit, charlie does not but has the most downloads, delta ties with alpha.
	list := func() []resultView {
		// A fresh copy each time.
		return []resultView{
			{Name: "charlie", Pulls: "12M"},
			{Name: "bravo", Pulls: "2M", FitCount: 1},
			{Name: "delta", Pulls: "900K", FitCount: 1},
			{Name: "alpha", Pulls: "900K", FitCount: 1},
		}
	} // end of list
	// Most downloaded with fit first: the fitting ones by downloads (ties by name), then the rest.
	l := list()
	// Sort.
	resortViews(l, false, true)
	// Check.
	if got := names(l); got != "bravo,alpha,delta,charlie" {
		// Report.
		t.Errorf("downloads, fit first: %q", got)
	} // end of the check
	// Name A to Z with fit first.
	l = list()
	// Sort.
	resortViews(l, true, true)
	// Check.
	if got := names(l); got != "alpha,bravo,delta,charlie" {
		// Report.
		t.Errorf("name, fit first: %q", got)
	} // end of the check
	// Cloud models have no fit grouping: by downloads, then by name.
	l = list()
	// Sort.
	resortViews(l, false, false)
	// Check.
	if got := names(l); got != "charlie,bravo,alpha,delta" {
		// Report.
		t.Errorf("downloads, no fit: %q", got)
	} // end of the check
	// And by name.
	resortViews(l, true, false)
	// Check.
	if got := names(l); got != "alpha,bravo,charlie,delta" {
		// Report.
		t.Errorf("name, no fit: %q", got)
	} // end of the check
} // end of TestResortViewsOrder

// TestFindResortKeepsTheSearch checks the whole round trip: the choice carries the re-sort address and the script only when models are listed, a wrong token is refused, a re-sort changes the kept order choice without a new reading of the library, and without a kept search it just goes back to the page.
func TestFindResortKeepsTheSearch(t *testing.T) {
	// The saved library list goes to a throw-away folder.
	isolateFindData(t)
	// Start with an empty saved list.
	theListCache = listCache{}
	// Clear it again at the end.
	t.Cleanup(func() { theListCache = listCache{} })
	// A fake library, with a counter of the pages read.
	hits := fakeSite(t, findTestPages())
	// The rig (a new program: nothing is kept).
	rig := newThemeRig(t)
	// Before any search: no re-sort address, no script.
	_, _, first := get(t, rig.h, http.MethodGet, "/findllm")
	// Check.
	if strings.Contains(first, "data-resort") || strings.Contains(first, "/sortpick.js") {
		// Report.
		t.Error("the starting page carries the re-sort address or script")
	} // end of the check
	// A re-sort with no kept search goes back to the page and changes nothing.
	res := post(t, rig.h, "/findllm/resort", url.Values{"token": {rig.token}, "sort": {"name"}}, fromThisPage)
	// Check.
	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/findllm#sortby" {
		// Report.
		t.Errorf("resort without a search = %d to %q", res.StatusCode, res.Header.Get("Location"))
	} // end of the check
	// A search with the default order.
	_, found := postFind(t, rig, url.Values{"token": {rig.token}, "disk_gb": {"100"}, "mem_gb": {"64"}})
	// The results page has the re-sort address and the script, once.
	if !strings.Contains(found, `data-resort="/findllm/resort"`) || strings.Count(found, `<script src="/sortpick.js" defer></script>`) != 1 {
		// Report.
		t.Fatal("the results page lacks the re-sort address or the script")
	} // end of the check
	// The script must be allowed by the page's security policy.
	r2 := post(t, rig.h, "/findllm/search", url.Values{"token": {rig.token}}, fromThisPage)
	// Check.
	if csp := r2.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe-inline") {
		// Report.
		t.Errorf("policy on the results page: %q", csp)
	} // end of the check
	// Count the library reads so far.
	before := *hits
	// A wrong token is refused.
	if bad := post(t, rig.h, "/findllm/resort", url.Values{"token": {"wrong"}, "sort": {"name"}}, fromThisPage); bad.StatusCode != http.StatusForbidden {
		// Report.
		t.Errorf("resort with a wrong token = %d, want 403", bad.StatusCode)
	} // end of the check
	// Still the default order after the refusal.
	if _, _, still := get(t, rig.h, http.MethodGet, "/findllm"); !strings.Contains(still, `<option value="downloads" selected>`) {
		// Report.
		t.Error("a refused re-sort changed the order choice")
	} // end of the check
	// A real re-sort to Name A to Z.
	res = post(t, rig.h, "/findllm/resort", url.Values{"token": {rig.token}, "sort": {"name"}}, fromThisPage)
	// It redirects back to the Sort by choice.
	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/findllm#sortby" {
		// Report.
		t.Errorf("resort = %d to %q", res.StatusCode, res.Header.Get("Location"))
	} // end of the check
	// The page now shows Name A to Z and still the results.
	_, _, named := get(t, rig.h, http.MethodGet, "/findllm")
	// Check.
	if !strings.Contains(named, `<option value="name" selected>Name A to Z</option>`) || !strings.Contains(named, "Models found") {
		// Report.
		t.Error("after the re-sort the page lacks the new choice or the results")
	} // end of the check
	// Back to the default order.
	post(t, rig.h, "/findllm/resort", url.Values{"token": {rig.token}}, fromThisPage)
	// Check.
	if _, _, back := get(t, rig.h, http.MethodGet, "/findllm"); !strings.Contains(back, `<option value="downloads" selected>`) {
		// Report.
		t.Error("the default order did not come back")
	} // end of the check
	// Nothing was read from the library again.
	if *hits != before {
		// Report.
		t.Errorf("library pages read: %d before, %d after the re-sorts", before, *hits)
	} // end of the check
	// A search with no match has no re-sort address.
	_, none := postFind(t, rig, url.Values{"token": {rig.token}, "ab_embedding": {"on"}, "ab_tools": {"on"}, "disk_gb": {"100"}, "mem_gb": {"64"}})
	// Check.
	if strings.Contains(none, "data-resort") || strings.Contains(none, "/sortpick.js") {
		// Report.
		t.Error("a page with no models carries the re-sort address or script")
	} // end of the check
} // end of TestFindResortKeepsTheSearch

// TestSortPickScriptIsServedAndHarmless checks the script is sent as JavaScript, only on GET, and does nothing but send the page's own form to the re-sort address.
func TestSortPickScriptIsServedAndHarmless(t *testing.T) {
	// A rig.
	rig := newThemeRig(t)
	// Fetch the script.
	status, header, body := get(t, rig.h, http.MethodGet, "/sortpick.js")
	// Found and typed as JavaScript.
	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/javascript") || !strings.Contains(body, "data-resort") {
		// Report.
		t.Fatalf("status %d, type %q", status, header.Get("Content-Type"))
	} // end of the check
	// Only GET is allowed.
	if res := post(t, rig.h, "/sortpick.js", url.Values{}, fromThisPage); res.StatusCode != http.StatusMethodNotAllowed {
		// Report.
		t.Errorf("POST /sortpick.js = %d, want 405", res.StatusCode)
	} // end of the check
	// Nothing that sends data away, runs text as code, writes markup or opens an address.
	for _, bad := range []string{"fetch(", "XMLHttpRequest", "sendBeacon", "WebSocket", "eval(", "new Function", "innerHTML", "outerHTML", "document.write", "http://", "https://", "location", "import("} {
		// Present.
		if strings.Contains(body, bad) {
			// Report.
			t.Errorf("the sort script must not contain %q", bad)
		} // end of the check
	} // end of the loop
	// Every code line carries a comment on the line above it or ends a block.
	lines := strings.Split(body, "\n")
	// Check from the second line.
	for i := 1; i < len(lines); i++ {
		// The trimmed line.
		l := strings.TrimSpace(lines[i])
		// Blank lines, comments and lines that close a block need nothing.
		if l == "" || strings.HasPrefix(l, "//") || strings.HasPrefix(l, "}") {
			// Fine.
			continue
		} // end of the skip check
		// The line above must be a comment.
		if !strings.HasPrefix(strings.TrimSpace(lines[i-1]), "//") {
			// Report.
			t.Errorf("sortpick.js line %d has no comment above it: %q", i+1, l)
		} // end of the comment check
	} // end of the line loop
} // end of TestSortPickScriptIsServedAndHarmless
