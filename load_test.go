// Package main tells Go that this test file belongs to the same program as load.go, memory.go and countdown.go.
package main

import ( // import lists the packages this test file uses.
	// errors builds a fake memory failure.
	"errors"
	// io reads request bodies in the fake Ollama.
	"io"
	// net/http provides requests and status codes.
	"net/http"
	// net/http/httptest records replies and runs the fake Ollama.
	"net/http/httptest"
	// net/url builds form data and parsed addresses.
	"net/url"
	// regexp finds the token in the page.
	"regexp"
	// strings searches the page text.
	"strings"
	// sync protects the fake's records, because the server runs in its own goroutine.
	"sync"
	// testing is Go's built-in test framework.
	"testing"
	// time shortens the waiting time in the tests and builds times.
	"time"
) // end of imports

// loadFake is a fake Ollama that remembers what it was asked and can pretend to load and unload models.
type loadFake struct {
	// mu protects every field below.
	mu sync.Mutex
	// loaded is the list of names that /api/ps reports.
	loaded []string
	// calls records "path body" for every POST.
	calls []string
	// generateStatus is the status that /api/generate answers (200 unless a test changes it).
	generateStatus int
	// ignore makes the fake accept load requests without actually loading.
	ignore bool
} // end of loadFake

// start runs the fake as a server and returns it.
func (f *loadFake) start(t *testing.T) *httptest.Server {
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
		// The installed list: a 3.3 GB chat model and a 2 GB embedding model.
		case "/api/tags":
			// Two models.
			w.Write([]byte(`{"models":[{"name":"alpha:1b","size":3300000000,"details":{"family":"llama"},"capabilities":["completion"]},{"name":"embed:1b","size":2000000000,"details":{"family":"bert"},"capabilities":["embedding"]}]}`))
		// The loaded list.
		case "/api/ps":
			// Build the list from the fake's state.
			parts := []string{}
			// Five minutes from now, the way a default load reports it.
			exp := time.Now().Add(5 * time.Minute).UTC().Format(time.RFC3339)
			// Every loaded name.
			for _, n := range f.loaded {
				// One entry.
				parts = append(parts, `{"name":"`+n+`","size":5,"expires_at":"`+exp+`"}`)
			} // end of the loop
			// Send the list.
			w.Write([]byte(`{"models":[` + strings.Join(parts, ",") + `]}`))
		// The load and unload requests.
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
			// Every request except a keep_alive of 0 loads; the model name is between the quotes after "model":.
			if !f.ignore && !strings.Contains(string(b), `"keep_alive":0`) {
				// Take the name out of the body.
				name := regexp.MustCompile(`"model":"([^"]*)"`).FindStringSubmatch(string(b))[1]
				// Add it to the loaded list.
				f.loaded = append(f.loaded, name)
			} // end of the load
			// Accept.
			w.Write([]byte(`{}`))
		// Anything else.
		default:
			// Not found.
			http.NotFound(w, r)
		} // end of the switch
	}) // end of the server
} // end of start

// callCount says how many load or unload requests the fake has received.
func (f *loadFake) callCount() int {
	// One at a time.
	f.mu.Lock()
	// Release at the end.
	defer f.mu.Unlock()
	// The number.
	return len(f.calls)
} // end of callCount

// loadRig builds a handler on top of the fake, fixes the free memory to the given value (a negative value means "cannot be read") and finds the page token.
func loadRig(t *testing.T, f *loadFake, avail int64) themeRig {
	// Mark this as a helper.
	t.Helper()
	// Keep the old settings and restore them afterwards.
	oldWait, oldMem := loadVerifyWait, availableMemoryFunc
	// Restore at the end.
	t.Cleanup(func() { loadVerifyWait, availableMemoryFunc = oldWait, oldMem })
	// Short waiting, so the tests stay quick.
	loadVerifyWait = 500 * time.Millisecond
	// The pretend memory reading.
	availableMemoryFunc = func() (int64, error) {
		// A negative value means the memory cannot be read.
		if avail < 0 {
			// A fixed message.
			return 0, errors.New("this system does not report its free memory")
		} // end of the failure case
		// The pretend value.
		return avail, nil
	} // end of the pretend reading
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
} // end of loadRig

