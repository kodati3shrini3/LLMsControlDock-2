// Package main tells Go that this test file belongs to the same program as unload.go.
package main

import ( // import lists the packages this test file uses.
	// io reads request bodies in the fake Ollama.
	"io"
	// net/http provides requests and status codes.
	"net/http"
	// net/http/httptest records replies and runs the fake Ollama.
	"net/http/httptest"
	// net/url builds form data.
	"net/url"
	// regexp finds the token in the page.
	"regexp"
	// strings searches the page text.
	"strings"
	// sync protects the fake's records, because the server runs in its own goroutine.
	"sync"
	// testing is Go's built-in test framework.
	"testing"
	// time shortens the waiting time in the tests.
	"time"
) // end of imports

// unloadFake is a fake Ollama that remembers what it was asked and can pretend to unload models.
type unloadFake struct {
	// mu protects every field below.
	mu sync.Mutex
	// loaded is the list of names that /api/ps reports.
	loaded []string
	// calls records "path body" for every POST.
	calls []string
	// generateStatus is the status that /api/generate answers (200 unless a test changes it).
	generateStatus int
	// ignore makes the fake accept unload requests without actually unloading (a busy model).
	ignore bool
} // end of unloadFake

// start runs the fake as a server and returns it.
func (f *unloadFake) start(t *testing.T) *httptest.Server {
	// Mark this as a helper.
	t.Helper()
	// Default to a working generate.
	if f.generateStatus == 0 {
		// Status 200.
		f.generateStatus = http.StatusOK
	} // end of the default
	// Start the server.
	return fakeOllama(t, func(w http.ResponseWriter, r *http.Request) {
		// One request at a time.
		f.mu.Lock()
		// Release when this request is done.
		defer f.mu.Unlock()
		// Pick the reply by path.
		switch r.URL.Path {
		// The version check.
		case "/api/version":
			// A valid version.
			w.Write([]byte(`{"version":"0.34.4"}`))
		// The installed list: two models.
		case "/api/tags":
			// Two models, one of them an embedding model.
			w.Write([]byte(`{"models":[{"name":"alpha:1b","size":1000,"details":{"family":"llama"},"capabilities":["completion"]},{"name":"embed:1b","size":2000,"details":{"family":"bert"},"capabilities":["embedding"]}]}`))
		// The loaded list.
		case "/api/ps":
			// Build the list from the fake's state.
			parts := []string{}
			// Every loaded name.
			for _, n := range f.loaded {
				// One entry with an expiry far in the future.
				parts = append(parts, `{"name":"`+n+`","size":5,"expires_at":"2099-01-01T00:00:00Z"}`)
			} // end of the loop
			// Send the list.
			w.Write([]byte(`{"models":[` + strings.Join(parts, ",") + `]}`))
		// The two unload requests.
		case "/api/generate", "/api/embed":
			// Read the body.
			b, _ := io.ReadAll(r.Body)
			// Record the call.
			f.calls = append(f.calls, r.URL.Path+" "+string(b))
			// A refusal from generate (an embedding model) is what a real Ollama gives.
			if r.URL.Path == "/api/generate" && f.generateStatus != http.StatusOK {
				// Send the chosen status.
				w.WriteHeader(f.generateStatus)
				// Stop here.
				return
			} // end of the refusal
			// A working fake really unloads.
			if !f.ignore {
				// Empty the loaded list.
				f.loaded = nil
			} // end of the unload
			// Accept.
			w.Write([]byte(`{}`))
		// Anything else.
		default:
			// Not found.
			http.NotFound(w, r)
		} // end of the switch
	}) // end of the server
} // end of start

// callCount says how many unload requests the fake has received.
func (f *unloadFake) callCount() int {
	// One at a time.
	f.mu.Lock()
	// Release at the end.
	defer f.mu.Unlock()
	// The number.
	return len(f.calls)
} // end of callCount

// unloadRig builds a handler on top of the fake and finds the page token.
func unloadRig(t *testing.T, f *unloadFake) themeRig {
	// Mark this as a helper.
	t.Helper()
	// Short waiting, so the tests stay quick.
	old := unloadVerifyWait
	// Restore it afterwards.
	t.Cleanup(func() { unloadVerifyWait = old })
	// Half a second is plenty for a fake.
	unloadVerifyWait = 500 * time.Millisecond
	// Start the fake.
	srv := f.start(t)
	// Build the handler once, because the token belongs to one handler.
	h := handlerFor(t, srv.URL)
	// Fetch the page.
	_, _, body := get(t, h, http.MethodGet, "/")
	// Find the first hidden token field.
	m := regexp.MustCompile(`name="token" value="([0-9a-f]{32})"`).FindStringSubmatch(body)
	// The page must carry a token.
	if m == nil {
		// Stop the test.
		t.Fatalf("no token found in the page")
	} // end of the token check
	// Hand back the pair.
	return themeRig{h: h, token: m[1]}
} // end of unloadRig

