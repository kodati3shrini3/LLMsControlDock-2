// Package main tells Go that this folder builds into a runnable program.
package main

import ( // import lists the standard-library packages this file uses.
	// bytes catches the printed report.
	"bytes"
	// net/http makes the fake sites.
	"net/http"
	// httptest runs the fake sites.
	"net/http/httptest"
	// strings searches the report.
	"strings"
	// sync/atomic counts requests safely.
	"sync/atomic"
	// testing is Go's test framework.
	"testing"
) // end of imports

// fakeSites starts one fake site with a path for each case: ok, gone, moved (to ok), loop and refusal.
func fakeSites(t *testing.T, hits *atomic.Int32, agents *[]string) *httptest.Server {
	// Mark this as a helper.
	t.Helper()
	// The routes.
	mux := http.NewServeMux()
	// A page that answers.
	mux.HandleFunc("/ok", func(w http.ResponseWriter, r *http.Request) {
		// Count the request and note who asked and how.
		hits.Add(1)
		// Remember the agent and the method.
		*agents = append(*agents, r.Method+" "+r.Header.Get("User-Agent"))
		// Answer.
		w.Write([]byte("hello"))
	}) // end of ok
	// A page that is gone.
	mux.HandleFunc("/gone", func(w http.ResponseWriter, r *http.Request) {
		// 404.
		http.NotFound(w, r)
	}) // end of gone
	// A page that moved to /ok.
	mux.HandleFunc("/moved", func(w http.ResponseWriter, r *http.Request) {
		// Permanent redirect.
		http.Redirect(w, r, "/ok", http.StatusMovedPermanently)
	}) // end of moved
	// A page that redirects to itself for ever.
	mux.HandleFunc("/loop", func(w http.ResponseWriter, r *http.Request) {
		// Redirect to itself.
		http.Redirect(w, r, "/loop", http.StatusFound)
	}) // end of loop
	// A site that refuses programs.
	mux.HandleFunc("/refuse", func(w http.ResponseWriter, r *http.Request) {
		// 403.
		w.WriteHeader(http.StatusForbidden)
	}) // end of refuse
	// Start the server and stop it at the end.
	srv := httptest.NewServer(mux)
	// Cleanup.
	t.Cleanup(srv.Close)
	// Hand it back.
	return srv
} // end of fakeSites

// TestCheckLinksReportsEachCase checks success, a missing page, a redirect, a redirect loop, a refusal and a dead address.
func TestCheckLinksReportsEachCase(t *testing.T) {
	// Counters.
	var hits atomic.Int32
	// Who asked.
	var agents []string
	// The fake site.
	srv := fakeSites(t, &hits, &agents)
	// A closed port for the "no answer" case.
	dead := httptest.NewServer(http.NotFoundHandler())
	// Close it at once, so nothing listens there.
	deadURL := dead.URL
	// Close.
	dead.Close()
	// The references.
	refs := []reference{{N: 1, URL: srv.URL + "/ok"}, {N: 2, URL: srv.URL + "/gone"}, {N: 3, URL: srv.URL + "/moved"}, {N: 4, URL: srv.URL + "/loop"}, {N: 5, URL: srv.URL + "/refuse"}, {N: 6, URL: deadURL + "/x"}}
	// Run it.
	var out bytes.Buffer
	// The exit code.
	code := runCheckLinks(refs, newLinkClient(), "1 January 2026", &out)
	// The report.
	text := out.String()
	// At least one failed, so the code is 1.
	if code != 1 {
		// Report the problem.
		t.Errorf("exit code %d, want 1\n%s", code, text)
	} // end of the code check
	// What each line must say.
	for _, want := range []string{"[1] OK    200  " + srv.URL + "/ok", "[2] FAIL  404  ", "[3] OK    200  ", "moved to " + srv.URL + "/ok", "[4] FAIL  --  ", "more than 5 redirects", "[5] FAIL  403  ", "[6] FAIL  --  ", "2 of 6 addresses answered with a success code", "last read by hand on 1 January 2026", "A 403 or 429 can mean the site refuses programs", "nothing was changed by this command"} {
		// Look for it.
		if !strings.Contains(text, want) {
			// Report the gap.
			t.Errorf("report lacks %q\n%s", want, text)
		} // end of the check
	} // end of the loop
	// Every request was a plain GET with our own name, nothing else.
	for _, a := range agents {
		// Check it.
		if a != "GET OllamaControlCenter-check-links" {
			// Report it.
			t.Errorf("unexpected request %q", a)
		} // end of the check
	} // end of the loop
} // end of TestCheckLinksReportsEachCase

// TestCheckLinksAllGood checks the exit code 0 and that no advice is printed when everything answers.
func TestCheckLinksAllGood(t *testing.T) {
	// Counters.
	var hits atomic.Int32
	// Who asked.
	var agents []string
	// The fake site.
	srv := fakeSites(t, &hits, &agents)
	// Two good references.
	refs := []reference{{N: 1, URL: srv.URL + "/ok"}, {N: 2, URL: srv.URL + "/ok"}}
	// Run it.
	var out bytes.Buffer
	// The exit code.
	code := runCheckLinks(refs, newLinkClient(), "x", &out)
	// Success.
	if code != 0 {
		// Report the problem.
		t.Errorf("exit code %d, want 0", code)
	} // end of the code check
	// No advice.
	if strings.Contains(out.String(), "For each FAIL") || !strings.Contains(out.String(), "2 of 2 addresses") {
		// Report the problem.
		t.Errorf("unexpected report: %s", out.String())
	} // end of the text check
	// Two requests, no more.
	if hits.Load() != 2 {
		// Report the problem.
		t.Errorf("%d requests, want 2", hits.Load())
	} // end of the count check
} // end of TestCheckLinksAllGood

// TestRealReferencesAreWellFormed checks the six real addresses are https, unique and numbered 1 to n, without opening them (the tests never touch the internet).
func TestRealReferencesAreWellFormed(t *testing.T) {
	// Seen addresses.
	seen := map[string]bool{}
	// Go through the list.
	for i, r := range compareReferences {
		// Numbered without gaps.
		if r.N != i+1 {
			// Report it.
			t.Errorf("reference %d has number %d", i+1, r.N)
		} // end of the number check
		// Secure address only.
		if !strings.HasPrefix(r.URL, "https://") {
			// Report it.
			t.Errorf("reference %d is not https: %s", r.N, r.URL)
		} // end of the scheme check
		// No duplicates.
		if seen[r.URL] {
			// Report it.
			t.Errorf("duplicate address %s", r.URL)
		} // end of the duplicate check
		// Remember it.
		seen[r.URL] = true
	} // end of the loop
} // end of TestRealReferencesAreWellFormed