// TestLoadButtonOnlyOnNotLoadedRows checks the Load button appears for the not-loaded model and not for the loaded one.
func TestLoadButtonOnlyOnNotLoadedRows(t *testing.T) {
	// One model loaded, one not.
	f := &loadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Fetch the page.
	_, _, body := get(t, rig.h, http.MethodGet, "/")
	// Exactly one load form, for the embedding model.
	if n := strings.Count(body, `action="/load"`); n != 1 {
		// Report the difference.
		t.Errorf("load forms = %d, want 1", n)
	} // end of the count
	// It names the right model and has an accessible name.
	for _, want := range []string{`name="model" value="embed:1b"`, `aria-label="Load embed:1b"`, `class="load"`} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("page lacks %q", want)
		} // end of the check
	} // end of the loop
	// The loaded model has an Unload button and no Load button.
	if strings.Contains(body, `aria-label="Load alpha:1b"`) {
		// Report the problem.
		t.Errorf("a loaded model has a Load button")
	} // end of the other check
	// The main page may load the monitor's own script file and nothing else: exactly one script tag, with no inline code.
	if n := strings.Count(body, "<script"); n != 1 || !strings.Contains(body, `<script src="/countdown.js" defer></script>`) {
		// Report the problem.
		t.Errorf("the main page has %d script tags, want only the countdown.js one", n)
	} // end of the script check
} // end of TestLoadButtonOnlyOnNotLoadedRows

// TestLoadAskShowsMemoryAndChangesNothing checks the first step shows the figures and sends no load request.
func TestLoadAskShowsMemoryAndChangesNothing(t *testing.T) {
	// Nothing loaded.
	f := &loadFake{}
	// Plenty of memory: 16 GB free.
	rig := loadRig(t, f, 16e9)
	// Ask to load the 3.3 GB model.
	res := post(t, rig.h, "/load", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// It must answer 200.
	if res.StatusCode != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d, want 200", res.StatusCode)
	} // end of the status check
	// Read the page.
	body := bodyOf(res)
	// The figures and the default time must be there.
	for _, want := range []string{"16.0 GB", "3.3 GB", "Ollama's default is 5 minutes", `action="/load/confirm"`, "Cancel, do not load"} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("confirm page lacks %q", want)
		} // end of the check
	} // end of the loop
	// With plenty of memory there is no warning.
	if strings.Contains(body, "⚠") {
		// Report the problem.
		t.Errorf("a warning was shown although memory is plentiful")
	} // end of the warning check
	// This page runs only the monitor's own waiting script: no inline code and no unsafe-inline rule (the new loading tests check the rest).
	if strings.Contains(body, "<script>") || strings.Contains(res.Header.Get("Content-Security-Policy"), "unsafe-inline") {
		// Report the problem.
		t.Errorf("the load warning page allows or contains inline script")
	} // end of the script check
	// Nothing may have been sent to Ollama.
	if n := f.callCount(); n != 0 || len(f.loaded) != 0 {
		// Report the problem.
		t.Errorf("the first step had an effect: %d calls, %d loaded", n, len(f.loaded))
	} // end of the effect check
} // end of TestLoadAskShowsMemoryAndChangesNothing

// TestLoadMemoryWarnings checks the three memory situations and the unknown case.
func TestLoadMemoryWarnings(t *testing.T) {
	// A table of free memory, expected words that must appear and words that must not.
	for _, tc := range []struct {
		// name labels the case.
		name string
		// avail is the pretend free memory in bytes; negative means unreadable.
		avail int64
		// want is text that must appear.
		want string
		// not is text that must not appear.
		not string
	}{ // the cases follow
		// Less free memory than the model's size.
		{"short", 1e9, "Not enough free memory", "close to what"},
		// Between the model's size and 1.25 times that.
		{"tight", 3.5e9, "Free memory is close to what this model needs", "Not enough free memory"},
		// Plenty.
		{"plenty", 20e9, "20.0 GB", "⚠"},
		// Unreadable memory is said plainly and not guessed.
		{"unknown", -1, "not known (this system does not report its free memory)", "⚠"},
	} { // end of the table
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Nothing loaded.
			f := &loadFake{}
			// Build the rig with the pretend memory.
			rig := loadRig(t, f, tc.avail)
			// Ask.
			res := post(t, rig.h, "/load", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
			// Read the page.
			body := bodyOf(res)
			// The wanted text.
			if !strings.Contains(body, tc.want) {
				// Report the problem.
				t.Errorf("page lacks %q", tc.want)
			} // end of the want check
			// The unwanted text.
			if strings.Contains(body, tc.not) {
				// Report the problem.
				t.Errorf("page contains %q", tc.not)
			} // end of the not check
			// The Yes button is always offered: the person decides.
			if !strings.Contains(body, "Yes, load it now") {
				// Report the problem.
				t.Errorf("the Yes button is missing")
			} // end of the button check
		}) // end of the subtest
	} // end of the loop
} // end of TestLoadMemoryWarnings