// bodyOf reads a recorded reply.
func bodyOf(res *http.Response) string {
	// Read it all.
	b, _ := io.ReadAll(res.Body)
	// As text.
	return string(b)
} // end of bodyOf

// TestUnloadButtonOnlyOnLoadedRows checks the button appears for the loaded model and nowhere else.
func TestUnloadButtonOnlyOnLoadedRows(t *testing.T) {
	// A fake with one loaded model.
	f := &unloadFake{loaded: []string{"alpha:1b"}}
	// Build the rig and fetch the page.
	rig := unloadRig(t, f)
	// Fetch the page.
	_, _, body := get(t, rig.h, http.MethodGet, "/")
	// Exactly one unload form.
	if n := strings.Count(body, `action="/unload"`); n != 1 {
		// Report the difference.
		t.Errorf("unload forms = %d, want 1", n)
	} // end of the count
	// It names the loaded model.
	if !strings.Contains(body, `name="model" value="alpha:1b"`) {
		// Report the problem.
		t.Errorf("the unload form does not name alpha:1b")
	} // end of the name check
	// The button has a name for screen readers that includes the model.
	if !strings.Contains(body, `aria-label="Unload alpha:1b"`) {
		// Report the problem.
		t.Errorf("the unload button has no accessible name")
	} // end of the label check
	// The embedding model is not loaded, so it has no Unload button (it has a Load button instead).
	if strings.Contains(body, `aria-label="Unload embed:1b"`) {
		// Report the problem.
		t.Errorf("a not-loaded model has an unload button")
	} // end of the other check
} // end of TestUnloadButtonOnlyOnLoadedRows

// TestUnloadAskChangesNothing checks the first step shows the warning and sends no unload request.
func TestUnloadAskChangesNothing(t *testing.T) {
	// A fake with one loaded model.
	f := &unloadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := unloadRig(t, f)
	// Ask to unload it.
	res := post(t, rig.h, "/unload", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// It must answer 200.
	if res.StatusCode != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d, want 200", res.StatusCode)
	} // end of the status check
	// Read the page.
	body := bodyOf(res)
	// The warning must be there, saying that Ollama does not report busy.
	for _, want := range []string{"cannot see whether a model is working", "Only continue if you know that nothing is using this model", `action="/unload/confirm"`, "Cancel, keep it loaded"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("confirm page lacks %q", want)
		} // end of the check
	} // end of the loop
	// Nothing may have been sent to Ollama.
	if n := f.callCount(); n != 0 {
		// Report the problem.
		t.Errorf("the first step sent %d unload requests, want 0", n)
	} // end of the call check
	// The model must still be loaded.
	if len(f.loaded) != 1 {
		// Report the problem.
		t.Errorf("the model was unloaded by the first step")
	} // end of the state check
} // end of TestUnloadAskChangesNothing

// TestUnloadConfirmUnloads checks the second step sends exactly one correct request and reports success.
func TestUnloadConfirmUnloads(t *testing.T) {
	// A fake with one loaded model.
	f := &unloadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := unloadRig(t, f)
	// Confirm.
	res := post(t, rig.h, "/unload/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// It must answer 200.
	if res.StatusCode != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d, want 200", res.StatusCode)
	} // end of the status check
	// The page must say it worked.
	if body := bodyOf(res); !strings.Contains(body, "no longer lists this model as loaded") {
		// Report the problem.
		t.Errorf("success message missing: %s", body)
	} // end of the message check
	// Exactly one request, to /api/generate, with keep_alive 0 and the right model.
	if len(f.calls) != 1 || f.calls[0] != `/api/generate {"keep_alive":0,"model":"alpha:1b"}` {
		// Report the problem.
		t.Errorf("unexpected calls: %v", f.calls)
	} // end of the call check
} // end of TestUnloadConfirmUnloads

// TestUnloadEmbeddingFallback checks a model that cannot generate is unloaded through /api/embed.
func TestUnloadEmbeddingFallback(t *testing.T) {
	// A fake whose generate answers 400, with an embedding model loaded.
	f := &unloadFake{loaded: []string{"embed:1b"}, generateStatus: http.StatusBadRequest}
	// Build the rig.
	rig := unloadRig(t, f)
	// Confirm.
	res := post(t, rig.h, "/unload/confirm", url.Values{"token": {rig.token}, "model": {"embed:1b"}}, fromThisPage)
	// It must answer 200 with the success message.
	if body := bodyOf(res); res.StatusCode != http.StatusOK || !strings.Contains(body, "no longer lists this model as loaded") {
		// Report the problem.
		t.Errorf("status %d, body %s", res.StatusCode, body)
	} // end of the check
	// Two requests: generate, then embed with keep_alive 0.
	if len(f.calls) != 2 || !strings.HasPrefix(f.calls[1], "/api/embed ") || !strings.Contains(f.calls[1], `"keep_alive":0`) {
		// Report the problem.
		t.Errorf("unexpected calls: %v", f.calls)
	} // end of the call check
} // end of TestUnloadEmbeddingFallback