// TestLoadConfirmLoads checks the second step sends exactly one load request without a keep-alive and shows the live timer.
func TestLoadConfirmLoads(t *testing.T) {
	// Nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Confirm.
	res := post(t, rig.h, "/load/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// It must answer 200.
	if res.StatusCode != http.StatusOK {
		// Stop the test.
		t.Fatalf("status %d, want 200", res.StatusCode)
	} // end of the status check
	// Read the page.
	body := bodyOf(res)
	// The page says it worked, has a ticking timer and the script.
	for _, want := range []string{"Ollama lists this model as loaded", `class="countdown" data-seconds="`, `<script src="/countdown.js" defer></script>`} {
		// Look for it.
		if !strings.Contains(body, want) {
			// Report the problem.
			t.Errorf("done page lacks %q", want)
		} // end of the check
	} // end of the loop
	// The policy allows the script from this address only, and no inline scripts.
	if csp := res.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe-inline") {
		// Report the problem.
		t.Errorf("unexpected policy: %s", csp)
	} // end of the policy check
	// Exactly one request: generate with only the model (no keep_alive, so Ollama's default applies).
	if len(f.calls) != 1 || f.calls[0] != `/api/generate {"model":"alpha:1b"}` {
		// Report the problem.
		t.Errorf("unexpected calls: %v", f.calls)
	} // end of the call check
} // end of TestLoadConfirmLoads

// TestLoadEmbeddingFallback checks a model that cannot generate is loaded through /api/embed, again without a keep-alive.
func TestLoadEmbeddingFallback(t *testing.T) {
	// A fake whose generate answers 400.
	f := &loadFake{generateStatus: http.StatusBadRequest}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Confirm.
	res := post(t, rig.h, "/load/confirm", url.Values{"token": {rig.token}, "model": {"embed:1b"}}, fromThisPage)
	// It must say it worked.
	if body := bodyOf(res); res.StatusCode != http.StatusOK || !strings.Contains(body, "Ollama lists this model as loaded") {
		// Report the problem.
		t.Errorf("status %d, body %s", res.StatusCode, body)
	} // end of the check
	// Two requests: generate, then embed, and neither carries keep_alive.
	if len(f.calls) != 2 || !strings.HasPrefix(f.calls[1], "/api/embed ") || strings.Contains(f.calls[0]+f.calls[1], "keep_alive") {
		// Report the problem.
		t.Errorf("unexpected calls: %v", f.calls)
	} // end of the call check
} // end of TestLoadEmbeddingFallback