// TestUnloadStillLoaded checks the page does not claim success when Ollama accepted the request but the model stays loaded.
func TestUnloadStillLoaded(t *testing.T) {
	// A fake that accepts and ignores unload requests.
	f := &unloadFake{loaded: []string{"alpha:1b"}, ignore: true}
	// Build the rig.
	rig := unloadRig(t, f)
	// Confirm.
	res := post(t, rig.h, "/unload/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// Read the page.
	body := bodyOf(res)
	// It must say the model is still loaded and must not claim success.
	if !strings.Contains(body, "still listed as loaded") || strings.Contains(body, "no longer lists") {
		// Report the problem.
		t.Errorf("wrong message: %s", body)
	} // end of the message check
} // end of TestUnloadStillLoaded

// TestUnloadNotLoaded checks a model that is not loaded is never sent an unload request (requirement S3).
func TestUnloadNotLoaded(t *testing.T) {
	// A fake with nothing loaded.
	f := &unloadFake{}
	// Build the rig.
	rig := unloadRig(t, f)
	// Both steps must refuse politely.
	for _, path := range []string{"/unload", "/unload/confirm"} {
		// Send it.
		res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
		// Read the page.
		body := bodyOf(res)
		// The page says there is nothing to unload and offers no unload form.
		if res.StatusCode != http.StatusOK || !strings.Contains(body, "nothing to unload") || strings.Contains(body, "/unload/confirm") {
			// Report the problem.
			t.Errorf("%s: status %d, body %s", path, res.StatusCode, body)
		} // end of the check
	} // end of the loop
	// Nothing may have been sent to Ollama.
	if n := f.callCount(); n != 0 {
		// Report the problem.
		t.Errorf("%d unload requests were sent for a model that is not loaded", n)
	} // end of the call check
} // end of TestUnloadNotLoaded

// TestUnloadEscapesModelName checks a hostile model name can never become markup.
func TestUnloadEscapesModelName(t *testing.T) {
	// A fake with nothing loaded.
	f := &unloadFake{}
	// Build the rig.
	rig := unloadRig(t, f)
	// Send a name that contains a script tag.
	res := post(t, rig.h, "/unload", url.Values{"token": {rig.token}, "model": {"<script>alert(1)</script>"}}, fromThisPage)
	// Read the page.
	body := bodyOf(res)
	// The tag must be escaped.
	if strings.Contains(body, "<script>") {
		// Report the problem.
		t.Errorf("the model name reached the page unescaped")
	} // end of the escape check
} // end of TestUnloadEscapesModelName

// TestUnloadRefusals checks every way a post can be refused on both routes, and that a refusal never reaches Ollama.
func TestUnloadRefusals(t *testing.T) {
	// A fake with one loaded model.
	f := &unloadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := unloadRig(t, f)
	// A table of cases.
	for _, tc := range []struct {
		// name labels the case.
		name string
		// form is the posted form.
		form url.Values
		// headers are the request headers.
		headers map[string]string
		// want is the expected status.
		want int
	}{ // the cases follow
		// A page on another site posts the form.
		{"cross-site", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, map[string]string{"Sec-Fetch-Site": "cross-site"}, http.StatusForbidden},
		// A script without any browser headers.
		{"no origin headers", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, map[string]string{}, http.StatusForbidden},
		// The right origin but no token.
		{"missing token", url.Values{"model": {"alpha:1b"}}, fromThisPage, http.StatusForbidden},
		// The right origin but a wrong token.
		{"wrong token", url.Values{"token": {strings.Repeat("0", 32)}, "model": {"alpha:1b"}}, fromThisPage, http.StatusForbidden},
		// No model name.
		{"no model", url.Values{"token": {rig.token}}, fromThisPage, http.StatusBadRequest},
		// A model name that is far too long.
		{"model too long", url.Values{"token": {rig.token}, "model": {strings.Repeat("a", 400)}}, fromThisPage, http.StatusBadRequest},
		// A body larger than the 2 KB limit.
		{"too large", url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "junk": {strings.Repeat("x", 5000)}}, fromThisPage, http.StatusBadRequest},
	} { // end of the table
		// Both routes must refuse in the same way.
		for _, path := range []string{"/unload", "/unload/confirm"} {
			// Run each case as a named subtest.
			t.Run(tc.name+" "+path, func(t *testing.T) {
				// Send it.
				res := post(t, rig.h, path, tc.form, tc.headers)
				// Compare the status.
				if res.StatusCode != tc.want {
					// Report the difference.
					t.Errorf("status %d, want %d", res.StatusCode, tc.want)
				} // end of the status check
			}) // end of the subtest
		} // end of the route loop
	} // end of the table loop
	// No refusal may have reached Ollama, and the model must still be loaded.
	if n := f.callCount(); n != 0 || len(f.loaded) != 1 {
		// Report the problem.
		t.Errorf("a refused request had an effect: %d calls, %d loaded", n, len(f.loaded))
	} // end of the effect check
} // end of TestUnloadRefusals