// TestLoadStillNotLoaded checks the page does not claim success when the model never appears.
func TestLoadStillNotLoaded(t *testing.T) {
	// A fake that accepts and ignores load requests.
	f := &loadFake{ignore: true}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Confirm.
	res := post(t, rig.h, "/load/confirm", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// Read the page.
	body := bodyOf(res)
	// It must say the model is not listed and must not claim success.
	if !strings.Contains(body, "Not listed yet") || strings.Contains(body, "Ollama lists this model as loaded") {
		// Report the problem.
		t.Errorf("wrong message: %s", body)
	} // end of the message check
} // end of TestLoadStillNotLoaded

// TestLoadRefusesWrongModels checks a loaded model and an unknown model are never sent a load request.
func TestLoadRefusesWrongModels(t *testing.T) {
	// One model loaded.
	f := &loadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// A table of model, expected words.
	for _, tc := range []struct {
		// model is the posted name.
		model string
		// want is the text that must appear.
		want string
	}{ // the cases follow
		// Already loaded.
		{"alpha:1b", "already loaded"},
		// Not installed.
		{"ghost:1", "not installed"},
	} { // end of the table
		// Both steps must refuse politely.
		for _, path := range []string{"/load", "/load/confirm"} {
			// Send it.
			res := post(t, rig.h, path, url.Values{"token": {rig.token}, "model": {tc.model}}, fromThisPage)
			// Read the page.
			body := bodyOf(res)
			// The page explains and offers no Yes form.
			if res.StatusCode != http.StatusOK || !strings.Contains(body, tc.want) || strings.Contains(body, "/load/confirm") {
				// Report the problem.
				t.Errorf("%s %s: status %d, body %s", path, tc.model, res.StatusCode, body)
			} // end of the check
		} // end of the path loop
	} // end of the table loop
	// Nothing may have been sent to Ollama.
	if n := f.callCount(); n != 0 {
		// Report the problem.
		t.Errorf("%d requests were sent for models that must not be loaded", n)
	} // end of the call check
} // end of TestLoadRefusesWrongModels

// TestLoadEscapesModelName checks a hostile model name can never become markup.
func TestLoadEscapesModelName(t *testing.T) {
	// Nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Send a name that contains a script tag.
	res := post(t, rig.h, "/load", url.Values{"token": {rig.token}, "model": {"<script>alert(1)</script>"}}, fromThisPage)
	// The tag must be escaped.
	if strings.Contains(bodyOf(res), "<script>") {
		// Report the problem.
		t.Errorf("the model name reached the page unescaped")
	} // end of the escape check
} // end of TestLoadEscapesModelName

// TestLoadPostRefusals checks every way a post can be refused on both load routes, and that a refusal never reaches Ollama.
func TestLoadPostRefusals(t *testing.T) {
	// Nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
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
		// A body larger than the 2 KB limit.
		{"too large", url.Values{"token": {rig.token}, "model": {"alpha:1b"}, "junk": {strings.Repeat("x", 5000)}}, fromThisPage, http.StatusBadRequest},
	} { // end of the table
		// Both routes must refuse in the same way.
		for _, path := range []string{"/load", "/load/confirm"} {
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
	// No refusal may have reached Ollama.
	if n := f.callCount(); n != 0 {
		// Report the problem.
		t.Errorf("a refused request reached Ollama: %d calls", n)
	} // end of the effect check
	// A GET must be refused on both routes.
	for _, path := range []string{"/load", "/load/confirm"} {
		// Check the method.
		if status, _, _ := get(t, rig.h, http.MethodGet, path); status != http.StatusMethodNotAllowed {
			// Report the problem.
			t.Errorf("GET %s = %d, want 405", path, status)
		} // end of the check
	} // end of the method loop
} // end of TestLoadPostRefusals

// TestLoadOllamaDown checks a clear error page when Ollama cannot be read.
func TestLoadOllamaDown(t *testing.T) {
	// A fake that works for the first page and is then closed.
	f := &loadFake{}
	// Keep the old settings and restore them afterwards.
	oldMem := availableMemoryFunc
	// Restore at the end.
	t.Cleanup(func() { availableMemoryFunc = oldMem })
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
	// Ask to load.
	res := post(t, h, "/load", url.Values{"token": {token}, "model": {"alpha:1b"}}, fromThisPage)
	// It must be a 502 with a message and without the address.
	if b := bodyOf(res); res.StatusCode != http.StatusBadGateway || !strings.Contains(b, "Could not do this") || strings.Contains(b, srv.URL) {
		// Report the problem.
		t.Errorf("status %d, body %s", res.StatusCode, b)
	} // end of the check
} // end of TestLoadOllamaDown

// TestUnloadWarningHasLiveTimer checks the unload warning page now carries the ticking timer, the script and the relaxed policy.
func TestUnloadWarningHasLiveTimer(t *testing.T) {
	// One model loaded, reported as unloading in five minutes.
	f := &loadFake{loaded: []string{"alpha:1b"}}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Ask to unload.
	res := post(t, rig.h, "/unload", url.Values{"token": {rig.token}, "model": {"alpha:1b"}}, fromThisPage)
	// Read the page.
	body := bodyOf(res)
	// A ticking timer with its starting seconds, and the script.
	if m := regexp.MustCompile(`class="countdown" data-seconds="(\d+)"`).FindStringSubmatch(body); m == nil || !strings.Contains(body, `<script src="/countdown.js" defer></script>`) {
		// Report the problem.
		t.Errorf("no ticking timer or script in: %s", body)
	} // end of the timer check
	// The policy allows only the monitor's own script.
	if csp := res.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "script-src 'self'") || strings.Contains(csp, "unsafe-inline") {
		// Report the problem.
		t.Errorf("unexpected policy: %s", csp)
	} // end of the policy check
} // end of TestUnloadWarningHasLiveTimer

// TestMainPolicyAllowsOnlyOwnScript checks the main page policy allows the monitor's own script and requests to its own address, and nothing inline or from elsewhere.
func TestMainPolicyAllowsOnlyOwnScript(t *testing.T) {
	// A fake with nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Fetch the page and its headers.
	_, header, _ := get(t, rig.h, http.MethodGet, "/")
	// The policy as sent.
	csp := header.Get("Content-Security-Policy")
	// It must allow scripts and requests from this address only.
	for _, want := range []string{"default-src 'none'", "script-src 'self'", "connect-src 'self'"} {
		// Look for it.
		if !strings.Contains(csp, want) {
			// Report the problem.
			t.Errorf("the main page policy lacks %q: %s", want, csp)
		} // end of the check
	} // end of the loop
	// It must never allow inline code or code from other sites.
	for _, bad := range []string{"unsafe-inline", "unsafe-eval", "http:", "https:", "*"} {
		// Look for it.
		if strings.Contains(csp, bad) {
			// Report the problem.
			t.Errorf("the main page policy contains %q: %s", bad, csp)
		} // end of the check
	} // end of the loop
} // end of TestMainPolicyAllowsOnlyOwnScript

// TestCountdownScriptIsServed checks the script file is sent as JavaScript.
func TestCountdownScriptIsServed(t *testing.T) {
	// A fake with nothing loaded.
	f := &loadFake{}
	// Build the rig.
	rig := loadRig(t, f, 16e9)
	// Fetch the script.
	status, header, body := get(t, rig.h, http.MethodGet, "/countdown.js")
	// It must be found, typed as JavaScript, and be the countdown.
	if status != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/javascript") || !strings.Contains(body, "setInterval") {
		// Report the problem.
		t.Errorf("status %d, type %q", status, header.Get("Content-Type"))
	} // end of the check
} // end of TestCountdownScriptIsServed