// TestUnloadRoutesNeedPost checks the unload addresses accept only POST, so a link or an image tag can never trigger them.
func TestUnloadRoutesNeedPost(t *testing.T) {
	// A fake with one loaded model.
	f := &unloadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := unloadRig(t, f)
	// Both addresses.
	for _, path := range []string{"/unload", "/unload/confirm"} {
		// A GET must be refused with 405.
		if status, _, _ := get(t, rig.h, http.MethodGet, path+"?model=alpha:1b"); status != http.StatusMethodNotAllowed {
			// Report the problem.
			t.Errorf("GET %s = %d, want 405", path, status)
		} // end of the check
	} // end of the loop
} // end of TestUnloadRoutesNeedPost

// TestUnloadOllamaDown checks a clear error page when Ollama cannot be read.
func TestUnloadOllamaDown(t *testing.T) {
	// A fake that works for the first page and is then closed.
	f := &unloadFake{loaded: []string{"alpha:1b"}}
	// Start it by hand so it can be closed.
	srv := f.start(t)
	// Build the handler and read the token.
	h := handlerFor(t, srv.URL)
	// Fetch the page.
	_, _, body := get(t, h, http.MethodGet, "/")
	// Find the token.
	token := regexp.MustCompile(`name="token" value="([0-9a-f]{32})"`).FindStringSubmatch(body)[1]
	// Close the fake: Ollama is now unreachable.
	srv.Close()
	// Ask to unload.
	res := post(t, h, "/unload", url.Values{"token": {token}, "model": {"alpha:1b"}}, fromThisPage)
	// It must be a 502 with a message and without the address.
	if b := bodyOf(res); res.StatusCode != http.StatusBadGateway || !strings.Contains(b, "Could not do this") || strings.Contains(b, srv.URL) {
		// Report the problem.
		t.Errorf("status %d, body %s", res.StatusCode, b)
	} // end of the check
} // end of TestUnloadOllamaDown

// TestUnloadStyles checks the stylesheet has the button rules in both themes.
func TestUnloadStyles(t *testing.T) {
	// The stylesheet text.
	css := string(appCSS)
	// Each of these protects one behaviour.
	for name, want := range map[string]string{
		// The outlined button.
		"unload button": ".unload {",
		// It fills on hover.
		"unload hover": ".unload:hover",
		// Light colour.
		"light button colour": "--btn: #b3261e",
		// Dark colour.
		"dark button colour": "--btn: #ff8a80",
		// A visible keyboard focus.
		"focus ring": ".unload:focus-visible",
	} { // end of the map
		// Look for it.
		if !strings.Contains(css, want) {
			// Report the gap.
			t.Errorf("stylesheet lacks %s (%q)", name, want)
		} // end of the check
	} // end of the loop
} // end of TestUnloadStyles

// TestRemainingText checks the three kinds of "time left" wording.
func TestRemainingText(t *testing.T) {
	// A fixed "now" keeps the test steady.
	now := time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)
	// A table of cases.
	for _, tc := range []struct {
		// name labels the case.
		name string
		// expires is the reported unload time.
		expires time.Time
		// ok says whether a time was reported.
		ok bool
		// want is the expected text.
		want string
	}{ // the cases follow
		// A normal countdown.
		{"soon", now.Add(4*time.Minute + 30*time.Second), true, "4 min 30 s"},
		// A model set to stay loaded forever reports a date centuries away.
		{"forever", time.Date(2318, 1, 1, 0, 0, 0, 0, time.UTC), true, "never on its own (it is set to stay loaded)"},
		// No time reported.
		{"unknown", time.Time{}, false, "not reported"},
	} { // end of the table
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Compare.
			if got := remainingText(now, tc.expires, tc.ok); got != tc.want {
				// Report the difference.
				t.Errorf("got %q, want %q", got, tc.want)
			} // end of the compare
		}) // end of the subtest
	} // end of the loop
} // end of TestRemainingText