// TestRemainingSeconds checks which times get a ticking timer.
func TestRemainingSeconds(t *testing.T) {
	// A fixed "now".
	now := time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)
	// A table of cases.
	for _, tc := range []struct {
		// name labels the case.
		name string
		// expires is the reported unload time.
		expires time.Time
		// ok says whether a time was reported.
		ok bool
		// want is the expected number of seconds.
		want int
	}{ // the cases follow
		// Four and a half minutes left.
		{"soon", now.Add(270 * time.Second), true, 270},
		// Already past.
		{"past", now.Add(-time.Second), true, 0},
		// A model set to stay loaded reports a date centuries away.
		{"forever", time.Date(2318, 1, 1, 0, 0, 0, 0, time.UTC), true, 0},
		// No time reported.
		{"unknown", time.Time{}, false, 0},
	} { // end of the table
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Compare.
			if got := remainingSeconds(now, tc.expires, tc.ok); got != tc.want {
				// Report the difference.
				t.Errorf("got %d, want %d", got, tc.want)
			} // end of the compare
		}) // end of the subtest
	} // end of the loop
} // end of TestRemainingSeconds

// TestParseMemAvailable checks the reading of /proc/meminfo.
func TestParseMemAvailable(t *testing.T) {
	// A table of file texts and expected results.
	for _, tc := range []struct {
		// name labels the case.
		name string
		// text is the file content.
		text string
		// want is the expected number of bytes.
		want int64
		// ok says whether a value is expected.
		ok bool
	}{ // the cases follow
		// A normal file: 1000 kB are 1,024,000 bytes.
		{"normal", "MemTotal:  2000 kB\nMemFree:   500 kB\nMemAvailable:   1000 kB\n", 1024000, true},
		// The line is missing.
		{"missing", "MemTotal: 2000 kB\n", 0, false},
		// A different unit.
		{"unit", "MemAvailable: 1000 MB\n", 0, false},
		// Not a number.
		{"garbage", "MemAvailable: lots kB\n", 0, false},
		// A negative number.
		{"negative", "MemAvailable: -5 kB\n", 0, false},
		// Empty.
		{"empty", "", 0, false},
	} { // end of the table
		// Run each case as a named subtest.
		t.Run(tc.name, func(t *testing.T) {
			// Parse.
			got, ok := parseMemAvailable(tc.text)
			// Compare.
			if got != tc.want || ok != tc.ok {
				// Report the difference.
				t.Errorf("got %d, %v; want %d, %v", got, ok, tc.want, tc.ok)
			} // end of the compare
		}) // end of the subtest
	} // end of the loop
} // end of TestParseMemAvailable

// TestOllamaIsLocal checks which addresses count as this same computer.
func TestOllamaIsLocal(t *testing.T) {
	// A table of addresses and expected answers.
	for addr, want := range map[string]bool{
		// The usual local addresses.
		"http://127.0.0.1:11434": true, "http://localhost:11434": true, "http://[::1]:11434": true,
		// Other computers, by name and by number.
		"http://spark-5f81:11434": false, "http://192.168.1.20:11434": false, "https://ollama.example.com": false,
	} { // end of the table
		// Parse it.
		u, err := url.Parse(addr)
		// A bad test address.
		if err != nil {
			// Stop the test.
			t.Fatalf("bad address %q", addr)
		} // end of the parse check
		// Compare.
		if got := ollamaIsLocal(u); got != want {
			// Report the difference.
			t.Errorf("%s: got %v, want %v", addr, got, want)
		} // end of the compare
	} // end of the loop
} // end of TestOllamaIsLocal

// TestMemoryLevel checks the thresholds.
func TestMemoryLevel(t *testing.T) {
	// A table of free memory, model size and expected level.
	for _, tc := range []struct {
		// avail is the free memory.
		avail int64
		// need is the model size.
		need int64
		// want is the expected level.
		want string
	}{ // the cases follow
		// Less than the model.
		{99, 100, "short"},
		// Exactly the model: not short, but tight.
		{100, 100, "tight"},
		// Just below 1.25 times.
		{124, 100, "tight"},
		// Exactly 1.25 times and more.
		{125, 100, ""}, {1000, 100, ""},
	} { // end of the table
		// Compare.
		if got := memoryLevel(tc.avail, tc.need); got != tc.want {
			// Report the difference.
			t.Errorf("memoryLevel(%d, %d) = %q, want %q", tc.avail, tc.need, got, tc.want)
		} // end of the compare
	} // end of the loop
} // end of TestMemoryLevel

// TestLoadStyles checks the stylesheet has the Load button rules in both themes.
func TestLoadStyles(t *testing.T) {
	// The stylesheet text.
	css := string(appCSS)
	// Each of these protects one behaviour.
	for name, want := range map[string]string{
		// The outlined button.
		"load button": ".load {",
		// It fills on hover.
		"load hover": ".load:hover",
		// Light colour.
		"light load colour": "--load: #0b57d0",
		// Dark colour.
		"dark load colour": "--load: #8ab4f8",
		// The memory warning has a marker that is not only colour.
		"warning box": ".warn {",
		// The facts table.
		"facts table": ".facts {",
	} { // end of the map
		// Look for it.
		if !strings.Contains(css, want) {
			// Report the gap.
			t.Errorf("stylesheet lacks %s (%q)", name, want)
		} // end of the check
	} // end of the loop
} // end of TestLoadStyles

// TestMemoryFacts checks the three ways the free memory can be reported, including Ollama on another computer.
func TestMemoryFacts(t *testing.T) {
	// Keep the old reading and restore it afterwards.
	old := availableMemoryFunc
	// Restore at the end.
	t.Cleanup(func() { availableMemoryFunc = old })
	// A reading that always says 10 GB.
	availableMemoryFunc = func() (int64, error) { return 10e9, nil }
	// Parse a local and a remote address.
	local, _ := url.Parse("http://127.0.0.1:11434")
	// The remote one.
	remote, _ := url.Parse("http://spark-5f81:11434")
	// Local: the figure is shown and compared with the need.
	if avail, note, level := memoryFacts(local, 3e9); avail != "10.0 GB" || note != "" || level != "" {
		// Report the problem.
		t.Errorf("local: %q %q %q", avail, note, level)
	} // end of the local check
	// Local and short.
	if _, _, level := memoryFacts(local, 20e9); level != "short" {
		// Report the problem.
		t.Errorf("local short: level %q", level)
	} // end of the short check
	// Remote: no figure, with the reason, and no warning level (the 10 GB must not be used).
	if avail, note, level := memoryFacts(remote, 3e9); avail != "" || !strings.Contains(note, "another computer") || level != "" {
		// Report the problem.
		t.Errorf("remote: %q %q %q", avail, note, level)
	} // end of the remote check
	// A reading that fails.
	availableMemoryFunc = func() (int64, error) { return 0, errors.New("no reading") }
	// Local but unreadable: the reason is passed on.
	if avail, note, _ := memoryFacts(local, 3e9); avail != "" || note != "no reading" {
		// Report the problem.
		t.Errorf("unreadable: %q %q", avail, note)
	} // end of the unreadable check
} // end of TestMemoryFacts
